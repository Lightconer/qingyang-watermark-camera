import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingyang_watermark/core/models/profile_config.dart';
import 'package:qingyang_watermark/core/models/template.dart';
import 'package:qingyang_watermark/core/models/types.dart';

void main() {
  test('模板 JSON 往返不丢失样式与字段', () {
    const template = TemplateConfig(
      id: 'tpl_a',
      name: '测试模板',
      profileId: 'processed',
      style: WatermarkStyle(
        position: WatermarkPosition.bottomRight,
        fontSizeRatio: 0.033,
        bandOpacity: 0.5,
        showQr: true,
      ),
      enabledFieldIds: {WatermarkFieldIds.time, WatermarkFieldIds.coords},
      values: {'note': '备注内容'},
    );
    final json = jsonDecode(jsonEncode(template.toJson())) as Map<String, dynamic>;
    final parsed = TemplateConfig.fromJson(json);
    expect(parsed, isNotNull);
    expect(parsed!.id, 'tpl_a');
    expect(parsed.style.position, WatermarkPosition.bottomRight);
    expect(parsed.style.fontSizeRatio, closeTo(0.033, 1e-9));
    expect(parsed.style.showQr, isTrue);
    expect(parsed.enabledFieldIds.length, 2);
    expect(parsed.valueOf('note'), '备注内容');
  });

  test('字段列表缺失时回退为全字段（旧版本模板可读）', () {
    final parsed = TemplateConfig.fromJson({
      'id': 'legacy',
      'name': '旧模板',
      'schemaVersion': '0.9',
    });
    expect(parsed, isNotNull);
    expect(parsed!.enabledFieldIds.length, WatermarkFieldIds.all.length);
  });

  test('模式 JSON 解析与白名单', () {
    final profile = ProfileConfig.fromJson({
      'id': 'processed',
      'label': '加工',
      'timePolicy': 'originalOnly',
      'coordPolicy': 'originalOnly',
      'allowedFields': ['time', 'coords', 'hash'],
      'requireProvenanceBadge': true,
      'weatherAllowed': false,
    });
    expect(profile, isNotNull);
    expect(profile!.timePolicy, TimePolicyKind.originalOnly);
    expect(profile.coordPolicy, CoordPolicyKind.originalOnly);
    expect(profile.allowsField('time'), isTrue);
    expect(profile.allowsField('weather'), isFalse);
    expect(profile.manualEntryForbidden, isTrue);
  });

  test('未知模式回退到自由模式', () {
    final registry = ProfileRegistry(const [ProfileConfig.fallback]);
    expect(registry.byId('not-exist').id, 'free');
  });
}
