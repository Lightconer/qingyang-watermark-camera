import 'dart:convert';
import 'dart:typed_data';

/// 极简 XLSX 生成器（纯 Dart，零依赖）。
///
/// 台账导出只需要一张表 + 表头，用最小 OOXML 集合即可，避免为导表引入重量级依赖。
/// 单元格一律使用 inlineStr，省掉 sharedStrings；ZIP 使用 store（不压缩），
/// 体积对几千行台账完全可接受，且实现没有 deflate 状态机风险。
class XlsxWriter {
  const XlsxWriter._();

  static Uint8List build({
    required String sheetName,
    required List<String> headers,
    required List<List<Object?>> rows,
    Map<int, double> columnWidths = const {},
  }) {
    final zip = _ZipBuilder();

    zip.addString('[Content_Types].xml', _contentTypes);
    zip.addString('_rels/.rels', _rootRels);
    zip.addString('xl/workbook.xml', _workbook(sheetName));
    zip.addString('xl/_rels/workbook.xml.rels', _workbookRels);
    zip.addString('xl/worksheets/sheet1.xml',
        _sheet(headers: headers, rows: rows, columnWidths: columnWidths));
    return zip.finish();
  }

  static const String _contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '</Types>';

  static const String _rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';

  static const String _workbookRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
      '</Relationships>';

  static String _workbook(String sheetName) {
    final safe = _escapeXml(sheetName.isEmpty ? '台账' : sheetName);
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="$safe" sheetId="1" r:id="rId1"/></sheets>'
        '</workbook>';
  }

  static String _sheet({
    required List<String> headers,
    required List<List<Object?>> rows,
    required Map<int, double> columnWidths,
  }) {
    final buffer = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');

    if (columnWidths.isNotEmpty) {
      buffer.write('<cols>');
      columnWidths.forEach((index, width) {
        buffer.write('<col min="${index + 1}" max="${index + 1}" '
            'width="${width.toStringAsFixed(1)}" customWidth="1"/>');
      });
      buffer.write('</cols>');
    }

    buffer.write('<sheetData>');
    buffer.write('<row r="1">');
    for (var index = 0; index < headers.length; index++) {
      buffer.write('<c r="${_column(index)}1" t="inlineStr"><is><t>'
          '${_escapeXml(headers[index])}</t></is></c>');
    }
    buffer.write('</row>');

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final excelRow = rowIndex + 2;
      buffer.write('<row r="$excelRow">');
      final row = rows[rowIndex];
      for (var columnIndex = 0; columnIndex < row.length; columnIndex++) {
        final value = row[columnIndex];
        if (value == null) continue;
        final ref = '${_column(columnIndex)}$excelRow';
        if (value is num) {
          buffer.write('<c r="$ref"><v>$value</v></c>');
        } else {
          final text = '$value';
          if (text.isEmpty) continue;
          buffer.write('<c r="$ref" t="inlineStr"><is><t xml:space="preserve">'
              '${_escapeXml(text)}</t></is></c>');
        }
      }
      buffer.write('</row>');
    }

    buffer.write('</sheetData></worksheet>');
    return buffer.toString();
  }

  static String _column(int index) {
    var value = index;
    final letters = StringBuffer();
    do {
      letters.write(String.fromCharCode(65 + value % 26));
      value = value ~/ 26 - 1;
    } while (value >= 0);
    return String.fromCharCodes(letters.toString().codeUnits.reversed);
  }

  static String _escapeXml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}

class _ZipBuilder {
  final List<_ZipEntry> _entries = [];

  void addString(String name, String content) {
    add(name, utf8.encode(content));
  }

  void add(String name, List<int> data) {
    _entries.add(_ZipEntry(name, Uint8List.fromList(data)));
  }

  Uint8List finish() {
    final output = BytesBuilder(copy: false);
    final offsets = <int>[];
    for (final entry in _entries) {
      offsets.add(output.length);
      final nameBytes = utf8.encode(entry.name);
      final header = ByteData(30);
      header.setUint32(0, 0x04034b50, Endian.little);
      header.setUint16(4, 20, Endian.little);
      header.setUint16(6, 0x0800, Endian.little);
      header.setUint16(8, 0, Endian.little);
      header.setUint16(10, 0, Endian.little);
      header.setUint16(12, 0, Endian.little);
      header.setUint32(14, _crc32(entry.data), Endian.little);
      header.setUint32(18, entry.data.length, Endian.little);
      header.setUint32(22, entry.data.length, Endian.little);
      header.setUint16(26, nameBytes.length, Endian.little);
      header.setUint16(28, 0, Endian.little);
      output.add(header.buffer.asUint8List());
      output.add(nameBytes);
      output.add(entry.data);
    }

    final centralStart = output.length;
    for (var index = 0; index < _entries.length; index++) {
      final entry = _entries[index];
      final nameBytes = utf8.encode(entry.name);
      final central = ByteData(46);
      central.setUint32(0, 0x02014b50, Endian.little);
      central.setUint16(4, 20, Endian.little);
      central.setUint16(6, 20, Endian.little);
      central.setUint16(8, 0x0800, Endian.little);
      central.setUint16(10, 0, Endian.little);
      central.setUint16(12, 0, Endian.little);
      central.setUint16(14, 0, Endian.little);
      central.setUint32(16, _crc32(entry.data), Endian.little);
      central.setUint32(20, entry.data.length, Endian.little);
      central.setUint32(24, entry.data.length, Endian.little);
      central.setUint16(28, nameBytes.length, Endian.little);
      central.setUint16(30, 0, Endian.little);
      central.setUint16(32, 0, Endian.little);
      central.setUint16(34, 0, Endian.little);
      central.setUint16(36, 0, Endian.little);
      central.setUint32(38, 0, Endian.little);
      central.setUint32(42, offsets[index], Endian.little);
      output.add(central.buffer.asUint8List());
      output.add(nameBytes);
    }
    final centralSize = output.length - centralStart;

    final end = ByteData(22);
    end.setUint32(0, 0x06054b50, Endian.little);
    end.setUint16(4, 0, Endian.little);
    end.setUint16(6, 0, Endian.little);
    end.setUint16(8, _entries.length, Endian.little);
    end.setUint16(10, _entries.length, Endian.little);
    end.setUint32(12, centralSize, Endian.little);
    end.setUint32(16, centralStart, Endian.little);
    end.setUint16(20, 0, Endian.little);
    output.add(end.buffer.asUint8List());
    return output.takeBytes();
  }

  static int _crc32(List<int> data) {
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      final index = (crc ^ byte) & 0xFF;
      crc = (_crcTable[index] ^ (crc >> 8)) & 0xFFFFFFFF;
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static final List<int> _crcTable = List<int>.generate(256, (index) {
    var value = index;
    for (var bit = 0; bit < 8; bit++) {
      value = (value & 1) == 1 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1);
    }
    return value & 0xFFFFFFFF;
  });
}

class _ZipEntry {
  _ZipEntry(this.name, this.data);

  final String name;
  final Uint8List data;
}
