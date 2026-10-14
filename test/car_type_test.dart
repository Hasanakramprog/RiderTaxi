import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_auth_app/models/car_type.dart';

void main() {
  group('CarType Constants & IDs', () {
    test('car type string values match expected values', () {
      expect(CarType.bike, 'bike');
      expect(CarType.standard, 'standard');
      expect(CarType.female, 'female');
      expect(CarType.xl, 'xl');
      expect(CarType.vip, 'vip');
      expect(CarType.defaultId, 'standard');
    });

    test('ids list contains all car types in order', () {
      expect(CarType.ids, ['bike', 'standard', 'female', 'xl', 'vip']);
    });
  });

  group('CarType.all specifications', () {
    test('contains 5 vehicle types with exact properties', () {
      expect(CarType.all.length, 5);

      final bike = CarType.all[0];
      expect(bike.id, 'bike');
      expect(bike.name, 'Bike');
      expect(bike.icon, Icons.two_wheeler);
      expect(bike.capacity, '1 seat');
      expect(bike.priceMultiplier, 0.65);

      final standard = CarType.all[1];
      expect(standard.id, 'standard');
      expect(standard.name, 'Standard');
      expect(standard.icon, Icons.directions_car);
      expect(standard.capacity, '4 seats');
      expect(standard.priceMultiplier, 1.0);

      final female = CarType.all[2];
      expect(female.id, 'female');
      expect(female.name, 'Female');
      expect(female.icon, Icons.face_3);
      expect(female.capacity, '4 seats');
      expect(female.priceMultiplier, 1.0);

      final xl = CarType.all[3];
      expect(xl.id, 'xl');
      expect(xl.name, 'XL');
      expect(xl.icon, Icons.airport_shuttle);
      expect(xl.capacity, '6 seats');
      expect(xl.priceMultiplier, 1.5);

      final vip = CarType.all[4];
      expect(vip.id, 'vip');
      expect(vip.name, 'VIP');
      expect(vip.icon, Icons.electric_car);
      expect(vip.capacity, '4 seats');
      expect(vip.priceMultiplier, 2.0);
    });
  });

  group('CarType.byId resolution', () {
    test('resolves known ids properly', () {
      expect(CarType.byId('bike').id, 'bike');
      expect(CarType.byId('standard').id, 'standard');
      expect(CarType.byId('female').id, 'female');
      expect(CarType.byId('xl').id, 'xl');
      expect(CarType.byId('vip').id, 'vip');
    });

    test('falls back to default (standard) for unknown or null ids', () {
      expect(CarType.byId(null).id, CarType.standard);
      expect(CarType.byId('invalid_car_type').id, CarType.standard);
      expect(CarType.byId('').id, CarType.standard);
    });
  });
}
