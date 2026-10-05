import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_auth_app/models/car_type.dart';

void main() {
  group('CarType Constants & IDs', () {
    test('car type string values match expected values', () {
      expect(CarType.standard, 'standard');
      expect(CarType.xl, 'xl');
      expect(CarType.vip, 'vip');
      expect(CarType.defaultId, 'standard');
    });

    test('ids list contains all car types in order', () {
      expect(CarType.ids, ['standard', 'xl', 'vip']);
    });
  });

  group('CarType.all specifications', () {
    test('contains 3 vehicle types with exact properties', () {
      expect(CarType.all.length, 3);

      final standard = CarType.all[0];
      expect(standard.id, 'standard');
      expect(standard.name, 'Standard');
      expect(standard.icon, Icons.directions_car);
      expect(standard.capacity, '4 seats');
      expect(standard.priceMultiplier, 1.0);

      final xl = CarType.all[1];
      expect(xl.id, 'xl');
      expect(xl.name, 'XL');
      expect(xl.icon, Icons.airport_shuttle);
      expect(xl.capacity, '6 seats');
      expect(xl.priceMultiplier, 1.5);

      final vip = CarType.all[2];
      expect(vip.id, 'vip');
      expect(vip.name, 'VIP');
      expect(vip.icon, Icons.electric_car);
      expect(vip.capacity, '4 seats');
      expect(vip.priceMultiplier, 2.0);
    });
  });

  group('CarType.byId resolution', () {
    test('resolves known ids properly', () {
      expect(CarType.byId('standard').id, 'standard');
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
