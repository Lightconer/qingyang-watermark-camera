import 'package:flutter/widgets.dart';

import '../core/extensions/watermark_field_provider.dart';
import '../engines/image/pipeline.dart';
import 'services.dart';

/// 路由描述：只声明"名字 + 构建器"，由 [FeatureRegistry] 汇总给 Router。
class RouteSpec {
  const RouteSpec({required this.name, required this.builder, this.title});

  final String name;
  final WidgetBuilder builder;
  final String? title;
}

/// 设置页分区描述：各模块把自己的设置块插进设置页，不改设置页本身。
class SettingSection {
  const SettingSection({
    required this.id,
    required this.title,
    required this.builder,
    this.priority = 100,
  });

  final String id;
  final String title;
  final WidgetBuilder builder;
  final int priority;
}

/// 扩展点五：业务功能模块化。
///
/// 新增一个业务单元（例如"执法文书导出"）= 新增一个文件实现本接口，
/// 然后在 `app/bootstrap.dart` 里 `registry.register(XxxModule())`。
/// 不需要改动 AppShell、Router、设置页或任何既有模块的主流程。
abstract class FeatureModule {
  String get id;

  /// 默认是否启用（用户可在设置里关闭）。
  bool get enabledByDefault => true;

  /// 本模块提供的页面。
  List<RouteSpec> get routes => const [];

  /// 本模块新增的水印字段（扩展点一）。
  List<WatermarkFieldProvider> get fields => const [];

  /// 本模块新增的图像中间件（扩展点二），按 order 插入管线。
  List<ImageMiddleware> get middlewares => const [];

  /// 本模块在设置页的独立分区。
  List<SettingSection> get settings => const [];

  /// 启动时初始化（例如申请静默缓存、注册后台任务）。
  Future<void> init(AppServices services) async {}
}
