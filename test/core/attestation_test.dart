import 'package:flutter_test/flutter_test.dart';
import 'package:qingyang_watermark/core/models/photo_metadata.dart';
import 'package:qingyang_watermark/core/models/types.dart';
import 'package:qingyang_watermark/core/service/attestation.dart';

WatermarkStamp stamp({String sha = 'a' * 64, PhotoSource source = PhotoSource.camera}) {
  return WatermarkStamp(
    source: source,
    mode: CaptureMode.forensics,
    templateId: 'default',
    capturedAt: DateTime(2026, 11, 27, 20, 31, 5),
    timeAuthority: source == PhotoSource.camera
        ? TimeAuthority.ntp
        : TimeAuthority.originalExif,
    coordAuthority: CoordAuthority.fused,
    position: const GeoPoint(latitude: 30.274084, longitude: 120.15507),
    fingerprint: 'b' * 64,
    fileSha256: sha,
  );
}

PhotoMetadata metadataWith(WatermarkStamp value) => PhotoMetadata(
      takenAt: DateTime(2026, 11, 27, 20, 31, 5),
      gps: const GeoPoint(latitude: 30.274084, longitude: 120.15507),
      software: 'QingyangWatermarkCamera 1.0',
      userComment: value.encode(),
      hasExifBlock: true,
      hasXmpPacket: true,
      hasQingyangMarker: true,
    );

void main() {
  const service = AttestationService();

  test('哈希一致 → 校验通过', () {
    final report = service.verify(
      actualSha256: 'a' * 64,
      metadata: metadataWith(stamp()),
      xmpSha256: 'a' * 64,
      xmpFingerprint: 'b' * 64,
    );
    expect(report.verdict, AttestVerdict.authentic);
    expect(report.isAuthentic, isTrue);
    expect(report.stamp, isNotNull);
    expect(report.failures, isEmpty);
  });

  test('哈希不一致 → 疑似被修改', () {
    final report = service.verify(
      actualSha256: 'c' * 64,
      metadata: metadataWith(stamp()),
      xmpSha256: 'a' * 64,
    );
    expect(report.verdict, AttestVerdict.tampered);
    expect(
      report.failures.any((check) => check.code == 'hash.file'),
      isTrue,
    );
  });

  test('无戳记 → 非本应用产物', () {
    final report = service.verify(
      actualSha256: 'a' * 64,
      metadata: const PhotoMetadata(),
    );
    expect(report.verdict, AttestVerdict.unknown);
  });

  test('EXIF 与 XMP 记录不一致 → 记录不一致', () {
    final report = service.verify(
      actualSha256: 'a' * 64,
      metadata: metadataWith(stamp()),
      xmpSha256: 'd' * 64,
    );
    expect(report.verdict, AttestVerdict.tampered);
    expect(report.failures.any((check) => check.code == 'hash.cross'), isTrue);
  });

  test('导入图不得被标成现场取证', () {
    final imported = stamp(source: PhotoSource.gallery);
    final report = service.verify(
      actualSha256: 'a' * 64,
      metadata: metadataWith(imported),
      xmpSha256: 'a' * 64,
    );
    expect(report.stamp!.source, PhotoSource.gallery);
    expect(report.stamp!.timeAuthority, TimeAuthority.originalExif);
  });

  test('戳记缺少哈希 → 记录不一致', () {
    final noHash = WatermarkStamp(
      source: PhotoSource.camera,
      mode: CaptureMode.forensics,
      templateId: 'default',
      capturedAt: DateTime(2026, 11, 27, 20, 31, 5),
      timeAuthority: TimeAuthority.ntp,
      coordAuthority: CoordAuthority.fused,
    );
    final report = service.verify(
      actualSha256: 'a' * 64,
      metadata: metadataWith(noHash),
    );
    expect(report.verdict, AttestVerdict.inconsistent);
  });
}
