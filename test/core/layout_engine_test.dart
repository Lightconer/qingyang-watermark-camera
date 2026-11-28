import 'package:flutter_test/flutter_test.dart';
import 'package:qingyang_watermark/core/extensions/watermark_field_provider.dart';
import 'package:qingyang_watermark/core/layout/layout_engine.dart';
import 'package:qingyang_watermark/core/models/template.dart';

List<ResolvedField> fields(int count) => [
      for (var index = 0; index < count; index++)
        ResolvedField(
          id: 'f$index',
          label: 'f$index',
          text: '示例字段内容 $index',
          priority: index * 10,
          emphasize: index < 2,
        ),
    ];

void main() {
  const engine = LayoutEngine();

  test('通栏高度落在短边 6%–12% 区间', () {
    final layout = engine.compute(
      size: const LayoutSize(4000, 3000),
      fields: [
        const ResolvedField(
          id: 'time',
          label: '时间',
          text: '2026-11-27 20:31:05',
          priority: 10,
          emphasize: true,
        ),
        const ResolvedField(
          id: 'coords',
          label: '经纬度',
          text: '30.274084°N 120.155070°E',
          priority: 20,
          emphasize: true,
        ),
      ],
      style: const WatermarkStyle(),
      badgeText: '现场拍摄',
    );
    expect(layout.band.height, greaterThanOrEqualTo(3000 * 0.06 - 0.5));
    expect(layout.band.height, lessThanOrEqualTo(3000 * 0.12 + 0.5));
    expect(layout.band.bottom, closeTo(3000, 0.5));
    expect(layout.lines.length, 2);
    expect(layout.badge, isNotNull);
    expect(layout.compact, isFalse);
  });

  test('小图切成两行精简版', () {
    final layout = engine.compute(
      size: const LayoutSize(640, 480),
      fields: fields(5),
      style: const WatermarkStyle(),
      badgeText: '导入 · 非现场取证',
    );
    expect(layout.compact, isTrue);
    expect(layout.lines.length, lessThanOrEqualTo(2));
    expect(layout.fontSize, greaterThanOrEqualTo(12));
  });

  test('全景图分段重复绘制', () {
    final layout = engine.compute(
      size: const LayoutSize(12000, 3000),
      fields: fields(2),
      style: const WatermarkStyle(),
    );
    expect(layout.repeatCount, greaterThan(1));
  });

  test('左下 / 右下定位不铺满整宽', () {
    for (final position in [
      WatermarkPosition.bottomLeft,
      WatermarkPosition.bottomRight,
    ]) {
      final layout = engine.compute(
        size: const LayoutSize(4000, 3000),
        fields: fields(2),
        style: WatermarkStyle(position: position),
      );
      expect(layout.band.width, lessThan(4000));
      expect(layout.band.bottom, lessThan(3000));
    }
  });

  test('顶部通栏贴着画面上沿', () {
    final layout = engine.compute(
      size: const LayoutSize(4000, 3000),
      fields: fields(2),
      style: const WatermarkStyle(position: WatermarkPosition.topBar),
      badgeText: '现场拍摄',
    );
    expect(layout.band.top, 0);
    expect(layout.band.width, 4000);
    expect(layout.band.bottom, lessThanOrEqualTo(3000 * 0.12 + 0.5));
    // 角标不越过画面
    expect(layout.badge, isNotNull);
    expect(layout.badge!.left, greaterThanOrEqualTo(0));
    expect(layout.badge!.right, lessThanOrEqualTo(4000.5));
  });

  test('左下 / 右下时角标移到底板外侧，不压正文', () {
    for (final position in [
      WatermarkPosition.bottomLeft,
      WatermarkPosition.bottomRight,
    ]) {
      final layout = engine.compute(
        size: const LayoutSize(4000, 3000),
        fields: fields(2),
        style: WatermarkStyle(position: position),
        badgeText: '现场拍摄',
      );
      final badge = layout.badge;
      expect(badge, isNotNull, reason: '$position 应绘制来源角标');
      expect(
        badge!.bottom,
        lessThanOrEqualTo(layout.lines.first.bounds.top + 0.5),
        reason: '$position 的角标必须落在第一行文字上方',
      );
      // 角标必须与底板同侧对齐，不能跑到画面另一头
      if (position == WatermarkPosition.bottomLeft) {
        expect(badge.left, closeTo(layout.band.left, 0.5));
      } else {
        expect(badge.right, closeTo(layout.band.right, 0.5));
      }
    }
  });

  test('通栏角标占用横向空间，长文本不会压到角标底下', () {
    final layout = engine.compute(
      size: const LayoutSize(4000, 3000),
      fields: const [
        ResolvedField(
          id: 'address',
          label: '地址',
          text: '浙江省杭州市西湖区某某街道某某社区某某园区某某号楼某某单元某某室'
              '（这是一段足够长的地址用来触发自动换行）',
          priority: 40,
          emphasize: true,
        ),
      ],
      style: const WatermarkStyle(),
      badgeText: '现场拍摄',
    );
    expect(layout.badge, isNotNull);
    for (final line in layout.lines) {
      expect(
        line.bounds.right,
        lessThanOrEqualTo(layout.badge!.left + 0.5),
        reason: '第 ${layout.lines.indexOf(line)} 行越过了角标左边界',
      );
    }
  });

  test('角标关闭时完全不占位', () {
    final withBadge = engine.compute(
      size: const LayoutSize(4000, 3000),
      fields: fields(2),
      style: const WatermarkStyle(),
      badgeText: '现场拍摄',
    );
    final without = engine.compute(
      size: const LayoutSize(4000, 3000),
      fields: fields(2),
      style: const WatermarkStyle(showBadge: false),
      badgeText: '现场拍摄',
    );
    expect(withBadge.badge, isNotNull);
    expect(without.badge, isNull);
  });

  test('布局是确定的：同输入两次结果一致', () {
    final first = engine.compute(
      size: const LayoutSize(3000, 4000),
      fields: fields(3),
      style: const WatermarkStyle(),
      badgeText: '现场拍摄',
      qrData: 'QY|camera|2026',
    );
    final second = engine.compute(
      size: const LayoutSize(3000, 4000),
      fields: fields(3),
      style: const WatermarkStyle(),
      badgeText: '现场拍摄',
      qrData: 'QY|camera|2026',
    );
    expect(first.toJson().toString(), second.toJson().toString());
    expect(first.qrRect, isNotNull);
  });
}
