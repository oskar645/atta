import 'package:atta/src/models/car_specs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('car specs omit optional engine and power when absent', () {
    const car = CarSpecs(
      brand: 'Toyota',
      model: 'Camry',
      generation: '',
      year: 2020,
      mileageKm: 10000,
      bodyType: 'Седан',
      fuel: 'Бензин',
      transmission: 'Автомат',
      drive: 'Передний',
      condition: 'Не битый',
      color: 'Чёрный',
    );

    final map = car.toMap();

    expect(map.containsKey('engineVolume'), isFalse);
    expect(map.containsKey('powerHp'), isFalse);
  });

  test('car specs keep missing engine and power as null', () {
    final car = CarSpecs.fromAny(<String, dynamic>{
      'brand': 'Toyota',
      'model': 'Camry',
      'generation': '',
      'year': 2020,
      'mileageKm': 10000,
      'bodyType': 'Седан',
      'fuel': 'Бензин',
      'transmission': 'Автомат',
      'drive': 'Передний',
      'condition': 'Не битый',
      'color': 'Чёрный',
    });

    expect(car, isNotNull);
    expect(car!.engineVolume, isNull);
    expect(car.powerHp, isNull);
  });
}
