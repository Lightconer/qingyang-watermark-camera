import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/models/photo_metadata.dart';
import '../../core/models/template.dart';
import '../../core/models/types.dart';
import '../../core/policy/policies.dart';
import '../../core/service/attestation.dart';

/// 相册索引项。
class GalleryPhoto {
  GalleryPhoto({
    required this.path,
    required this.metadata,
    required this.stamp,
    required this.modified,
    required this.sizeBytes,
  });

  final String path;
  final PhotoMetadata metadata;
  final WatermarkStamp? stamp;
  final DateTime modified;
  final int sizeBytes;

  String get fileName => p.basename(path);

  PhotoSource get source => stamp?.source ?? PhotoSource.gallery;

  String get templateId => stamp?.templateId ?? '-';

  DateTime? get takenAt => stamp?.capturedAt ?? metadata.takenAt;
}

/// 相册仓库：扫日期目录 + 读元数据，按来源/模板/日期筛选。
class GalleryRepository {
  GalleryRepository(this.services);

  final AppServices services;

  Future<List<GalleryPhoto>> load({
    int days = 14,
    PhotoSource? source,
    String? templateId,
  }) async {
    final now = DateTime.now();
    final photos = <GalleryPhoto>[];
    for (var offset = 0; offset < days; offset++) {
      final date = now.subtract(Duration(days: offset));
      final paths = await services.storage.listDay(date);
      for (final path in paths) {
        final file = File(path);
        final metadata = await services.metadata.readFile(path);
        final stamp = WatermarkStamp.decode(metadata.userComment);
        final stat = await file.stat();
        final photo = GalleryPhoto(
          path: path,
          metadata: metadata,
          stamp: stamp,
          modified: stat.modified,
          sizeBytes: stat.size,
        );
        if (source != null && photo.source != source) continue;
        if (templateId != null && photo.templateId != templateId) continue;
        photos.add(photo);
      }
    }
    photos.sort((a, b) => b.modified.compareTo(a.modified));
    return photos;
  }
}

/// 相册页（底部第三个入口）。页内单设「导入加水印」入口。
class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key, this.onOpenImport});

  final VoidCallback? onOpenImport;

  @override
  State<GalleryPage> createState() => GalleryPageState();
}

class GalleryPageState extends State<GalleryPage> {
  Future<List<GalleryPhoto>>? _future;
  PhotoSource? _sourceFilter;
  String _templateFilter = '';

  void reload() {
    setState(() {
      _future = GalleryRepository(ServicesScope.of(context)).load(
        source: _sourceFilter,
        templateId: _templateFilter.isEmpty ? null : _templateFilter,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= GalleryRepository(ServicesScope.of(context)).load();
  }

  @override
  Widget build(BuildContext context) {
    final services = ServicesScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('相册'),
        actions: [
          IconButton(
            tooltip: '导入加水印',
            onPressed: widget.onOpenImport,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(
            source: _sourceFilter,
            templateId: _templateFilter,
            onSourceChanged: (value) {
              _sourceFilter = value;
              reload();
            },
            onTemplateChanged: (value) {
              _templateFilter = value;
              reload();
            },
            templates: services.templates.templates,
          ),
          Expanded(
            child: FutureBuilder<List<GalleryPhoto>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final photos = snapshot.data ?? const <GalleryPhoto>[];
                if (photos.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.photo_outlined, size: 48),
                        const SizedBox(height: 8),
                        const Text('还没有带水印的照片'),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: widget.onOpenImport,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('导入加水印'),
                        ),
                      ],
                    ),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: photos.length,
                  itemBuilder: (context, index) {
                    final photo = photos[index];
                    return GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PhotoDetailPage(photo: photo),
                        ),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            File(photo.path),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const ColoredBox(
                              color: Color(0xFF1E1E1E),
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                          Positioned(
                            left: 4,
                            bottom: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              color: Colors.black54,
                              child: Text(
                                photo.source.shortBadge,
                                style: const TextStyle(
                                    fontSize: 9, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.source,
    required this.templateId,
    required this.onSourceChanged,
    required this.onTemplateChanged,
    required this.templates,
  });

  final PhotoSource? source;
  final String templateId;
  final ValueChanged<PhotoSource?> onSourceChanged;
  final ValueChanged<String> onTemplateChanged;
  final List<TemplateConfig> templates;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('全部来源'),
            selected: source == null,
            onSelected: (_) => onSourceChanged(null),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('现场拍摄'),
            selected: source == PhotoSource.camera,
            onSelected: (_) => onSourceChanged(PhotoSource.camera),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('导入'),
            selected: source != null && source!.isImport,
            onSelected: (_) => onSourceChanged(PhotoSource.gallery),
          ),
          const SizedBox(width: 12),
          DropdownButton<String>(
            value: templateId.isEmpty ? '' : templateId,
            hint: const Text('全部模板'),
            items: [
              const DropdownMenuItem(value: '', child: Text('全部模板')),
              for (final template in templates)
                DropdownMenuItem(
                  value: template.id,
                  child: Text(template.name),
                ),
            ],
            onChanged: (value) => onTemplateChanged(value ?? ''),
          ),
        ],
      ),
    );
  }
}

/// 详情页：展示完整水印原始信息 + 哈希 + 校验结果。
class PhotoDetailPage extends StatefulWidget {
  const PhotoDetailPage({super.key, required this.photo});

  final GalleryPhoto photo;

  @override
  State<PhotoDetailPage> createState() => _PhotoDetailPageState();
}

class _PhotoDetailPageState extends State<PhotoDetailPage> {
  AttestationReport? _report;
  bool _verifying = false;

  Future<void> _verify() async {
    final services = ServicesScope.of(context);
    setState(() => _verifying = true);
    try {
      final bytes = await File(widget.photo.path).readAsBytes();
      final snapshot = await services.metadata.snapshot(widget.photo.path);
      final pixelHash = services.hash.sha256OfPixelStream(bytes);
      final report = services.attestation.verify(
        actualSha256: pixelHash,
        metadata: snapshot.metadata,
        xmpSha256: snapshot.xmpSha256,
        xmpFingerprint: snapshot.xmpFingerprint,
        pixelWatermarkPresent: snapshot.metadata.hasQingyangMarker,
      );
      if (mounted) setState(() => _report = report);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;
    final stamp = photo.stamp;
    return Scaffold(
      appBar: AppBar(
        title: Text(photo.fileName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '校验',
            onPressed: _verifying ? null : _verify,
            icon: const Icon(Icons.verified_outlined),
          ),
        ],
      ),
      body: ListView(
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Image.file(File(photo.path), fit: BoxFit.contain),
          ),
          if (_verifying) const LinearProgressIndicator(),
          if (_report != null) _ReportCard(report: _report!),
          _Section(title: '水印原始信息', children: [
            _row('来源', photo.source.label),
            _row('模板', photo.templateId),
            _row('时间口径', stamp?.timeAuthority.label ?? '-'),
            _row('坐标口径', stamp?.coordAuthority.label ?? '-'),
            _row('采集时间', stamp == null ? '-' : TimeText.format(stamp.capturedAt)),
            _row('经纬度',
                stamp?.position?.toDisplay() ?? (photo.metadata.hasGps ? photo.metadata.gps!.toDisplay() : '无原始定位')),
            _row('地址', stamp?.address ?? '未解析'),
            _row('采集人', stamp?.operator ?? '未填写'),
            _row('单位', stamp?.organization ?? '未填写'),
            _row('项目', stamp?.project ?? '未填写'),
          ]),
          _Section(title: '哈希与溯源', children: [
            _row('内容指纹', stamp?.fingerprint ?? '-'),
            _row('成品哈希', stamp?.fileSha256 ?? '-'),
            _row('文件大小', '${(photo.sizeBytes / 1024).toStringAsFixed(1)} KB'),
            _row('文件路径', photo.path),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 6),
          child: Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        ...children,
        const Divider(),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final AttestationReport report;

  @override
  Widget build(BuildContext context) {
    final color = report.isAuthentic
        ? AppTheme.online
        : (report.verdict == AttestVerdict.tampered ? AppTheme.danger : AppTheme.warning);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(report.isAuthentic ? Icons.verified : Icons.report_gmailerrorred,
                  color: color, size: 18),
              const SizedBox(width: 6),
              Text(
                report.verdict.label,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final check in report.checks)
            Text(
              '${check.passed ? '✓' : '✕'} ${check.label}'
              '${check.detail.isEmpty ? '' : '：${check.detail}'}',
              style: const TextStyle(fontSize: 11),
            ),
        ],
      ),
    );
  }
}
