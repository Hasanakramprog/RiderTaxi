# Driver Dispatch System — Improvement Tasks
> **For AI Agents**: This document is a self-contained task list. Each improvement is independent and can be developed separately. Always read the referenced files before making changes. The project is a Flutter + Firebase app located at `d:\coding-repo\taxi-app\taxii-app\taxi_auth_app`.

---

## Project Context

| Item | Detail |
|---|---|
| App Name | Ismail Taxi (Rider App) |
| Flutter version | 3.7.2+ |
| State management | `provider` package |
| Backend | Firebase Cloud Functions (Node.js v2 API) |
| Key files | `lib/providers/map_provider.dart`, `lib/screens/trip_tracking_screen.dart`, `functions/findNearbyDrivers.js` |

---

## Task 1 — Broadcast Driver Notification (Replace Sequential with Parallel)

### Problem
Currently in `functions/findNearbyDrivers.js`, only **one driver** (the top-scored driver) is notified at a time. If that driver doesn't respond within 60 seconds, the next driver is tried — causing worst-case 5-minute waiting times for users.

### Files to Modify
- `functions/findNearbyDrivers.js` — change notification strategy
- `lib/screens/trip_tracking_screen.dart` — update client-side acceptance handling

### Current Behaviour (lines 211-228 in findNearbyDrivers.js)
```js
// OLD: notify only the single top driver
const topDriver = driversWithPriority[0];
await db.collection("trips").doc(tripId).update({
  notifiedDriverId: topDriver.driverId,
  status: "driver_notified",
});
await fcm.send(buildMessage(topDriver));
```

### Target Behaviour
```js
// NEW: notify top 3 drivers simultaneously
const TOP_N = 3;
const topDrivers = driversWithPriority.slice(0, TOP_N);

await db.collection("trips").doc(tripId).update({
  notifiedDriverIds: topDrivers.map(d => d.driverId),  // array of all notified
  claimedByDriverId: null,   // null until one accepts
  status: "driver_notified",
  notificationTime: admin.firestore.FieldValue.serverTimestamp(),
});

// Notify all top drivers in parallel
await Promise.all(topDrivers.map(driver => {
  if (driver.fcmToken) return fcm.send(buildMessage(driver, tripId));
  return Promise.resolve();
}));
```

### Driver App Side (out of scope here, note for driver app agent)
- Driver app shows "Accept / Decline" button
- On accept: write `driverId` and `status: "driver_accepted"` to `trips/{tripId}` using a **Firestore Transaction** to prevent two drivers accepting the same trip simultaneously:
```js
await db.runTransaction(async (tx) => {
  const tripRef = db.collection("trips").doc(tripId);
  const trip = await tx.get(tripRef);
  if (trip.data().claimedByDriverId != null) throw new Error("already claimed");
  tx.update(tripRef, { claimedByDriverId: driverId, status: "driver_accepted" });
});
```

### Flutter Client Change (trip_tracking_screen.dart)
- No logic change needed — client already listens for `driver_accepted` status via the Firestore real-time stream.
- Remove the fallback logic in `_handleDriverTimeout` that tries to notify the "next driver" — the Cloud Function now handles that automatically.

### Acceptance Criteria
- [ ] Top 3 drivers are notified simultaneously via FCM
- [ ] Firestore transaction prevents double-claiming
- [ ] Only first driver to accept gets the trip
- [ ] Other notified drivers see "Trip already taken" if they try to accept late
- [ ] `notifiedDriverIds` array is stored on the trip document

---

## Task 2 — Expanding Search Radius Fallback

### Problem
`findNearbyDrivers.js` uses a **hardcoded 5 km radius**. If no drivers are within 5 km, the trip immediately gets `no_drivers_available` — even if a driver is 6 km away.

### Files to Modify
- `functions/findNearbyDrivers.js` — wrap driver search in a radius loop

### Current Code (line 134)
```js
const searchRadius = 5; // hardcoded, never changes
```

### Target Implementation
```js
// Expanding radius search — try 3km, then 5km, then 8km, then 12km
const SEARCH_RADII_KM = [3, 5, 8, 12];
let driversWithPriority = [];
let usedRadius = 0;

for (const radius of SEARCH_RADII_KM) {
  driversWithPriority = filterAndScoreDrivers(allDrivers, pickupLat, pickupLng, radius);
  if (driversWithPriority.length > 0) {
    usedRadius = radius;
    console.log(`Found ${driversWithPriority.length} drivers within ${radius}km`);
    break;
  }
  console.log(`No drivers within ${radius}km, expanding...`);
}

if (driversWithPriority.length === 0) {
  // Truly no drivers anywhere — mark trip
  await db.collection("trips").doc(tripId).update({ status: "no_drivers_available" });
  return null;
}

// Store the radius used for analytics
await db.collection("trips").doc(tripId).update({ searchRadiusUsed: usedRadius });
```

### Acceptance Criteria
- [ ] Radius expands through `[3, 5, 8, 12]` km in order
- [ ] Stops at the first radius that has ≥ 1 driver
- [ ] `searchRadiusUsed` is stored on the trip document for analytics
- [ ] `no_drivers_available` is only set when all radii are exhausted

---

## Task 3 — Replace Haversine with Google Distance Matrix API for ETA

### Problem
`calculateDistance()` in `findNearbyDrivers.js` uses straight-line (crow-flies) distance. A driver ranked #1 by straight-line distance might actually be slower due to road conditions, traffic, or geography. Driver priority scoring is therefore inaccurate.

### Files to Modify
- `functions/findNearbyDrivers.js` — replace `calculateDistance()` with Distance Matrix API call

### Current Code (lines 34-48 in findNearbyDrivers.js)
```js
function calculateDistance(lat1, lon1, lat2, lon2) {
  // Haversine formula — straight line only
  const R = 6371;
  ...
  return R * c; // km, not ETA
}
```

### Target Implementation
```js
const axios = require("axios"); // add to package.json
const MAPS_API_KEY = process.env.GOOGLE_MAPS_API_KEY; // from Firebase env config

async function getETAMinutes(originLat, originLng, destLat, destLng) {
  try {
    const url = `https://maps.googleapis.com/maps/api/distancematrix/json` +
      `?origins=${originLat},${originLng}` +
      `&destinations=${destLat},${destLng}` +
      `&mode=driving` +
      `&key=${MAPS_API_KEY}`;

    const response = await axios.get(url);
    const element = response.data.rows[0].elements[0];

    if (element.status === "OK") {
      return element.duration.value / 60; // convert seconds to minutes
    }
  } catch (e) {
    console.warn("Distance Matrix API failed, falling back to Haversine", e);
  }
  // Fallback: estimate from Haversine at 30 km/h average
  const dist = calculateDistance(originLat, originLng, destLat, destLng);
  return (dist / 0.5); // 0.5 km/min = 30 km/h
}
```

Replace the Distance Score component in `calculateDriverPriority()`:
```js
// OLD: const distanceScore = Math.max(0, 50 - (distance * 5));
// NEW: ETA-based score — closer ETA = more points (max 50 pts at 0 min)
const etaMinutes = await getETAMinutes(...);
const etaScore = Math.max(0, 50 - (etaMinutes * 2.5)); // 0 min = 50pts, 20 min = 0pts
```

### Environment Variable Setup
Store the API key securely using Firebase Functions config:
```bash
firebase functions:config:set maps.api_key="YOUR_KEY_HERE"
```
Access in code:
```js
const MAPS_API_KEY = process.env.MAPS_API_KEY; // set via Firebase environment
```

### Acceptance Criteria
- [ ] Distance Matrix API is called for each candidate driver
- [ ] ETA in minutes is used instead of straight-line km in the priority score
- [ ] Haversine fallback is used if the API call fails
- [ ] API key is stored in Firebase Functions environment config, NOT hardcoded
- [ ] `etaMinutes` is stored in `nearbyDrivers[]` array on the trip document

---

## Task 4 — Remove Hardcoded Google Maps API Key from Flutter Source

### Problem
The Google Maps API key is **plaintext in source code** in `lib/providers/map_provider.dart` at line 832 and 886:
```dart
String apiKey = "AIzaSyBghYBLMtYdxteEo5GXM6eTdF_8Cc47tis"; // SECURITY RISK
```
This is visible to anyone with repo access and will be flagged by GitHub secret scanning.

### Files to Modify
- `lib/providers/map_provider.dart` — replace hardcoded key with env constant
- `android/app/src/main/AndroidManifest.xml` — may need `MAPS_API_KEY` meta-data
- `.env.example` — document the required variable (already exists in project root)

### Target Implementation

**Step 1**: Replace the hardcoded string in `map_provider.dart`:
```dart
// OLD:
String apiKey = "AIzaSyBghYBLMtYdxteEo5GXM6eTdF_8Cc47tis";

// NEW: loaded from dart-define at build time
static const String apiKey = String.fromEnvironment(
  'GOOGLE_MAPS_API_KEY',
  defaultValue: '', // empty = API calls will fail gracefully
);
```

**Step 2**: Pass the key at build/run time:
```bash
flutter run --dart-define=GOOGLE_MAPS_API_KEY=YOUR_KEY
flutter build apk --dart-define=GOOGLE_MAPS_API_KEY=YOUR_KEY
```

**Step 3**: Update `.env.example` (already exists in project root) to document:
```
GOOGLE_MAPS_API_KEY=your_google_maps_api_key_here
```

**Step 4**: Add to `.gitignore`:
```
# Flutter dart-define env files
.env
*.env.local
```

### Acceptance Criteria
- [ ] No API key string literals exist in any `.dart` files
- [ ] Key is injected via `--dart-define=GOOGLE_MAPS_API_KEY`
- [ ] `.env.example` documents the required variable
- [ ] Build works correctly with the key passed at build time
- [ ] App gracefully handles empty key (shows fallback text addresses)

---

## Task 5 — Remove Redundant 3-Second Manual Polling Timer

### Problem
`TripTrackingScreen` runs **two overlapping update mechanisms simultaneously**:
1. A Firestore **real-time stream** (`_setupTripListener`) — fires instantly on changes
2. A `Timer.periodic(3 seconds)` **manual poll** (`_manualRefreshTripStatus`) — redundant & expensive

This doubles Firestore read costs and can cause the same status update to be handled **twice** by both handlers.

### Files to Modify
- `lib/screens/trip_tracking_screen.dart`

### Current Code to Remove (lines 54-57)
```dart
// REMOVE THIS:
_refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
  _manualRefreshTripStatus();
});
```

### Replacement — Offline Detection Fallback
Only poll if the real-time stream signals it is offline:
```dart
void _setupTripListener() {
  _tripSubscription = FirebaseFirestore.instance
    .collection('trips')
    .doc(widget.tripId)
    .snapshots(includeMetadataChanges: true)
    .listen(
      (snapshot) {
        // Cancel fallback poll if stream recovers
        _fallbackPollTimer?.cancel();
        _isStreamOnline = true;
        _processSnapshot(snapshot);
      },
      onError: (error) {
        // Stream lost — start fallback poll
        if (_isStreamOnline) {
          _isStreamOnline = false;
          _startFallbackPoll();
        }
      },
    );
}

void _startFallbackPoll() {
  _fallbackPollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('trips')
        .doc(widget.tripId)
        .get(const GetOptions(source: Source.server));
    _processSnapshot(snapshot);
  });
}
```

Also **delete** the entire `_manualRefreshTripStatus()` method — its logic is absorbed into the stream listener.

### Acceptance Criteria
- [ ] `_refreshTimer` (3-second periodic poll) is fully removed
- [ ] `_manualRefreshTripStatus()` method is fully removed
- [ ] Firestore stream is the single source of truth
- [ ] A fallback poll only activates when the stream goes offline (`onError`)
- [ ] Fallback poll cancels itself when the stream recovers

---

## Task 6 — Consolidate to a Single State Machine (Fix Timer Race Conditions)

### Problem
`TripTrackingScreen` has **3 separate competing timers**:
- `_refreshTimer` (3s periodic)
- `_driverResponseTimer` (60s one-shot)
- `_progressUpdateTimer` (500ms periodic)

They can all fire simultaneously and each call `setState()` independently. Lines 469-480 show a manual attempt to cancel one timer from inside another — a fragile pattern that can still cause `_handleDriverTimeout` to run twice.

### Files to Modify
- `lib/screens/trip_tracking_screen.dart` — refactor to single state handler

### Target Pattern — Status-Driven Single Handler

Replace all boolean flags (`_isWaitingForDriver`, `_isDriverOnTheWay`, etc.) with a single `_tripStatus` string that is the single source of truth. All timers and UI derive from it:

```dart
// REMOVE these booleans:
// bool _isWaitingForDriver = false;
// bool _isDriverOnTheWay = false;
// bool _isDriverArrived = false;
// bool _isTripInProgress = false;
// bool _isTripCompleted = false;
// bool _noDriversAvailable = false;

// KEEP only this (already exists):
String _tripStatus = 'searching';

// One consolidated transition function:
void _transitionToStatus(String newStatus, Map<String, dynamic> tripData) {
  if (_tripStatus == newStatus) return; // guard: no double processing
  setState(() => _tripStatus = newStatus);
  
  switch (newStatus) {
    case 'driver_notified': _startCountdownTimer(tripData); break;
    case 'driver_accepted': _cancelAllTimers(); _showDriverDialog(tripData); break;
    case 'driver_arrived':  _cancelAllTimers(); _showArrivalNotification(); break;
    case 'in_progress':     _updateMapForRoute(); break;
    case 'completed':       _cancelAllTimers(); break;
    case 'cancelled':       _cancelAllTimers(); Navigator.popUntil(...); break;
    case 'no_drivers_available': _cancelAllTimers(); _showRetryDialog(); break;
  }
}

void _cancelAllTimers() {
  _driverResponseTimer?.cancel();
  _progressUpdateTimer?.cancel();
  _fallbackPollTimer?.cancel();
}
```

Call `_transitionToStatus()` from both the stream listener and the fallback poll — they share the same guard (`if (_tripStatus == newStatus) return`) which prevents double execution.

### Acceptance Criteria
- [ ] All 5 boolean flags (`_isWaitingForDriver`, etc.) are removed
- [ ] `_transitionToStatus()` is the single function that handles all status changes
- [ ] A guard `if (_tripStatus == newStatus) return` prevents double handling
- [ ] `_cancelAllTimers()` is called in a single place
- [ ] UI rendering is derived purely from `_tripStatus` string

---

## Task 7 — Handle Stale FCM Tokens — Skip Driver Immediately on FCM Error

### Problem
When a driver's FCM token is expired or invalid, `fcm.send()` throws an error that is **silently caught** in `findNearbyDrivers.js` lines 316-323:
```js
try {
  await fcm.send(message);
} catch (error) {
  console.error("Error sending notification:", error); // logged but nothing done
}
```
The app then waits the full 60 seconds for a driver who will never receive the notification.

### Files to Modify
- `functions/findNearbyDrivers.js` — act on FCM error codes

### Target Implementation
```js
async function notifyDriverWithFallback(driversRanked, startIndex, tripId, tripData) {
  for (let i = startIndex; i < driversRanked.length; i++) {
    const driver = driversRanked[i];
    if (!driver.fcmToken) continue;

    try {
      await fcm.send(buildMessage(driver, tripId, tripData));
      console.log(`Successfully notified driver ${driver.driverId} (rank ${i + 1})`);
      
      // Update trip with the actually-notified driver
      await db.collection("trips").doc(tripId).update({
        notifiedDriverId: driver.driverId,
        status: "driver_notified",
        notificationTime: admin.firestore.FieldValue.serverTimestamp(),
      });
      return; // success — stop here

    } catch (err) {
      const isTokenError = [
        'messaging/invalid-registration-token',
        'messaging/registration-token-not-registered',
      ].includes(err.code);

      if (isTokenError) {
        console.warn(`Stale FCM token for driver ${driver.driverId} — skipping immediately`);
        // Clean up the stale token from Firestore
        await db.collection("drivers").doc(driver.driverId).update({ fcmToken: null });
        // Loop continues to next driver automatically
      } else {
        console.error("Non-token FCM error:", err);
        break; // unexpected error — stop
      }
    }
  }
  
  // All drivers failed — no one available
  await db.collection("trips").doc(tripId).update({ status: "no_drivers_available" });
}
```

### Acceptance Criteria
- [ ] FCM `invalid-registration-token` and `registration-token-not-registered` errors cause immediate skip to next driver
- [ ] Stale `fcmToken` field is set to `null` in the driver's Firestore document for cleanup
- [ ] Non-token FCM errors (network errors etc.) are still logged and halt the loop
- [ ] No 60-second wait is wasted on a driver with a dead token

---

## Task 8 — Geohash Spatial Query (Replace Full Collection Scan)

### Problem
`findNearbyDrivers.js` queries **ALL** online+available drivers globally (lines 137-140):
```js
const driversSnapshot = await db.collection("drivers")
    .where("isOnline", "==", true)
    .where("isAvailable", "==", true)
    .get(); // fetches every driver on the platform
```
At scale (thousands of drivers), this is **slow and very expensive** (Firestore charges per document read).

### Files to Modify
- `functions/findNearbyDrivers.js` — replace full scan with geohash bounding box query
- `functions/package.json` — add `geofire-common` dependency

### Setup
```bash
cd functions
npm install geofire-common
```

### Target Implementation
```js
const { geohashQueryBounds, distanceBetween } = require("geofire-common");

async function findDriversInRadius(pickupLat, pickupLng, radiusKm) {
  const center = [pickupLat, pickupLng];
  const radiusMeters = radiusKm * 1000;

  // Generate geohash bounding box cells
  const bounds = geohashQueryBounds(center, radiusMeters);

  // Query only drivers in the relevant geohash cells
  const queries = bounds.map(b =>
    db.collection("drivers")
      .where("isOnline", "==", true)
      .where("isAvailable", "==", true)
      .orderBy("geohash")          // requires 'geohash' field on driver document
      .startAt(b[0])
      .endAt(b[1])
      .get()
  );

  const snapshots = await Promise.all(queries);
  const drivers = [];

  snapshots.forEach(snap => {
    snap.forEach(doc => {
      const data = doc.data();
      // Final exact distance check (geohash cells are square, not circular)
      const distKm = distanceBetween(
        [data.location.latitude, data.location.longitude],
        center
      ) / 1000;

      if (distKm <= radiusKm) {
        drivers.push({ driverId: doc.id, ...data, distanceKm: distKm });
      }
    });
  });

  return drivers;
}
```

### Driver App Prerequisite (for driver app agent)
The driver app must write a `geohash` field alongside the location update:
```js
// In driver app, when updating location:
const { geohashForLocation } = require("geofire-common");
const geohash = geohashForLocation([lat, lng]);
await db.collection("drivers").doc(driverId).update({
  "location.latitude": lat,
  "location.longitude": lng,
  "geohash": geohash,  // <-- required for geohash queries
});
```

### Firestore Index Required
Add to `firestore.indexes.json`:
```json
{
  "collectionGroup": "drivers",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "isOnline", "order": "ASCENDING" },
    { "fieldPath": "isAvailable", "order": "ASCENDING" },
    { "fieldPath": "geohash", "order": "ASCENDING" }
  ]
}
```

### Acceptance Criteria
- [ ] `geofire-common` is added to `functions/package.json`
- [ ] Driver documents have a `geohash` field (written by driver app)
- [ ] Cloud Function queries by geohash bounding box, not full collection scan
- [ ] Final circular distance check filters out drivers in corners of the bounding box
- [ ] Composite Firestore index (`isOnline + isAvailable + geohash`) is deployed

---

## Implementation Priority Order

| Priority | Task | Effort | Impact |
|---|---|---|---|
| 🔴 Critical | **Task 4** — Remove hardcoded API key | Low | Security |
| 🔴 Critical | **Task 1** — Broadcast driver notification | Medium | UX / Waiting time |
| 🟠 High | **Task 7** — FCM stale token handling | Low | Reliability |
| 🟠 High | **Task 5** — Remove redundant polling | Low | Cost / Stability |
| 🟡 Medium | **Task 2** — Expanding search radius | Low | Coverage |
| 🟡 Medium | **Task 6** — Single state machine | Medium | Code quality |
| 🟢 Enhancement | **Task 3** — ETA-based scoring | Medium | Matching accuracy |
| 🟢 Enhancement | **Task 8** — Geohash spatial queries | High | Scale / Cost |

---

> [!IMPORTANT]
> Tasks 1, 5, and 6 are **interdependent** — implement them together in the same development session to avoid partial states where the old polling logic conflicts with the new broadcast acceptance logic.

> [!NOTE]
> Task 8 (Geohash) requires coordination with the **driver app** to write a `geohash` field. Confirm this is done before implementing the Cloud Function side.
