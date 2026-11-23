# RiderTaxi: Final Cost Report (Firebase + Google Maps)

> [!NOTE]
> **Updated:** 2026-10-31 (Post-commit `9c98dc1`: *migrate driver search to Cloud Tasks chain and remove client polling*, and updated for the **Drag-to-Pin UX** in `TripRequestScreenPro`).  
> **Scope:** Rider Flutter app (`HomeScreenPro` / `TripRequestScreenPro`), Cloud Functions + Cloud Tasks in `functions/`, and Driver app location/decline writes.  
> **Related Plans:** [`CLOUD_TASKS_DISPATCH.md`](./CLOUD_TASKS_DISPATCH.md) (Implemented) | [`MAPS_COST_OPTIMIZATION_PLAN.md`](./MAPS_COST_OPTIMIZATION_PLAN.md) (Planned)

---

## 1. Executive Summary

Because your active Rider app ([`TripRequestScreenPro`](file:///Users/macbook/Desktop/rider/lib/screens/trip_request_screen_pro.dart)) uses **Drag-to-Pin** on the map (and does **not** use the legacy typing autocomplete in `location_service.dart`), your Google Maps costs are **much lower** than a text-autocomplete app and come only from **Reverse Geocoding** (on pin release) and **Directions API** (for the route polyline).

| Metric | Current Drag-Pin State (Post-`9c98dc1`) | After [`MAPS_COST_OPTIMIZATION_PLAN.md`](./MAPS_COST_OPTIMIZATION_PLAN.md) |
| :--- | :--- | :--- |
| **Dispatch Architecture** | ✅ **100% Server-Side Cloud Tasks Chain** | ✅ **100% Server-Side Cloud Tasks Chain** |
| **Dispatch Cloud Tasks Cost** | **$0.00 / month** up to ~250k trips (1M free ops/mo) | **$0.00 / month** |
| **Pin-Drag Geocoding Cost (50k trips)** | **~$950 / month** (`geocode/json` HTTP call on pin release) | **$0.00 / month** (Free on-device `geocoding` package) |
| **Directions API Cost (50k trips)** | **~$325 / month** (uncached + multi-segment calls) | **~$200 / month** (1 cached call/trip, minus 10k free/mo) |
| **Total Bill for 50,000 Trips** | **~$1,327 / month** (~$1,027 after $300 credit) | **~$252 / month** (**$0.00 out of pocket** with $300 credit!) |
| **Recommended Plans** | **Firebase Blaze + Google Maps Pay-As-You-Go** | **Firebase Blaze + Google Maps Pay-As-You-Go** |

---

## 2. Cost Impact of Commit `9c98dc1` (Cloud Tasks Dispatch — Implemented ✅)

Migrating from client-driven `Timer.periodic` polling (and avoiding a 120s server `sleep()` loop) in [`findNearbyDrivers.js`](file:///Users/macbook/Desktop/rider/functions/findNearbyDrivers.js) and [`trip_tracking_screen.dart`](file:///Users/macbook/Desktop/rider/lib/screens/trip_tracking_screen.dart) delivered:

| Resource | Before (`searchRefreshedAt` Polling) | Alternative (`120s sleep` Loop) | **Now (`9c98dc1` Cloud Tasks Chain)** |
| :--- | :--- | :--- | :--- |
| **Client Polling Writes (`trips/{id}`)** | Up to **12 writes / trip** (every 10s) | 0 writes | ✅ **0 client polling writes** |
| **Unnecessary Trigger Fan-Out** | Up to **36 function calls / trip** | 0 extra calls | ✅ **Eliminated `refreshNearbyDriversSearch`** |
| **Function Active Compute Time** | ~1–6s across refreshes | ❌ **Up to 120s billed idle time / trip** | ✅ **~0.8s per round × 2–8 rounds** ($0 idle wait) |
| **Cloud Tasks Operations** | 0 | 0 | **2–16 ops / trip** (**FREE** up to 1,000,000 ops/mo) |

---

## 3. Monthly Cost Projections (Drag-to-Pin UX)

### Assumptions
* **Each trip:** ~4 pin drag releases (Pickup + Dropoff adjustments), 1 confirmed route polyline, ~2.5 dispatch rounds on average, and ~250–450 Firestore reads during active tracking.
* **Drivers:** Online 8 hours/day sending location updates every 10 seconds (20, 100, 400, and 1,000 drivers across the 4 tiers).

### Total Monthly Bill (Google Maps + Firebase — Before Applying $300 Credit)

| Trips / Month | **A. Current Drag-Pin Code (Post-`9c98dc1`)** | **B. After On-Device Geocode + Route Cache ([`MAPS_COST_OPTIMIZATION_PLAN.md`](./MAPS_COST_OPTIMIZATION_PLAN.md))** | **C. After All Fixes (+ Driver GPS Throttle & Hotspots)** |
| :--- | :--- | :--- | :--- |
| **1,000** | ~$1 | **$0–$1** | **$0–$1** |
| **10,000** | ~$185 | **~$11** ($0 Maps + ~$11 Firebase) | **~$10** ($0 Maps + ~$10 Firebase) |
| **50,000** | ~$1,327 | **~$252** ($200 Maps + ~$52 Firebase) | **~$235** ($200 Maps + ~$35 Firebase) |
| **150,000** | ~$4,180 | **~$870** ($700 Maps + ~$170 Firebase) | **~$815** ($700 Maps + ~$115 Firebase) |

### Detailed Breakdown for Column B (After [`MAPS_COST_OPTIMIZATION_PLAN.md`](./MAPS_COST_OPTIMIZATION_PLAN.md))

| Trips / Month | Pin-Drag Geocoding (On-Device) | Google Directions API (10k free/mo) | Firestore Reads & Writes | Cloud Functions + Cloud Tasks | Out of Pocket (With $300 Credit) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1,000** | **$0** | **$0** (Under 10k free) | ~$1 | **$0** (Free tier) | **$0** |
| **10,000** | **$0** | **$0** (10k free tier) | ~$11 | **$0** (Free tier) | **$0** |
| **50,000** | **$0** | **$200** (40k billable × $5/1k) | ~$51 | **~$1** (Tasks 100% Free) | **$0** ($252 covered by $300 credit) |
| **150,000** | **$0** | **$700** (140k billable × $5/1k) | ~$163 | **~$7** (Tasks ~$0, Functions ~$7) | **~$570** (or ~$870 after credit ends) |

---

## 4. Optimization Status & Roadmap

### ✅ Completed
* **[DONE — `9c98dc1`] Cloud Tasks Autonomous Dispatch & Client Polling Removal:**
  * Replaced client-side 10s `searchRefreshedAt` writes in [`trip_tracking_screen.dart`](file:///Users/macbook/Desktop/rider/lib/screens/trip_tracking_screen.dart) with short (~1s) stateless Cloud Tasks rounds in [`findNearbyDrivers.js`](file:///Users/macbook/Desktop/rider/functions/findNearbyDrivers.js).

### 🔴 Priority 1 — Implement [`MAPS_COST_OPTIMIZATION_PLAN.md`](./MAPS_COST_OPTIMIZATION_PLAN.md) in `map_provider.dart`
1. **Free On-Device Reverse Geocoding on Pin Release:**
   * Replace the paid HTTP `geocode/json` call in [`MapProvider._getAddressFromCoordinates()`](file:///Users/macbook/Desktop/rider/lib/providers/map_provider.dart#L927-L959) with `placemarkFromCoordinates()` from the `geocoding` package + a 4-decimal (`~11m`) coordinate cache (keeping HTTP only as an error fallback). **Saves ~$950/month at 50k trips.**
2. **Smart Route Caching & 5-Layer Directions API Protection:**
   * Only call `_updateRoute()` on the final Confirm step (not on `setPickupLocationSilent`, `addStop`, or waiting-time changes).
   * Cache polylines by 4-decimal rounded coordinates (`~11m`).
   * Combine multi-stop trips into a single request via `&waypoints=`.
   * Enforce a **max 3 Directions calls per booking session** cap + **5s cooldown** so an indecisive or abusive user repeatedly moving the pin cannot burn Directions quota (fare & distance still calculate 100% locally via Haversine math).

### 🟠 Priority 2 — Firestore Optimizations for High Scale (> 20k Trips)
3. **Throttle Driver Location Writes (Driver App):** Write driver GPS only after **30–50m of movement** or every **15–20s while idle** (cuts Firestore writes by **50–60%**).
4. **Geohash Filter in `findEligibleDriversForTrip`:** Once you have **100+ simultaneous online drivers**, add a geohash bounding box + `.limit(30)`.
5. **Paginate Trip History ([`trip_history_screen.dart`](file:///Users/macbook/Desktop/rider/lib/screens/trip_history_screen.dart#L340-L349)):** Use one-time `.get()` with `.limit(20)` for completed/cancelled trips instead of `.snapshots()`.
