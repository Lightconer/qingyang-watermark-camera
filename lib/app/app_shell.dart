import 'package:flutter/material.dart';

import '../features/capture/capture_controller.dart';
import '../features/capture/capture_page.dart';
import '../features/gallery/gallery_page.dart';
import 'router.dart';
import 'services.dart';
import 'theme.dart';

/// 应用外壳：主页以相机预览为主，底部三按钮（模板 / 快门 / 相册）。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final GlobalKey<CapturePageState> _captureKey = GlobalKey<CapturePageState>();
  CaptureController? _controller;
  int _tab = 0;
  bool _updateCheckScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final services = ServicesScope.of(context);
    _controller = CaptureController(services: services);
    _controller!.initialize();
    _scheduleUpdateCheck(services);
  }

  /// 冷启动检查更新：仅在开启「自动检查更新」且距上次检查超过 24 小时时发一次请求，
  /// 结果只做一条可关闭的提示，不打断拍摄——外勤点开 APP 是为了拍照，不是等更新。
  void _scheduleUpdateCheck(AppServices services) {
    if (_updateCheckScheduled) return;
    _updateCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final result = await services.update.checkIfDue();
      if (!mounted || result == null || !result.hasUpdate) return;
      final release = result.release;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('发现新版本 v${release?.version}（当前 ${result.currentVersion}）'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: '去更新',
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.settings),
        ),
      ));
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _tab,
            children: [
              CapturePage(key: _captureKey, controller: controller),
              GalleryPage(
                onOpenImport: () => Navigator.of(context).pushNamed(AppRoutes.import),
              ),
            ],
          ),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: IconButton(
                tooltip: '设置',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withOpacity(0.35),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(context).pushNamed(AppRoutes.settings),
                icon: const Icon(Icons.settings_outlined, size: 20),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        tab: _tab,
        busy: controller.busy || controller.recording,
        onTemplate: () => Navigator.of(context).pushNamed(AppRoutes.template),
        onShutter: () async {
          if (_tab != 0) {
            setState(() => _tab = 0);
            return;
          }
          await _captureKey.currentState?.shoot();
        },
        onGallery: () => setState(() => _tab = _tab == 1 ? 0 : 1),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.tab,
    required this.busy,
    required this.onTemplate,
    required this.onShutter,
    required this.onGallery,
  });

  final int tab;
  final bool busy;
  final VoidCallback onTemplate;
  final VoidCallback onShutter;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        height: 74,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.4)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _BarButton(
              icon: Icons.dashboard_customize_outlined,
              label: '模板',
              onTap: onTemplate,
            ),
            _ShutterButton(busy: busy, onTap: onShutter),
            _BarButton(
              icon: Icons.photo_library_outlined,
              label: '相册',
              active: tab == 1,
              onTap: onGallery,
            ),
          ],
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: busy ? AppTheme.warning : Theme.of(context).colorScheme.primary,
            width: 3,
          ),
        ),
        child: Center(
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: busy
                  ? AppTheme.warning.withOpacity(0.4)
                  : Theme.of(context).colorScheme.primary,
            ),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.camera_alt, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}
