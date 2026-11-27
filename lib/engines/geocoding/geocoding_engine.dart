import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/models/types.dart';

/// 逆地理编码引擎。离线、未配置或失败时一律返回 null —— 绝不编造地址。
abstract class GeocodingEngine {
  bool get configured;

  String get providerLabel;

  Future<String?> reverse(GeoPoint point);
}

/// 支持高德（需 Key）与 Nominatim（免 Key）两种实现。
class HttpGeocodingEngine implements GeocodingEngine {
  HttpGeocodingEngine({
    this.provider = 'nominatim',
    this.apiKey = '',
    this.timeout = const Duration(seconds: 6),
  });

  /// `nominatim` 或 `amap`。
  final String provider;
  final String apiKey;
  final Duration timeout;

  final Map<String, String> _cache = {};

  @override
  bool get configured => provider == 'nominatim' || apiKey.trim().isNotEmpty;

  @override
  String get providerLabel => provider == 'amap' ? '高德逆地理' : 'OpenStreetMap';

  @override
  Future<String?> reverse(GeoPoint point) async {
    if (!configured) return null;
    final key =
        '${point.latitude.toStringAsFixed(4)},${point.longitude.toStringAsFixed(4)}';
    final cached = _cache[key];
    if (cached != null) return cached;

    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final uri = provider == 'amap'
          ? Uri.parse(
              'https://restapi.amap.com/v3/geocode/regeo?key=$apiKey'
              '&location=${point.longitude},${point.latitude}&extensions=base',
            )
          : Uri.parse(
              'https://nominatim.openstreetmap.org/reverse?format=jsonv2'
              '&lat=${point.latitude}&lon=${point.longitude}'
              '&accept-language=zh-CN&zoom=18',
            );
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'QingyangWatermarkCamera/1.0');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      final address = _extract(json);
      if (address != null && address.trim().isNotEmpty) {
        _cache[key] = address.trim();
        return address.trim();
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  String? _extract(Object? json) {
    if (json is! Map) return null;
    if (provider == 'amap') {
      final regeocode = json['regeocode'];
      if (regeocode is Map) {
        final formatted = regeocode['formatted_address'];
        if (formatted is String) return formatted;
      }
      return null;
    }
    final display = json['display_name'];
    return display is String ? display : null;
  }
}

/// 测试替身 / 离线实现：始终不可用，保证"无地址就显示无原始定位"。
class DisabledGeocodingEngine implements GeocodingEngine {
  const DisabledGeocodingEngine();

  @override
  bool get configured => false;

  @override
  String get providerLabel => '已关闭';

  @override
  Future<String?> reverse(GeoPoint point) async => null;
}

class FakeGeocodingEngine implements GeocodingEngine {
  FakeGeocodingEngine({this.address});

  String? address;

  @override
  bool get configured => true;

  @override
  String get providerLabel => '测试';

  @override
  Future<String?> reverse(GeoPoint point) async => address;
}
