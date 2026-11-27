import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../core/layout/layout_engine.dart';
import '../../core/models/photo_metadata.dart';
import '../../core/models/pipeline_job.dart';
import '../../core/service/field_catalog.dart';
import '../hash/hash_engine.dart';
import '../metadata/metadata_engine.dart';
import '../watermark/watermark_renderer.dart';
import 'image_codec.dart';

/// 管线帧：在中间件之间流转的可变载面。
class FrameBuffer {
  FrameBuffer({
    required this.image,
    required this.metadata,
    this.bytes,
    Map<String, Object?>? bag,
  }) : bag = bag ?? <String, Object?>{};

  final ui.Image image;
  final PhotoMetadata metadata;
  final Uint8List? bytes;

  /// 中间件之间的旁路数据（指纹、跳过原因、阶段日志等）。
  final Map<String, Object?> bag;

  bool get skipped => bag['skipped'] == true;

  String? get skipReason => bag['skipReason'] as String?;

  FrameBuffer fork({
    ui.Image? image,
    PhotoMetadata? metadata,
    Uint8List? bytes,
  }) {
    return FrameBuffer(
      image: image ?? this.image,
      metadata: metadata ?? this.metadata,
      bytes: bytes ?? this.bytes,
      bag: bag,
    );
  }

  T? read<T>(String key) {
    final value = bag[key];
    return value is T ? value : null;
  }
}

/// 扩展点二：图像管线中间件。
///
/// `order` 之间刻意留出间隔（100/200/300/400/550/600/700/800），
/// 新中间件插进任意位置都不需要改动既有实现。
abstract class ImageMiddleware {
  String get id;

  /// 执行顺序。管线固定顺序：解码取帧 → 方向校正 → 降采样 → 水印查重 →
  /// 可选人脸打码 → 绘制水印 → 编码 → EXIF 回写。
  int get order;

  /// 是否作用于该任务（例如人脸打码只对配置了检测结果的任务生效）。
  bool appliesTo(PipelineJob job);

  /// [frame] 在第一个中间件（解码）时为 null，解码负责建立初始帧；
  /// 之后的中间件必须原样或派生返回新帧。
  Future<FrameBuffer> process(
    FrameBuffer? frame,
    PipelineJob job,
    PipelineContext ctx,
  );
}

/// 管线运行上下文：注入能力引擎，中间件不自行 new 依赖。
class PipelineContext {
  const PipelineContext({
    required this.codec,
    required this.renderer,
    required this.fields,
    required this.layout,
    required this.hash,
    required this.metadata,
    this.onStage,
  });

  final ImageCodecEngine codec;
  final WatermarkRenderer renderer;
  final FieldCatalog fields;
  final LayoutEngine layout;
  final HashEngine hash;
  final MetadataEngine metadata;
  final void Function(String stage)? onStage;
}

class PipelineResult {
  const PipelineResult({
    required this.job,
    required this.outputPath,
    required this.pixelSha256,
    this.fingerprint,
    this.skipped = false,
    this.skipReason,
    this.stages = const [],
    this.layout,
  });

  final PipelineJob job;
  final String outputPath;
  final String pixelSha256;
  final String? fingerprint;
  final bool skipped;
  final String? skipReason;
  final List<String> stages;
  final WatermarkLayout? layout;
}

class PipelineFailure implements Exception {
  PipelineFailure(this.job, this.stage, this.cause);

  final PipelineJob job;
  final String stage;
  final Object cause;

  @override
  String toString() => '[$stage] $cause';
}

/// 管线执行器：按 order 串行执行中间件，任一环节抛错即带上阶段名中断。
class PipelineRunner {
  PipelineRunner(List<ImageMiddleware> middlewares)
      : middlewares = List<ImageMiddleware>.unmodifiable(
          middlewares.toList()..sort((a, b) => a.order.compareTo(b.order)),
        );

  final List<ImageMiddleware> middlewares;

  Future<PipelineResult> run(PipelineJob job, PipelineContext ctx, {FrameBuffer? seed}) async {
    final stages = <String>[];
    FrameBuffer? frame = seed;
    String? currentStage = '初始化';
    try {
      for (final middleware in middlewares) {
        if (!middleware.appliesTo(job)) continue;
        currentStage = middleware.id;
        ctx.onStage?.call(middleware.id);
        stages.add(middleware.id);
        frame = await middleware.process(frame, job, ctx);
        if (frame.skipped) break;
      }
      if (frame == null) {
        throw StateError('管线未产生任何帧（缺少解码中间件）');
      }
      final outputPath = frame.read<String>('outputPath') ?? job.outputPath;
      final sha = frame.read<String>('pixelSha256') ?? '';
      return PipelineResult(
        job: job,
        outputPath: outputPath,
        pixelSha256: sha,
        fingerprint: frame.read<String>('fingerprint'),
        skipped: frame.skipped,
        skipReason: frame.skipReason,
        stages: stages,
        layout: frame.read<WatermarkLayout>('layout'),
      );
    } catch (error) {
      throw PipelineFailure(job, currentStage ?? '初始化', error);
    }
  }
}

enum BatchStageStatus { pending, running, done, skipped, failed }

class BatchProgress {
  const BatchProgress({
    required this.index,
    required this.total,
    required this.job,
    required this.status,
    this.stage,
    this.result,
    this.error,
  });

  final int index;
  final int total;
  final PipelineJob job;
  final BatchStageStatus status;
  final String? stage;
  final PipelineResult? result;
  final Object? error;

  double get ratio => total == 0 ? 0 : (index + (status == BatchStageStatus.running ? 0.5 : 1)) / total;
}

class BatchOutcome {
  const BatchOutcome({required this.results, required this.failures});

  final List<PipelineResult> results;
  final List<PipelineFailure> failures;
}

/// 批量队列：串行执行，逐张上报进度与失败原因。
///
/// 说明：`dart:ui` 的 Image/Canvas 只能在 UI isolate 使用，因此像素环节无法丢给
/// `Isolate.run`；这里的"队列"通过串行化 + 每张之间让出一帧来避免 OOM 与卡顿，
/// 同时保证同一时刻只有一张大图在内存里。文件 IO 与哈希在中间件内部异步执行。
class BatchPipeline {
  BatchPipeline(this.runner);

  final PipelineRunner runner;

  Stream<BatchProgress> process(
    List<PipelineJob> jobs,
    PipelineContext ctx,
  ) async* {
    final total = jobs.length;
    for (var index = 0; index < total; index++) {
      final job = jobs[index];
      yield BatchProgress(
        index: index,
        total: total,
        job: job,
        status: BatchStageStatus.running,
        stage: '解码取帧',
      );
      try {
        final result = await runner.run(job, ctx);
        yield BatchProgress(
          index: index,
          total: total,
          job: job,
          status: result.skipped ? BatchStageStatus.skipped : BatchStageStatus.done,
          result: result,
          stage: result.skipped ? '水印查重' : '完成',
        );
      } catch (error) {
        yield BatchProgress(
          index: index,
          total: total,
          job: job,
          status: BatchStageStatus.failed,
          error: error,
          stage: error is PipelineFailure ? error.stage : '未知阶段',
        );
      }
      // 让出事件循环，避免长批量时界面掉帧。
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// 重试失败任务：用同一批上下文重新跑一次。
  Future<BatchOutcome> runAll(
    List<PipelineJob> jobs,
    PipelineContext ctx, {
    void Function(BatchProgress progress)? onProgress,
  }) async {
    final results = <PipelineResult>[];
    final failures = <PipelineFailure>[];
    await for (final progress in process(jobs, ctx)) {
      onProgress?.call(progress);
      if (progress.status == BatchStageStatus.done ||
          progress.status == BatchStageStatus.skipped) {
        final result = progress.result;
        if (result != null) results.add(result);
      } else if (progress.status == BatchStageStatus.failed) {
        failures.add(progress.error is PipelineFailure
            ? progress.error as PipelineFailure
            : PipelineFailure(progress.job, progress.stage ?? '未知', progress.error ?? '未知错误'));
      }
    }
    return BatchOutcome(results: results, failures: failures);
  }
}

/// 便捷：把帧里的布局转成纯数据（供调试与 golden 夹具使用）。
Map<String, dynamic>? layoutToJson(FrameBuffer? frame) =>
    frame?.read<WatermarkLayout>('layout')?.toJson();
