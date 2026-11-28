import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/extensions/watermark_field_provider.dart';
import '../../core/layout/layout_engine.dart';
import '../../core/models/template.dart';
import '../../core/models/types.dart';

/// 模板编辑器：字段开关 + 样式 + 自定义取值 + 导入导出，全部 JSON 化。
class TemplatePage extends StatefulWidget {
  const TemplatePage({super.key});

  @override
  State<TemplatePage> createState() => _TemplatePageState();
}

class _TemplatePageState extends State<TemplatePage> {
  late TemplateConfig _draft;
  bool _dirty = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = ServicesScope.of(context);
    _draft = services.templates.active;
  }

  void _update(TemplateConfig next) {
    setState(() {
      _draft = next;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final services = ServicesScope.of(context);
    await services.templates.save(_draft);
    final saved = services.templates.byId(_draft.id);
    setState(() {
      _draft = saved;
      _dirty = false;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('模板已保存：${saved.name}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = ServicesScope.of(context);
    final templates = services.templates.templates;
    return Scaffold(
      appBar: AppBar(
        title: const Text('水印模板'),
        actions: [
          IconButton(
            tooltip: '另存为副本',
            onPressed: () async {
              final copy = services.templates.duplicate(_draft, '${_draft.name} 副本');
              await services.templates.save(copy);
              setState(() {
                _draft = copy;
                _dirty = false;
              });
            },
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: '导出 JSON',
            onPressed: () => _showJson(context, services.templates.exportJson(_draft.id)),
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            tooltip: '导入 JSON',
            onPressed: () => _importJson(context),
            icon: const Icon(Icons.file_open_outlined),
          ),
          TextButton(
            onPressed: _dirty ? _save : null,
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: DropdownButtonFormField<String>(
              value: _draft.id,
              decoration: const InputDecoration(
                labelText: '当前模板',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final template in templates)
                  DropdownMenuItem(
                    value: template.id,
                    child: Text('${template.name}${template.isBuiltin ? '（内置）' : ''}'),
                  ),
              ],
              onChanged: (value) async {
                if (value == null) return;
                await services.templates.setActive(value);
                if (!mounted) return;
                setState(() {
                  _draft = services.templates.byId(value);
                  _dirty = false;
                });
              },
            ),
          ),
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CustomPaint(
                  painter: _TemplatePreviewPainter(services: services, template: _draft),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          _title('水印位置'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<WatermarkPosition>(
              segments: const [
                ButtonSegment(value: WatermarkPosition.bottomBar, label: Text('底部')),
                ButtonSegment(value: WatermarkPosition.bottomLeft, label: Text('左下')),
                ButtonSegment(value: WatermarkPosition.bottomRight, label: Text('右下')),
                ButtonSegment(value: WatermarkPosition.topBar, label: Text('顶部')),
              ],
              selected: {_draft.style.position},
              onSelectionChanged: (value) => _update(
                _draft.copyWith(style: _draft.style.copyWith(position: value.first)),
              ),
            ),
          ),
          _slider(
            '字号比例',
            _draft.style.fontSizeRatio,
            0.012,
            0.06,
            (value) => _update(
              _draft.copyWith(style: _draft.style.copyWith(fontSizeRatio: value)),
            ),
            label: '${(_draft.style.fontSizeRatio * 100).toStringAsFixed(1)}% 短边',
          ),
          _slider(
            '描边粗细',
            _draft.style.strokeWidthRatio,
            0.0,
            0.3,
            (value) => _update(
              _draft.copyWith(style: _draft.style.copyWith(strokeWidthRatio: value)),
            ),
            label: '${(_draft.style.strokeWidthRatio * 100).toStringAsFixed(0)}% 字号',
          ),
          _slider(
            '底板不透明度',
            _draft.style.bandOpacity,
            0.0,
            0.9,
            (value) => _update(
              _draft.copyWith(style: _draft.style.copyWith(bandOpacity: value)),
            ),
            label: '${(_draft.style.bandOpacity * 100).toStringAsFixed(0)}%',
          ),
          _slider(
            '行距',
            _draft.style.lineSpacing,
            1.0,
            1.8,
            (value) => _update(
              _draft.copyWith(style: _draft.style.copyWith(lineSpacing: value)),
            ),
            label: '${_draft.style.lineSpacing.toStringAsFixed(2)}x',
          ),
          SwitchListTile(
            value: _draft.style.showBadge,
            onChanged: (value) => _update(
              _draft.copyWith(style: _draft.style.copyWith(showBadge: value)),
            ),
            title: const Text('来源标识角标'),
            subtitle: const Text('现场拍摄 / 导入 · 非现场取证，硬性要求建议保持开启'),
          ),
          SwitchListTile(
            value: _draft.style.showQr,
            onChanged: (value) => _update(
              _draft.copyWith(style: _draft.style.copyWith(showQr: value)),
            ),
            title: const Text('溯源二维码'),
            subtitle: const Text('扫码可读来源、时间、坐标与批次号'),
          ),
          _title('字段开关'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in services.fields.uiItems)
                FilterChip(
                  label: Text(item.label),
                  selected: _draft.isFieldEnabled(item.id),
                  onSelected: (selected) {
                    final fields = {..._draft.enabledFieldIds};
                    if (selected) {
                      fields.add(item.id);
                    } else {
                      fields.remove(item.id);
                    }
                    _update(_draft.copyWith(enabledFieldIds: fields));
                  },
                ),
            ],
          ),
          _title('自定义取值'),
          _valueField('采集人', WatermarkFieldIds.operator),
          _valueField('所属单位', WatermarkFieldIds.organization),
          _valueField('项目名称', WatermarkFieldIds.project),
          _valueField('备注', WatermarkFieldIds.note),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Text(
              '模板以 JSON 存储，可导出后交付同事导入；新增模式只需要在 assets/profiles/ 增加一个 JSON。',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      );

  Widget _slider(
    String title,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    String? label,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 12)),
              Text(label ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _valueField(String label, String key) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: TextFormField(
        initialValue: _draft.valueOf(key),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) {
          final values = {..._draft.values, key: value};
          _update(_draft.copyWith(values: values));
        },
      ),
    );
  }

  Future<void> _showJson(BuildContext context, String json) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('模板 JSON'),
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: SingleChildScrollView(child: SelectableText(json)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _importJson(BuildContext context) async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入模板 JSON'),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            decoration: const InputDecoration(hintText: '粘贴模板 JSON'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (raw == null || raw.trim().isEmpty || !mounted) return;
    final services = ServicesScope.of(context);
    final imported = await services.templates.importJson(raw);
    if (!mounted) return;
    if (imported == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('导入失败：JSON 格式不正确')),
      );
      return;
    }
    setState(() {
      _draft = imported;
      _dirty = false;
    });
  }
}

/// 模板预览：用真实排版引擎 + 示例数据，所见即所得。
class _TemplatePreviewPainter extends CustomPainter {
  _TemplatePreviewPainter({required this.services, required this.template});

  final AppServices services;
  final TemplateConfig template;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF2B3A3F),
    );
    // 示例背景：模拟现场画面
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [const Color(0xFF3C4F52), const Color(0xFF1D2A2C)],
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = gradient.createShader(Offset.zero & size));

    final profile = services.profiles.byId(template.profileId);
    final now = DateTime.now();
    final sampleContext = CaptureContext(
      capturedAt: now,
      timeAuthority: TimeAuthority.ntp,
      coordAuthority: CoordAuthority.fused,
      position: const GeoPoint(latitude: 30.274084, longitude: 120.155070),
      altitudeMeters: 42.5,
      address: '浙江省杭州市西湖区某街道 88 号',
      weather: WeatherSnapshot(temperatureC: 18, text: '多云', fetchedAt: now),
      deviceModel: 'Sample Device',
      online: true,
      // 模板预览要能看出方位角这一行长什么样，用固定示例值而不是真实传感器。
      headingDegrees: 42,
      headingAccuracyDegrees: 3,
      headingAuthority: HeadingAuthority.sensor,
    );
    final fieldContext = FieldContext(
      mode: profile.mode,
      provenance: Provenance.capture(batchId: 'preview', at: now),
      capture: sampleContext,
      template: template,
      identity: services.settings.identity,
      fingerprint: 'a3f5c9d1e7b24680a3f5c9d1e7b24680',
      weatherAllowed: profile.weatherAllowed,
      headingFormat: services.settings.headingFormat,
    );
    final fields = services.fields.resolve(
      fieldContext,
      enabledFieldIds: template.enabledFieldIds,
      allowedFieldIds: profile.allowedFields,
    );
    final layout = services.layout.compute(
      size: LayoutSize(size.width, size.height),
      fields: fields,
      style: template.style,
      badgeText: profile.requireProvenanceBadge ? '现场拍摄' : null,
      qrData: template.isFieldEnabled(WatermarkFieldIds.qr) ? 'QY|preview|sample' : null,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          layout.band.left,
          layout.band.top,
          layout.band.width,
          layout.band.height,
        ),
        Radius.circular(size.shortestSide * template.style.cornerRadiusRatio),
      ),
      Paint()..color = Color(template.style.bandColor).withOpacity(template.style.bandOpacity),
    );

    for (final line in layout.lines) {
      final offset = Offset(line.bounds.left, line.bounds.top);
      final style = TextStyle(
        fontSize: line.fontSize,
        fontWeight: line.emphasize ? FontWeight.w700 : FontWeight.w500,
        height: 1.12,
      );
      TextPainter(
        text: TextSpan(
          text: line.text,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = layout.strokeWidth
              ..color = Color(template.style.strokeColor),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )
        ..layout()
        ..paint(canvas, offset);
      TextPainter(
        text: TextSpan(
          text: line.text,
          style: style.copyWith(color: Color(template.style.color)),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )
        ..layout()
        ..paint(canvas, offset);
    }

    if (layout.badge != null && layout.badgeText != null) {
      final badge = Rect.fromLTWH(
        layout.badge!.left,
        layout.badge!.top,
        layout.badge!.width,
        layout.badge!.height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(badge, Radius.circular(badge.height * 0.28)),
        Paint()..color = AppTheme.online,
      );
      TextPainter(
        text: TextSpan(
          text: layout.badgeText,
          style: TextStyle(
            color: Colors.white,
            fontSize: badge.height * 0.58,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )
        ..layout()
        ..paint(
          canvas,
          Offset(
            badge.left + (badge.width - layout.badge!.width) / 2 + 4,
            badge.top + badge.height * 0.2,
          ),
        );
    }
  }

  @override
  bool shouldRepaint(covariant _TemplatePreviewPainter oldDelegate) =>
      oldDelegate.template != template;
}
