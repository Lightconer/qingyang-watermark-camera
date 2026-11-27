import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/models/types.dart';

/// 文件名规则：
/// * 拍摄：`QY_20261127_203105_482.jpg`
/// * 导入：`原名_wm.jpg`（原图绝不覆盖）
class FileNaming {
  const FileNaming._();

  static String capture(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    final local = time.toLocal();
    final stamp = '${local.year}${two(local.month)}${two(local.day)}_'
        '${two(local.hour)}${two(local.minute)}${two(local.second)}_'
        '${local.millisecond.toString().padLeft(3, '0')}';
    return 'QY_$stamp.jpg';
  }

  static String importName(String originalFilePath) {
    final base = p.basenameWithoutExtension(originalFilePath);
    return '${base}_wm.jpg';
  }

  static String dayFolder(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    final local = time.toLocal();
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}

/// 存储引擎：独立目录按日期分组，成品按 `日期/import`、`日期/camera` 分目录。
abstract class StorageEngine {
  Future<Directory> root();

  /// 成品输出路径。
  Future<String> outputPath({
    required DateTime date,
    required PhotoSource source,
    required String fileName,
  });

  /// 原图备份路径（可选）。
  Future<String> originalPath({
    required DateTime date,
    required PhotoSource source,
    required String fileName,
  });

  Future<String> ledgerPath(DateTime date);

  Future<List<String>> listDay(DateTime date);

  Future<int> totalBytes();
}

class FileStorageEngine implements StorageEngine {
  FileStorageEngine({this.folderName = 'QingyangWatermark'});

  final String folderName;
  Directory? _cached;

  @override
  Future<Directory> root() async {
    if (_cached != null) return _cached!;
    Directory base;
    try {
      final external = await getExternalStorageDirectory();
      base = external ?? await getApplicationDocumentsDirectory();
    } catch (_) {
      base = await getApplicationDocumentsDirectory();
    }
    final directory = Directory(p.join(base.path, folderName));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _cached = directory;
    return directory;
  }

  @override
  Future<String> outputPath({
    required DateTime date,
    required PhotoSource source,
    required String fileName,
  }) async {
    final rootDir = await root();
    final folder = Directory(p.join(
      rootDir.path,
      FileNaming.dayFolder(date),
      source.isImport ? 'import' : 'camera',
    ));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return p.join(folder.path, fileName);
  }

  @override
  Future<String> originalPath({
    required DateTime date,
    required PhotoSource source,
    required String fileName,
  }) async {
    final rootDir = await root();
    final folder = Directory(p.join(
      rootDir.path,
      FileNaming.dayFolder(date),
      'original',
      source.isImport ? 'import' : 'camera',
    ));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return p.join(folder.path, fileName);
  }

  @override
  Future<String> ledgerPath(DateTime date) async {
    final rootDir = await root();
    final folder = Directory(p.join(rootDir.path, 'ledger'));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return p.join(folder.path, '台账_${FileNaming.dayFolder(date)}.xlsx');
  }

  @override
  Future<List<String>> listDay(DateTime date) async {
    final rootDir = await root();
    final folder = Directory(p.join(rootDir.path, FileNaming.dayFolder(date)));
    if (!await folder.exists()) return const [];
    final result = <String>[];
    await for (final entity in folder.list(recursive: true)) {
      if (entity is File && _isImage(entity.path)) {
        result.add(entity.path);
      }
    }
    result.sort();
    return result;
  }

  @override
  Future<int> totalBytes() async {
    final rootDir = await root();
    var total = 0;
    await for (final entity in rootDir.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  static bool _isImage(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }
}

/// 测试替身：内存路径 + 临时目录（不污染真实存储）。
class FakeStorageEngine implements StorageEngine {
  FakeStorageEngine(this.basePath);

  final String basePath;
  final List<String> written = [];

  @override
  Future<Directory> root() async {
    final directory = Directory(basePath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  @override
  Future<String> outputPath({
    required DateTime date,
    required PhotoSource source,
    required String fileName,
  }) async {
    final path = p.join(
      basePath,
      FileNaming.dayFolder(date),
      source.isImport ? 'import' : 'camera',
      fileName,
    );
    await Directory(p.dirname(path)).create(recursive: true);
    written.add(path);
    return path;
  }

  @override
  Future<String> originalPath({
    required DateTime date,
    required PhotoSource source,
    required String fileName,
  }) async =>
      p.join(basePath, FileNaming.dayFolder(date), 'original', fileName);

  @override
  Future<String> ledgerPath(DateTime date) async =>
      p.join(basePath, 'ledger', '台账_${FileNaming.dayFolder(date)}.xlsx');

  @override
  Future<List<String>> listDay(DateTime date) async => written;

  @override
  Future<int> totalBytes() async => 0;
}
