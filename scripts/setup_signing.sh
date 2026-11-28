#!/usr/bin/env bash
# 一次性生成发布签名证书，并输出要写进 GitHub Secrets 的 4 个值。
#
# 用法（Git Bash / macOS / Linux 均可，在项目根目录执行）：
#   bash scripts/setup_signing.sh            生成证书 + 打印命令（默认，不写 GitHub）
#   bash scripts/setup_signing.sh --print    复用已有证书，只重新打印命令，不会换证书
#   bash scripts/setup_signing.sh --apply    生成后直接写入 GitHub Secrets（需已登录 gh）
#
# 证书生成两条路，自动选择：
#   A) 找到 keytool（JDK / Android Studio JBR）→ 用它生成，最标准；
#   B) 没有 JDK 但有 openssl（Git Bash / macOS / Linux 自带）→ 生成等价的
#      PKCS12 证书。apksigner 按内容识别 keystore 类型，两种都能读。
# 想强制走 A：KEYTOOL=/path/to/keytool bash scripts/setup_signing.sh
#
# 生成物（均在 dist/，已被 .gitignore 忽略，切勿提交）：
#   release.jks          签名私钥；丢了就永远无法给老用户升级
#   keystore.base64      同一文件的 base64 文本，供 gh secret set 读取
#   signing-secrets.txt  4 个 Secret 的明文值，网页方式逐个复制
#   secret-commands.txt  4 条填好值的 gh 命令，打开即可整段复制
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
PRINT_ONLY=0
case "${1:-}" in
  --apply) APPLY=1 ;;
  --print) PRINT_ONLY=1 ;;
  "") ;;
  *) echo "[setup] 未知参数：${1}（可用 --print / --apply）" >&2; exit 2 ;;
esac

DIST="$ROOT_DIR/dist"
JKS="$DIST/release.jks"
B64_FILE="$DIST/keystore.base64"
VALUES="$DIST/signing-secrets.txt"
COMMANDS="$DIST/secret-commands.txt"

# 打印给用户复制时一律用相对路径：只要 cd 到项目根目录，
# Git Bash / PowerShell / cmd 都能用，不会出现 /d/WorkBuudy 这种只有 Git Bash 认的路径。
R_B64="dist/keystore.base64"
R_VALUES="dist/signing-secrets.txt"
R_COMMANDS="dist/secret-commands.txt"

mkdir -p "$DIST"

# ---------------------------------------------------------------- 输出与写入
# 生成"填好值"的命令文件，同时打印纯命令，最后按 --apply 决定是否真的写 GitHub。
emit_commands() {
  cat > "$COMMANDS" <<EOF
# 在仓库根目录执行（Git Bash / PowerShell 均可）。含明文口令，切勿提交。
# 由 scripts/setup_signing.sh 于 $(date '+%Y-%m-%d %H:%M:%S') 生成。
gh secret set KEYSTORE_BASE64   -R "$REPO" < "$R_B64"
gh secret set KEYSTORE_PASSWORD -R "$REPO" --body "$PASS"
gh secret set KEY_ALIAS         -R "$REPO" --body "$ALIAS"
gh secret set KEY_PASSWORD     -R "$REPO" --body "$PASS"
EOF
  chmod 600 "$COMMANDS" 2>/dev/null || true

  echo
  echo "下面 4 条命令已存到 $R_COMMANDS，打开即可整段复制："
  echo
  printf '  gh secret set KEYSTORE_BASE64   -R "%s" < "%s"\n' "$REPO" "$R_B64"
  printf '  gh secret set KEYSTORE_PASSWORD -R "%s" --body "%s"\n' "$REPO" "$PASS"
  printf '  gh secret set KEY_ALIAS         -R "%s" --body "%s"\n' "$REPO" "$ALIAS"
  printf '  gh secret set KEY_PASSWORD     -R "%s" --body "%s"\n' "$REPO" "$PASS"
  echo
  echo "没装 gh 就打开 $R_VALUES，把等号右边的值逐个粘到网页的 New repository secret。"
  echo "验证：gh secret list -R \"$REPO\"  应能看到这 4 个名字。"
  echo
  echo "⚠ 装完 Secret 后要重新打 tag 发版，签名才会换成正式证书。"
  echo "⚠ 已安装 v1.4.0（调试证书签名）的设备仍需卸载重装一次，之后升级才连续。"
  echo "⚠ 请另外离线备份 dist/release.jks 与 $R_VALUES；私钥丢了无法补。"

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
}

# ---------------------------------------------------------------- --print 模式
# 忘了命令时随时重打，绝不碰已有证书：换证书等于让老用户装不上升级包。
if [ "$PRINT_ONLY" -eq 1 ]; then
  if [ ! -f "$VALUES" ] || [ ! -f "$B64_FILE" ] || [ ! -f "$JKS" ]; then
    echo "[setup] 还没生成过证书，请先跑：bash scripts/setup_signing.sh" >&2
    exit 1
  fi
  PASS="$(grep '^KEYSTORE_PASSWORD=' "$VALUES" | cut -d'=' -f2-)"
  ALIAS="$(grep '^KEY_ALIAS=' "$VALUES" | cut -d'=' -f2-)"
  if [ -z "$PASS" ] || [ -z "$ALIAS" ]; then
    echo "[setup] $R_VALUES 格式异常，缺少 KEYSTORE_PASSWORD / KEY_ALIAS" >&2
    exit 1
  fi
  echo "[setup] 复用已有证书，只重新打印命令（未更换证书）"
  emit_commands
  exit 0
fi

if [ -f "$JKS" ]; then
  echo "[setup] ⚠ 已存在 dist/release.jks" >&2
  echo "[setup] 复用已有证书才能给老用户连续升级；只是想重新看命令请跑：" >&2
  echo "[setup]   bash scripts/setup_signing.sh --print" >&2
  echo "[setup] 确实要换证书的话，先手动删除 dist/release.jks 再重跑。" >&2
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
if [ -n "$KEYTOOL_BIN" ]; then
  MODE=keytool
  echo "[setup] 证书方式：keytool（$KEYTOOL_BIN）"
elif command -v openssl >/dev/null 2>&1; then
  MODE=openssl
  echo "[setup] 未找到 JDK，改用 openssl 生成等价的 PKCS12 证书"
  echo "[setup] （若日后 CI 报 Failed to load keystore，装 JDK 17 后删掉 dist/release.jks 重跑即可）"
else
  cat >&2 <<'HINT'
[setup] keytool 和 openssl 都没有，二选一：
  1) 安装 JDK 17（Temurin）：https://adoptium.net/ ，装完重开 Git Bash 再跑本脚本；
  2) 安装 OpenSSL（Git Bash / macOS / Linux 通常已自带）。
  也可以手动指定：KEYTOOL=/path/to/keytool bash scripts/setup_signing.sh
HINT
  exit 1
fi

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
# 两种都产出 PKCS12。文件名沿用 release.jks 是为了对齐 bootstrap_android.sh 的
# 既有路径；apksigner 按内容识别 keystore 类型，不看扩展名。
# -name / -alias 必须是 qingyang，与 KEY_ALIAS 一致，否则 apksigner 找不到 key。
SUBJECT="/C=CN/ST=Zhejiang/L=Hangzhou/O=Qingyang/OU=Engineering/CN=Qingyang Watermark Camera"

if [ "$MODE" = "keytool" ]; then
  "$KEYTOOL_BIN" -genkeypair -v \
    -keystore "$JKS" \
    -alias "$ALIAS" \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -storetype PKCS12 \
    -storepass "$PASS" -keypass "$PASS" \
    -dname "CN=Qingyang Watermark Camera, OU=Engineering, O=Qingyang, L=Hangzhou, ST=Zhejiang, C=CN" \
    >/dev/null 2>&1 || {
      echo "[setup] keytool 生成失败" >&2
      rm -f "$JKS"
      exit 1
    }
else
  TMP_KEY="$DIST/.tmp_key.pem"
  TMP_CERT="$DIST/.tmp_cert.pem"
  cleanup_tmp() { rm -f "$TMP_KEY" "$TMP_CERT"; }
  trap cleanup_tmp EXIT

  openssl req -x509 -newkey rsa:2048 -sha256 -days 10000 -nodes \
    -keyout "$TMP_KEY" -out "$TMP_CERT" -subj "$SUBJECT" \
    >/dev/null 2>&1 || { echo "[setup] openssl 生成自签名证书失败" >&2; exit 1; }

  # -name 是 PKCS12 的 friendlyName，Java 的 KeyStore 把它当 alias 读出。
  openssl pkcs12 -export \
    -inkey "$TMP_KEY" -in "$TMP_CERT" \
    -out "$JKS" -name "$ALIAS" \
    -passout "pass:$PASS" >/dev/null 2>&1 || {
      echo "[setup] openssl 打包 PKCS12 失败" >&2
      rm -f "$JKS"
      exit 1
    }

  # 自己先解一遍，确认口令、证书、结构都完整，别把坏证书交给 CI 才发现问题。
  openssl pkcs12 -in "$JKS" -passin "pass:$PASS" -nokeys -info -noout \
    >/dev/null 2>&1 || {
      echo "[setup] PKCS12 自检失败：生成的证书无法用给定口令解开" >&2
      rm -f "$JKS"
      exit 1
    }
  cleanup_tmp
  trap - EXIT
fi

if [ ! -s "$JKS" ]; then
  echo "[setup] 证书文件为空，生成失败" >&2
  exit 1
fi

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

echo "[setup] 证书已生成（$MODE / PKCS12）：dist/release.jks"
echo "[setup] 4 个 Secret 的明文值在：$R_VALUES（网页方式逐个复制）"
emit_commands
