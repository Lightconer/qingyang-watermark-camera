import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'router.dart';
import 'services.dart';
import 'theme.dart';

/// 应用根节点：注入服务 → 主题 → 路由 → 外壳。
class QingyangApp extends StatelessWidget {
  const QingyangApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final router = AppRouter(services.registry);
    return ServicesScope(
      services: services,
      child: AnimatedBuilder(
        animation: services.settings,
        builder: (context, _) {
          return MaterialApp(
            title: '青阳水印相机',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode:
                services.settings.darkTheme ? ThemeMode.dark : ThemeMode.light,
            onGenerateRoute: router.onGenerateRoute,
            home: const AppShell(),
            builder: (context, child) {
              // 统一字体缩放上限，避免水印预览与出图比例被系统字号打乱。
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  textScaler: TextScaler.linear(
                    media.textScaler.scale(1).clamp(0.9, 1.15),
                  ),
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
          );
        },
      ),
    );
  }
}
