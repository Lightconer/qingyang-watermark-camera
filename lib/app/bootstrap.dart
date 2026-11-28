import 'package:flutter/widgets.dart';

import '../core/service/attestation.dart';
import '../engines/geocoding/geocoding_engine.dart';
import '../engines/hash/hash_engine.dart';
import '../engines/image/image_codec.dart';
import '../engines/location/location_engine.dart';
import '../engines/media/gallery_export_engine.dart';
import '../engines/media/media_gateway.dart';
import '../engines/metadata/metadata_engine.dart';
import '../engines/storage/settings_store.dart';
import '../engines/storage/storage_engine.dart';
import '../engines/storage/template_store.dart';
import '../engines/time/time_engine.dart';
import '../engines/update/apk_installer.dart';
import '../engines/update/update_engine.dart';
import '../engines/update/update_service.dart';
import '../engines/watermark/watermark_renderer.dart';
import '../engines/weather/weather_engine.dart';
import '../features/feature_modules.dart';
import 'feature_registry.dart';
import 'services.dart';

/// 组装层入口：把引擎、模板、模式、功能模块一次性装配好。
///
/// 顺序很关键：设置 → 模板 → 模式 → 模块注册 → 服务容器 → 模块初始化。
Future<AppServices> bootstrapServices() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = await SettingsStore.load();

  final templates = TemplateStore(settings: settings);
  await templates.load();

  final profiles = await ProfileRepository.load();

  final registry = FeatureRegistry(settings: settings);

  // ---- 模块注册：新增功能只在这里加一行 ----
  registry.register(CaptureFeature());
  registry.register(ImportFeature());
  registry.register(TemplateFeature());
  registry.register(GalleryFeature());
  registry.register(VerifyFeature());
  registry.register(LedgerFeature());
  registry.register(SettingsFeature());

  final geocoding = settings.geocodeEnabled
      ? (settings.amapKey.trim().isEmpty
          ? HttpGeocodingEngine(provider: 'nominatim')
          : HttpGeocodingEngine(provider: 'amap', apiKey: settings.amapKey))
      : const DisabledGeocodingEngine();

  final weather = settings.weatherEnabled
      ? OpenMeteoWeatherEngine() as WeatherEngine
      : const DisabledWeatherEngine();

  final services = AppServices(
    settings: settings,
    storage: FileStorageEngine(),
    codec: const FlutterImageCodec(),
    renderer: const CanvasWatermarkRenderer(),
    hash: const CryptoHashEngine(),
    metadata: MetadataEngine(providers: [
      CameraMetadataProvider(),
      ExifMetadataProvider(),
    ]),
    location: GeolocatorLocationEngine(),
    time: TimeEngine(),
    geocoding: geocoding,
    weather: weather,
    media: PlatformMediaGateway(),
    gallery: GalleryExportService(
      engine: const MediaStoreGalleryExportEngine(),
      isEnabled: () => settings.exportToGallery,
      albumName: () => settings.galleryAlbum,
    ),
    update: UpdateService(
      engine: GitHubUpdateEngine(),
      installer: const NativeApkInstaller(),
      settings: settings,
    ),
    profiles: profiles,
    templates: templates,
    registry: registry,
    attestation: const AttestationService(),
  );

  await registry.initAll(services);
  await settings.setOnboardingDone();
  return services;
}
