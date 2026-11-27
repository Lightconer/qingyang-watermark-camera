import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// 图片编解码引擎接口。像素层能力全部收敛在这里，便于替换为原生实现
/// （Android BitmapFactory.inSampleSize / BitmapRegionDecoder，iOS CoreGraphics）。
abstract class ImageCodecEngine {
  /// 解码。若 [maxLongSide] 有界，则在解码阶段直接降采样（等价 inSampleSize），避免 OOM。
  Future<ui.Image> decode(Uint8List bytes, {int? maxLongSide});

  /// 按长边限制缩放（解码降采样不足时兜底）。
  Future<ui.Image> resizeToLongSide(ui.Image image, int maxLongSide);

  /// 旋转/镜像（方向校正）。
  Future<ui.Image> transform(
    ui.Image image, {
    int quarterTurns = 0,
    bool flipX = false,
    bool flipY = false,
  });

  /// 编码为 JPEG。
  Future<Uint8List> encodeJpeg(ui.Image image, {int quality = 92});

  /// 编码为 PNG（调试与单测用）。
  Future<Uint8List> encodePng(ui.Image image);

  /// 读取像素（RGBA8888），用于哈希与单测。
  Future<Uint8List> readRgba(ui.Image image);

  /// EXIF Orientation 1..8 → 变换参数。
  static ({int quarterTurns, bool flipX, bool flipY}) orientationTransform(
      int orientation) {
    switch (orientation) {
      case 2:
        return (quarterTurns: 0, flipX: true, flipY: false);
      case 3:
        return (quarterTurns: 2, flipX: false, flipY: false);
      case 4:
        return (quarterTurns: 0, flipX: false, flipY: true);
      case 5:
        return (quarterTurns: 1, flipX: true, flipY: false);
      case 6:
        return (quarterTurns: 1, flipX: false, flipY: false);
      case 7:
        return (quarterTurns: 3, flipX: true, flipY: false);
      case 8:
        return (quarterTurns: 3, flipX: false, flipY: false);
      default:
        return (quarterTurns: 0, flipX: false, flipY: false);
    }
  }
}

/// 基于 dart:ui + image 包的默认实现。
class FlutterImageCodec implements ImageCodecEngine {
  const FlutterImageCodec();

  @override
  Future<ui.Image> decode(Uint8List bytes, {int? maxLongSide}) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    var targetWidth = descriptor.width;
    if (maxLongSide != null && maxLongSide > 0) {
      final longSide = math.max(descriptor.width, descriptor.height);
      if (longSide > maxLongSide) {
        targetWidth =
            (descriptor.width * maxLongSide / longSide).round().clamp(1, 1 << 20);
      }
    }
    final codec = await descriptor.instantiateCodec(
      targetWidth: targetWidth == descriptor.width ? null : targetWidth,
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  @override
  Future<ui.Image> resizeToLongSide(ui.Image image, int maxLongSide) async {
    final longSide = math.max(image.width, image.height);
    if (longSide <= maxLongSide) return image;
    final scale = maxLongSide / longSide;
    final width = math.max(1, (image.width * scale).round());
    final height = math.max(1, (image.height * scale).round());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    final result = await picture.toImage(width, height);
    picture.dispose();
    return result;
  }

  @override
  Future<ui.Image> transform(
    ui.Image image, {
    int quarterTurns = 0,
    bool flipX = false,
    bool flipY = false,
  }) async {
    final turns = quarterTurns % 4;
    if (turns == 0 && !flipX && !flipY) return image;
    final swap = turns.isOdd;
    final width = swap ? image.height : image.width;
    final height = swap ? image.width : image.height;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.translate(width / 2, height / 2);
    canvas.rotate(turns * math.pi / 2);
    canvas.scale(flipX ? -1.0 : 1.0, flipY ? -1.0 : 1.0);
    canvas.drawImage(
      image,
      ui.Offset(-image.width / 2, -image.height / 2),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final result = await picture.toImage(width, height);
    picture.dispose();
    return result;
  }

  @override
  Future<Uint8List> encodeJpeg(ui.Image image, {int quality = 92}) async {
    final rgba = await readRgba(image);
    final raw = img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    final encoded = img.encodeJpg(raw, quality: quality);
    return Uint8List.fromList(encoded);
  }

  @override
  Future<Uint8List> encodePng(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('PNG 编码失败');
    return Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  @override
  Future<Uint8List> readRgba(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw StateError('像素读取失败');
    // 必须复制成独立 buffer：fromBytes 直接消费 ByteBuffer，不能带视图偏移。
    return Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }
}

/// 测试替身：不碰真实解码器，用纯色/网格图验证管线顺序与哈希一致性。
class FakeImageCodec implements ImageCodecEngine {
  FakeImageCodec({this.width = 320, this.height = 240});

  final int width;
  final int height;
  int decodeCount = 0;
  int encodeCount = 0;

  @override
  Future<ui.Image> decode(Uint8List bytes, {int? maxLongSide}) async {
    decodeCount++;
    return _solid(width, height, const ui.Color(0xFF203040));
  }

  @override
  Future<ui.Image> resizeToLongSide(ui.Image image, int maxLongSide) async {
    final longSide = math.max(image.width, image.height);
    if (longSide <= maxLongSide) return image;
    final scale = maxLongSide / longSide;
    return _solid(
      math.max(1, (image.width * scale).round()),
      math.max(1, (image.height * scale).round()),
      const ui.Color(0xFF203040),
    );
  }

  @override
  Future<ui.Image> transform(
    ui.Image image, {
    int quarterTurns = 0,
    bool flipX = false,
    bool flipY = false,
  }) async {
    final swap = quarterTurns.isOdd;
    return _solid(
      swap ? image.height : image.width,
      swap ? image.width : image.height,
      const ui.Color(0xFF203040),
    );
  }

  @override
  Future<Uint8List> encodeJpeg(ui.Image image, {int quality = 92}) async {
    encodeCount++;
    // 产生稳定但随尺寸变化的字节，便于断言"内容变了哈希就变了"。
    final header = 'FAKEJPEG:${image.width}x${image.height}:$quality'
        .codeUnits;
    final payload = List<int>.generate(
      math.min(4096, image.width * image.height),
      (index) => (index * 31 + quality) & 0xFF,
    );
    return Uint8List.fromList([...header, 0, ...payload]);
  }

  @override
  Future<Uint8List> encodePng(ui.Image image) async =>
      Uint8List.fromList('FAKEPNG:${image.width}x${image.height}'.codeUnits);

  @override
  Future<Uint8List> readRgba(ui.Image image) async => Uint8List(
      image.width * image.height * 4);

  Future<ui.Image> _solid(int width, int height, ui.Color color) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = color,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    return image;
  }
}
