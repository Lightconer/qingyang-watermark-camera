import 'types.dart';

/// 时间口径。
enum TimePolicyKind {
  /// 必须可信授时（NTP）。缺失时降级为系统时间并强制标注。
  trustedRequired,

  /// 导入链路：只认原图 EXIF DateTimeOriginal，禁止用当前时间替代。
  originalOnly,

  /// 有则用，无则标注未知。
  anyAvailable,
}

/// 坐标口径。
enum CoordPolicyKind {
  /// 必须设备定位（北斗/GPS/网络融合）。
  deviceFixRequired,

  /// 导入链路：只认原图 EXIF GPS，禁止手填坐标。
  originalOnly,

  /// 有则显示，无则标注"无原始定位"。
  optional,
}

/// 扩展点四：模式配置化。
///
/// 取证 / 加工 / 自由三种模式的差异全部由本数据描述，代码中不写
/// `if (mode == CaptureMode.forensics)` 这类分支。新增模式只需新增一个 JSON。
class ProfileConfig {
  const ProfileConfig({
    required this.id,
    required this.label,
    required this.timePolicy,
    required this.coordPolicy,
    this.allowedFields,
    this.requireProvenanceBadge = true,
    this.allowMetaEditing = false,
    this.weatherAllowed = false,
    this.shutterLocked = false,
    this.description = '',
  });

  final String id;
  final String label;
  final TimePolicyKind timePolicy;
  final CoordPolicyKind coordPolicy;

  /// 允许出现的字段白名单；null 表示不限制。
  final Set<String>? allowedFields;

  /// 画面上是否必须出现来源标识（现场拍摄 / 导入）。
  final bool requireProvenanceBadge;

  /// 是否允许在导出前修改元数据（时间、坐标一律禁止手填，见 [manualEntryForbidden]）。
  final bool allowMetaEditing;

  /// 天气是否可上水印。
  final bool weatherAllowed;

  /// 快门一旦触发即锁定上下文，不允许回填。
  final bool shutterLocked;
  final String description;

  /// 硬约束：任何模式都不得提供手动输入时间/经纬度的入口。
  bool get manualEntryForbidden => true;

  bool allowsField(String fieldId) =>
      allowedFields == null || allowedFields!.contains(fieldId);

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'timePolicy': timePolicy.name,
        'coordPolicy': coordPolicy.name,
        'allowedFields': allowedFields?.toList(growable: false),
        'requireProvenanceBadge': requireProvenanceBadge,
        'allowMetaEditing': allowMetaEditing,
        'weatherAllowed': weatherAllowed,
        'shutterLocked': shutterLocked,
        'description': description,
      };

  static ProfileConfig? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final rawAllowed = json['allowedFields'];
    Set<String>? allowed;
    if (rawAllowed is List) {
      allowed = rawAllowed.whereType<String>().toSet();
    }
    return ProfileConfig(
      id: id,
      label: '${json['label'] ?? id}',
      timePolicy: TimePolicyKind.values.firstWhere(
        (value) => value.name == json['timePolicy'],
        orElse: () => TimePolicyKind.anyAvailable,
      ),
      coordPolicy: CoordPolicyKind.values.firstWhere(
        (value) => value.name == json['coordPolicy'],
        orElse: () => CoordPolicyKind.optional,
      ),
      allowedFields: allowed,
      requireProvenanceBadge: json['requireProvenanceBadge'] as bool? ?? true,
      allowMetaEditing: json['allowMetaEditing'] as bool? ?? false,
      weatherAllowed: json['weatherAllowed'] as bool? ?? false,
      shutterLocked: json['shutterLocked'] as bool? ?? false,
      description: '${json['description'] ?? ''}',
    );
  }

  /// 内置兜底模式：任何情况下都必须有一个可用 mode。
  static const ProfileConfig fallback = ProfileConfig(
    id: 'free',
    label: '自由',
    timePolicy: TimePolicyKind.anyAvailable,
    coordPolicy: CoordPolicyKind.optional,
    requireProvenanceBadge: true,
    weatherAllowed: true,
    description: '兜底模式：不限制字段，离线可用。',
  );

  /// 与旧枚举的兼容映射，仅用于 UI 图标等场景。
  CaptureMode get mode {
    switch (id) {
      case 'forensics':
        return CaptureMode.forensics;
      case 'processed':
        return CaptureMode.processed;
      default:
        return CaptureMode.free;
    }
  }
}

/// 模式注册表：新增模式只加载一个新 JSON，不动任何分支逻辑。
class ProfileRegistry {
  ProfileRegistry(Iterable<ProfileConfig> configs)
      : _byId = {for (final config in configs) config.id: config};

  final Map<String, ProfileConfig> _byId;

  List<ProfileConfig> get all => _byId.values.toList(growable: false);

  ProfileConfig byId(String? id) =>
      _byId[id] ?? _byId[ProfileConfig.fallback.id] ?? ProfileConfig.fallback;

  bool contains(String id) => _byId.containsKey(id);

  ProfileRegistry merge(Iterable<ProfileConfig> extra) {
    return ProfileRegistry([..._byId.values, ...extra]);
  }
}
