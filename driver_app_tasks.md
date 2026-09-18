# Driver App — Critical Backend Integration Tasks

> **For AI Agents / Developers**: This guide contains two mandatory updates required in the **Driver App** to integrate with the new parallel broadcast dispatch and geohash spatial query system.
> Follow the exact field names, transaction patterns, and logic provided below.

---

## 📋 System Context

In the dispatch overhaul:
1. **Parallel Notification (Task 1 in Backend)**: Cloud Functions now notify the top 3 drivers simultaneously instead of one by one.
2. **Atomic Claiming**: The trip document in Firestore has `claimedByDriverId: null`. The first driver to accept must claim the trip atomically.
3. **Geohash Search (Task 8 in Backend)**: Cloud Functions will query nearby drivers using Geohash bounding boxes (`geofire-common`) rather than scanning all drivers in Firestore. The Driver App must write a `geohash` field with every GPS location update.

---

## 🎯 Task 1 — Atomic Trip Acceptance with Firestore Transaction

### Objective
Prevent race conditions when multiple drivers tap **"Accept"** at the exact same moment. Exactly **one driver** must win the trip; any late driver must receive an immediate notification that the trip was already claimed.

### Firestore Document Structure (`trips/{tripId}`)
Before acceptance:
```json
{
  "status": "driver_notified",
  "notifiedDriverIds": ["driver_1", "driver_2", "driver_3"],
  "claimedByDriverId": null
}
```

After winning driver accepts:
```json
{
  "status": "driver_accepted",
  "driverId": "<winning_driver_id>",
  "claimedByDriverId": "<winning_driver_id>",
  "acceptedAt": "SERVER_TIMESTAMP"
}
```

### Implementation (Flutter / Dart)

Locate the `acceptTrip` method in the Driver App (usually in `trip_provider.dart`, `driver_service.dart`, or the incoming ride dialog/screen).

Replace any simple `.update()` call with a **Firestore Transaction**:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

class TripAlreadyClaimedException implements Exception {
  final String message;
  TripAlreadyClaimedException([this.message = 'This trip has already been claimed by another driver.']);
  
  @override
  String toString() => message;
}

Future<bool> acceptTripWithTransaction({
  required String tripId,
  required String driverId,
  Map<String, dynamic>? driverInfo, // Optional: Driver name, phone, photo, vehicle, rating
}) async {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final DocumentReference tripRef = firestore.collection('trips').doc(tripId);

  try {
    await firestore.runTransaction((transaction) async {
      final DocumentSnapshot tripSnapshot = await transaction.get(tripRef);

      if (!tripSnapshot.exists) {
        throw Exception('Trip does not exist or has been cancelled.');
      }

      final data = tripSnapshot.data() as Map<String, dynamic>?;
      if (data == null) {
        throw Exception('Invalid trip data.');
      }

      // Check if another driver already claimed it
      if (data['claimedByDriverId'] != null) {
        throw TripAlreadyClaimedException('Trip already claimed by another driver.');
      }

      // Check if trip was cancelled by rider
      if (data['status'] == 'cancelled') {
        throw Exception('Trip was cancelled by the passenger.');
      }

      // Prepare updates
      final Map<String, dynamic> updates = {
        'status': 'driver_accepted',
        'driverId': driverId,
        'claimedByDriverId': driverId,
        'acceptedAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      if (driverInfo != null) {
        updates['driverInfo'] = driverInfo;
      }

      // Atomically write claim
      transaction.update(tripRef, updates);
    });

    // Successfully claimed
    return true;

  } on TripAlreadyClaimedException catch (e) {
    // Another driver won the race
    print('Trip $tripId was already claimed: $e');
    return false;
  } catch (e) {
    // General network or transaction error
    print('Failed to accept trip: $e');
    rethrow;
  }
}
```

### UI Handling in Driver App
When calling `acceptTripWithTransaction`:

```dart
void onAcceptPressed(String tripId, String driverId) async {
  showLoadingDialog();

  try {
    final bool wonTrip = await acceptTripWithTransaction(
      tripId: tripId,
      driverId: driverId,
      driverInfo: currentDriverData,
    );

    hideLoadingDialog();

    if (wonTrip) {
      // 1. Close ride offer dialog
      Navigator.of(context).pop();
      // 2. Navigate to active trip / navigation screen
      Navigator.pushNamed(context, '/active_trip', arguments: tripId);
    } else {
      // Show polite message that another driver took it
      Navigator.of(context).pop(); // dismiss request dialog
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Another driver accepted this ride first.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  } catch (e) {
    hideLoadingDialog();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not accept trip: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}
```

### Acceptance Criteria for Task 1:
- [ ] `claimedByDriverId` is evaluated inside a `runTransaction` block before write.
- [ ] If `claimedByDriverId != null`, transaction halts and does NOT overwrite.
- [ ] Driver app UI shows a friendly notification ("Another driver accepted first") without crashing.
- [ ] On success, `claimedByDriverId`, `driverId`, and `status: "driver_accepted"` are written together.

---

## 🎯 Task 2 — Write `geohash` on Driver GPS Updates

### Objective
To enable fast, low-cost spatial bounding box queries in Firebase Cloud Functions (`geofire-common`), every location update written by the Driver App must include an accurate **geohash string** (precision 9).

### Firestore Document Structure (`drivers/{driverId}`)
```json
{
  "isOnline": true,
  "isAvailable": true,
  "geohash": "9q8yyk2k5",
  "location": {
    "latitude": 37.7749,
    "longitude": -122.4194
  },
  "lastLocationUpdate": "SERVER_TIMESTAMP"
}
```
> **Important**: The field name must be exactly `geohash` (lowercase) at the root of the document, matching the composite index in Firestore.

---

### Step 1: Add Geohash Utility (Zero Dependencies)
Create a new file `lib/utils/geohash_util.dart` in the Driver App. This pure-Dart implementation has **no external dependencies** and works reliably on all Flutter versions:

```dart
/// Pure Dart Geohash encoder
class GeohashUtil {
  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  /// Encodes latitude and longitude into a geohash string.
  /// Default precision is 9 (~4.8 meters accuracy).
  static String encode(double latitude, double longitude, {int precision = 9}) {
    double minLat = -90.0, maxLat = 90.0;
    double minLng = -180.0, maxLng = 180.0;

    final StringBuffer buffer = StringBuffer();
    bool isEven = true;
    int bit = 0;
    int ch = 0;

    while (buffer.length < precision) {
      if (isEven) {
        final double mid = (minLng + maxLng) / 2;
        if (longitude >= mid) {
          ch |= (1 << (4 - bit));
          minLng = mid;
        } else {
          maxLng = mid;
        }
      } else {
        final double mid = (minLat + maxLat) / 2;
        if (latitude >= mid) {
          ch |= (1 << (4 - bit));
          minLat = mid;
        } else {
          maxLat = mid;
        }
      }

      isEven = !isEven;
      if (bit < 4) {
        bit++;
      } else {
        buffer.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }

    return buffer.toString();
  }
}
```

---

### Step 2: Update Driver Location Service / Background Tracker

Locate where the Driver App writes location to Firestore (e.g., `location_service.dart`, `driver_provider.dart`, or GPS background task).

Update the write operation to compute and store the `geohash`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/geohash_util.dart'; // import the utility above

Future<void> updateDriverLocation({
  required String driverId,
  required double latitude,
  required double longitude,
  double? heading,
  double? speed,
}) async {
  // Generate precision-9 geohash
  final String geohash = GeohashUtil.encode(latitude, longitude, precision: 9);

  final Map<String, dynamic> updateData = {
    'geohash': geohash, // <-- REQUIRED FOR CLOUD FUNCTION SPATIAL SEARCH
    'location': {
      'latitude': latitude,
      'longitude': longitude,
    },
    'lastLocationUpdate': FieldValue.serverTimestamp(),
  };

  if (heading != null) updateData['heading'] = heading;
  if (speed != null) updateData['speed'] = speed;

  await FirebaseFirestore.instance
      .collection('drivers')
      .doc(driverId)
      .update(updateData);
}
```

If using `SetOptions(merge: true)`:
```dart
await FirebaseFirestore.instance
    .collection('drivers')
    .doc(driverId)
    .set(updateData, SetOptions(merge: true));
```

### Acceptance Criteria for Task 2:
- [ ] `lib/utils/geohash_util.dart` is added to the driver project.
- [ ] Every GPS location update writes `geohash` at the root of `drivers/{driverId}`.
- [ ] The `geohash` length is 9 characters (e.g., `9q8yyk2k5`).
- [ ] Location updates continue to update `location.latitude` and `location.longitude` alongside `geohash`.

---

## 🔍 Verification Checklist for Driver App AI Agent

| Step | Action | Expected Outcome |
|---|---|---|
| 1 | Test Geohash utility with test coordinates `(37.7749, -122.4194)` | Returns `9q8yyk2k5` (first 9 chars) |
| 2 | Trigger a GPS location update in Driver App | Check Firestore `drivers/{driverId}` document; verify `geohash` field exists |
| 3 | Simulate 2 drivers accepting the same trip at once | Driver 1 succeeds (`driver_accepted`); Driver 2 receives `TripAlreadyClaimedException` and orange SnackBar |
