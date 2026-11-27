import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/services.dart';
import '../../core/models/ledger_entry.dart';
import '../../engines/storage/ledger_store.dart';

/// 台账：按天查看 + 导出台账 Excel（文件名、来源、时间、经纬度、地址、备注）。
class LedgerPage extends StatefulWidget {
  const LedgerPage({super.key});

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  DateTime _date = DateTime.now();
  List<LedgerEntry> _entries = const [];
  bool _loading = false;
  bool _exporting = false;
  String? _message;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final services = ServicesScope.of(context);
    setState(() => _loading = true);
    try {
      final entries = await LedgerStore(services.storage).readAll(days: 30);
      if (mounted) setState(() => _entries = entries);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _export() async {
    final services = ServicesScope.of(context);
    setState(() => _exporting = true);
    try {
      final path = await LedgerStore(services.storage).exportXlsx(
        date: _date,
        entries: _entries,
        includeFields: services.settings.ledgerIncludeOriginal,
      );
      if (!mounted) return;
      setState(() => _message = '已导出：$path');
      await Share.shareXFiles([XFile(path)], subject: '青阳水印相机台账');
    } catch (error) {
      if (mounted) setState(() => _message = '导出失败：$error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('台账'),
        actions: [
          IconButton(
            tooltip: '选择导出日期',
            onPressed: _pickDate,
            icon: const Icon(Icons.event),
          ),
          IconButton(
            tooltip: '导出台账 Excel',
            onPressed: _exporting || _entries.isEmpty ? null : _export,
            icon: const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '近 30 天共 ${_entries.length} 条记录'
                    '${_message == null ? '' : '\n$_message'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (_loading) const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: _entries.isEmpty
                ? const Center(child: Text('暂无台账记录'))
                : ListView.separated(
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = _entries[index];
                      return ListTile(
                        dense: true,
                        title: Text(entry.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${entry.source.label} · ${entry.capturedAt ?? entry.processedAt}\n'
                          '${entry.position?.toDisplay() ?? '无定位'} · ${entry.address ?? '无地址'}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Text(
                          entry.sha256.length > 8 ? entry.sha256.substring(0, 8) : entry.sha256,
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
