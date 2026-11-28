import 'package:flutter_test/flutter_test.dart';
import 'package:qingyang_watermark/core/layout/frame_fit.dart';
import 'package:qingyang_watermark/core/layout/layout_engine.dart';

void main() {
  group('完整显示（contain）', () {
    test('比例不一致时留边并居中', () {
      final fit = FrameFit.contain(
        const LayoutSize(400, 300),
        const LayoutSize(360, 600),
      );
      expect(fit.scale, closeTo(0.9, 1e-9));
      expect(fit.rect.width, closeTo(360, 1e-9));
      expect(fit.rect.height, closeTo(270, 1e-9));
      expect(fit.rect.left, closeTo(0, 1e-9));
      expect(fit.rect.top, closeTo(165, 1e-9));
      expect(fit.needsPadding, isTrue);
      expect(fit.croppedFraction, 0);
    });

    test('比例一致时完全吻合，不留边', () {
      final fit = FrameFit.contain(
        const LayoutSize(300, 200),
        const LayoutSize(300, 200),
      );
      expect(fit.scale, 1);
      expect(fit.rect.left, 0);
      expect(fit.rect.top, 0);
      expect(fit.needsPadding, isFalse);
    });

    test('可见区域就是整张照片', () {
      final fit = FrameFit.contain(
        const LayoutSize(400, 300),
        const LayoutSize(360, 600),
      );
      final visible = fit.visiblePhotoRect;
      expect(visible.left, closeTo(0, 1e-9));
      expect(visible.top, closeTo(0, 1e-9));
      expect(visible.width, closeTo(400, 1e-9));
      expect(visible.height, closeTo(300, 1e-9));
    });
  });

  group('裁切铺满（cover）', () {
    test('竖向容器里横向照片左右被裁掉', () {
      final fit = FrameFit.cover(
        const LayoutSize(400, 300),
        const LayoutSize(360, 600),
      );
      expect(fit.scale, closeTo(2, 1e-9));
      expect(fit.rect.width, closeTo(800, 1e-9));
      expect(fit.rect.height, closeTo(600, 1e-9));
      expect(fit.rect.left, closeTo(-220, 1e-9));
      expect(fit.needsPadding, isFalse);
      expect(fit.croppedFraction, greaterThan(0.5));
    });

    test('可见区域按容器反推回照片坐标', () {
      final fit = FrameFit.cover(
        const LayoutSize(400, 300),
        const LayoutSize(360, 600),
      );
      final visible = fit.visiblePhotoRect;
      expect(visible.left, closeTo(110, 1e-9));
      expect(visible.top, closeTo(0, 1e-9));
      expect(visible.width, closeTo(180, 1e-9));
      expect(visible.height, closeTo(300, 1e-9));
    });
  });

  group('坐标互转', () {
    test('照片坐标 → 容器坐标 → 照片坐标 可逆', () {
      final fit = FrameFit.cover(
        const LayoutSize(400, 300),
        const LayoutSize(360, 600),
      );
      const photoRect = LayoutRect(20, 30, 100, 50);
      final back = fit.toPhoto(fit.toBox(photoRect));
      expect(back.left, closeTo(photoRect.left, 1e-9));
      expect(back.top, closeTo(photoRect.top, 1e-9));
      expect(back.width, closeTo(photoRect.width, 1e-9));
      expect(back.height, closeTo(photoRect.height, 1e-9));
    });

    test('水印底板映射后仍然贴着画面底边', () {
      final fit = FrameFit.contain(
        const LayoutSize(400, 300),
        const LayoutSize(360, 600),
      );
      const bandInPhoto = LayoutRect(0, 270, 400, 30);
      final inBox = fit.toBox(bandInPhoto);
      expect(inBox.bottom, closeTo(fit.rect.bottom, 1e-9));
      expect(inBox.width, closeTo(fit.rect.width, 1e-9));
    });
  });

  group('退化输入', () {
    test('零尺寸不抛异常也不产生 NaN', () {
      final fit = FrameFit.contain(
        const LayoutSize(0, 0),
        const LayoutSize(0, 0),
      );
      expect(fit.scale.isFinite, isTrue);
      expect(fit.rect.width.isFinite, isTrue);
      expect(fit.rect.height.isFinite, isTrue);
    });
  });
}
