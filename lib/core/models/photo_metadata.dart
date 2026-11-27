import 'dart:convert';

import 'types.dart';

/// 从文件读取到的照片元数据。渲染层只依赖本模型，不感知来源（拍摄 / 导入 EXIF）。
class PhotoMetadata {
  const PhotoMetadata({
    this.takenAt,
    this.gps,
    this.altitudeMeters,
    this.make,
    this.model,
    this.orientation = 1,
    this.pixelWidth,
    this.pixelHeight,
    this.software,
    this.userComment,
    this.hasExifBlock = false,
    this.hasXmpPacket = false,
    this.hasQingyangMarker = false,
  });

  static const PhotoMetadata unknown = PhotoMetadata();

  final DateTime? takenAt;
  final GeoPoint? gps;
  final double? altitudeMeters;
  final String? make;
  final String? model;

  /// EXIF Orientation，1..8。绘制前必须先按它转正。
  final int orientation;
  final int? pixelWidth;
  final int? pixelHeight;
  final String? software;
  final String? userComment;
  final bool hasExifBlock;
  final bool hasXmpPacket;

  /// 是否已带青阳水印标记（EXIF UserComment 或 XMP 中的 QY1 标记），用于防二次叠加。
  final bool hasQingyangMarker;

  bool get hasGps => gps != null && gps!.isValid;

  /// 若原图 Orientation 属于需要旋转的 5..8（含镜像），返回 true。
  bool get needsRotation => orientation > 1;

  PhotoMetadata copyWith({
    DateTime? takenAt,
    GeoPoint? gps,
    double? altitudeMeters,
    String? make,
    String? model,
    int? orientation,
    int? pixelWidth,
    int? pixelHeight,
    String? software,
    String? userComment,
    bool? hasExifBlock,
    bool? hasXmpPacket,
    bool? hasQingyangMarker,
  }) {
    return PhotoMetadata(
      takenAt: takenAt ?? this.takenAt,
      gps: gps ?? this.gps,
      altitudeMeters: altitudeMeters ?? this.altitudeMeters,
      make: make ?? this.make,
      model: model ?? this.model,
      orientation: orientation ?? this.orientation,
      pixelWidth: pixelWidth ?? this.pixelWidth,
      pixelHeight: pixelHeight ?? this.pixelHeight,
      software: software ?? this.software,
      userComment: userComment ?? this.userComment,
      hasExifBlock: hasExifBlock ?? this.hasExifBlock,
      hasXmpPacket: hasXmpPacket ?? this.hasXmpPacket,
      hasQingyangMarker: hasQingyangMarker ?? this.hasQingyangMarker,
    );
  }

  Map<String, dynamic> toJson() => {
        'takenAt': takenAt?.toIso8601String(),
        'gps': gps?.toJson(),
        'altitudeMeters': altitudeMeters,
        'make': make,
        'model': model,
        'orientation': orientation,
        'pixelWidth': pixelWidth,
        'pixelHeight': pixelHeight,
        'software': software,
        'userComment': userComment,
        'hasExifBlock': hasExifBlock,
        'hasXmpPacket': hasXmpPacket,
        'hasQingyangMarker': hasQingyangMarker,
      };

  static PhotoMetadata fromJson(Map<String, dynamic> json) {
    return PhotoMetadata(
      takenAt: DateTime.tryParse('${json['takenAt']}'),
      gps: GeoPoint.fromJson(json['gps'] as Map<String, dynamic>?),
      altitudeMeters: (json['altitudeMeters'] as num?)?.toDouble(),
      make: json['make'] as String?,
      model: json['model'] as String?,
      orientation: (json['orientation'] as num?)?.toInt() ?? 1,
      pixelWidth: (json['pixelWidth'] as num?)?.toInt(),
      pixelHeight: (json['pixelHeight'] as num?)?.toInt(),
      software: json['software'] as String?,
      userComment: json['userComment'] as String?,
      hasExifBlock: json['hasExifBlock'] == true,
      hasXmpPacket: json['hasXmpPacket'] == true,
      hasQingyangMarker: json['hasQingyangMarker'] == true,
    );
  }
}

/// 埋入成品的可信戳记。EXIF UserComment 与 XMP 双写，构成"像素 + 元数据"双重留痕。
class WatermarkStamp {
  const WatermarkStamp({
    required this.source,
    required this.mode,
    required this.templateId,
    required this.capturedAt,
    required this.timeAuthority,
    required this.coordAuthority,
    this.position,
    this.altitudeMeters,
    this.address,
    this.fingerprint,
    this.fileSha256,
    this.operator,
    this.organization,
    this.project,
    this.note,
  });

  static const String prefix = 'QY1';
  static const String xmpNamespace = 'https://qingyang.app/ns/watermark/1.0/';

  final PhotoSource source;
  final CaptureMode mode;
  final String templateId;
  final DateTime capturedAt;
  final TimeAuthority timeAuthority;
  final CoordAuthority coordAuthority;
  final GeoPoint? position;
  final double? altitudeMeters;
  final String? address;

  /// 绘制哈希小字之前的内容指纹（SHA256）。
  final String? fingerprint;

  /// 成品文件 SHA256（写入 EXIF/XMP/台账，用于篡改比对）。
  final String? fileSha256;
  final String? operator;
  final String? organization;
  final String? project;
  final String? note;

  /// `QY1|src=camera|mode=forensics|t=...|lat=...`
  String encode() {
    final parts = <String>[
      prefix,
      'src=${source.code}',
      'mode=${mode.name}',
      'tpl=$templateId',
      't=${capturedAt.toUtc().toIso8601String()}',
      'tz=${capturedAt.timeZoneOffset.inMinutes}',
      'ta=${timeAuthority.name}',
      'ca=${coordAuthority.name}',
      if (position != null) 'lat=${position!.latitude.toStringAsFixed(7)}',
      if (position != null) 'lon=${position!.longitude.toStringAsFixed(7)}',
      if (altitudeMeters != null) 'alt=${altitudeMeters!.toStringAsFixed(1)}',
      if (fingerprint != null) 'fp=${fingerprint!}',
      if (fileSha256 != null) 'sha=${fileSha256!}',
      if (operator != null && operator!.isNotEmpty) 'op=$operator',
      if (organization != null && organization!.isNotEmpty) 'org=$organization',
      if (project != null && project!.isNotEmpty) 'pj=$project',
      if (note != null && note!.isNotEmpty) 'nt=$note',
    ];
    return '${AppIdentity.softwareTag} ${parts.join('|')}';
  }

  /// 解析 UserComment / XMP 中的戳记。解析失败返回 null。
  static WatermarkStamp? decode(String? raw) {
    if (raw == null) return null;
    final index = raw.indexOf('$prefix|');
    if (index < 0) return null;
    final payload = raw.substring(index);
    final fields = <String, String>{};
    for (final token in payload.split('|').skip(1)) {
      final eq = token.indexOf('=');
      if (eq <= 0) continue;
      fields[token.substring(0, eq)] = token.substring(eq + 1);
    }
    final takenAt = DateTime.tryParse(fields['t'] ?? '');
    final tz = int.tryParse(fields['tz'] ?? '') ?? 0;
    if (takenAt == null) return null;
    final lat = double.tryParse(fields['lat'] ?? '');
    final lon = double.tryParse(fields['lon'] ?? '');
    return WatermarkStamp(
      source: PhotoSourceX.fromCode(fields['src']),
      mode: CaptureModeX.fromCode(fields['mode']),
      templateId: fields['tpl'] ?? '',
      capturedAt: takenAt.add(Duration(minutes: tz)),
      timeAuthority: TimeAuthority.values.firstWhere(
        (value) => value.name == fields['ta'],
        orElse: () => TimeAuthority.missing,
      ),
      coordAuthority: CoordAuthority.values.firstWhere(
        (value) => value.name == fields['ca'],
        orElse: () => CoordAuthority.missing,
      ),
      position: (lat != null && lon != null)
          ? GeoPoint(latitude: lat, longitude: lon)
          : null,
      altitudeMeters: double.tryParse(fields['alt'] ?? ''),
      fingerprint: fields['fp'],
      fileSha256: fields['sha'],
      operator: fields['op'],
      organization: fields['org'],
      project: fields['pj'],
      note: fields['nt'],
    );
  }

  String toJsonString() => jsonEncode({
        'source': source.code,
        'mode': mode.name,
        'templateId': templateId,
        'capturedAt': capturedAt.toIso8601String(),
        'timeAuthority': timeAuthority.name,
        'coordAuthority': coordAuthority.name,
        'position': position?.toJson(),
        'altitudeMeters': altitudeMeters,
        'address': address,
        'fingerprint': fingerprint,
        'fileSha256': fileSha256,
        'operator': operator,
        'organization': organization,
        'project': project,
        'note': note,
      });
}
