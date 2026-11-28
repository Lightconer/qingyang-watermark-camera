import 'dart:async';

import 'package:flutter/services.dart';

/// 一次朝向读数（0°=正北，顺时针增加）。
class CompassReading {
  const CompassReading({required this.degrees, this.accuracyDegrees});

  final double degrees;

  /// 传感器自报精度（度）；设备不上报时为 null。
  final double? accuracyDegrees;

  bool get isValid => degrees.isFinite;

  static CompassReading? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final value = raw['degrees'];
    if (value is! num) return null;
    final reading = CompassReading(
      degrees: value.toDouble(),
      accuracyDegrees: (raw['accuracy'] as num?)?.toDouble(),
    );
    return reading.isValid ? reading : null;
  }

  @override
  String toString() =>
      'CompassReading(${degrees.toStringAsFixed(1)}°, ±$accuracyDegrees)';
}

/// 扩展点：朝向来源。
///
/// 抽象出接口而不是在页面里直接调 SensorManager，是为了：
/// 1. 无磁力计的设备（部分平板、模拟器）能优雅降级成"朝向未知"；
/// 2. 单测与桌面端可注入 [FakeCompassEngine]，不依赖真实传感器。
abstract class CompassEngine {
  /// 设备是否具备可用的方向传感器。必须在订阅前调用一次。
  Future<bool> probe();

  /// 连续读数流。不支持时为空流，绝不抛错打断拍摄链路。
  Stream<CompassReading> get stream;

  /// 一次性读数；不支持或超时返回 null。
  Future<CompassReading?> read();

  Future<void> dispose();
}

/// 原生实现：Android 侧用 `SensorManager` 的旋转矢量传感器（融合磁力计 + 陀螺仪 +
/// 加速度计），比裸磁力计抗干扰、不需要"8 字校准"就能出稳定值。
///
/// 与相册/更新通道一样走自建通道，不额外引入传感器插件依赖。
class NativeCompassEngine implements CompassEngine {
  NativeCompassEngine({
    MethodChannel? channel,
    EventChannel? eventChannel,
  })  : _channel = channel ??
            const MethodChannel('com.qingyang.watermark/compass'),
        _eventChannel = eventChannel ??
            const EventChannel('com.qingyang.watermark/compassStream');

  final MethodChannel _channel;
  final EventChannel _eventChannel;

  Stream<CompassReading>? _cached;
  bool? _supported;

  @override
  Future<bool> probe() async {
    if (_supported != null) return _supported!;
    try {
      final value = await _channel.invokeMethod<bool>('hasCompass');
      _supported = value ?? false;
    } on MissingPluginException {
      // 未注入原生实现（桌面 / 测试环境）：按不支持处理。
      _supported = false;
    } on PlatformException {
      _supported = false;
    }
    return _supported!;
  }

  @override
  Stream<CompassReading> get stream {
    return _cached ??= _eventChannel
        .receiveBroadcastStream()
        .map(CompassReading.fromMap)
        .where((reading) => reading != null)
        .cast<CompassReading>();
  }

  @override
  Future<CompassReading?> read() async {
    if (!await probe()) return null;
    try {
      final raw = await _channel
          .invokeMethod<Object?>('read')
          .timeout(const Duration(seconds: 3));
      return CompassReading.fromMap(raw);
    } on TimeoutException {
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    // 原生侧在 Activity 销毁时自行注销监听，这里只清缓存。
    _cached = null;
  }
}

/// 测试与桌面端用的假实现。
class FakeCompassEngine implements CompassEngine {
  FakeCompassEngine({
    this.supported = true,
    double? degrees = 45,
    this.accuracyDegrees = 3,
  }) : _degrees = degrees;

  final bool supported;
  final double? accuracyDegrees;
  double? _degrees;

  final StreamController<CompassReading> _controller =
      StreamController<CompassReading>.broadcast();

  /// 变更当前朝向并推给订阅者。设备不支持时静默忽略（与真实传感器一致）。
  void emit(double degrees, {double? accuracy}) {
    if (!supported) return;
    _degrees = degrees;
    if (_controller.isClosed) return;
    _controller.add(CompassReading(
      degrees: degrees,
      accuracyDegrees: accuracy ?? accuracyDegrees,
    ));
  }

  bool get hasListener => _controller.hasListener;

  @override
  Future<bool> probe() async => supported;

  @override
  Stream<CompassReading> get stream => _controller.stream;

  @override
  Future<CompassReading?> read() async {
    if (!supported || _degrees == null) return null;
    return CompassReading(
      degrees: _degrees!,
      accuracyDegrees: accuracyDegrees,
    );
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}
