import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../engines/media/media_gateway.dart';
import 'import_controller.dart';

/// 导入加水印：三个入口 → 网格预览 → 统一/单张换模板 → 批量执行。
class ImportPage extends StatefulWidget {
  const ImportPage({super.key});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  ImportController? _controller;

  ImportController _ensure(AppServices services) {
    return _controller ??= ImportController(
      services: services,
      channel: ImportChannel.systemGallery,
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = ServicesScope.of(context);
    final controller = _ensure(services);
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入加水印'),
        actions: [
          if (controller.items.isNotEmpty)
            IconButton(
              tooltip: '清空',
              onPressed: controller.processing ? null : controller.clear,
              icon: const Icon(Icons.clear_all),
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return Column(
            children: [
              _EntryRow(controller: controller, services: services),
              if (controller.items.isNotEmpty) _Toolbar(controller: controller),
              if (controller.processing || controller.progress > 0)
                LinearProgressIndicator(value: controller.progress),
              if (controller.processing)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Text(
                    '${controller.doneCount + controller.failedCount + controller.skippedCount}'
                    '/${controller.total} · ${controller.currentStage}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Expanded(
                child: controller.items.isEmpty
                    ? _EmptyHint(controller: controller, services: services)
                    : _ItemGrid(controller: controller),
              ),
              _ActionBar(controller: controller),
            ],
          );
        },
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.controller, required this.services});

  final ImportController controller;
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: controller.loading || controller.processing
                  ? null
                  : () => controller.load(services.media.pickSystemGallery),
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('系统相册'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: controller.loading || controller.processing
                  ? null
                  : () => controller.load(services.media.pickFolder),
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('文件夹'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: controller.loading || controller.processing
                  ? null
                  : () => controller.load(services.media.takeSharedImages),
              icon: const Icon(Icons.share_outlined, size: 18),
              label: const Text('分享进入'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller});

  final ImportController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          const Text('统一模板', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: controller.uniformTemplate.id,
              items: [
                for (final template in controller.templates)
                  DropdownMenuItem(value: template.id, child: Text(template.name)),
              ],
              onChanged: controller.processing
                  ? null
                  : (value) {
                      if (value == null) return;
                      final template = controller.templates
                          .firstWhere((item) => item.id == value);
                      controller.applyTemplateToAll(template);
                    },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.controller, required this.services});

  final ImportController controller;
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_photo_alternate_outlined, size: 56),
            const SizedBox(height: 12),
            Text(
              '从相册、文件夹或其它应用分享进入照片',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '导入图会标注「导入 · 非现场取证」；'
              '经纬度只取原图 EXIF，原图没有就显示「无原始定位」，不提供手动输入。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (controller.loading)
              const CircularProgressIndicator(strokeWidth: 2)
            else
              FilledButton.icon(
                onPressed: () => controller.load(services.media.pickSystemGallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('选择照片'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ItemGrid extends StatelessWidget {
  const _ItemGrid({required this.controller});

  final ImportController controller;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.78,
      ),
      itemCount: controller.items.length,
      itemBuilder: (context, index) {
        final item = controller.items[index];
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(item.path),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => const ColoredBox(
                        color: Color(0xFF222222),
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
                    Positioned(
                      left: 6,
                      top: 6,
                      child: _Tag(
                        text: item.hasOriginalGeo ? '原图有定位' : '无原始定位',
                        color: item.hasOriginalGeo ? AppTheme.online : AppTheme.warning,
                      ),
                    ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        onPressed: controller.processing
                            ? null
                            : () => controller.remove(item.path),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: Text(
                  item.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  item.timeLabel,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
              SizedBox(
                height: 34,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    isDense: true,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    value: item.template.id,
                    style: const TextStyle(fontSize: 11),
                    items: [
                      for (final template in controller.templates)
                        DropdownMenuItem(value: template.id, child: Text(template.name)),
                    ],
                    onChanged: controller.processing
                        ? null
                        : (value) {
                            if (value == null) return;
                            final template = controller.templates
                                .firstWhere((element) => element.id == value);
                            controller.setItemTemplate(item, template);
                          },
                  ),
                ),
              ),
              _StatusLine(item: item),
            ],
          ),
        );
      },
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.item});

  final ImportItem item;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String text;
    switch (item.stage) {
      case ImportStage.pending:
        color = Colors.grey;
        text = '待处理';
        break;
      case ImportStage.running:
        color = AppTheme.accent;
        text = item.message ?? '处理中';
        break;
      case ImportStage.done:
        color = AppTheme.online;
        text = '已完成';
        break;
      case ImportStage.skipped:
        color = AppTheme.warning;
        text = item.message ?? '已跳过';
        break;
      case ImportStage.failed:
        color = AppTheme.danger;
        text = item.message ?? '失败';
        break;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.controller});

  final ImportController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.items.isEmpty) return const SizedBox.shrink();
    final hasFailed = controller.failedCount > 0;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Column(
          children: [
            if (controller.hasMissingGeo)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '有原图缺少 GPS：将显示「无原始定位」，不会编造地址',
                  style: TextStyle(fontSize: 11, color: AppTheme.warning),
                ),
              ),
            if (controller.hasUnsupportedHeic)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '检测到 HEIC/HEIF：需系统转码，若失败请先在相册中导出为 JPEG',
                  style: TextStyle(fontSize: 11, color: AppTheme.warning),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: controller.processing
                        ? null
                        : () => controller.processAll(),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: Text(controller.processing ? '处理中…' : '开始批量加水印'),
                  ),
                ),
                if (hasFailed) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: controller.processing ? null : controller.retryFailed,
                    child: const Text('重试失败'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
