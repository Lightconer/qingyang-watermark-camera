import 'dart:math' as math;

import '../extensions/watermark_field_provider.dart';
import '../models/template.dart';

/// 与平台无关的矩形（core 不引用 dart:ui）。
class LayoutRect {
  const LayoutRect(this.left, this.top, this.width, this.height);

  static const LayoutRect zero = LayoutRect(0, 0, 0, 0);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  bool get isEmpty => width <= 0 || height <= 0;

  Map<String, dynamic> toJson() => {
        'l': _round(left),
        't': _round(top),
        'w': _round(width),
        'h': _round(height),
      };

  @override
  String toString() =>
      'LayoutRect(${_round(left)}, ${_round(top)}, ${_round(width)}, ${_round(height)})';
}

class LayoutSize {
  const LayoutSize(this.width, this.height);

  final double width;
  final double height;

  double get shortSide => math.min(width, height);
  double get longSide => math.max(width, height);
  double get aspect => height == 0 ? 0 : width / height;
}

/// 文本测量函数：core 只做几何，测量交给注入的实现（生产用 TextPainter，测试用固定公式）。
typedef TextMeasure = double Function(String text, double fontSize, bool bold);

/// 默认测量：CJK 近似 1.0 字宽，ASCII 近似 0.55 字宽。仅用于测试与兜底。
double approximateTextMeasure(String text, double fontSize, bool bold) {
  var units = 0.0;
  for (final rune in text.runes) {
    units += rune < 0x2E80 ? 0.56 : 1.0;
  }
  return units * fontSize * (bold ? 1.02 : 1.0);
}

class LayoutLine {
  const LayoutLine({
    required this.id,
    required this.text,
    required this.bounds,
    required this.fontSize,
    required this.isBadge,
    required this.emphasize,
  });

  final String id;
  final String text;
  final LayoutRect bounds;
  final double fontSize;
  final bool isBadge;
  final bool emphasize;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'rect': bounds.toJson(),
        'fontSize': _round(fontSize),
        'badge': isBadge,
        'emphasize': emphasize,
      };
}

/// 排版结果。预览层与出图层共用同一个结果，保证"所见即所得"。
class WatermarkLayout {
  const WatermarkLayout({
    required this.canvas,
    required this.band,
    required this.lines,
    required this.style,
    required this.fontSize,
    required this.padding,
    required this.lineHeight,
    this.badge,
    this.qrRect,
    this.qrData,
    this.badgeText,
    this.repeatCount = 1,
    this.compact = false,
  });

  final LayoutSize canvas;
  final LayoutRect band;
  final List<LayoutLine> lines;
  final WatermarkStyle style;
  final double fontSize;
  final double padding;
  final double lineHeight;
  final LayoutRect? badge;
  final LayoutRect? qrRect;
  final String? qrData;

  /// 来源标识文字（现场拍摄 / 导入 · 非现场取证）。
  final String? badgeText;

  /// 全景图等超宽画幅时的分段重复次数。
  final int repeatCount;

  /// 是否使用了"两行精简版"。
  final bool compact;

  double get strokeWidth => fontSize * style.strokeWidthRatio;

  Map<String, dynamic> toJson() => {
        'canvas': {'w': _round(canvas.width), 'h': _round(canvas.height)},
        'band': band.toJson(),
        'fontSize': _round(fontSize),
        'padding': _round(padding),
        'lineHeight': _round(lineHeight),
        'compact': compact,
        'repeat': repeatCount,
        'badge': badge?.toJson(),
        'badgeText': badgeText,
        'qr': qrRect?.toJson(),
        'lines': lines.map((line) => line.toJson()).toList(growable: false),
      };
}

/// 水印排版引擎。
///
/// 规则：
/// * 字号按短边比例自适应，并夹在模板给定的 min/max 之间；
/// * 通栏高度控制在短边的 6%–12%，超出则缩字号，仍超出则切两行精简版；
/// * 全景图（宽高比 > 2.5）按段重复绘制，保证任意裁剪区域都能看到水印。
class LayoutEngine {
  const LayoutEngine({this.measure = approximateTextMeasure});

  final TextMeasure measure;

  static const double _minBandRatio = 0.06;
  static const double _maxBandRatio = 0.12;

  WatermarkLayout compute({
    required LayoutSize size,
    required List<ResolvedField> fields,
    required WatermarkStyle style,
    String? badgeText,
    String? qrData,
    bool forceCompact = false,
  }) {
    final shortSide = size.shortSide;
    final maxBandHeight = shortSide * _maxBandRatio;
    final minBandHeight = shortSide * _minBandRatio;
    final padding = shortSide * style.paddingRatio;

    var fontSize = _clamp(
      shortSide * style.fontSizeRatio,
      style.minFontSize,
      style.maxFontSize,
    );
    var compact = forceCompact || fields.isEmpty;

    final workingFields = fields;
    if (!compact && shortSide < 720 && fields.length > 2) {
      // 小图直接使用两行精简版。
      compact = true;
    }

    List<ResolvedField> buildFields(bool dense) {
      if (!dense) return workingFields;
      final sorted = [...workingFields]..sort((a, b) => a.priority.compareTo(b.priority));
      return sorted.take(2).toList(growable: false);
    }

    var denseFields = buildFields(compact);
    var availableWidth = size.width - padding * 2;
    if (style.showQr) {
      availableWidth -= shortSide * style.qrSizeRatio + padding;
    }
    availableWidth = math.max(availableWidth, shortSide * 0.35);

    var lines = _buildLines(denseFields, fontSize, availableWidth, compact);
    var naturalHeight = _heightOf(lines, padding, style.lineSpacing);

    var guard = 0;
    while (naturalHeight > maxBandHeight && guard < 8) {
      guard++;
      if (fontSize > style.minFontSize * 1.05) {
        fontSize = math.max(style.minFontSize, fontSize * 0.9);
        lines = _buildLines(denseFields, fontSize, availableWidth, compact);
        naturalHeight = _heightOf(lines, padding, style.lineSpacing);
      } else if (!compact) {
        compact = true;
        denseFields = buildFields(true);
        lines = _buildLines(denseFields, fontSize, availableWidth, compact);
        naturalHeight = _heightOf(lines, padding, style.lineSpacing);
      } else {
        break;
      }
    }

    final bandHeight = _clamp(
      math.max(naturalHeight, minBandHeight),
      minBandHeight,
      math.max(minBandHeight, maxBandHeight),
    );

    final lineHeight = fontSize * style.lineSpacing;
    final band = _bandRect(
      size: size,
      style: style,
      height: bandHeight,
      padding: padding,
      lines: lines,
    );

    final positioned = <LayoutLine>[];
    var cursorTop = band.top + padding;
    final textLeft = style.position == WatermarkPosition.bottomBar
        ? band.left + padding
        : band.left + padding;
    for (final line in lines) {
      positioned.add(LayoutLine(
        id: line.id,
        text: line.text,
        bounds: LayoutRect(
          textLeft,
          cursorTop,
          measure(line.text, line.fontSize, line.emphasize),
          line.fontSize * style.lineSpacing,
        ),
        fontSize: line.fontSize,
        isBadge: line.isBadge,
        emphasize: line.emphasize,
      ));
      cursorTop += line.fontSize * style.lineSpacing;
    }

    LayoutRect? badge;
    if (style.showBadge && badgeText != null && badgeText.isNotEmpty) {
      final badgeFont = fontSize * 0.8;
      final badgeWidth = measure(badgeText, badgeFont, true) + badgeFont * 1.2;
      final badgeHeight = badgeFont * 1.55;
      final top = band.top + padding * 0.35;
      final left = style.position == WatermarkPosition.bottomBar
          ? band.right - padding - badgeWidth
          : band.left + padding;
      badge = LayoutRect(left, top, badgeWidth, badgeHeight);
    }

    LayoutRect? qrRect;
    if (style.showQr && qrData != null && qrData.isNotEmpty) {
      final qrSize = shortSide * style.qrSizeRatio;
      qrRect = LayoutRect(
        band.right - padding - qrSize,
        band.bottom - padding - qrSize,
        qrSize,
        qrSize,
      );
    }

    final repeatCount = size.aspect > 2.5
        ? math.max(1, (size.width / (size.height * 1.6)).ceil())
        : 1;

    return WatermarkLayout(
      canvas: size,
      band: band,
      lines: positioned,
      style: style,
      fontSize: fontSize,
      padding: padding,
      lineHeight: lineHeight,
      badge: badge,
      qrRect: qrRect,
      qrData: qrData,
      badgeText: badgeText,
      repeatCount: repeatCount,
      compact: compact,
    );
  }

  LayoutRect _bandRect({
    required LayoutSize size,
    required WatermarkStyle style,
    required double height,
    required double padding,
    required List<_PendingLine> lines,
  }) {
    final maxTextWidth = lines.isEmpty
        ? size.width * 0.4
        : lines
            .map((line) => measure(line.text, line.fontSize, line.emphasize))
            .fold<double>(0, math.max);

    switch (style.position) {
      case WatermarkPosition.bottomBar:
        return LayoutRect(0, size.height - height, size.width, height);
      case WatermarkPosition.bottomLeft:
        final width = math.min(
          size.width,
          maxTextWidth + padding * 2 + height * 0.35,
        );
        return LayoutRect(padding * 0.5, size.height - height - padding * 0.5,
            width, height);
      case WatermarkPosition.bottomRight:
        final width = math.min(
          size.width,
          maxTextWidth + padding * 2 + height * 0.35,
        );
        return LayoutRect(
            size.width - width - padding * 0.5,
            size.height - height - padding * 0.5,
            width,
            height);
    }
  }

  double _heightOf(List<_PendingLine> lines, double padding, double lineSpacing) {
    var total = padding * 2;
    for (final line in lines) {
      total += line.fontSize * lineSpacing;
    }
    return total;
  }

  List<_PendingLine> _buildLines(
    List<ResolvedField> fields,
    double fontSize,
    double maxWidth,
    bool compact,
  ) {
    final result = <_PendingLine>[];
    for (final field in fields) {
      final size = field.emphasize ? fontSize * 1.12 : fontSize;
      final wrapped = _wrap(field.text, size, maxWidth, compact);
      for (var index = 0; index < wrapped.length; index++) {
        result.add(_PendingLine(
          id: index == 0 ? field.id : '${field.id}#$index',
          text: wrapped[index],
          fontSize: size,
          emphasize: field.emphasize && index == 0,
        ));
      }
      if (compact && result.length >= 2) break;
    }
    return result;
  }

  List<String> _wrap(String text, double fontSize, double maxWidth, bool compact) {
    if (text.isEmpty) return const <String>[];
    if (measure(text, fontSize, false) <= maxWidth) return <String>[text];

    final maxLines = compact ? 1 : 3;
    final lines = <String>[];
    var buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final candidate = buffer.toString() + char;
      if (measure(candidate, fontSize, false) > maxWidth && buffer.isNotEmpty) {
        lines.add(buffer.toString());
        buffer = StringBuffer(char);
        if (lines.length >= maxLines) break;
      } else {
        buffer.write(char);
      }
    }
    if (buffer.isNotEmpty && lines.length < maxLines) {
      lines.add(buffer.toString());
    }
    // 溢出时补省略号
    if (lines.isNotEmpty &&
        measure(lines.join(), fontSize, false) <
            measure(text, fontSize, false)) {
      final last = lines.removeLast();
      lines.add(last.length > 2 ? '${last.substring(0, last.length - 1)}…' : last);
    }
    return lines;
  }
}

class _PendingLine {
  const _PendingLine({
    required this.id,
    required this.text,
    required this.fontSize,
    required this.emphasize,
  });

  final String id;
  final String text;
  final double fontSize;
  final bool emphasize;

  bool get isBadge => false;
}

double _clamp(double value, double min, double max) =>
    value < min ? min : (value > max ? max : value);

double _round(double value) => (value * 10).roundToDouble() / 10;
