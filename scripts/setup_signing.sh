#!/usr/bin/env bash
# 一次性生成发布签名证书，并输出要写进 GitHub Secrets 的 4 个值。
#
# 用法（Git Bash / macOS / Linux 均可）：
#   bash scripts/setup_signing.sh
#
# 默认只「打印」命令，不向 GitHub 写任何东西，也不回显私钥内容。
# 确认无误后把打印出来的 4 条命令复制执行即可。
# 若已安装并登录 gh，加 --apply 可由脚本直接写入仓库 Secrets：
#   bash scripts/setup_signing.sh --apply
#
# 生成物（均已加入 .gitignore，切勿提交）：
#   dist/release.jks          签名私钥；丢了就永远无法给老用户升级
#   dist/keystore.base64      同一文件的 base64 文本，供 gh secret set 读取
#   dist/signing-secrets.txt  4 个 Secret 的明文值，方便网页方式逐个复制
#
# 可选环境变量：
#   REPO      目标仓库，默认 Lightconer/qingyang-watermark-camera
#   KEYTOOL   手动指定 keytool 路径（自动探测不到时用）
#   ALIAS     key 别名，默认 qingyang
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REPO="${REPO:-Lightconer/qingyang-watermark-camera}"
ALIAS="${ALIAS:-qingyang}"
APPLY=0
if [ "${1:-}" = "--apply" ]; then APPLY=1; fi

DIST="$ROOT_DIR/dist"
JKS="$DIST/release.jks"
B64_FILE="$DIST/keystore.base64"
VALUES="$DIST/signing-secrets.txt"

mkdir -p "$DIST"
if [ -f "$JKS" ]; then
  echo "[setup] ⚠ 已存在 $JKS" >&2
  echo "[setup] 复用已有证书才能给老用户连续升级。确认要重新生成的话，先手动删除该文件。" >&2
  echo "[setup] 若只是忘了 Secret 的值，请改备份里的 signing-secrets.txt。" >&2
  exit 1
fi

# ---------------------------------------------------------------- 1. 找 keytool
find_keytool() {
  if [ -n "${KEYTOOL:-}" ] && [ -x "$KEYTOOL" ]; then
    echo "$KEYTOOL"; return 0
  fi
  if command -v keytool >/dev/null 2>&1; then
    command -v keytool; return 0
  fi
  local candidates=(
    "${JAVA_HOME:-}/bin/keytool"
    "${JAVA_HOME:-}/bin/keytool.exe"
    "/c/Program Files/Android/Android Studio/jbr/bin/keytool.exe"
    "/c/Program Files/Android/Android Studio1/jbr/bin/keytool.exe"
    "/c/Program Files/Eclipse Adoptium/jdk-17/bin/keytool.exe"
    "/c/Program Files/Java/jdk-17/bin/keytool.exe"
    "/c/Program Files/Java/jdk-21/bin/keytool.exe"
    "$HOME/.gradle/jdks"/*/bin/keytool
  )
  local p
  for p in "${candidates[@]}"; do
    if [ -x "$p" ]; then echo "$p"; return 0; fi
  done
  return 1
}

KEYTOOL_BIN="$(find_keytool || true)"
if [ -z "$KEYTOOL_BIN" ]; then
  cat >&2 <<'HINT'
[setup] 没找到 keytool，三选一：
  1) 安装 JDK 17（Temurin）：https://adoptium.net/ ，装完重开 Git Bash 再跑本脚本；
  2) 已装 Android Studio：直接指定自带 JBR，例如
       KEYTOOL="/c/Program Files/Android/Android Studio/jbr/bin/keytool.exe" bash scripts/setup_signing.sh
  3) 其他 JDK：KEYTOOL=/path/to/keytool bash scripts/setup_signing.sh
HINT
  exit 1
fi
echo "[setup] keytool: $KEYTOOL_BIN"

# ---------------------------------------------------------------- 2. 随机口令
# 纯字母数字，避免特殊字符被 key.properties / shell 二次解释。
rand_pass() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "import secrets,string; print(''.join(secrets.choice(string.ascii_letters+string.digits) for _ in range(32)))"
  elif command -v python >/dev/null 2>&1; then
    python -c "import secrets,string; print(''.join(secrets.choice(string.ascii_letters+string.digits) for _ in range(32)))"
  else
    # 末位兜底：仍然随机，但强度不如上面两种，建议装 openssl 后重跑。
    echo "qingyang${RANDOM}${RANDOM}${RANDOM}${RANDOM}"
  fi
}
PASS="$(rand_pass)"

# ---------------------------------------------------------------- 3. 生成证书
# 用 PKCS12（JDK 9+ 默认）。文件名沿用 release.jks 是为了对齐 bootstrap_android.sh
# 的既有路径；apksigner 按内容识别 keystore 类型，不看扩展名。
"$KEYTOOL_BIN" -genkeypair -v \
  -keystore "$JKS" \
  -alias "$ALIAS" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storetype PKCS12 \
  -storepass "$PASS" -keypass "$PASS" \
  -dname "CN=Qingyang Watermark Camera, OU=Engineering, O=Qingyang, L=Hangzhou, ST=Zhejiang, C=CN" \
  >/dev/null 2>&1 || {
    echo "[setup] keytool 生成失败，请把上面的输出打开排查（去掉 >/dev/null 2>&1）" >&2
    rm -f "$JKS"
    exit 1
  }

# base64 单行输出：-w0 在 macOS 不存在，统一走 tr 去换行最稳。
# 文件末尾不能留换行：gh secret set < file 会把换行一起当成值的末尾，
# 部分解码器虽能容忍，但没必要冒这个险。
base64 < "$JKS" | tr -d '\n' > "$B64_FILE"

cat > "$VALUES" <<EOF
# 本地生成于 $(date '+%Y-%m-%d %H:%M:%S')。此文件含私钥口令，切勿提交。
# 到 GitHub 仓库 → Settings → Secrets and variables → Actions → New repository secret 逐个添加。
KEYSTORE_BASE64=$(cat "$B64_FILE")
KEYSTORE_PASSWORD=$PASS
KEY_ALIAS=$ALIAS
KEY_PASSWORD=$PASS
EOF
chmod 600 "$JKS" "$B64_FILE" "$VALUES" 2>/dev/null || true

# ---------------------------------------------------------------- 4. 打印命令
echo
echo "[setup] 证书已生成：$JKS"
echo "[setup] 4 个 Secret 的明文值在：$VALUES（网页方式逐个复制）"
echo
echo "复制执行下面 4 条命令（gh 已登录时可用）："
echo
echo "  gh secret set KEYSTORE_BASE64   -R \"$REPO\" < \"$B64_FILE\""
echo "  gh secret set KEYSTORE_PASSWORD -R \"$REPO\" --body \"$PASS\""
echo "  gh secret set KEY_ALIAS         -R \"$REPO\" --body \"$ALIAS\""
echo "  gh secret set KEY_PASSWORD     -R \"$REPO\" --body \"$PASS\""
echo
echo "如果没装 gh，打开 $VALUES，把等号右边的值逐个粘到网页的 New repository secret。"
echo
echo "验证：gh secret list -R \"$REPO\"  应能看到这 4 个名字。"
echo
echo "⚠ 装完 Secret 后要重新打 tag 发版，签名才会换成正式证书。"
echo "⚠ 已安装 v1.4.0（调试证书签名）的设备仍需卸载重装一次，之后升级才连续。"
echo "⚠ 请另外离线备份 release.jks 与 signing-secrets.txt；私钥丢了无法补。"

# ---------------------------------------------------------------- 5. 可选直接写入
if [ "$APPLY" -eq 1 ]; then
  if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
    echo "[setup] --apply 需要已安装且已登录的 gh（先跑 gh auth login）" >&2
    exit 1
  fi
  gh secret set KEYSTORE_BASE64   -R "$REPO" < "$B64_FILE"
  gh secret set KEYSTORE_PASSWORD -R "$REPO" --body "$PASS"
  gh secret set KEY_ALIAS         -R "$REPO" --body "$ALIAS"
  gh secret set KEY_PASSWORD     -R "$REPO" --body "$PASS"
  echo "[setup] 已写入 $REPO 的 4 个 Secret。"
fi
