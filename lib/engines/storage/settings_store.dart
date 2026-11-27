import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/extensions/watermark_field_provider.dart';
import '../../core/models/template.dart';

/// 设置存储：所有开关、密钥、默认模板、输出路径、台账配置集中在这里。
///
/// 硬性约束：这里没有任何"手动输入时间/经纬度"的配置项。
class SettingsStore extends ChangeNotifier {
  SettingsStore._(this._prefs);

  final SharedPreferences _prefs;

  static Future<SettingsStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsStore._(prefs);
  }

  // ---- 网络能力开关（可全关，完全离线可用） ----
  bool get ntpEnabled => _prefs.getBool('net.ntp') ?? true;
  bool get geocodeEnabled => _prefs.getBool('net.geocode') ?? true;
  bool get weatherEnabled => _prefs.getBool('net.weather') ?? false;
  bool get cloudBackupEnabled => _prefs.getBool('net.backup') ?? false;
  String get geocodeProvider => _prefs.getString('net.geocode.provider') ?? 'nominatim';
  String get amapKey => _prefs.getString('net.amap.key') ?? '';

  Future<void> setNtpEnabled(bool value) => _setBool('net.ntp', value);
  Future<void> setGeocodeEnabled(bool value) => _setBool('net.geocode', value);
  Future<void> setWeatherEnabled(bool value) => _setBool('net.weather', value);
  Future<void> setCloudBackupEnabled(bool value) => _setBool('net.backup', value);

  Future<void> setGeocodeProvider(String value) async {
    await _prefs.setString('net.geocode.provider', value);
    notifyListeners();
  }

  Future<void> setAmapKey(String value) async {
    await _prefs.setString('net.amap.key', value.trim());
    notifyListeners();
  }

  // ---- 拍摄与输出 ----
  int get jpegQuality => _prefs.getInt('output.quality') ?? 92;
  int get maxLongSide => _prefs.getInt('output.maxLongSide') ?? 4096;
  bool get saveOriginal => _prefs.getBool('output.saveOriginal') ?? false;
  String get captureModeId => _prefs.getString('output.profile') ?? 'forensics';

  Future<void> setJpegQuality(int value) async {
    await _prefs.setInt('output.quality', value.clamp(60, 100));
    notifyListeners();
  }

  Future<void> setMaxLongSide(int value) async {
    await _prefs.setInt('output.maxLongSide', value.clamp(1024, 8192));
    notifyListeners();
  }

  Future<void> setSaveOriginal(bool value) => _setBool('output.saveOriginal', value);

  Future<void> setCaptureModeId(String value) async {
    await _prefs.setString('output.profile', value);
    notifyListeners();
  }

  // ---- 模板 ----
  String get activeTemplateId => _prefs.getString('template.active') ?? 'default';
  Future<void> setActiveTemplateId(String id) async {
    await _prefs.setString('template.active', id);
    notifyListeners();
  }

  List<String> get userTemplates => _prefs.getStringList('template.user') ?? const [];

  Future<void> setUserTemplates(List<String> jsonList) async {
    await _prefs.setStringList('template.user', jsonList);
    notifyListeners();
  }

  // ---- 身份信息 ----
  IdentityInfo get identity => IdentityInfo(
        operatorName: _prefs.getString('identity.operator') ?? '',
        organization: _prefs.getString('identity.organization') ?? '',
        projectName: _prefs.getString('identity.project') ?? '',
        note: _prefs.getString('identity.note') ?? '',
      );

  Future<void> setIdentity(IdentityInfo identity) async {
    await _prefs.setString('identity.operator', identity.operatorName);
    await _prefs.setString('identity.organization', identity.organization);
    await _prefs.setString('identity.project', identity.projectName);
    await _prefs.setString('identity.note', identity.note);
    notifyListeners();
  }

  // ---- 台账 ----
  bool get ledgerIncludeOriginal => _prefs.getBool('ledger.includeOriginal') ?? true;
  Future<void> setLedgerIncludeOriginal(bool value) =>
      _setBool('ledger.includeOriginal', value);

  // ---- 主题 ----
  bool get darkTheme => _prefs.getBool('ui.dark') ?? true;
  Future<void> setDarkTheme(bool value) => _setBool('ui.dark', value);

  // ---- 首次运行 ----
  bool get onboardingDone => _prefs.getBool('ui.onboarding') ?? false;
  Future<void> setOnboardingDone() => _setBool('ui.onboarding', true);

  /// 上一次拍照使用的模板（单张换模板后记住选择）。
  String get lastTemplateId => _prefs.getString('template.last') ?? activeTemplateId;
  Future<void> setLastTemplateId(String id) async {
    await _prefs.setString('template.last', id);
  }

  /// 批量导入时是否统一套用当前模板。
  bool get importUseUniformTemplate => _prefs.getBool('import.uniform') ?? true;
  Future<void> setImportUseUniformTemplate(bool value) =>
      _setBool('import.uniform', value);

  /// 导入模式是否显示天气（默认不显示）。
  bool get importShowWeather => _prefs.getBool('import.weather') ?? false;
  Future<void> setImportShowWeather(bool value) => _setBool('import.weather', value);

  /// 字段池默认开关（新建模板时使用）。
  Map<String, bool> get fieldDefaults {
    final result = <String, bool>{};
    for (final id in WatermarkFieldIds.all) {
      result[id] = _prefs.getBool('field.$id') ?? true;
    }
    result[WatermarkFieldIds.qr] = _prefs.getBool('field.${WatermarkFieldIds.qr}') ?? false;
    return result;
  }

  Future<void> setFieldDefault(String id, bool value) async {
    await _prefs.setBool('field.$id', value);
    notifyListeners();
  }

  // ---- 功能模块开关 ----
  bool isFeatureEnabled(String id, bool defaultValue) =>
      _prefs.getBool('feature.$id') ?? defaultValue;

  Future<void> setFeatureEnabled(String id, bool value) =>
      _setBool('feature.$id', value);

  Future<void> _setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
    notifyListeners();
  }

  /// 便捷：当前采集人姓名。
  String get operatorName => identity.operatorName;
}
