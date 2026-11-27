import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app/services.dart';
import '../../core/models/ledger_entry.dart';
import '../../core/models/pipeline_job.dart';
import '../../core/models/profile_config.dart';
import '../../core/models/template.dart';
import '../../core/models/types.dart';
import '../../core/policy/policies.dart';
import '../../engines/image/pipeline.dart';
import '../../engines/location/location_engine.dart';
import '../../engines/storage/ledger_store.dart';
import '../../engines/storage/storage_engine.dart';

/// 设备型号：优先问原生侧，取不到就用系统版本摘要，绝不空着。
class DeviceInfo {
  const DeviceInfo._();

  static const MethodChannel _channel =
      MethodChannel('com.qingyang.watermark/device');

  static Future<String> resolveModel() async {
    try {
      final model = await _channel.invokeMethod<String>('model');
      if (model != null && model.trim().isNotEmpty) return model.trim();
    } on MissingPluginException {
      // 原生通道未注入，走回退
    } on PlatformException {
      // 同上
    }
    final version = Platform.operatingSystemVersion.replaceAll('\n', ' ');
    final short = version.length > 40 ? version.substring(0, 40) : version;
    return '${Platform.operatingSystem} $short';
  }
}

/// 拍摄链路控制器：预览、冻结上下文、出图、落盘、写台账。
class CaptureController extends ChangeNotifier {
  CaptureController({required this.services});

  final AppServices services;

  CameraController? _camera;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool _initializing = false;
  bool _busy = false;
  bool _recording = false;
  String? _error;
  String _status = '准备就绪';

  LocationFix? _fix;
  DateTime? _fixAt;
  String? _address;
  bool _fixFailed = false;
  bool _online = false;
  double _zoom = 1;
  bool _flashOn = false;
  bool _gridOn = true;
  bool _weatherLoading = false;

  StreamSubscription<LocationFix>? _locationSub;
  Timer? _ntpTimer;

  CameraController? get camera => _camera;
  bool get initializing => _initializing;
  bool get busy => _busy;
  bool get recording => _recording;
  String? get error => _error;
  String get status => _status;
  LocationFix? get fix => _fix;
  DateTime? get fixAt => _fixAt;
  String? get address => _address;
  bool get fixFailed => _fixFailed;
  bool get online => _online;
  double get zoom => _zoom;
  bool get flashOn => _flashOn;
  bool get gridOn => _gridOn;
  bool get weatherLoading => _weatherLoading;

  TemplateConfig get template => services.templates.byId(services.settings.lastTemplateId);
  ProfileConfig get profile => services.profiles.byId(template.profileId);

  Future<void> initialize() async {
    if (_initializing) return;
    _initializing = true;
    notifyListeners();
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _error = '未检测到可用摄像头';
        return;
      }
      _cameraIndex = _cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      if (_cameraIndex < 0) _cameraIndex = 0;
      await _bindCamera(_cameras[_cameraIndex]);
      unawaited(_startLocation());
      unawaited(_syncTime());
      _ntpTimer = Timer.periodic(const Duration(minutes: 5), (_) => _syncTime());
      _status = '预览已就绪';
    } catch (error) {
      _error = '相机初始化失败：$error';
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  Future<void> _bindCamera(CameraDescription description) async {
    final previous = _camera;
    final controller = CameraController(
      description,
      ResolutionPreset.veryHigh,
      enableAudio: true,
    );
    await controller.initialize();
    _camera = controller;
    await previous?.dispose();
    try {
      await controller.setFlashMode(FlashMode.off);
      await controller.setZoomLevel(1);
    } catch (_) {
      // 部分设备不支持设置，忽略
    }
    _zoom = 1;
    notifyListeners();
  }

  Future<void> switchCamera() async {
    if (_cameras.length < 2 || _busy || _recording) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    _status = '切换摄像头';
    notifyListeners();
    await _bindCamera(_cameras[_cameraIndex]);
  }

  Future<void> toggleFlash() async {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) return;
    _flashOn = !_flashOn;
    try {
      await controller.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    } catch (_) {
      _flashOn = false;
    }
    notifyListeners();
  }

  Future<void> setZoom(double value) async {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) return;
    _zoom = value;
    notifyListeners();
    try {
      await controller.setZoomLevel(value);
    } catch (_) {
      // 忽略不支持缩放的设备
    }
  }

  Future<void> toggleGrid() async {
    _gridOn = !_gridOn;
    notifyListeners();
  }

  Future<void> _syncTime() async {
    if (!services.settings.ntpEnabled) {
      services.time.reset();
      _online = false;
      notifyListeners();
      return;
    }
    final result = await services.time.sync();
    _online = result != null;
    notifyListeners();
  }

  Future<void> _startLocation() async {
    final granted = await services.location.ensurePermission();
    if (!granted) {
      _fixFailed = true;
      _status = '未获得精确定位权限，水印将标注「定位失败」';
      notifyListeners();
      return;
    }
    final immediate = await services.location.currentFix();
    if (immediate != null) {
      _applyFix(immediate);
      unawaited(_enrich(immediate));
    } else {
      _fixFailed = true;
      notifyListeners();
    }
    await _locationSub?.cancel();
    _locationSub = services.location.watch().listen(
      (fix) {
        _applyFix(fix);
        unawaited(_enrich(fix));
      },
      onError: (_) {
        _fixFailed = true;
        notifyListeners();
      },
    );
  }

  void _applyFix(LocationFix fix) {
    _fix = fix;
    _fixAt = fix.at;
    _fixFailed = false;
    notifyListeners();
  }

  /// 逆地理与天气只在开关打开时请求，失败就保持空（不编造）。
  Future<void> _enrich(LocationFix fix) async {
    if (!_online) return;
    if (services.settings.geocodeEnabled && services.geocoding.configured) {
      final address = await services.geocoding.reverse(fix.point);
      if (address != null) {
        _address = address;
        notifyListeners();
      }
    }
    if (services.settings.weatherEnabled) {
      _weatherLoading = true;
      notifyListeners();
      final weather = await services.weather.current(fix.point);
      _weatherLoading = false;
      if (weather != null) {
        _weather = weather;
        notifyListeners();
      }
    }
  }

  WeatherSnapshot? _weather;

  /// 快门瞬间冻结上下文：时间、坐标、地址、天气一次锁定，之后不再变化。
  CaptureContext freezeContext() {
    final now = services.time.now();
    final authority = services.settings.ntpEnabled && now.authority == TimeAuthority.ntp
        ? TimeAuthority.ntp
        : TimeAuthority.system;
    final fix = _fix;
    return CaptureContext(
      capturedAt: now.time,
      timeAuthority: authority,
      coordAuthority: fix == null
          ? CoordAuthority.missing
          : (fix.isFused ? CoordAuthority.fused : CoordAuthority.gps),
      position: fix?.point,
      altitudeMeters: fix?.altitudeMeters,
      address: _address,
      weather: services.settings.weatherEnabled ? _weather : null,
      deviceModel: null,
      online: _online,
      ntpOffsetMs: now.offsetMs,
    );
  }

  /// 拍照并出图。返回成品路径；失败返回 null 并写 [status]。
  Future<String?> shoot() async {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) {
      _status = '相机尚未就绪';
      notifyListeners();
      return null;
    }
    if (_busy || _recording) return null;

    _busy = true;
    _status = '正在拍摄…';
    notifyListeners();

    // 快门瞬间冻结，之后的所有异步操作都不再读取实时状态。
    final context = freezeContext();
    final capturedTemplate = template;
    final capturedProfile = profile;
    final batchId = 'B${context.capturedAt.millisecondsSinceEpoch}';

    try {
      final deviceModel = await DeviceInfo.resolveModel();
      final xfile = await controller.takePicture();
      final frozen = CaptureContext(
        capturedAt: context.capturedAt,
        timeAuthority: context.timeAuthority,
        coordAuthority: context.coordAuthority,
        position: context.position,
        altitudeMeters: context.altitudeMeters,
        address: context.address,
        weather: context.weather,
        deviceModel: deviceModel,
        online: context.online,
        ntpOffsetMs: context.ntpOffsetMs,
      );

      final outputPath = await services.storage.outputPath(
        date: frozen.capturedAt,
        source: PhotoSource.camera,
        fileName: FileNaming.capture(frozen.capturedAt),
      );

      final job = PipelineJob(
        id: batchId,
        inputPath: xfile.path,
        outputPath: outputPath,
        template: capturedTemplate,
        profile: capturedProfile,
        capture: frozen,
        provenance: Provenance.capture(batchId: batchId, at: frozen.capturedAt),
        identity: services.settings.identity,
        options: {'jpegQuality': services.settings.jpegQuality},
      );

      _status = '正在绘制水印…';
      notifyListeners();

      final result = await services.pipelineRunner.run(
        job,
        services.createPipelineContext(),
      );

      if (services.settings.saveOriginal) {
        final originalTarget = await services.storage.originalPath(
          date: frozen.capturedAt,
          source: PhotoSource.camera,
          fileName: p.basename(xfile.path),
        );
        await File(xfile.path).copy(originalTarget);
      }

      if (!result.skipped) {
        await LedgerStore(services.storage).append(_ledgerEntry(
          job: job,
          result: result,
          originalPath: xfile.path,
        ));
      }

      _status = result.skipped
          ? '已跳过：${result.skipReason ?? '检测到已有水印'}'
          : '已保存 ${p.basename(result.outputPath)}';
      return result.skipped ? null : result.outputPath;
    } catch (error) {
      _status = '拍摄失败：$error';
      _error = '$error';
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  LedgerEntry _ledgerEntry({
    required PipelineJob job,
    required PipelineResult result,
    required String originalPath,
  }) {
    final identity = services.settings.identity;
    final template = job.template;
    return LedgerEntry(
      fileName: p.basename(result.outputPath),
      outputPath: result.outputPath,
      originalPath: originalPath,
      source: job.source,
      templateId: template.id,
      mode: job.mode,
      sha256: result.pixelSha256,
      processedAt: DateTime.now(),
      capturedAt: job.capture.capturedAt,
      position: job.capture.position,
      altitudeMeters: job.capture.altitudeMeters,
      address: job.capture.address,
      note: template.valueOf(WatermarkFieldIds.note, fallback: identity.note),
      operatorName: identity.operatorName,
      organization: identity.organization,
      timeAuthority: job.isImport
          ? TimeAuthority.originalExif
          : job.capture.timeAuthority,
      coordAuthority: job.isImport
          ? CoordAuthority.originalExif
          : job.capture.coordAuthority,
      fingerprint: result.fingerprint,
    );
  }

  /// 录制视频：画面叠加水印，并在结束时写同目录 sidecar 记录冻结上下文。
  ///
  /// 帧级烧录需要 MediaCodec 重编码，当前版本先落 sidecar + 首帧海报，
  /// README「已知限制」中已明确说明。
  Future<void> startVideo() async {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized || _recording) return;
    try {
      await controller.startVideoRecording();
      _recording = true;
      _status = '正在录制…';
    } catch (error) {
      _status = '录制失败：$error';
    }
    notifyListeners();
  }

  Future<String?> stopVideo() async {
    final controller = _camera;
    if (controller == null || !_recording) return null;
    try {
      final context = freezeContext();
      final xfile = await controller.stopVideoRecording();
      _recording = false;
      final path = await services.storage.outputPath(
        date: context.capturedAt,
        source: PhotoSource.camera,
        fileName: 'QY_${context.capturedAt.millisecondsSinceEpoch}.mp4',
      );
      await File(xfile.path).copy(path);
      final sidecar = File('$path.json');
      await sidecar.writeAsString(_sidecarJson(context), flush: true);
      _status = '视频已保存 ${p.basename(path)}';
      notifyListeners();
      return path;
    } catch (error) {
      _recording = false;
      _status = '停止录制失败：$error';
      notifyListeners();
      return null;
    }
  }

  String _sidecarJson(CaptureContext context) {
    final map = context.toJson();
    map['videoWatermark'] = 'overlay-only-beta';
    map['note'] = '视频水印目前为预览叠加 + sidecar 记录，帧级烧录待接入 MediaCodec。';
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// 供页面显示的口径提示（离线、定位失败等）。
  List<String> get notices {
    final result = <String>[];
    if (!_online) result.add('离线采集：时间为本地系统时间');
    if (_fixFailed || _fix == null) result.add('定位失败：水印将标注「定位失败」');
    if (_address == null && services.settings.geocodeEnabled) {
      result.add('地址未解析：画面上不显示地址');
    }
    return result;
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _ntpTimer?.cancel();
    _camera?.dispose();
    super.dispose();
  }
}
