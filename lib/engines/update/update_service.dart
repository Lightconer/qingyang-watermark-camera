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
    // 设备 ABI 决定挑哪只包：arm64 / armeabi-v7a 拆包发布后，
    // 这一步漏了就会给 32 位机器推 arm64 包。
    final abis = await installer.supportedAbis();
    late final UpdateCheckResult result;
    try {
      result = await engine.check(
        currentVersion: currentVersion ?? await currentVersionLabel(),
        repo: settings.updateRepo,
        deviceAbis: abis,
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
  ///
  /// 清单必须能取到、且必须能查到这只包的哈希才继续：
  /// 「查不到就跳过校验」等于把安全校验做成了可选项。
  Future<ApkInstallResult> installRelease(
    UpdateRelease release, {
    void Function(int received, int total)? onProgress,
  }) async {
    final url = release.checksumUrl;
    String? expected;
    if (url != null && url.isNotEmpty) {
      final text = await engine.fetchText(url);
      if (text == null) {
        return const ApkInstallResult(
          ApkInstallStatus.downloadFailed,
          '取不到校验清单（SHA256SUMS.txt），已停止安装。'
          '可到发布页手动下载，那里同样带校验清单。',
        );
      }
      expected = ChecksumFile.lookup(text, release.apkName);
      if (expected == null) {
        return const ApkInstallResult(
          ApkInstallStatus.checksumMismatch,
          '发布清单里没有这只安装包的哈希，已拒绝安装',
        );
      }
    }
    return installer.downloadAndInstall(
      release,
      expectedSha256: expected,
      onProgress: onProgress,
    );
  }

  Future<void> openReleasePage(UpdateRelease release) async {
    if (release.pageUrl.isEmpty) return;
    await installer.openUrl(release.pageUrl);
  }
}
