import 'package:flutter_test/flutter_test.dart';
import 'package:qingyang_watermark/core/policy/heading.dart';

void main() {
  group('归一化', () {
    test('合法角度落在 [0,360)', () {
      expect(HeadingPolicy.normalize(0), 0);
      expect(HeadingPolicy.normalize(359.5), 359.5);
      expect(HeadingPolicy.normalize(360), 0);
      expect(HeadingPolicy.normalize(450), 90);
      expect(HeadingPolicy.normalize(-1), 359);
      expect(HeadingPolicy.normalize(-370), 350);
    });

    test('非法角度返回 null，绝不当作 0°（正北）', () {
      expect(HeadingPolicy.normalize(null), isNull);
      expect(HeadingPolicy.normalize(double.nan), isNull);
      expect(HeadingPolicy.normalize(double.infinity), isNull);
    });
  });

  group('八方位', () {
    test('扇区边界按 ±22.5° 划分', () {
      expect(HeadingPolicy.cardinal8(0), '北');
      expect(HeadingPolicy.cardinal8(22), '北');
      expect(HeadingPolicy.cardinal8(23), '东北');
      expect(HeadingPolicy.cardinal8(45), '东北');
      expect(HeadingPolicy.cardinal8(67), '东北');
      expect(HeadingPolicy.cardinal8(68), '东');
      expect(HeadingPolicy.cardinal8(90), '东');
      expect(HeadingPolicy.cardinal8(135), '东南');
      expect(HeadingPolicy.cardinal8(180), '南');
      expect(HeadingPolicy.cardinal8(225), '西南');
      expect(HeadingPolicy.cardinal8(270), '西');
      expect(HeadingPolicy.cardinal8(315), '西北');
      expect(HeadingPolicy.cardinal8(340), '北');
      expect(HeadingPolicy.cardinal8(359), '北');
    });

    test('非法角度返回空串', () {
      expect(HeadingPolicy.cardinal8(null), '');
    });
  });

  group('十六方位', () {
    test('扇区边界按 ±11.25° 划分', () {
      expect(HeadingPolicy.cardinal16(0), '北');
      expect(HeadingPolicy.cardinal16(11), '北');
      expect(HeadingPolicy.cardinal16(12), '北东北');
      expect(HeadingPolicy.cardinal16(22), '北东北');
      expect(HeadingPolicy.cardinal16(34), '东北');
      expect(HeadingPolicy.cardinal16(45), '东北');
      expect(HeadingPolicy.cardinal16(90), '东');
      expect(HeadingPolicy.cardinal16(180), '南');
      expect(HeadingPolicy.cardinal16(270), '西');
      expect(HeadingPolicy.cardinal16(348), '北西北');
    });
  });

  group('角度文案', () {
    test('四舍五入且 360° 回绕成 0°', () {
      expect(HeadingPolicy.degreesText(42), '42°');
      expect(HeadingPolicy.degreesText(42.6), '43°');
      expect(HeadingPolicy.degreesText(359.6), '0°');
      expect(HeadingPolicy.degreesText(-0.4), '0°');
    });
  });

  group('三种写法', () {
    test('八方位', () {
      expect(
        HeadingPolicy.format(42, style: HeadingFormat.cardinal8),
        '东北 42°',
      );
    });

    test('十六方位', () {
      expect(
        HeadingPolicy.format(22, style: HeadingFormat.cardinal16),
        '北东北 22°',
      );
    });

    test('仅角度', () {
      expect(
        HeadingPolicy.format(346, style: HeadingFormat.degrees),
        '346°',
      );
    });

    test('无读数时返回空串，界面据此隐藏该行', () {
      expect(HeadingPolicy.format(null), '');
      expect(HeadingPolicy.format(double.nan), '');
    });

    test('code 往返一致（设置持久化用）', () {
      for (final format in HeadingFormat.values) {
        expect(HeadingFormatX.fromCode(format.code), format);
      }
    });
  });
}
