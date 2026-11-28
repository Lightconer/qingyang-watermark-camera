import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/extensions/watermark_field_provider.dart';
import '../../core/layout/frame_fit.dart';
import '../../core/layout/layout_engine.dart';
import '../../core/models/template.dart';
import '../../core/models/types.dart';
import 'capture_controller.dart';

/// 拍摄页：预览为主，水印以「与出图同规则」的方式实时叠加。
///
/// 关键点：水印永远在**成片坐标系**里排版，再由 [FrameFit] 映射到屏幕。
/// 屏幕是 19.5:9、20:9 还是平板 4:3 都不影响水印的相对位置与字号，
/// 这是"预览和成片对不上"这类设备差异问题的根因所在。
class CapturePage extends StatefulWidget {
  const CapturePage({super.key, required this.controller});

  final CaptureController controller;

  @override
  State<CapturePage> createState() => CapturePageState();
}

class CapturePageState extends State<CapturePage> {
  CaptureController get controller => widget.controller;

  Future<void> shoot() async {
    final path = await controller.shoot();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(path == null ? controller.status : '已保存：${controller.status}'),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final services = ServicesScope.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final camera = controller.camera;
        final ready = camera?.value.isInitialized ?? false;
        return Column(
          children: [
            Expanded(
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final box = LayoutSize(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    final fit = (ready && camera != null)
                        ? _frameFit(
                            camera.value.aspectRatio,
                            box,
                            fill: services.settings.previewFill,
                          )
                        : null;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        // 留边模式下的背景：不用纯黑，避免大黑边观感；
                        // 也不用"再叠一层模糊预览"，低端机上多一份相机纹理就是掉帧。
                        if (fit != null && fit.needsPadding)
                          const _LetterboxBackdrop(),
                        if (ready && camera != null && fit != null)
                          Positioned(
                            left: fit.rect.left,
                            top: fit.rect.top,
                            width: fit.rect.width,
                            height: fit.rect.height,
                            child: CameraPreview(camera),
                          )
                        else
                          _Placeholder(
                            initializing: controller.initializing,
                            error: controller.error,
                            errorHint: controller.errorHint,
                            onRetry: controller.initialize,
                          ),
                        if (ready && fit != null)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: WatermarkOverlayPainter(
                                  services: services,
                                  controller: controller,
                                  fit: fit,
                                ),
                              ),
                            ),
                          ),
                        if (controller.gridOn && ready)
                          const Positioned.fill(
                            child: IgnorePointer(child: _GridLines()),
                          ),
                        Positioned(
                          left: 12,
                          right: 12,
                          top: 10,
                          child: _StatusBar(controller: controller),
                        ),
                        if (controller.notices.isNotEmpty)
                          Positioned(
                            left: 12,
                            right: 12,
                            bottom: 12,
                            child: IgnorePointer(
                              child: _NoticeStrip(notices: controller.notices),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            _Controls(controller: controller),
          ],
        );
      },
    );
  }

  /// 由相机上报的比例推出成片比例，再算出成片在屏幕上的落位。
  ///
  /// 相机插件给的 `aspectRatio` 是"传感器方向"（横向）的宽高比，
  /// 竖屏取景时必须取倒数——不同厂商的 previewSize 上报不一致，
  /// 这里按屏幕方向判断，而不是假设竖屏，横屏/平板下同样成立。
  FrameFit _frameFit(double rawAspect, LayoutSize box, {required bool fill}) {
    final safe = (rawAspect.isFinite && rawAspect > 0) ? rawAspect : 3 / 4;
    final landscape = box.width > box.height;
    final displayAspect = landscape
        ? (safe >= 1 ? safe : 1 / safe)
        : (safe >= 1 ? 1 / safe : safe);
    // 以长边 1000 为基准画布：字号、内边距都按短边比例算，
    // 与出图（3000/4000 短边）走的是同一条缩放路径，minFontSize 不会在预览里误触发。
    final photo = displayAspect >= 1
        ? LayoutSize(1000, 1000 / displayAspect)
        : LayoutSize(1000 * displayAspect, 1000);
    return fill ? FrameFit.cover(photo, box) : FrameFit.contain(photo, box);
  }
}

/// 留边背景：竖向渐变 + 极淡的网点感，比纯黑更像"取景窗"。
class _LetterboxBackdrop extends StatelessWidget {
  const _LetterboxBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF141917), Color(0xFF0A0D0C)],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.initializing,
    required this.error,
    required this.errorHint,
    required this.onRetry,
  });

  final bool initializing;
  final String? error;
  final String? errorHint;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (initializing) const CircularProgressIndicator(),
          if (!initializing && error != null) ...[
            const Icon(Icons.videocam_off_outlined, size: 48),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(error!, textAlign: TextAlign.center),
            ),
            if (errorHint != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  errorHint!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});

  final CaptureController controller;

  @override
  Widget build(BuildContext context) {
    final services = ServicesScope.of(context);
    final profile = controller.profile;
    final time = services.time.now();
    final heading = controller.headingLabel;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _Chip(
          text: controller.online ? '在线' : '离线采集',
          color: controller.online ? AppTheme.online : AppTheme.warning,
        ),
        _Chip(text: profile.label, color: AppTheme.accent),
        _Chip(
          text: controller.fix == null ? '定位失败' : '已定位',
          color: controller.fix == null ? AppTheme.danger : AppTheme.online,
        ),
        _Chip(
          text: time.authority == TimeAuthority.ntp ? 'NTP' : '系统时间',
          color: time.authority == TimeAuthority.ntp
              ? AppTheme.online
              : AppTheme.warning,
        ),
        // 朝向：无传感器的设备这里显示"无指南针"，而不是显示 0° 骗人。
        _Chip(
          text: heading ?? '无指南针',
          color: heading == null ? const Color(0xFF4A5560) : const Color(0xFF1F5F8B),
        ),
        _Chip(text: controller.template.name, color: const Color(0xFF4A5560)),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.86),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NoticeStrip extends StatelessWidget {
  const _NoticeStrip({required this.notices});

  final List<String> notices;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final notice in notices)
            Text(
              '· $notice',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

class _GridLines extends StatelessWidget {
  const _GridLines();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GridPainter());
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.28)
      ..strokeWidth = 0.8;
    for (var index = 1; index < 3; index++) {
      final dx = size.width * index / 3;
      final dy = size.height * index / 3;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});

  final CaptureController controller;

  @override
  Widget build(BuildContext context) {
    final camera = controller.camera;
    final maxZoom = camera == null ? 1.0 : controller.maxZoom;
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Column(
        children: [
          Row(
            children: [
              // 没有闪光灯的设备（前置、部分平板）按钮直接置灰，
              // 而不是点了没反应让人以为坏了。
              IconButton(
                tooltip: controller.flashAvailable ? '闪光灯' : '此摄像头无闪光灯',
                onPressed: controller.flashAvailable ? controller.toggleFlash : null,
                icon: Icon(controller.flashOn ? Icons.flash_on : Icons.flash_off),
              ),
              IconButton(
                tooltip: '网格线',
                onPressed: controller.toggleGrid,
                icon: Icon(controller.gridOn ? Icons.grid_on : Icons.grid_off),
              ),
              IconButton(
                tooltip: controller.canSwitchCamera ? '切换摄像头' : '只有一颗摄像头',
                onPressed: controller.canSwitchCamera ? controller.switchCamera : null,
                icon: const Icon(Icons.cameraswitch_outlined),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: maxZoom <= 1.01
                    ? const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Text(
                          '此设备不支持变焦',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      )
                    : Slider(
                        value: controller.zoom.clamp(1.0, maxZoom),
                        min: 1,
                        max: maxZoom,
                        label: '${controller.zoom.toStringAsFixed(1)}x',
                        onChanged: controller.setZoom,
                      ),
              ),
              _VideoButton(controller: controller),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: Text(
              controller.status,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoButton extends StatelessWidget {
  const _VideoButton({required this.controller});

  final CaptureController controller;

  @override
  Widget build(BuildContext context) {
    final recording = controller.recording;
    return IconButton(
      tooltip: recording ? '停止录制' : '录制视频',
      onPressed: () async {
        if (recording) {
          final path = await controller.stopVideo();
          if (context.mounted && path != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('视频已保存：$path')),
            );
          }
        } else {
          await controller.startVideo();
        }
      },
      icon: Icon(
        recording ? Icons.stop_circle : Icons.videocam_outlined,
        color: recording ? AppTheme.danger : null,
      ),
    );
  }
}

/// 预览水印：与出图共用 [LayoutEngine]，并且把排版画在**成片坐标**上，
/// 再按 [FrameFit] 变换到屏幕，因此比例、字号、位置在任何屏幕比例下都一致。
class WatermarkOverlayPainter extends CustomPainter {
  WatermarkOverlayPainter({
    required this.services,
    required this.controller,
    required this.fit,
  });

  final AppServices services;
  final CaptureController controller;
  final FrameFit fit;

  @override
  void paint(Canvas canvas, Size size) {
    final template = controller.template;
    final profile = services.profiles.byId(template.profileId);
    final context = controller.freezeContext();
    final fieldContext = FieldContext(
      mode: profile.mode,
      provenance: Provenance.capture(
        batchId: 'preview',
        at: context.capturedAt,
      ),
      capture: context,
      template: template,
      identity: services.settings.identity,
      weatherAllowed: services.settings.weatherEnabled,
      headingFormat: services.settings.headingFormat,
    );
    final fields = services.fields.resolve(
      fieldContext,
      enabledFieldIds: template.enabledFieldIds,
      allowedFieldIds: profile.allowedFields,
    );
    final layout = services.layout.compute(
      size: fit.photo,
      fields: fields,
      style: template.style,
      badgeText: profile.requireProvenanceBadge
          ? fieldContext.provenance.badgeText
          : null,
      qrData: template.isFieldEnabled(WatermarkFieldIds.qr) ? 'QY|preview' : null,
    );

    canvas.save();
    canvas.translate(fit.rect.left, fit.rect.top);
    canvas.scale(fit.scale);

    final shortSide = layout.canvas.shortSide;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          layout.band.left,
          layout.band.top,
          layout.band.width,
          layout.band.height,
        ),
        Radius.circular(shortSide * layout.style.cornerRadiusRatio),
      ),
      Paint()
        ..color =
            Color(layout.style.bandColor).withOpacity(layout.style.bandOpacity),
    );

    for (final line in layout.lines) {
      final offset = Offset(line.bounds.left, line.bounds.top);
      final textStyle = TextStyle(
        fontSize: line.fontSize,
        fontWeight: line.emphasize ? FontWeight.w700 : FontWeight.w500,
        height: 1.12,
      );
      final strokePainter = TextPainter(
        text: TextSpan(
          text: line.text,
          style: textStyle.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = layout.strokeWidth
              ..strokeJoin = StrokeJoin.round
              ..color = Color(layout.style.strokeColor),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      strokePainter.paint(canvas, offset);
      final fillPainter = TextPainter(
        text: TextSpan(
          text: line.text,
          style: textStyle.copyWith(color: Color(layout.style.color)),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      fillPainter.paint(canvas, offset);
    }

    if (layout.badge != null && layout.badgeText != null) {
      final badge = Rect.fromLTWH(
        layout.badge!.left,
        layout.badge!.top,
        layout.badge!.width,
        layout.badge!.height,
      );
      // 来源标识的配色必须与出图一致：现场绿、导入橙。
      final isCamera = layout.badgeText!.startsWith('现场');
      canvas.drawRRect(
        RRect.fromRectAndRadius(badge, Radius.circular(badge.height * 0.28)),
        Paint()
          ..color = (isCamera ? AppTheme.online : AppTheme.warning)
              .withOpacity(0.92),
      );
      final badgePainter = TextPainter(
        text: TextSpan(
          text: layout.badgeText,
          style: TextStyle(
            color: Colors.white,
            fontSize: badge.height * 0.58,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      badgePainter.paint(
        canvas,
        Offset(
          badge.left + (badge.width - badgePainter.width) / 2,
          badge.top + (badge.height - badgePainter.height) / 2,
        ),
      );
    }

    // 二维码：预览里只画占位块（真实码形由出图阶段渲染）。
    // 预览是每帧重绘的，这里不跑 QrCode 矩阵计算，避免低端机预览掉帧。
    final qr = layout.qrRect;
    if (qr != null) {
      final rect = Rect.fromLTWH(qr.left, qr.top, qr.width, qr.height);
      canvas.drawRect(rect, Paint()..color = Colors.white);
      canvas.drawRect(
        rect.deflate(rect.width * 0.12),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rect.width * 0.02
          ..color = Colors.black.withOpacity(0.18),
      );
      final label = TextPainter(
        text: TextSpan(
          text: 'QR',
          style: TextStyle(
            color: Colors.black.withOpacity(0.35),
            fontSize: rect.height * 0.22,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(
          rect.left + (rect.width - label.width) / 2,
          rect.top + (rect.height - label.height) / 2,
        ),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant WatermarkOverlayPainter oldDelegate) => true;
}
