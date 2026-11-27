import 'package:flutter_test/flutter_test.dart';
import 'package:qingyang_watermark/core/ledger/xlsx_writer.dart';
import 'package:qingyang_watermark/core/models/ledger_entry.dart';
import 'package:qingyang_watermark/core/models/types.dart';

void main() {
  test('生成的 XLSX 是合法 zip 且包含工作表与单元格文本', () {
    final bytes = XlsxWriter.build(
      sheetName: '台账',
      headers: const ['文件名', '来源', '经度'],
      rows: [
        ['QY_20261127_203105_482_wm.jpg', '现场拍摄', 120.15507],
      ],
    );
    expect(bytes.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
    final text = String.fromCharCodes(bytes);
    expect(text.contains('xl/worksheets/sheet1.xml'), isTrue);
    expect(text.contains('QY_20261127_203105_482_wm.jpg'), isTrue);
  });

  test('列名映射到 Excel 列号', () {
    final bytes = XlsxWriter.build(
      sheetName: 's',
      headers: const ['a', 'b', 'c'],
      rows: const [],
    );
    final text = String.fromCharCodes(bytes);
    expect(text.contains('r="A1"'), isTrue);
    expect(text.contains('r="C1"'), isTrue);
  });

  test('台账行包含必需列', () {
    final entry = LedgerEntry(
      fileName: 'x_wm.jpg',
      outputPath: '/tmp/x_wm.jpg',
      source: PhotoSource.gallery,
      templateId: 'import_trace',
      mode: CaptureMode.processed,
      sha256: 'a' * 64,
      processedAt: DateTime(2026, 11, 27, 21, 0, 0),
      capturedAt: DateTime(2026, 11, 1, 9, 0, 0),
      position: const GeoPoint(latitude: 30.274084, longitude: 120.15507),
    );
    final row = entry.toRow();
    expect(row.length, LedgerEntry.columns.length);
    expect(row[1], '相册导入');
    expect(row[4], '30.2740840');
  });
}
