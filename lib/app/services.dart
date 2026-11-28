import 'package:flutter/widgets.dart';

import '../core/layout/layout_engine.dart';
import '../core/models/profile_config.dart';
import '../core/service/attestation.dart';
import '../core/service/field_catalog.dart';
import '../engines/geocoding/geocoding_engine.dart';
import '../engines/hash/hash_engine.dart';
import '../engines/image/image_codec.dart';
import '../engines/image/middlewares.dart';
import '../engines/image/pipeline.dart';
import '../engines/location/location_engine.dart';
import '../engines/media/gallery_export_engine.dart';
import '../engines/media/media_gateway.dart';
import '../engines/metadata/metadata_engine.dart';
import '../engines/storage/settings_store.dart';
import '../engines/storage/storage_engine.dart';
import '../engines/storage/template_store.dart';
import '../engines/time/time_engine.dart';
import '../engines/watermark/watermark_renderer.dart';
import '../engines/weather/weather_engine.dart';
import 'feature_registry.dart';

/// 组装层服务容器：所有引擎实例在这里一次性装配好，向下通过构造注入，
/// 向上通过 [ServicesScope] 提供给页面。业务代码不做 `new`，只拿接口。
class AppServices {
  AppServices({
    required this.settings,
    required this.storage,
    required this.codec,
    required this.renderer,
    required this.hash,
    required this.metadata,
    required this.location,
    required this.time,
    required this.geocoding,
    required this.weather,
    required this.media,
    required this.gallery,
    required this.profiles,
    required this.templates,
    required this.registry,
    required this.attestation,
  });

  final SettingsStore settings;
  final StorageEngine storage;
  final ImageCodecEngine codec;
  final WatermarkRenderer renderer;
  final HashEngine hash;
  final MetadataEngine metadata;
  final LocationEngine location;
  final TimeEngine time;
  final GeocodingEngine geocoding;
  final WeatherEngine weather;
  final MediaGateway media;

  /// 相册输出：成品落盘后再复制到系统相册的独立相册（可关）。
  final GalleryExportService gallery;
  final ProfileRegistry profiles;
  final TemplateStore templates;
  final FeatureRegistry registry;
  final AttestationService attestation;

  /// 字段目录 = 内置字段 + 各功能模块注册的字段。
  late final FieldCatalog fields = FieldCatalog([
    ...builtinFieldProviders(),
    ...registry.fields,
  ]);

  final LayoutEngine layout = const LayoutEngine(measure: textPainterMeasure);

  /// 管线 = 默认 8 个中间件 + 各模块注册的中间件，统一按 order 排序。
  late final PipelineRunner pipelineRunner = PipelineRunner([
    ...defaultMiddlewares(maxLongSide: settings.maxLongSide),
    ...registry.middlewares,
  ]);

  late final BatchPipeline batch = BatchPipeline(pipelineRunner);

  PipelineContext createPipelineContext({void Function(String stage)? onStage}) {
    return PipelineContext(
      codec: codec,
      renderer: renderer,
      fields: fields,
      layout: layout,
      hash: hash,
      metadata: metadata,
      onStage: onStage,
    );
  }

  ProfileConfig profileById(String? id) => profiles.byId(id);

  Future<void> dispose() async {
    settings.dispose();
    templates.dispose();
  }
}

/// 通过 InheritedWidget 分发服务，避免在页面里到处传构造参数。
class ServicesScope extends InheritedWidget {
  const ServicesScope({
    super.key,
    required this.services,
    required super.child,
  });

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ServicesScope>();
    assert(scope != null, 'ServicesScope 未挂载：请检查 app 根节点');
    return scope!.services;
  }

  static AppServices? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ServicesScope>()?.services;

  @override
  bool updateShouldNotify(ServicesScope oldWidget) =>
      oldWidget.services != services;
}
