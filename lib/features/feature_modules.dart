import 'package:flutter/material.dart';

import '../app/feature_module.dart';
import '../app/router.dart';
import '../app/services.dart';
import 'gallery/gallery_page.dart';
import 'import/import_page.dart';
import 'ledger/ledger_page.dart';
import 'settings/settings_page.dart';
import 'template/template_page.dart';
import 'verify/verify_page.dart';

/// 全部功能模块声明。新增业务单元 = 在这里加一个类 + 在 bootstrap 里注册一行。
///
/// 每个模块可以携带：路由、水印字段、图像中间件、设置分区、启动初始化逻辑。

/// 拍摄链路模块。
class CaptureFeature extends FeatureModule {
  @override
  String get id => 'capture';

  @override
  List<RouteSpec> get routes => const [];

  @override
  List<SettingSection> get settings => [
        SettingSection(
          id: 'capture.options',
          title: '拍摄',
          priority: 10,
          builder: (context) => const Column(
            children: [
              ListTile(
                dense: true,
                title: Text('快门冻结'),
                subtitle: Text('时间、坐标、地址、天气在快门瞬间锁定，生成后不可修改'),
              ),
              ListTile(
                dense: true,
                title: Text('视频水印'),
                subtitle: Text('录制时画面叠加水印并写 sidecar；帧级烧录见 README 已知限制'),
              ),
            ],
          ),
        ),
      ];
}

/// 导入链路模块。
class ImportFeature extends FeatureModule {
  @override
  String get id => 'import';

  @override
  List<RouteSpec> get routes => [
        RouteSpec(name: AppRoutes.import, builder: (context) => const ImportPage()),
      ];

  @override
  List<SettingSection> get settings => [
        SettingSection(
          id: 'import.options',
          title: '导入',
          priority: 20,
          builder: (context) => _ImportSettings(),
        ),
      ];
}

class _ImportSettings extends StatelessWidget {
  const _ImportSettings();

  @override
  Widget build(BuildContext context) {
    final services = ServicesScope.of(context);
    return Column(
      children: [
        SwitchListTile(
          value: services.settings.importUseUniformTemplate,
          onChanged: services.settings.setImportUseUniformTemplate,
          title: const Text('批量统一模板'),
          subtitle: const Text('关闭后每张默认沿用当前模板，可在预览网格里单张切换'),
        ),
        SwitchListTile(
          value: services.settings.importShowWeather,
          onChanged: services.settings.setImportShowWeather,
          title: const Text('导入图显示天气'),
          subtitle: const Text('默认关闭：导入图不编造拍摄当时的天气'),
        ),
      ],
    );
  }
}

/// 模板模块。
class TemplateFeature extends FeatureModule {
  @override
  String get id => 'template';

  @override
  List<RouteSpec> get routes => [
        RouteSpec(name: AppRoutes.template, builder: (context) => const TemplatePage()),
      ];
}

/// 相册模块。
class GalleryFeature extends FeatureModule {
  @override
  String get id => 'gallery';

  @override
  List<RouteSpec> get routes => [
        RouteSpec(
          name: AppRoutes.gallery,
          builder: (context) => GalleryPage(
            onOpenImport: () => Navigator.of(context).pushNamed(AppRoutes.import),
          ),
        ),
      ];
}

/// 校验模块。
class VerifyFeature extends FeatureModule {
  @override
  String get id => 'verify';

  @override
  List<RouteSpec> get routes => [
        RouteSpec(name: AppRoutes.verify, builder: (context) => const VerifyPage()),
      ];
}

/// 台账模块。
class LedgerFeature extends FeatureModule {
  @override
  String get id => 'ledger';

  @override
  List<RouteSpec> get routes => [
        RouteSpec(name: AppRoutes.ledger, builder: (context) => const LedgerPage()),
      ];
}

/// 设置模块。
class SettingsFeature extends FeatureModule {
  @override
  String get id => 'settings';

  @override
  List<RouteSpec> get routes => [
        RouteSpec(name: AppRoutes.settings, builder: (context) => const SettingsPage()),
      ];
}
