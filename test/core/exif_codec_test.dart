import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingyang_watermark/core/metadata/exif_codec.dart';
import 'package:qingyang_watermark/core/models/photo_metadata.dart';
import 'package:qingyang_watermark/core/models/types.dart';

/// 极简 JPEG 骨架：SOI + SOS，足以验证 APP1 的拼接与解析。
Uint8List fakeJpeg() => Uint8List.fromList(
      [0xFF, 0xD8, 0xFF, 0xDA, 0x00, 0x02, 0x01, 0x02, 0x03, 0x04],
    );

WatermarkStamp sampleStamp({String? sha}) => WatermarkStamp(
      source: PhotoSource.camera,
      mode: CaptureMode.forensics,
      templateId: 'default',
      capturedAt: DateTime(2026, 11, 27, 20, 31, 5),
      timeAuthority: TimeAuthority.ntp,
      coordAuthority: CoordAuthority.fused,
      position: const GeoPoint(latitude: 30.274084, longitude: 120.15507),
      fileSha256: sha,
    );

void main() {
  const codec = ExifCodec();

  test('写入后能读回 Software / UserComment / GPS / 拍摄时间', () {
    final written = codec.write(
      fakeJpeg(),
      software: 'QingyangWatermarkCamera 1.0',
      userComment: sampleStamp().encode(),
      dateTimeOriginal: DateTime(2026, 11, 27, 20, 31, 5),
      gps: const GeoPoint(latitude: 30.274084, longitude: 120.15507),
      altitudeMeters: 42,
    );

    final info = codec.read(written);
    expect(info.metadata.hasExifBlock, isTrue);
    expect(info.metadata.software, contains('QingyangWatermarkCamera'));
    expect(info.metadata.userComment, contains('QY1|src=camera'));
    expect(info.metadata.orientation, 1);
    expect(info.metadata.takenAt, DateTime(2026, 11, 27, 20, 31, 5));
    expect(info.metadata.gps, isNotNull);
    expect(info.metadata.gps!.latitude, closeTo(30.274084, 1e-5));
    expect(info.metadata.gps!.longitude, closeTo(120.15507, 1e-5));
    expect(info.metadata.altitudeMeters, closeTo(42, 0.6));
  });

  test('二次写入保留原图 DateTimeOriginal 与 GPS', () {
    final first = codec.write(
      fakeJpeg(),
      software: 'QingyangWatermarkCamera 1.0',
      userComment: sampleStamp().encode(),
      dateTimeOriginal: DateTime(2026, 11, 27, 20, 31, 5),
      gps: const GeoPoint(latitude: 30.274084, longitude: 120.15507),
    );
    final second = codec.write(
      first,
      software: 'QingyangWatermarkCamera 1.0',
      userComment: '${sampleStamp(sha: 'b' * 64).encode()}',
    );
    final info = codec.read(second);
    expect(info.metadata.takenAt, DateTime(2026, 11, 27, 20, 31, 5));
    expect(info.metadata.gps, isNotNull);
    expect(info.metadata.gps!.latitude, closeTo(30.274084, 1e-5));
    expect(info.metadata.userComment, contains('sha=${'b' * 64}'));
  });

  test('XMP 与 EXIF 并存，写入 XMP 不会抹掉 EXIF', () {
    final withExif = codec.write(
      fakeJpeg(),
      software: 'QingyangWatermarkCamera 1.0',
      userComment: sampleStamp(sha: 'c' * 64).encode(),
    );
    final withXmp = codec.writeXmp(
      withExif,
      '<x:xmpmeta><rdf:Description qingyang:FileSha256="${'c' * 64}"/></x:xmpmeta>',
    );
    final info = codec.read(withXmp);
    expect(info.metadata.hasExifBlock, isTrue);
    expect(info.metadata.hasXmpPacket, isTrue);
    expect(info.metadata.hasQingyangMarker, isTrue);
    expect(info.metadata.userComment, contains('QY1|'));
  });

  test('stripMetadata 去掉 EXIF/XMP，且结果稳定可复现', () {
    final stamped = codec.writeXmp(
      codec.write(
        fakeJpeg(),
        software: 'QingyangWatermarkCamera 1.0',
        userComment: sampleStamp().encode(),
      ),
      '<x:xmpmeta/>',
    );
    final stripped = codec.stripMetadata(stamped);
    expect(stripped.length, lessThan(stamped.length));
    expect(codec.read(stripped).metadata.hasExifBlock, isFalse);
    expect(codec.stripMetadata(stamped), stripped);
  });

  test('戳记可往返解析', () {
    final stamp = sampleStamp(sha: 'd' * 64);
    final decoded = WatermarkStamp.decode(stamp.encode());
    expect(decoded, isNotNull);
    expect(decoded!.source, PhotoSource.camera);
    expect(decoded.mode, CaptureMode.forensics);
    expect(decoded.templateId, 'default');
    expect(decoded.position!.latitude, closeTo(30.274084, 1e-6));
    expect(decoded.fileSha256, 'd' * 64);
    expect(decoded.capturedAt.year, 2026);
  });
}
