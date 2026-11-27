import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../core/metadata/exif_codec.dart';

/// 哈希引擎。台账、水印小字、XMP 三处共用同一套口径：
/// * `sha256OfPixelStream`：去掉 EXIF/XMP 段后的像素流哈希，写元数据不会改变它；
/// * `sha256OfFile`：整文件哈希，用于文件级比对。
abstract class HashEngine {
  String sha256OfBytes(Uint8List bytes);

  String sha256OfPixelStream(Uint8List jpegBytes);

  Future<String> sha256OfFile(String path);

  String shortHash(String digest, {int length = 16}) =>
      digest.length <= length ? digest : digest.substring(0, length);
}

class CryptoHashEngine implements HashEngine {
  const CryptoHashEngine({this.exifCodec = const ExifCodec()});

  final ExifCodec exifCodec;

  @override
  String sha256OfBytes(Uint8List bytes) => sha256.convert(bytes).toString();

  @override
  String sha256OfPixelStream(Uint8List jpegBytes) {
    try {
      return sha256OfBytes(exifCodec.stripMetadata(jpegBytes));
    } on FormatException {
      return sha256OfBytes(jpegBytes);
    }
  }

  @override
  Future<String> sha256OfFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return sha256OfBytes(bytes);
  }
}

/// 测试替身：稳定、可预期、不依赖真实文件。
class FakeHashEngine implements HashEngine {
  FakeHashEngine({this.seed = 'a'});

  final String seed;
  int calls = 0;

  @override
  String sha256OfBytes(Uint8List bytes) {
    calls++;
    final base = seed * 64;
    final tail = bytes.length.toRadixString(16).padLeft(8, '0');
    return '${base.substring(0, 56)}$tail';
  }

  @override
  String sha256OfPixelStream(Uint8List jpegBytes) => sha256OfBytes(jpegBytes);

  @override
  Future<String> sha256OfFile(String path) async {
    final stat = await File(path).length();
    return sha256OfBytes(Uint8List(stat));
  }
}
