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
import '../../engines/image/pipeline.dart';
import '../../engines/location/location_engine.dart';
import '../../engines/media/gallery_export_engine.dart';
import '../../engines/sensor/compass_engine.dart';
import '../../engines/storage/ledger_store.dart';
import '../../engines/storage/storage_engine.dart';
import '../../core/policy/heading.dart';

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
  double _maxZoom = 1;
  bool _flashOn = false;
  bool _flashAvailable = true;
  bool _gridOn = true;
  bool _weatherLoading = false;
  String? _errorHint;

  // ---- 朝向 ----
  CompassReading? _heading;
  bool _compassSupported = false;
  StreamSubscription<CompassReading>? _compassSub;

  StreamSubscription<LocationFix>? _locationSub;
  Timer? _ntpTimer;

  CameraController? get camera => _camera;
  bool get initializing => _initializing;
  bool get busy => _busy;
  bool get recording => _recording;
  String? get error => _error;

  /// 相机失败时的处置建议（缺权限 / 被别的应用占用 / 无摄像头）。
  String? get errorHint => _errorHint;
  String get status => _status;

  /// 最近一次相册写入结果：拍摄页据此提示"已存入相册 / 缺权限"，不做硬失败。
  GalleryExportResult? get lastGallery => _lastGallery;
  GalleryExportResult? _lastGallery;
  LocationFix? get fix => _fix;
  DateTime? get fixAt => _fixAt;
  String? get address => _address;
  bool get fixFailed => _fixFailed;
  bool get online => _online;
  double get zoom => _zoom;
  double get maxZoom => _maxZoom;
  bool get flashOn => _flashOn;

  /// 当前摄像头是否有可用闪光灯（前置摄像头通常没有）。
  bool get flashAvailable => _flashAvailable;
  bool get canSwitchCamera => _cameras.length > 1;
  bool get gridOn => _gridOn;
  bool get weatherLoading => _weatherLoading;

  /// 设备是否具备方向传感器。
  bool get compassSupported => _compassSupported;

  /// 屏幕上展示的朝向文案；无传感器或未开启时为 null（不显示，不编造）。
  String? get headingLabel {
    if (!services.settings.compassEnabled) return null;
    final reading = _heading;
    if (reading == null || !reading.isValid) return null;
    final text = HeadingPolicy.format(
      reading.degrees,
      style: services.settings.headingFormat,
    );
    return text.isEmpty ? null : text;
  }

  TemplateConfig get template => services.templates.byId(services.settings.lastTemplateId);
  ProfileConfig get profile => services.profiles.byId(template.profileId);

  Future<void> initialize() async {
    if (_initializing) return;
    _initializing = true;
    _error = null;
    _errorHint = null;
    notifyListeners();
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _error = '未检测到可用摄像头';
        _errorHint = '这台设备没有上报任何摄像头；模拟器请先配置虚拟摄像头。';
        return;
      }
      _cameraIndex = _cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      if (_cameraIndex < 0) _cameraIndex = 0;
      await _bindCamera(_cameras[_cameraIndex]);
      unawaited(_startLocation());
      unawaited(_syncTime());
      unawaited(_startCompass());
      _ntpTimer = Timer.periodic(const Duration(minutes: 5), (_) => _syncTime());
      _status = '预览已就绪';
    } catch (error) {
      _classifyCameraError(error);
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  /// 相机初始化失败的原因分类。
  ///
  /// 各厂商抛出的异常文案不统一，"相机初始化失败：xxx"这种原文对人没用；
  /// 这里翻译成"接下来该做什么"，并给一条可执行的建议。
  void _classifyCameraError(Object error) {
    final raw = '$error';
    final lower = raw.toLowerCase();
    if (lower.contains('permission') || lower.contains('denied')) {
      _error = '未获得相机权限';
      _errorHint = '到系统设置 → 应用 → ${AppIdentity.appName} → 权限，打开「相机」后重试。';
    } else if (lower.contains('in use') || lower.contains('occupied')) {
      _error = '摄像头被其他应用占用';
      _errorHint = '关掉正在使用相机的应用（视频通话、扫码、其他相机）后点重试。';
    } else if (lower.contains('no camera') || lower.contains('not found')) {
      _error = '没有找到可用摄像头';
      _errorHint = '请确认设备摄像头未被系统禁用。';
    } else {
      _error = '相机初始化失败：$raw';
      _errorHint = '可尝试退出重进；若持续失败，把这段提示反馈给我们。';
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
    // 只有后置摄像头通常带闪光灯；前置/外接摄像头上把按钮置灰，
    // 比"点了没反应"更诚实。
    _flashAvailable = description.lensDirection == CameraLensDirection.back;
    _flashOn = false;
    // 闪光灯与变焦分开 try：有些机型只拒绝其中一项，
    // 合在一起会把"能变焦但闪光灯不可用"的设备误判成不支持变焦。
    if (_flashAvailable) {
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {
        _flashAvailable = false;
      }
    }
    try {
      await controller.setZoomLevel(1);
      // 缩放上限由平台上报（0.11 起改为异步查询），失败按 1x 处理即禁用缩放条。
      _maxZoom = await controller.getMaxZoomLevel();
    } catch (_) {
      // 部分设备不支持设置，忽略
      _maxZoom = 1;
    }
    if (!_maxZoom.isFinite || _maxZoom < 1) _maxZoom = 1;
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
    if (!_flashAvailable) return;
    if (controller == null || !controller.value.isInitialized) return;
    _flashOn = !_flashOn;
    try {
      await controller.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    } catch (_) {
      // 该设备声称有闪光灯但拒绝切换到常亮（部分机型只允许拍照瞬间闪光）：
      // 保持"关"，并把按钮降级为不可用，避免反复误触。
      _flashOn = false;
      _flashAvailable = false;
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

  /// 启动朝向采集。
  ///
  /// 传感器不是拍摄的必要条件：取不到就一直保持"朝向未知"，
  /// 水印不画方位角这一行，绝不用 0° 顶替。
  Future<void> _startCompass() async {
    if (!services.settings.compassEnabled) {
      _compassSupported = false;
      notifyListeners();
      return;
    }
    final supported = await services.compass.probe();
    _compassSupported = supported;
    if (!supported) {
      _heading = null;
      notifyListeners();
      return;
    }
    // 先取一次静态值，避免订阅到第一帧读数之前水印缺行。
    final immediate = await services.compass.read();
    if (immediate != null) {
      _heading = immediate;
      notifyListeners();
    }
    await _compassSub?.cancel();
    _compassSub = services.compass.stream.listen(
      (reading) {
        _heading = reading;
        notifyListeners();
      },
      onError: (_) {
        _compassSupported = false;
        notifyListeners();
      },
    );
  }

  /// 设置里开关朝向后即时生效，不必重启应用。
  Future<void> refreshCompass() async {
    await _compassSub?.cancel();
    _compassSub = null;
    _heading = null;
    await _startCompass();
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

  /// 快门瞬间冻结上下文：时间、坐标、地址、天气、朝向一次锁定，之后不再变化。
  ///
  /// 朝向也要冻结：用户按下快门后再转身，不能让水印上的方位角跟着变，
  /// 否则照片方向和画面的实际朝向对不上，取证就失效了。
  CaptureContext freezeContext() {
    final now = services.time.now();
    final authority = services.settings.ntpEnabled && now.authority == TimeAuthority.ntp
        ? TimeAuthority.ntp
        : TimeAuthority.system;
    final fix = _fix;
    final heading = services.settings.compassEnabled ? _heading : null;
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
      headingDegrees: heading?.degrees,
      headingAccuracyDegrees: heading?.accuracyDegrees,
      headingAuthority: heading == null
          ? HeadingAuthority.missing
          : HeadingAuthority.sensor,
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
        headingDegrees: context.headingDegrees,
        headingAccuracyDegrees: context.headingAccuracyDegrees,
        headingAuthority: context.headingAuthority,
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
        options: {
          'jpegQuality': services.settings.jpegQuality,
          'headingFormat': services.settings.headingFormat.code,
        },
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

      GalleryExportResult? exported;
      if (!result.skipped) {
        await LedgerStore(services.storage).append(_ledgerEntry(
          job: job,
          result: result,
          originalPath: xfile.path,
        ));

        _status = '正在存入相册…';
        notifyListeners();
        exported = await services.gallery.save(
          path: result.outputPath,
          fileName: p.basename(result.outputPath),
        );
        _lastGallery = exported;
      }

      _status = result.skipped
          ? '已跳过：${result.skipReason ?? '检测到已有水印'}'
          : '${p.basename(result.outputPath)} · ${exported!.describe()}';
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
    // 传感器缺失必须说清楚，否则用户会以为"方位角字段坏了"。
    if (services.settings.compassEnabled && !_compassSupported) {
      result.add('此设备无方向传感器：水印不显示方位角');
    }
    if (services.settings.compassEnabled &&
        _compassSupported &&
        _heading == null) {
      result.add('正在获取朝向：拿到读数后自动显示方位角');
    }
    return result;
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _compassSub?.cancel();
    _ntpTimer?.cancel();
    _camera?.dispose();
    super.dispose();
  }
}
