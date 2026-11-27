import 'types.dart';

/// 水印位置。
enum WatermarkPosition { bottomBar, bottomLeft, bottomRight }

extension WatermarkPositionX on WatermarkPosition {
  String get label {
    switch (this) {
      case WatermarkPosition.bottomBar:
        return '底部通栏';
      case WatermarkPosition.bottomLeft:
        return '左下角';
      case WatermarkPosition.bottomRight:
        return '右下角';
    }
  }

  static WatermarkPosition fromCode(String? code) {
    for (final value in WatermarkPosition.values) {
      if (value.name == code) return value;
    }
    return WatermarkPosition.bottomBar;
  }
}

/// 内置字段 id 常量。新增字段用自定义 id，不需要改动这里。
class WatermarkFieldIds {
  const WatermarkFieldIds._();

  static const String time = 'time';
  static const String coords = 'coords';
  static const String altitude = 'altitude';
  static const String address = 'address';
  static const String weather = 'weather';
  static const String device = 'device';
  static const String operator = 'operator';
  static const String organization = 'organization';
  static const String project = 'project';
  static const String note = 'note';
  static const String logo = 'logo';
  static const String hash = 'hash';
  static const String qr = 'qr';
  static const String sourceBadge = 'source_badge';

  static const List<String> all = [
    time,
    coords,
    altitude,
    address,
    weather,
    device,
    operator,
    organization,
    project,
    note,
    hash,
    qr,
  ];
}

/// 水印样式。所有尺寸均为"相对短边"的比例，保证不同分辨率下视觉一致。
class WatermarkStyle {
  const WatermarkStyle({
    this.position = WatermarkPosition.bottomBar,
    this.fontSizeRatio = 0.030,
    this.minFontSize = 12,
    this.maxFontSize = 64,
    this.color = 0xFFFFFFFF,
    this.strokeColor = 0xCC000000,
    this.strokeWidthRatio = 0.12,
    this.opacity = 1.0,
    this.lineSpacing = 1.15,
    this.paddingRatio = 0.022,
    this.cornerRadiusRatio = 0.012,
    this.bandColor = 0xFF000000,
    this.bandOpacity = 0.38,
    this.showBadge = true,
    this.showQr = false,
    this.qrSizeRatio = 0.11,
    this.showLogo = false,
  });

  final WatermarkPosition position;
  final double fontSizeRatio;
  final double minFontSize;
  final double maxFontSize;
  final int color;
  final int strokeColor;

  /// 描边宽度 = 字号 × 该比例（文字必须带描边，保证强光下可读）。
  final double strokeWidthRatio;
  final double opacity;
  final double lineSpacing;
  final double paddingRatio;
  final double cornerRadiusRatio;
  final int bandColor;
  final double bandOpacity;
  final bool showBadge;
  final bool showQr;
  final double qrSizeRatio;
  final bool showLogo;

  WatermarkStyle copyWith({
    WatermarkPosition? position,
    double? fontSizeRatio,
    double? minFontSize,
    double? maxFontSize,
    int? color,
    int? strokeColor,
    double? strokeWidthRatio,
    double? opacity,
    double? lineSpacing,
    double? paddingRatio,
    double? cornerRadiusRatio,
    int? bandColor,
    double? bandOpacity,
    bool? showBadge,
    bool? showQr,
    double? qrSizeRatio,
    bool? showLogo,
  }) {
    return WatermarkStyle(
      position: position ?? this.position,
      fontSizeRatio: fontSizeRatio ?? this.fontSizeRatio,
      minFontSize: minFontSize ?? this.minFontSize,
      maxFontSize: maxFontSize ?? this.maxFontSize,
      color: color ?? this.color,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidthRatio: strokeWidthRatio ?? this.strokeWidthRatio,
      opacity: opacity ?? this.opacity,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      paddingRatio: paddingRatio ?? this.paddingRatio,
      cornerRadiusRatio: cornerRadiusRatio ?? this.cornerRadiusRatio,
      bandColor: bandColor ?? this.bandColor,
      bandOpacity: bandOpacity ?? this.bandOpacity,
      showBadge: showBadge ?? this.showBadge,
      showQr: showQr ?? this.showQr,
      qrSizeRatio: qrSizeRatio ?? this.qrSizeRatio,
      showLogo: showLogo ?? this.showLogo,
    );
  }

  Map<String, dynamic> toJson() => {
        'position': position.name,
        'fontSizeRatio': fontSizeRatio,
        'minFontSize': minFontSize,
        'maxFontSize': maxFontSize,
        'color': color,
        'strokeColor': strokeColor,
        'strokeWidthRatio': strokeWidthRatio,
        'opacity': opacity,
        'lineSpacing': lineSpacing,
        'paddingRatio': paddingRatio,
        'cornerRadiusRatio': cornerRadiusRatio,
        'bandColor': bandColor,
        'bandOpacity': bandOpacity,
        'showBadge': showBadge,
        'showQr': showQr,
        'qrSizeRatio': qrSizeRatio,
        'showLogo': showLogo,
      };

  static WatermarkStyle fromJson(Map<String, dynamic> json) {
    final defaults = const WatermarkStyle();
    return WatermarkStyle(
      position: WatermarkPositionX.fromCode(json['position'] as String?),
      fontSizeRatio: _d(json['fontSizeRatio'], defaults.fontSizeRatio),
      minFontSize: _d(json['minFontSize'], defaults.minFontSize),
      maxFontSize: _d(json['maxFontSize'], defaults.maxFontSize),
      color: _i(json['color'], defaults.color),
      strokeColor: _i(json['strokeColor'], defaults.strokeColor),
      strokeWidthRatio: _d(json['strokeWidthRatio'], defaults.strokeWidthRatio),
      opacity: _d(json['opacity'], defaults.opacity),
      lineSpacing: _d(json['lineSpacing'], defaults.lineSpacing),
      paddingRatio: _d(json['paddingRatio'], defaults.paddingRatio),
      cornerRadiusRatio:
          _d(json['cornerRadiusRatio'], defaults.cornerRadiusRatio),
      bandColor: _i(json['bandColor'], defaults.bandColor),
      bandOpacity: _d(json['bandOpacity'], defaults.bandOpacity),
      showBadge: json['showBadge'] as bool? ?? defaults.showBadge,
      showQr: json['showQr'] as bool? ?? defaults.showQr,
      qrSizeRatio: _d(json['qrSizeRatio'], defaults.qrSizeRatio),
      showLogo: json['showLogo'] as bool? ?? defaults.showLogo,
    );
  }
}

/// 模板：字段池 + 样式 + 归属模式 + 自定义取值。JSON 化存储、可导入导出、可多套切换。
class TemplateConfig {
  const TemplateConfig({
    required this.id,
    required this.name,
    required this.profileId,
    required this.style,
    required this.enabledFieldIds,
    this.values = const {},
    this.schemaVersion = AppIdentity.schemaVersion,
    this.isBuiltin = false,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String profileId;
  final WatermarkStyle style;
  final Set<String> enabledFieldIds;

  /// 模板级自定义取值（采集人、单位、项目名称、备注等）。
  final Map<String, String> values;
  final String schemaVersion;
  final bool isBuiltin;
  final DateTime? updatedAt;

  bool isFieldEnabled(String fieldId) => enabledFieldIds.contains(fieldId);

  String valueOf(String key, {String fallback = ''}) {
    final value = values[key];
    if (value == null || value.trim().isEmpty) return fallback;
    return value.trim();
  }

  TemplateConfig copyWith({
    String? id,
    String? name,
    String? profileId,
    WatermarkStyle? style,
    Set<String>? enabledFieldIds,
    Map<String, String>? values,
    bool? isBuiltin,
    DateTime? updatedAt,
  }) {
    return TemplateConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      profileId: profileId ?? this.profileId,
      style: style ?? this.style,
      enabledFieldIds: enabledFieldIds ?? this.enabledFieldIds,
      values: values ?? this.values,
      schemaVersion: schemaVersion,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        'profileId': profileId,
        'style': style.toJson(),
        'fields': enabledFieldIds.toList(growable: false),
        'values': values,
        'isBuiltin': isBuiltin,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  /// 解析并做版本迁移（当前仅 1.0，未知版本按 1.0 兼容读取）。
  static TemplateConfig? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final styleJson = json['style'];
    final fields = <String>{};
    final rawFields = json['fields'];
    if (rawFields is List) {
      for (final item in rawFields) {
        if (item is String) fields.add(item);
      }
    }
    if (fields.isEmpty) fields.addAll(WatermarkFieldIds.all);
    final values = <String, String>{};
    final rawValues = json['values'];
    if (rawValues is Map) {
      rawValues.forEach((key, value) {
        if (key is String && value != null) values[key] = '$value';
      });
    }
    return TemplateConfig(
      id: id,
      name: '${json['name'] ?? '未命名模板'}',
      profileId: '${json['profileId'] ?? CaptureMode.forensics.name}',
      style: styleJson is Map<String, dynamic>
          ? WatermarkStyle.fromJson(styleJson)
          : const WatermarkStyle(),
      enabledFieldIds: fields,
      values: values,
      schemaVersion: '${json['schemaVersion'] ?? AppIdentity.schemaVersion}',
      isBuiltin: json['isBuiltin'] == true,
      updatedAt: DateTime.tryParse('${json['updatedAt']}'),
    );
  }
}

double _d(Object? value, double fallback) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

int _i(Object? value, int fallback) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}
