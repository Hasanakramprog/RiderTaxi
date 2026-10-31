# Next Steps: Firebase Deployment & Driver App Update Reminder

> **Project ID:** `taxiapp-b0cd7`  
> **Related Implementation:** [CLOUD_TASKS_DISPATCH.md](./CLOUD_TASKS_DISPATCH.md) (`functions/findNearbyDrivers.js`, `functions/index.js`, `lib/screens/trip_tracking_screen.dart`)

---

## 1. Deploy Cloud Tasks Dispatch Functions to Firebase

When you are ready to deploy the new autonomous Cloud Tasks dispatch system to your Firebase project (`taxiapp-b0cd7`), run the following commands:

```bash
# 1. Enable the Cloud Tasks API on your Google Cloud project (one-time setup)
gcloud services enable cloudtasks.googleapis.com --project=taxiapp-b0cd7

# 2. Lint and deploy the 3 dispatch functions
cd /Users/macbook/Desktop/rider/functions
npm run lint
firebase deploy --only functions:findNearbyDrivers,functions:dispatchNextRound,functions:restartDispatch
```

### Optional Cleanup (Remove Deprecated Function from Firebase)
If `refreshNearbyDriversSearch` was previously deployed to your live Firebase project, you can delete the old Cloud Function from the server so it no longer exists in your console:

```bash
firebase functions:delete refreshNearbyDriversSearch
```

---

## 2. Reminder for Your Driver App Repository

When a driver taps **"Decline"** (or when their incoming ride request countdown timer expires without accepting), update the **Driver App** codebase to append `currentDriverId` to `declinedDriverIds` on the trip document:

```dart
// In Driver App: Ride Request Dialog / Trip Service (on Decline or Timeout)
await FirebaseFirestore.instance
    .collection('trips')
    .doc(tripId)
    .update({
      'declinedDriverIds': FieldValue.arrayUnion([currentDriverId]),
    });
```

### Why This Matters
* **During active search (Rounds 1..N):** Both `notifiedDriverIds` and `declinedDriverIds` are excluded so no driver is pinged twice—even when the search radius expands from **5 km to 8 km** after 45 seconds.
* **When Rider taps "TRY AGAIN":** `restartDispatch` resets `notifiedDriverIds: []` (so drivers who simply missed the first notification can be tried again), **but keeps `declinedDriverIds`** so drivers who explicitly declined are never bothered again for the same trip.

