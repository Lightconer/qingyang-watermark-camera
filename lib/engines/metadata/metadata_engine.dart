import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/metadata/exif_codec.dart';
import '../../core/metadata/xmp.dart';
import '../../core/models/photo_metadata.dart';
import '../../core/models/types.dart';

/// 扩展点三：元数据来源适配器。
///
/// 拍摄链路与导入链路各自实现一套，渲染层只拿到统一的 [PhotoMetadata] 与写入结果，
/// 不感知来源。新增来源（例如执法记录仪同步）只需再加一个实现。
abstract class MetadataProvider {
  String get id;

  /// 是否负责该来源。
  bool supports(PhotoSource source);

  /// 读取文件元数据。
  Future<PhotoMetadata> read(String path);

  /// 把戳记写入 JPEG 字节并返回新字节。
  Future<Uint8List> write(
    Uint8List jpegBytes, {
    required WatermarkStamp stamp,
    required PhotoMetadata original,
    DateTime? dateTimeOriginal,
    GeoPoint? gps,
    double? altitudeMeters,
  });
}

/// 拍摄链路：时间与坐标来自快门冻结的上下文，写入 DateTimeOriginal 与 GPS。
class CameraMetadataProvider implements MetadataProvider {
  CameraMetadataProvider({this.exifCodec = const ExifCodec()});

  final ExifCodec exifCodec;

  @override
  String get id => 'metadata.camera';

  @override
  bool supports(PhotoSource source) => source == PhotoSource.camera;

  @override
  Future<PhotoMetadata> read(String path) async {
    final bytes = await File(path).readAsBytes();
    return exifCodec.read(bytes).metadata;
  }

  @override
  Future<Uint8List> write(
    Uint8List jpegBytes, {
    required WatermarkStamp stamp,
    required PhotoMetadata original,
    DateTime? dateTimeOriginal,
    GeoPoint? gps,
    double? altitudeMeters,
  }) async {
    final withExif = exifCodec.write(
      jpegBytes,
      software: '${AppIdentity.softwareTag} ${AppIdentity.schemaVersion}',
      userComment: stamp.encode(),
      dateTimeOriginal: dateTimeOriginal,
      gps: gps,
      altitudeMeters: altitudeMeters,
      keepExistingGps: false,
    );
    final xmp = XmpPacket.build(stamp: stamp, address: stamp.address);
    return exifCodec.writeXmp(withExif, xmp);
  }
}

/// 导入链路：只读原图元数据，写入时保留 DateTimeOriginal / GPS / Make，仅追加 Software 与 UserComment。
class ExifMetadataProvider implements MetadataProvider {
  ExifMetadataProvider({this.exifCodec = const ExifCodec()});

  final ExifCodec exifCodec;

  @override
  String get id => 'metadata.exif';

  @override
  bool supports(PhotoSource source) => source.isImport;

  @override
  Future<PhotoMetadata> read(String path) async {
    final bytes = await File(path).readAsBytes();
    return exifCodec.read(bytes).metadata;
  }

  @override
  Future<Uint8List> write(
    Uint8List jpegBytes, {
    required WatermarkStamp stamp,
    required PhotoMetadata original,
    DateTime? dateTimeOriginal,
    GeoPoint? gps,
    double? altitudeMeters,
  }) async {
    // 导入链路绝不改写原始拍摄时间与原始 GPS：dateTimeOriginal/gps 传 null。
    final withExif = exifCodec.write(
      jpegBytes,
      software: '${AppIdentity.softwareTag} ${AppIdentity.schemaVersion}',
      userComment: stamp.encode(),
      keepExistingGps: true,
    );
    final xmp = XmpPacket.build(stamp: stamp, address: stamp.address);
    return exifCodec.writeXmp(withExif, xmp);
  }
}

/// 测试替身：把写入内容记录在内存里。
class FakeMetadataProvider implements MetadataProvider {
  FakeMetadataProvider({this.id = 'metadata.fake'});

  @override
  final String id;

  final List<WatermarkStamp> written = [];

  @override
  bool supports(PhotoSource source) => true;

  @override
  Future<PhotoMetadata> read(String path) async => PhotoMetadata.unknown;

  @override
  Future<Uint8List> write(
    Uint8List jpegBytes, {
    required WatermarkStamp stamp,
    required PhotoMetadata original,
    DateTime? dateTimeOriginal,
    GeoPoint? gps,
    double? altitudeMeters,
  }) async {
    written.add(stamp);
    return jpegBytes;
  }
}

/// 元数据引擎：按来源分派到合适的 [MetadataProvider]。
class MetadataEngine {
  MetadataEngine({required List<MetadataProvider> providers, this.exifCodec = const ExifCodec()})
      : _providers = List<MetadataProvider>.unmodifiable(providers);

  final List<MetadataProvider> _providers;
  final ExifCodec exifCodec;

  List<MetadataProvider> get providers => _providers;

  MetadataProvider providerFor(PhotoSource source) {
    for (final provider in _providers) {
      if (provider.supports(source)) return provider;
    }
    // 兜底：EXIF 适配器（读多写少，宁可少写也不伪造）
    return _providers.first;
  }

  Future<PhotoMetadata> readFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return exifCodec.read(bytes).metadata;
  }

  /// 综合读取：EXIF 基础信息 + XMP 哈希。
  Future<MetadataSnapshot> snapshot(String path, {PhotoSource? source}) async {
    final bytes = await File(path).readAsBytes();
    final info = exifCodec.read(bytes);
    final xmp = ExifCodecInspector.extractXmp(bytes);
    return MetadataSnapshot(
      metadata: info.metadata,
      xmpSha256: XmpPacket.readFileSha256(xmp),
      xmpFingerprint: XmpPacket.readFingerprint(xmp),
    );
  }
}

class MetadataSnapshot {
  const MetadataSnapshot({
    required this.metadata,
    this.xmpSha256,
    this.xmpFingerprint,
  });

  final PhotoMetadata metadata;
  final String? xmpSha256;
  final String? xmpFingerprint;
}

/// 只读辅助：从字节里提取 XMP 原文（不写）。
class ExifCodecInspector {
  const ExifCodecInspector._();

  static const String _header = 'http://ns.adobe.com/xap/1.0/\u0000';

  static String? extractXmp(Uint8List bytes) {
    final start = _indexOfBytes(bytes, utf8.encode(_header));
    if (start < 0) return null;
    final end = _indexOfBytes(bytes, utf8.encode('<?xpacket end'), start);
    final stop = end < 0 ? bytes.length : math.min(end + 40, bytes.length);
    return utf8.decode(bytes.sublist(start, stop), allowMalformed: true);
  }

  static int _indexOfBytes(Uint8List data, List<int> pattern, [int from = 0]) {
    if (pattern.isEmpty) return -1;
    for (var index = from; index <= data.length - pattern.length; index++) {
      var matched = true;
      for (var offset = 0; offset < pattern.length; offset++) {
        if (data[index + offset] != pattern[offset]) {
          matched = false;
          break;
        }
      }
      if (matched) return index;
    }
    return -1;
  }
}
