import 'dart:math' as math;

import 'layout_engine.dart';

/// 照片在取景容器中的摆放结果。
///
/// 解决的问题：相机预览区的尺寸由屏幕决定（19.5:9、20:9、平板 4:3…），
/// 而成片尺寸由传感器决定（通常 4:3）。如果把水印按"屏幕尺寸"排版，
/// 预览里看到的字号、位置和真正拍出来的图必然对不上。
///
/// 这里把两者的几何关系统一到一处：水印永远在**照片坐标系**里排版，
/// 预览层再用 [toBox] 把排版结果映射到屏幕。这样"所见即所得"在任何
/// 屏幕比例下都成立，而不是在某一种手机比例下碰巧成立。
class FrameFit {
  const FrameFit({
    required this.photo,
    required this.box,
    required this.rect,
    required this.scale,
    required this.isCover,
  });

  /// 成片尺寸（像素）。
  final LayoutSize photo;

  /// 取景容器尺寸（逻辑像素）。
  final LayoutSize box;

  /// 照片在容器坐标系中的矩形。[isCover] 为 true 时可能超出容器。
  final LayoutRect rect;

  /// 照片像素 → 容器逻辑像素的缩放比。
  final double scale;

  /// true = 裁切铺满，false = 完整显示（四周留边）。
  final bool isCover;

  /// 完整显示：照片一定落在容器内，四周留边。
  static FrameFit contain(LayoutSize photo, LayoutSize box) =>
      _compute(photo, box, cover: false);

  /// 裁切铺满：容器一定被照片填满，边缘被裁掉。
  static FrameFit cover(LayoutSize photo, LayoutSize box) =>
      _compute(photo, box, cover: true);

  static FrameFit _compute(LayoutSize photo, LayoutSize box, {required bool cover}) {
    final safePhotoW = photo.width <= 0 ? 1.0 : photo.width;
    final safePhotoH = photo.height <= 0 ? 1.0 : photo.height;
    final safeBoxW = box.width <= 0 ? 1.0 : box.width;
    final safeBoxH = box.height <= 0 ? 1.0 : box.height;

    final sx = safeBoxW / safePhotoW;
    final sy = safeBoxH / safePhotoH;
    final scale = cover ? math.max(sx, sy) : math.min(sx, sy);

    final width = safePhotoW * scale;
    final height = safePhotoH * scale;
    return FrameFit(
      photo: LayoutSize(safePhotoW, safePhotoH),
      box: LayoutSize(safeBoxW, safeBoxH),
      rect: LayoutRect(
        (safeBoxW - width) / 2,
        (safeBoxH - height) / 2,
        width,
        height,
      ),
      scale: scale,
      isCover: cover,
    );
  }

  /// 取景框是否"有多余空间"（contain 且比例不一致时为 true）。
  bool get needsPadding => rect.width < box.width - 0.5 || rect.height < box.height - 0.5;

  /// 被裁掉的面积占比（0–1）。铺满模式下用它在设置页说明"边缘会少一点"。
  double get croppedFraction {
    if (!isCover) return 0;
    final visible = visiblePhotoRect;
    final total = photo.width * photo.height;
    if (total <= 0) return 0;
    final shown = visible.width * visible.height;
    return (1 - shown / total).clamp(0.0, 1.0);
  }

  /// 容器当前实际可见的那部分照片，用照片坐标表示。
  ///
  /// 铺满模式下比 `0,0,photo.width,photo.height` 小；完整显示模式下与之相同。
  LayoutRect get visiblePhotoRect {
    final left = ((0 - rect.left) / scale).clamp(0.0, photo.width);
    final top = ((0 - rect.top) / scale).clamp(0.0, photo.height);
    final right = ((box.width - rect.left) / scale).clamp(0.0, photo.width);
    final bottom = ((box.height - rect.top) / scale).clamp(0.0, photo.height);
    return LayoutRect(left, top, right - left, bottom - top);
  }

  /// 照片坐标 → 容器坐标。
  LayoutRect toBox(LayoutRect photoRect) => LayoutRect(
        rect.left + photoRect.left * scale,
        rect.top + photoRect.top * scale,
        photoRect.width * scale,
        photoRect.height * scale,
      );

  /// 容器坐标 → 照片坐标。
  LayoutRect toPhoto(LayoutRect boxRect) => LayoutRect(
        (boxRect.left - rect.left) / scale,
        (boxRect.top - rect.top) / scale,
        boxRect.width / scale,
        boxRect.height / scale,
      );

  @override
  String toString() => 'FrameFit(${photo.width}x${photo.height} → '
      '${box.width}x${box.height}, scale=${scale.toStringAsFixed(4)}, '
      '${isCover ? 'cover' : 'contain'})';
}
