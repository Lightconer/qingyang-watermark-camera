import 'dart:convert';
import 'dart:io';

import '../../core/models/types.dart';

/// 天气引擎。仅在开关打开且有网时调用；失败返回 null，画面上不显示天气。
abstract class WeatherEngine {
  bool get configured;

  Future<WeatherSnapshot?> current(GeoPoint point);
}

/// 基于 Open-Meteo 的免 Key 实现。
class OpenMeteoWeatherEngine implements WeatherEngine {
  OpenMeteoWeatherEngine({this.timeout = const Duration(seconds: 6)});

  final Duration timeout;

  @override
  bool get configured => true;

  @override
  Future<WeatherSnapshot?> current(GeoPoint point) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=${point.latitude}'
        '&longitude=${point.longitude}&current=temperature_2m,weather_code'
        '&timezone=auto',
      );
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'QingyangWatermarkCamera/1.0');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      if (json is! Map) return null;
      final current = json['current'];
      if (current is! Map) return null;
      final temperature = (current['temperature_2m'] as num?)?.toDouble();
      final code = (current['weather_code'] as num?)?.toInt() ?? -1;
      if (temperature == null && code < 0) return null;
      return WeatherSnapshot(
        temperatureC: temperature,
        text: weatherCodeToText(code),
        fetchedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// WMO 天气代码 → 中文。
  static String weatherCodeToText(int code) {
    if (code == 0) return '晴';
    if (code <= 2) return '多云';
    if (code == 3) return '阴';
    if (code == 45 || code == 48) return '雾';
    if (code >= 51 && code <= 57) return '毛毛雨';
    if (code >= 61 && code <= 67) return '雨';
    if (code >= 71 && code <= 77) return '雪';
    if (code >= 80 && code <= 82) return '阵雨';
    if (code == 85 || code == 86) return '阵雪';
    if (code >= 95) return '雷雨';
    return '';
  }
}

class DisabledWeatherEngine implements WeatherEngine {
  const DisabledWeatherEngine();

  @override
  bool get configured => false;

  @override
  Future<WeatherSnapshot?> current(GeoPoint point) async => null;
}

class FakeWeatherEngine implements WeatherEngine {
  FakeWeatherEngine({this.snapshot});

  WeatherSnapshot? snapshot;

  @override
  bool get configured => true;

  @override
  Future<WeatherSnapshot?> current(GeoPoint point) async => snapshot;
}
