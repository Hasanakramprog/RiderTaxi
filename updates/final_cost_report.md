# RiderTaxi: final cost report (Firebase + Google Maps)

> [!NOTE]
> **Prepared:** 2026-10-21. **Scope:** the rider app, the Cloud Functions in `functions/`, and the driver app's location writes. **Prices:** Google Maps prices are from mapsplatform.google.com/pricing (checked today). Firestore prices are US list prices from memory: reads $0.06 per 100k and writes $0.18 per 100k. A single-region database costs about half. Treat every number as an estimate that could be off by ±30%.

---

## 1. Summary

| | Now | After all fixes |
|---|---|---|
| Cost per trip at 10k trips a month | **~$0.25** | **~$0.001–0.007** |
| Biggest cost | Place Details (legacy, $17 per 1,000), up to 5 per search request | Routes and Place Details Essentials |
| Recommended plan | — | **Firebase Blaze + Google Maps pay-as-you-go** |

**About 90% of the bill comes from one function**, `searchPlaces()` in [location_service.dart](file:///Users/macbook/Desktop/rider/lib/services/location_service.dart#L108-L175). Fix it before launch.

---

## 2. Monthly cost

### Assumptions
- Each trip: 3 autocomplete requests, 2 Directions calls, 3 reverse geocodes and about 300–550 Firestore reads.
- Drivers are online 8 hours a day and send their location every 10 seconds.
- Number of drivers: 20, 100, 400 and 1,000 for the four sizes below.

### Totals (Google Maps + Firebase)

| Trips per month | **A. Now** | **B. Maps fix only** | **C. All fixes, hotspots removed** |
|---|---|---|---|
| 1,000 | ~$172 | ~$2 | **~$1** |
| 10,000 | ~$2,520 | ~$20–77 | **~$11–68** |
| 50,000 | ~$11,100 | ~$500–870 | **~$457–827** |
| 150,000 | ~$23,000 | ~$1,610–2,660 | **~$1,475–2,525** |

Each range depends on whether autocomplete uses search sessions (low number) or not (high number).

### Breakdown for column C
| Trips per month | Google Maps | Firestore reads | Firestore writes | Functions + Tasks | Auth, FCM, map display |
|---|---|---|---|---|---|
| 1,000 | $0 | $0 | ~$1 | $0 | Free |
| 10,000 | $0–57 | ~$1 | ~$10 | $0 | Free |
| 50,000 | $400–770 | ~$12 | ~$43 | ~$2 | Free |
| 150,000 | $1,300–2,350 | ~$50 | ~$115 | ~$10 | Free |

---

## 3. Which plans to choose

### Firebase: **Blaze (pay-as-you-go)**. Required.
- Your Cloud Functions, and the planned Cloud Tasks dispatch, only run on Blaze.
- Blaze still includes the free allowance: 50k reads and 20k writes a day, 2M function calls a month, 1M Cloud Tasks operations.
- Keep functions in the **same region as Firestore**. Check where your database is in the console: a database's location can't be changed after it's created.

### Google Maps: **pay-as-you-go. Don't subscribe yet.**
| Plan | Price per month | Should you pick it? |
|---|---|---|
| Starter | $100, 50k calls | ❌ Doesn't include Autocomplete, Place Details or Routes |
| Essentials | $275, 100k calls | ⏳ Only worth it above **about 20k trips a month**, and only if you don't use search sessions |
| Pro | $1,200, 250k calls | ❌ Only makes sense if you keep the current code at 5k–11k trips a month. Fixing the code is far cheaper |
| **Pay-as-you-go** | $0 base, 10k free calls per API each month | ✅ **$0 up to about 10k trips a month after the fixes** |

- Use the **$300 trial credit** for new customers to cover testing and the first weeks.
- Review the plan choice when you pass **20k trips a month**. Also ask Google sales about volume discounts once you pass about 100k trips a month.

---

## 4. Ways to save, in order of priority

### 🔴 Must do before launch (Google Maps)
1. **Switch to Places API (New) and use session tokens.** Use Autocomplete (New) with a `sessionToken`. Call Place Details **only when the user taps a result**, with field mask `location` (the Essentials level, $5). → **Saves about 95% of the Maps bill.**
2. **Restrict search** with `includedRegionCodes: ["lb"]` and `locationBias` set to the user's position. Wait for at least 3 characters before searching, and raise the debounce from 500 to 700 ms. → **About 30–40% fewer autocomplete calls.**
3. **Save recent and favourite places** (Home, Work, last 10 destinations) with `shared_preferences`. Show them before any search. → Many trips then need **no Places calls at all.**
4. **Do reverse geocoding on the device** for pin drags with the `geocoding` package you already have. Drop the paid call in [map_provider.dart:927](file:///Users/macbook/Desktop/rider/lib/providers/map_provider.dart#L927-L960). → **Geocoding cost becomes $0.**
5. **Switch to the Routes API** (Compute Routes Essentials) with a field mask. **Cache one route per trip**, and remove the debug `print` of the full response body.

### 🟠 Firestore and Functions
6. **Write driver location only when needed:** after 30–50 m of movement, or at most every 15–20 s while idle. → About **50–60% fewer writes**, which are now the biggest Firebase cost.
7. **Search drivers by area in `findNearbyDrivers`.** Use a geohash range query plus `limit(20)`, so it doesn't read every online driver each round.
8. **Merge the 3 `onDocumentUpdated("trips/{id}")` triggers** (refresh, notifications, rating) into one function. Return early when the fields it cares about haven't changed. → About **3 times fewer function calls.**
9. **Trip history:** use one-off `get()` reads in pages with `limit(20)` instead of live listeners for completed and cancelled trips ([trip_history_screen.dart](file:///Users/macbook/Desktop/rider/lib/screens/trip_history_screen.dart#L340-L349)).
10. **Remove hotspots**, or have it process only new trips. → Saves $0–65 a month.
11. **Put driver location in a small separate document** (`driver_locations/{id}`) so the rider's live listener doesn't download the full driver profile on every update. The read count stays the same, but it uses less data and battery.

### 🟢 Planned dispatch migration ([CLOUD_TASKS_DISPATCH.md](file:///Users/macbook/Desktop/rider/updates/CLOUD_TASKS_DISPATCH.md))
- **Cost is about neutral, and it removes a hidden cost.** Today the app writes `searchRefreshedAt` every 10 s. Each of those writes triggers 3 functions plus a full driver query, up to 12 times per search.
- Moving to Cloud Tasks: about 8 rounds per trip × ~1 s each fits inside the free allowance (1M operations a month) up to about 100k trips.
- Do **#7 (search by area)** together with it, or every round will re-read all online drivers.

---

## 5. Launch checklist (protects against a surprise bill)
- [ ] **Budget alerts** in Cloud Billing at $25, $100 and $500.
- [ ] **Daily quotas for each Maps API** to start with, for example Places 3,000 a day, Routes 2,000 a day, Geocoding 500 a day. Raise them as you grow.
- [ ] **Restrict the API key** to your Android package and SHA-1, your iOS bundle ID, and only the APIs you use.
- [ ] Turn on **Firebase App Check** for Firestore and Functions to block scripted abuse.
- [ ] **Usage dashboard:** check reads, writes and function calls per day weekly for the first month and compare them with this report.
- [ ] Include the **driver app** in the cost review. Its Directions calls for navigation are not counted here.

---

## 6. Expected bill in practice

| Stage | Trips per month | Expected monthly bill (after fixes) |
|---|---|---|
| Testing / soft launch | < 1,000 | **$0** (free allowances + $300 credit) |
| Launch in one city | ~10,000 | **~$10–70** |
| Growth | ~50,000 | **~$450–830** |
| Scale | ~150,000 | **~$1,500–2,500** (ask Google sales for a discount) |
