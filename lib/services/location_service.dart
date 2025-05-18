import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/location_model.dart';

class LocationService {
  final String _googleApiKey = 'AIzaSyBghYBLMtYdxteEo5GXM6eTdF_8Cc47tis'; // Replace with your API key
  
  // Get the current user location
  Future<Position?> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;
    
    // Test if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }
    
    // Check for location permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied.');
    }
    
    // Get the current position
    return await Geolocator.getCurrentPosition();
  }
  
  // Get address from latitude and longitude
  Future<String> getAddressFromLatLng(LatLng latLng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
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
  
  // Search for places using Google Places API
  Future<List<LocationModel>> searchPlaces(String query) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=$query'
        '&types=geocode'
        '&key=$_googleApiKey'
      );
      
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK') {
          final predictions = data['predictions'] as List;
          
          // Process a maximum of 5 predictions
          final results = <LocationModel>[];
          
          for (var i = 0; i < predictions.length && i < 5; i++) {
            final prediction = predictions[i];
            final placeId = prediction['place_id'] as String;
            final description = prediction['description'] as String;
            
            // Get details for this place to get coordinates
            final locationDetails = await _getPlaceDetails(placeId);
            
            if (locationDetails != null) {
              results.add(LocationModel(
                coordinates: locationDetails,
                address: description,
                name: prediction['structured_formatting']['main_text'] as String,
                placeId: placeId
              ));
            }
          }
          
          return results;
        }
      }
      
      return [];
    } catch (e) {
      print('Error searching places: $e');
      return [];
    }
  }
  
  // Get place details (coordinates) from a place ID
  Future<LatLng?> _getPlaceDetails(String placeId) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=$placeId'
        '&fields=geometry'
        '&key=$_googleApiKey'
      );
      
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK') {
          final lat = data['result']['geometry']['location']['lat'] as double;
          final lng = data['result']['geometry']['location']['lng'] as double;
          
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