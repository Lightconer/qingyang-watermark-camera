import '../models/types.dart';

/// 台账一行：文件名、来源、拍摄时间、处理时间、经纬度、地址、备注 + 校验信息。
class LedgerEntry {
  const LedgerEntry({
    required this.fileName,
    required this.outputPath,
    required this.source,
    required this.templateId,
    required this.mode,
    required this.sha256,
    required this.processedAt,
    this.originalPath,
    this.capturedAt,
    this.position,
    this.altitudeMeters,
    this.address,
    this.note,
    this.operatorName,
    this.organization,
    this.timeAuthority = TimeAuthority.missing,
    this.coordAuthority = CoordAuthority.missing,
    this.fingerprint,
  });

  final String fileName;
  final String outputPath;
  final String? originalPath;
  final PhotoSource source;
  final String templateId;
  final CaptureMode mode;
  final String sha256;
  final DateTime processedAt;
  final DateTime? capturedAt;
  final GeoPoint? position;
  final double? altitudeMeters;
  final String? address;
  final String? note;
  final String? operatorName;
  final String? organization;
  final TimeAuthority timeAuthority;
  final CoordAuthority coordAuthority;
  final String? fingerprint;

  static const List<String> columns = [
    '文件名',
    '来源',
    '拍摄时间',
    '处理时间',
    '纬度',
    '经度',
    '海拔(米)',
    '地址',
    '模板',
    '模式',
    '时间口径',
    '坐标口径',
    '采集人',
    '单位',
    '备注',
    'SHA256',
  ];

  List<Object?> toRow() => [
        fileName,
        source.label,
        _fmt(capturedAt),
        _fmt(processedAt)!,
        position?.latitude.toStringAsFixed(7) ?? '',
        position?.longitude.toStringAsFixed(7) ?? '',
        altitudeMeters?.toStringAsFixed(1) ?? '',
        address ?? '',
        templateId,
        mode.label,
        timeAuthority.label,
        coordAuthority.label,
        operatorName ?? '',
        organization ?? '',
        note ?? '',
        sha256,
      ];

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'outputPath': outputPath,
        'originalPath': originalPath,
        'source': source.code,
        'templateId': templateId,
        'mode': mode.name,
        'sha256': sha256,
        'processedAt': processedAt.toIso8601String(),
        'capturedAt': capturedAt?.toIso8601String(),
        'position': position?.toJson(),
        'altitudeMeters': altitudeMeters,
        'address': address,
        'note': note,
        'operatorName': operatorName,
        'organization': organization,
        'timeAuthority': timeAuthority.name,
        'coordAuthority': coordAuthority.name,
        'fingerprint': fingerprint,
      };

  static LedgerEntry? fromJson(Map<String, dynamic> json) {
    final fileName = json['fileName'];
    if (fileName is! String) return null;
    return LedgerEntry(
      fileName: fileName,
      outputPath: '${json['outputPath'] ?? ''}',
      originalPath: json['originalPath'] as String?,
      source: PhotoSourceX.fromCode(json['source'] as String?),
      templateId: '${json['templateId'] ?? ''}',
      mode: CaptureModeX.fromCode(json['mode'] as String?),
      sha256: '${json['sha256'] ?? ''}',
      processedAt: DateTime.tryParse('${json['processedAt']}') ?? DateTime.now(),
      capturedAt: DateTime.tryParse('${json['capturedAt']}'),
      position: GeoPoint.fromJson(json['position'] as Map<String, dynamic>?),
      altitudeMeters: (json['altitudeMeters'] as num?)?.toDouble(),
      address: json['address'] as String?,
      note: json['note'] as String?,
      operatorName: json['operatorName'] as String?,
      organization: json['organization'] as String?,
      timeAuthority: TimeAuthority.values.firstWhere(
        (value) => value.name == json['timeAuthority'],
        orElse: () => TimeAuthority.missing,
      ),
      coordAuthority: CoordAuthority.values.firstWhere(
        (value) => value.name == json['coordAuthority'],
        orElse: () => CoordAuthority.missing,
      ),
      fingerprint: json['fingerprint'] as String?,
    );
  }

  static String? _fmt(DateTime? time) {
    if (time == null) return null;
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}
