#!/usr/bin/env bash
# zipalign + apksigner 重签并校验。
#
# 未配置签名证书时给出明确告警并跳过（构建产物保持 flutter 的签名结果）。
#
# 为什么这个脚本写得这么啰嗦：
# 「解析包时出现问题」在国产 ROM（荣耀/华为/OPPO/vivo）上最常见的三个成因是
#   1) APK 下载不完整（体积大、网络断）—— 靠瘦身解决，见 CI 的分 ABI 构建；
#   2) 只带 v3 签名、缺 v1/v2 —— 老安装器直接判定「包损坏」；
#   3) native 库只按 4 KB 对齐，而 Android 15 起部分设备是 16 KB 页大小。
# 这里把 2、3 全部锁死，并在结尾用 apksigner verify 兜底：
# 自己都验不过的包，绝不往外发。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APK_PATH="${1:-build/app/outputs/flutter-apk/app-release.apk}"
OUT_PATH="${2:-}"

# 与 pubspec / android 侧保持一致。显式传给 apksigner 而不是让它去读清单：
# 读错 minSdk 会让 v1 签名选错摘要算法，结果就是「能下能装但解析失败」。
MIN_SDK="${MIN_SDK:-24}"
TARGET_SDK="${TARGET_SDK:-36}"

if [ ! -f "$APK_PATH" ]; then
  echo "[sign] 找不到 APK：$APK_PATH" >&2
  exit 1
fi

SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"

# 跳过重签时也要把产物放到 OUT_PATH：调用方（build_release.sh）依赖它
# 一定存在，否则「没配证书」会变成「构建脚本找不到文件而失败」。
emit_without_signing() {
  local reason="$1"
  echo "[sign] $reason，跳过 zipalign/apksigner" >&2
  if [ -n "$OUT_PATH" ]; then
    mkdir -p "$(dirname "$OUT_PATH")"
    cp "$APK_PATH" "$OUT_PATH"
    echo "[sign] 已复制（未重签）：$OUT_PATH"
  fi
  exit 0
}

if [ -z "$SDK_ROOT" ] || [ ! -d "$SDK_ROOT" ]; then
  emit_without_signing "未找到 Android SDK（ANDROID_SDK_ROOT/ANDROID_HOME）"
fi

BUILD_TOOLS_DIR="$(ls -d "$SDK_ROOT"/build-tools/* 2>/dev/null | sort -V | tail -n 1)"
if [ -z "$BUILD_TOOLS_DIR" ]; then
  emit_without_signing "未找到 build-tools"
fi

ZIPALIGN="$BUILD_TOOLS_DIR/zipalign"
APKSIGNER="$BUILD_TOOLS_DIR/apksigner"

KEYSTORE="android/app/release.jks"
PROPS="android/key.properties"
FALLBACK_SIGNING=0

# 没配发布证书时的兜底：拿 AGP 刚才用过的调试证书重新签一遍。
#
# 这一段是「解析包时出现问题」的直接修复点：minSdk 24 时 AGP 认定 v1 签名
# 只服务 Android 7 以下，默认**不生成** v1——而部分国产 ROM（荣耀/华为等）
# 的安装器只要发现包里没有 META-INF/*.RSA，就直接判「包损坏」。
# 所以哪怕没有发布证书，也必须用调试证书重签一遍把 v1 补上。
if [ ! -f "$KEYSTORE" ] || [ ! -f "$PROPS" ]; then
  DEBUG_KS="${HOME}/.android/debug.keystore"
  if [ ! -f "$DEBUG_KS" ]; then
    emit_without_signing "未配置签名证书，且找不到调试证书（$DEBUG_KS）"
  fi
  KEYSTORE="$DEBUG_KS"
  STORE_PASSWORD="android"
  KEY_ALIAS="androiddebugkey"
  KEY_PASSWORD="android"
  FALLBACK_SIGNING=1
  echo "[sign] ⚠ 未配置 KEYSTORE_BASE64，改用调试证书重签（补齐 v1 签名，但不适合正式分发）"
else
  # key.properties → 环境变量
  STORE_PASSWORD="$(grep -E '^storePassword=' "$PROPS" | cut -d'=' -f2-)"
  KEY_ALIAS="$(grep -E '^keyAlias=' "$PROPS" | cut -d'=' -f2-)"
  KEY_PASSWORD="$(grep -E '^keyPassword=' "$PROPS" | cut -d'=' -f2-)"
fi

# ---------------------------------------------------------------- 1. 对齐
# -P 16 是 16 KB 页对齐（build-tools 35+ 才有）。Android 15 的部分新机型
# 与 Google Play 的 16 KB 要求都指向它；老 build-tools 不认识该参数，
# 探测后回退 4 KB 页对齐，保证两种环境下脚本都能跑。
ALIGNED="$APK_PATH.aligned"
rm -f "$ALIGNED"
# 先按 16 KB 页对齐真跑一次：能跑通就用它，跑不通再退 4 KB。
# 不去猜 `-h` 的输出格式——不同 build-tools 的用法文本写法不一致，
# 猜错的结果是「以为不支持」，于是新机装不上还查不出原因。
if "$ZIPALIGN" -P 16 -p -f 4 "$APK_PATH" "$ALIGNED" >/dev/null 2>&1; then
  echo "[sign] 已按 16 KB 页对齐（Android 15+ 新机型要求）"
else
  rm -f "$ALIGNED"
  "$ZIPALIGN" -p -f 4 "$APK_PATH" "$ALIGNED"
  echo "[sign] 当前 build-tools 不支持 -P，回退 4 KB 页对齐"
fi
rm -f "$APK_PATH"
mv "$ALIGNED" "$APK_PATH"

# ---------------------------------------------------------------- 2. 签名
# v1 必开：缺 v1 的包在部分国产 ROM 的安装器上直接报「解析包失败」。
# v2 必开：Android 7+ 的主校验通道。
# v3 开：Android 9+ 的密钥轮换/降级保护，与 v1/v2 可并存，不影响老设备。
# 不开 v4：v4 需要同目录的 .idsig 文件，侧载场景反而容易缺件。
"$APKSIGNER" sign \
  --ks "$KEYSTORE" \
  --ks-key-alias "$KEY_ALIAS" \
  --ks-pass "pass:$STORE_PASSWORD" \
  --key-pass "pass:$KEY_PASSWORD" \
  --min-sdk-version "$MIN_SDK" \
  --max-sdk-version "$TARGET_SDK" \
  --v1-signing-enabled true \
  --v2-signing-enabled true \
  --v3-signing-enabled true \
  "$APK_PATH"

# ---------------------------------------------------------------- 3. 自检
# verify 失败说明包本身有问题（结构损坏 / 签名不完整 / 对齐被破坏）。
# 这种情况必须让 CI 红，而不是把一个装不上的包发到 Release。
if ! "$APKSIGNER" verify \
  --min-sdk-version "$MIN_SDK" \
  --max-sdk-version "$TARGET_SDK" \
  "$APK_PATH" >/dev/null 2>&1; then
  echo "[sign] 签名校验失败：$APK_PATH" >&2
  "$APKSIGNER" verify --min-sdk-version "$MIN_SDK" "$APK_PATH" >&2 || true
  exit 1
fi

echo "[sign] 签名方案："
"$APKSIGNER" verify --print-certs --min-sdk-version "$MIN_SDK" "$APK_PATH" \
  | grep -Ei 'Verified using v[0-9]|Signer #1 certificate DN|SHA-256 digest' | head -n 8 || true
echo "[sign] 重签完成：$APK_PATH（$(du -h "$APK_PATH" | cut -f1)）"

if [ "$FALLBACK_SIGNING" = "1" ]; then
  echo "[sign] ----------------------------------------------------------------"
  echo "[sign] ⚠  本次使用调试证书签名："
  echo "[sign] ⚠  · 能装、能跑，但不能用于正式分发；"
  echo "[sign] ⚠  · CI 每次构建都会生成新的调试证书，跨版本覆盖安装会失败。"
  echo "[sign] ⚠  配置 KEYSTORE_BASE64 / KEYSTORE_PASSWORD / KEY_ALIAS / KEY_PASSWORD"
  echo "[sign] ⚠  后签名才稳定，用户才能从旧版直接升级。"
  echo "[sign] ----------------------------------------------------------------"
fi

if [ -n "$OUT_PATH" ]; then
  mkdir -p "$(dirname "$OUT_PATH")"
  cp "$APK_PATH" "$OUT_PATH"
  echo "[sign] 已复制到：$OUT_PATH"
fi
