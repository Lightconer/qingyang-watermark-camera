import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../core/models/types.dart';

class LocationFix {
  const LocationFix({
    required this.point,
    required this.at,
    this.altitudeMeters,
    this.accuracyMeters,
    this.isFused = false,
    this.isMocked = false,
  });

  final GeoPoint point;
  final DateTime at;
  final double? altitudeMeters;
  final double? accuracyMeters;

  /// 是否由系统融合定位（北斗/GPS/网络）给出。
  final bool isFused;
  final bool isMocked;
}

/// 定位引擎接口。快门触发时取一次 [currentFix] 并冻结，之后不再读取。
abstract class LocationEngine {
  Future<bool> ensurePermission();

  Future<bool> isServiceEnabled();

  Future<LocationFix?> currentFix({Duration timeout = const Duration(seconds: 12)});

  Stream<LocationFix> watch({Duration interval = const Duration(seconds: 3)});
}

class GeolocatorLocationEngine implements LocationEngine {
  GeolocatorLocationEngine({this.allowMocked = false});

  /// 取证场景默认拒绝模拟定位（外挂定位软件）。
  final bool allowMocked;

  @override
  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return false;
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationFix?> currentFix({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: timeout,
      );
      return _toFix(position);
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<LocationFix> watch({
    Duration interval = const Duration(seconds: 3),
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        timeLimit: null,
      ),
    ).map(_toFix).where((fix) => fix != null).cast<LocationFix>();
  }

  LocationFix? _toFix(Position position) {
    final point = GeoPoint(
      latitude: position.latitude,
      longitude: position.longitude,
    );
    if (!point.isValid) return null;
    final mocked = position.isMocked;
    if (mocked && !allowMocked) return null;
    return LocationFix(
      point: point,
      at: DateTime.now(),
      altitudeMeters: position.altitude,
      accuracyMeters: position.accuracy,
      isFused: true,
      isMocked: mocked,
    );
  }
}

/// 测试替身：固定坐标，可模拟"定位失败"。
class FakeLocationEngine implements LocationEngine {
  FakeLocationEngine({
    this.fix,
    this.permissionGranted = true,
    this.serviceEnabled = true,
  });

  LocationFix? fix;
  bool permissionGranted;
  bool serviceEnabled;

  @override
  Future<bool> ensurePermission() async => permissionGranted;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationFix?> currentFix({
    Duration timeout = const Duration(seconds: 12),
  }) async =>
      fix;

  @override
  Stream<LocationFix> watch({
    Duration interval = const Duration(seconds: 3),
  }) async* {
    if (fix != null) yield fix!;
  }
}
