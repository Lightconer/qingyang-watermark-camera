/// 方位角（相机朝向）的归一化与格式化。
///
/// 纯函数、无 Flutter 依赖：传感器只负责给出角度，文案口径全部收在这里，
/// 保证预览、出图、台账、校验端读到的是同一套说法。
library;

/// 方位角展示口径。
enum HeadingFormat {
  /// 八方位：北 / 东北 / 东 / 东南 / 南 / 西南 / 西 / 西北
  cardinal8,

  /// 十六方位：北 / 北东北 / 东北 / 东东北 / 东 …（工程放样常用）
  cardinal16,

  /// 只显示角度：346°
  degrees,
}

extension HeadingFormatX on HeadingFormat {
  String get label {
    switch (this) {
      case HeadingFormat.cardinal8:
        return '八方位';
      case HeadingFormat.cardinal16:
        return '十六方位';
      case HeadingFormat.degrees:
        return '仅角度';
    }
  }

  String get code => name;

  static HeadingFormat fromCode(String? code) {
    for (final value in HeadingFormat.values) {
      if (value.name == code) return value;
    }
    return HeadingFormat.cardinal8;
  }
}

/// 方位角策略：把磁力计/旋转矢量给的度数变成水印上的一行字。
class HeadingPolicy {
  const HeadingPolicy._();

  /// 八方位中文名（从正北顺时针）。
  static const List<String> cardinal8Names = [
    '北',
    '东北',
    '东',
    '东南',
    '南',
    '西南',
    '西',
    '西北',
  ];

  /// 十六方位中文名（从正北顺时针）。
  static const List<String> cardinal16Names = [
    '北',
    '北东北',
    '东北',
    '东东北',
    '东',
    '东东南',
    '东南',
    '南东南',
    '南',
    '南西南',
    '西南',
    '西西南',
    '西',
    '西西北',
    '西北',
    '北西北',
  ];

  /// 归一化到 `[0, 360)`。`-1` → `359`，`360` → `0`，NaN/∞ 返回 null。
  static double? normalize(double? degrees) {
    if (degrees == null || !degrees.isFinite) return null;
    var value = degrees % 360;
    if (value < 0) value += 360;
    // 避免 `359.9999999` 四舍五入成 360 后又被当成 0 以外的值。
    if (value >= 360) value = 0;
    return value;
  }

  /// 八方位名。传入非法角度返回空串（调用方据此判定不可用）。
  static String cardinal8(double? degrees) {
    final value = normalize(degrees);
    if (value == null) return '';
    return cardinal8Names[((value + 22.5) ~/ 45) % 8];
  }

  /// 十六方位名。
  static String cardinal16(double? degrees) {
    final value = normalize(degrees);
    if (value == null) return '';
    return cardinal16Names[((value + 11.25) ~/ 22.5) % 16];
  }

  /// 取整后的角度文本，例如 `346°`。
  static String degreesText(double? degrees) {
    final value = normalize(degrees);
    if (value == null) return '';
    final rounded = value.round() % 360;
    return '$rounded°';
  }

  /// 组装成水印文案（不含"方位角"前缀，前缀由字段插件统一加）：
  /// * 八方位 → `东北 45°`
  /// * 十六方位 → `北东北 22°`
  /// * 仅角度 → `346°`
  static String format(
    double? degrees, {
    HeadingFormat style = HeadingFormat.cardinal8,
  }) {
    final value = normalize(degrees);
    if (value == null) return '';
    switch (style) {
      case HeadingFormat.cardinal8:
        return '${cardinal8(value)} ${degreesText(value)}';
      case HeadingFormat.cardinal16:
        return '${cardinal16(value)} ${degreesText(value)}';
      case HeadingFormat.degrees:
        return degreesText(value);
    }
  }
}
