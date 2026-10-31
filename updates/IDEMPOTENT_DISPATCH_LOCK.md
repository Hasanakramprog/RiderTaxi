# Idempotent Dispatch (dispatchLock) — Planned Update

> **Status:** Planned (not implemented yet)
> **Target file:** `functions/findNearbyDrivers.js`
> **Related:** `CLOUD_FUNCTION_DISPATCH_MIGRATION.md`

---

## 1. Problem: Duplicate Triggers

Firestore triggers are **at-least-once**. The same `onDocumentCreated` event can be delivered twice (retries, cold starts, slow acknowledgement).

Without protection, one ride request starts **two dispatch loops** for the same trip:

```
Trip created ──► Loop A: notifies drivers 1,2,3 at t=0s
             └─► Loop B: notifies drivers 1,2,3 at t=0s   (duplicate event)
```

Consequences:
- Drivers receive **double push notifications**.
- Each loop keeps its own `alreadyNotifiedDriverIds`, so they conflict. Both may write `status` / `searchAttempts` at the same time.
- Double cost (two 150s functions).
- Both may write `no_drivers_available` at timeout.

---

## 2. Solution: Atomic Lock via Transaction

Before starting the loop, the function **claims the trip** by writing a `dispatchLock` field inside a **Firestore transaction**. Transactions are atomic, so only one invocation wins.

### 2.1 Acquire lock

```javascript
const crypto = require("crypto");

async function acquireDispatchLock(tripId, ownerId) {
  const ref = db.collection("trips").doc(tripId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return false;

    const lock = snap.data().dispatchLock;
    const now = Date.now();

    // Someone else holds a fresh lock -> do not start another loop
    if (lock && lock.expiresAt > now && lock.owner !== ownerId) {
      return false;
    }

    tx.update(ref, {
      dispatchLock: { owner: ownerId, expiresAt: now + 150 * 1000 },
    });
    return true;
  });
}
```

### 2.2 Release lock

```javascript
async function releaseDispatchLock(tripId, ownerId) {
  const ref = db.collection("trips").doc(tripId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists && snap.data().dispatchLock?.owner === ownerId) {
      tx.update(ref, { dispatchLock: admin.firestore.FieldValue.delete() });
    }
  });
}
```

### 2.3 Use in the trigger

```javascript
exports.findNearbyDrivers = onDocumentCreated(
  { document: "trips/{tripId}", timeoutSeconds: 150 },
  async (event) => {
    const tripId = event.params.tripId;
    const ownerId = crypto.randomUUID(); // unique per invocation

    const gotLock = await acquireDispatchLock(tripId, ownerId);
    if (!gotLock) {
      console.log(`[Dispatch] ${tripId} already being handled, skipping.`);
      return null; // duplicate event exits
    }

    try {
      return await dispatchTripLifecycle(tripId, event.data.data(), ownerId);
    } finally {
      await releaseDispatchLock(tripId, ownerId);
    }
  }
);
```

### 2.4 Verify ownership inside the loop

Each round already re-reads the trip. Add:

```javascript
if (currentTrip.dispatchLock?.owner !== ownerId) return null; // lost the lock, stop
```

---

## 3. What Happens

```
Event 1 -> transaction: no lock -> writes lock (owner=A) -> runs loop
Event 2 -> transaction: lock owned by A, not expired -> returns false -> exits
```

### Why `expiresAt`?
If the winning instance crashes, it never releases the lock. The expiry (150s = function timeout) lets a later retry take over, so the trip is never locked forever.

### Retry flow ("TRY AGAIN")
The `no_drivers_available -> searching` `onDocumentUpdated` trigger must call `acquireDispatchLock` with the same logic. The previous lock has expired/been released, so the new loop starts cleanly.

---

## 4. Alternative: Event-ID Marker

Write `processedEvents/{event.id}` using `create()` (fails if it already exists). This stops duplicate event deliveries but does **not** stop a retry trigger overlapping a still-running loop. Prefer `dispatchLock`, which covers both.

---

## 5. Implementation Steps

1. Add `acquireDispatchLock` and `releaseDispatchLock` to `functions/findNearbyDrivers.js`.
2. Wrap the `findNearbyDrivers` trigger as in section 2.3.
3. Apply the same lock in the retry trigger (`no_drivers_available -> searching`).
4. Pass `ownerId` into `dispatchTripLifecycle` and check ownership each round.
5. Test in the Firebase Emulator: fire the trigger twice for one trip. Expect one loop and one "already being handled" log.
6. Deploy:
   ```bash
   cd functions
   npm run lint
   firebase deploy --only functions:findNearbyDrivers
   ```

## 6. Verification Checklist

- [ ] Duplicate `onCreate` event produces only one loop.
- [ ] Drivers receive a single notification per round.
- [ ] Crashed instance: lock expires after 150s and a retry can take over.
- [ ] "TRY AGAIN" restarts the loop cleanly.
- [ ] `dispatchLock` is removed from the trip after the loop ends.
