import 'package:flutter_test/flutter_test.dart';
import 'package:qingyang_watermark/core/policy/abi_policy.dart';

void main() {
  group('ApkAssetPolicy.classify', () {
    test('识别 arm64 命名', () {
      for (final name in [
        'qingyang-watermark-v1.4.0-arm64-v8a.apk',
        'app-arm64-v8a-release.apk',
        'qingyang_1.4.0_arm64.apk',
        'qingyang-aarch64.apk',
      ]) {
        expect(ApkAssetPolicy.classify(name), ApkAbi.arm64, reason: name);
      }
    });

    test('识别 32 位 ARM 命名', () {
      for (final name in [
        'qingyang-watermark-v1.4.0-armeabi-v7a.apk',
        'app-armeabi-v7a-release.apk',
        'qingyang_1.4.0_armv7.apk',
        'qingyang_v7a.apk',
      ]) {
        expect(ApkAssetPolicy.classify(name), ApkAbi.armv7, reason: name);
      }
    });

    test('arm64 必须优先于 arm 判断，否则 64 位包会被当成 32 位', () {
      expect(
        ApkAssetPolicy.classify('app-arm64-v8a-release.apk'),
        ApkAbi.arm64,
      );
    });

    test('识别 x86 / x86_64', () {
      expect(ApkAssetPolicy.classify('app-x86_64-release.apk'), ApkAbi.x86_64);
      expect(ApkAssetPolicy.classify('app-x86-release.apk'), ApkAbi.x86);
    });

    test('没有 ABI 标记的按通用包处理', () {
      expect(
        ApkAssetPolicy.classify('qingyang-watermark-v1.2.0.apk'),
        ApkAbi.universal,
      );
      expect(ApkAssetPolicy.classify('update.apk'), ApkAbi.universal);
    });
  });

  group('ApkAssetPolicy.score', () {
    const arm64Phone = ['arm64-v8a', 'armeabi-v7a', 'armeabi'];
    const arm32Phone = ['armeabi-v7a', 'armeabi'];

    test('arm64 设备上 arm64 包得分最高', () {
      final arm64 =
          ApkAssetPolicy.score('x-arm64-v8a.apk', arm64Phone);
      final v7a = ApkAssetPolicy.score('x-armeabi-v7a.apk', arm64Phone);
      final universal = ApkAssetPolicy.score('x.apk', arm64Phone);

      expect(arm64, greaterThan(v7a));
      expect(v7a, greaterThan(universal));
    });

    test('32 位设备上 arm64 包直接判为不可用', () {
      expect(ApkAssetPolicy.score('x-arm64-v8a.apk', arm32Phone), lessThan(0));
      expect(ApkAssetPolicy.score('x-armeabi-v7a.apk', arm32Phone),
          greaterThan(0));
    });

    test('拿不到设备 ABI 时，通用包最稳', () {
      const unknown = <String>[];
      final universal = ApkAssetPolicy.score('x.apk', unknown);
      final arm64 = ApkAssetPolicy.score('x-arm64-v8a.apk', unknown);
      expect(universal, greaterThan(arm64));
    });

    test('设备首选 ABI 越靠前得分越高', () {
      final first = ApkAssetPolicy.score('x-arm64-v8a.apk', arm64Phone);
      final second =
          ApkAssetPolicy.score('x-arm64-v8a.apk', ['armeabi-v7a', 'arm64-v8a']);
      expect(first, greaterThan(second));
    });
  });

  group('ApkAssetPolicy.pick', () {
    final assets = [
      'qingyang-watermark-v1.4.0-armeabi-v7a.apk',
      'qingyang-watermark-v1.4.0-arm64-v8a.apk',
      'SHA256SUMS.txt',
    ];
    String nameOf(String s) => s;

    test('arm64 手机拿到 arm64 包', () {
      expect(
        ApkAssetPolicy.pick(assets, nameOf, ['arm64-v8a', 'armeabi-v7a']),
        'qingyang-watermark-v1.4.0-arm64-v8a.apk',
      );
    });

    test('32 位手机拿到 v7a 包，不会拿到装不上的 arm64 包', () {
      expect(
        ApkAssetPolicy.pick(assets, nameOf, ['armeabi-v7a']),
        'qingyang-watermark-v1.4.0-armeabi-v7a.apk',
      );
    });

    test('一个都装不上时返回 null，由上层明确提示', () {
      final onlyArm = assets.where((a) => a.endsWith('.apk')).toList();
      expect(ApkAssetPolicy.pick(onlyArm, nameOf, ['x86_64']), isNull);
    });

    test('只有通用包时照样能选出来', () {
      expect(
        ApkAssetPolicy.pick(
          ['qingyang-watermark-v1.2.0.apk'],
          nameOf,
          ['arm64-v8a'],
        ),
        'qingyang-watermark-v1.2.0.apk',
      );
    });
  });
}
