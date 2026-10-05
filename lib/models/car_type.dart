import 'package:flutter/material.dart';

/// Single source of truth for car types.
/// ⚠️ These ids are also used by:
///   - the driver app (lib/models/vehicle_type.dart)
///   - the Cloud Function findNearbyDrivers.js (VEHICLE_TYPES)
/// and are stored in Firestore as `trips.carType` and `drivers.carType`.
/// Never rename an id without updating all three places and migrating data.
class CarType {
  static const String standard = 'standard';
  static const String xl = 'xl';
  static const String vip = 'vip';

  static const List<String> ids = [standard, xl, vip];
  static const String defaultId = standard;

  final String id;
  final String name;
  final IconData icon;
  final String capacity;
  final double priceMultiplier;

  const CarType({
    required this.id,
    required this.name,
    required this.icon,
    required this.capacity,
    required this.priceMultiplier,
  });

  static const List<CarType> all = [
    CarType(
      id: standard,
      name: 'Standard',
      icon: Icons.directions_car,
      capacity: '4 seats',
      priceMultiplier: 1.0,
    ),
    CarType(
      id: xl,
      name: 'XL',
      icon: Icons.airport_shuttle,
      capacity: '6 seats',
      priceMultiplier: 1.5,
    ),
    CarType(
      id: vip,
      name: 'VIP',
      icon: Icons.electric_car,
      capacity: '4 seats',
      priceMultiplier: 2.0,
    ),
  ];

  /// Returns the matching CarType, or [standard] if the id is unknown.
  static CarType byId(String? id) =>
      all.firstWhere((c) => c.id == id, orElse: () => all.first);
}
