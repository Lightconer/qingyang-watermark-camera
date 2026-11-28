import 'package:flutter_test/flutter_test.dart';
import 'package:qingyang_watermark/core/policy/checksum_file.dart';

const _shaA = 'a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0'
    'a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0';
const _shaB = 'b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1'
    'b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1';

void main() {
  group('ChecksumFile.parseAll', () {
    test('解析 sha256sum 的两种格式', () {
      final map = ChecksumFile.parseAll(
        '$_shaA  qingyang-watermark-v1.2.0.apk\n'
        '$_shaB *other.apk\n',
      );
      expect(map['qingyang-watermark-v1.2.0.apk'], _shaA);
      expect(map['other.apk'], _shaB);
    });

    test('兼容 Windows 换行、前后空白与目录前缀', () {
      final map = ChecksumFile.parseAll('  $_shaA   ./dist/app.apk  \r\n');
      expect(map['app.apk'], _shaA);
    });

    test('忽略非法行，不会把说明文字当成哈希', () {
      final map = ChecksumFile.parseAll(
        '# 这是说明\n'
        'not-a-hash  app.apk\n'
        '$_shaA  app.apk\n',
      );
      expect(map.length, 1);
      expect(map['app.apk'], _shaA);
    });

    test('大小写归一为小写', () {
      final map = ChecksumFile.parseAll('${_shaA.toUpperCase()}  app.apk\n');
      expect(map['app.apk'], _shaA);
    });

    test('空内容返回空表', () {
      expect(ChecksumFile.parseAll(null), isEmpty);
      expect(ChecksumFile.parseAll(''), isEmpty);
    });
  });

  group('ChecksumFile.lookup', () {
    test('按文件名命中', () {
      final text = '$_shaA  a.apk\n$_shaB  b.apk\n';
      expect(ChecksumFile.lookup(text, 'b.apk'), _shaB);
    });

    test('只有一条记录时按该条兜底（发布方改名也能校验）', () {
      final text = '$_shaA  releases/app.apk\n';
      expect(ChecksumFile.lookup(text, 'qingyang.apk'), _shaA);
    });

    test('多条记录且都对不上时返回 null，不猜', () {
      final text = '$_shaA  a.apk\n$_shaB  b.apk\n';
      expect(ChecksumFile.lookup(text, 'c.apk'), isNull);
    });
  });

  group('ChecksumFile.matches', () {
    test('忽略大小写与空白', () {
      expect(ChecksumFile.matches('$_shaA', '  ${_shaA.toUpperCase()} '), isTrue);
      expect(ChecksumFile.matches(_shaA, _shaB), isFalse);
    });

    test('任一侧缺失都视为不匹配（宁可不装）', () {
      expect(ChecksumFile.matches(null, _shaA), isFalse);
      expect(ChecksumFile.matches(_shaA, null), isFalse);
    });
  });
}
