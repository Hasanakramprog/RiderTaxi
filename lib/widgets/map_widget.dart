import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'dart:math';
import '../providers/map_provider.dart';

class MapWidget extends StatefulWidget {
  final bool allowMapTaps;
  final bool isPickupSelection;
  final int stopIndex; // -1 for pickup/dropoff, 0+ for stops
  final bool showDriverLocation; // Add this parameter
  final String? tripId; // Add this parameter
  // Add these parameters
  final bool showCompletedTrip;
  final Map<String, dynamic>? tripData;
  
  const MapWidget({
    Key? key, 
    this.allowMapTaps = false,
    this.isPickupSelection = true,
    this.stopIndex = -1,
    this.showDriverLocation = false, // Default to false
    this.tripId, // Optional parameter
    this.showCompletedTrip = false, // Add this parameter
    this.tripData, // Add this parameter
  }) : super(key: key);

  @override
  State<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends State<MapWidget> {
  StreamSubscription<DocumentSnapshot>? _tripSubscription;
  StreamSubscription<DocumentSnapshot>? _driverSubscription;
  Marker? _driverMarker;
  late MapProvider _mapProvider;
  // Add a polyline set for routes
  Set<Polyline> _polylines = {};
  
  @override
  void initState() {
    super.initState();
    // Initialize user location when widget is created
    Future.delayed(Duration.zero, () {
     _mapProvider = Provider.of<MapProvider>(context, listen: false);
      _mapProvider.initializeUserLocation();
      
      // Set up driver tracking if needed
      if (widget.showDriverLocation && widget.tripId != null) {
        _setupDriverTracking();
      }
      
      // Show completed trip route if needed
      if (widget.showCompletedTrip && widget.tripData != null) {
        _showCompletedTripRoute();
      }
    });
  }
  
  @override
  void didUpdateWidget(MapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Handle changes to showDriverLocation or tripId
    if (widget.showDriverLocation != oldWidget.showDriverLocation ||
        widget.tripId != oldWidget.tripId) {
      if (widget.showDriverLocation && widget.tripId != null) {
        _setupDriverTracking();
      } else {
        _cancelDriverTracking();
      }
    }
    
    // Handle changes to showCompletedTrip or tripData
    if ((widget.showCompletedTrip != oldWidget.showCompletedTrip) ||
        (widget.tripData != oldWidget.tripData)) {
      if (widget.showCompletedTrip && widget.tripData != null) {
        _showCompletedTripRoute();
      }
    }
  }
  
  @override
void dispose() {
  // Cancel any tracking subscriptions
  _cancelDriverTracking();
  
  // Clear map resources when widget is disposed
  // Get MapProvider before widget is disposed
 _clearMapResources(_mapProvider);
  
  super.dispose();
}

// Add this new method to clear map resources
void _clearMapResources(MapProvider? mapProvider) {
  try {
    // Clear provider resources if available
    if (mapProvider != null) {
      mapProvider.clearAllMapResources();
    }
    
    // Clear local polylines
    _polylines.clear();
    
  } catch (e) {
    print('Error clearing map resources: $e');
  }
}
  
  void _setupDriverTracking() {
    _cancelDriverTracking(); // Cancel any existing subscriptions
    
    if (widget.tripId == null) return;
    
    // First, get the trip to find the driver ID
    _tripSubscription = FirebaseFirestore.instance
        .collection('trips')
        .doc(widget.tripId)
        .snapshots()
        .listen((tripSnapshot) {
      if (!tripSnapshot.exists) return;
      
      final tripData = tripSnapshot.data()!;
      final driverId = tripData['driverId'] ?? tripData['notifiedDriverId'];
      
      if (driverId != null) {
        // Now track the driver's location
        _trackDriverLocation(driverId);
      }
    });
  }
  
  void _trackDriverLocation(String driverId) {
    _driverSubscription?.cancel();
    
    _driverSubscription = FirebaseFirestore.instance
        .collection('drivers')
        .doc(driverId)
        .snapshots()
        .listen((driverSnapshot) {
      if (!driverSnapshot.exists) return;
      
      final driverData = driverSnapshot.data()!;
      final location = driverData['location'];
      
      if (location != null && 
          location['latitude'] != null && 
          location['longitude'] != null) {
        
        // Create a driver marker
        final driverPosition = LatLng(
          location['latitude'],
          location['longitude'],
        );
        
        setState(() {
          _driverMarker = Marker(
            markerId: const MarkerId('driver'),
            position: driverPosition,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            infoWindow: InfoWindow(
              title: 'Your Driver',
              snippet: driverData['displayName'] ?? 'Driver',
            ),
          );
        });
        
        // Update the map to show the driver's location
        final mapProvider = Provider.of<MapProvider>(context, listen: false);
        mapProvider.updateDriverLocation(_driverMarker!);
        
        // Adjust camera to include both pickup and driver
        if (mapProvider.pickupLocation != null) {
          _updateCameraForDriverAndPickup(
            driverPosition, 
            mapProvider.pickupLocation!.coordinates,
            mapProvider,
          );
        }
      }
    });
  }
  
  void _updateCameraForDriverAndPickup(
    LatLng driverPosition, 
    LatLng pickupPosition,
    MapProvider mapProvider,
  ) {
    // Calculate bounds that include both driver and pickup
    final southwest = LatLng(
      min(driverPosition.latitude, pickupPosition.latitude) - 0.01,
      min(driverPosition.longitude, pickupPosition.longitude) - 0.01,
    );
    
    final northeast = LatLng(
      max(driverPosition.latitude, pickupPosition.latitude) + 0.01,
      max(driverPosition.longitude, pickupPosition.longitude) + 0.01,
    );
    
    final bounds = LatLngBounds(southwest: southwest, northeast: northeast);
    mapProvider.animateToLatLngBounds(bounds, 50);
  }
  
  void _cancelDriverTracking() {
    _tripSubscription?.cancel();
    _tripSubscription = null;
    
    _driverSubscription?.cancel();
    _driverSubscription = null;
    
    // Remove driver marker
    if (_driverMarker != null) {
      final mapProvider = Provider.of<MapProvider>(context, listen: false);
      mapProvider.removeDriverLocation();
      _driverMarker = null;
    }
  }
  
  // Add this method to show completed trip route
  void _showCompletedTripRoute() async {
    try {
      final pickup = widget.tripData?['pickup'];
      final dropoff = widget.tripData?['dropoff'];
      
      if (pickup == null || dropoff == null) return;
      
      final pickupLatLng = LatLng(
        pickup['latitude'] ?? 0.0, 
        pickup['longitude'] ?? 0.0
      );
      
      final dropoffLatLng = LatLng(
        dropoff['latitude'] ?? 0.0, 
        dropoff['longitude'] ?? 0.0
      );
      
      // Create markers for pickup and dropoff
      final pickupMarker = Marker(
        markerId: const MarkerId('trip_pickup'),
        position: pickupLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: 'Pickup', 
          snippet: pickup['address'] ?? 'Pickup location'
        ),
      );
      
      final dropoffMarker = Marker(
        markerId: const MarkerId('trip_dropoff'),
        position: dropoffLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: 'Dropoff', 
          snippet: dropoff['address'] ?? 'Dropoff location'
        ),
      );
      
      // Add markers to map provider
      final mapProvider = Provider.of<MapProvider>(context, listen: false);
      mapProvider.addTripMarker(pickupMarker);
      mapProvider.addTripMarker(dropoffMarker);
      
      // Get route polyline points
      final routePoints = widget.tripData?['routePoints'];
      
      if (routePoints != null && routePoints is List) {
        final List<LatLng> polylinePoints = [];
        
        for (var point in routePoints) {
          if (point is Map && point['latitude'] != null && point['longitude'] != null) {
            polylinePoints.add(LatLng(point['latitude'], point['longitude']));
          }
        }
        
        if (polylinePoints.isNotEmpty) {
          // Create a polyline
          final polyline = Polyline(
            polylineId: const PolylineId('trip_route'),
            points: polylinePoints,
            color: Colors.blue,
            width: 5,
          );
          
          // Add polyline to map
          setState(() {
            _polylines = {polyline};
          });
          
          // Also add to map provider
          mapProvider.setPolyline(polyline);
        } else {
          // Fallback - if no polyline points, just draw a straight line
          final polyline = Polyline(
            polylineId: const PolylineId('trip_route'),
            points: [pickupLatLng, dropoffLatLng],
            color: Colors.blue,
            width: 5,
          );
          
          setState(() {
            _polylines = {polyline};
          });
          
          mapProvider.setPolyline(polyline);
        }
      }
      
      // Animate camera to show the entire route
      final bounds = LatLngBounds(
        southwest: LatLng(
          min(pickupLatLng.latitude, dropoffLatLng.latitude) - 0.01,
          min(pickupLatLng.longitude, dropoffLatLng.longitude) - 0.01,
        ),
        northeast: LatLng(
          max(pickupLatLng.latitude, dropoffLatLng.latitude) + 0.01,
          max(pickupLatLng.longitude, dropoffLatLng.longitude) + 0.01,
        ),
      );
      
      // Animate to bounds with padding
      mapProvider.animateToLatLngBounds(bounds, 50);
    } catch (e) {
      print('Error showing completed trip route: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Consumer<MapProvider>(
      builder: (context, mapProvider, _) {
        return GoogleMap(
          initialCameraPosition: mapProvider.initialCameraPosition,
          onMapCreated:(GoogleMapController controller) {
                mapProvider.setMapController(controller);
              },
          markers: mapProvider.markers,
          polylines: mapProvider.polylines.union(_polylines), // Include local polylines
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          zoomControlsEnabled: true,
          mapToolbarEnabled: false,
          compassEnabled: true,
          onTap: widget.allowMapTaps ? (LatLng position) {
            // Handle map taps differently based on selection mode
            if (widget.isPickupSelection) {
              mapProvider.setPickupLocationFromMap(position);
            } else if (widget.stopIndex >= 0) {
              // Use the MapProvider's method to set stop location
              mapProvider.setStopLocationFromMap(position, widget.stopIndex);
            } else {
              mapProvider.setDropoffLocationFromMap(position);
            }
          } : null,
        );
      },
    );
  }
}
