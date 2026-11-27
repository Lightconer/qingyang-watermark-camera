import '../models/photo_metadata.dart';
import '../models/types.dart';

enum AttestVerdict { authentic, inconsistent, tampered, unknown }

extension AttestVerdictX on AttestVerdict {
  String get label {
    switch (this) {
      case AttestVerdict.authentic:
        return '校验通过';
      case AttestVerdict.inconsistent:
        return '记录不一致';
      case AttestVerdict.tampered:
        return '疑似被修改';
      case AttestVerdict.unknown:
        return '非本应用产物';
    }
  }
}

class AttestationCheck {
  const AttestationCheck({
    required this.code,
    required this.label,
    required this.passed,
    this.detail = '',
    this.critical = false,
  });

  final String code;
  final String label;
  final bool passed;
  final String detail;
  final bool critical;
}

class AttestationReport {
  const AttestationReport({
    required this.verdict,
    required this.checks,
    this.stamp,
    this.actualSha256,
  });

  final AttestVerdict verdict;
  final List<AttestationCheck> checks;
  final WatermarkStamp? stamp;
  final String? actualSha256;

  bool get isAuthentic => verdict == AttestVerdict.authentic;

  List<AttestationCheck> get failures =>
      checks.where((check) => !check.passed).toList(growable: false);
}

/// 校验工具：比对成品当前 SHA256 与戳记（EXIF/XMP）中的 SHA256，并核对关键口径。
///
/// 说明：水印文字画在像素上，任何重新编码都会改变文件哈希，因此"哈希不匹配"
/// 等价于"文件在落盘后被改动过"。小字里的内容指纹用于人工比对与台账交叉验证。
class AttestationService {
  const AttestationService();

  AttestationReport verify({
    required String actualSha256,
    required PhotoMetadata metadata,
    String? xmpSha256,
    String? xmpFingerprint,
    bool pixelWatermarkPresent = true,
  }) {
    final stamp = WatermarkStamp.decode(metadata.userComment);
    final checks = <AttestationCheck>[];

    if (stamp == null) {
      checks.add(const AttestationCheck(
        code: 'stamp.missing',
        label: 'EXIF 水印戳记',
        passed: false,
        detail: '未找到 QY1 戳记，可能不是青阳水印产物',
        critical: true,
      ));
      if (xmpSha256 == null) {
        return AttestationReport(
          verdict: AttestVerdict.unknown,
          checks: checks,
          actualSha256: actualSha256,
        );
      }
    }

    checks.add(AttestationCheck(
      code: 'stamp.exif',
      label: 'EXIF 水印戳记',
      passed: stamp != null,
      detail: stamp == null ? '缺失' : '存在',
      critical: true,
    ));

    checks.add(AttestationCheck(
      code: 'stamp.xmp',
      label: 'XMP 水印记录',
      passed: metadata.hasXmpPacket,
      detail: metadata.hasXmpPacket ? '存在' : '缺失',
    ));

    final recorded = stamp?.fileSha256 ?? xmpSha256;
    final hashMatched = recorded != null && recorded == actualSha256;
    checks.add(AttestationCheck(
      code: 'hash.file',
      label: '成品哈希比对',
      passed: hashMatched,
      detail: recorded == null
          ? '戳记中没有哈希'
          : (hashMatched ? '一致' : '不一致（文件已被修改或重新压缩）'),
      critical: true,
    ));

    if (xmpSha256 != null && stamp?.fileSha256 != null) {
      checks.add(AttestationCheck(
        code: 'hash.cross',
        label: 'EXIF / XMP 交叉比对',
        passed: xmpSha256 == stamp!.fileSha256,
        detail: xmpSha256 == stamp.fileSha256 ? '一致' : '两处记录不一致',
      ));
    }

    if (stamp != null) {
      checks.add(AttestationCheck(
        code: 'pixel.watermark',
        label: '像素层水印（戳记推定，需人工比对画面）',
        passed: pixelWatermarkPresent,
        detail: pixelWatermarkPresent ? '戳记声明水印已烧录进像素' : '画面未检出',
        critical: true,
      ));

      final sourceOk = stamp.source == PhotoSource.camera
          ? stamp.timeAuthority == TimeAuthority.ntp ||
              stamp.timeAuthority == TimeAuthority.system
          : stamp.timeAuthority == TimeAuthority.originalExif;
      checks.add(AttestationCheck(
        code: 'provenance.source',
        label: '来源与时间口径',
        passed: sourceOk,
        detail: '${stamp.source.label} / ${stamp.timeAuthority.label}',
      ));

      if (stamp.source.isImport) {
        checks.add(AttestationCheck(
          code: 'provenance.notField',
          label: '导入图不得标注为现场取证',
          passed: stamp.source.isImport,
          detail: '来源=${stamp.source.label}',
        ));
      }
    }

    if (xmpFingerprint != null && stamp?.fingerprint != null) {
      checks.add(AttestationCheck(
        code: 'fingerprint.cross',
        label: '内容指纹交叉比对',
        passed: xmpFingerprint == stamp!.fingerprint,
        detail: xmpFingerprint == stamp.fingerprint ? '一致' : '不一致',
      ));
    }

    final criticalFailed = checks.any((check) => check.critical && !check.passed);
    final anyFailed = checks.any((check) => !check.passed);
    final AttestVerdict verdict;
    if (recorded == null) {
      verdict = AttestVerdict.inconsistent;
    } else if (criticalFailed) {
      verdict = AttestVerdict.tampered;
    } else if (anyFailed) {
      verdict = AttestVerdict.inconsistent;
    } else {
      verdict = AttestVerdict.authentic;
    }

    return AttestationReport(
      verdict: verdict,
      checks: checks,
      stamp: stamp,
      actualSha256: actualSha256,
    );
  }
}
