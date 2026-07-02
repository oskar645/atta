import 'package:atta/src/utils/vehicle_specs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('engine power parser accepts custom horsepower values', () {
    expect(parsePowerHpInput('193'), 193);
    expect(parsePowerHpInput('197 л.с.'), 197);
    expect(parsePowerHpInput('300'), 300);
    expect(parsePowerHpInput('1000 л.с.'), 1000);
  });

  test('engine volume parser accepts cc and liters values', () {
    expect(parseEngineVolumeInput('20'), 20);
    expect(parseEngineVolumeInput('50cc'), 50);
    expect(parseEngineVolumeInput('80 куб. см'), 80);
    expect(parseEngineVolumeInput('300 куб. см'), 300);
    expect(parseEngineVolumeInput('2.2'), 2.2);
    expect(parseEngineVolumeInput('6.2L'), 6.2);
  });

  test('engine volume formatter shows cc and liters correctly', () {
    expect(formatEngineVolume(300), '300 куб. см');
    expect(formatEngineVolume(80), '80 куб. см');
    expect(formatEngineVolume(2.2), '2.2 л');
    expect(formatEngineVolume(6.2), '6.2 л');
  });
}
