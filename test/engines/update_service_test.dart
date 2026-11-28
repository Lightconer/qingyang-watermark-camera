import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingyang_watermark/core/models/types.dart';
import 'package:qingyang_watermark/core/policy/version.dart';
import 'package:qingyang_watermark/engines/storage/settings_store.dart';
import 'package:qingyang_watermark/engines/update/apk_installer.dart';
import 'package:qingyang_watermark/engines/update/update_engine.dart';
import 'package:qingyang_watermark/engines/update/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _apkSha = 'c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2'
    'c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2';

Map<String, dynamic> _releaseJson({
  String tag = 'v1.2.0',
  bool withApk = true,
  bool withChecksums = true,
}) =>
    {
      'tag_name': tag,
      'name': '青阳水印相机 $tag',
      'body': '- 支持远程更新\n- 修复若干问题',
      'html_url': 'https://github.com/Lightconer/qingyang-watermark-camera/releases/tag/$tag',
      'published_at': '2026-11-28T01:00:00Z',
      'assets': [
        if (withApk)
          {
            'name': 'qingyang-watermark-v1.2.0.apk',
            'size': 56518246,
            'browser_download_url':
                'https://github.com/x/y/releases/download/$tag/qingyang-watermark-v1.2.0.apk',
          },
        {
          'name': 'notes.txt',
          'size': 12,
          'browser_download_url': 'https://github.com/x/y/notes.txt',
        },
        if (withChecksums)
          {
            'name': 'SHA256SUMS.txt',
            'size': 90,
            'browser_download_url': 'https://github.com/x/y/SHA256SUMS.txt',
          },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UpdateRelease.fromGitHubJson', () {
    test('挑出 APK 附件与校验清单', () {
      final release = UpdateRelease.fromGitHubJson(_releaseJson())!;
      expect(release.tag, 'v1.2.0');
      expect(release.version, const AppVersion(1, 2, 0));
      expect(release.apkName, 'qingyang-watermark-v1.2.0.apk');
      expect(release.apkSizeBytes, 56518246);
      expect(release.sizeLabel, '53.9 MB');
      expect(release.checksumUrl, contains('SHA256SUMS.txt'));
      expect(release.notes, contains('远程更新'));
      expect(release.publishedAt, isNotNull);
    });

    test('没有 APK 附件时返回 null，不给现场一个打不开的更新入口', () {
      expect(UpdateRelease.fromGitHubJson(_releaseJson(withApk: false)), isNull);
    });

    test('标签无法解析版本时返回 null', () {
      expect(UpdateRelease.fromGitHubJson(_releaseJson(tag: 'nightly')), isNull);
    });

    test('没有校验清单时 checksumUrl 为 null，仍可提示"未校验"', () {
      final release =
          UpdateRelease.fromGitHubJson(_releaseJson(withChecksums: false))!;
      expect(release.checksumUrl, isNull);
    });
  });

  group('GitHubUpdateEngine 的参数校验（不联网）', () {
    final engine = GitHubUpdateEngine();

    test('仓库格式不对直接失败，不发请求', () async {
      final result = await engine.check(currentVersion: '1.1.0', repo: 'not a repo');
      expect(result.status, UpdateStatus.failed);
      expect(result.detail, contains('owner/repo'));
    });

    test('当前版本号无法识别时失败，不会误判成"已是最新"', () async {
      final result = await engine.check(currentVersion: 'dev', repo: 'a/b');
      expect(result.status, UpdateStatus.failed);
      expect(result.detail, contains('无法识别'));
    });
  });

  group('UpdateService', () {
    late SettingsStore settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = await SettingsStore.load();
    });

    UpdateRelease release() => UpdateRelease.fromGitHubJson(_releaseJson())!;

    test('关掉自动检查后 checkIfDue 不发请求', () async {
      await settings.setAutoCheckUpdate(false);
      final engine = FakeUpdateEngine();
      final service = UpdateService(
        engine: engine,
        installer: FakeApkInstaller(),
        settings: settings,
      );

      expect(await service.checkIfDue(), isNull);
      expect(engine.checkCount, 0);
    });

    test('24 小时内不重复检查', () async {
      final now = DateTime(2026, 11, 28, 9);
      await settings.setLastUpdateCheck(now.subtract(const Duration(hours: 3)));
      final engine = FakeUpdateEngine();
      final service = UpdateService(
        engine: engine,
        installer: FakeApkInstaller(),
        settings: settings,
        clock: () => now,
      );

      expect(await service.checkIfDue(), isNull);
      expect(engine.checkCount, 0);
    });

    test('超过 24 小时才真正检查一次，并记录检查时间', () async {
      final now = DateTime(2026, 11, 28, 9);
      await settings.setLastUpdateCheck(now.subtract(const Duration(hours: 30)));
      final engine = FakeUpdateEngine(
        result: UpdateCheckResult(
          status: UpdateStatus.available,
          currentVersion: '1.1.0',
          release: release(),
        ),
      );
      final service = UpdateService(
        engine: engine,
        installer: FakeApkInstaller(version: '1.1.0'),
        settings: settings,
        clock: () => now,
      );

      final result = await service.checkIfDue();
      expect(result?.hasUpdate, isTrue);
      expect(engine.checkCount, 1);
      expect(settings.lastUpdateCheckAt, now);
      expect(settings.latestKnownVersion, 'v1.2.0');
    });

    test('手动检查不受自动开关限制（用户明确操作）', () async {
      await settings.setAutoCheckUpdate(false);
      final engine = FakeUpdateEngine(
        result: UpdateCheckResult.upToDate('1.2.0'),
      );
      final service = UpdateService(
        engine: engine,
        installer: FakeApkInstaller(version: '1.2.0'),
        settings: settings,
      );

      final result = await service.checkNow();
      expect(result.status, UpdateStatus.upToDate);
      expect(engine.checkCount, 1);
    });

    test('已是最新时清空"待更新版本"，避免旧提示残留', () async {
      await settings.setLatestKnownVersion('v1.2.0');
      final service = UpdateService(
        engine: FakeUpdateEngine(result: UpdateCheckResult.upToDate('1.2.0')),
        installer: FakeApkInstaller(version: '1.2.0'),
        settings: settings,
      );

      await service.checkNow();
      expect(settings.latestKnownVersion, isEmpty);
    });

    test('安装时把发布清单里的哈希交给安装器', () async {
      final installer = FakeApkInstaller();
      final engine = FakeUpdateEngine(
        text: '$_apkSha  qingyang-watermark-v1.2.0.apk\n',
      );
      final service = UpdateService(
        engine: engine,
        installer: installer,
        settings: settings,
      );

      final result = await service.installRelease(release());
      expect(result.ok, isTrue);
      expect(installer.installs.single.sha, _apkSha);
      expect(engine.fetchedUrls.single, contains('SHA256SUMS.txt'));
    });

    test('没有校验清单时哈希为 null，由安装器标记"未校验"', () async {
      final installer = FakeApkInstaller();
      final service = UpdateService(
        engine: FakeUpdateEngine(),
        installer: installer,
        settings: settings,
      );

      final releaseWithoutChecksums =
          UpdateRelease.fromGitHubJson(_releaseJson(withChecksums: false))!;
      await service.installRelease(releaseWithoutChecksums);
      expect(installer.installs.single.sha, isNull);
    });

    test('当前版本优先取系统 versionName，取不到才用编译期常量', () async {
      final withNative = UpdateService(
        engine: FakeUpdateEngine(),
        installer: FakeApkInstaller(version: '1.3.7'),
        settings: settings,
      );
      expect(await withNative.currentVersionLabel(), '1.3.7');

      final withoutNative = UpdateService(
        engine: FakeUpdateEngine(),
        installer: FakeApkInstaller(version: null),
        settings: settings,
      );
      expect(await withoutNative.currentVersionLabel(), AppIdentity.version);
    });

    test('引擎抛异常时返回 failed 而不是把异常漏到 UI', () async {
      final service = UpdateService(
        engine: FakeUpdateEngine(throwOnCheck: true),
        installer: FakeApkInstaller(),
        settings: settings,
      );

      final result = await service.checkNow();
      expect(result.status, UpdateStatus.failed);
    });

    test('更新源默认指向本项目仓库，且可被设置覆盖', () async {
      expect(settings.updateRepo, AppIdentity.updateRepo);
      await settings.setUpdateRepo('someone/fork');
      expect(settings.updateRepo, 'someone/fork');
      // 留空回退默认值，避免手滑清空后永远查不到更新
      await settings.setUpdateRepo('   ');
      expect(settings.updateRepo, AppIdentity.updateRepo);
    });
  });

  group('发布 JSON 解析边界', () {
    test('assets 缺失时不崩', () {
      final json = {
        'tag_name': 'v2.0.0',
        'name': 'x',
        'body': '',
        'html_url': '',
        'assets': <dynamic>[],
      };
      expect(UpdateRelease.fromGitHubJson(json), isNull);
    });

    test('body 为 null 时 notes 为空串', () {
      final json = jsonDecode(jsonEncode(_releaseJson())) as Map<String, dynamic>;
      json['body'] = null;
      final release = UpdateRelease.fromGitHubJson(json)!;
      expect(release.notes, isEmpty);
    });
  });
}
