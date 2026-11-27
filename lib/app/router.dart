import 'package:flutter/material.dart';

import 'feature_registry.dart';

/// 路由名常量。模块新增页面时只用自己的路由名，不改这里。
class AppRoutes {
  const AppRoutes._();

  static const String home = '/';
  static const String template = '/template';
  static const String import = '/import';
  static const String gallery = '/gallery';
  static const String photoDetail = '/gallery/detail';
  static const String verify = '/verify';
  static const String ledger = '/ledger';
  static const String settings = '/settings';
}

/// 路由器：完全由注册表驱动，新增页面无需修改本文件。
class AppRouter {
  AppRouter(this.registry);

  final FeatureRegistry registry;

  Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    for (final spec in registry.routes) {
      if (spec.name == settings.name) {
        return MaterialPageRoute(
          builder: spec.builder,
          settings: settings,
        );
      }
    }
    return MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('页面不存在')),
        body: Center(
          child: Text('未注册的路由：${settings.name}'),
        ),
      ),
      settings: settings,
    );
  }
}
