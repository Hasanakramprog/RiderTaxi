import 'dart:math';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import '../models/location_model.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class MapProvider extends ChangeNotifier {
  // Default initial camera position
  final CameraPosition _initialCameraPosition = const CameraPosition(
    target: LatLng(33.8938, 35.5018), // Beirut, Lebanon coordinates
    zoom: 14.0,
  );

  CameraPosition get initialCameraPosition => _initialCameraPosition;

  GoogleMapController? _mapController;
  LocationModel? _pickupLocation;
  LocationModel? _dropoffLocation;
  LatLng _currentUserLocation = const LatLng(0, 0);
  bool _hasInitializedLocation = false;
  bool _isLoading = false;
  final Set<Marker> _markers = {};
  final Set<Marker> _tripMarkers = {};
  final Set<Polyline> _polylines = {};
  double _estimatedFare = 0.0;
  String _currentUserAddress = "";
    // Add this property near other class properties
  bool _hasCustomPickupLocation = false;
  bool get hasCustomPickupLocation => _hasCustomPickupLocation;
  // Add storage for stops with wait time
  List<Map<String, dynamic>> _stops = [];

  // Add these private variables
  double? _estimatedDistance;
  int? _estimatedDuration;

  // Add a new field to track initialization status
  bool _isInitializing = true;
  bool get isInitializing => _isInitializing;

  // Getters
  Set<Marker> get markers {
    final result = <Marker>{};

    // Add existing markers
    result.addAll(_markers);

    // Add trip markers
    result.addAll(_tripMarkers);

    // Add driver marker if available
    // if (_driverMarker != null) {
    //   result.add(_driverMarker!);
    // }

    return result;
  }
  Set<Polyline> get polylines => _polylines;
  GoogleMapController? get mapController => _mapController;
  LocationModel? get pickupLocation => _pickupLocation;
  LocationModel? get dropoffLocation => _dropoffLocation;
  List<Map<String, dynamic>> get stops => _stops;
  bool get isLoading => _isLoading;
  bool get hasInitializedLocation => _hasInitializedLocation;
  LatLng get currentUserLocation => _currentUserLocation;
  double get estimatedFare => _estimatedFare;
  String get currentUserAddress => _currentUserAddress;

  // Add these getters
  double get estimatedDistance {
    // Calculate total distance in km, default to 0 if no route
    // This should be properly calculated in your route calculation method
    return _estimatedDistance ?? 0.0;
  }

  int get estimatedDuration {
    // Calculate total duration in minutes, default to 0 if no route
    // This should be properly calculated in your route calculation method
    return _estimatedDuration ?? 0;
  }

  // Initialize user location
  Future<void> initializeUserLocation() async {
    _isInitializing = true;
    _isLoading = true;
    notifyListeners();

    try {
      Location location = Location();
      bool serviceEnabled;
      PermissionStatus permissionGranted;

      // Check if location service is enabled
      serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) {
          // If service is not available, use default location
          await setDefaultLocation();
          return;
        }
      }

      // Check location permissions
      permissionGranted = await location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          // If permission is denied, use default location
          await setDefaultLocation();
          return;
        }
      }

      try {
        // Attempt to get current location with a timeout
        LocationData locationData = await location.getLocation()
            .timeout(const Duration(seconds: 10));
        
        _currentUserLocation = LatLng(
          locationData.latitude!, 
          locationData.longitude!
        );

        // Get address from coordinates
        _currentUserAddress = await _getAddressFromCoordinates(_currentUserLocation);
        
        // Update flag
        _hasInitializedLocation = true;

        // Only set current location as pickup if no custom location
        if (!_hasCustomPickupLocation && _pickupLocation == null) {
          _pickupLocation = LocationModel(
            placeId: 'current_location',
            address: _currentUserAddress,
            coordinates: _currentUserLocation,
            name: 'Current Location',
          );
        }

        // Update markers and route
        _updateMarkers();

        if (_dropoffLocation != null) {
          _updateRoute();
        }
      } catch (e) {
        print('Error getting current location: $e');
        await setDefaultLocation();
        return;
      }
    } catch (e) {
      print('Error initializing user location: $e');
      await setDefaultLocation();
    } finally {
      _isInitializing = false;
      _isLoading = false;
      notifyListeners();
    }
  }
  // Update setDefaultLocation method
Future<void> setDefaultLocation() async {
  try {
    // Set default location to Beirut, Lebanon
    _currentUserLocation = const LatLng(33.8938, 35.5018);
    _currentUserAddress = "Beirut, Lebanon";
    
    // Update the flag
    _hasInitializedLocation = true;

    // Only set Beirut as pickup if no custom location is set
    if (!_hasCustomPickupLocation && _pickupLocation == null) {
      _pickupLocation = LocationModel(
        placeId: 'default_location',
        address: _currentUserAddress,
        coordinates: _currentUserLocation,
        name: 'Beirut',
      );
    }

    _updateMarkers();
    
    if (_dropoffLocation != null) {
      _updateRoute();
    }
  } catch (e) {
    print('Error setting default location: $e');
  } finally {
    _isInitializing = false;
    _isLoading = false;
    notifyListeners();
  }
}
  // Set map controller
  void setMapController(GoogleMapController controller) {
    _mapController = controller;
    
    // Only move camera if we have initialized location and controller
    if (_hasInitializedLocation && !_isInitializing) {
      // If we have a custom pickup location, use that
      LatLng cameraTarget = _hasCustomPickupLocation && _pickupLocation != null
          ? _pickupLocation!.coordinates
          : _currentUserLocation;
      
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(cameraTarget, 15),
      );
    }
  }

  // Set current location as pickup
  Future<void> setCurrentLocationAsPickup() async {
    if (_hasInitializedLocation) {
      _isLoading = true;
      notifyListeners();

      try {
        // Set pickup location from current user location
        _pickupLocation = LocationModel(
          placeId: 'current_location',
          address: _currentUserAddress,
          coordinates: _currentUserLocation,
          name: 'Current Location',
        );

        _updateMarkers();
        _updateRoute();

        // Animate camera to the current location
        if (_mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLng(_currentUserLocation),
          );
        }
      } catch (e) {
        print('Error setting current location as pickup: $e');
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // Add this new method after setCurrentLocationAsPickup
  Future<void> resetPickupToCurrentLocation() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Re-fetch the current location to make sure it's up to date
      Location location = Location();
      LocationData locationData = await location.getLocation();
      _currentUserLocation = LatLng(locationData.latitude!, locationData.longitude!);

      // Update the address for the current location
      await _getAddressFromCoordinates(_currentUserLocation);

      // Set pickup location to current location
      _pickupLocation = LocationModel(
        placeId: 'current_location',
        address: _currentUserAddress,
        coordinates: _currentUserLocation,
        name: 'Current Location',
      );

      _updateMarkers();
      _updateRoute();

      // Animate camera to the current location
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(_currentUserLocation),
        );
      }
    } catch (e) {
      print('Error resetting pickup to current location: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Set pickup location from LocationModel
  Future<void> setPickupLocation(LocationModel location) async {
    _isLoading = true;
    notifyListeners();

    try {
      _pickupLocation = location;
    _hasCustomPickupLocation = true;
      _updateMarkers();

      // Move camera to the selected location
      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(location.coordinates, 15),
        );
      }

      _updateRoute();
    } catch (e) {
      print('Error setting pickup location: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Set dropoff location from LocationModel
  Future<void> setDropoffLocation(LocationModel location) async {
    _isLoading = true;
    notifyListeners();

    try {
      _dropoffLocation = location;
      _updateMarkers();

      // Move camera to the selected location
      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(location.coordinates, 15),
        );
      }

      _updateRoute();
    } catch (e) {
      print('Error setting dropoff location: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Add a new stop with location and waiting time
  void addStop({LocationModel? location, String address = '', int waitingTime = 0}) {
    _stops.add({
      'location': location,
      'address': address,
      'waitingTime': waitingTime,
    });

    _updateMarkers();
    _updateRoute();
    notifyListeners();
  }

  // Update an existing stop
  void updateStop(int index, {LocationModel? location, String? address, int? waitingTime}) {
    if (index >= 0 && index < _stops.length) {
      if (location != null) {
        _stops[index]['location'] = location;
      }
      if (address != null) {
        _stops[index]['address'] = address;
      }
      if (waitingTime != null) {
        _stops[index]['waitingTime'] = waitingTime;
      }

      _updateMarkers();
      _updateRoute();
      notifyListeners();
    }
  }

  // Remove a stop
  void removeStop(int index) {
    if (index >= 0 && index < _stops.length) {
      _stops.removeAt(index);
      _updateMarkers();
      _updateRoute();
      notifyListeners();
    }
  }

  // Clear all stops
  void clearStops() {
    _stops.clear();
    _updateMarkers();
    _updateRoute();
    notifyListeners();
  }

  // Clear pickup location
  void clearPickupLocation() {
    _pickupLocation = null;
     _hasCustomPickupLocation = false;
    _updateMarkers();
    _updateRoute();
    notifyListeners();
  }
  // Add this method to reset the custom pickup flag
void clearCustomPickupFlag() {
  _hasCustomPickupLocation = false;
}
  // Clear dropoff location
  void clearDropoffLocation() {
    _dropoffLocation = null;
    _updateMarkers();
    _updateRoute();
    notifyListeners();
  }

  // Set pickup location from map tap
  Future<void> setPickupLocationFromMap(LatLng latLng) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Get address from tapped coordinates
      String address = await _getAddressFromCoordinates(latLng);

      // Create new location model
      _pickupLocation = LocationModel(
        placeId: 'map_selected_pickup',
        address: address,
        coordinates: latLng,
        name: 'Selected Pickup',
      );
       // Set custom pickup flag
    _hasCustomPickupLocation = true;

      _updateMarkers();
      _updateRoute();

      // Animate camera to the selected location
      if (_mapController != null) {
        _mapController!.animateCamera(CameraUpdate.newLatLng(latLng));
      }
    } catch (e) {
      print('Error setting pickup from map: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Set dropoff location from map tap
  Future<void> setDropoffLocationFromMap(LatLng latLng) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Get address from tapped coordinates
      String address = await _getAddressFromCoordinates(latLng);

      // Create new location model
      _dropoffLocation = LocationModel(
        placeId: 'map_selected_dropoff',
        address: address,
        coordinates: latLng,
        name: 'Selected Dropoff',
      );

      _updateMarkers();
      _updateRoute();

      // Animate camera to the selected location
      if (_mapController != null) {
        _mapController!.animateCamera(CameraUpdate.newLatLng(latLng));
      }
    } catch (e) {
      print('Error setting dropoff from map: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Set stop location from map tap
  Future<void> setStopLocationFromMap(LatLng latLng, int index) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Get address from tapped coordinates
      String address = await _getAddressFromCoordinates(latLng);

      // Create new location model
      LocationModel stopLocation = LocationModel(
        placeId: 'map_selected_stop_$index',
        address: address,
        coordinates: latLng,
        name: 'Stop ${index + 1}',
      );

      // Update or add stop
      if (index < _stops.length) {
        _stops[index]['location'] = stopLocation;
        _stops[index]['address'] = address;
      } else {
        addStop(location: stopLocation, address: address);
      }

      // Animate camera to the selected location
      if (_mapController != null) {
        _mapController!.animateCamera(CameraUpdate.newLatLng(latLng));
      }
      _updateMarkers();
      _updateRoute();
    } catch (e) {
      print('Error setting stop from map: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update markers based on current locations
  void _updateMarkers() {
    _markers.clear();

    // Add pickup marker if exists
    if (_pickupLocation != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: _pickupLocation!.coordinates,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(title: 'Pickup', snippet: _pickupLocation!.address),
        ),
      );
    }

    // Add stop markers if any
    for (int i = 0; i < _stops.length; i++) {
      if (_stops[i]['location'] != null) {
        final LocationModel location = _stops[i]['location'];
        _markers.add(
          Marker(
            markerId: MarkerId('stop_$i'),
            position: location.coordinates,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
            infoWindow: InfoWindow(title: 'Stop ${i + 1}', snippet: location.address),
          ),
        );
      }
    }

    // Add dropoff marker if exists
    if (_dropoffLocation != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('dropoff'),
          position: _dropoffLocation!.coordinates,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(title: 'Dropoff', snippet: _dropoffLocation!.address),
        ),
      );
    }
  }

  // Update route between all points (pickup -> stops -> dropoff)
  Future<void> _updateRoute() async {
    _polylines.clear();
    _estimatedFare = 0.0;

    // Need at least pickup and dropoff to calculate a route
    if (_pickupLocation == null || _dropoffLocation == null) {
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      // Create list of all waypoints with valid locations (filter out stops without location)
      List<LocationModel> waypoints = [];
      for (var stop in _stops) {
        if (stop['location'] != null) {
          waypoints.add(stop['location']);
        }
      }

      // Process route segments
      LatLng currentPoint = _pickupLocation!.coordinates;
      List<LatLng> allRoutePoints = [];
      double totalDistance = 0;
      int totalDurationMinutes = 0;

      // Process routes: pickup -> stop1 -> stop2 -> ... -> dropoff
      List<LocationModel> allPoints = [_pickupLocation!, ...waypoints, _dropoffLocation!];

      for (int i = 0; i < allPoints.length - 1; i++) {
        final nextPoint = allPoints[i + 1].coordinates;

        // Calculate route for this segment
        List<LatLng> segmentPoints = await _getDirectionsPolyline(currentPoint, nextPoint);

        // Calculate segment distance
        double segmentDistance = _calculateDistance(
          currentPoint.latitude, currentPoint.longitude,
          nextPoint.latitude, nextPoint.longitude
        );
        totalDistance += segmentDistance;

        // Calculate segment duration (simplified, replace with actual API data if available)
        int segmentDuration = (segmentDistance / 0.5).round(); // Assume 0.5 km/min average speed
        totalDurationMinutes += segmentDuration;

        // Add segment to overall route
        if (i == 0) {
          allRoutePoints.addAll(segmentPoints);
        } else {
          allRoutePoints.addAll(segmentPoints.sublist(1)); // Avoid duplicating connecting points
        }

        // Add polyline for this segment
        _polylines.add(
          Polyline(
            polylineId: PolylineId('segment_$i'),
            color: i < allPoints.length - 2 ? Colors.orange : Colors.blue,
            width: 5,
            points: segmentPoints,
          ),
        );

        // Update current point for next iteration
        currentPoint = nextPoint;
      }

      // Calculate estimated fare based on distance and stops
      double baseFare = 5.0 + (2.5 * totalDistance);
      double stopCharge = _stops.length * 2.0; // $2 per stop
      double waitingCharge = 0;
      for (var stop in _stops) {
        waitingCharge += (stop['waitingTime'] ?? 0) * 0.5; // $0.50 per minute
      }
      _estimatedFare = baseFare + stopCharge + waitingCharge;

      // Store the total distance and duration
      _estimatedDistance = totalDistance; // Total distance in km
      _estimatedDuration = totalDurationMinutes; // Total duration in minutes

      // Adjust map camera to show the entire route
      if (_mapController != null && allRoutePoints.isNotEmpty) {
        LatLngBounds bounds = _getBounds(allRoutePoints);
        _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
      }
    } catch (e) {
      print('Error updating route: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Helper function to get directions polyline between two points
  Future<List<LatLng>> _getDirectionsPolyline(LatLng origin, LatLng destination) async {
    List<LatLng> polylineCoordinates = [];

    try {
      // This is a simplified implementation. In a real app, you'd use your API key.
      String apiKey = "AIzaSyBghYBLMtYdxteEo5GXM6eTdF_8Cc47tis"; // Replace with your API key

      // Prepare the URL for the API request
      final String baseUrl = 'https://maps.googleapis.com/maps/api/directions/json';
      final String url = '$baseUrl?origin=${origin.latitude},${origin.longitude}'
          '&destination=${destination.latitude},${destination.longitude}'
          '&mode=driving'
          '&key=$apiKey';

      // Make the request
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);

        // Check for valid response
        if (decoded['status'] == 'OK') {
          // Get the encoded polyline
          final points = decoded['routes'][0]['overview_polyline']['points'];

          // Decode the polyline
          PolylinePoints polylinePoints = PolylinePoints();
          List<PointLatLng> decodedPolylinePoints = polylinePoints.decodePolyline(points);

          // Convert to LatLng coordinates
          polylineCoordinates = decodedPolylinePoints
              .map((point) => LatLng(point.latitude, point.longitude))
              .toList();
        } else {
          // Fallback: direct line between points if API fails
          polylineCoordinates = [origin, destination];
        }
      } else {
        // Fallback: direct line between points if request fails
        polylineCoordinates = [origin, destination];
      }
    } catch (e) {
      print('Error getting directions: $e');
      // Fallback: direct line between points if exception
      polylineCoordinates = [origin, destination];
    }

    return polylineCoordinates;
  }

  // Helper function to get address from coordinates
  Future<String> _getAddressFromCoordinates(LatLng coordinates) async {
    try {
      // This is a simplified implementation. In a real app, you'd use your API key.
      String apiKey = "AIzaSyBghYBLMtYdxteEo5GXM6eTdF_8Cc47tis"; // Replace with your API key
      final url = 'https://maps.googleapis.com/maps/api/geocode/json'
          '?latlng=${coordinates.latitude},${coordinates.longitude}'
          '&key=$apiKey';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK') {
          final address = data['results'][0]['formatted_address'];

          // Update current user address if these are user coordinates
          if (coordinates.latitude == _currentUserLocation.latitude &&
              coordinates.longitude == _currentUserLocation.longitude) {
            _currentUserAddress = address;
          }

          return address;
        }
      }

      // Fallback if geocoding fails
      return '${coordinates.latitude}, ${coordinates.longitude}';
    } catch (e) {
      print('Error getting address: $e');
      return '${coordinates.latitude}, ${coordinates.longitude}';
    }
  }

  // Helper function to calculate distance between two points in km
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // in km

    double dLat = _toRadians(lat2 - lat1);
    double dLon = _toRadians(lon1 - lon2);

    double a = (
      (dLat / 2).sin().pow(2) +
      (lat1).toRadians().cos() *
      (lat2).toRadians().cos() *
      (dLon / 2).sin().pow(2)
    );

    double c = 2 * a.sqrt().asin();
    double distance = earthRadius * c;

    return distance;
  }

  // Helper function to convert degrees to radians
  double _toRadians(double degrees) {
    return degrees * (pi / 180);
  }

  // Helper function to get bounds for a list of coordinates
  LatLngBounds _getBounds(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (LatLng point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  // Add this method to your MapProvider class
  double calculateAdditionalCharges(double stopCharge, double waitingChargePerMinute) {
    double additionalCharge = 0;
    
    // Charge for each stop
    additionalCharge += _stops.length * stopCharge;
    
    // Charge for waiting time
    for (var stop in _stops) {
      additionalCharge += (stop['waitingTime'] ?? 0) * waitingChargePerMinute;
    }
    
    return additionalCharge;
  }

  // Animate camera to bounds
  void animateToLatLngBounds(LatLngBounds bounds, double padding) {
    if (_mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, padding));
    }
  }

  // Add/update the driver marker to the markers set
  void updateDriverLocation(Marker driverMarker) {
    _markers.removeWhere((marker) => marker.markerId.value == 'driver');
    _markers.add(driverMarker);
    notifyListeners();
  }
  
  // Remove driver marker from the markers set
  void removeDriverLocation() {
    _markers.removeWhere((marker) => marker.markerId.value == 'driver');
    // notifyListeners();
  }

  // Add methods to manage trip markers and polylines
  void addTripMarker(Marker marker) {
    _tripMarkers.removeWhere((m) => m.markerId == marker.markerId);
    _tripMarkers.add(marker);
    notifyListeners();
  }
  
  void clearTripMarkers() {
    _tripMarkers.clear();
    notifyListeners();
  }
  
  void setPolyline(Polyline polyline) {
    _polylines.clear();
    _polylines.add(polyline);
    notifyListeners();
  }
  
  void clearPolylines() {
    _polylines.clear();
    notifyListeners();
  }

  // Add this method to your MapProvider class
  void clearAllMapResources() {
    // Clear all markers
    _markers.clear();
    _tripMarkers.clear();
    // _driverMarker = null;
    
    // Clear all polylines
    _polylines.clear();
    
    // Reset any active selections or routes
    // _selectedPickupLocation = null;
    // _selectedDropoffLocation = null;
    // _routeInfo = null;
    
    // Notify listeners about these changes
    // notifyListeners();
  }

  // Add to MapProvider class
  void disposeMapController() {
    if (_mapController != null) {
      _mapController!.dispose();
      _mapController = null;
    }
  }

  // Add this method to handle current location button clicks
Future<void> moveToCurrentLocation() async {
  // Set loading state
  _isLoading = true;
  notifyListeners();

  try {
    // Try to get fresh location data
    Location location = Location();
    LocationData? locationData;
    
    try {
      // Try to get current location with timeout
      locationData = await location.getLocation().timeout(const Duration(seconds: 10));
      
      // Update current location
      _currentUserLocation = LatLng(
        locationData.latitude!, 
        locationData.longitude!
      );

      // Get address from coordinates
      _currentUserAddress = await _getAddressFromCoordinates(_currentUserLocation);
    } catch (e) {
      print('Error getting current location: $e');
      // Continue with existing location data if we can't get a fresh location
    }

    // If we have a map controller, animate to the current location
    if (_mapController != null) {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_currentUserLocation, 15),
      );
    }
  } catch (e) {
    print('Error moving to current location: $e');
  } finally {
    _isLoading = false;
    notifyListeners();
  }
}
}

// Extensions for math operations
extension on double {
  double toRadians() => this * (pi / 180);
  double sin() => math.sin(this);
  double cos() => math.cos(this);
  double sqrt() => math.sqrt(this);
  double asin() => math.asin(this);
  double pow(double exponent) => math.pow(this, exponent).toDouble();
}