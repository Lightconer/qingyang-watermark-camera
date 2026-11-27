import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/extensions/watermark_field_provider.dart';
import '../../core/layout/layout_engine.dart';
import '../../core/models/template.dart';
import '../../core/models/types.dart';
import 'capture_controller.dart';

/// 拍摄页：预览为主，水印以「与出图同规则」的方式实时叠加。
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
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text(path == null ? controller.status : '已保存：${controller.status}'),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final camera = controller.camera;
        final ready = camera != null && camera.value.isInitialized;
        return Column(
          children: [
            Expanded(
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (ready)
                      Center(child: CameraPreview(camera))
                    else
                      _Placeholder(
                        initializing: controller.initializing,
                        error: controller.error,
                        onRetry: controller.initialize,
                      ),
                    if (ready)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: WatermarkOverlayPainter(
                            services: ServicesScope.of(context),
                            controller: controller,
                          ),
                        ),
                      ),
                    if (controller.gridOn && ready)
                      const Positioned.fill(child: IgnorePointer(child: _GridLines())),
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
                        child: _NoticeStrip(notices: controller.notices),
                      ),
                  ],
                ),
              ),
            ),
            _Controls(controller: controller),
          ],
        );
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.initializing,
    required this.error,
    required this.onRetry,
  });

  final bool initializing;
  final String? error;
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '闪光灯',
                onPressed: controller.toggleFlash,
                icon: Icon(controller.flashOn ? Icons.flash_on : Icons.flash_off),
              ),
              IconButton(
                tooltip: '网格线',
                onPressed: controller.toggleGrid,
                icon: Icon(controller.gridOn ? Icons.grid_on : Icons.grid_off),
              ),
              IconButton(
                tooltip: '切换摄像头',
                onPressed: controller.switchCamera,
                icon: const Icon(Icons.cameraswitch_outlined),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: controller.zoom.clamp(1.0, maxZoom),
                  min: 1,
                  max: maxZoom <= 1 ? 1.0001 : maxZoom,
                  divisions: maxZoom <= 1 ? null : 8,
                  label: '${controller.zoom.toStringAsFixed(1)}x',
                  onChanged: maxZoom <= 1 ? null : controller.setZoom,
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

/// 预览水印：与出图共用 [LayoutEngine]，因此比例、字号、位置一致。
class WatermarkOverlayPainter extends CustomPainter {
  WatermarkOverlayPainter({required this.services, required this.controller});

  final AppServices services;
  final CaptureController controller;

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
    );
    final fields = services.fields.resolve(
      fieldContext,
      enabledFieldIds: template.enabledFieldIds,
      allowedFieldIds: profile.allowedFields,
    );
    final layout = services.layout.compute(
      size: LayoutSize(size.width, size.height),
      fields: fields,
      style: template.style,
      badgeText: profile.requireProvenanceBadge ? '现场拍摄' : null,
      qrData: template.isFieldEnabled(WatermarkFieldIds.qr) ? 'QY|preview' : null,
    );

    final style = layout.style;
    final bandRect = Rect.fromLTWH(
      layout.band.left,
      layout.band.top,
      layout.band.width,
      layout.band.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bandRect,
        Radius.circular(size.shortestSide * style.cornerRadiusRatio),
      ),
      Paint()..color = Color(style.bandColor).withOpacity(style.bandOpacity),
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
              ..color = Color(style.strokeColor),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      strokePainter.paint(canvas, offset);
      final fillPainter = TextPainter(
        text: TextSpan(
          text: line.text,
          style: textStyle.copyWith(color: Color(style.color)),
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
      canvas.drawRRect(
        RRect.fromRectAndRadius(badge, Radius.circular(badge.height * 0.28)),
        Paint()..color = AppTheme.online.withOpacity(0.92),
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
      )..layout();
      badgePainter.paint(
        canvas,
        Offset(
          badge.left + (badge.width - badgePainter.width) / 2,
          badge.top + (badge.height - badgePainter.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant WatermarkOverlayPainter oldDelegate) => true;
}
