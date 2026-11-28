import 'package:flutter_test/flutter_test.dart';
import 'package:qingyang_watermark/core/policy/version.dart';

void main() {
  group('AppVersion.tryParse', () {
    test('识别常见写法', () {
      expect(AppVersion.tryParse('1.2.3'), const AppVersion(1, 2, 3));
      expect(AppVersion.tryParse('v1.2.3'), const AppVersion(1, 2, 3));
      expect(AppVersion.tryParse('V1.2.3'), const AppVersion(1, 2, 3));
      expect(AppVersion.tryParse(' 1.2.3 '), const AppVersion(1, 2, 3));
    });

    test('缺段补零', () {
      expect(AppVersion.tryParse('1'), const AppVersion(1, 0, 0));
      expect(AppVersion.tryParse('1.2'), const AppVersion(1, 2, 0));
    });

    test('去掉 pubspec 的 build 号', () {
      expect(AppVersion.tryParse('1.2.3+45'), const AppVersion(1, 2, 3));
    });

    test('保留预发布后缀', () {
      final version = AppVersion.tryParse('1.2.3-beta.1');
      expect(version, isNotNull);
      expect(version!.preRelease, 'beta.1');
      expect(version.major, 1);
    });

    test('无法识别的输入返回 null', () {
      expect(AppVersion.tryParse(null), isNull);
      expect(AppVersion.tryParse(''), isNull);
      expect(AppVersion.tryParse('latest'), isNull);
      expect(AppVersion.tryParse('1.2.3.4'), isNull);
      expect(AppVersion.tryParse('1.x.0'), isNull);
    });
  });

  group('版本比较', () {
    test('按 major/minor/patch 逐段比较', () {
      expect(const AppVersion(1, 2, 3).isNewerThan(const AppVersion(1, 2, 2)), isTrue);
      expect(const AppVersion(1, 3, 0).isNewerThan(const AppVersion(1, 2, 9)), isTrue);
      expect(const AppVersion(2, 0, 0).isNewerThan(const AppVersion(1, 9, 9)), isTrue);
      expect(const AppVersion(1, 2, 3).isNewerThan(const AppVersion(1, 2, 3)), isFalse);
      expect(const AppVersion(1, 2, 3) > const AppVersion(1, 2, 2), isTrue);
      expect(const AppVersion(1, 2, 3) < const AppVersion(1, 2, 4), isTrue);
    });

    test('同号时正式版高于预发布版', () {
      final stable = AppVersion.tryParse('1.2.3')!;
      final beta = AppVersion.tryParse('1.2.3-beta.1')!;
      expect(stable.isNewerThan(beta), isTrue);
      expect(beta.isNewerThan(stable), isFalse);
      // 正式版不会被同号 beta 反复提示更新
      expect(stable == beta, isFalse);
    });

    test('相等判定用于"已是最新"', () {
      expect(
        AppVersion.tryParse('v1.1.0') == AppVersion.tryParse('1.1.0+7'),
        isTrue,
      );
      expect(AppVersion.tryParse('v1.1.0')!.isNewerThan(AppVersion.tryParse('1.1.0')!),
          isFalse);
    });

    test('标签比当前新才提示更新', () {
      final current = AppVersion.tryParse('1.1.0')!;
      expect(AppVersion.tryParse('v1.2.0')!.isNewerThan(current), isTrue);
      expect(AppVersion.tryParse('v1.1.0')!.isNewerThan(current), isFalse);
      expect(AppVersion.tryParse('v1.0.9')!.isNewerThan(current), isFalse);
    });
  });
}
