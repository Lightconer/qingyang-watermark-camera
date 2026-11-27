import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../core/extensions/watermark_field_provider.dart';
import '../../core/layout/layout_engine.dart';
import '../../core/models/photo_metadata.dart';
import '../../core/models/pipeline_job.dart';
import '../../core/models/template.dart';
import '../../core/models/types.dart';
import 'image_codec.dart';
import 'pipeline.dart';

/// 100 · 解码取帧。
///
/// 解码阶段就按长边上限降采样（等价 Android `inSampleSize`），避免整张大图进内存。
class DecodeMiddleware implements ImageMiddleware {
  DecodeMiddleware({this.maxLongSide = 4096});

  final int maxLongSide;

  @override
  String get id => '解码取帧';

  @override
  int get order => 100;

  @override
  bool appliesTo(PipelineJob job) => true;

  @override
  Future<FrameBuffer> process(
    FrameBuffer? frame,
    PipelineJob job,
    PipelineContext ctx,
  ) async {
    final file = File(job.inputPath);
    if (!await file.exists()) {
      throw StateError('源文件不存在：${job.inputPath}');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length < 4) {
      throw StateError('源文件为空或损坏：${job.inputPath}');
    }
    final image = await ctx.codec.decode(bytes, maxLongSide: maxLongSide);
    final metadata = await ctx.metadata.readFile(job.inputPath);
    final result = FrameBuffer(image: image, metadata: metadata, bytes: bytes);
    result.bag['inputBytes'] = bytes;
    result.bag['originalSize'] = '${image.width}x${image.height}';
    return result;
  }
}

/// 200 · 方向校正。先按 EXIF Orientation 转正，再进入后续环节。
class OrientMiddleware implements ImageMiddleware {
  OrientMiddleware();

  @override
  String get id => '方向校正';

  @override
  int get order => 200;

  @override
  bool appliesTo(PipelineJob job) => true;

  @override
  Future<FrameBuffer> process(
    FrameBuffer? frame,
    PipelineJob job,
    PipelineContext ctx,
  ) async {
    final current = frame!;
    final orientation = current.metadata.orientation;
    if (orientation <= 1) return current;
    final transform = ImageCodecEngine.orientationTransform(orientation);
    final rotated = await ctx.codec.transform(
      current.image,
      quarterTurns: transform.quarterTurns,
      flipX: transform.flipX,
      flipY: transform.flipY,
    );
    current.bag['orientationApplied'] = orientation;
    return current.fork(
      image: rotated,
      metadata: current.metadata.copyWith(orientation: 1),
    );
  }
}

/// 300 · 降采样。长边压到 4096 以内，防 OOM。
class DownscaleMiddleware implements ImageMiddleware {
  DownscaleMiddleware({this.maxLongSide = 4096});

  final int maxLongSide;

  @override
  String get id => '降采样';

  @override
  int get order => 300;

  @override
  bool appliesTo(PipelineJob job) => true;

  @override
  Future<FrameBuffer> process(
    FrameBuffer? frame,
    PipelineJob job,
    PipelineContext ctx,
  ) async {
    final current = frame!;
    final longSide = math.max(current.image.width, current.image.height);
    if (longSide <= maxLongSide) return current;
    final resized = await ctx.codec.resizeToLongSide(current.image, maxLongSide);
    current.bag['downscaledFrom'] = '$longSide';
    return current.fork(image: resized);
  }
}

/// 400 · 水印查重。
///
/// 原图已带青阳戳记（EXIF UserComment 的 QY1 或 XMP qingyang: 命名空间）时跳过，
/// 避免二次叠加把画面糊死、并防止"反复加工"造成溯源断链。
class DedupeMiddleware implements ImageMiddleware {
  DedupeMiddleware();

  @override
  String get id => '水印查重';

  @override
  int get order => 400;

  @override
  bool appliesTo(PipelineJob job) => true;

  @override
  Future<FrameBuffer> process(
    FrameBuffer? frame,
    PipelineJob job,
    PipelineContext ctx,
  ) async {
    final current = frame!;
    final metadata = current.metadata;
    final alreadyStamped = metadata.hasQingyangMarker ||
        WatermarkStamp.decode(metadata.userComment) != null;
    if (alreadyStamped) {
      current.bag['skipped'] = true;
      current.bag['skipReason'] = '检测到已有青阳水印标记，已跳过以防二次叠加';
    }
    return current;
  }
}

/// 550 · 可选人脸打码。
///
/// 默认不启用（`appliesTo` 为 false）。接入人脸检测后，把检测框写入
/// `job.options['faceRects']`，本中间件负责马赛克，无需改动其它环节。
class FaceBlurMiddleware implements ImageMiddleware {
  const FaceBlurMiddleware();

  @override
  String get id => '人脸打码';

  @override
  int get order => 550;

  @override
  bool appliesTo(PipelineJob job) {
    final rects = job.options['faceRects'];
    return rects is List && rects.isNotEmpty;
  }

  @override
  Future<FrameBuffer> process(
    FrameBuffer? frame,
    PipelineJob job,
    PipelineContext ctx,
  ) async {
    final current = frame!;
    final raw = job.options['faceRects'];
    if (raw is! List) return current;

    var image = current.image;
    for (final item in raw) {
      if (item is! LayoutRect) continue;
      image = await _pixelate(image, item);
    }
    current.bag['faceBlurred'] = raw.length;
    return current.fork(image: image);
  }

  Future<ui.Image> _pixelate(ui.Image source, LayoutRect rect) async {
    final left = rect.left.clamp(0, source.width.toDouble());
    final top = rect.top.clamp(0, source.height.toDouble());
    final width = rect.width.clamp(1, source.width - left);
    final height = rect.height.clamp(1, source.height - top);
    final src = ui.Rect.fromLTWH(left, top, width, height);
    const blocks = 12.0;
    final smallWidth = math.max(1, (width / blocks).round());
    final smallHeight = math.max(1, (height / blocks).round());

    final smallRecorder = ui.PictureRecorder();
    ui.Canvas(smallRecorder).drawImageRect(
      source,
      src,
      ui.Rect.fromLTWH(0, 0, smallWidth.toDouble(), smallHeight.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.low,
    );
    final smallPicture = smallRecorder.endRecording();
    final smallImage = await smallPicture.toImage(smallWidth, smallHeight);
    smallPicture.dispose();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(source, ui.Offset.zero, ui.Paint());
    canvas.drawImageRect(
      smallImage,
      ui.Rect.fromLTWH(0, 0, smallWidth.toDouble(), smallHeight.toDouble()),
      src,
      ui.Paint()..filterQuality = ui.FilterQuality.none,
    );
    final picture = recorder.endRecording();
    final result = await picture.toImage(source.width, source.height);
    picture.dispose();
    smallImage.dispose();
    return result;
  }
}

/// 600 · 绘制水印。
///
/// 两遍渲染：第一遍不带哈希小字 → 算出内容指纹 → 第二遍把指纹画进去。
/// 哈希小字因此指向"加水印后的图像内容"，同时不影响最终文件的元数据哈希。
class DrawWatermarkMiddleware implements ImageMiddleware {
  const DrawWatermarkMiddleware();

  @override
  String get id => '绘制水印';

  @override
  int get order => 600;

  @override
  bool appliesTo(PipelineJob job) => true;

  @override
  Future<FrameBuffer> process(
    FrameBuffer? frame,
    PipelineJob job,
    PipelineContext ctx,
  ) async {
    final current = frame!;
    final template = job.template;
    final style = template.style;
    final badge = job.profile.requireProvenanceBadge ? job.provenance.badgeText : null;
    final size = LayoutSize(
      current.image.width.toDouble(),
      current.image.height.toDouble(),
    );

    FieldContext buildContext(String? fingerprint) => FieldContext(
          mode: job.mode,
          provenance: job.provenance,
          capture: job.capture,
          template: template,
          original: job.originalMeta,
          identity: job.identity,
          fingerprint: fingerprint,
          weatherAllowed: job.weatherAllowed,
        );

    List<ResolvedField> resolve(FieldContext context) => ctx.fields.resolve(
          context,
          enabledFieldIds: template.enabledFieldIds,
          allowedFieldIds: job.profile.allowedFields,
        );

    final firstPass = resolve(buildContext(null));
    final firstLayout = ctx.layout.compute(
      size: size,
      fields: firstPass,
      style: style,
      badgeText: badge,
      qrData: null,
    );
    final firstImage = await ctx.renderer.render(base: current.image, layout: firstLayout);
    final firstBytes = await ctx.codec.encodeJpeg(firstImage, quality: 90);
    final fingerprint = ctx.hash.sha256OfBytes(firstBytes);
    firstImage.dispose();

    final wantsFingerprintLine = template.isFieldEnabled(WatermarkFieldIds.hash);
    final secondPass = resolve(buildContext(wantsFingerprintLine ? fingerprint : null));
    final wantsQr = template.isFieldEnabled(WatermarkFieldIds.qr) || style.showQr;
    final finalLayout = ctx.layout.compute(
      size: size,
      fields: secondPass,
      style: style,
      badgeText: badge,
      qrData: wantsQr ? job.qrPayload : null,
    );
    final finalImage = await ctx.renderer.render(base: current.image, layout: finalLayout);

    current.bag['fingerprint'] = fingerprint;
    current.bag['layout'] = finalLayout;
    current.bag['fieldCount'] = secondPass.length;
    return current.fork(image: finalImage);
  }
}

/// 700 · 编码。
class EncodeMiddleware implements ImageMiddleware {
  const EncodeMiddleware();

  @override
  String get id => '编码';

  @override
  int get order => 700;

  @override
  bool appliesTo(PipelineJob job) => true;

  @override
  Future<FrameBuffer> process(
    FrameBuffer? frame,
    PipelineJob job,
    PipelineContext ctx,
  ) async {
    final current = frame!;
    final quality = job.options['jpegQuality'];
    final bytes = await ctx.codec.encodeJpeg(
      current.image,
      quality: quality is int ? quality : 92,
    );
    return current.fork(bytes: bytes);
  }
}

/// 800 · EXIF / XMP 回写。
///
/// 先算"去元数据后的像素流哈希"，再写入戳记，因此哈希不会被元数据写入影响，
/// 校验端只要用同样口径重算即可判断文件是否被改过。
class MetadataWriteMiddleware implements ImageMiddleware {
  const MetadataWriteMiddleware();

  @override
  String get id => 'EXIF回写';

  @override
  int get order => 800;

  @override
  bool appliesTo(PipelineJob job) => true;

  @override
  Future<FrameBuffer> process(
    FrameBuffer? frame,
    PipelineJob job,
    PipelineContext ctx,
  ) async {
    final current = frame!;
    final encoded = current.bytes;
    if (encoded == null) {
      throw StateError('缺少编码结果，无法回写元数据');
    }

    final pixelSha = ctx.hash.sha256OfPixelStream(encoded);
    final stamp = WatermarkStamp(
      source: job.source,
      mode: job.mode,
      templateId: job.template.id,
      capturedAt: job.capture.capturedAt,
      timeAuthority: job.isImport
          ? TimeAuthority.originalExif
          : job.capture.timeAuthority,
      coordAuthority: job.isImport
          ? CoordAuthority.originalExif
          : job.capture.coordAuthority,
      position: job.isImport ? current.metadata.gps : job.capture.position,
      altitudeMeters:
          job.isImport ? current.metadata.altitudeMeters : job.capture.altitudeMeters,
      address: job.capture.address,
      fingerprint: current.read<String>('fingerprint'),
      fileSha256: pixelSha,
      operator: job.identity.operatorName,
      organization: job.identity.organization,
      project: job.identity.projectName,
      note: job.template.valueOf(WatermarkFieldIds.note, fallback: job.identity.note),
    );

    final provider = ctx.metadata.providerFor(job.source);
    final stamped = await provider.write(
      encoded,
      stamp: stamp,
      original: current.metadata,
      dateTimeOriginal: job.isImport ? null : job.capture.capturedAt,
      gps: job.isImport ? null : job.capture.position,
      altitudeMeters: job.isImport ? null : job.capture.altitudeMeters,
    );

    final output = File(job.outputPath);
    await output.parent.create(recursive: true);
    await output.writeAsBytes(stamped, flush: true);

    current.bag['outputPath'] = job.outputPath;
    current.bag['pixelSha256'] = pixelSha;
    current.bag['stamp'] = stamp;
    return current.fork(bytes: stamped);
  }
}

/// 默认管线集合。新增中间件只需追加进这个列表（或由 FeatureModule 提供）。
List<ImageMiddleware> defaultMiddlewares({int maxLongSide = 4096}) => [
      DecodeMiddleware(maxLongSide: maxLongSide),
      OrientMiddleware(),
      DownscaleMiddleware(maxLongSide: maxLongSide),
      DedupeMiddleware(),
      const FaceBlurMiddleware(),
      const DrawWatermarkMiddleware(),
      const EncodeMiddleware(),
      const MetadataWriteMiddleware(),
    ];

/// 供扩展点说明引用：管线固定顺序。
const List<String> pipelineStageOrder = [
  '解码取帧',
  '方向校正',
  '降采样',
  '水印查重',
  '人脸打码',
  '绘制水印',
  '编码',
  'EXIF回写',
];
