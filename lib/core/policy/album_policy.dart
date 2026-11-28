/// 相册名口径：成品写入系统相册时使用的独立相册名。
///
/// 相册名会进入 Android 的 `MediaStore.Images.Media.RELATIVE_PATH`
/// （`Pictures/<相册名>/`），也会进入 legacy 分支的真实目录路径，
/// 因此必须过滤掉路径分隔符与文件系统保留字符——否则写入会失败，
/// 或者落进错误目录。这里做成纯 Dart 规则，便于单测与服务端/原生侧对齐。
class AlbumPolicy {
  const AlbumPolicy._();

  /// 默认相册名，与 APP 名称保持一致。
  static const String defaultAlbum = '青阳水印相机';

  /// Android 文件系统 / MediaStore 不接受的字符。
  static final RegExp _illegal = RegExp(r'[\\/:*?"<>|\x00-\x1F]');

  /// 名称上限：过长会被部分 ROM 截断，导致同一相册分裂成多个。
  static const int maxLength = 40;

  /// 归一化相册名：非法字符替换为下划线，去首尾空白与点号，空则回退默认名。
  static String normalize(String? raw) {
    var name = (raw ?? '').trim();
    if (name.isEmpty) return defaultAlbum;
    name = name.replaceAll(_illegal, '_');
    // 连续空白压成一个空格，避免相册名里出现大段空白
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    // 首尾的点与空格在部分文件系统上非法
    name = name.replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
    if (name.isEmpty) return defaultAlbum;
    if (name.length > maxLength) {
      name = name.substring(0, maxLength).trim();
      if (name.isEmpty) return defaultAlbum;
    }
    // `.` 与 `..` 是目录语义，不能当相册名
    if (name == '.' || name == '..') return defaultAlbum;
    return name;
  }

  /// 归一化后是否与原文一致（供设置页即时提示）。
  static bool isClean(String raw) => normalize(raw) == raw.trim();
}
