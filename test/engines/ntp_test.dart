import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingyang_watermark/engines/time/time_engine.dart';

void main() {
  test('SNTP 请求包为 48 字节且首位为 0x1B', () {
    final packet = NtpClient.buildRequestPacket();
    expect(packet.length, 48);
    expect(packet[0], 0x1B);
  });

  test('时间戳编解码往返误差 < 2ms', () {
    final time = DateTime.utc(2026, 11, 27, 12, 31, 5, 482);
    final packet = NtpClient.encodeTimestamp(time);
    final decoded = NtpClient.parseResponse(packet);
    expect(decoded, isNotNull);
    expect(decoded!.difference(time).inMilliseconds.abs(), lessThanOrEqualTo(2));
  });

  test('空响应被判定为无效', () {
    expect(NtpClient.parseResponse(Uint8List(48)), isNull);
    expect(NtpClient.parseResponse(Uint8List(10)), isNull);
  });

  test('NTP 不可用时回退系统时间并标注口径', () async {
    final engine = TimeEngine(
      source: FakeTimeSource(available: false),
    );
    final result = await engine.sync();
    expect(result, isNull);
    expect(engine.hasTrustedTime, isFalse);
    expect(engine.now().authority.name, 'system');
  });

  test('NTP 可用时口径为 ntp', () async {
    final engine = TimeEngine(source: FakeTimeSource());
    final result = await engine.sync();
    expect(result, isNotNull);
    expect(engine.now().authority.name, 'ntp');
    expect(NtpClient.isAcceptable(result!), isTrue);
  });
}
