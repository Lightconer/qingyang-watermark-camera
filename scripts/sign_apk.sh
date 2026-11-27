#!/usr/bin/env bash
# zipalign + apksigner 重签并校验。
# 未配置签名证书时给出明确告警并跳过（构建产物保持 flutter 的签名结果）。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APK_PATH="${1:-build/app/outputs/flutter-apk/app-release.apk}"
OUT_PATH="${2:-}"

if [ ! -f "$APK_PATH" ]; then
  echo "[sign] 找不到 APK：$APK_PATH" >&2
  exit 1
fi

SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [ -z "$SDK_ROOT" ] || [ ! -d "$SDK_ROOT" ]; then
  echo "[sign] 未找到 Android SDK（ANDROID_SDK_ROOT/ANDROID_HOME），跳过重签" >&2
  exit 0
fi

BUILD_TOOLS_DIR="$(ls -d "$SDK_ROOT"/build-tools/* 2>/dev/null | sort -V | tail -n 1)"
if [ -z "$BUILD_TOOLS_DIR" ]; then
  echo "[sign] 未找到 build-tools，跳过重签" >&2
  exit 0
fi

ZIPALIGN="$BUILD_TOOLS_DIR/zipalign"
APKSIGNER="$BUILD_TOOLS_DIR/apksigner"

KEYSTORE="android/app/release.jks"
PROPS="android/key.properties"

if [ ! -f "$KEYSTORE" ] || [ ! -f "$PROPS" ]; then
  echo "[sign] 未配置签名证书（KEYSTORE_BASE64 缺失），跳过 zipalign/apksigner"
  exit 0
fi

# key.properties → 环境变量
STORE_PASSWORD="$(grep -E '^storePassword=' "$PROPS" | cut -d'=' -f2-)"
KEY_ALIAS="$(grep -E '^keyAlias=' "$PROPS" | cut -d'=' -f2-)"
KEY_PASSWORD="$(grep -E '^keyPassword=' "$PROPS" | cut -d'=' -f2-)"

ALIGNED="$APK_PATH.aligned"
"$ZIPALIGN" -p -f 4 "$APK_PATH" "$ALIGNED"
rm -f "$APK_PATH"
mv "$ALIGNED" "$APK_PATH"

"$APKSIGNER" sign \
  --ks "$KEYSTORE" \
  --ks-key-alias "$KEY_ALIAS" \
  --ks-pass "pass:$STORE_PASSWORD" \
  --key-pass "pass:$KEY_PASSWORD" \
  --v1-signing-enabled true \
  --v2-signing-enabled true \
  "$APK_PATH"

"$APKSIGNER" verify --print-certs "$APK_PATH" | head -n 5
echo "[sign] 重签完成：$APK_PATH"

if [ -n "$OUT_PATH" ]; then
  cp "$APK_PATH" "$OUT_PATH"
  echo "[sign] 已复制到：$OUT_PATH"
fi
