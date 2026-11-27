import 'dart:convert';
import 'dart:typed_data';

import '../models/photo_metadata.dart';
import '../models/types.dart';

/// 纯 Dart 的 JPEG / EXIF(TIFF) 读写实现。
///
/// 之所以不用第三方 exif 包：水印可信链路必须能精确控制"保留哪些标签、追加哪些标签"，
/// 并且要能在纯 Dart 单测里做往返校验（读 → 改 → 写 → 再读）。
class ExifCodec {
  const ExifCodec();

  static const int _tagMake = 0x010F;
  static const int _tagModel = 0x0110;
  static const int _tagOrientation = 0x0112;
  static const int _tagSoftware = 0x0131;
  static const int _tagDateTime = 0x0132;
  static const int _tagExifIfd = 0x8769;
  static const int _tagGpsIfd = 0x8825;
  static const int _tagDateTimeOriginal = 0x9003;
  static const int _tagUserComment = 0x9286;
  static const int _tagMakerNote = 0x927C;

  static const int _gpsLatRef = 0x0001;
  static const int _gpsLat = 0x0002;
  static const int _gpsLonRef = 0x0003;
  static const int _gpsLon = 0x0004;
  static const int _gpsAltRef = 0x0005;
  static const int _gpsAlt = 0x0006;

  /// 读取 JPEG 的 EXIF 信息。非 JPEG 或没有 EXIF 时返回 [PhotoMetadata.unknown] 的派生值。
  ExifInfo read(Uint8List bytes) {
    final exifPayload = _findApp1Exif(bytes);
    final hasXmp = _findXmp(bytes) != null;
    if (exifPayload == null) {
      return ExifInfo(
        metadata: PhotoMetadata(hasXmpPacket: hasXmp),
        raw: null,
      );
    }
    try {
      final tiff = _TiffReader(exifPayload, 6);
      final ifd0 = tiff.readIfd(tiff.firstIfdOffset);
      final exifOffset = _asLong(ifd0[_tagExifIfd]);
      final gpsOffset = _asLong(ifd0[_tagGpsIfd]);
      final exifIfd = exifOffset == null ? <int, _Entry>{} : tiff.readIfd(exifOffset);
      final gpsIfd = gpsOffset == null ? <int, _Entry>{} : tiff.readIfd(gpsOffset);

      final userComment = _decodeUserComment(exifIfd[_tagUserComment]);
      final meta = PhotoMetadata(
        takenAt: _parseExifDate(_asAscii(exifIfd[_tagDateTimeOriginal]) ??
            _asAscii(ifd0[_tagDateTime])),
        gps: _readGps(gpsIfd),
        altitudeMeters: _readAltitude(gpsIfd),
        make: _asAscii(ifd0[_tagMake]),
        model: _asAscii(ifd0[_tagModel]),
        orientation: _asShort(ifd0[_tagOrientation]) ?? 1,
        software: _asAscii(ifd0[_tagSoftware]),
        userComment: userComment,
        hasExifBlock: true,
        hasXmpPacket: hasXmp,
        hasQingyangMarker:
            (userComment?.contains('${WatermarkStamp.prefix}|') ?? false) ||
                (_findXmp(bytes)?.contains('qingyang:') ?? false),
      );
      return ExifInfo(
        metadata: meta,
        raw: _RawExif(ifd0: ifd0, exifIfd: exifIfd, gpsIfd: gpsIfd),
      );
    } catch (_) {
      return ExifInfo(
        metadata: PhotoMetadata(hasExifBlock: true, hasXmpPacket: hasXmp),
        raw: null,
      );
    }
  }

  /// 写入/追加标签并返回新的 JPEG 字节。
  ///
  /// 保留原图的 DateTimeOriginal、GPS、Make（不修改），只追加 Software 与 UserComment；
  /// MakerNote 因内部绝对偏移在重排后会失效，主动丢弃并在日志中说明。
  Uint8List write(
    Uint8List jpegBytes, {
    String? software,
    String? userComment,
    DateTime? dateTimeOriginal,
    GeoPoint? gps,
    double? altitudeMeters,
    bool keepExistingGps = true,
  }) {
    final info = read(jpegBytes);
    final raw = info.raw;

    final ifd0 = <_Entry>[
      ...?_copyEntries(raw?.ifd0, skip: {_tagSoftware, _tagExifIfd, _tagGpsIfd}),
    ];
    if (software != null) {
      ifd0.add(_Entry.ascii(_tagSoftware, software));
    }

    final exif = <_Entry>[
      ...?_copyEntries(raw?.exifIfd, skip: {_tagUserComment, _tagMakerNote}),
    ];
    if (userComment != null) {
      exif.add(_Entry.userComment(_tagUserComment, userComment));
    }
    final existingOriginal = raw?.exifIfd[_tagDateTimeOriginal];
    if (dateTimeOriginal != null && existingOriginal == null) {
      exif.add(_Entry.ascii(_tagDateTimeOriginal, _formatExifDate(dateTimeOriginal)));
    }

    var gpsEntries = <_Entry>[];
    if (keepExistingGps && raw != null && raw.gpsIfd.isNotEmpty) {
      gpsEntries = [..._copyEntries(raw.gpsIfd, skip: const {})!];
    } else if (gps != null && gps.isValid) {
      gpsEntries = _buildGps(gps, altitudeMeters);
    }

    final tiff = _TiffWriter.build(
      ifd0: ifd0,
      exifIfd: exif,
      gpsIfd: gpsEntries,
    );

    final payload = Uint8List(6 + tiff.length)
      ..[0] = 0x45
      ..[1] = 0x78
      ..[2] = 0x69
      ..[3] = 0x66
      ..[4] = 0
      ..[5] = 0;
    payload.setRange(6, payload.length, tiff);

    return spliceApp1(jpegBytes, [payload]);
  }

  /// 把 XMP 包写入 APP1（与 EXIF 并存，互不覆盖）。
  Uint8List writeXmp(Uint8List jpegBytes, String xmpXml) {
    final body = Uint8List.fromList([
      ...utf8.encode('http://ns.adobe.com/xap/1.0/\u0000'),
      ...utf8.encode(xmpXml),
    ]);
    // 只替换旧 XMP，保留刚写入的 EXIF。
    return spliceApp1(jpegBytes, [body], replaceExif: false);
  }

  /// 去掉 EXIF/XMP 段后的"纯像素流"。用于计算不受元数据写入影响的稳定哈希。
  Uint8List stripMetadata(Uint8List jpeg) => spliceApp1(jpeg, const <Uint8List>[]);

  /// 用新的 APP1 段替换指定的旧段，其余段原样保留。
  ///
  /// [replaceExif] / [replaceXmp] 控制是否丢弃旧段：写 XMP 时必须保留刚写好的 EXIF。
  Uint8List spliceApp1(
    Uint8List jpeg,
    List<Uint8List> app1Payloads, {
    bool replaceExif = true,
    bool replaceXmp = true,
  }) {
    if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) {
      throw const FormatException('不是合法的 JPEG 数据');
    }
    final output = BytesBuilder(copy: false);
    output.add([0xFF, 0xD8]);

    var index = 2;
    // 保留 APP0(JFIF)，插在其后。
    while (index + 4 <= jpeg.length && jpeg[index] == 0xFF) {
      final marker = jpeg[index + 1];
      if (marker == 0xDA) break;
      if (marker == 0xE1) {
        final length = (jpeg[index + 2] << 8) | jpeg[index + 3];
        final payloadEnd = index + 2 + length;
        final payloadStart = index + 4;
        if (payloadEnd > jpeg.length) break;
        final payload = jpeg.sublist(payloadStart, payloadEnd);
        final isExif = _startsWith(payload, const [0x45, 0x78, 0x69, 0x66, 0, 0]);
        final isXmp = _startsWith(payload, utf8.encode('http://ns.adobe.com/xap/1.0/\u0000'));
        if ((isExif && replaceExif) || (isXmp && replaceXmp)) {
          index = payloadEnd;
          continue;
        }
      }
      break;
    }

    for (final payload in app1Payloads) {
      final length = payload.length + 2;
      output.add([0xFF, 0xE1, (length >> 8) & 0xFF, length & 0xFF]);
      output.add(payload);
    }
    output.add(Uint8List.sublistView(jpeg, index));
    return output.takeBytes();
  }

  // ---- 内部解析辅助 ----

  Uint8List? _findApp1Exif(Uint8List jpeg) {
    for (final segment in _segments(jpeg)) {
      if (segment.marker != 0xE1) continue;
      if (_startsWith(segment.payload, const [0x45, 0x78, 0x69, 0x66, 0, 0])) {
        return segment.payload;
      }
    }
    return null;
  }

  String? _findXmp(Uint8List jpeg) {
    final header = utf8.encode('http://ns.adobe.com/xap/1.0/\u0000');
    for (final segment in _segments(jpeg)) {
      if (segment.marker != 0xE1) continue;
      if (_startsWith(segment.payload, header)) {
        try {
          return utf8.decode(
            segment.payload.sublist(header.length),
            allowMalformed: true,
          );
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }

  static List<_Segment> _segments(Uint8List jpeg) {
    final segments = <_Segment>[];
    if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) return segments;
    var index = 2;
    while (index + 4 <= jpeg.length) {
      if (jpeg[index] != 0xFF) break;
      final marker = jpeg[index + 1];
      if (marker == 0xDA || marker == 0xD9) break;
      final length = (jpeg[index + 2] << 8) | jpeg[index + 3];
      if (length < 2) break;
      final end = index + 2 + length;
      if (end > jpeg.length) break;
      segments.add(_Segment(marker, jpeg.sublist(index + 4, end)));
      index = end;
    }
    return segments;
  }

  static bool _startsWith(Uint8List data, List<int> prefix) {
    if (data.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (data[index] != prefix[index]) return false;
    }
    return true;
  }

  static int? _asLong(_Entry? entry) {
    if (entry == null || entry.raw.length < 4) return null;
    return ByteData.sublistView(entry.raw).getUint32(0, entry.endian);
  }

  static int? _asShort(_Entry? entry) {
    if (entry == null || entry.raw.length < 2) return null;
    return ByteData.sublistView(entry.raw).getUint16(0, entry.endian);
  }

  static String? _asAscii(_Entry? entry) {
    if (entry == null) return null;
    final bytes = entry.raw;
    final end = bytes.indexOf(0) >= 0 ? bytes.indexOf(0) : bytes.length;
    if (end <= 0) return null;
    final text = utf8.decode(bytes.sublist(0, end), allowMalformed: true).trim();
    return text.isEmpty ? null : text;
  }

  static String? _decodeUserComment(_Entry? entry) {
    if (entry == null || entry.raw.isEmpty) return null;
    final bytes = entry.raw;
    if (bytes.length > 8) {
      final prefix = ascii.decode(bytes.sublist(0, 8), allowInvalid: true);
      if (prefix.startsWith('UNICODE')) {
        final body = bytes.sublist(8);
        try {
          return String.fromCharCodes(
            List<int>.generate(
              body.length ~/ 2,
              (index) => body[index * 2] | (body[index * 2 + 1] << 8),
            ),
          );
        } catch (_) {
          return null;
        }
      }
      if (prefix.startsWith('ASCII')) {
        return utf8.decode(bytes.sublist(8), allowMalformed: true).trim();
      }
    }
    return utf8.decode(bytes, allowMalformed: true).trim();
  }

  static List<_Entry>? _copyEntries(Map<int, _Entry>? source,
      {required Set<int> skip}) {
    if (source == null) return null;
    return source.values
        .where((entry) => !skip.contains(entry.tag))
        .map((entry) => entry.copy())
        .toList(growable: true);
  }

  static List<_Entry> _buildGps(GeoPoint point, double? altitude) {
    final entries = <_Entry>[];
    entries.add(_Entry.ascii(_gpsLatRef, point.latitude >= 0 ? 'N' : 'S'));
    entries.add(_Entry.rationals(
        _gpsLat, _toDmsRationals(point.latitude.abs())));
    entries.add(_Entry.ascii(_gpsLonRef, point.longitude >= 0 ? 'E' : 'W'));
    entries.add(_Entry.rationals(
        _gpsLon, _toDmsRationals(point.longitude.abs())));
    if (altitude != null) {
      entries.add(_Entry.byte(_gpsAltRef, altitude < 0 ? 1 : 0));
      entries.add(_Entry.rationals(
          _gpsAlt, [_Rational(altitude.abs().round(), 1)]));
    }
    return entries;
  }

  static List<_Rational> _toDmsRationals(double value) {
    final degree = value.floor();
    final minuteFull = (value - degree) * 60;
    final minute = minuteFull.floor();
    final second = ((minuteFull - minute) * 60 * 10000).round();
    return [
      _Rational(degree, 1),
      _Rational(minute, 1),
      _Rational(second, 10000),
    ];
  }

  static GeoPoint? _readGps(Map<int, _Entry> gps) {
    final lat = _readRationalTriplet(gps[_gpsLat]);
    final lon = _readRationalTriplet(gps[_gpsLon]);
    if (lat == null || lon == null) return null;
    final latRef = _asAscii(gps[_gpsLatRef]) ?? 'N';
    final lonRef = _asAscii(gps[_gpsLonRef]) ?? 'E';
    final latitude = latRef.toUpperCase().startsWith('S') ? -lat : lat;
    final longitude = lonRef.toUpperCase().startsWith('W') ? -lon : lon;
    final point = GeoPoint(latitude: latitude, longitude: longitude);
    return point.isValid ? point : null;
  }

  static double? _readAltitude(Map<int, _Entry> gps) {
    final entry = gps[_gpsAlt];
    if (entry == null) return null;
    final value = _readRationalTriplet(entry, single: true);
    if (value == null) return null;
    final ref = _asShort(gps[_gpsAltRef]) ?? 0;
    return ref == 1 ? -value : value;
  }

  static double? _readRationalTriplet(_Entry? entry, {bool single = false}) {
    if (entry == null || entry.raw.length < 8) return null;
    final data = ByteData.sublistView(entry.raw);
    final first = data.getUint32(0, entry.endian) /
        (data.getUint32(4, entry.endian) == 0
            ? 1
            : data.getUint32(4, entry.endian));
    if (single || entry.count < 3 || entry.raw.length < 24) return first;
    final second = data.getUint32(8, entry.endian) /
        (data.getUint32(12, entry.endian) == 0
            ? 1
            : data.getUint32(12, entry.endian));
    final third = data.getUint32(16, entry.endian) /
        (data.getUint32(20, entry.endian) == 0
            ? 1
            : data.getUint32(20, entry.endian));
    return first + second / 60 + third / 3600;
  }

  static DateTime? _parseExifDate(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})')
        .firstMatch(value.trim());
    if (match == null) return null;
    try {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
    } catch (_) {
      return null;
    }
  }

  static String _formatExifDate(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year.toString().padLeft(4, '0')}:${two(local.month)}:'
        '${two(local.day)} ${two(local.hour)}:${two(local.minute)}:'
        '${two(local.second)}';
  }
}

class ExifInfo {
  const ExifInfo({required this.metadata, required this.raw});

  final PhotoMetadata metadata;
  final _RawExif? raw;
}

class _RawExif {
  const _RawExif({
    required this.ifd0,
    required this.exifIfd,
    required this.gpsIfd,
  });

  final Map<int, _Entry> ifd0;
  final Map<int, _Entry> exifIfd;
  final Map<int, _Entry> gpsIfd;
}

class _Segment {
  const _Segment(this.marker, this.payload);

  final int marker;
  final Uint8List payload;
}

class _Rational {
  const _Rational(this.numerator, this.denominator);

  final int numerator;
  final int denominator;
}

class _Entry {
  _Entry(this.tag, this.type, this.count, this.raw, this.endian);

  factory _Entry.ascii(int tag, String value) {
    final bytes = utf8.encode(value);
    final data = Uint8List(bytes.length + 1)..setRange(0, bytes.length, bytes);
    return _Entry(tag, 2, data.length, data, Endian.little);
  }

  factory _Entry.userComment(int tag, String value) {
    final body = utf8.encode(value);
    final data = Uint8List(8 + body.length)
      ..setRange(0, 8, ascii.encode('ASCII\u0000\u0000\u0000'))
      ..setRange(8, 8 + body.length, body);
    return _Entry(tag, 7, data.length, data, Endian.little);
  }

  factory _Entry.byte(int tag, int value) =>
      _Entry(tag, 1, 1, Uint8List.fromList([value & 0xFF]), Endian.little);

  factory _Entry.rationals(int tag, List<_Rational> values) {
    final data = ByteData(values.length * 8);
    for (var index = 0; index < values.length; index++) {
      data.setUint32(index * 8, values[index].numerator, Endian.little);
      data.setUint32(index * 8 + 4, values[index].denominator, Endian.little);
    }
    return _Entry(tag, 5, values.length, data.buffer.asUint8List(), Endian.little);
  }

  final int tag;
  final int type;
  final int count;
  final Uint8List raw;
  final Endian endian;

  int get typeSize {
    switch (type) {
      case 1:
      case 2:
      case 7:
        return 1;
      case 3:
        return 2;
      case 4:
      case 9:
        return 4;
      case 5:
      case 10:
        return 8;
      default:
        return 1;
    }
  }

  /// 复制到输出字节序（始终为小端）。原图若为大端，数值型需要逐单元翻转。
  _Entry copy() {
    var bytes = Uint8List.fromList(raw);
    if (endian == Endian.big) {
      final unit = (type == 5 || type == 10) ? 4 : typeSize;
      if (unit == 2 || unit == 4) {
        final flipped = Uint8List(bytes.length);
        for (var offset = 0; offset + unit <= bytes.length; offset += unit) {
          for (var index = 0; index < unit; index++) {
            flipped[offset + index] = bytes[offset + unit - 1 - index];
          }
        }
        bytes = flipped;
      }
    }
    return _Entry(tag, type, count, bytes, Endian.little);
  }
}

class _TiffReader {
  _TiffReader(Uint8List payload, this.baseOffset) {
    final header = ByteData.sublistView(payload);
    if (payload.length < baseOffset + 8) {
      throw const FormatException('EXIF 数据过短');
    }
    final byteOrder = header.getUint16(baseOffset, Endian.big);
    endian = byteOrder == 0x4949 ? Endian.little : Endian.big;
    _data = header;
    _base = baseOffset;
    _payload = payload;
  }

  late final Endian endian;
  late final ByteData _data;
  late final int _base;
  late final Uint8List _payload;
  final int baseOffset;

  int get firstIfdOffset => _data.getUint32(_base + 4, endian);

  Map<int, _Entry> readIfd(int offset) {
    final result = <int, _Entry>{};
    final absolute = _base + offset;
    if (absolute + 2 > _payload.length) return result;
    final count = _data.getUint16(absolute, endian);
    for (var index = 0; index < count; index++) {
      final entryOffset = absolute + 2 + index * 12;
      if (entryOffset + 12 > _payload.length) break;
      final tag = _data.getUint16(entryOffset, endian);
      final type = _data.getUint16(entryOffset + 2, endian);
      final valueCount = _data.getUint32(entryOffset + 4, endian);
      final typeSize = _typeSize(type);
      final total = typeSize * valueCount;
      Uint8List raw;
      if (total <= 4) {
        raw = Uint8List.fromList(
            _payload.sublist(entryOffset + 8, entryOffset + 8 + total));
      } else {
        final valueOffset = _data.getUint32(entryOffset + 8, endian);
        final start = _base + valueOffset;
        final end = start + total;
        if (start < 0 || end > _payload.length) continue;
        raw = Uint8List.fromList(_payload.sublist(start, end));
      }
      result[tag] = _Entry(tag, type, valueCount, raw, endian);
    }
    return result;
  }

  static int _typeSize(int type) {
    switch (type) {
      case 1:
      case 2:
      case 6:
      case 7:
        return 1;
      case 3:
      case 8:
        return 2;
      case 4:
      case 9:
      case 11:
        return 4;
      case 5:
      case 10:
      case 12:
        return 8;
      default:
        return 1;
    }
  }
}

class _TiffWriter {
  const _TiffWriter._();

  static Uint8List build({
    required List<_Entry> ifd0,
    required List<_Entry> exifIfd,
    required List<_Entry> gpsIfd,
  }) {
    final hasExif = exifIfd.isNotEmpty;
    final hasGps = gpsIfd.isNotEmpty;

    final ifd0Entries = <_Entry>[...ifd0];
    final ifd0Count = ifd0Entries.length + (hasExif ? 1 : 0) + (hasGps ? 1 : 0);

    final ifd0Size = 2 + ifd0Count * 12 + 4;
    final exifOffset = 8 + ifd0Size;
    final exifSize = hasExif ? 2 + exifIfd.length * 12 + 4 : 0;
    final gpsOffset = exifOffset + exifSize;
    final gpsSize = hasGps ? 2 + gpsIfd.length * 12 + 4 : 0;
    var dataOffset = gpsOffset + gpsSize;

    final header = BytesBuilder(copy: false);
    header.add(const [0x49, 0x49, 0x2A, 0x00]);
    header.add(_u32(8));

    final dataArea = BytesBuilder(copy: false);

    void writeIfd(BytesBuilder target, List<_Entry> entries) {
      target.add(_u16(entries.length));
      for (final entry in entries) {
        target.add(_u16(entry.tag));
        target.add(_u16(entry.type));
        target.add(_u32(entry.count));
        if (entry.raw.length <= 4) {
          final inline = Uint8List(4)..setRange(0, entry.raw.length, entry.raw);
          target.add(inline);
        } else {
          target.add(_u32(dataOffset));
          dataArea.add(entry.raw);
          dataOffset += entry.raw.length;
          if (entry.raw.length.isOdd) {
            dataArea.addByte(0);
            dataOffset += 1;
          }
        }
      }
      target.add(_u32(0));
    }

    if (hasExif) {
      ifd0Entries.add(_Entry(0x8769, 4, 1, _u32(exifOffset), Endian.little));
    }
    if (hasGps) {
      ifd0Entries.add(_Entry(0x8825, 4, 1, _u32(gpsOffset), Endian.little));
    }

    writeIfd(header, ifd0Entries);
    if (hasExif) writeIfd(header, exifIfd);
    if (hasGps) writeIfd(header, gpsIfd);

    header.add(dataArea.takeBytes());
    return header.takeBytes();
  }

  static Uint8List _u16(int value) => Uint8List(2)
    ..[0] = value & 0xFF
    ..[1] = (value >> 8) & 0xFF;

  static Uint8List _u32(int value) => Uint8List(4)
    ..[0] = value & 0xFF
    ..[1] = (value >> 8) & 0xFF
    ..[2] = (value >> 16) & 0xFF
    ..[3] = (value >> 24) & 0xFF;
}
