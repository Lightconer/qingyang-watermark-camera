import '../../core/models/types.dart';
import '../../core/policy/checksum_file.dart';
import '../storage/settings_store.dart';
import 'apk_installer.dart';
import 'update_engine.dart';

/// 远程更新的编排层：查更新 → 取清单 → 下载校验 → 交给系统安装器。
///
/// 三条纪律：
/// 1. 关掉「自动检查更新」后，[checkIfDue] 不发任何请求（完全离线可用）；
/// 2. 手动点「检查更新」属于用户明确操作，即使自动检查关着也允许一次；
/// 3. 装之前必须核对 `SHA256SUMS.txt`，没有清单或哈希不符就不装。
class UpdateService {
  UpdateService({
    required this.engine,
    required this.installer,
    required this.settings,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final UpdateEngine engine;
  final ApkInstaller installer;
  final SettingsStore settings;
  final DateTime Function() _clock;

  /// 与 release.yml 发布的仓库一致；分叉部署可在设置里改。
  static const String defaultRepo = AppIdentity.updateRepo;

  /// 自动检查的节流间隔：外勤网络差，没必要每次冷启动都请求一次。
  static const Duration dueInterval = Duration(hours: 24);

  /// 已安装版本：优先取系统 `versionName`，取不到时用编译期常量兜底。
  Future<String> currentVersionLabel() async {
    final native = await installer.currentVersion();
    if (native != null && native.trim().isNotEmpty) return native.trim();
    return AppIdentity.version;
  }

  /// 手动检查（不写节流时间以外的副作用）。
  Future<UpdateCheckResult> checkNow({String? currentVersion}) async {
    late final UpdateCheckResult result;
    try {
      result = await engine.check(
        currentVersion: currentVersion ?? await currentVersionLabel(),
        repo: settings.updateRepo,
      );
    } catch (error) {
      return UpdateCheckResult.failed(currentVersion ?? AppIdentity.version, '$error');
    }
    await settings.setLastUpdateCheck(_clock());
    await settings.setLatestKnownVersion(
      result.hasUpdate ? (result.release?.tag ?? '') : '',
    );
    return result;
  }

  /// 冷启动时调用：开关关闭、或 24 小时内查过，返回 null 表示"什么都不做"。
  Future<UpdateCheckResult?> checkIfDue() async {
    if (!settings.autoCheckUpdate) return null;
    final last = settings.lastUpdateCheckAt;
    if (last != null && _clock().difference(last) < dueInterval) return null;
    return checkNow();
  }

  /// 下载并安装；[onProgress] 用于页面进度条。
  Future<ApkInstallResult> installRelease(
    UpdateRelease release, {
    void Function(int received, int total)? onProgress,
  }) async {
    final expected = await _expectedSha256(release);
    return installer.downloadAndInstall(
      release,
      expectedSha256: expected,
      onProgress: onProgress,
    );
  }

  /// 读取发布清单里这只 APK 的哈希；没有清单返回 null（调用方按"未校验"提示）。
  Future<String?> _expectedSha256(UpdateRelease release) async {
    final url = release.checksumUrl;
    if (url == null || url.isEmpty) return null;
    final text = await engine.fetchText(url);
    return ChecksumFile.lookup(text, release.apkName);
  }

  Future<void> openReleasePage(UpdateRelease release) async {
    if (release.pageUrl.isEmpty) return;
    await installer.openUrl(release.pageUrl);
  }
}
