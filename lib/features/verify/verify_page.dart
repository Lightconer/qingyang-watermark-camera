import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/models/photo_metadata.dart';
import '../../core/service/attestation.dart';

/// 校验工具：比对成品当前哈希与戳记中的哈希，输出是否被篡改。
class VerifyPage extends StatefulWidget {
  const VerifyPage({super.key});

  @override
  State<VerifyPage> createState() => _VerifyPageState();
}

class _VerifyPageState extends State<VerifyPage> {
  String? _path;
  PhotoMetadata? _metadata;
  String? _actualHash;
  String? _recordedHash;
  AttestationReport? _report;
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      _path = path;
      _report = null;
      _error = null;
    });
    await _verify();
  }

  Future<void> _verify() async {
    final path = _path;
    if (path == null) return;
    final services = ServicesScope.of(context);
    setState(() => _busy = true);
    try {
      final bytes = await File(path).readAsBytes();
      final snapshot = await services.metadata.snapshot(path);
      final actual = services.hash.sha256OfPixelStream(bytes);
      final report = services.attestation.verify(
        actualSha256: actual,
        metadata: snapshot.metadata,
        xmpSha256: snapshot.xmpSha256,
        xmpFingerprint: snapshot.xmpFingerprint,
        pixelWatermarkPresent: snapshot.metadata.hasQingyangMarker,
      );
      if (!mounted) return;
      setState(() {
        _metadata = snapshot.metadata;
        _actualHash = actual;
        _recordedHash = snapshot.metadata.userComment;
        _report = report;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        title: const Text('图片校验'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _verify,
            icon: const Icon(Icons.refresh),
            tooltip: '重新校验',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: FilledButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.folder_open),
              label: const Text('选择要校验的图片'),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(_error!, style: TextStyle(color: AppTheme.danger)),
            ),
          if (_path != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Text(p.basename(_path!), style: const TextStyle(fontSize: 12)),
            ),
          if (report != null) ...[
            Container(
              margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (report.isAuthentic ? AppTheme.online : AppTheme.danger)
                    .withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.verdict.label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: report.isAuthentic ? AppTheme.online : AppTheme.danger,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final check in report.checks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${check.passed ? '✓' : '✕'} ${check.label}'
                        '${check.detail.isEmpty ? '' : '：${check.detail}'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            _HashBlock(
              title: '当前文件哈希（去元数据后的像素流）',
              value: _actualHash ?? '-',
            ),
            _HashBlock(
              title: '戳记记录',
              value: report.stamp?.fileSha256 ?? '戳记中没有哈希',
            ),
            _HashBlock(
              title: 'EXIF UserComment 原文',
              value: _recordedHash ?? '（空）',
            ),
            if (_metadata != null)
              _HashBlock(
                title: 'EXIF 摘要',
                value: 'Orientation=${_metadata!.orientation}\n'
                    'DateTimeOriginal=${_metadata!.takenAt ?? '-'}\n'
                    'Make=${_metadata!.make ?? '-'} Model=${_metadata!.model ?? '-'}\n'
                    'GPS=${_metadata!.gps?.toDisplay() ?? '-'}',
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Text(
                '说明：水印文字画在像素上，任何重新编码都会改变像素哈希。'
                '哈希一致只说明文件未被改动，画面内容是否合规仍需人工比对。',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HashBlock extends StatelessWidget {
  const _HashBlock({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
