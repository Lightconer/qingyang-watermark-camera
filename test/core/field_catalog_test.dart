import 'package:flutter_test/flutter_test.dart';
import 'package:qingyang_watermark/core/extensions/watermark_field_provider.dart';
import 'package:qingyang_watermark/core/models/photo_metadata.dart';
import 'package:qingyang_watermark/core/models/template.dart';
import 'package:qingyang_watermark/core/models/types.dart';
import 'package:qingyang_watermark/core/policy/heading.dart';
import 'package:qingyang_watermark/core/service/field_catalog.dart';

final FieldCatalog catalog = FieldCatalog(builtinFieldProviders());

final TemplateConfig allFieldsTemplate = TemplateConfig(
  id: 'tpl',
  name: '全字段',
  profileId: 'forensics',
  style: const WatermarkStyle(),
  enabledFieldIds: WatermarkFieldIds.all.toSet(),
);

FieldContext captureContext({
  bool online = true,
  TimeAuthority authority = TimeAuthority.ntp,
  GeoPoint? position,
  double? heading,
  double? headingAccuracy,
  HeadingFormat headingFormat = HeadingFormat.cardinal8,
}) {
  return FieldContext(
    mode: CaptureMode.forensics,
    provenance: Provenance.capture(batchId: 'b1', at: DateTime(2026, 11, 27, 20, 31, 5)),
    capture: CaptureContext(
      capturedAt: DateTime(2026, 11, 27, 20, 31, 5),
      timeAuthority: authority,
      coordAuthority: position == null ? CoordAuthority.missing : CoordAuthority.fused,
      position: position,
      altitudeMeters: 42.0,
      address: '浙江省杭州市西湖区某街道 88 号',
      weather: WeatherSnapshot(
        temperatureC: 18,
        text: '多云',
        fetchedAt: DateTime(2026, 11, 27, 20, 31, 5),
      ),
      deviceModel: 'Test Phone',
      online: online,
      headingDegrees: heading,
      headingAccuracyDegrees: headingAccuracy,
      headingAuthority:
          heading == null ? HeadingAuthority.missing : HeadingAuthority.sensor,
    ),
    template: allFieldsTemplate,
    weatherAllowed: true,
    headingFormat: headingFormat,
  );
}

FieldContext importContext({bool withGps = false}) {
  return FieldContext(
    mode: CaptureMode.processed,
    provenance: Provenance(
      source: PhotoSource.gallery,
      batchId: 'b2',
      importedAt: DateTime(2026, 11, 27, 21, 0, 0),
    ),
    capture: CaptureContext(
      capturedAt: DateTime(2026, 11, 1, 9, 0, 0),
      timeAuthority: TimeAuthority.originalExif,
      coordAuthority: withGps ? CoordAuthority.originalExif : CoordAuthority.missing,
      position: withGps
          ? const GeoPoint(latitude: 30.274084, longitude: 120.15507)
          : null,
    ),
    template: allFieldsTemplate,
    original: PhotoMetadata(
      takenAt: DateTime(2026, 11, 1, 9, 0, 0),
      gps: withGps
          ? const GeoPoint(latitude: 30.274084, longitude: 120.15507)
          : null,
      model: 'Original Phone',
      hasExifBlock: true,
    ),
    weatherAllowed: false,
  );
}

List<String> resolveIds(FieldContext context, {Set<String>? allowed}) {
  final fields = catalog.resolve(
    context,
    enabledFieldIds: allFieldsTemplate.enabledFieldIds,
    allowedFieldIds: allowed,
  );
  return fields.map((field) => field.id).toList(growable: false);
}

void main() {
  test('在线拍摄：字段按优先级排序且来源标识在最前', () {
    final ids = resolveIds(captureContext(
      position: const GeoPoint(latitude: 30.274084, longitude: 120.15507),
    ));
    expect(ids.first, WatermarkFieldIds.sourceBadge);
    expect(ids.contains(WatermarkFieldIds.time), isTrue);
    expect(ids.contains(WatermarkFieldIds.coords), isTrue);
    expect(ids.contains(WatermarkFieldIds.weather), isTrue);
    expect(ids.contains(WatermarkFieldIds.hash), isFalse);
  });

  test('离线拍摄：时间后缀标注「离线采集·本地系统时间」', () {
    final fields = catalog.resolve(
      captureContext(online: false, authority: TimeAuthority.system),
      enabledFieldIds: allFieldsTemplate.enabledFieldIds,
    );
    final time = fields.firstWhere((field) => field.id == WatermarkFieldIds.time);
    expect(time.text, contains('离线采集'));
    expect(time.text, contains('本地系统时间'));
  });

  test('定位失败：经纬度显示「定位失败」且不伪造坐标', () {
    final fields = catalog.resolve(
      captureContext(),
      enabledFieldIds: allFieldsTemplate.enabledFieldIds,
    );
    final coords = fields.firstWhere((field) => field.id == WatermarkFieldIds.coords);
    expect(coords.text, '定位失败');
  });

  test('导入图无原始 GPS：显示「无原始定位」，且不显示天气', () {
    final ids = resolveIds(importContext());
    expect(ids.contains(WatermarkFieldIds.weather), isFalse);
    final fields = catalog.resolve(
      importContext(),
      enabledFieldIds: allFieldsTemplate.enabledFieldIds,
    );
    final coords = fields.firstWhere((field) => field.id == WatermarkFieldIds.coords);
    expect(coords.text, '无原始定位');
    final badge = fields.firstWhere((field) => field.id == WatermarkFieldIds.sourceBadge);
    expect(badge.text, contains('导入'));
    expect(badge.text, contains('非现场取证'));
  });

  test('导入图有原始 GPS：显示原图坐标', () {
    final fields = catalog.resolve(
      importContext(withGps: true),
      enabledFieldIds: allFieldsTemplate.enabledFieldIds,
    );
    final coords = fields.firstWhere((field) => field.id == WatermarkFieldIds.coords);
    expect(coords.text, contains('30.274084'));
    expect(coords.text, contains('N'));
  });

  test('来源标识优先级最高，任何模式都不可关闭', () {
    final fields = catalog.resolve(
      importContext(),
      enabledFieldIds: {WatermarkFieldIds.sourceBadge},
    );
    expect(fields.length, 1);
    expect(fields.first.id, WatermarkFieldIds.sourceBadge);
  });

  test('指纹字段仅在第二遍绘制时出现', () {
    final without = resolveIds(captureContext(
      position: const GeoPoint(latitude: 30.1, longitude: 120.1),
    ));
    expect(without.contains(WatermarkFieldIds.hash), isFalse);

    final withPrint = catalog.resolve(
      captureContext(position: const GeoPoint(latitude: 30.1, longitude: 120.1))
          .withFingerprint('a' * 64),
      enabledFieldIds: allFieldsTemplate.enabledFieldIds,
    );
    final hash = withPrint.firstWhere((field) => field.id == WatermarkFieldIds.hash);
    expect(hash.text, contains('SHA256'));
    expect(hash.text.length, lessThan(30));
  });

  test('模式白名单可过滤字段', () {
    final ids = resolveIds(
      captureContext(position: const GeoPoint(latitude: 30.1, longitude: 120.1)),
      allowed: {
        WatermarkFieldIds.sourceBadge,
        WatermarkFieldIds.time,
        WatermarkFieldIds.coords,
      },
    );
    expect(ids, [
      WatermarkFieldIds.sourceBadge,
      WatermarkFieldIds.time,
      WatermarkFieldIds.coords,
    ]);
  });

  group('方位角字段', () {
    test('有传感器读数时按八方位输出', () {
      final fields = catalog.resolve(
        captureContext(heading: 42, headingAccuracy: 3),
        enabledFieldIds: allFieldsTemplate.enabledFieldIds,
      );
      final heading =
          fields.firstWhere((field) => field.id == WatermarkFieldIds.heading);
      expect(heading.text, '方位角 东北 42°');
      expect(heading.text.contains('精度低'), isFalse);
    });

    test('写法跟随设置（十六方位 / 仅角度）', () {
      final sixteen = catalog.resolve(
        captureContext(heading: 22, headingFormat: HeadingFormat.cardinal16),
        enabledFieldIds: allFieldsTemplate.enabledFieldIds,
      );
      expect(
        sixteen
            .firstWhere((field) => field.id == WatermarkFieldIds.heading)
            .text,
        '方位角 北东北 22°',
      );

      final degrees = catalog.resolve(
        captureContext(heading: 346, headingFormat: HeadingFormat.degrees),
        enabledFieldIds: allFieldsTemplate.enabledFieldIds,
      );
      expect(
        degrees
            .firstWhere((field) => field.id == WatermarkFieldIds.heading)
            .text,
        '方位角 346°',
      );
    });

    test('无传感器时整行不出现，绝不写 0°', () {
      final ids = resolveIds(captureContext());
      expect(ids.contains(WatermarkFieldIds.heading), isFalse);
    });

    test('精度差于 ±25° 时补「（精度低）」', () {
      final fields = catalog.resolve(
        captureContext(heading: 200, headingAccuracy: 45),
        enabledFieldIds: allFieldsTemplate.enabledFieldIds,
      );
      final heading =
          fields.firstWhere((field) => field.id == WatermarkFieldIds.heading);
      expect(heading.text, contains('精度低'));
    });

    test('导入链路不出现方位角（原图无可靠朝向来源）', () {
      final ids = resolveIds(importContext(withGps: true));
      expect(ids.contains(WatermarkFieldIds.heading), isFalse);
    });
  });
}
