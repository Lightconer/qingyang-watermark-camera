#!/usr/bin/env bash
# 构建、签名、体检、汇总校验清单。
#
# 为什么要拆 ABI：
#   universal 包会把 arm64 + armeabi-v7a + x86_64 三套 Flutter 引擎全塞进去，
#   54 MB 里近 30 MB 是这台手机永远用不到的另一套 native 库。
#   现场网络本来就差，包越大越容易下载中断——而「下载不完整」正是
#   「解析包时出现问题」最常见的原因。拆包后单包约 19 MB，下载失败率直线下降。
#
# 为什么不发 x86_64：只有模拟器会用到。真机上多带 20 MB 纯属浪费。
#
# 用法：bash scripts/build_release.sh <version> <build-number>
#   产物落在 dist/：qingyang-watermark-v<version>-<abi>.apk + SHA256SUMS.txt
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:?用法: build_release.sh <version> <build-number>}"
BUILD_NO="${2:?用法: build_release.sh <version> <build-number>}"

OUT_DIR="dist"
APK_DIR="build/app/outputs/flutter-apk"

# 只发 ARM 两档：arm64-v8a 覆盖绝大多数在用手机，armeabi-v7a 兜底老设备。
# 顺序有意义——dist 里第一个出现的是 arm64 包，README 与 Release 说明默认指向它。
ABIS=(arm64-v8a armeabi-v7a)

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "[build] flutter build apk --release --split-per-abi（版本 $VERSION，build $BUILD_NO）"
flutter build apk \
  --release \
  --split-per-abi \
  --build-name "$VERSION" \
  --build-number "$BUILD_NO"

for abi in "${ABIS[@]}"; do
  SRC="$APK_DIR/app-${abi}-release.apk"
  if [ ! -f "$SRC" ]; then
    echo "[build] 缺少 $SRC" >&2
    exit 1
  fi
  DST="$OUT_DIR/qingyang-watermark-v${VERSION}-${abi}.apk"
  # sign_apk.sh 会在未配置证书时跳过签名并直接复制，两种情况下 DST 都会生成。
  bash scripts/sign_apk.sh "$SRC" "$DST"
done

# 校验清单放在 dist 里生成：路径不带目录前缀，用户 sha256sum -c 就能直接比对。
(
  cd "$OUT_DIR"
  sha256sum ./*.apk > SHA256SUMS.txt
  cat SHA256SUMS.txt
)

echo "[build] 结构体检"
python3 scripts/verify_apk.py "$OUT_DIR"/*.apk

echo "[build] 产物体积："
du -h "$OUT_DIR"/*.apk
