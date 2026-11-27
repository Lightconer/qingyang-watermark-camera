import '../models/photo_metadata.dart';
import '../models/types.dart';

/// XMP 包构造与解析。与 EXIF 双写：任何一个被抹掉，另一个仍能还原采集事实。
class XmpPacket {
  const XmpPacket._();

  static String build({
    required WatermarkStamp stamp,
    String? address,
  }) {
    final attributes = <String, String>{
      'App': AppIdentity.appName,
      'AppId': AppIdentity.packageName,
      'Schema': AppIdentity.schemaVersion,
      'Watermarked': 'true',
      'Source': stamp.source.code,
      'Mode': stamp.mode.name,
      'Template': stamp.templateId,
      'CapturedAt': stamp.capturedAt.toUtc().toIso8601String(),
      'TzOffsetMinutes': '${stamp.capturedAt.timeZoneOffset.inMinutes}',
      'TimeAuthority': stamp.timeAuthority.name,
      'CoordAuthority': stamp.coordAuthority.name,
      if (stamp.position != null)
        'Latitude': stamp.position!.latitude.toStringAsFixed(7),
      if (stamp.position != null)
        'Longitude': stamp.position!.longitude.toStringAsFixed(7),
      if (stamp.altitudeMeters != null)
        'Altitude': stamp.altitudeMeters!.toStringAsFixed(1),
      if (stamp.fingerprint != null) 'Fingerprint': stamp.fingerprint!,
      if (stamp.fileSha256 != null) 'FileSha256': stamp.fileSha256!,
      if (stamp.operator != null && stamp.operator!.isNotEmpty)
        'Operator': stamp.operator!,
      if (stamp.organization != null && stamp.organization!.isNotEmpty)
        'Organization': stamp.organization!,
      if (stamp.project != null && stamp.project!.isNotEmpty)
        'Project': stamp.project!,
      if (address != null && address.isNotEmpty) 'Address': address,
      if (stamp.note != null && stamp.note!.isNotEmpty) 'Note': stamp.note!,
    };

    final buffer = StringBuffer()
      ..writeln('<?xpacket begin="\uFEFF" id="W5M0MpCehiHzreSzNTczkc9d"?>')
      ..writeln('<x:xmpmeta xmlns:x="adobe:ns:meta/">')
      ..writeln(' <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">')
      ..writeln('  <rdf:Description rdf:about="" '
          'xmlns:qingyang="${WatermarkStamp.xmpNamespace}"');
    attributes.forEach((key, value) {
      buffer.writeln('    qingyang:$key="${escape(value)}"');
    });
    buffer
      ..writeln('  />')
      ..writeln(' </rdf:RDF>')
      ..writeln('</x:xmpmeta>')
      ..writeln('<?xpacket end="w"?>');
    return buffer.toString();
  }

  static String? readAttribute(String? xmp, String key) {
    if (xmp == null) return null;
    final match = RegExp('qingyang:$key="([^"]*)"').firstMatch(xmp);
    return match?.group(1);
  }

  static String? readFileSha256(String? xmp) => readAttribute(xmp, 'FileSha256');

  static String? readFingerprint(String? xmp) => readAttribute(xmp, 'Fingerprint');

  static String escape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;')
        .replaceAll('\n', '&#10;');
  }
}
