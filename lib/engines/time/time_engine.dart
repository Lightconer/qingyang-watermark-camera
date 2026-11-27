import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/models/types.dart';

/// NTP 授时结果。
class NtpResult {
  const NtpResult({
    required this.serverTime,
    required this.offset,
    required this.roundTrip,
    required this.queriedAt,
    required this.server,
  });

  /// 服务器时间（已按往返时延的一半补偿）。
  final Duration serverTime;
  final Duration offset;
  final Duration roundTrip;
  final DateTime queriedAt;
  final String server;
}

/// 时间源抽象，便于单测注入固定时间。
abstract class TimeSource {
  Future<NtpResult?> query({
    String host = 'ntp.aliyun.com',
    Duration timeout = const Duration(seconds: 3),
  });
}

/// 极简 SNTP 客户端（UDP/123），仅依赖 dart:io，无第三方库。
class NtpClient implements TimeSource {
  const NtpClient();

  static const int _ntpPort = 123;
  static const int _ntpEpochOffsetSeconds = 2208988800; // 1900-01-01 → 1970-01-01

  @override
  Future<NtpResult?> query({
    String host = 'ntp.aliyun.com',
    Duration timeout = const Duration(seconds: 3),
  }) async {
    RawDatagramSocket? socket;
    try {
      final startedAt = DateTime.now().toUtc();
      final request = buildRequestPacket();
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final completer = Completer<NtpResult?>();
      final timer = Timer(timeout, () {
        if (!completer.isCompleted) completer.complete(null);
      });

      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket?.receive();
        if (datagram == null) return;
        final receivedAt = DateTime.now().toUtc();
        final parsed = parseResponse(datagram.data);
        if (parsed == null) return;
        final rtt = receivedAt.difference(startedAt);
        final serverTime =
            parsed.add(Duration(microseconds: rtt.inMicroseconds ~/ 2));
        if (!completer.isCompleted) {
          completer.complete(NtpResult(
            serverTime: serverTime,
            offset: serverTime.difference(receivedAt),
            roundTrip: rtt,
            queriedAt: receivedAt,
            server: host,
          ));
        }
        timer.cancel();
      });

      socket.send(request, InternetAddress(host), _ntpPort);
      return await completer.future;
    } catch (_) {
      return null;
    } finally {
      socket?.close();
    }
  }

  /// 48 字节 SNTP 请求：LI=0, VN=3, Mode=3（客户端）。
  static Uint8List buildRequestPacket() {
    final packet = Uint8List(48);
    packet[0] = 0x1B;
    final now = DateTime.now().toUtc();
    final seconds = now.millisecondsSinceEpoch ~/ 1000 + _ntpEpochOffsetSeconds;
    final fraction =
        ((now.millisecondsSinceEpoch % 1000) / 1000 * 0xFFFFFFFF).round();
    final data = ByteData.sublistView(packet);
    data.setUint32(40, seconds);
    data.setUint32(44, fraction & 0xFFFFFFFF);
    return packet;
  }

  /// 解析响应的 transmit timestamp（偏移 40 字节）。
  static DateTime? parseResponse(Uint8List packet) {
    if (packet.length < 48) return null;
    final data = ByteData.sublistView(packet);
    final seconds = data.getUint32(40);
    final fraction = data.getUint32(44);
    if (seconds == 0 && fraction == 0) return null;
    final milliseconds = (seconds - _ntpEpochOffsetSeconds) * 1000 +
        (fraction * 1000 / 0x100000000).round();
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  }

  /// 便于单测：把时间装箱成 48 字节响应包。
  static Uint8List encodeTimestamp(DateTime time) {
    final packet = Uint8List(48);
    final data = ByteData.sublistView(packet);
    final utc = time.toUtc();
    final seconds = utc.millisecondsSinceEpoch ~/ 1000 + _ntpEpochOffsetSeconds;
    final fraction =
        ((utc.millisecondsSinceEpoch % 1000) / 1000 * 0xFFFFFFFF).round();
    data.setUint32(40, seconds);
    data.setUint32(44, fraction & 0xFFFFFFFF);
    return packet;
  }

  /// 保留给调用方判断往返是否可接受。
  static bool isAcceptable(NtpResult result) =>
      result.roundTrip.inMilliseconds <= 1500;
}

/// 授时引擎：优先 NTP，失败回退系统时间并明确标记口径。
class TimeEngine {
  TimeEngine({
    TimeSource? source,
    this.host = 'ntp.aliyun.com',
    this.validFor = const Duration(minutes: 10),
  }) : _source = source ?? const NtpClient();

  final TimeSource _source;
  final String host;
  final Duration validFor;

  NtpResult? _last;
  bool _syncing = false;

  NtpResult? get lastSync => _last;

  bool get hasTrustedTime =>
      _last != null &&
      DateTime.now().toUtc().difference(_last!.queriedAt.toUtc()).abs() < validFor;

  /// 返回当前时间 + 口径。
  ({DateTime time, TimeAuthority authority, int? offsetMs}) now() {
    if (hasTrustedTime) {
      final elapsed = DateTime.now().toUtc().difference(_last!.queriedAt.toUtc());
      return (
        time: _last!.serverTime.add(elapsed),
        authority: TimeAuthority.ntp,
        offsetMs: _last!.offset.inMilliseconds,
      );
    }
    return (
      time: DateTime.now(),
      authority: TimeAuthority.system,
      offsetMs: _last?.offset.inMilliseconds,
    );
  }

  Future<NtpResult?> sync({Duration timeout = const Duration(seconds: 3)}) async {
    if (_syncing) return _last;
    _syncing = true;
    try {
      final result = await _source.query(host: host, timeout: timeout);
      if (result != null) _last = result;
      return result;
    } finally {
      _syncing = false;
    }
  }

  /// 关闭 NTP 时强制使用系统时间（离线模式）。
  void reset() => _last = null;
}

/// 测试替身：固定时间、可切换"有/无 NTP"。
class FakeTimeSource implements TimeSource {
  FakeTimeSource({
    DateTime? fixedTime,
    this.available = true,
    this.roundTrip = const Duration(milliseconds: 40),
  }) : fixedTime = fixedTime ?? DateTime(2026, 11, 27, 20, 31, 5);

  final DateTime fixedTime;
  final bool available;
  final Duration roundTrip;

  @override
  Future<NtpResult?> query({
    String host = 'fake.ntp',
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (!available) return null;
    return NtpResult(
      serverTime: Duration(milliseconds: fixedTime.millisecondsSinceEpoch),
      offset: const Duration(milliseconds: 120),
      roundTrip: roundTrip,
      queriedAt: DateTime.now().toUtc(),
      server: host,
    );
  }
}

/// 便于测试：两个时间的偏斜（毫秒）。
int clockSkewMs(DateTime a, DateTime b) => math.max(
      a.difference(b).inMilliseconds,
      b.difference(a).inMilliseconds,
    );
