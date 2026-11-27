import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/layout/layout_engine.dart';
import '../../core/models/template.dart';

/// 水印渲染引擎接口。
///
/// 只负责"把排版结果画到像素上"，不解析字段、不做来源判断，因此新增字段不会改到这里。
abstract class WatermarkRenderer {
  Future<ui.Image> render({
    required ui.Image base,
    required WatermarkLayout layout,
    ui.Image? logo,
  });
}

/// 基于 Canvas 的默认实现：文字走"描边 + 填充"双绘，保证强光与复杂背景下可读。
class CanvasWatermarkRenderer implements WatermarkRenderer {
  const CanvasWatermarkRenderer();

  static const ui.Color _cameraBadgeColor = ui.Color(0xFF13794A);
  static const ui.Color _importBadgeColor = ui.Color(0xFFC2570A);

  @override
  Future<ui.Image> render({
    required ui.Image base,
    required WatermarkLayout layout,
    ui.Image? logo,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(base, ui.Offset.zero, ui.Paint());

    if (layout.repeatCount <= 1) {
      _drawBand(canvas, layout, layout.band, logo);
    } else {
      final blockWidth = layout.canvas.width / layout.repeatCount;
      for (var index = 0; index < layout.repeatCount; index++) {
        final rect = LayoutRect(
          index * blockWidth,
          layout.band.top,
          blockWidth,
          layout.band.height,
        );
        _drawBand(canvas, layout, rect, logo, repeated: true);
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(base.width, base.height);
    picture.dispose();
    return image;
  }

  void _drawBand(
    ui.Canvas canvas,
    WatermarkLayout layout,
    LayoutRect band,
    ui.Image? logo, {
    bool repeated = false,
  }) {
    final style = layout.style;
    final shortSide = layout.canvas.shortSide;
    final radius = ui.Radius.circular(shortSide * style.cornerRadiusRatio);

    final bandColor = ui.Color(style.bandColor)
        .withOpacity((style.bandOpacity * style.opacity).clamp(0.0, 1.0));
    final rrect = ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(band.left, band.top, band.width, band.height),
      radius,
    );
    canvas.drawRRect(rrect, ui.Paint()..color = bandColor);

    final textColor = ui.Color(style.color).withOpacity(style.opacity.clamp(0.0, 1.0));
    final strokeColor =
        ui.Color(style.strokeColor).withOpacity(style.opacity.clamp(0.0, 1.0));
    final strokeWidth = layout.strokeWidth;

    var offsetX = band.left + layout.padding;
    if (repeated) {
      offsetX = band.left + layout.padding * 0.6;
    }

    for (final line in layout.lines) {
      final dx = repeated
          ? offsetX
          : line.bounds.left;
      final dy = line.bounds.top;
      _paintText(
        canvas,
        line.text,
        ui.Offset(dx, dy),
        line.fontSize,
        textColor,
        strokeColor,
        strokeWidth,
        bold: line.emphasize,
      );
    }

    if (layout.badgeText != null && layout.badge != null) {
      final badgeRect = layout.badge!;
      final adjusted = repeated
          ? LayoutRect(
              band.right - layout.padding - badgeRect.width,
              badgeRect.top,
              badgeRect.width,
              badgeRect.height,
            )
          : badgeRect;
      _drawBadge(canvas, layout, adjusted);
    }

    if (layout.qrRect != null && layout.qrData != null) {
      _drawQr(canvas, layout, repeated ? null : layout.qrRect!);
    }

    if (logo != null && style.showLogo) {
      final size = shortSide * 0.08;
      final dest = ui.Rect.fromLTWH(
        band.left + layout.padding,
        band.top + layout.padding,
        size,
        size,
      );
      canvas.drawImageRect(
        logo,
        ui.Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
        dest,
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
    }
  }

  void _drawBadge(ui.Canvas canvas, WatermarkLayout layout, LayoutRect rect) {
    final isCamera = (layout.badgeText ?? '').startsWith('现场');
    final color = isCamera ? _cameraBadgeColor : _importBadgeColor;
    final rrect = ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height),
      ui.Radius.circular(rect.height * 0.28),
    );
    canvas.drawRRect(
      rrect,
      ui.Paint()..color = color.withOpacity(0.92 * layout.style.opacity),
    );
    final fontSize = rect.height * 0.58;
    final painter = TextPainter(
      text: TextSpan(
        text: layout.badgeText,
        style: TextStyle(
          color: const ui.Color(0xFFFFFFFF),
          fontSize: fontSize,
          fontWeight: ui.FontWeight.w700,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(
      canvas,
      ui.Offset(
        rect.left + (rect.width - painter.width) / 2,
        rect.top + (rect.height - painter.height) / 2,
      ),
    );
  }

  void _drawQr(ui.Canvas canvas, WatermarkLayout layout, LayoutRect? rect) {
    if (rect == null) return;
    final data = layout.qrData;
    if (data == null || data.isEmpty) return;
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      gapless: true,
      eyeStyle: QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: const ui.Color(0xFF000000),
      ),
      dataModuleStyle: QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: const ui.Color(0xFF000000),
      ),
    );
    canvas.save();
    canvas.translate(rect.left, rect.top);
    painter.paint(canvas, ui.Size(rect.width, rect.height));
    canvas.restore();
  }

  void _paintText(
    ui.Canvas canvas,
    String text,
    ui.Offset offset,
    double fontSize,
    ui.Color color,
    ui.Color strokeColor,
    double strokeWidth, {
    required bool bold,
  }) {
    if (text.isEmpty) return;
    final base = TextStyle(
      fontSize: fontSize,
      fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w500,
      height: 1.12,
      letterSpacing: 0.2,
    );

    final strokePaint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = math.max(strokeWidth, 0.8)
      ..strokeJoin = ui.StrokeJoin.round
      ..color = strokeColor;

    final strokePainter = TextPainter(
      text: TextSpan(text: text, style: base.copyWith(foreground: strokePaint)),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout();
    strokePainter.paint(canvas, offset);

    final fillPainter = TextPainter(
      text: TextSpan(text: text, style: base.copyWith(color: color)),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout();
    fillPainter.paint(canvas, offset);
  }
}

/// 测试替身：把"已绘制"记录到 [calls] 并原样返回底图。
class FakeWatermarkRenderer implements WatermarkRenderer {
  final List<WatermarkLayout> calls = [];

  @override
  Future<ui.Image> render({
    required ui.Image base,
    required WatermarkLayout layout,
    ui.Image? logo,
  }) async {
    calls.add(layout);
    return base;
  }
}

/// 供预览层复用的文字测量实现（与出图共用同一套度量，保证所见即所得）。
double textPainterMeasure(String text, double fontSize, bool bold) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w500,
      ),
    ),
    textDirection: ui.TextDirection.ltr,
    maxLines: 1,
  )..layout();
  return painter.width;
}

/// 便于测试注入固定字节的空白图。
Future<ui.Image> blankImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF000000),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

/// 供上层判断水印是否真的画进了像素（校验工具用）。
bool layoutHasVisibleContent(WatermarkLayout layout) =>
    layout.lines.any((line) => line.text.trim().isNotEmpty) ||
    (layout.qrRect != null);

/// 说明：水印必须画在像素上，不允许只写 EXIF。此常量在 UI 与 README 中引用。
const String kWatermarkPixelNotice = '水印已绘制在像素层，并同步写入 EXIF/XMP';
