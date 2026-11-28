/// `SHA256SUMS.txt` 解析：远程更新下载完 APK 后必须核对哈希才开始安装。
///
/// 兼容 `sha256sum` 的两种输出格式：
/// * `<hash>  <文件名>`（二进制模式两空格）
/// * `<hash> *<文件名>`（文本模式星号）
/// 也接受 Windows 换行与前后空白。
class ChecksumFile {
  const ChecksumFile._();

  /// 解析成「文件名 → 哈希」。非法行忽略。
  static Map<String, String> parseAll(String? content) {
    final result = <String, String>{};
    if (content == null || content.isEmpty) return result;
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      // 第一段是哈希，其余是文件名（可能带 * 前缀或 ./ 路径）
      final match = RegExp(r'^([0-9a-fA-F]{64})[ \t]+\*?(.+)$').firstMatch(line);
      if (match == null) continue;
      var name = match.group(2)!.trim();
      if (name.isEmpty) continue;
      final slash = name.lastIndexOf('/');
      if (slash >= 0) name = name.substring(slash + 1);
      result[name] = match.group(1)!.toLowerCase();
    }
    return result;
  }

  /// 查某个文件的哈希；文件名对不上时，若整份清单只有一个条目且 [fileName]
  /// 非空，则按该条目处理（发布方偶尔把文件改名的兜底）。
  static String? lookup(String? content, String fileName) {
    final all = parseAll(content);
    if (all.isEmpty) return null;
    final direct = all[fileName];
    if (direct != null) return direct;
    final base = fileName.split('/').last;
    final byBase = all[base];
    if (byBase != null) return byBase;
    if (all.length == 1) return all.values.first;
    return null;
  }

  /// 比较两个哈希（忽略大小写与空白）。
  static bool matches(String? expected, String? actual) {
    if (expected == null || actual == null) return false;
    return expected.trim().toLowerCase() == actual.trim().toLowerCase();
  }
}
