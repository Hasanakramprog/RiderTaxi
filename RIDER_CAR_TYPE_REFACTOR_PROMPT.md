# 🔧 Refactor Task (Rider App): Centralize Car Type IDs

> Scope: **rider app only**. This is a **behavior-neutral refactor**. After it, the app must work exactly as before, and the data written to Firestore must be identical.

---

## 1. Why

The car type ids (`standard`, `xl`, `vip`) are currently typed by hand inside `trip_request_screen_pro.dart`. The same ids are also used by the driver app and by the Cloud Function `findNearbyDrivers`, which matches `trips.carType` against `drivers.carType`.

If anyone changes an id on the rider side (`'vip'` → `'premium'`, `'xl'` → `'XL'`), the app still works, but dispatch silently stops matching (the Cloud Function falls back to no filter for unknown types). A single source of truth makes this impossible to do by accident.

## 2. Goal

- Define the car type ids **once** in the rider app.
- Make `trip_request_screen_pro.dart` use that definition instead of raw strings.
- **Do not change** any id value, label, price multiplier, icon, UI, fare calculation, or the Firestore payload.

---

## 3. Current State (where the ids appear)

All in `trip_request_screen_pro.dart`:

| Line (approx.) | Code |
|---|---|
| 32 | `String _selectedCarType = 'standard';` |
| 39 – 60 | `final List<Map<String, dynamic>> _carTypes = [ {'id': 'standard', ...}, {'id': 'xl', ...}, {'id': 'vip', ...} ];` |
| 940 – 942, 1267 – 1269 | `_carTypes.firstWhere((c) => c['id'] == _selectedCarType, orElse: () => _carTypes[0])` |
| 1056 – 1065 | UI list built from `_carTypes` and selection by `car['id']` |
| 1279 | `'carType': _selectedCarType,` written into the trip document |

First, **grep the whole rider app** for `'standard'`, `'xl'`, `'vip'`, `carType` and `_carTypes` and handle every other usage you find (other screens, providers, `FirestoreProvider`, tracking screens). Report what you found.

---

## 4. Required Changes

### 4.1 New file: `lib/models/car_type.dart`

Keep it small and `const`:

```dart
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
    CarType(id: standard, name: 'Standard', icon: Icons.directions_car,
        capacity: '4 seats', priceMultiplier: 1.0),
    CarType(id: xl, name: 'XL', icon: Icons.airport_shuttle,
        capacity: '6 seats', priceMultiplier: 1.5),
    CarType(id: vip, name: 'VIP', icon: Icons.electric_car,
        capacity: '4 seats', priceMultiplier: 2.0),
  ];

  /// Returns the matching CarType, or [standard] if the id is unknown.
  static CarType byId(String? id) =>
      all.firstWhere((c) => c.id == id, orElse: () => all.first);
}
```

(Match the values exactly to the current `_carTypes` list: names, icons, capacities, multipliers. If the current file differs from what is shown here, the current file wins.)

### 4.2 Edit `trip_request_screen_pro.dart`

1. Import the new file.
2. Line 32: `String _selectedCarType = CarType.defaultId;`
3. **Remove** the local `_carTypes` list.
4. Replace both `firstWhere` blocks (around lines 940 and 1267) with `CarType.byId(_selectedCarType)`, and use `selCar.priceMultiplier` instead of `selCar['price'] as double`.
5. In the car list UI (around lines 1056 – 1110): iterate `CarType.all`, and read `car.id`, `car.name`, `car.icon`, `car.capacity`, `car.priceMultiplier` instead of map keys (`car['id']`, `car['name']`...). Keep the exact same widgets and styling. Update `farePreview` to use the multiplier field.
6. Line 1279: keep `'carType': _selectedCarType,`. It already holds the id string.

### 4.3 Other usages
Update any other file found in step 3 to use `CarType` constants. Do not change a screen's behavior while doing so.

---

## 5. Safety Net (small, recommended)

Right before the trip document is created (inside the existing `try`, before `fp.createTrip(tripData)`), add a guard so a bad value never reaches Firestore:

```dart
assert(CarType.ids.contains(_selectedCarType),
    'Invalid carType: $_selectedCarType');
```

Do not add user-facing errors for this. It is a developer-time check.

---

## 6. Do NOT

- Do not rename any id, change the Firestore field name `carType`, or change the data type.
- Do not change fare math, stop or waiting charges, the `searchStartedAt` field, or navigation.
- Do not restyle the vehicle picker UI.
- Do not touch the driver app or Cloud Function in this task.

---

## 7. Acceptance Criteria

- [ ] No raw `'standard'`, `'xl'`, `'vip'` string literals remain in the rider app outside `car_type.dart`.
- [ ] `_carTypes` no longer exists in `trip_request_screen_pro.dart`.
- [ ] The vehicle picker looks and behaves exactly as before (same order, labels, icons, selection, fare preview).
- [ ] A created trip document contains `carType` with the same value as before for each type, and the same fare.
- [ ] `flutter analyze` is clean, and the app builds for iOS and Android.

## 8. Test Checklist

- Open the trip request screen and confirm all 3 types show with the correct icons and capacities.
- For one trip, compare the fare preview of Standard, XL and VIP with the values before the refactor (multipliers 1.0 / 1.5 / 2.0).
- Create a trip with each type and check the `trips` document in Firestore: `carType` is `standard`, `xl` or `vip` and the fare matches the preview.
- Confirm the default selection is Standard when the screen opens.
