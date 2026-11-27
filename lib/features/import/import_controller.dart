import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../app/services.dart';
import '../../core/models/ledger_entry.dart';
import '../../core/models/photo_metadata.dart';
import '../../core/models/pipeline_job.dart';
import '../../core/models/profile_config.dart';
import '../../core/models/template.dart';
import '../../core/models/types.dart';
import '../../engines/image/pipeline.dart';
import '../../engines/media/media_gateway.dart';
import '../../engines/storage/ledger_store.dart';
import '../../engines/storage/storage_engine.dart';

enum ImportStage { pending, running, done, skipped, failed }

class ImportItem {
  ImportItem({
    required this.path,
    required this.metadata,
    required this.template,
    required this.channel,
  });

  final String path;
  final PhotoMetadata metadata;
  final String channel;
  TemplateConfig template;

  ImportStage stage = ImportStage.pending;
  String? message;
  String? outputPath;
  String? sha256;

  String get fileName => p.basename(path);

  bool get hasOriginalGeo => metadata.hasGps;

  String get timeLabel {
    final taken = metadata.takenAt;
    if (taken == null) return '无原始时间';
    final local = taken.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

/// 导入链路控制器：多入口选择 → 网格预览 → 批量执行 → 失败重试。
class ImportController extends ChangeNotifier {
  ImportController({required this.services, required this.channel});

  final AppServices services;
  final String channel;

  final List<ImportItem> items = [];
  bool _loading = false;
  bool _processing = false;
  int _done = 0;
  int _failed = 0;
  int _skipped = 0;
  String _current = '';

  bool get loading => _loading;
  bool get processing => _processing;
  int get total => items.length;
  int get doneCount => _done;
  int get failedCount => _failed;
  int get skippedCount => _skipped;
  String get currentStage => _current;

  double get progress => items.isEmpty ? 0 : (_done + _failed + _skipped) / items.length;

  List<TemplateConfig> get templates => services.templates.templates;

  TemplateConfig get uniformTemplate => services.templates.active;

  /// 选择文件并读取原图元数据。
  Future<int> load(Future<MediaPickOutcome> Function() picker) async {
    _loading = true;
    notifyListeners();
    try {
      final outcome = await picker();
      _resetCounters();
      for (final path in outcome.paths) {
        if (items.any((item) => item.path == path)) continue;
        final metadata = await services.metadata.readFile(path);
        items.add(ImportItem(
          path: path,
          metadata: metadata,
          template: services.templates.active,
          channel: outcome.channel.isEmpty ? channel : outcome.channel,
        ));
      }
      return outcome.paths.length;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void remove(String path) {
    items.removeWhere((item) => item.path == path);
    notifyListeners();
  }

  void clear() {
    items.clear();
    _resetCounters();
    notifyListeners();
  }

  void applyTemplateToAll(TemplateConfig template) {
    for (final item in items) {
      if (item.stage == ImportStage.done) continue;
      item.template = template;
    }
    notifyListeners();
  }

  void setItemTemplate(ImportItem item, TemplateConfig template) {
    item.template = template;
    notifyListeners();
  }

  void _resetCounters() {
    _done = 0;
    _failed = 0;
    _skipped = 0;
    _current = '';
  }

  /// 批量执行。失败项保留状态，可调用 [retryFailed] 重跑。
  Future<void> processAll({bool onlyFailed = false}) async {
    if (_processing || items.isEmpty) return;
    _processing = true;
    _current = '准备执行';
    notifyListeners();

    try {
      final targets = onlyFailed
          ? items.where((item) => item.stage == ImportStage.failed).toList()
          : items.where((item) => item.stage != ImportStage.done).toList();
      if (onlyFailed) _resetCounters();

      final now = DateTime.now();
      final batchId = 'I${now.millisecondsSinceEpoch}';
      final jobs = <PipelineJob>[];
      final jobItems = <String, ImportItem>{};

      for (final item in targets) {
        final profile = services.profiles.byId(item.template.profileId);
        final job = await _buildJob(item, profile, batchId, now);
        jobs.add(job);
        jobItems[job.id] = item;
      }

      final outcome = await services.batch.runAll(
        jobs,
        services.createPipelineContext(onStage: (stage) {
          _current = stage;
          notifyListeners();
        }),
        onProgress: (progress) {
          final item = jobItems[progress.job.id];
          if (item == null) return;
          switch (progress.status) {
            case BatchStageStatus.running:
              item.stage = ImportStage.running;
              item.message = progress.stage;
              break;
            case BatchStageStatus.done:
              item.stage = ImportStage.done;
              item.outputPath = progress.result?.outputPath;
              item.sha256 = progress.result?.pixelSha256;
              item.message = '已完成';
              _done++;
              break;
            case BatchStageStatus.skipped:
              item.stage = ImportStage.skipped;
              item.message = progress.result?.skipReason ?? '已跳过';
              _skipped++;
              break;
            case BatchStageStatus.failed:
              item.stage = ImportStage.failed;
              item.message = '${progress.error}';
              _failed++;
              break;
            case BatchStageStatus.pending:
              break;
          }
          notifyListeners();
        },
      );

      // 写台账（仅成功的条目）。
      final ledger = LedgerStore(services.storage);
      for (final result in outcome.results) {
        final item = jobItems[result.job.id];
        if (item == null || result.skipped) continue;
        await ledger.append(_ledgerEntry(result, item));
      }
      _current = '批量完成：成功 ${outcome.results.length}，失败 ${outcome.failures.length}';
    } finally {
      _processing = false;
      notifyListeners();
    }
  }

  Future<void> retryFailed() => processAll(onlyFailed: true);

  Future<PipelineJob> _buildJob(
    ImportItem item,
    ProfileConfig profile,
    String batchId,
    DateTime now,
  ) async {
    final metadata = item.metadata;
    final takenAt = metadata.takenAt;
    final address = await _reverseGeocode(metadata);

    final context = CaptureContext(
      capturedAt: takenAt ?? now,
      timeAuthority:
          takenAt == null ? TimeAuthority.missing : TimeAuthority.originalExif,
      coordAuthority: metadata.hasGps ? CoordAuthority.originalExif : CoordAuthority.missing,
      position: metadata.gps,
      altitudeMeters: metadata.altitudeMeters,
      address: address,
      weather: null,
      deviceModel: metadata.model ?? metadata.make,
      online: address != null,
    );

    final provenance = Provenance(
      source: _sourceOf(item.channel),
      batchId: batchId,
      importedAt: now,
      originalPath: item.path,
      originalTakenAt: takenAt,
      hasOriginalGeo: metadata.hasGps,
      channelDetail: item.channel,
    );

    final outputPath = await services.storage.outputPath(
      date: now,
      source: provenance.source,
      fileName: FileNaming.importName(item.path),
    );

    return PipelineJob(
      id: '${provenance.source.code}_${item.path.hashCode}_${now.microsecondsSinceEpoch}',
      inputPath: item.path,
      outputPath: outputPath,
      template: item.template,
      profile: profile,
      capture: context,
      provenance: provenance,
      originalMeta: metadata,
      identity: services.settings.identity,
      options: {
        'jpegQuality': services.settings.jpegQuality,
        'importMode': true,
      },
    );
  }

  PhotoSource _sourceOf(String channel) {
    switch (channel) {
      case ImportChannel.folder:
        return PhotoSource.folder;
      case ImportChannel.share:
        return PhotoSource.share;
      default:
        return PhotoSource.gallery;
    }
  }

  Future<String?> _reverseGeocode(PhotoMetadata metadata) async {
    if (!services.settings.geocodeEnabled) return null;
    if (!services.geocoding.configured) return null;
    final point = metadata.gps;
    if (point == null || !point.isValid) return null;
    return services.geocoding.reverse(point);
  }

  LedgerEntry _ledgerEntry(PipelineResult result, ImportItem item) {
    final job = result.job;
    final identity = services.settings.identity;
    return LedgerEntry(
      fileName: p.basename(result.outputPath),
      outputPath: result.outputPath,
      originalPath: item.path,
      source: job.source,
      templateId: job.template.id,
      mode: job.mode,
      sha256: result.pixelSha256,
      processedAt: DateTime.now(),
      capturedAt: item.metadata.takenAt,
      position: item.metadata.gps,
      altitudeMeters: item.metadata.altitudeMeters,
      address: job.capture.address,
      note: job.template.valueOf(WatermarkFieldIds.note, fallback: identity.note),
      operatorName: identity.operatorName,
      organization: identity.organization,
      timeAuthority: item.metadata.takenAt == null
          ? TimeAuthority.missing
          : TimeAuthority.originalExif,
      coordAuthority:
          item.metadata.hasGps ? CoordAuthority.originalExif : CoordAuthority.missing,
      fingerprint: result.fingerprint,
    );
  }

  /// 是否存在"原图无 GPS"的条目（用于提示会显示「无原始定位」）。
  bool get hasMissingGeo => items.any((item) => !item.hasOriginalGeo);

  bool get hasUnsupportedHeic => items.any((item) {
        final lower = item.path.toLowerCase();
        return lower.endsWith('.heic') || lower.endsWith('.heif');
      });

  static bool isSupportedPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  Future<int> fileSize(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return 0;
    }
  }
}
