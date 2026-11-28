import '../models/photo_metadata.dart';
import '../models/template.dart';
import '../models/types.dart';
import '../policy/heading.dart';

/// 采集人 / 单位等可配置身份信息，来自设置页或模板取值。
class IdentityInfo {
  const IdentityInfo({
    this.operatorName = '',
    this.organization = '',
    this.projectName = '',
    this.note = '',
    this.logoPath,
  });

  final String operatorName;
  final String organization;
  final String projectName;
  final String note;
  final String? logoPath;

  bool get isEmpty =>
      operatorName.isEmpty &&
      organization.isEmpty &&
      projectName.isEmpty &&
      note.isEmpty;

  IdentityInfo copyWith({
    String? operatorName,
    String? organization,
    String? projectName,
    String? note,
    String? logoPath,
  }) {
    return IdentityInfo(
      operatorName: operatorName ?? this.operatorName,
      organization: organization ?? this.organization,
      projectName: projectName ?? this.projectName,
      note: note ?? this.note,
      logoPath: logoPath ?? this.logoPath,
    );
  }
}

/// 字段解析上下文：字段插件只能读取这里的内容，不能访问文件系统或网络。
class FieldContext {
  const FieldContext({
    required this.mode,
    required this.provenance,
    required this.capture,
    required this.template,
    this.original = PhotoMetadata.unknown,
    this.identity = const IdentityInfo(),
    this.fingerprint,
    this.weatherAllowed = false,
    this.headingFormat = HeadingFormat.cardinal8,
  });

  final CaptureMode mode;
  final Provenance provenance;
  final CaptureContext capture;
  final TemplateConfig template;

  /// 原图元数据（导入链路使用；拍摄链路为 unknown）。
  final PhotoMetadata original;
  final IdentityInfo identity;

  /// 内容指纹，仅第二遍绘制时可用；为 null 时 hash 字段不可用。
  final String? fingerprint;

  /// 天气是否允许出现在水印上（导入模式与离线模式默认关闭）。
  final bool weatherAllowed;

  /// 方位角的展示口径（八方位 / 十六方位 / 仅角度），来自设置页。
  final HeadingFormat headingFormat;

  bool get isImport => provenance.source.isImport;

  /// 当前生效坐标：拍摄取冻结坐标，导入只取原图 EXIF GPS（绝不接受手填）。
  GeoPoint? get activePosition =>
      isImport ? original.gps : capture.position;

  double? get activeAltitude =>
      isImport ? original.altitudeMeters : capture.altitudeMeters;

  /// 原图没有 GPS 时，导入链路必须显示"无原始定位"。
  bool get lacksOriginalGeo => isImport && !original.hasGps;

  bool get hasPosition {
    final point = activePosition;
    return point != null && point.isValid;
  }

  /// 展示用时间：拍摄=NTP 冻结时间；导入=原图 DateTimeOriginal（绝不使用"当前时间"）。
  DateTime? get effectiveTime {
    if (isImport) return original.takenAt;
    if (capture.timeAuthority == TimeAuthority.missing) return null;
    return capture.capturedAt;
  }

  TimeAuthority get effectiveTimeAuthority =>
      isImport ? TimeAuthority.originalExif : capture.timeAuthority;

  CoordAuthority get effectiveCoordAuthority =>
      isImport ? CoordAuthority.originalExif : capture.coordAuthority;

  /// 离线采集必须带上的补充说明，绝不吞掉。
  bool get needsOfflineNotice =>
      !isImport && !capture.online && capture.timeAuthority == TimeAuthority.system;

  FieldContext withFingerprint(String value) {
    return FieldContext(
      mode: mode,
      provenance: provenance,
      capture: capture,
      template: template,
      original: original,
      identity: identity,
      fingerprint: value,
      weatherAllowed: weatherAllowed,
      headingFormat: headingFormat,
    );
  }
}

/// 字段解析结果，交给排版引擎做几何计算。
class ResolvedField {
  const ResolvedField({
    required this.id,
    required this.label,
    required this.text,
    required this.priority,
    this.emphasize = false,
  });

  final String id;
  final String label;
  final String text;
  final int priority;

  /// 主字段（时间/经纬度/地址）使用更大字号。
  final bool emphasize;

  ResolvedField copyWith({String? text}) => ResolvedField(
        id: id,
        label: label,
        text: text ?? this.text,
        priority: priority,
        emphasize: emphasize,
      );
}

/// 扩展点一：水印字段插件。
///
/// 新增「项目编号」「车牌号」「传感器读数」等字段时，只需新增一个实现类并在
/// FeatureModule.fields 中注册，不修改渲染器、排版引擎与任何页面。
abstract class WatermarkFieldProvider {
  /// 全局唯一 id，用于模板字段开关与设置持久化。
  String get id;

  /// 中文标签，设置页与模板编辑器展示用。
  String get label;

  /// 排序权重，数值越小越靠前（时间=10，经纬度=20 ...）。
  int get priority;

  /// 当前上下文是否可提供值。返回 false 时该字段整体不绘制。
  bool isAvailable(FieldContext ctx);

  /// 解析为待绘制字段。返回 null 等价于不可用。
  ResolvedField? resolve(FieldContext ctx);
}
