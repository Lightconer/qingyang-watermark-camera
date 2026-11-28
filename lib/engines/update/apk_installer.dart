import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/policy/checksum_file.dart';
import 'update_engine.dart';

enum ApkInstallStatus {
  /// 已把安装会话交给系统，用户确认后完成安装。
  started,

  /// 当前平台不支持（桌面/测试环境）。
  unsupported,

  /// 下载完成但哈希与发布清单不符——直接删掉，绝不安装。
  checksumMismatch,

  /// 网络/写文件失败。
  downloadFailed,

  /// 交给系统安装时失败（权限被拒、安装包损坏等）。
  installFailed,
}

class ApkInstallResult {
  const ApkInstallResult(this.status, this.message, {this.localPath});

  const ApkInstallResult.unsupported()
      : this(ApkInstallStatus.unsupported, '当前平台不支持就地安装 APK');

  final ApkInstallStatus status;
  final String message;
  final String? localPath;

  bool get ok => status == ApkInstallStatus.started;
}

/// APK 安装引擎：下载 → 校验 → 交给系统安装器。
///
/// 为什么自己下载而不是直接丢给系统下载器：
/// 发布清单里带 `SHA256SUMS.txt`，只有自己拿到字节才能核对哈希；
/// 取证工具的更新如果能在传输中被换包，整套留痕的可信度就没有意义了。
abstract class ApkInstaller {
  /// 系统里真实的 versionName（PackageManager）；拿不到时返回 null。
  Future<String?> currentVersion();

  /// 本机支持的 ABI（`Build.SUPPORTED_ABIS`，首选在前）。
  ///
  /// 安装包按 ABI 拆包发布，查更新时靠它挑对包；拿不到时返回空列表，
  /// 由 [ApkAssetPolicy] 退化为"优先通用包"。
  Future<List<String>> supportedAbis();

  Future<ApkInstallResult> downloadAndInstall(
    UpdateRelease release, {
    String? expectedSha256,
    void Function(int received, int total)? onProgress,
  });

  Future<void> openUrl(String url);
}

class NativeApkInstaller implements ApkInstaller {
  const NativeApkInstaller();

  static const MethodChannel _updateChannel =
      MethodChannel('com.qingyang.watermark/update');
  static const MethodChannel _deviceChannel =
      MethodChannel('com.qingyang.watermark/device');

  static const String _userAgent = 'QingyangWatermarkCamera';

  @override
  Future<String?> currentVersion() async {
    try {
      final value = await _deviceChannel.invokeMethod<String>('version');
      if (value == null || value.trim().isEmpty) return null;
      return value.trim();
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<String>> supportedAbis() async {
    try {
      final value = await _deviceChannel.invokeMethod<List<dynamic>>('abis');
      if (value == null) return const [];
      return value
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      // 老版本宿主没有这个通道：交给策略退化为"优先通用包"。
      return const [];
    }
  }

  @override
  Future<void> openUrl(String url) async {
    try {
      await _updateChannel.invokeMethod<void>('openUrl', {'url': url});
    } on MissingPluginException {
      // 桌面/测试环境没有原生实现：静默失败，由调用方提示
    } on PlatformException {
      // 没有浏览器可用等情况
    }
  }

  @override
  Future<ApkInstallResult> downloadAndInstall(
    UpdateRelease release, {
    String? expectedSha256,
    void Function(int received, int total)? onProgress,
  }) async {
    if (!Platform.isAndroid) return const ApkInstallResult.unsupported();
    if (release.apkUrl.isEmpty) {
      return const ApkInstallResult(ApkInstallStatus.downloadFailed, '安装包地址为空');
    }

    Directory dir;
    try {
      dir = await getTemporaryDirectory();
    } catch (_) {
      dir = Directory.systemTemp;
    }
    final target = File(p.join(dir.path, 'qingyang_update.apk'));

    HttpClient? client;
    try {
      if (await target.exists()) await target.delete();

      client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(Uri.parse(release.apkUrl));
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      final response = await request.close();
      if (response.statusCode != 200) {
        return ApkInstallResult(
          ApkInstallStatus.downloadFailed,
          '下载失败：HTTP ${response.statusCode}',
        );
      }

      final total = response.contentLength > 0
          ? response.contentLength
          : release.apkSizeBytes;
      var received = 0;
      final sink = target.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      // 长度对不上就是下载被截断——这种包交给安装器，用户看到的
      // 一定是「解析包时出现问题」。在这里拦下，说明白原因。
      if (total > 0 && received != total) {
        await target.delete();
        return ApkInstallResult(
          ApkInstallStatus.downloadFailed,
          '下载不完整（$received/$total 字节），已删除，请检查网络后重试',
        );
      }

      if (expectedSha256 != null && expectedSha256.isNotEmpty) {
        final actual = await _sha256OfFile(target);
        if (!ChecksumFile.matches(expectedSha256, actual)) {
          await target.delete();
          return const ApkInstallResult(
            ApkInstallStatus.checksumMismatch,
            '安装包校验失败：哈希与发布清单不一致，已丢弃',
          );
        }
      }

      // 装之前的最后一道：让系统自己去解析这个包。
      // 解析不了就别交给安装器——否则弹出来的是「解析包时出现问题」，
      // 用户除了重新下载没有任何线索。
      final parsable = await _canParse(target.path);
      if (parsable == false) {
        await target.delete();
        return const ApkInstallResult(
          ApkInstallStatus.installFailed,
          '安装包无法解析（下载损坏或与本机系统不兼容），已删除。'
          '请重试；若反复失败，到发布页手动下载对应 ABI 的安装包。',
        );
      }

      await _updateChannel.invokeMethod<void>('install', {'path': target.path});
      return ApkInstallResult(
        ApkInstallStatus.started,
        '已交给系统安装器，按提示确认即可',
        localPath: target.path,
      );
    } on PlatformException catch (error) {
      return ApkInstallResult(
        ApkInstallStatus.installFailed,
        error.message ?? '安装失败（${error.code}）',
        localPath: target.path,
      );
    } on SocketException catch (error) {
      return ApkInstallResult(
        ApkInstallStatus.downloadFailed,
        '网络中断：${error.osError?.message ?? error.message}',
      );
    } on FileSystemException catch (error) {
      return ApkInstallResult(
        ApkInstallStatus.downloadFailed,
        '写入临时文件失败：${error.message}',
      );
    } catch (error) {
      return ApkInstallResult(ApkInstallStatus.downloadFailed, '下载失败：$error');
    } finally {
      client?.close(force: true);
    }
  }

  static Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// 让系统解析一次这个 APK。
  ///
  /// 返回 null 表示宿主没有实现该方法（老版本 / 桌面），此时跳过预检，
  /// 保持旧行为；返回 false 才是"确实解析不了"。
  static Future<bool?> _canParse(String path) async {
    try {
      final info = await _updateChannel
          .invokeMapMethod<String, dynamic>('inspect', {'path': path});
      return info != null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }
}

/// 测试替身：不联网、不落地。
class FakeApkInstaller implements ApkInstaller {
  FakeApkInstaller({
    this.version = '1.1.0',
    this.status = ApkInstallStatus.started,
    this.message = '已交给系统安装器',
  });

  String? version;
  List<String> abis = const ['arm64-v8a', 'armeabi-v7a'];
  ApkInstallStatus status;
  String message;

  final List<({String apkUrl, String? sha, String name})> installs = [];
  final List<String> openedUrls = [];

  @override
  Future<String?> currentVersion() async => version;

  @override
  Future<List<String>> supportedAbis() async => abis;

  @override
  Future<ApkInstallResult> downloadAndInstall(
    UpdateRelease release, {
    String? expectedSha256,
    void Function(int received, int total)? onProgress,
  }) async {
    installs.add((apkUrl: release.apkUrl, sha: expectedSha256, name: release.apkName));
    onProgress?.call(1, 1);
    return ApkInstallResult(status, message, localPath: '/tmp/${release.apkName}');
  }

  @override
  Future<void> openUrl(String url) async => openedUrls.add(url);
}
