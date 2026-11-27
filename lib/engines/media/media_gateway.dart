import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

/// 导入通道标识，用于来源留痕（photo_picker / saf / action_send）。
class ImportChannel {
  const ImportChannel._();

  static const String systemGallery = 'photo_picker';
  static const String folder = 'saf';
  static const String share = 'action_send';
}

class MediaPickOutcome {
  const MediaPickOutcome({required this.paths, required this.channel});

  final List<String> paths;
  final String channel;

  bool get isEmpty => paths.isEmpty;
}

/// 媒体入口网关。
///
/// * Android 13+ 走系统 Photo Picker（免媒体权限）；iOS 走 PHPicker；
/// * 文件夹批量导入走 SAF；
/// * ACTION_SEND `image/*` 由原生侧 MainActivity 通过 MethodChannel 回传。
abstract class MediaGateway {
  Future<MediaPickOutcome> pickSystemGallery();

  Future<MediaPickOutcome> pickFolder();

  Future<MediaPickOutcome> takeSharedImages();
}

class PlatformMediaGateway implements MediaGateway {
  PlatformMediaGateway({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  static const MethodChannel _intentChannel =
      MethodChannel('com.qingyang.watermark/intent');

  static const List<String> _supportedExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
    'dng',
  ];

  final ImagePicker _picker;

  @override
  Future<MediaPickOutcome> pickSystemGallery() async {
    try {
      final files = await _picker.pickMultiImage();
      return MediaPickOutcome(
        paths: files.map((file) => file.path).where(_exists).toList(growable: false),
        channel: ImportChannel.systemGallery,
      );
    } catch (_) {
      return const MediaPickOutcome(paths: [], channel: ImportChannel.systemGallery);
    }
  }

  @override
  Future<MediaPickOutcome> pickFolder() async {
    // 优先 SAF 目录选择；部分内容提供者不给真实路径时退回多选文件。
    try {
      final directory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择要批量导入的文件夹',
      );
      if (directory != null) {
        final dir = Directory(directory);
        if (await dir.exists()) {
          final files = <String>[];
          await for (final entity in dir.list(recursive: true)) {
            if (entity is! File) continue;
            final ext = p.extension(entity.path).replaceFirst('.', '').toLowerCase();
            if (_supportedExtensions.contains(ext)) files.add(entity.path);
          }
          if (files.isNotEmpty) {
            files.sort();
            return MediaPickOutcome(paths: files, channel: ImportChannel.folder);
          }
        }
      }
    } catch (_) {
      // 继续走文件多选
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
        dialogTitle: '选择照片（可多选）',
      );
      final paths = <String>[];
      if (result != null) {
        for (final file in result.files) {
          final path = file.path;
          if (path != null && _exists(path)) paths.add(path);
        }
      }
      return MediaPickOutcome(paths: paths, channel: ImportChannel.folder);
    } catch (_) {
      return const MediaPickOutcome(paths: [], channel: ImportChannel.folder);
    }
  }

  @override
  Future<MediaPickOutcome> takeSharedImages() async {
    try {
      final result = await _intentChannel.invokeMethod<List<dynamic>>('takeSharedImages');
      final paths = <String>[];
      if (result != null) {
        for (final item in result) {
          if (item is String && _exists(item)) paths.add(item);
        }
      }
      return MediaPickOutcome(paths: paths, channel: ImportChannel.share);
    } on MissingPluginException {
      // 原生侧未注入（例如纯 Dart 测试环境）时静默返回空。
      return const MediaPickOutcome(paths: [], channel: ImportChannel.share);
    } on PlatformException {
      return const MediaPickOutcome(paths: [], channel: ImportChannel.share);
    }
  }

  bool _exists(String path) {
    try {
      return path.isNotEmpty && File(path).existsSync();
    } catch (_) {
      return false;
    }
  }
}

class FakeMediaGateway implements MediaGateway {
  FakeMediaGateway({this.paths = const [], this.channel = 'photo_picker'});

  List<String> paths;
  String channel;

  @override
  Future<MediaPickOutcome> pickSystemGallery() async =>
      MediaPickOutcome(paths: paths, channel: channel);

  @override
  Future<MediaPickOutcome> pickFolder() async =>
      MediaPickOutcome(paths: paths, channel: channel);

  @override
  Future<MediaPickOutcome> takeSharedImages() async =>
      MediaPickOutcome(paths: paths, channel: channel);
}
