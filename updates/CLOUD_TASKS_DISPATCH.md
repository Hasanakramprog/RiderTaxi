# Cloud Tasks Dispatch (Replace `sleep` Loop) — Planned Update

> **Status:** Implemented
> **Target file:** `functions/findNearbyDrivers.js`
> **Related:** `CLOUD_FUNCTION_DISPATCH_MIGRATION.md`, `updates/IDEMPOTENT_DISPATCH_LOCK.md`

---

## 1. Problem with the `sleep` loop

The migration plan uses one function that stays alive up to 120 seconds:

```javascript
while (elapsed < 120s) {
  notify drivers
  await sleep(15000);   // idle, but still running and billed
}
```

- **Idle billing:** you pay while the function just waits.
- **Fragile:** if the instance is killed (deploy, crash, restart), the loop dies and the trip stays stuck in `searching`.
- **Concurrency cost:** 100 simultaneous requests = 100 instances held open for 2 minutes.
- **Hard cap:** limited by the function timeout.

## 2. Solution: short rounds chained by Cloud Tasks

Each function invocation does **one round** (about 1 second), then schedules the next round and exits. Cloud Tasks handles the 15-second delay, not your code.

```
Round 1 (~1s)  notify drivers -> enqueue Round 2 (delay 15s) -> exit
   ... 15s: nothing running, nothing billed ...
Round 2 (~1s)  check trip, notify next drivers -> enqueue Round 3 -> exit
   ...
Round N        deadline passed -> set no_drivers_available -> exit
```

---

## 3. Per-round lock (what it means)

### Why it is still needed
Cloud Tasks is also **at-least-once**. The same task can be delivered twice (retry after a timeout, network blip). Also the `onCreate` trigger itself can fire twice.

Without protection, one round runs twice and **the same drivers are notified twice**.

### The old idea vs. the per-round idea

| | Whole-loop lock (old doc) | Per-round lock (this design) |
|---|---|---|
| What is protected | One long loop | Each individual round |
| Held for | ~120s | Only the moment the round is claimed |
| Fits | `sleep` loop | Cloud Tasks chain |

With Cloud Tasks there is no long-running loop to lock. Instead, **each round claims its own round number** inside a transaction. A duplicate of the same round finds it already claimed and exits.

### Example

Trip document state:

```
dispatch: { sessionId: "abc123", lastRound: 2 }
```

```
Task for round 3 delivered   -> lastRound is 2, 3 > 2 -> claim (lastRound=3) -> run
Same task delivered again    -> lastRound is 3, 3 <= 3 -> already claimed -> exit
```

### Code

```javascript
async function claimRound(tripId, sessionId, round) {
  const ref = db.collection("trips").doc(tripId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return false;

    const d = snap.data().dispatch || {};

    // A newer search session (TRY AGAIN) replaced this one -> stale, stop
    if (d.sessionId && d.sessionId !== sessionId) return false;

    // This round (or a later one) was already claimed -> duplicate, stop
    if ((d.lastRound || 0) >= round) return false;

    tx.update(ref, { dispatch: { sessionId, lastRound: round } });
    return true;
  });
}
```

`sessionId` lets "TRY AGAIN" start a brand-new search (new `sessionId`, round 1) without being blocked by the old one, and makes any leftover tasks from the old search exit harmlessly.

---

## 4. Full implementation

### 4.1 Config

```javascript
const { getFunctions } = require("firebase-admin/functions");
const { onTaskDispatched } = require("firebase-functions/v2/tasks");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const crypto = require("crypto");

const DISPATCH_CONFIG = {
  MAX_SEARCH_DURATION_MS: 120 * 1000,
  ROUND_DELAY_SECONDS: 15,
  DEFAULT_RADIUS_KM: 5,
  EXPANDED_RADIUS_KM: 8,
  EXPAND_AFTER_MS: 45 * 1000,
  TOP_DRIVERS_PER_ROUND: 3,
};
```

### 4.2 Enqueue helper (with task-name de-duplication)

```javascript
async function enqueueNextRound(tripId, sessionId, startedAt, nextRound) {
  const queue = getFunctions().taskQueue("dispatchNextRound");
  await queue.enqueue(
    { tripId, sessionId, startedAt, round: nextRound },
    {
      scheduleDelaySeconds: DISPATCH_CONFIG.ROUND_DELAY_SECONDS,
      // Same id = Cloud Tasks refuses a duplicate task for this round
      id: `${tripId}-${sessionId}-r${nextRound}`,
    }
  );
}
```

The task `id` is a second safety net: Cloud Tasks itself rejects a duplicate task with the same name.

### 4.3 One round

```javascript
async function runDispatchRound(tripId, sessionId, startedAt, round) {
  // 1. Claim this round (per-round lock). Duplicate -> exit.
  const claimed = await claimRound(tripId, sessionId, round);
  if (!claimed) {
    console.log(`[Dispatch] ${tripId} round ${round} already handled, skipping.`);
    return;
  }

  const ref = db.collection("trips").doc(tripId);
  const snap = await ref.get();
  if (!snap.exists) return;
  const trip = snap.data();

  // 2. Stop conditions
  if (trip.status === "cancelled") return;
  if (trip.status === "driver_accepted" || trip.claimedByDriverId) return;

  // 3. Deadline
  const elapsed = Date.now() - startedAt;
  if (elapsed > DISPATCH_CONFIG.MAX_SEARCH_DURATION_MS) {
    await ref.update({
      status: "no_drivers_available",
      noDriversAvailable: true,
      searchEndedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return;
  }

  // 4. Do ONE round of work
  const radius =
    elapsed > DISPATCH_CONFIG.EXPAND_AFTER_MS
      ? DISPATCH_CONFIG.EXPANDED_RADIUS_KM
      : DISPATCH_CONFIG.DEFAULT_RADIUS_KM;

  // Build complete exclusion set:
  // Combines all previously notified drivers + drivers who explicitly declined!
  // CRITICAL: When radius expands from 5km to 8km at 45s, this exclusion prevents
  // re-finding or re-notifying ANY driver that was already contacted or declined.
  const excludedDriverIds = new Set([
    ...(trip.notifiedDriverIds || []),
    ...(trip.declinedDriverIds || []),
  ]);

  const candidates = await findEligibleDriversForTrip(tripId, trip, radius, excludedDriverIds);
  const batch = candidates.slice(0, DISPATCH_CONFIG.TOP_DRIVERS_PER_ROUND);

  if (batch.length > 0) {
    await sendNotificationsToDrivers(batch, tripId, trip);
    await ref.update({
      status: "driver_notified",
      // Use FieldValue.arrayUnion to safely append without race conditions
      notifiedDriverIds: admin.firestore.FieldValue.arrayUnion(...batch.map((d) => d.driverId)),
      searchAttempts: round,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    });
  } else {
    await ref.update({
      status: "searching",
      searchAttempts: round,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  // 5. Schedule the next round, then EXIT
  await enqueueNextRound(tripId, sessionId, startedAt, round + 1);
}
```

### 4.4 Entry points

**Trip created -> round 1**

```javascript
exports.findNearbyDrivers = onDocumentCreated("trips/{tripId}", async (event) => {
  const tripId = event.params.tripId;
  const sessionId = crypto.randomUUID();
  await runDispatchRound(tripId, sessionId, Date.now(), 1);
});
```

**Task handler -> rounds 2..N**

```javascript
exports.dispatchNextRound = onTaskDispatched(
  {
    retryConfig: { maxAttempts: 3, minBackoffSeconds: 5 },
    rateLimits: { maxConcurrentDispatches: 50 },
  },
  async (req) => {
    const { tripId, sessionId, startedAt, round } = req.data;
    await runDispatchRound(tripId, sessionId, startedAt, round);
  }
);
```

**TRY AGAIN -> new session, round 1**

```javascript
exports.restartDispatch = onDocumentUpdated("trips/{tripId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (before.status === "no_drivers_available" && after.status === "searching") {
    const sessionId = crypto.randomUUID();
    // Reset session and notified list, BUT preserve declinedDriverIds
    // so drivers who explicitly said "No" are NOT bothered again on retry!
    await event.data.after.ref.update({
      notifiedDriverIds: [],
      dispatch: { sessionId, lastRound: 0 },
    });
    await runDispatchRound(event.params.tripId, sessionId, Date.now(), 1);
  }
});
```

### 4.5 Driver App Repository Action Item (CRITICAL REMINDER)

When implementing the new dispatch system, remember to make this single update in the **Driver App** codebase:

When a driver taps **"Decline"** (or when the driver's trip incoming dialog countdown expires without acceptance):
```dart
// In Driver App: Ride Request Dialog / Service
await FirebaseFirestore.instance
    .collection('trips')
    .doc(tripId)
    .update({
  'declinedDriverIds': FieldValue.arrayUnion([currentDriverId]),
});
```
This enables the backend to instantly register the driver's decline and permanently exclude them from being pinged again for this ride.

---

## 5. Timeline example

```
t=0s    Trip created   -> Round 1: claim r1, notify A,B,C  -> enqueue r2 (15s)
t=15s   Task r2        -> claim r2, still searching, notify D,E,F -> enqueue r3
t=15s   Task r2 AGAIN  -> lastRound=2 -> already claimed -> skipped (no double notify)
t=30s   Task r3        -> claim r3, driver B accepted -> EXIT, no more tasks
```

If nobody accepts, rounds continue until `elapsed > 120s`, where the last round writes `no_drivers_available`.

---

## 6. Comparison

| | `sleep` loop | Cloud Tasks chain |
|---|---|---|
| Running time per trip | ~120s | ~1s x ~8 rounds |
| Billed idle time | Yes | No |
| If instance dies | Search stops, trip stuck | Task retries automatically |
| Setup | Easy | Moderate (queue + task function) |
| Duplicate protection | Whole-loop `dispatchLock` | Per-round `claimRound` + task `id` |

---

## 7. Setup steps

1. Enable billing (Blaze plan) on the Firebase project. This is required for Cloud Functions and Cloud Tasks.
2. Enable the **Cloud Tasks API** in Google Cloud Console.
3. Make sure the functions service account has permission to enqueue tasks (`roles/cloudtasks.enqueuer`).
4. Add the code above to `functions/findNearbyDrivers.js`. Reuse the existing `findEligibleDriversForTrip` / `sendNotificationsToDrivers` logic (wallet, car type, scoring).
5. Remove `refreshNearbyDriversSearch` and the client `Timer.periodic` / `searchRefreshedAt` writes.
6. Deploy:
   ```bash
   cd functions
   npm run lint
   firebase deploy --only functions:findNearbyDrivers,functions:dispatchNextRound,functions:restartDispatch
   ```

## 8. Verification checklist

- [ ] Duplicate `onCreate` event: round 1 runs once, drivers notified once.
- [ ] Duplicate task delivery: second delivery logs "already handled".
- [ ] Phone locked 90s: rounds keep running (check Firebase logs).
- [ ] Driver accepts at 30s: no further tasks are enqueued.
- [ ] Rider cancels: next round exits without notifying.
- [ ] 120s with no drivers: `status: 'no_drivers_available'` written once.
- [ ] TRY AGAIN: new `sessionId`, round 1 starts; old session's leftover tasks exit.
- [ ] Function instance killed mid-round: Cloud Tasks retries it.

## 9. Notes

- This design supersedes the whole-loop lock in `IDEMPOTENT_DISPATCH_LOCK.md`. Use that doc only if you stay with the `sleep` loop.
- Test with the Firebase Emulator first (it supports task queue functions).
