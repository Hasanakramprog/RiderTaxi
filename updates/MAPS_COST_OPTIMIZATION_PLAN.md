# Google Maps Cost Optimization Plan (On-Device Pin-Drag Geocoding + Smart Route Caching & Rate-Limiting)

> **Status:** Planned (Ready to Implement)  
> **Target Files:**
> - [`lib/providers/map_provider.dart`](file:///Users/macbook/Desktop/rider/lib/providers/map_provider.dart)
> - [`lib/screens/trip_request_screen_pro.dart`](file:///Users/macbook/Desktop/rider/lib/screens/trip_request_screen_pro.dart)
>
> **Related Report:** [`updates/final_cost_report.md`](./final_cost_report.md)

---

## 1. Executive Summary & Goal

Because the Rider app uses a **Drag-to-Pin UX** in [`TripRequestScreenPro`](file:///Users/macbook/Desktop/rider/lib/screens/trip_request_screen_pro.dart) (and does not use typing autocomplete), 100% of your Google Maps API cost comes from just **two HTTP calls** inside [`lib/providers/map_provider.dart`](file:///Users/macbook/Desktop/rider/lib/providers/map_provider.dart):

1. **Reverse Geocoding on Pin Release ([`_getAddressFromCoordinates`](file:///Users/macbook/Desktop/rider/lib/providers/map_provider.dart#L927-L959)):** Calls `maps.googleapis.com/maps/api/geocode/json` ($5.00 per 1,000 calls) every time the user stops dragging the pin.
2. **Route Polyline Fetching ([`_updateRoute`](file:///Users/macbook/Desktop/rider/lib/providers/map_provider.dart#L773-L878) & [`_getDirectionsPolyline`](file:///Users/macbook/Desktop/rider/lib/providers/map_provider.dart#L881-L924)):** Calls `maps.googleapis.com/maps/api/directions/json` ($5.00 per 1,000 calls) across 19 uncached trigger points and loops separately for each stop.

### Cost Impact of This Plan (at 50,000 Trips / Month)
| Cost Component | Before This Plan | After This Plan |
| :--- | :--- | :--- |
| **Pin-Drag Reverse Geocoding** (~200k drags/mo) | **~$950 / mo** | **$0.00 / mo** (100% free on-device OS geocoder) |
| **Google Directions API** | **~$325 / mo** | **~$200 / mo** (or **$0** up to 10k trips/mo; covered by $300 credit) |
| **Total Google Maps + Firebase (50k trips)** | **~$1,327 / mo** | **~$252 / mo** (**$0 out of pocket** with $300 credit) |

---

## 2. Part 1 — Free On-Device Pin-Drag Reverse Geocoding (`$0.00`)

### Current Problem
In [`map_provider.dart:927-959`](file:///Users/macbook/Desktop/rider/lib/providers/map_provider.dart#L927-L959), `_getAddressFromCoordinates(LatLng coordinates)` immediately makes a paid HTTP request to `https://maps.googleapis.com/maps/api/geocode/json`.

### Solution
Use `placemarkFromCoordinates()` from the `geocoding` package (already installed in `pubspec.yaml` and used in [`location_service.dart`](file:///Users/macbook/Desktop/rider/lib/services/location_service.dart#L82-L105)), which uses Apple's free `CLGeocoder` on iOS and Android's free `Geocoder` on Android, plus a small in-memory coordinate cache:

1. **Grid-Snap Cache (~11m):** Round `latitude` and `longitude` to 4 decimal places (`33.8938, 35.5018`). If the address for that 11m cell is already in `_geocodeCache`, return it immediately in `0ms`.
2. **Primary (Free On-Device Geocoder):** Call `placemarkFromCoordinates(coordinates.latitude, coordinates.longitude)` and format `[street, subLocality, locality]`.
3. **Fallback Only:** Only call the Google HTTP Geocoding API if the device geocoder throws an exception or returns no placemarks.

### Implementation Snippet (`lib/providers/map_provider.dart`)

```dart
import 'package:geocoding/geocoding.dart';

// Add to MapProvider fields:
final Map<String, String> _geocodeCache = {};

String _coordKey(LatLng c, {int decimals = 4}) =>
    '${c.latitude.toStringAsFixed(decimals)},${c.longitude.toStringAsFixed(decimals)}';

Future<String> _getAddressFromCoordinates(LatLng coordinates) async {
  final key = _coordKey(coordinates);
  if (_geocodeCache.containsKey(key)) {
    return _geocodeCache[key]!;
  }

  // 1. FREE On-Device Reverse Geocoding (iOS CLGeocoder / Android Geocoder)
  try {
    final placemarks = await placemarkFromCoordinates(
      coordinates.latitude,
      coordinates.longitude,
    );

    if (placemarks.isNotEmpty) {
      final place = placemarks.first;
      final parts = <String>[
        if (place.street != null && place.street!.trim().isNotEmpty)
          place.street!.trim(),
        if (place.subLocality != null && place.subLocality!.trim().isNotEmpty)
          place.subLocality!.trim(),
        if (place.locality != null && place.locality!.trim().isNotEmpty)
          place.locality!.trim(),
      ];

      // Deduplicate identical consecutive parts (e.g. street == subLocality)
      final uniqueParts = <String>[];
      for (final p in parts) {
        if (!uniqueParts.contains(p)) uniqueParts.add(p);
      }

      if (uniqueParts.isNotEmpty) {
        final address = uniqueParts.join(', ');
        _geocodeCache[key] = address;
        if (coordinates.latitude == _currentUserLocation.latitude &&
            coordinates.longitude == _currentUserLocation.longitude) {
          _currentUserAddress = address;
        }
        return address;
      }
    }
  } catch (e) {
    // Device geocoder unavailable or offline — fall through to HTTP fallback
    print('On-device geocoder fallback: $e');
  }

  // 2. Fallback: Google HTTP Geocoding API (only if on-device fails)
  try {
    final String apiKey = AppConfig.googleMapsApiKey;
    final url =
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${coordinates.latitude},${coordinates.longitude}'
        '&key=$apiKey';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['status'] == 'OK' && (data['results'] as List).isNotEmpty) {
        final address = data['results'][0]['formatted_address'] as String;
        _geocodeCache[key] = address;
        if (coordinates.latitude == _currentUserLocation.latitude &&
            coordinates.longitude == _currentUserLocation.longitude) {
          _currentUserAddress = address;
        }
        return address;
      }
    }
  } catch (e) {
    print('Error in HTTP geocoding fallback: $e');
  }

  return '${coordinates.latitude.toStringAsFixed(5)}, ${coordinates.longitude.toStringAsFixed(5)}';
}
```

---

## 3. Part 2 — Smart Route Caching & 5-Layer Directions API Protection

To prevent both code redundancy and user abuse (e.g., a user repeatedly tapping *Back -> Drag Pin -> Confirm* 20 times without booking), we enforce **5 layers of protection** on `_updateRoute()`:

### Protection 1: Stop Intermediate Route Calls (Fetch Only When Needed)
* **Remove `_updateRoute()` from:**
  * `setPickupLocationSilent()` (called on Step 1 before Dropoff is confirmed)
  * `addStop()` (called when adding an empty stop slot before its location is chosen)
  * `updateStop()` when only `waitingTime` changed (changing waiting minutes only affects `_estimatedFare`, not the road polyline!).
  * `clearPickupLocation()` / `clearDropoffLocation()` / `clearStops()` (simply clear `_polylines.clear()` directly).

### Protection 2: Coordinate-Rounded Route Cache (`~11m` Grid Snap)
* Build a deterministic route signature key from rounded coordinates (4 decimal places = `~11m`):
  `routeKey = "pickupLat,pickupLng|stop1Lat,stop1Lng|...|dropoffLat,dropoffLng"`
* Store `Map<String, List<LatLng>> _routePolylineCache = {}`.
* If `_routePolylineCache.containsKey(routeKey)` is true:
  * Reuse the cached polyline points immediately (**0 HTTP calls**).
  * Recalculate `_estimatedFare`, `_estimatedDistance`, and `_estimatedDuration` locally.

### Protection 3: Combine Multi-Stop Trips into 1 Single Directions Call (`&waypoints=`)
* Currently, [`_updateRoute()`](file:///Users/macbook/Desktop/rider/lib/providers/map_provider.dart#L808-L815) loops over every segment (`Pickup -> Stop 1`, `Stop 1 -> Dropoff`), making multiple HTTP requests for 1 trip.
* **Fix:** Pass intermediate stops in a single HTTP request using `&waypoints=lat1,lng1|lat2,lng2`:
  ```
  https://maps.googleapis.com/maps/api/directions/json
    ?origin=pickupLat,pickupLng
    &destination=dropoffLat,dropoffLng
    &waypoints=stop1Lat,stop1Lng|stop2Lat,stop2Lng
    &mode=driving
    &key=$apiKey
  ```
* Also remove the verbose debug print `print('🗺️ [DIRECTIONS DEBUG] Response body: ${rawResponse.body}')` on [line 899](file:///Users/macbook/Desktop/rider/lib/providers/map_provider.dart#L899).

### Protection 4: Per-Booking Session Cap (Max 3 Directions Calls) + 5s Cooldown
* Note that your app **already calculates `_estimatedDistance` and `_estimatedFare` locally** using Haversine math (`_calculateDistance`). The Directions API is **only** used for drawing the visual road curve on the map.
* Add two anti-abuse guards in `MapProvider`:
  * `static const int _maxDirectionsCallsPerSession = 3;`
  * `int _directionsCallsInSession = 0;` (reset inside `resetTripData()` when a trip finishes or resets)
  * `DateTime? _lastDirectionsCallAt;` (minimum **5-second cooldown** between uncached HTTP calls)
* If a user changes pins more than **3 times** in a single booking session (or faster than once every 5 seconds):
  * `_estimatedDistance`, `_estimatedDuration`, and `_estimatedFare` **still update 100% accurately**.
  * The map draws the clean fallback line connecting `[pickup, ...stops, dropoff]` **without making another paid Google Directions call**.

### Protection 5: Minimum Distance Guard (`< 150 meters`)
* If total distance between Pickup and Dropoff is `< 0.15 km` (150 meters), draw `[origin, destination]` directly without calling Google Directions API.

---

## 4. Summary of Behaviour After Implementation

| User Action | Directions API Calls Before | Directions API Calls After | Reverse Geocode API Calls After |
| :--- | :--- | :--- | :--- |
| Dragging pin 5 times to pick Pickup & Dropoff | 0 | **0** | **0** (On-device free) |
| Confirming Pickup, then confirming Dropoff | 1–2 | **1** | **0** (On-device free) |
| Switching between Bike / Standard / Female / XL / VIP | 0 | **0** | **0** |
| Changing stop waiting time (+5 min, +10 min) | 1 per tap | **0** (Cached) | **0** |
| Trip with 2 stops (`Pickup -> Stop 1 -> Stop 2 -> Dropoff`) | 3 | **1** (`&waypoints=`) | **0** (On-device free) |
| User spams *Back -> Move Pin -> Confirm* 15 times | 15 | **Max 3** (Session cap) | **0** (On-device free) |

---

## 5. Verification Checklist When Implementing

- [ ] Dragging and releasing Pickup, Stop, and Dropoff pins in `TripRequestScreenPro` resolves street/area names via `placemarkFromCoordinates` with **0 Google Geocoding HTTP calls**.
- [ ] Confirming Pickup + Dropoff makes **exactly 1** Directions API call and draws the polyline.
- [ ] Tapping Back and re-confirming the same spot (within ~11m) uses `_routePolylineCache` (**0 new HTTP calls**).
- [ ] Adding stops uses `&waypoints=` in a **single** Directions API call.
- [ ] Changing stop waiting time updates the fare immediately with **0 Directions API calls**.
- [ ] Moving and re-confirming the pin more than 3 times in one session caps HTTP calls at **3** while still updating distance and fare accurately.
- [ ] `flutter analyze` passes with 0 errors.

