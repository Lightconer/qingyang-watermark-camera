import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';

Future<void> main() async {
  final services = await bootstrapServices();
  runApp(QingyangApp(services: services));
}
