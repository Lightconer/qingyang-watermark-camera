import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../core/ledger/xlsx_writer.dart';
import '../../core/models/ledger_entry.dart';
import '../../core/models/types.dart';
import 'storage_engine.dart';

/// 台账存储：按天追加 JSONL，导出时汇总为 XLSX。
///
/// 台账是"像素哈希 + 元数据戳记"之外的第三份留痕：即使图片被重新编码，
/// 台账里仍留有当时的哈希与坐标，可交叉比对。
class LedgerStore {
  LedgerStore(this.storage);

  final StorageEngine storage;

  Future<String> _ledgerFile(DateTime date) async {
    final root = await storage.root();
    final folder = Directory(p.join(root.path, 'ledger'));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return p.join(folder.path, 'ledger_${FileNaming.dayFolder(date)}.jsonl');
  }

  Future<void> append(LedgerEntry entry) async {
    final file = File(await _ledgerFile(entry.processedAt));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${jsonEncode(entry.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<List<LedgerEntry>> readDay(DateTime date) async {
    final file = File(await _ledgerFile(date));
    if (!await file.exists()) return const [];
    final lines = await file.readAsLines();
    final entries = <LedgerEntry>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final json = jsonDecode(line);
        if (json is Map<String, dynamic>) {
          final entry = LedgerEntry.fromJson(json);
          if (entry != null) entries.add(entry);
        }
      } catch (_) {
        continue;
      }
    }
    return entries;
  }

  Future<List<LedgerEntry>> readAll({int days = 30}) async {
    final result = <LedgerEntry>[];
    final now = DateTime.now();
    for (var offset = 0; offset < days; offset++) {
      result.addAll(await readDay(now.subtract(Duration(days: offset))));
    }
    return result;
  }

  /// 导出台账 XLSX 并返回文件路径。
  Future<String> exportXlsx({
    DateTime? date,
    List<LedgerEntry>? entries,
    bool includeFields = true,
  }) async {
    final targetDate = date ?? DateTime.now();
    final rows = entries ?? await readAll();

    final headers = [
      ...LedgerEntry.columns,
      if (includeFields) ...['内容指纹'],
    ];
    final data = rows
        .map((entry) => [
              ...entry.toRow(),
              if (includeFields) entry.fingerprint ?? '',
            ])
        .toList(growable: false);

    final bytes = XlsxWriter.build(
      sheetName: '台账 ${FileNaming.dayFolder(targetDate)}',
      headers: headers,
      rows: data,
      columnWidths: {0: 30, 1: 12, 2: 20, 3: 20, 7: 40, 15: 66},
    );

    final path = await storage.ledgerPath(targetDate);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return path;
  }

  /// 便于测试：直接拿到 XLSX 字节。
  Uint8List buildXlsxBytes(List<LedgerEntry> entries) {
    return XlsxWriter.build(
      sheetName: '台账',
      headers: LedgerEntry.columns,
      rows: entries.map((entry) => entry.toRow()).toList(growable: false),
    );
  }
}
