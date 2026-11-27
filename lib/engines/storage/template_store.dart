import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/models/profile_config.dart';
import '../../core/models/template.dart';
import '../../core/models/types.dart';
import 'settings_store.dart';

/// 模式仓库：从 assets/profiles/ 加载 JSON。新增模式 = 新增一个 JSON + 在 index.json 里登记。
class ProfileRepository {
  const ProfileRepository._();

  static const String indexAsset = 'assets/profiles/index.json';

  static Future<ProfileRegistry> load({AssetBundle? bundle}) async {
    final assets = bundle ?? rootBundle;
    final configs = <ProfileConfig>[];
    try {
      final indexText = await assets.loadString(indexAsset);
      final index = jsonDecode(indexText);
      final paths = <String>[];
      if (index is Map && index['profiles'] is List) {
        for (final item in index['profiles'] as List) {
          if (item is String) paths.add(item);
        }
      }
      for (final path in paths) {
        try {
          final text = await assets.loadString(path);
          final json = jsonDecode(text);
          if (json is Map<String, dynamic>) {
            final config = ProfileConfig.fromJson(json);
            if (config != null) configs.add(config);
          }
        } catch (_) {
          continue;
        }
      }
    } catch (_) {
      // 资源缺失时使用兜底模式，应用仍可启动。
    }
    if (!configs.any((config) => config.id == ProfileConfig.fallback.id)) {
      configs.add(ProfileConfig.fallback);
    }
    return ProfileRegistry(configs);
  }
}

/// 模板仓库：内置模板来自 assets，用户模板存 SharedPreferences，均以 JSON 表达。
class TemplateStore extends ChangeNotifier {
  TemplateStore({required this.settings});

  static const String templatesAsset = 'assets/templates/default.json';

  final SettingsStore settings;
  final List<TemplateConfig> _builtin = [];
  final List<TemplateConfig> _user = [];

  List<TemplateConfig> get templates => [..._builtin, ..._user];

  List<TemplateConfig> get builtinTemplates => List.unmodifiable(_builtin);

  List<TemplateConfig> get userTemplates => List.unmodifiable(_user);

  TemplateConfig byId(String id) {
    for (final template in templates) {
      if (template.id == id) return template;
    }
    return active;
  }

  TemplateConfig get active => byIdOrFallback(settings.activeTemplateId);

  TemplateConfig byIdOrFallback(String id) {
    for (final template in templates) {
      if (template.id == id) return template;
    }
    return _builtin.isNotEmpty ? _builtin.first : _fallbackTemplate();
  }

  Future<void> load({AssetBundle? bundle}) async {
    final assets = bundle ?? rootBundle;
    _builtin.clear();
    _user.clear();
    try {
      final text = await assets.loadString(templatesAsset);
      final json = jsonDecode(text);
      if (json is Map && json['templates'] is List) {
        for (final item in json['templates'] as List) {
          if (item is Map<String, dynamic>) {
            final template = TemplateConfig.fromJson(item);
            if (template != null) {
              _builtin.add(template.copyWith(isBuiltin: true));
            }
          }
        }
      }
    } catch (_) {
      // 忽略：下面会补一个兜底模板
    }
    if (_builtin.isEmpty) _builtin.add(_fallbackTemplate());

    for (final raw in settings.userTemplates) {
      try {
        final json = jsonDecode(raw);
        if (json is Map<String, dynamic>) {
          final template = TemplateConfig.fromJson(json);
          if (template != null) _user.add(template.copyWith(isBuiltin: false));
        }
      } catch (_) {
        continue;
      }
    }
    notifyListeners();
  }

  Future<void> save(TemplateConfig template) async {
    final index = _user.indexWhere((item) => item.id == template.id);
    final stored = template.copyWith(
      isBuiltin: false,
      updatedAt: DateTime.now(),
    );
    if (index >= 0) {
      _user[index] = stored;
    } else {
      final builtinIndex = _builtin.indexWhere((item) => item.id == template.id);
      if (builtinIndex >= 0) {
        // 内置模板不可覆盖：另存为副本。
        _user.add(stored.copyWith(id: '${template.id}_${DateTime.now().millisecondsSinceEpoch}'));
      } else {
        _user.add(stored);
      }
    }
    await _persistUser();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _user.removeWhere((template) => template.id == id);
    if (settings.activeTemplateId == id) {
      await settings.setActiveTemplateId(_builtin.first.id);
    }
    await _persistUser();
    notifyListeners();
  }

  Future<void> setActive(String id) async {
    await settings.setActiveTemplateId(id);
    notifyListeners();
  }

  Future<void> _persistUser() async {
    await settings.setUserTemplates(
      _user.map((template) => jsonEncode(template.toJson())).toList(growable: false),
    );
  }

  String exportJson(String id) => const JsonEncoder.withIndent('  ')
      .convert(byId(id).toJson());

  /// 导入模板 JSON：兼容单个对象或 `{templates: [...]}` 数组；失败返回 null。
  Future<TemplateConfig?> importJson(String raw) async {
    try {
      final json = jsonDecode(raw);
      final candidates = <Map<String, dynamic>>[];
      if (json is Map<String, dynamic>) {
        if (json['templates'] is List) {
          for (final item in json['templates'] as List) {
            if (item is Map<String, dynamic>) candidates.add(item);
          }
        } else {
          candidates.add(json);
        }
      }
      if (candidates.isEmpty) return null;
      TemplateConfig? first;
      for (final candidate in candidates) {
        final parsed = TemplateConfig.fromJson(candidate);
        if (parsed == null) continue;
        final uniqueId =
            '${parsed.id}_${DateTime.now().millisecondsSinceEpoch}';
        final copy = parsed.copyWith(id: uniqueId, isBuiltin: false, updatedAt: DateTime.now());
        _user.add(copy);
        first ??= copy;
      }
      if (first == null) return null;
      await _persistUser();
      notifyListeners();
      return first;
    } catch (_) {
      return null;
    }
  }

  TemplateConfig _fallbackTemplate() => TemplateConfig(
        id: 'default',
        name: '默认模板',
        profileId: 'forensics',
        style: const WatermarkStyle(),
        enabledFieldIds: {
          WatermarkFieldIds.sourceBadge,
          WatermarkFieldIds.time,
          WatermarkFieldIds.coords,
          WatermarkFieldIds.address,
          WatermarkFieldIds.organization,
          WatermarkFieldIds.operator,
        },
        isBuiltin: true,
      );

  /// 新建（克隆 + 改名）模板。
  TemplateConfig duplicate(TemplateConfig base, String name) {
    return base.copyWith(
      id: 'tpl_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      isBuiltin: false,
      updatedAt: DateTime.now(),
    );
  }

  /// 拍摄页需要的"当前模式 + 模板"组合。
  ({TemplateConfig template, String profileId}) get activePair =>
      (template: active, profileId: active.profileId);

  /// 统计：给设置页显示用。
  String get summary =>
      '内置 ${_builtin.length} 套 · 自定义 ${_user.length} 套 · 当前 ${active.name}（${AppIdentity.appName}）';
}
