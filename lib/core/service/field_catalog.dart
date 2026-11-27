import '../extensions/watermark_field_provider.dart';
import '../models/template.dart';
import '../models/types.dart';
import '../policy/policies.dart';

/// 字段池 UI 描述（设置页 / 模板编辑器用）。
class FieldUiItem {
  const FieldUiItem(this.id, this.label, this.group);

  final String id;
  final String label;
  final String group;
}

/// 字段目录：汇总所有已注册的 [WatermarkFieldProvider]，并做口径过滤与排序。
///
/// 这是"新增字段只加实现类"的唯一汇聚点：`app/feature_registry.dart` 把所有模块声明的
/// 字段装配进本目录，渲染器与页面只认 id。
class FieldCatalog {
  FieldCatalog(Iterable<WatermarkFieldProvider> providers)
      : providers = List<WatermarkFieldProvider>.unmodifiable(
          (providers.toList()..sort((a, b) => a.priority.compareTo(b.priority))),
        );

  final List<WatermarkFieldProvider> providers;

  WatermarkFieldProvider? byId(String id) {
    for (final provider in providers) {
      if (provider.id == id) return provider;
    }
    return null;
  }

  /// 解析为可直接排版的字段列表。
  ///
  /// 过滤顺序：模板开关 → 口径白名单 → 可用性 → 插件解析结果。
  List<ResolvedField> resolve(
    FieldContext ctx, {
    required Set<String> enabledFieldIds,
    Set<String>? allowedFieldIds,
  }) {
    final result = <ResolvedField>[];
    for (final provider in providers) {
      if (!enabledFieldIds.contains(provider.id)) continue;
      if (allowedFieldIds != null && !allowedFieldIds.contains(provider.id)) {
        continue;
      }
      if (!provider.isAvailable(ctx)) continue;
      final field = provider.resolve(ctx);
      if (field != null && field.text.trim().isNotEmpty) {
        result.add(field);
      }
    }
    result.sort((a, b) => a.priority.compareTo(b.priority));
    return result;
  }

  /// 设置页展示的字段清单（含样式级元素 qr / logo）。
  List<FieldUiItem> get uiItems {
    final items = <FieldUiItem>[
      for (final provider in providers)
        FieldUiItem(provider.id, provider.label, _groupOf(provider.id)),
      const FieldUiItem(WatermarkFieldIds.qr, '溯源二维码', '溯源'),
      const FieldUiItem(WatermarkFieldIds.logo, 'LOGO', '溯源'),
    ];
    return List<FieldUiItem>.unmodifiable(items);
  }

  static String _groupOf(String id) {
    switch (id) {
      case WatermarkFieldIds.time:
      case WatermarkFieldIds.sourceBadge:
        return '时间与来源';
      case WatermarkFieldIds.coords:
      case WatermarkFieldIds.altitude:
      case WatermarkFieldIds.address:
      case WatermarkFieldIds.weather:
        return '位置与环境';
      case WatermarkFieldIds.device:
        return '设备';
      case WatermarkFieldIds.hash:
        return '溯源';
      default:
        return '业务信息';
    }
  }
}

/// 标准时间（精确到秒）。
class TimeFieldProvider implements WatermarkFieldProvider {
  const TimeFieldProvider();

  @override
  String get id => WatermarkFieldIds.time;

  @override
  String get label => '标准时间';

  @override
  int get priority => 10;

  @override
  bool isAvailable(FieldContext ctx) => true;

  @override
  ResolvedField? resolve(FieldContext ctx) {
    final time = ctx.effectiveTime;
    if (time == null) {
      return const ResolvedField(
        id: WatermarkFieldIds.time,
        label: '标准时间',
        text: '时间未知',
        priority: 10,
        emphasize: true,
      );
    }
    final suffix = ctx.isImport
        ? ''
        : (ctx.capture.timeAuthority == TimeAuthority.ntp
            ? ''
            : ctx.needsOfflineNotice
                ? '（离线采集·本地系统时间）'
                : TimeText.authoritySuffix(ctx.capture.timeAuthority));
    return ResolvedField(
      id: WatermarkFieldIds.time,
      label: '标准时间',
      text: '${TimeText.format(time)}$suffix',
      priority: 10,
      emphasize: true,
    );
  }
}

/// 经纬度。只认设备冻结坐标或原图 EXIF GPS，绝不接受人工输入。
class CoordsFieldProvider implements WatermarkFieldProvider {
  const CoordsFieldProvider();

  @override
  String get id => WatermarkFieldIds.coords;

  @override
  String get label => '经纬度';

  @override
  int get priority => 20;

  @override
  bool isAvailable(FieldContext ctx) => true;

  @override
  ResolvedField? resolve(FieldContext ctx) {
    if (ctx.hasPosition) {
      return ResolvedField(
        id: WatermarkFieldIds.coords,
        label: '经纬度',
        text: '${ctx.activePosition!.toDisplay()}  ${ctx.activePosition!.toDms()}',
        priority: 20,
        emphasize: true,
      );
    }
    if (ctx.lacksOriginalGeo) {
      return const ResolvedField(
        id: WatermarkFieldIds.coords,
        label: '经纬度',
        text: '无原始定位',
        priority: 20,
        emphasize: true,
      );
    }
    return const ResolvedField(
      id: WatermarkFieldIds.coords,
      label: '经纬度',
      text: '定位失败',
      priority: 20,
      emphasize: true,
    );
  }
}

/// 海拔。
class AltitudeFieldProvider implements WatermarkFieldProvider {
  const AltitudeFieldProvider();

  @override
  String get id => WatermarkFieldIds.altitude;

  @override
  String get label => '海拔';

  @override
  int get priority => 30;

  @override
  bool isAvailable(FieldContext ctx) =>
      ctx.activeAltitude != null && ctx.hasPosition;

  @override
  ResolvedField? resolve(FieldContext ctx) {
    final altitude = ctx.activeAltitude;
    if (altitude == null) return null;
    return ResolvedField(
      id: WatermarkFieldIds.altitude,
      label: '海拔',
      text: '海拔 ${altitude.toStringAsFixed(1)} 米',
      priority: 30,
    );
  }
}

/// 详细地址（离线或无解析结果时不编造）。
class AddressFieldProvider implements WatermarkFieldProvider {
  const AddressFieldProvider();

  @override
  String get id => WatermarkFieldIds.address;

  @override
  String get label => '详细地址';

  @override
  int get priority => 40;

  @override
  bool isAvailable(FieldContext ctx) {
    if (ctx.lacksOriginalGeo) return false;
    final address = ctx.capture.address;
    return address != null && address.trim().isNotEmpty;
  }

  @override
  ResolvedField? resolve(FieldContext ctx) {
    final address = ctx.capture.address?.trim();
    if (address == null || address.isEmpty) return null;
    return ResolvedField(
      id: WatermarkFieldIds.address,
      label: '详细地址',
      text: address,
      priority: 40,
      emphasize: true,
    );
  }
}

/// 天气。导入模式默认关闭，离线无数据时不显示。
class WeatherFieldProvider implements WatermarkFieldProvider {
  const WeatherFieldProvider();

  @override
  String get id => WatermarkFieldIds.weather;

  @override
  String get label => '天气';

  @override
  int get priority => 50;

  @override
  bool isAvailable(FieldContext ctx) {
    if (ctx.isImport) return false;
    if (!ctx.weatherAllowed) return false;
    return ctx.capture.weather != null;
  }

  @override
  ResolvedField? resolve(FieldContext ctx) {
    final weather = ctx.capture.weather;
    if (weather == null) return null;
    return ResolvedField(
      id: WatermarkFieldIds.weather,
      label: '天气',
      text: weather.display,
      priority: 50,
    );
  }
}

/// 设备型号。
class DeviceFieldProvider implements WatermarkFieldProvider {
  const DeviceFieldProvider();

  @override
  String get id => WatermarkFieldIds.device;

  @override
  String get label => '设备型号';

  @override
  int get priority => 60;

  @override
  bool isAvailable(FieldContext ctx) => _model(ctx) != null;

  @override
  ResolvedField? resolve(FieldContext ctx) {
    final model = _model(ctx);
    if (model == null) return null;
    return ResolvedField(
      id: WatermarkFieldIds.device,
      label: '设备型号',
      text: '设备 $model',
      priority: 60,
    );
  }

  String? _model(FieldContext ctx) {
    final candidate = ctx.isImport
        ? (ctx.original.model ?? ctx.original.make)
        : ctx.capture.deviceModel;
    if (candidate == null || candidate.trim().isEmpty) return null;
    return candidate.trim();
  }
}

/// 采集人。
class OperatorFieldProvider implements WatermarkFieldProvider {
  const OperatorFieldProvider();

  @override
  String get id => WatermarkFieldIds.operator;

  @override
  String get label => '采集人';

  @override
  int get priority => 70;

  @override
  bool isAvailable(FieldContext ctx) => _value(ctx) != null;

  @override
  ResolvedField? resolve(FieldContext ctx) {
    final value = _value(ctx);
    if (value == null) return null;
    return ResolvedField(
      id: WatermarkFieldIds.operator,
      label: '采集人',
      text: '采集人 $value',
      priority: 70,
    );
  }

  String? _value(FieldContext ctx) {
    final value =
        ctx.template.valueOf(WatermarkFieldIds.operator, fallback: ctx.identity.operatorName);
    return value.isEmpty ? null : value;
  }
}

/// 所属单位。
class OrganizationFieldProvider implements WatermarkFieldProvider {
  const OrganizationFieldProvider();

  @override
  String get id => WatermarkFieldIds.organization;

  @override
  String get label => '所属单位';

  @override
  int get priority => 75;

  @override
  bool isAvailable(FieldContext ctx) => _value(ctx) != null;

  @override
  ResolvedField? resolve(FieldContext ctx) {
    final value = _value(ctx);
    if (value == null) return null;
    return ResolvedField(
      id: WatermarkFieldIds.organization,
      label: '所属单位',
      text: value,
      priority: 75,
    );
  }

  String? _value(FieldContext ctx) {
    final value = ctx.template.valueOf(WatermarkFieldIds.organization,
        fallback: ctx.identity.organization);
    return value.isEmpty ? null : value;
  }
}

/// 项目名称。
class ProjectFieldProvider implements WatermarkFieldProvider {
  const ProjectFieldProvider();

  @override
  String get id => WatermarkFieldIds.project;

  @override
  String get label => '项目名称';

  @override
  int get priority => 80;

  @override
  bool isAvailable(FieldContext ctx) => _value(ctx) != null;

  @override
  ResolvedField? resolve(FieldContext ctx) {
    final value = _value(ctx);
    if (value == null) return null;
    return ResolvedField(
      id: WatermarkFieldIds.project,
      label: '项目名称',
      text: '项目 $value',
      priority: 80,
    );
  }

  String? _value(FieldContext ctx) {
    final value = ctx.template.valueOf(WatermarkFieldIds.project,
        fallback: ctx.identity.projectName);
    return value.isEmpty ? null : value;
  }
}

/// 自定义备注。
class NoteFieldProvider implements WatermarkFieldProvider {
  const NoteFieldProvider();

  @override
  String get id => WatermarkFieldIds.note;

  @override
  String get label => '自定义备注';

  @override
  int get priority => 90;

  @override
  bool isAvailable(FieldContext ctx) => _value(ctx) != null;

  @override
  ResolvedField? resolve(FieldContext ctx) {
    final value = _value(ctx);
    if (value == null) return null;
    return ResolvedField(
      id: WatermarkFieldIds.note,
      label: '自定义备注',
      text: '备注 $value',
      priority: 90,
    );
  }

  String? _value(FieldContext ctx) {
    final value = ctx.template.valueOf(WatermarkFieldIds.note,
        fallback: ctx.identity.note);
    return value.isEmpty ? null : value;
  }
}

/// SHA256 校验小字。只有第二遍绘制（已算出内容指纹）时可用。
class HashFieldProvider implements WatermarkFieldProvider {
  const HashFieldProvider();

  @override
  String get id => WatermarkFieldIds.hash;

  @override
  String get label => 'SHA256 校验小字';

  @override
  int get priority => 95;

  @override
  bool isAvailable(FieldContext ctx) =>
      ctx.fingerprint != null && ctx.fingerprint!.length >= 16;

  @override
  ResolvedField? resolve(FieldContext ctx) {
    final fingerprint = ctx.fingerprint;
    if (fingerprint == null || fingerprint.length < 16) return null;
    return ResolvedField(
      id: WatermarkFieldIds.hash,
      label: 'SHA256 校验小字',
      text: 'SHA256 ${fingerprint.substring(0, 16)}',
      priority: 95,
    );
  }
}

/// 来源标识文字（现场拍摄 / 导入 · 非现场取证）。硬性要求，任何模式都不可关闭。
class SourceBadgeFieldProvider implements WatermarkFieldProvider {
  const SourceBadgeFieldProvider();

  @override
  String get id => WatermarkFieldIds.sourceBadge;

  @override
  String get label => '来源标识';

  @override
  int get priority => 5;

  @override
  bool isAvailable(FieldContext ctx) => true;

  @override
  ResolvedField? resolve(FieldContext ctx) {
    final authority = ctx.isImport
        ? '原图时间'
        : (ctx.capture.timeAuthority == TimeAuthority.ntp ? 'NTP' : '离线');
    return ResolvedField(
      id: WatermarkFieldIds.sourceBadge,
      label: '来源标识',
      text: '${ctx.provenance.badgeText} · $authority',
      priority: 5,
      emphasize: true,
    );
  }
}

/// 内置字段集合。
List<WatermarkFieldProvider> builtinFieldProviders() => const [
      SourceBadgeFieldProvider(),
      TimeFieldProvider(),
      CoordsFieldProvider(),
      AltitudeFieldProvider(),
      AddressFieldProvider(),
      WeatherFieldProvider(),
      DeviceFieldProvider(),
      OperatorFieldProvider(),
      OrganizationFieldProvider(),
      ProjectFieldProvider(),
      NoteFieldProvider(),
      HashFieldProvider(),
    ];
