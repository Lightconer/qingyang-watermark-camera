import 'package:flutter_test/flutter_test.dart';
import 'package:qingyang_watermark/engines/sensor/compass_engine.dart';

void main() {
  group('CompassReading.fromMap', () {
    test('解析度数与精度', () {
      final reading = CompassReading.fromMap({'degrees': 42.5, 'accuracy': 5});
      expect(reading, isNotNull);
      expect(reading!.degrees, 42.5);
      expect(reading.accuracyDegrees, 5.0);
      expect(reading.isValid, isTrue);
    });

    test('缺精度字段时为 null（设备不上报）', () {
      final reading = CompassReading.fromMap({'degrees': 10});
      expect(reading!.accuracyDegrees, isNull);
    });

    test('脏数据一律丢弃，不产生 0°', () {
      expect(CompassReading.fromMap(null), isNull);
      expect(CompassReading.fromMap(<String, Object?>{}), isNull);
      expect(CompassReading.fromMap({'degrees': 'abc'}), isNull);
      expect(CompassReading.fromMap({'degrees': double.nan}), isNull);
      expect(CompassReading.fromMap({'degrees': double.infinity}), isNull);
    });
  });

  group('FakeCompassEngine', () {
    test('支持探测与一次性读数', () async {
      final engine = FakeCompassEngine(degrees: 90);
      expect(await engine.probe(), isTrue);
      final reading = await engine.read();
      expect(reading!.degrees, 90);
      await engine.dispose();
    });

    test('不支持时探测为 false、读数为 null、流不发数据', () async {
      final engine = FakeCompassEngine(supported: false);
      expect(await engine.probe(), isFalse);
      expect(await engine.read(), isNull);
      final received = <CompassReading>[];
      final sub = engine.stream.listen(received.add);
      engine.emit(30);
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);
      await sub.cancel();
      await engine.dispose();
    });

    test('emit 会推给订阅者', () async {
      final engine = FakeCompassEngine();
      final received = <CompassReading>[];
      final sub = engine.stream.listen(received.add);
      engine.emit(135, accuracy: 10);
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 1);
      expect(received.first.degrees, 135);
      expect(received.first.accuracyDegrees, 10);
      expect(engine.hasListener, isTrue);
      await sub.cancel();
      await engine.dispose();
    });

    test('dispose 后再 emit 不抛异常', () async {
      final engine = FakeCompassEngine();
      await engine.dispose();
      expect(() => engine.emit(10), returnsNormally);
    });
  });
}
