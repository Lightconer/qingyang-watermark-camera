import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/router.dart';
import '../../app/services.dart';
import '../../core/extensions/watermark_field_provider.dart';
import '../../core/models/template.dart';
import '../../core/models/types.dart';

/// 设置页：字段、模板、API Key、输出路径、台账、功能模块集中在这里。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final services = ServicesScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _sectionTitle(context, '采集身份'),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('采集人'),
                  subtitle: Text(services.settings.identity.operatorName.isEmpty
                      ? '未填写'
                      : services.settings.identity.operatorName),
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: () => _editIdentity(context, services, _IdentityField.operator),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('所属单位'),
                  subtitle: Text(services.settings.identity.organization.isEmpty
                      ? '未填写'
                      : services.settings.identity.organization),
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: () => _editIdentity(context, services, _IdentityField.organization),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('项目名称'),
                  subtitle: Text(services.settings.identity.projectName.isEmpty
                      ? '未填写'
                      : services.settings.identity.projectName),
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: () => _editIdentity(context, services, _IdentityField.project),
                ),
              ],
            ),
          ),
          _sectionTitle(context, '模板与字段'),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('水印模板'),
                  subtitle: Text(services.templates.summary),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pushNamed(AppRoutes.template),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('字段池'),
                  subtitle: const Text('逐项开关；关闭后该字段不进入水印'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openFieldPool(context, services),
                ),
              ],
            ),
          ),
          _sectionTitle(context, '网络与隐私'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: services.settings.ntpEnabled,
                  onChanged: (value) async {
                    await services.settings.setNtpEnabled(value);
                    if (!value) services.time.reset();
                  },
                  title: const Text('NTP 授时'),
                  subtitle: const Text('关闭后使用本地系统时间，画面会标注「本地系统时间」'),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: services.settings.geocodeEnabled,
                  onChanged: services.settings.setGeocodeEnabled,
                  title: const Text('逆地理编码'),
                  subtitle: Text('当前：${services.geocoding.providerLabel}；关闭后不显示地址'),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: services.settings.weatherEnabled,
                  onChanged: services.settings.setWeatherEnabled,
                  title: const Text('天气'),
                  subtitle: const Text('导入模式默认不显示天气'),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: services.settings.cloudBackupEnabled,
                  onChanged: services.settings.setCloudBackupEnabled,
                  title: const Text('云备份（默认关闭）'),
                  subtitle: const Text('本应用不强制云端；开启后仅作为后续版本可选能力预留'),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('高德 Key（可选）'),
                  subtitle: Text(services.settings.amapKey.isEmpty
                      ? '未配置，使用 OpenStreetMap 免 Key 接口'
                      : '已配置'),
                  trailing: const Icon(Icons.key_outlined, size: 18),
                  onTap: () => _editText(
                    context,
                    title: '高德地图 Key',
                    initial: services.settings.amapKey,
                    onSubmit: (value) async {
                      await services.settings.setAmapKey(value);
                      await services.settings.setGeocodeProvider(
                          value.trim().isEmpty ? 'nominatim' : 'amap');
                    },
                  ),
                ),
              ],
            ),
          ),
          _sectionTitle(context, '输出与存储'),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('JPEG 质量'),
                  subtitle: Slider(
                    value: services.settings.jpegQuality.toDouble(),
                    min: 60,
                    max: 100,
                    divisions: 8,
                    label: '${services.settings.jpegQuality}',
                    onChanged: (value) =>
                        services.settings.setJpegQuality(value.round()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('长边上限'),
                  subtitle: Text('${services.settings.maxLongSide} px（超出则降采样，防 OOM）'),
                  trailing: DropdownButton<int>(
                    value: services.settings.maxLongSide,
                    items: const [
                      DropdownMenuItem(value: 2048, child: Text('2048')),
                      DropdownMenuItem(value: 4096, child: Text('4096')),
                      DropdownMenuItem(value: 6144, child: Text('6144')),
                    ],
                    onChanged: (value) {
                      if (value != null) services.settings.setMaxLongSide(value);
                    },
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: services.settings.saveOriginal,
                  onChanged: services.settings.setSaveOriginal,
                  title: const Text('同时保存原图'),
                  subtitle: const Text('原图放在 original/ 目录，成品另存为原名_wm'),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('成品目录'),
                  subtitle: const Text('应用私有外部目录 / QingyangWatermark / 日期 / import|camera'),
                  trailing: const Icon(Icons.folder_outlined, size: 18),
                  onTap: () async {
                    final root = await services.storage.root();
                    if (!context.mounted) return;
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('成品目录'),
                        content: SelectableText(root.path),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          _sectionTitle(context, '台账与校验'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: services.settings.ledgerIncludeOriginal,
                  onChanged: services.settings.setLedgerIncludeOriginal,
                  title: const Text('台账包含内容指纹'),
                  subtitle: const Text('导出 XLSX 时附带逐张内容指纹列'),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('导出/查看台账'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pushNamed(AppRoutes.ledger),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('图片校验工具'),
                  subtitle: const Text('比对像素哈希与 EXIF/XMP 戳记'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pushNamed(AppRoutes.verify),
                ),
              ],
            ),
          ),
          _sectionTitle(context, '权限'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.my_location, size: 18),
                  title: const Text('精确定位'),
                  subtitle: const Text('用于快门瞬间冻结坐标（拒绝后水印标注定位失败）'),
                  onTap: () => Permission.locationWhenInUse.request(),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined, size: 18),
                  title: const Text('相机'),
                  onTap: () => Permission.camera.request(),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined, size: 18),
                  title: const Text('相册 / 存储'),
                  subtitle: const Text('Android 13+ 使用系统 Photo Picker，无需媒体权限'),
                  onTap: () => Permission.photos.request(),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.settings_outlined, size: 18),
                  title: const Text('打开系统应用设置'),
                  onTap: () => openAppSettings(),
                ),
              ],
            ),
          ),
          _sectionTitle(context, '功能模块'),
          Card(
            child: Column(
              children: [
                for (final module in services.registry.modules)
                  SwitchListTile(
                    value: services.registry.isEnabled(module.id),
                    onChanged: (value) async {
                      await services.registry.setEnabled(module.id, value);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${module.id} 已${value ? '启用' : '停用'}，重启后完全生效')),
                        );
                      }
                    },
                    title: Text(module.id),
                    subtitle: Text(module.routes.map((route) => route.name).join(' · ')),
                  ),
              ],
            ),
          ),
          for (final section in services.registry.settingsSections) ...[
            _sectionTitle(context, section.title),
            Card(child: section.builder(context)),
          ],
          _sectionTitle(context, '关于'),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text(AppIdentity.appName),
                  subtitle: Text('包名 ${AppIdentity.packageName}'),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('装配状态'),
                  subtitle: Text(services.registry.summary),
                ),
                const Divider(height: 1),
                const ListTile(
                  title: Text('硬性约束'),
                  subtitle: Text(
                    '无手动输入时间/经纬度入口；水印绘制在像素层并双写 EXIF/XMP；'
                    '离线/在线、拍摄/导入在画面上明确区分；无广告、无付费弹窗。',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Future<void> _editIdentity(
    BuildContext context,
    AppServices services,
    _IdentityField field,
  ) async {
    final identity = services.settings.identity;
    final initial = switch (field) {
      _IdentityField.operator => identity.operatorName,
      _IdentityField.organization => identity.organization,
      _IdentityField.project => identity.projectName,
    };
    await _editText(
      context,
      title: switch (field) {
        _IdentityField.operator => '采集人',
        _IdentityField.organization => '所属单位',
        _IdentityField.project => '项目名称',
      },
      initial: initial,
      onSubmit: (value) async {
        await services.settings.setIdentity(
          switch (field) {
            _IdentityField.operator => identity.copyWith(operatorName: value),
            _IdentityField.organization => identity.copyWith(organization: value),
            _IdentityField.project => identity.copyWith(projectName: value),
          },
        );
      },
    );
  }

  Future<void> _editText(
    BuildContext context, {
    required String title,
    required String initial,
    required Future<void> Function(String value) onSubmit,
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '留空表示不显示'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value != null) await onSubmit(value);
  }

  Future<void> _openFieldPool(BuildContext context, AppServices services) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          final items = services.fields.uiItems;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('字段池', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: Text(
                      '这里设置新建模板时的默认开关；单套模板可在模板编辑器里单独调整。',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final item in items)
                          SwitchListTile(
                            dense: true,
                            value: services.settings
                                .fieldDefaults[item.id] ?? false,
                            title: Text('${item.label}（${item.id}）'),
                            subtitle: Text(item.group),
                            onChanged: (value) async {
                              await services.settings.setFieldDefault(item.id, value);
                              setState(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }
}

enum _IdentityField { operator, organization, project }

/// 供模板页复用的字段标签查询。
String fieldLabel(AppServices services, String id) {
  for (final item in services.fields.uiItems) {
    if (item.id == id) return item.label;
  }
  return id;
}

/// 便捷：判断某字段是否属于"样式级元素"（二维码/LOGO 不进入文字行）。
bool isStyleLevelField(String id) =>
    id == WatermarkFieldIds.qr || id == WatermarkFieldIds.logo;
