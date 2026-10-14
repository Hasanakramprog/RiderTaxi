# Backend Specification: Supporting `bike` and `female` Car Types in Driver Dispatch

> **Target File:** [`functions/findNearbyDrivers.js`](file:///Users/macbook/Desktop/rider/functions/findNearbyDrivers.js)  
> **Related Files:** [`firestore.indexes.json`](file:///Users/macbook/Desktop/rider/firestore.indexes.json), [`lib/models/car_type.dart`](file:///Users/macbook/Desktop/rider/lib/models/car_type.dart), [`lib/screens/trip_request_screen_pro.dart`](file:///Users/macbook/Desktop/rider/lib/screens/trip_request_screen_pro.dart)  
> **Status:** Specification Ready for Implementation  
> **Date:** October 2026  

---

## 1. Executive Summary

The Rider App has expanded its ride tier offerings in the booking interface to include:
1. **`bike`**: A fast, low-cost two-wheeler tier (multiplier `0.65x`, single seat).
2. **`female`**: A dedicated Women-for-Women ride tier featuring female drivers (multiplier `1.0x`, 4 seats, hijab badge `🧕`).

Currently, the Cloud Function [`functions/findNearbyDrivers.js`](file:///Users/macbook/Desktop/rider/functions/findNearbyDrivers.js) is designed around 3 legacy car types: `standard`, `xl`, and `vip`. Trips created with `bike` or `female` temporarily fallback to `carType: 'standard'` on the backend.

This document provides the complete, production-ready specification and code modifications required to update [`findNearbyDrivers.js`](file:///Users/macbook/Desktop/rider/functions/findNearbyDrivers.js), the Firestore data model, composite indexes, and driver FCM push notifications.

---

## 2. Dispatch Matching Matrix

| Requested Ride Tier | `tripData.requestedCarType` | `tripData.carType` | `tripData.driverGenderPreference` | Matching Driver Criteria in Firestore |
| :--- | :--- | :--- | :--- | :--- |
| **Bike** | `'bike'` | `'bike'` | `'any'` | `isOnline == true` AND `isAvailable == true` AND `walletCanWork == true` AND `carType == 'bike'` |
| **Female** | `'female'` | `'female'` (or `'standard'`) | `'female'` | `isOnline == true` AND `isAvailable == true` AND `walletCanWork == true` AND `gender == 'female'` AND `carType in ['standard', 'female']` |
| **Standard** | `'standard'` | `'standard'` | `'any'` | `isOnline == true` AND `isAvailable == true` AND `walletCanWork == true` AND `carType == 'standard'` |
| **XL** | `'xl'` | `'xl'` | `'any'` | `isOnline == true` AND `isAvailable == true` AND `walletCanWork == true` AND `carType == 'xl'` |
| **VIP** | `'vip'` | `'vip'` | `'any'` | `isOnline == true` AND `isAvailable == true` AND `walletCanWork == true` AND `carType == 'vip'` |

---

## 3. Detailed Logic & Edge Case Design

### 3.1. `bike` Vehicle Matching
- **Driver Query:** Drivers registered with two-wheelers must have `drivers.carType = 'bike'` in their profile.
- **Search Radius:** Default radius is `5 km`. For bikes in dense urban areas, the 5 km radius is maintained to allow rapid pickups.
- **Fare Allowance:** The wallet buffer check uses `tripData.fare` (which already reflects the `0.65x` multiplier), automatically adjusting driver wallet deduction thresholds without code changes in `walletCore.js`.
- **FCM Notification:** The push notification body identifies the trip as a bike pickup: `🛵 New Bike Trip Request`.

### 3.2. `female` Ride Tier Matching
- **Driver Query:**
  - A rider booking the `female` tier requires a **female driver**.
  - In Firestore, female drivers have `gender: 'female'` in their `drivers` document.
  - Female drivers typically drive standard passenger vehicles (`carType: 'standard'` or `carType: 'female'`).
  - Therefore, the Cloud Function checks:
    ```javascript
    if (tripData.requestedCarType === "female" || tripData.driverGenderPreference === "female") {
      // Must match verified female drivers
      driversQuery = driversQuery.where("gender", "==", "female");
    }
    ```
- **Vehicle compatibility for Female tier:**
  - If a driver is female and has `carType: 'standard'` or `carType: 'female'`, she is eligible.
  - In-memory post-filtering ensures male drivers are never dispatched for a female-tier trip under any circumstances.
- **FCM Notification:**
  - Includes `🧕 Women Trip Request` in notification title/body, so the driver knows it is a women-only booking.

---

## 4. Code Changes for `functions/findNearbyDrivers.js`

### 4.1. Define Supported Vehicle Types & Helpers

Add at the top of [`functions/findNearbyDrivers.js`](file:///Users/macbook/Desktop/rider/functions/findNearbyDrivers.js):

```javascript
/**
 * Supported vehicle classes in the dispatch system.
 */
const VEHICLE_TYPES = Object.freeze({
  BIKE: "bike",
  STANDARD: "standard",
  FEMALE: "female",
  XL: "xl",
  VIP: "vip",
});

const GENDER = Object.freeze({
  ANY: "any",
  FEMALE: "female",
  MALE: "male",
});
```

---

### 4.2. Update `driversQuery` Construction in `findDriversForTrip`

Replace lines 216–228 in [`functions/findNearbyDrivers.js`](file:///Users/macbook/Desktop/rider/functions/findNearbyDrivers.js):

#### Before:
```javascript
    // 2. Query for available drivers with walletCanWork == true
    let driversQuery = db.collection("drivers")
      .where("isOnline", "==", true)
      .where("isAvailable", "==", true)
      .where("walletCanWork", "==", true);


    // If carType filter is present on trip
    if (tripData.carType) {
      driversQuery = driversQuery.where("carType", "==", tripData.carType);
    }

    const driversSnapshot = await driversQuery.get();
```

#### After (Proposed):
```javascript
    // 2. Query for available drivers with walletCanWork == true
    let driversQuery = db.collection("drivers")
      .where("isOnline", "==", true)
      .where("isAvailable", "==", true)
      .where("walletCanWork", "==", true);

    const isFemaleRequested =
      tripData.requestedCarType === VEHICLE_TYPES.FEMALE ||
      tripData.driverGenderPreference === GENDER.FEMALE;

    const isBikeRequested =
      tripData.requestedCarType === VEHICLE_TYPES.BIKE ||
      tripData.carType === VEHICLE_TYPES.BIKE;

    if (isFemaleRequested) {
      // 👩‍🦰 Prioritize indexed query on gender for women-only trips
      driversQuery = driversQuery.where("gender", "==", GENDER.FEMALE);
    } else if (isBikeRequested) {
      // 🛵 Only two-wheeler drivers
      driversQuery = driversQuery.where("carType", "==", VEHICLE_TYPES.BIKE);
    } else if (tripData.carType) {
      // 🚗 Standard, XL, or VIP
      driversQuery = driversQuery.where("carType", "==", tripData.carType);
    }

    const driversSnapshot = await driversQuery.get();
```

---

### 4.3. In-Memory Guard & Compatibility Filter

In section `candidatesInRadius` filter (lines 243–267), add a safety assertion to ensure strict matching:

```javascript
    driversSnapshot.forEach((doc) => {
      const driverData = doc.data();
      const driverId = doc.id;

      // ── Safety Guard: Ensure female trip receives ONLY female drivers ──────
      if (isFemaleRequested && driverData.gender !== GENDER.FEMALE) {
        console.warn(`[Dispatch] Driver ${driverId} rejected: Not a female driver for female trip.`);
        return;
      }

      // ── Safety Guard: Ensure bike trip receives ONLY bike drivers ───────────
      if (isBikeRequested && driverData.carType !== VEHICLE_TYPES.BIKE) {
        console.warn(`[Dispatch] Driver ${driverId} rejected: Non-bike driver for bike trip.`);
        return;
      }

      // ── Safety Guard: Female tier vehicle class compatibility ─────────────
      if (isFemaleRequested) {
        const allowedCarTypes = [VEHICLE_TYPES.STANDARD, VEHICLE_TYPES.FEMALE];
        if (driverData.carType && !allowedCarTypes.includes(driverData.carType)) {
          return;
        }
      }

      // Check if driver has valid coordinates
      if (driverData.location &&
        driverData.location.latitude &&
        driverData.location.longitude) {
        const distance = calculateDistance(
          pickupLat,
          pickupLng,
          driverData.location.latitude,
          driverData.location.longitude,
        );

        if (distance <= searchRadius) {
          candidatesInRadius.push({
            driverId,
            driverData,
            distance,
          });
        }
      }
    });
```

---

### 4.4. Update `buildMessage` for Custom Push Notifications

Update [`buildMessage`](file:///Users/macbook/Desktop/rider/functions/findNearbyDrivers.js#L120-L188) to send specific vehicle & gender details to the driver:

```javascript
function buildMessage(driver, tripId, tripData, pickupLat, pickupLng) {
  const requestedType = tripData.requestedCarType || tripData.carType || "standard";
  const isFemaleTrip = tripData.driverGenderPreference === "female" || requestedType === "female";
  const isBikeTrip = requestedType === "bike";

  const messageData = {
    tripId: tripId,
    pickupAddress: tripData.pickup.address || "Unknown location",
    pickupLatitude: pickupLat.toString(),
    pickupLongitude: pickupLng.toString(),
    dropoffAddress: tripData.dropoff.address || "Unknown destination",
    fare: tripData.fare ? tripData.fare.toString() : "0",
    distance: tripData.distance ? tripData.distance.toString() : "0",
    estimatedDuration: tripData.duration ? tripData.duration.toString() : "0",
    expiresIn: "20",
    notificationType: "tripRequest",
    carType: tripData.carType || "standard",
    requestedCarType: requestedType,
    driverGenderPreference: tripData.driverGenderPreference || "any",
    notificationTime: tripData.notificationTime ?
      tripData.notificationTime.toMillis().toString() :
      Date.now().toString(),
  };

  // Dynamic notification title & icon
  let notificationTitle = "New Trip Request";
  if (isBikeTrip) {
    notificationTitle = "🛵 New Bike Trip Request";
  } else if (isFemaleTrip) {
    notificationTitle = "🧕 New Women Trip Request";
  }

  let notificationBody = `New pickup (${driver.distance.toFixed(1)}km away)`;
  if (isBikeTrip) {
    notificationBody = `Bike request • ${driver.distance.toFixed(1)}km away`;
  } else if (isFemaleTrip) {
    notificationBody = `Women ride • ${driver.distance.toFixed(1)}km away`;
  }

  return {
    token: driver.fcmToken,
    notification: {
      title: notificationTitle,
      body: notificationBody,
    },
    data: messageData,
  };
}
```

---

## 5. Firestore Composite Indexes Updates

File: [`firestore.indexes.json`](file:///Users/macbook/Desktop/rider/firestore.indexes.json)

To execute the queries efficiently without runtime index errors, add the following composite indexes for the `drivers` collection:

```json
{
  "indexes": [
    {
      "collectionGroup": "trips",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "userId", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "drivers",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "isOnline", "order": "ASCENDING" },
        { "fieldPath": "isAvailable", "order": "ASCENDING" },
        { "fieldPath": "walletCanWork", "order": "ASCENDING" },
        { "fieldPath": "carType", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "drivers",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "isOnline", "order": "ASCENDING" },
        { "fieldPath": "isAvailable", "order": "ASCENDING" },
        { "fieldPath": "walletCanWork", "order": "ASCENDING" },
        { "fieldPath": "gender", "order": "ASCENDING" }
      ]
    }
  ],
  "fieldOverrides": []
}
```

---

## 6. Client Model Alignment: `lib/models/car_type.dart`

Once the backend supports `bike` and `female`, update [`lib/models/car_type.dart`](file:///Users/macbook/Desktop/rider/lib/models/car_type.dart) so the rider app and driver app share the unified constants:

```dart
class CarType {
  static const String bike = 'bike';
  static const String standard = 'standard';
  static const String female = 'female';
  static const String xl = 'xl';
  static const String vip = 'vip';

  static const List<String> ids = [bike, standard, female, xl, vip];
  static const String defaultId = standard;
  ...
}
```

---

## 7. Migration Checklist for Implementation

- [x] **Step 1: Update `firestore.indexes.json`**:
  Added composite indexes for `drivers` on `(isOnline, isAvailable, walletCanWork, carType)` and `(isOnline, isAvailable, walletCanWork, gender)`.
  Ready for deployment with `firebase deploy --only firestore:indexes`.

- [x] **Step 2: Update `functions/findNearbyDrivers.js`**:
  1. Added `VEHICLE_TYPES` and `GENDER` constants.
  2. Implemented conditional query branching for `bike` and `female`.
  3. Added in-memory verification guards in candidate filtering.
  4. Enriched `buildMessage` with `requestedCarType`, `driverGenderPreference`, and contextual notification text.
  Ready for deployment with `firebase deploy --only functions:findNearbyDrivers,functions:refreshNearbyDriversSearch`.

- [x] **Step 3: Update `lib/models/car_type.dart`**:
  Added `bike` and `female` to `CarType.ids` and `CarType.all`, and updated unit test suite (`test/car_type_test.dart` passing 5/5 tests).

- [ ] **Step 4: Firebase Deployment & End-to-End Verification**:
  1. Deploy indexes and functions to Firebase (`firebase deploy`).
  2. Request a **Bike** trip from the rider app $\rightarrow$ verify only drivers with `carType: 'bike'` receive the FCM push.
  3. Request a **Female** trip (🧕) $\rightarrow$ verify only drivers with `gender: 'female'` receive the FCM push.
  4. Request a **Standard** trip $\rightarrow$ verify standard dispatch proceeds as normal.
