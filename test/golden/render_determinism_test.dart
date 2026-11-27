import 'package:flutter_test/flutter_test.dart';
import 'package:qingyang_watermark/core/extensions/watermark_field_provider.dart';
import 'package:qingyang_watermark/core/layout/layout_engine.dart';
import 'package:qingyang_watermark/core/models/template.dart';
import 'package:qingyang_watermark/engines/hash/hash_engine.dart';
import 'package:qingyang_watermark/engines/image/image_codec.dart';
import 'package:qingyang_watermark/engines/watermark/watermark_renderer.dart';

/// 像素级回归：不依赖 golden 基线，用"同一输入两次渲染必须字节一致 + 必须真的改变像素"
/// 来守住渲染器退化。需要人工比对的 golden 基线由本地 `flutter test --update-goldens` 生成。
void main() {
  const codec = FlutterImageCodec();
  const renderer = CanvasWatermarkRenderer();
  const engine = LayoutEngine(measure: textPainterMeasure);

  List<ResolvedField> fields() => const [
        ResolvedField(
          id: WatermarkFieldIds.sourceBadge,
          label: '来源',
          text: '现场拍摄 · NTP',
          priority: 5,
          emphasize: true,
        ),
        ResolvedField(
          id: WatermarkFieldIds.time,
          label: '时间',
          text: '2026-11-27 20:31:05',
          priority: 10,
          emphasize: true,
        ),
        ResolvedField(
          id: WatermarkFieldIds.coords,
          label: '经纬度',
          text: '30.274084°N 120.155070°E  N30°16\'26.7" E120°09\'18.3"',
          priority: 20,
          emphasize: true,
        ),
        ResolvedField(
          id: WatermarkFieldIds.hash,
          label: '哈希',
          text: 'SHA256 a3f5c9d1e7b24680',
          priority: 95,
        ),
      ];

  Future<WatermarkLayout> buildLayout(int width, int height) async {
    return engine.compute(
      size: LayoutSize(width.toDouble(), height.toDouble()),
      fields: fields(),
      style: const WatermarkStyle(),
      badgeText: '现场拍摄',
    );
  }

  testWidgets('同一布局两次渲染结果字节一致', (tester) async {
    await tester.runAsync(() async {
      final base = await blankImage(1600, 1200);
      final layout = await buildLayout(1600, 1200);
      final first = await renderer.render(base: base, layout: layout);
      final second = await renderer.render(base: base, layout: layout);
      final firstBytes = await codec.encodeJpeg(first, quality: 90);
      final secondBytes = await codec.encodeJpeg(second, quality: 90);
      expect(firstBytes, secondBytes);
    });
  });

  testWidgets('水印真的画进了像素（与底图哈希不同）', (tester) async {
    await tester.runAsync(() async {
      const hasher = CryptoHashEngine();
      final base = await blankImage(1600, 1200);
      final baseBytes = await codec.encodeJpeg(base, quality: 90);
      final layout = await buildLayout(1600, 1200);
      final rendered = await renderer.render(base: base, layout: layout);
      final renderedBytes = await codec.encodeJpeg(rendered, quality: 90);

      expect(hasher.sha256OfBytes(baseBytes), isNot(hasher.sha256OfBytes(renderedBytes)));
      expect(layout.lines.length, greaterThanOrEqualTo(3));
      expect(layoutHasVisibleContent(layout), isTrue);
    });
  });

  testWidgets('竖图与水印位置无关地保持在画面内', (tester) async {
    await tester.runAsync(() async {
      for (final width in [1080, 3000]) {
        for (final height in [1440, 4000]) {
          final layout = await buildLayout(width, height);
          expect(layout.band.top, greaterThanOrEqualTo(0));
          expect(layout.band.bottom, lessThanOrEqualTo(height.toDouble() + 0.5));
          expect(layout.band.right, lessThanOrEqualTo(width.toDouble() + 0.5));
          for (final line in layout.lines) {
            expect(line.bounds.top, greaterThanOrEqualTo(layout.band.top - 0.5));
          }
        }
      }
    });
  });
}
