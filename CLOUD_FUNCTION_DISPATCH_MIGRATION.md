# Cloud Function Dispatch & Retry Migration Plan

> **Specification & Implementation Prompt for AI Agent**  
> **Target Files:**
> - `functions/findNearbyDrivers.js`
> - `lib/screens/trip_tracking_screen.dart`
> - `functions/index.js`

---

## 1. Executive Summary & Objective

Migrate the driver search retry loop, cascading dispatch, and 2-minute timeout from the Flutter mobile app to **Firebase Cloud Functions v2**.

### Primary Goals:
1. **Decouple from phone lifecycle:** Dispatching must continue on Google Cloud servers even if the rider locks their phone, minimizes the app, or loses cell connection.
2. **Eliminate wasteful client Firestore writes:** Stop the Flutter app from pinging Firestore every 10 seconds (`searchRefreshedAt`).
3. **Smart Cascading Dispatch:** If the initial batch of drivers ignores or rejects the ride, automatically cascade to the next closest eligible drivers instead of prematurely giving up.
4. **Server-enforced 2-minute deadline:** If no driver accepts within 120 seconds, the backend atomically sets `status: 'no_drivers_available'` and `noDriversAvailable: true`.

---

## 2. Current Architecture vs. New Architecture

### Current Architecture (Client-Driven Anti-Pattern)
```
[Flutter App]
   ├── 1. Creates trip in Firestore (`status: 'searching'`)
   ├── 2. Runs Timer.periodic every 10s: writes `searchRefreshedAt` + `searchAttempts++`
   └── 3. After 120s timer: writes `status: 'no_drivers_available'`
           ▲
           └── ⚠️ IF PHONE IS LOCKED / CLOSED: Timer dies, search stops, trip stranded forever!

[Cloud Functions]
   ├── `findNearbyDrivers`: Triggered on trip create (`onCreate`), notifies top 3 drivers once.
   └── `refreshNearbyDriversSearch`: Triggered on trip update (`onUpdate`), runs whenever phone writes `searchRefreshedAt`.
```

### New Architecture (100% Server-Side Autonomous Dispatch)
```
[Flutter App] (Pure Reactive UI)
   ├── 1. Creates trip in Firestore (`status: 'searching'`)
   └── 2. Listens to Firestore snapshots (`doc('trips/{tripId}').snapshots()`)
           └── Renders UI: Searching Radar ➔ Driver Notified ➔ Driver Accepted ➔ No Drivers

[Cloud Functions] (`findNearbyDrivers` - v2 with timeoutSeconds: 150)
   ├── 1. Triggered on trip create (`onCreate`)
   ├── 2. Autonomous Loop (Server-side, up to 120 seconds max):
   │       ├── Check: Did rider cancel or did driver accept? ➔ Exit immediately.
   │       ├── Scan: Find eligible drivers within 5 km (wallet balance, carType, online).
   │       ├── Filter: Exclude previously declined/notified drivers (`declinedDriverIds`).
   │       ├── Rank: Compute priority scores (distance, tier, acceptance, rating).
   │       ├── Broadcast: Notify top candidates via FCM.
   │       └── Wait: Sleep 15–20s to allow acceptance race-lock (`claimedByDriverId`).
   └── 3. Deadline Reached (120s):
           └── Sets `status: 'no_drivers_available'`, `noDriversAvailable: true`.
```

---

## 3. Deep Analysis of Existing Backend Components

In `functions/findNearbyDrivers.js`, the following existing logic **must be preserved**:

1. **Wallet Balance & Overdraft Checks (Section 4.4):**
   - Read `app_settings/wallet`.
   - Batch-fetch `driver_wallets` for all candidates.
   - Enforce: `(balanceCents + overdraftLimit) >= requiredAllowanceCents`.
2. **Car Type Filtering:**
   - Filter `drivers.where("carType", "==", tripData.carType)` if specified.
3. **Driver Priority Scoring (0–100 pts):**
   - Distance (0–50 pts), Tier bonus (0–15 pts), Acceptance rate (0–20 pts), Rating (0–15 pts).
4. **Race-Lock Mechanism (`claimedByDriverId`):**
   - Sets `claimedByDriverId: null` on notification.
   - Driver app performs an atomic transaction to claim the trip.

---

## 4. Step-by-Step Implementation Instructions

### STEP 1: Update `functions/findNearbyDrivers.js`

#### 1.1 Configure Cloud Function v2 Options
Increase the function timeout and memory so it can safely execute the 2-minute server loop:
```javascript
const { onDocumentCreated } = require("firebase-functions/v2/firestore");

exports.findNearbyDrivers = onDocumentCreated(
  {
    document: "trips/{tripId}",
    timeoutSeconds: 150, // 2.5 minutes maximum execution window
    memory: "256MiB",
  },
  async (event) => {
    const tripId = event.params.tripId;
    const tripData = event.data.data();
    if (!tripData) return null;

    return dispatchTripLifecycle(tripId, tripData);
  }
);
```

#### 1.2 Implement `dispatchTripLifecycle(tripId, initialTripData)`
Create the server-side dispatch loop with the following flow:

```javascript
const DISPATCH_CONFIG = {
  MAX_SEARCH_DURATION_MS: 120 * 1000, // 2 minutes maximum
  ROUND_WAIT_TIME_MS: 15 * 1000,      // 15 seconds wait per driver response
  DEFAULT_RADIUS_KM: 5,
  EXPANDED_RADIUS_KM: 8,             // Optional radius expansion on retry
  TOP_DRIVERS_PER_ROUND: 3,
};

async function dispatchTripLifecycle(tripId, initialTripData) {
  const startTime = Date.now();
  const alreadyNotifiedDriverIds = new Set();
  let searchAttempts = 0;

  console.log(`[Dispatch] Starting server-side dispatch for trip ${tripId}`);

  while (Date.now() - startTime < DISPATCH_CONFIG.MAX_SEARCH_DURATION_MS) {
    searchAttempts++;

    // 1. Fetch latest trip state from Firestore
    const tripSnap = await db.collection("trips").doc(tripId).get();
    if (!tripSnap.exists) {
      console.log(`[Dispatch] Trip ${tripId} deleted, exiting dispatch loop.`);
      return null;
    }

    const currentTrip = tripSnap.data();

    // 2. Cancellation / Acceptance check
    if (currentTrip.status === "cancelled") {
      console.log(`[Dispatch] Trip ${tripId} cancelled by user, stopping search.`);
      return null;
    }
    if (currentTrip.status === "driver_accepted" || currentTrip.claimedByDriverId) {
      console.log(`[Dispatch] Trip ${tripId} accepted by driver ${currentTrip.claimedByDriverId}. Done!`);
      return null;
    }

    // 3. Search radius (expand to 8 km after 45 seconds if no drivers found in 5 km)
    const elapsedMs = Date.now() - startTime;
    const searchRadius = elapsedMs > 45000 
      ? DISPATCH_CONFIG.EXPANDED_RADIUS_KM 
      : DISPATCH_CONFIG.DEFAULT_RADIUS_KM;

    // 4. Find eligible drivers excluding already notified/rejected drivers
    const candidates = await findEligibleDriversForTrip(
      tripId, 
      currentTrip, 
      searchRadius, 
      alreadyNotifiedDriverIds
    );

    if (candidates && candidates.length > 0) {
      // Pick top N candidates
      const topBatch = candidates.slice(0, DISPATCH_CONFIG.TOP_DRIVERS_PER_ROUND);
      topBatch.forEach(d => alreadyNotifiedDriverIds.add(d.driverId));

      // Update trip document: status = "driver_notified", record notified IDs
      await db.collection("trips").doc(tripId).update({
        status: "driver_notified",
        notifiedDriverIds: topBatch.map(d => d.driverId),
        searchAttempts: searchAttempts,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Send FCM notifications in parallel
      await sendNotificationsToDrivers(topBatch, tripId, currentTrip);

      // Wait 15 seconds to give notified drivers time to accept
      await sleep(DISPATCH_CONFIG.ROUND_WAIT_TIME_MS);
    } else {
      console.log(`[Dispatch] Attempt ${searchAttempts}: No new eligible drivers in ${searchRadius}km radius.`);
      
      // Update attempt count in Firestore
      await db.collection("trips").doc(tripId).update({
        status: "searching",
        searchAttempts: searchAttempts,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Sleep 10 seconds before polling again
      await sleep(10000);
    }
  }

  // 5. Timeout Reached (120 seconds elapsed)
  // Re-verify that no driver claimed at the very last moment
  const finalCheck = await db.collection("trips").doc(tripId).get();
  const finalData = finalCheck.data();
  if (finalData && finalData.status !== "driver_accepted" && !finalData.claimedByDriverId && finalData.status !== "cancelled") {
    console.log(`[Dispatch] Trip ${tripId} reached 2-minute deadline with no driver. Marking no_drivers_available.`);
    await db.collection("trips").doc(tripId).update({
      status: "no_drivers_available",
      noDriversAvailable: true,
      searchEndedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  return null;
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}
```

#### 1.3 Retire `refreshNearbyDriversSearch`
In `functions/index.js` and `functions/findNearbyDrivers.js`, remove or deprecate `exports.refreshNearbyDriversSearch`. Since the master loop handles re-searching internally, client-triggered refreshes are no longer needed.

---

### STEP 2: Update Flutter Client (`lib/screens/trip_tracking_screen.dart`)

#### 2.1 Remove Client-Side Polling Timer
Remove the following client-side timer logic from `_TripTrackingScreenState`:
- ❌ Remove `_searchingTimer` and `Timer.periodic(const Duration(seconds: 10), ...)`
- ❌ Remove `_triggerDriverSearch()` and `searchRefreshedAt` updates
- ❌ Remove `_checkForSearchTimeout()` (the backend now enforces the 2-minute timeout)
- ❌ Remove `DRIVER_TIMEOUT_SECONDS = 60` and `_handleDriverTimeout()`

#### 2.2 Retain Pure Reactive Listening
Keep the real-time Firestore stream in `_setupTripListener`:
- When backend transitions to `status: 'driver_notified'` ➔ Flutter shows the countdown UI.
- When backend transitions to `status: 'driver_accepted'` ➔ Flutter shows driver info and route polyline.
- When backend transitions to `status: 'no_drivers_available'` ➔ Flutter shows the *"No Drivers Available"* dialog.

#### 2.3 Retain "TRY AGAIN" Button Behavior
When the user taps **"TRY AGAIN"** in the *No Drivers Available* dialog:
```dart
onPressed: () {
  Navigator.of(ctx).pop();
  FirebaseFirestore.instance
      .collection('trips')
      .doc(widget.tripId)
      .update({
        'status': 'searching',
        'searchStartedAt': FieldValue.serverTimestamp(),
        'noDriversAvailable': false,
      });
}
```
> **Note for AI Agent:** In Cloud Functions, add an `onDocumentUpdated` listener for when `status` transitions from `no_drivers_available` ➔ `searching` so the server restarts the dispatch loop for the retry.

---

## 5. Verification & Testing Checklist

- [ ] **Cold Start / Phone Locked Test:** Start a trip request, immediately lock the phone or switch apps for 90 seconds. Confirm via Firebase logs that the Cloud Function continues scanning and notifies drivers.
- [ ] **Driver Acceptance Test:** Start a trip, have a driver accept at 30 seconds. Verify the server-side loop exits immediately without notifying further drivers.
- [ ] **Rider Cancellation Test:** Start a trip, tap "Cancel" in the Flutter app. Verify the Cloud Function detects `status === 'cancelled'` and cleanly terminates its loop.
- [ ] **2-Minute Timeout Test:** Request a ride in an area with zero drivers. After exactly 120 seconds, verify that Firestore updates to `status: 'no_drivers_available'` and `noDriversAvailable: true`, and the Flutter app displays the dialog.
- [ ] **Cost / Write Volume Test:** Verify that the Flutter client no longer generates Firestore document writes every 10 seconds.

---

## 6. Deployment Command

```bash
cd /Users/macbook/Desktop/rider/functions
npm run lint
firebase deploy --only functions:findNearbyDrivers
```
