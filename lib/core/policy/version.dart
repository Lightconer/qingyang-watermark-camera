/// 版本号口径：远程更新要比较「已安装版本」与「发布标签」。
///
/// 只认数字段（major.minor.patch），忽略 `v` 前缀、`+build` 后缀；
/// 预发布后缀（`-beta.1`）参与比较时视为低于同号正式版，
/// 避免把 beta 当成新版本推给现场人员。
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch, {this.preRelease});

  final int major;
  final int minor;
  final int patch;

  /// 预发布后缀（不含 `-`）；正式版为 null。
  final String? preRelease;

  static const AppVersion zero = AppVersion(0, 0, 0);

  /// 解析失败返回 null（调用方据此提示"版本号无法识别"，而不是当成最新）。
  static AppVersion? tryParse(String? raw) {
    if (raw == null) return null;
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('v') || text.startsWith('V')) {
      text = text.substring(1);
    }
    // 去掉 pubspec 的 +build 号
    final plus = text.indexOf('+');
    if (plus >= 0) text = text.substring(0, plus);
    String? pre;
    final dash = text.indexOf('-');
    if (dash >= 0) {
      pre = text.substring(dash + 1).trim();
      text = text.substring(0, dash);
      if (pre.isEmpty) pre = null;
    }
    final parts = text.split('.');
    if (parts.isEmpty || parts.length > 3) return null;
    final numbers = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part.trim());
      if (value == null || value < 0) return null;
      numbers.add(value);
    }
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return AppVersion(numbers[0], numbers[1], numbers[2], preRelease: pre);
  }

  /// 是否比 [other] 新。
  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    // 同号：正式版 > 预发布版
    if (preRelease == null && other.preRelease == null) return 0;
    if (preRelease == null) return 1;
    if (other.preRelease == null) return -1;
    return preRelease!.compareTo(other.preRelease!);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease);

  @override
  String toString() =>
      preRelease == null ? '$major.$minor.$patch' : '$major.$minor.$patch-$preRelease';
}
