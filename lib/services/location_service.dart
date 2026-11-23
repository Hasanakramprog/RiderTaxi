import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/location_model.dart';

import '../utils/app_config.dart';

class LocationService {
  final String _googleApiKey = AppConfig.googleMapsApiKey;

  // Get the current user location with timeout and fallback
  Future<Position?> getCurrentLocation() async {
    try {
      print('🗺️ Getting current location with geolocator...');

      // STEP 1: Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('🗺️ Location services are disabled');
        return Future.error('Location services are disabled.');
      }

      // STEP 2: Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('🗺️ Location permissions are denied');
          return Future.error('Location permissions are denied');
        }
      }

      // STEP 3: Check for permanent denial
      if (permission == LocationPermission.deniedForever) {
        print('🗺️ Location permissions are permanently denied');
        return Future.error('Location permissions are permanently denied.');
      }

      // STEP 4: Get current position with TIMEOUT (10 seconds)
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10), // ⏱️ KEY: 10 second timeout
      );

      print(
        '🗺️ Current location obtained: ${position.latitude}, ${position.longitude}',
      );
      return position;
    } on TimeoutException catch (e) {
      // ⚡ CRITICAL: Timeout fallback
      print('🗺️ Location timeout: $e - trying last known position...');
      return await _tryLastKnownPosition();
    } on LocationServiceDisabledException {
      print('🗺️ Location services are disabled');
      return Future.error('Location services are disabled.');
    } on PermissionDeniedException {
      print('🗺️ Location permissions denied');
      return Future.error('Location permissions are denied');
    } catch (e) {
      // ⚡ CRITICAL: Generic error fallback
      print('🗺️ Error getting location: $e');
      return await _tryLastKnownPosition();
    }
  }

  // Fallback to last known position
  Future<Position?> _tryLastKnownPosition() async {
    try {
      Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        print(
          '🗺️ Using last known position: ${lastKnown.latitude}, ${lastKnown.longitude}',
        );
        return lastKnown;
      } else {
        print('🗺️ No last known position available');
        return Future.error('Unable to get location');
      }
    } catch (e) {
      print('🗺️ Could not get last known position: $e');
      return Future.error('Unable to get location');
    }
  }

  // Get address from latitude and longitude
  Future<String> getAddressFromLatLng(LatLng latLng) async {
    try {
      List<Placemark> placemarks = await Geocoding().placemarkFromCoordinates(
        latLng.latitude,
        latLng.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        return '${place.street}, ${place.locality}, ${place.administrativeArea}';
      }
      return 'Unknown location';
    } catch (e) {
      print('Error getting address: $e');
      return 'Error getting address';
    }
  }

  // Search for places using Google Places API (New)
  Future<List<LocationModel>> searchPlaces(String query) async {
    try {
      final url = Uri.parse(
        'https://places.googleapis.com/v1/places:autocomplete',
      );

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _googleApiKey,
        },
        body: json.encode({'input': query}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final suggestions = data['suggestions'] as List? ?? [];

        // Process a maximum of 5 predictions
        final results = <LocationModel>[];

        for (var i = 0; i < suggestions.length && results.length < 5; i++) {
          final prediction =
              suggestions[i]['placePrediction'] as Map<String, dynamic>?;
          if (prediction == null) continue;

          final placeId = prediction['placeId'] as String?;
          if (placeId == null || placeId.isEmpty) continue;

          final description =
              (prediction['text']?['text'] as String?) ?? '';
          final mainText =
              (prediction['structuredFormat']?['mainText']?['text']
                  as String?) ??
              description;

          // Get details for this place to get coordinates
          final locationDetails = await _getPlaceDetails(placeId);

          if (locationDetails != null) {
            results.add(
              LocationModel(
                coordinates: locationDetails,
                address: description,
                name: mainText,
                placeId: placeId,
              ),
            );
          }
        }

        return results;
      }

      return [];
    } catch (e) {
      print('Error searching places: $e');
      return [];
    }
  }

  // Get place details (coordinates) from a place ID using Places API (New)
  Future<LatLng?> _getPlaceDetails(String placeId) async {
    try {
      final url = Uri.parse(
        'https://places.googleapis.com/v1/places/$placeId',
      );

      final response = await http.get(
        url,
        headers: {
          'X-Goog-Api-Key': _googleApiKey,
          'X-Goog-FieldMask': 'location',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final location = data['location'] as Map<String, dynamic>?;

        if (location != null &&
            location['latitude'] != null &&
            location['longitude'] != null) {
          final lat = (location['latitude'] as num).toDouble();
          final lng = (location['longitude'] as num).toDouble();

          return LatLng(lat, lng);
        }
      }

      return null;
    } catch (e) {
      print('Error getting place details: $e');
      return null;
    }
  }
}
