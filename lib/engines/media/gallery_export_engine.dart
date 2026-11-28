import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/policy/album_policy.dart';

/// 写入系统相册的结果。
enum GalleryExportStatus {
  /// 已写入相册（`uri` 为 MediaStore 的 content uri，legacy 分支为文件路径）。
  saved,

  /// 设置里关掉了「存入系统相册」。
  disabled,

  /// 当前平台没有相册能力（桌面、测试环境）。
  unsupported,

  /// Android 9 及以下缺少 WRITE_EXTERNAL_STORAGE。
  permissionRequired,

  /// 其它失败（文件不存在、ROM 拒绝等），原因见 [GalleryExportResult.detail]。
  failed,
}

class GalleryExportResult {
  const GalleryExportResult(
    this.status, {
    this.uri,
    this.album,
    this.detail,
  });

  const GalleryExportResult.saved({required String uri, required String album})
      : this(GalleryExportStatus.saved, uri: uri, album: album);

  const GalleryExportResult.disabled({String? album})
      : this(GalleryExportStatus.disabled, album: album);

  const GalleryExportResult.unsupported({String? detail})
      : this(GalleryExportStatus.unsupported, detail: detail);

  const GalleryExportResult.permissionRequired({String? detail})
      : this(GalleryExportStatus.permissionRequired, detail: detail);

  const GalleryExportResult.failed(String detail, {String? album})
      : this(GalleryExportStatus.failed, detail: detail, album: album);

  final GalleryExportStatus status;

  /// 写入后的定位符：Android 10+ 为 `content://media/...`，legacy 为绝对路径。
  final String? uri;

  /// 实际写入的相册名（已归一化）。
  final String? album;

  final String? detail;

  bool get isSaved => status == GalleryExportStatus.saved;

  /// 供状态栏/提示使用的短句。
  String describe() {
    switch (status) {
      case GalleryExportStatus.saved:
        return '已存入相册「${album ?? ''}」';
      case GalleryExportStatus.disabled:
        return '仅保存到应用目录（未开启写入相册）';
      case GalleryExportStatus.unsupported:
        return '当前平台不支持写入系统相册';
      case GalleryExportStatus.permissionRequired:
        return '缺少存储权限，未能写入相册';
      case GalleryExportStatus.failed:
        return '写入相册失败：${detail ?? '未知原因'}';
    }
  }
}

/// 相册输出引擎：把成品复制到系统相册的独立相册里。
///
/// 只负责"把一张已经落盘的图片放进系统相册"，不参与渲染、不改像素、
/// 不覆盖应用目录里的成品——应用目录仍是唯一事实源（校验、台账都读它），
/// 相册里的是给系统图库、微信、其它 APP 直接可见的一份副本。
abstract class GalleryExportEngine {
  Future<GalleryExportResult> saveImage({
    required String sourcePath,
    required String fileName,
    required String album,
  });
}

/// Android 实现：走 `MediaStore` 插入（Android 10+ 用 RELATIVE_PATH +
/// IS_PENDING，9 及以下写公共 Pictures 目录后 MediaScanner 登记），
/// 因此不会出现"扫描不到 / 重启后从相册消失"这类问题。
class MediaStoreGalleryExportEngine implements GalleryExportEngine {
  const MediaStoreGalleryExportEngine();

  static const MethodChannel _channel =
      MethodChannel('com.qingyang.watermark/gallery');

  @override
  Future<GalleryExportResult> saveImage({
    required String sourcePath,
    required String fileName,
    required String album,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      return GalleryExportResult.failed('原文件不存在', album: album);
    }
    try {
      final uri = await _channel.invokeMethod<String>('saveImage', {
        'path': sourcePath,
        'name': fileName,
        'album': album,
      });
      if (uri == null || uri.isEmpty) {
        return GalleryExportResult.failed('系统未返回写入结果', album: album);
      }
      return GalleryExportResult.saved(uri: uri, album: album);
    } on MissingPluginException {
      return const GalleryExportResult.unsupported(detail: '缺少原生实现');
    } on PlatformException catch (error) {
      if (error.code == 'permission_required') {
        return GalleryExportResult.permissionRequired(detail: error.message);
      }
      return GalleryExportResult.failed(
        error.message ?? error.code,
        album: album,
      );
    }
  }
}

/// 测试替身：记录调用。前 [failTimes] 次返回 [failStatus]，之后一律成功。
class FakeGalleryExportEngine implements GalleryExportEngine {
  FakeGalleryExportEngine({
    this.failStatus = GalleryExportStatus.failed,
    this.failTimes = 0,
    this.detail,
  });

  /// 失败时返回的状态（`failed` / `permissionRequired` / `unsupported`）。
  GalleryExportStatus failStatus;

  /// 连续失败的次数；0 表示始终成功。
  int failTimes;

  String? detail;

  final List<({String path, String name, String album})> calls = [];

  @override
  Future<GalleryExportResult> saveImage({
    required String sourcePath,
    required String fileName,
    required String album,
  }) async {
    calls.add((path: sourcePath, name: fileName, album: album));
    if (failTimes > 0) {
      failTimes--;
      return GalleryExportResult(failStatus, album: album, detail: detail);
    }
    return GalleryExportResult.saved(
      uri: 'content://media/external/images/media/${calls.length}',
      album: album,
    );
  }
}

/// 相册输出的编排层：读设置 → 归一化相册名 → 调引擎 → 权限缺失时补一次。
///
/// 放在引擎侧而不是页面里，是为了让"拍摄"与"导入"两条链路共用同一套规则，
/// 也让设置开关（完全离线、不写系统相册）只在一处生效。
class GalleryExportService {
  GalleryExportService({
    required this.engine,
    bool Function()? isEnabled,
    String Function()? albumName,
    Future<bool> Function()? requestPermission,
  })  : _isEnabled = isEnabled ?? _alwaysEnabled,
        _albumName = albumName ?? _defaultAlbum,
        _requestPermission = requestPermission;

  final GalleryExportEngine engine;
  final bool Function() _isEnabled;
  final String Function() _albumName;

  /// 权限申请可注入，便于在单测里验证"缺权限 → 补权限后重试一次"。
  final Future<bool> Function()? _requestPermission;

  static bool _alwaysEnabled() => true;
  static String _defaultAlbum() => AlbumPolicy.defaultAlbum;

  /// 当前设置下是否会写相册（页面用来决定是否提示）。
  bool get enabled => _isEnabled();

  /// 目标相册名（已归一化）。
  String get album => AlbumPolicy.normalize(_albumName());

  /// 把 [path] 处的成品放进系统相册。
  Future<GalleryExportResult> save({
    required String path,
    required String fileName,
  }) async {
    final target = album;
    if (!_isEnabled()) {
      return GalleryExportResult.disabled(album: target);
    }
    var result = await engine.saveImage(
      sourcePath: path,
      fileName: fileName,
      album: target,
    );
    if (result.status == GalleryExportStatus.permissionRequired) {
      final granted = await (_requestPermission?.call() ??
          _requestLegacyStoragePermission());
      if (granted) {
        result = await engine.saveImage(
          sourcePath: path,
          fileName: fileName,
          album: target,
        );
      }
    }
    return result;
  }

  /// Android 9 及以下的写外部存储权限；10+ 走 MediaStore，不需要该权限。
  Future<bool> _requestLegacyStoragePermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final current = await Permission.storage.status;
      if (current.isGranted) return true;
      final requested = await Permission.storage.request();
      return requested.isGranted;
    } catch (_) {
      return false;
    }
  }
}
