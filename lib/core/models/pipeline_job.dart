import '../extensions/watermark_field_provider.dart';
import 'photo_metadata.dart';
import 'profile_config.dart';
import 'template.dart';
import 'types.dart';

/// 一次"加水印"任务的完整输入。纯数据，可在 Isolate 间传递（除 ui.Image 外的部分）。
class PipelineJob {
  const PipelineJob({
    required this.id,
    required this.inputPath,
    required this.outputPath,
    required this.template,
    required this.profile,
    required this.capture,
    required this.provenance,
    this.originalMeta = PhotoMetadata.unknown,
    this.identity = const IdentityInfo(),
    this.options = const {},
  });

  final String id;
  final String inputPath;
  final String outputPath;
  final TemplateConfig template;
  final ProfileConfig profile;
  final CaptureContext capture;
  final Provenance provenance;
  final PhotoMetadata originalMeta;
  final IdentityInfo identity;
  final Map<String, Object?> options;

  bool get isImport => provenance.source.isImport;

  PhotoSource get source => provenance.source;

  CaptureMode get mode => profile.mode;

  bool get weatherAllowed => profile.weatherAllowed && !isImport;

  /// 溯源二维码内容：轻量文本，扫码即可看到关键事实（不依赖网络）。
  String get qrPayload {
    final parts = <String>[
      'QY',
      provenance.source.code,
      capture.capturedAt.toUtc().toIso8601String(),
      if (capture.position != null) capture.position!.toDisplay(decimals: 6),
      provenance.batchId,
    ];
    return parts.join('|');
  }

  PipelineJob copyWith({
    String? outputPath,
    TemplateConfig? template,
    Map<String, Object?>? options,
  }) {
    return PipelineJob(
      id: id,
      inputPath: inputPath,
      outputPath: outputPath ?? this.outputPath,
      template: template ?? this.template,
      profile: profile,
      capture: capture,
      provenance: provenance,
      originalMeta: originalMeta,
      identity: identity,
      options: options ?? this.options,
    );
  }
}
