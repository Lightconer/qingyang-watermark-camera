import 'package:flutter/foundation.dart';

import '../core/extensions/watermark_field_provider.dart';
import '../engines/image/pipeline.dart';
import '../engines/storage/settings_store.dart';
import 'feature_module.dart';
import 'services.dart';

/// 功能注册表：唯一装配点。
///
/// * 新模块 → `register(Module())`；
/// * 模块自带路由、字段、中间件、设置分区，全部自动汇入；
/// * 关闭某个模块只需在设置里关掉，不影响其它模块运行。
class FeatureRegistry {
  FeatureRegistry({required this.settings});

  final SettingsStore settings;
  final Map<String, FeatureModule> _modules = {};

  List<FeatureModule> get modules => _modules.values.toList(growable: false);

  FeatureModule? byId(String id) => _modules[id];

  void register(FeatureModule module) {
    _modules[module.id] = module;
  }

  bool isEnabled(String id) {
    final module = _modules[id];
    if (module == null) return false;
    return settings.isFeatureEnabled(id, module.enabledByDefault);
  }

  Future<void> setEnabled(String id, bool value) =>
      settings.setFeatureEnabled(id, value);

  List<FeatureModule> get enabledModules =>
      modules.where((module) => isEnabled(module.id)).toList(growable: false);

  List<RouteSpec> get routes => [
        for (final module in enabledModules) ...module.routes,
      ];

  List<WatermarkFieldProvider> get fields => [
        for (final module in enabledModules) ...module.fields,
      ];

  /// 所有中间件按 order 排序后交给管线，order 相同的按注册顺序稳定排序。
  List<ImageMiddleware> get middlewares {
    final collected = <ImageMiddleware>[
      for (final module in enabledModules) ...module.middlewares,
    ];
    collected.sort((a, b) => a.order.compareTo(b.order));
    return collected;
  }

  List<SettingSection> get settingsSections {
    final sections = <SettingSection>[
      for (final module in enabledModules) ...module.settings,
    ];
    sections.sort((a, b) => a.priority.compareTo(b.priority));
    return sections;
  }

  Future<void> initAll(AppServices services) async {
    for (final module in enabledModules) {
      try {
        await module.init(services);
      } catch (error, stack) {
        debugPrint('模块 ${module.id} 初始化失败：$error\n$stack');
      }
    }
  }

  /// 调试用：一览当前装配结果（设置页"关于"里展示）。
  String get summary {
    final names = enabledModules.map((module) => module.id).join('、');
    return '已装配 ${enabledModules.length}/${_modules.length} 个模块（$names）；'
        '字段 ${fields.length} 个；中间件 ${middlewares.length} 个；'
        '路由 ${routes.length} 条';
  }
}
