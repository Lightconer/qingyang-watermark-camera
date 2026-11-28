import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/policy/abi_policy.dart';
import '../../core/policy/version.dart';

/// 远端发布的一条记录（当前只认 GitHub Releases）。
class UpdateRelease {
  const UpdateRelease({
    required this.tag,
    required this.version,
    required this.title,
    required this.notes,
    required this.pageUrl,
    required this.apkUrl,
    required this.apkName,
    required this.apkSizeBytes,
    required this.checksumUrl,
    required this.publishedAt,
    this.apkAssetCount = 1,
  });

  final String tag;
  final AppVersion version;
  final String title;
  final String notes;
  final String pageUrl;
  final String apkUrl;
  final String apkName;
  final int apkSizeBytes;

  /// `SHA256SUMS.txt` 的下载地址；发布未附带时为 null。
  final String? checksumUrl;

  final DateTime? publishedAt;

  /// 发布里一共带了几个安装包。多 ABI 拆包后通常 ≥2，用于给用户解释
  /// "为什么这次只有 20 MB"。
  final int apkAssetCount;

  String get sizeLabel {
    if (apkSizeBytes <= 0) return '未知大小';
    final mb = apkSizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// 从 GitHub Releases API 的单条记录解析。
  ///
  /// [deviceAbis] 交给 ABI 选择策略：按 ABI 拆包后同一版本有多个 `.apk`，
  /// 盲目取第一个会把 arm64 包装进 32 位设备（`NO_MATCHING_ABIS`），
  /// 用户看到的只是「安装失败」，根本没法自查。
  ///
  /// 找不到可用 APK 时返回 null——宁可提示「该发布没有安装包 / 没有适配本机的包」，
  /// 也不要给现场人员一个打不开的更新入口。
  static UpdateRelease? fromGitHubJson(
    Map<String, dynamic> json, {
    List<String> deviceAbis = const [],
  }) {
    final tag = (json['tag_name'] as String?)?.trim() ?? '';
    final version = AppVersion.tryParse(tag);
    if (version == null) return null;

    final assets = (json['assets'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();

    // 先筛出所有 .apk，再由策略挑最合适的一只。
    // 带 qingyang 的优先：仓库里同时挂测试包/示例包时不至于抓错。
    final apks = assets
        .where((asset) =>
            (asset['name'] as String?)?.toLowerCase().endsWith('.apk') ?? false)
        .toList();
    if (apks.isEmpty) return null;
    final branded = apks
        .where((asset) =>
            ((asset['name'] as String?) ?? '').toLowerCase().contains('qingyang'))
        .toList();
    final pool = branded.isEmpty ? apks : branded;

    final apk = ApkAssetPolicy.pick(
      pool,
      (asset) => (asset['name'] as String?) ?? '',
      deviceAbis,
    );
    if (apk == null) return null;

    String? checksumUrl;
    for (final asset in assets) {
      final name = (asset['name'] as String?)?.toLowerCase() ?? '';
      if (name == 'sha256sums.txt') {
        checksumUrl = asset['browser_download_url'] as String?;
        break;
      }
    }

    final published = DateTime.tryParse(json['published_at'] as String? ?? '');
    return UpdateRelease(
      tag: tag,
      version: version,
      title: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : tag,
      notes: (json['body'] as String? ?? '').trim(),
      pageUrl: json['html_url'] as String? ?? '',
      apkUrl: apk['browser_download_url'] as String? ?? '',
      apkName: apk['name'] as String? ?? 'update.apk',
      apkSizeBytes: (apk['size'] as num?)?.toInt() ?? 0,
      checksumUrl: checksumUrl,
      publishedAt: published,
      apkAssetCount: pool.length,
    );
  }

  UpdateRelease copyWith({String? checksumUrl}) => UpdateRelease(
        tag: tag,
        version: version,
        title: title,
        notes: notes,
        pageUrl: pageUrl,
        apkUrl: apkUrl,
        apkName: apkName,
        apkSizeBytes: apkSizeBytes,
        checksumUrl: checksumUrl ?? this.checksumUrl,
        publishedAt: publishedAt,
        apkAssetCount: apkAssetCount,
      );
}

enum UpdateStatus {
  /// 已是最新。
  upToDate,

  /// 发现新版本。
  available,

  /// 当前平台/构建不支持自更新（例如桌面调试）。
  unsupported,

  /// 网络、限流、发布记录异常等。
  failed,
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.status,
    required this.currentVersion,
    this.release,
    this.detail,
  });

  const UpdateCheckResult.upToDate(String currentVersion)
      : this(status: UpdateStatus.upToDate, currentVersion: currentVersion);

  const UpdateCheckResult.unsupported(String currentVersion, String detail)
      : this(
          status: UpdateStatus.unsupported,
          currentVersion: currentVersion,
          detail: detail,
        );

  const UpdateCheckResult.failed(String currentVersion, String detail)
      : this(
          status: UpdateStatus.failed,
          currentVersion: currentVersion,
          detail: detail,
        );

  final UpdateStatus status;
  final String currentVersion;
  final UpdateRelease? release;
  final String? detail;

  bool get hasUpdate => status == UpdateStatus.available;

  String describe() {
    switch (status) {
      case UpdateStatus.available:
        return '发现新版本 v${release?.version}（当前 $currentVersion）';
      case UpdateStatus.upToDate:
        return '已是最新版本 $currentVersion';
      case UpdateStatus.unsupported:
        return detail ?? '当前环境不支持自动更新';
      case UpdateStatus.failed:
        return detail ?? '检查更新失败';
    }
  }
}

/// 远程更新引擎：只负责「查」——把远端发布信息取回来并判断是否有新版。
///
/// 下载、校验、安装分别由 [ApkInstaller] 承担：查更新是一次轻量 HTTP，
/// 装 APK 是重活且有安全校验，混在一起会让两边都不好测。
abstract class UpdateEngine {
  Future<UpdateCheckResult> check({
    required String currentVersion,
    required String repo,
    List<String> deviceAbis = const [],
  });

  /// 拉取纯文本（用于 `SHA256SUMS.txt`）。
  Future<String?> fetchText(String url);
}

class GitHubUpdateEngine implements UpdateEngine {
  GitHubUpdateEngine({this.timeout = const Duration(seconds: 10)});

  final Duration timeout;

  static const String _userAgent = 'QingyangWatermarkCamera';

  @override
  Future<UpdateCheckResult> check({
    required String currentVersion,
    required String repo,
    List<String> deviceAbis = const [],
  }) async {
    final current = AppVersion.tryParse(currentVersion);
    if (current == null) {
      return UpdateCheckResult.failed(
        currentVersion,
        '无法识别当前版本号「$currentVersion」',
      );
    }
    final target = repo.trim();
    if (!RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(target)) {
      return UpdateCheckResult.failed(
        currentVersion,
        '更新源格式应为 owner/repo，实际是「$repo」',
      );
    }

    final url = 'https://api.github.com/repos/$target/releases/latest';
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = timeout;
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == 404) {
        return UpdateCheckResult.failed(currentVersion, '更新源没有发布记录');
      }
      if (response.statusCode == 403) {
        return UpdateCheckResult.failed(
          currentVersion,
          'GitHub 接口被限流，请稍后再试',
        );
      }
      if (response.statusCode != 200) {
        return UpdateCheckResult.failed(
          currentVersion,
          '更新源返回 HTTP ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return UpdateCheckResult.failed(currentVersion, '发布记录格式异常');
      }
      final release = UpdateRelease.fromGitHubJson(decoded, deviceAbis: deviceAbis);
      if (release == null) {
        final hasAnyApk = (decoded['assets'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .any((asset) =>
                (asset['name'] as String?)?.toLowerCase().endsWith('.apk') ?? false);
        return UpdateCheckResult.failed(
          currentVersion,
          hasAnyApk ? '该发布没有适配本机（${deviceAbis.join('/')}）的安装包' : '该发布没有可用的 APK 安装包',
        );
      }
      if (release.version.isNewerThan(current)) {
        return UpdateCheckResult(
          status: UpdateStatus.available,
          currentVersion: currentVersion,
          release: release,
        );
      }
      return UpdateCheckResult.upToDate(currentVersion);
    } on TimeoutException {
      return UpdateCheckResult.failed(currentVersion, '连接更新源超时');
    } on SocketException catch (error) {
      return UpdateCheckResult.failed(
        currentVersion,
        '网络不可用：${error.osError?.message ?? error.message}',
      );
    } on HandshakeException {
      return UpdateCheckResult.failed(currentVersion, 'TLS 握手失败');
    } catch (error) {
      return UpdateCheckResult.failed(currentVersion, '检查更新失败：$error');
    } finally {
      client?.close(force: true);
    }
  }

  @override
  Future<String?> fetchText(String url) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = timeout;
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;
      return await response.transform(utf8.decoder).join();
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }
}

/// 测试替身：不联网，按配置返回结果。
class FakeUpdateEngine implements UpdateEngine {
  FakeUpdateEngine({this.result, this.text, this.throwOnCheck = false});

  UpdateCheckResult? result;
  String? text;
  bool throwOnCheck;

  int checkCount = 0;
  final List<String> fetchedUrls = [];

  @override
  Future<UpdateCheckResult> check({
    required String currentVersion,
    required String repo,
    List<String> deviceAbis = const [],
  }) async {
    checkCount++;
    if (throwOnCheck) throw StateError('boom');
    return result ??
        UpdateCheckResult.upToDate(currentVersion);
  }

  @override
  Future<String?> fetchText(String url) async {
    fetchedUrls.add(url);
    return text;
  }
}
