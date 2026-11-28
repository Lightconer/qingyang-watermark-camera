/// 纯 Dart 领域基础类型：无 Flutter 依赖，可直接单测。
library;

/// 应用身份常量（水印、EXIF Software 字段统一引用）。
class AppIdentity {
  const AppIdentity._();

  static const String appName = '青阳水印相机';
  static const String packageName = 'com.qingyang.watermark';
  static const String softwareTag = 'QingyangWatermarkCamera';
  static const String schemaVersion = '1.0';

  /// 编译期版本兜底：优先用系统 `versionName`，原生取不到时才用它。
  /// 发版时与 `pubspec.yaml` 的 version 一起改。
  static const String version = '1.1.0';

  /// 默认更新源（与 release.yml 发布的仓库一致），设置页可改成分叉仓库。
  static const String updateRepo = 'Lightconer/qingyang-watermark-camera';
}

/// 照片来源。`camera` 为现场拍摄，其余均为导入。
enum PhotoSource { camera, gallery, folder, share }

extension PhotoSourceX on PhotoSource {
  String get label {
    switch (this) {
      case PhotoSource.camera:
        return '现场拍摄';
      case PhotoSource.gallery:
        return '相册导入';
      case PhotoSource.folder:
        return '文件夹导入';
      case PhotoSource.share:
        return '分享导入';
    }
  }

  String get code => name;

  /// 画面上使用的短标签，必须与 [Provenance.shortBadge] 口径一致。
  String get shortBadge => this == PhotoSource.camera ? '现场' : '导入';

  bool get isImport => this != PhotoSource.camera;

  static PhotoSource fromCode(String? code) {
    for (final source in PhotoSource.values) {
      if (source.name == code) return source;
    }
    return PhotoSource.gallery;
  }
}

/// 业务模式（取证 / 加工 / 自由）。模式行为由 [ProfileConfig] 的 JSON 描述驱动。
enum CaptureMode { forensics, processed, free }

extension CaptureModeX on CaptureMode {
  String get label {
    switch (this) {
      case CaptureMode.forensics:
        return '取证';
      case CaptureMode.processed:
        return '加工';
      case CaptureMode.free:
        return '自由';
    }
  }

  static CaptureMode fromCode(String? code) {
    for (final mode in CaptureMode.values) {
      if (mode.name == code) return mode;
    }
    return CaptureMode.free;
  }
}

/// 时间的权威来源。
enum TimeAuthority {
  /// NTP 授时（可信）。
  ntp,

  /// 系统本地时间（离线回退，必须显式标注）。
  system,

  /// 原图 EXIF DateTimeOriginal（导入链路唯一合法来源）。
  originalExif,

  /// 无任何可用时间。
  missing,
}

extension TimeAuthorityX on TimeAuthority {
  String get label {
    switch (this) {
      case TimeAuthority.ntp:
        return 'NTP 标准时间';
      case TimeAuthority.system:
        return '本地系统时间';
      case TimeAuthority.originalExif:
        return '原图拍摄时间';
      case TimeAuthority.missing:
        return '时间未知';
    }
  }

  bool get isTrusted => this == TimeAuthority.ntp || this == TimeAuthority.originalExif;
}

/// 坐标的权威来源。
enum CoordAuthority {
  /// 北斗 + GPS + 网络融合定位（拍摄链路）。
  fused,

  /// 仅 GPS 原始定位（离线）。
  gps,

  /// 原图 EXIF GPS（导入链路）。
  originalExif,

  /// 无坐标。
  missing,
}

extension CoordAuthorityX on CoordAuthority {
  String get label {
    switch (this) {
      case CoordAuthority.fused:
        return '融合定位';
      case CoordAuthority.gps:
        return 'GPS 定位';
      case CoordAuthority.originalExif:
        return '原图定位';
      case CoordAuthority.missing:
        return '定位失败';
    }
  }

  bool get hasFix =>
      this == CoordAuthority.fused ||
      this == CoordAuthority.gps ||
      this == CoordAuthority.originalExif;
}

/// WGS84 经纬度。
class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  bool get isValid =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      !(latitude == 0 && longitude == 0);

  /// `30.123456°N 120.123456°E`
  String toDisplay({int decimals = 6}) {
    final ns = latitude >= 0 ? 'N' : 'S';
    final ew = longitude >= 0 ? 'E' : 'W';
    return '${latitude.abs().toStringAsFixed(decimals)}°$ns '
        '${longitude.abs().toStringAsFixed(decimals)}°$ew';
  }

  /// `N30°12'34.5" E120°07'22.1"`
  String toDms() {
    String one(double value, String positive, String negative) {
      final abs = value.abs();
      final degree = abs.floor();
      final minuteFull = (abs - degree) * 60;
      final minute = minuteFull.floor();
      final second = (minuteFull - minute) * 60;
      final hemi = value >= 0 ? positive : negative;
      return '$hemi$degree°${minute.toString().padLeft(2, '0')}\''
          '${second.toStringAsFixed(1).padLeft(4, '0')}"';
    }

    return '${one(latitude, 'N', 'S')} ${one(longitude, 'E', 'W')}';
  }

  Map<String, dynamic> toJson() => {'lat': latitude, 'lon': longitude};

  static GeoPoint? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final lat = (json['lat'] as num?)?.toDouble();
    final lon = (json['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    return GeoPoint(latitude: lat, longitude: lon);
  }

  @override
  String toString() => toDisplay();
}

/// 天气快照（拍摄/导入瞬间冻结，离线时为 null）。
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperatureC,
    required this.text,
    required this.fetchedAt,
  });

  final double? temperatureC;
  final String text;
  final DateTime fetchedAt;

  String get display {
    final temp = temperatureC == null ? '' : '${temperatureC!.toStringAsFixed(0)}℃';
    if (text.isEmpty) return temp;
    if (temp.isEmpty) return text;
    return '$text $temp';
  }

  Map<String, dynamic> toJson() => {
        'temperatureC': temperatureC,
        'text': text,
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  static WeatherSnapshot? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final fetched = DateTime.tryParse('${json['fetchedAt']}');
    if (fetched == null) return null;
    return WeatherSnapshot(
      temperatureC: (json['temperatureC'] as num?)?.toDouble(),
      text: '${json['text'] ?? ''}',
      fetchedAt: fetched,
    );
  }
}

/// 快门瞬间冻结的采集上下文。坐标、时间、地址、天气在拍摄时一次性锁定，之后不可修改。
class CaptureContext {
  const CaptureContext({
    required this.capturedAt,
    required this.timeAuthority,
    required this.coordAuthority,
    this.position,
    this.altitudeMeters,
    this.address,
    this.weather,
    this.deviceModel,
    this.online = false,
    this.ntpOffsetMs,
  });

  factory CaptureContext.empty() => CaptureContext(
        capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
        timeAuthority: TimeAuthority.missing,
        coordAuthority: CoordAuthority.missing,
      );

  final DateTime capturedAt;
  final TimeAuthority timeAuthority;
  final CoordAuthority coordAuthority;
  final GeoPoint? position;
  final double? altitudeMeters;
  final String? address;
  final WeatherSnapshot? weather;
  final String? deviceModel;
  final bool online;
  final int? ntpOffsetMs;

  bool get hasTrustedTime => timeAuthority.isTrusted;
  bool get hasPosition => position != null && position!.isValid;

  /// 离线采集标记：无网络时坐标只有 GPS 原始值，时间只能用系统时间。
  bool get isOfflineCapture => !online;

  CaptureContext copyWith({
    DateTime? capturedAt,
    TimeAuthority? timeAuthority,
    CoordAuthority? coordAuthority,
    GeoPoint? position,
    double? altitudeMeters,
    String? address,
    WeatherSnapshot? weather,
    String? deviceModel,
    bool? online,
    int? ntpOffsetMs,
  }) {
    return CaptureContext(
      capturedAt: capturedAt ?? this.capturedAt,
      timeAuthority: timeAuthority ?? this.timeAuthority,
      coordAuthority: coordAuthority ?? this.coordAuthority,
      position: position ?? this.position,
      altitudeMeters: altitudeMeters ?? this.altitudeMeters,
      address: address ?? this.address,
      weather: weather ?? this.weather,
      deviceModel: deviceModel ?? this.deviceModel,
      online: online ?? this.online,
      ntpOffsetMs: ntpOffsetMs ?? this.ntpOffsetMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'capturedAt': capturedAt.toIso8601String(),
        'timeAuthority': timeAuthority.name,
        'coordAuthority': coordAuthority.name,
        'position': position?.toJson(),
        'altitudeMeters': altitudeMeters,
        'address': address,
        'weather': weather?.toJson(),
        'deviceModel': deviceModel,
        'online': online,
        'ntpOffsetMs': ntpOffsetMs,
      };

  static CaptureContext fromJson(Map<String, dynamic> json) {
    return CaptureContext(
      capturedAt: DateTime.tryParse('${json['capturedAt']}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      timeAuthority: _enumByName(TimeAuthority.values, json['timeAuthority']) ??
          TimeAuthority.missing,
      coordAuthority:
          _enumByName(CoordAuthority.values, json['coordAuthority']) ??
              CoordAuthority.missing,
      position: GeoPoint.fromJson(json['position'] as Map<String, dynamic>?),
      altitudeMeters: (json['altitudeMeters'] as num?)?.toDouble(),
      address: json['address'] as String?,
      weather: WeatherSnapshot.fromJson(json['weather'] as Map<String, dynamic>?),
      deviceModel: json['deviceModel'] as String?,
      online: json['online'] == true,
      ntpOffsetMs: (json['ntpOffsetMs'] as num?)?.toInt(),
    );
  }
}

/// 溯源信息：来源、批次、原图信息。导入链路据此禁止"旧图伪造成现场取证图"。
class Provenance {
  const Provenance({
    required this.source,
    required this.batchId,
    required this.importedAt,
    this.originalPath,
    this.originalTakenAt,
    this.hasOriginalGeo = false,
    this.channelDetail,
  });

  factory Provenance.capture({required String batchId, required DateTime at}) {
    return Provenance(
      source: PhotoSource.camera,
      batchId: batchId,
      importedAt: at,
      hasOriginalGeo: false,
      channelDetail: 'camera',
    );
  }

  final PhotoSource source;
  final String batchId;
  final DateTime importedAt;
  final String? originalPath;

  /// 原图 EXIF DateTimeOriginal（导入链路绝不替换成"当前时间"）。
  final DateTime? originalTakenAt;
  final bool hasOriginalGeo;

  /// 通道细节，例如 `photopicker` / `saf` / `action_send`。
  final String? channelDetail;

  bool get isFieldEvidence => source == PhotoSource.camera;

  /// 画面上必须出现的来源标识。拍摄与导入必须明确区分，不可省略。
  String get badgeText => isFieldEvidence ? '现场拍摄' : '导入 · 非现场取证';

  /// 屏幕与画面上都使用的短标签。
  String get shortBadge => isFieldEvidence ? '现场' : '导入';

  Map<String, dynamic> toJson() => {
        'source': source.name,
        'batchId': batchId,
        'importedAt': importedAt.toIso8601String(),
        'originalPath': originalPath,
        'originalTakenAt': originalTakenAt?.toIso8601String(),
        'hasOriginalGeo': hasOriginalGeo,
        'channelDetail': channelDetail,
      };

  static Provenance fromJson(Map<String, dynamic> json) {
    return Provenance(
      source: PhotoSourceX.fromCode(json['source'] as String?),
      batchId: '${json['batchId'] ?? ''}',
      importedAt: DateTime.tryParse('${json['importedAt']}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      originalPath: json['originalPath'] as String?,
      originalTakenAt: DateTime.tryParse('${json['originalTakenAt']}'),
      hasOriginalGeo: json['hasOriginalGeo'] == true,
      channelDetail: json['channelDetail'] as String?,
    );
  }
}

T? _enumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
