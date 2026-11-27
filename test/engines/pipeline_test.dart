import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingyang_watermark/core/layout/layout_engine.dart';
import 'package:qingyang_watermark/core/models/photo_metadata.dart';
import 'package:qingyang_watermark/core/models/pipeline_job.dart';
import 'package:qingyang_watermark/core/models/profile_config.dart';
import 'package:qingyang_watermark/core/models/template.dart';
import 'package:qingyang_watermark/core/models/types.dart';
import 'package:qingyang_watermark/core/metadata/exif_codec.dart';
import 'package:qingyang_watermark/core/service/field_catalog.dart';
import 'package:qingyang_watermark/engines/hash/hash_engine.dart';
import 'package:qingyang_watermark/engines/image/image_codec.dart';
import 'package:qingyang_watermark/engines/image/middlewares.dart';
import 'package:qingyang_watermark/engines/image/pipeline.dart';
import 'package:qingyang_watermark/engines/metadata/metadata_engine.dart';
import 'package:qingyang_watermark/engines/watermark/watermark_renderer.dart';

class _Recorder implements ImageMiddleware {
  _Recorder(this.id, this.order, this.log);

  @override
  final String id;

  @override
  final int order;

  final List<String> log;

  @override
  bool appliesTo(PipelineJob job) => true;

  @override
  Future<FrameBuffer> process(
    FrameBuffer? frame,
    PipelineJob job,
    PipelineContext ctx,
  ) async {
    log.add(id);
    if (frame != null) return frame;
    final image = await blankImage(64, 48);
    return FrameBuffer(image: image, metadata: PhotoMetadata.unknown);
  }
}

TemplateConfig template({Set<String>? fields}) => TemplateConfig(
      id: 'default',
      name: '测试模板',
      profileId: 'forensics',
      style: const WatermarkStyle(),
      enabledFieldIds: fields ?? WatermarkFieldIds.all.toSet(),
    );

PipelineJob job({
  required String input,
  required String output,
  PhotoSource source = PhotoSource.camera,
  TemplateConfig? config,
}) {
  final capture = CaptureContext(
    capturedAt: DateTime(2026, 11, 27, 20, 31, 5),
    timeAuthority: TimeAuthority.ntp,
    coordAuthority: CoordAuthority.fused,
    position: const GeoPoint(latitude: 30.274084, longitude: 120.15507),
    altitudeMeters: 42,
    address: '浙江省杭州市西湖区某街道 88 号',
    deviceModel: 'Test Phone',
    online: true,
  );
  return PipelineJob(
    id: 'job_${input.hashCode}',
    inputPath: input,
    outputPath: output,
    template: config ?? template(),
    profile: source == PhotoSource.camera
        ? const ProfileConfig(
            id: 'forensics',
            label: '取证',
            timePolicy: TimePolicyKind.trustedRequired,
            coordPolicy: CoordPolicyKind.deviceFixRequired,
          )
        : const ProfileConfig(
            id: 'processed',
            label: '加工',
            timePolicy: TimePolicyKind.originalOnly,
            coordPolicy: CoordPolicyKind.originalOnly,
          ),
    capture: capture,
    provenance: source == PhotoSource.camera
        ? Provenance.capture(batchId: 'b', at: DateTime(2026, 11, 27, 20, 31, 5))
        : Provenance(
            source: source,
            batchId: 'b',
            importedAt: DateTime(2026, 11, 27, 21, 0, 0),
          ),
  );
}

PipelineContext fakeContext() => PipelineContext(
      codec: FakeImageCodec(),
      renderer: FakeWatermarkRenderer(),
      fields: FieldCatalog(const []),
      layout: const LayoutEngine(),
      hash: FakeHashEngine(),
      metadata: MetadataEngine(providers: [FakeMetadataProvider()]),
    );

void main() {
  testWidgets('中间件严格按 order 执行，与注册顺序无关', (tester) async {
    await tester.runAsync(() async {
      final log = <String>[];
      final runner = PipelineRunner([
        _Recorder('c', 300, log),
        _Recorder('a', 100, log),
        _Recorder('b', 200, log),
      ]);
      final temp = await Directory.systemTemp.createTemp('qy_pipe');
      await runner.run(
        job(
          input: '${temp.path}/in.jpg',
          output: '${temp.path}/out.jpg',
        ),
        fakeContext(),
      );
      expect(log, ['a', 'b', 'c']);
    });
  });

  testWidgets('批量管线逐张上报进度，失败项带阶段名', (tester) async {
    await tester.runAsync(() async {
      final log = <String>[];
      final runner = PipelineRunner([_Recorder('only', 100, log)]);
      final batch = BatchPipeline(runner);
      final temp = await Directory.systemTemp.createTemp('qy_batch');
      final jobs = [
        job(input: '${temp.path}/a.jpg', output: '${temp.path}/a_out.jpg'),
        job(input: '${temp.path}/b.jpg', output: '${temp.path}/b_out.jpg'),
      ];
      final progress = <BatchProgress>[];
      final outcome = await batch.runAll(
        jobs,
        fakeContext(),
        onProgress: progress.add,
      );
      expect(outcome.results.length, 2);
      expect(outcome.failures, isEmpty);
      expect(progress.where((p) => p.status == BatchStageStatus.done).length, 2);
    });
  });

  testWidgets('端到端：真实渲染 + 编码 + EXIF 回写', (tester) async {
    await tester.runAsync(() async {
      final temp = await Directory.systemTemp.createTemp('qy_e2e');
      final codec = const FlutterImageCodec();
      final source = await blankImage(900, 600);
      final png = await codec.encodePng(source);
      final inputPath = '${temp.path}/src.png';
      await File(inputPath).writeAsBytes(png);

      final servicesMetadata = MetadataEngine(providers: [
        CameraMetadataProvider(),
        ExifMetadataProvider(),
      ]);
      final context = PipelineContext(
        codec: codec,
        renderer: const CanvasWatermarkRenderer(),
        fields: FieldCatalog(builtinFieldProviders()),
        layout: const LayoutEngine(),
        hash: const CryptoHashEngine(),
        metadata: servicesMetadata,
      );
      final runner = PipelineRunner(defaultMiddlewares(maxLongSide: 2048));
      final outputPath = '${temp.path}/out.jpg';
      final result = await runner.run(
        job(input: inputPath, output: outputPath),
        context,
      );

      expect(result.skipped, isFalse);
      expect(File(outputPath).existsSync(), isTrue);
      final bytes = await File(outputPath).readAsBytes();
      expect(bytes.length, greaterThan(1000));
      expect(bytes[0], 0xFF);
      expect(bytes[1], 0xD8);

      final info = const ExifCodec().read(bytes);
      expect(info.metadata.hasQingyangMarker, isTrue);
      expect(info.metadata.software, contains('QingyangWatermarkCamera'));
      expect(info.metadata.userComment, contains('QY1|src=camera'));
      expect(result.pixelSha256.isNotEmpty, isTrue);
      expect(
        const CryptoHashEngine().sha256OfPixelStream(bytes),
        result.pixelSha256,
      );
    });
  });

  testWidgets('已带水印的图会被查重跳过', (tester) async {
    await tester.runAsync(() async {
      final temp = await Directory.systemTemp.createTemp('qy_dedupe');
      final codec = const FlutterImageCodec();
      final source = await blankImage(400, 300);
      final base = await codec.encodeJpeg(source);
      final stamped = const ExifCodec().write(
        base,
        software: 'QingyangWatermarkCamera 1.0',
        userComment: WatermarkStamp(
          source: PhotoSource.gallery,
          mode: CaptureMode.processed,
          templateId: 'import_trace',
          capturedAt: DateTime(2026, 11, 27, 20, 31, 5),
          timeAuthority: TimeAuthority.originalExif,
          coordAuthority: CoordAuthority.originalExif,
        ).encode(),
      );
      final inputPath = '${temp.path}/stamped.jpg';
      await File(inputPath).writeAsBytes(stamped);

      final context = PipelineContext(
        codec: codec,
        renderer: const CanvasWatermarkRenderer(),
        fields: FieldCatalog(builtinFieldProviders()),
        layout: const LayoutEngine(),
        hash: const CryptoHashEngine(),
        metadata: MetadataEngine(providers: [
          CameraMetadataProvider(),
          ExifMetadataProvider(),
        ]),
      );
      final runner = PipelineRunner(defaultMiddlewares(maxLongSide: 4096));
      final result = await runner.run(
        job(
          input: inputPath,
          output: '${temp.path}/out.jpg',
          source: PhotoSource.gallery,
        ),
        context,
      );
      expect(result.skipped, isTrue);
      expect(result.skipReason, contains('二次叠加'));
    });
  });
}
