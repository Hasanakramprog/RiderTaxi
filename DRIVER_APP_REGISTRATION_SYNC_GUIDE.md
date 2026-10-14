# Driver App Integration Guide: Adding `carType` & `gender` to Driver Registration

> **For Driver App Developers & AI Agents**  
> **Target App:** Driver Mobile Application (Flutter / Dart)  
> **Backend Integration:** Cloud Functions ([`functions/findNearbyDrivers.js`](file:///Users/macbook/Desktop/rider/functions/findNearbyDrivers.js)), Firestore (`drivers` collection)  
> **Status:** Specification & Implementation Guide Ready  
> **Date:** October 2026  

---

## 1. Executive Summary & Purpose

The **Rider App** and **Cloud Function dispatch system** have introduced two new trip categories:
1. **`bike` (Two-Wheelers / Motorcycles / Scooters)**: Fast, single-passenger rides.
2. **`female` (Women-Only Rides 🧕)**: Safe, dedicated rides matching female passengers exclusively with **female drivers**.

To enable dispatching to the correct drivers, the **Driver App registration and onboarding flow** must capture and persist two mandatory attributes in the `drivers/{driverId}` Firestore document:
- **`gender`**: `'female'` | `'male'`
- **`carType`**: `'bike'` | `'standard'` | `'xl'` | `'vip'` (or `'female'`)

If these fields are missing or not synchronized:
- Motorbike drivers will receive car trips (or never receive bike requests).
- Female passengers booking Women-only rides will not find eligible drivers.
- Male drivers will be rejected by Cloud Function safety guards.

---

## 2. Firestore Document Specification (`drivers/{driverId}`)

When a driver completes registration (or updates their vehicle profile), the document must contain these exact fields:

```json
{
  "driverId": "DRV_123456",
  "displayName": "Sarah Ahmed",
  "phoneNumber": "+966501234567",
  "email": "sarah@example.com",
  
  // ── 1. GENDER ATTRIBUTE (REQUIRED) ─────────────────────────────────────────
  "gender": "female",            // "female" | "male"
  "isFemaleVerified": true,      // Set to true after KYC or national ID check
  "acceptsFemaleTrips": true,    // Defaults to true for female drivers
  
  // ── 2. VEHICLE CLASS ATTRIBUTE (REQUIRED) ──────────────────────────────────
  "carType": "standard",         // "bike" | "standard" | "xl" | "vip" | "female"
  
  // ── 3. DETAILED VEHICLE METADATA (RECOMMENDED) ─────────────────────────────
  "vehicleDetails": {
    "category": "car",           // "car" | "bike"
    "make": "Toyota",            // e.g. "Toyota", "Honda", "Yamaha"
    "model": "Camry",            // e.g. "Camry", "NMAX", "Hiace"
    "year": 2022,
    "color": "White",
    "plateNumber": "ABC 1234",
    "seats": 4
  },
  
  // ── 4. DISPATCH FLAGS (EXISTING) ───────────────────────────────────────────
  "isOnline": true,
  "isAvailable": true,
  "walletCanWork": true,
  "location": {
    "latitude": 24.7136,
    "longitude": 46.6753
  },
  "geohash": "thrr0w123",
  "fcmToken": "eX_ample_token...",
  "updatedAt": "SERVER_TIMESTAMP"
}
```

---

## 3. Vehicle Type & Gender Constants (Dart Model)

Create or update `lib/models/vehicle_type.dart` in the **Driver App**:

```dart
import 'package:flutter/material.dart';

/// Supported vehicle classes matching backend and rider app.
class VehicleType {
  static const String bike = 'bike';
  static const String standard = 'standard';
  static const String xl = 'xl';
  static const String vip = 'vip';
  static const String female = 'female';

  static const List<String> all = [bike, standard, xl, vip];

  static String getLabel(String type) {
    switch (type) {
      case bike:
        return 'Motorcycle / Bike (دراجة نارية)';
      case standard:
        return 'Standard Sedan (سيارة اقتصادية)';
      case xl:
        return 'XL Family Van (عائلية 6+ ركاب)';
      case vip:
        return 'VIP Luxury (فاخرة VIP)';
      case female:
        return 'Women Ride (سيدات)';
      default:
        return 'Standard';
    }
  }

  static IconData getIcon(String type) {
    switch (type) {
      case bike:
        return Icons.two_wheeler;
      case standard:
        return Icons.directions_car;
      case xl:
        return Icons.airport_shuttle;
      case vip:
        return Icons.electric_car;
      default:
        return Icons.directions_car;
    }
  }
}

/// Driver gender values.
class DriverGender {
  static const String female = 'female';
  static const String male = 'male';

  static const List<String> all = [female, male];

  static String getLabel(String gender) {
    switch (gender) {
      case female:
        return 'Female (أنثى)';
      case male:
        return 'Male (ذكر)';
      default:
        return gender;
    }
  }
}
```

---

## 4. UI Implementation in Driver Registration Flow

Locate the registration screens in the **Driver App** (typically `driver_register_screen.dart`, `vehicle_details_screen.dart`, or `onboarding_flow.dart`).

### 4.1. Step 1: Gender Selector Widget

Add this selector to the personal details step:

```dart
Widget _buildGenderSelector({
  required String selectedGender,
  required ValueChanged<String> onChanged,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Gender / الجنس',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          // Male Option
          Expanded(
            child: _buildGenderCard(
              id: DriverGender.male,
              label: 'Male (ذكر)',
              icon: Icons.male,
              isSelected: selectedGender == DriverGender.male,
              accentColor: const Color(0xFF2196F3),
              onTap: () => onChanged(DriverGender.male),
            ),
          ),
          const SizedBox(width: 12),
          // Female Option
          Expanded(
            child: _buildGenderCard(
              id: DriverGender.female,
              label: 'Female (أنثى)',
              icon: Icons.female,
              isSelected: selectedGender == DriverGender.female,
              accentColor: const Color(0xFFE91E63),
              badge: 'Eligible for Women Rides 🧕',
              onTap: () => onChanged(DriverGender.female),
            ),
          ),
        ],
      ),
    ],
  );
}

Widget _buildGenderCard({
  required String id,
  required String label,
  required IconData icon,
  required bool isSelected,
  required Color accentColor,
  String? badge,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: isSelected ? accentColor.withOpacity(0.15) : const Color(0xFF242424),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? accentColor : Colors.white12,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: isSelected ? accentColor : Colors.grey),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey.shade400,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          if (badge != null && isSelected) ...[
            const SizedBox(height: 4),
            Text(
              badge,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFE91E63),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
```

---

### 4.2. Step 2: Vehicle Class Selector Widget

Add this selector to the vehicle registration step:

```dart
Widget _buildVehicleClassSelector({
  required String selectedCarType,
  required ValueChanged<String> onChanged,
}) {
  final options = [
    {
      'id': VehicleType.bike,
      'name': 'Bike / دباب',
      'icon': Icons.two_wheeler,
      'desc': 'Motorcycle or Scooter (1 rider)',
    },
    {
      'id': VehicleType.standard,
      'name': 'Standard / سيدان',
      'icon': Icons.directions_car,
      'desc': '4-door sedan (Up to 4 riders)',
    },
    {
      'id': VehicleType.xl,
      'name': 'XL / عائلية',
      'icon': Icons.airport_shuttle,
      'desc': 'Van or SUV (6+ riders)',
    },
    {
      'id': VehicleType.vip,
      'name': 'VIP / فاخرة',
      'icon': Icons.electric_car,
      'desc': 'Luxury executive vehicle',
    },
  ];

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Select Vehicle Type / نوع المركبة',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      const SizedBox(height: 10),
      ...options.map((opt) {
        final isSelected = selectedCarType == opt['id'];
        return GestureDetector(
          onTap: () => onChanged(opt['id'] as String),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFFFC107).withOpacity(0.12)
                  : const Color(0xFF242424),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? const Color(0xFFFFC107) : Colors.white12,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  opt['icon'] as IconData,
                  size: 28,
                  color: isSelected ? const Color(0xFFFFC107) : Colors.grey,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        opt['name'] as String,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey.shade300,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        opt['desc'] as String,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Radio<String>(
                  value: opt['id'] as String,
                  groupValue: selectedCarType,
                  activeColor: const Color(0xFFFFC107),
                  onChanged: (val) {
                    if (val != null) onChanged(val);
                  },
                ),
              ],
            ),
          ),
        );
      }),
    ],
  );
}
```

---

## 5. Saving to Firestore (Dart Registration Service)

Update the registration submission logic (e.g., `driver_auth_service.dart` or `driver_profile_service.dart`):

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> completeDriverRegistration({
  required String driverId,
  required String displayName,
  required String phoneNumber,
  required String gender,           // 'female' | 'male'
  required String carType,          // 'bike' | 'standard' | 'xl' | 'vip'
  required String vehicleMake,
  required String vehicleModel,
  required int vehicleYear,
  required String plateNumber,
}) async {
  final isBike = carType == VehicleType.bike;
  final isFemale = gender == DriverGender.female;

  final Map<String, dynamic> driverData = {
    'driverId': driverId,
    'displayName': displayName,
    'phoneNumber': phoneNumber,
    
    // Core Dispatch Fields (Indexed by Cloud Function)
    'gender': gender,
    'carType': carType,
    'isFemaleVerified': isFemale, // or false if manual approval is required
    'acceptsFemaleTrips': isFemale, // Enable women-only trips for female drivers
    
    // Vehicle Details
    'vehicleDetails': {
      'category': isBike ? 'bike' : 'car',
      'make': vehicleMake,
      'model': vehicleModel,
      'year': vehicleYear,
      'plateNumber': plateNumber,
      'seats': isBike ? 1 : (carType == VehicleType.xl ? 6 : 4),
    },
    
    // Default Availability & Status
    'isOnline': false,
    'isAvailable': false,
    'walletCanWork': true,
    'registeredAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  // Write to drivers/{driverId}
  await FirebaseFirestore.instance
      .collection('drivers')
      .doc(driverId)
      .set(driverData, SetOptions(merge: true));
}
```

---

## 6. Incoming Trip Dialog: Displaying Trip Category

When an incoming trip notification (`tripRequest`) arrives, the Driver App receives the FCM payload generated by `findNearbyDrivers.js`:

```json
{
  "tripId": "TRIP_ABC",
  "notificationType": "tripRequest",
  "carType": "bike",
  "requestedCarType": "bike",
  "driverGenderPreference": "any"
}
```

Update the **Incoming Trip Alert Dialog** in the Driver App to highlight special categories:

```dart
Widget _buildTripClassBadge(Map<String, dynamic> tripData) {
  final requestedType = tripData['requestedCarType'] ?? tripData['carType'];
  final genderPref = tripData['driverGenderPreference'];

  if (genderPref == 'female' || requestedType == 'female') {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE91E63).withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE91E63)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🧕', style: TextStyle(fontSize: 14)),
          SizedBox(width: 4),
          Text(
            'Women Only Trip / مشوار سيدات',
            style: TextStyle(
              color: Color(0xFFE91E63),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  if (requestedType == 'bike') {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFC107).withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFC107)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.two_wheeler, size: 16, color: Color(0xFFFFC107)),
          SizedBox(width: 4),
          Text(
            'Bike Pickup / مشوار دراجة نارية',
            style: TextStyle(
              color: Color(0xFFFFC107),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  return const SizedBox.shrink();
}
```

---

## 7. Migration of Existing Drivers

For existing drivers already in Firestore without `gender` or `carType`:
1. **Fallback Default:** If `carType` is missing, treat as `'standard'`.
2. **Profile Edit Prompt:** Show a one-time dialog on app startup:
   > *"Please complete your profile: Select your gender and confirm your vehicle type to receive tailored ride requests."*
3. **Admin Panel / Script:** Run a one-time Firebase Admin script to backfill `gender: 'male'` and `carType: 'standard'` for legacy driver documents that lack them.

---

## 8. Verification & Test Matrix

| Test Scenario | Registered Gender | Registered carType | Rider App Action | Expected Dispatch Result |
|---|---|---|---|---|
| **Bike Matching** | `male` or `female` | `bike` | Rider requests **Bike** | Driver receives `🛵 New Bike Trip Request` FCM notification |
| **Bike Isolation** | `male` | `standard` | Rider requests **Bike** | Driver is **excluded** from dispatch |
| **Women Only Ride** | `female` | `standard` | Rider requests **Female (🧕)** | Driver receives `🧕 New Women Trip Request` FCM notification |
| **Male Driver Safety** | `male` | `standard` | Rider requests **Female (🧕)** | Driver is **strictly excluded** by query & safety guard |
| **Standard Ride** | `female` or `male` | `standard` | Rider requests **Standard** | Both male and female standard drivers are eligible |
