import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 解码后的图片缓存默认上限 100 MB，对一台还要留给相机缓冲的手机来说太多。
  // 这里压到 48 MB：本应用的图片主要出现在九宫格与详情页，
  // 缩略图已按 512 px 解码，48 MB 足够放几十张还不挤占系统内存。
  PaintingBinding.instance.imageCache
    ..maximumSize = 60
    ..maximumSizeBytes = 48 << 20;

  final services = await bootstrapServices();
  runApp(QingyangApp(services: services));
}
