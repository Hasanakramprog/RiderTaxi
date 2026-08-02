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
  final bool showDriverLocation;
  final String? tripId;
  final bool showCompletedTrip;
  final Map<String, dynamic>? tripData;

  // Drag-to-pin UX: disable tap-to-set and use camera move/idle instead
  final bool isDragPinMode;
  final void Function(LatLng)? onCameraMove;
  final void Function(LatLng)? onCameraIdle;

  const MapWidget({
    Key? key,
    this.allowMapTaps = false,
    this.isPickupSelection = true,
    this.stopIndex = -1,
    this.showDriverLocation = true,
    this.tripId,
    this.showCompletedTrip = false,
    this.tripData,
    this.isDragPinMode = false,
    this.onCameraMove,
    this.onCameraIdle,
  }) : super(key: key);

  @override
  State<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends State<MapWidget> {
  StreamSubscription<DocumentSnapshot>? _tripSubscription;
  StreamSubscription<DocumentSnapshot>? _driverSubscription;
  Marker? _driverMarker;
  late MapProvider _mapProvider;
  Set<Polyline> _polylines = {};

  // Tracks the last camera center for onCameraIdle callback
  LatLng? _lastCameraTarget;

  // Guard flag: prevents camera callbacks from firing after dispose.
  // Switching onCameraMove/onCameraIdle between null and non-null across
  // rebuilds causes GoogleMapController._connectStreams to crash with a
  // null check error. We always pass a non-null closure and check this flag.
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    // Initialize user location when widget is created
    Future.delayed(Duration.zero, () {
      _mapProvider = Provider.of<MapProvider>(context, listen: false);

      // Guard: only initialize location if it hasn't been done yet.
      // Prevents re-triggering GPS + new surface buffer allocation every
      // time AnimatedContainer rebuilds this widget (e.g. fullscreen toggle).
      if (!_mapProvider.hasInitializedLocation) {
        _mapProvider.initializeUserLocation();
      }

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
    _isDisposed = true;

    // Cancel any tracking subscriptions
    _cancelDriverTracking();

    // Dispose the GoogleMapController FIRST to release the GL surface buffer.
    // Without this, the old controller holds onto its ImageReader buffer slot
    // while the next MapWidget tries to allocate a new one, causing:
    // W/ImageReader_JNI: Unable to acquire a buffer item
    _mapProvider.disposeMapController();

    // Then clear markers/polylines
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
              location.latitude != null &&
              location.longitude != null) {
            // Create a driver marker
            final driverPosition = LatLng(
              location.latitude,
              location.longitude,
            );

            setState(() {
              _driverMarker = Marker(
                markerId: const MarkerId('driver'),
                position: driverPosition,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure,
                ),
                infoWindow: InfoWindow(
                  title: 'Your Driver',
                  snippet: driverData['displayName'] ?? 'Driver',
                ),
              );
            });

            // Update the map to show the driver's location
            final mapProvider = Provider.of<MapProvider>(
              context,
              listen: false,
            );
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
        pickup['longitude'] ?? 0.0,
      );

      final dropoffLatLng = LatLng(
        dropoff['latitude'] ?? 0.0,
        dropoff['longitude'] ?? 0.0,
      );

      // Create markers for pickup and dropoff
      final pickupMarker = Marker(
        markerId: const MarkerId('trip_pickup'),
        position: pickupLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: 'Pickup',
          snippet: pickup['address'] ?? 'Pickup location',
        ),
      );

      final dropoffMarker = Marker(
        markerId: const MarkerId('trip_dropoff'),
        position: dropoffLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: 'Dropoff',
          snippet: dropoff['address'] ?? 'Dropoff location',
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
          if (point is Map &&
              point['latitude'] != null &&
              point['longitude'] != null) {
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
        // Map renders immediately — no more full-screen blocking spinner.
        // A small non-intrusive chip is shown while GPS refines the position
        // in the background. The user can already see and interact with the map.
        return Stack(
          children: [
            // The map
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target:
                    mapProvider.pickupLocation?.coordinates ??
                    mapProvider.currentUserLocation,
                zoom: 14.0,
              ),
              onMapCreated: (GoogleMapController controller) {
                mapProvider.setMapController(controller);
              },
              markers: mapProvider.markers,
              polylines: mapProvider.polylines.union(_polylines),
              myLocationEnabled: true,
              myLocationButtonEnabled:
                  false, // Set to false to use custom button
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: true,
              // Always register non-null callbacks to keep GoogleMapController's
              // internal stream connections stable. Toggling null/non-null across
              // rebuilds causes _connectStreams to crash with a null check error.
              // Instead, we guard the logic inside using _isDisposed + isDragPinMode.
              onCameraMove: (CameraPosition pos) {
                if (_isDisposed) return;
                _lastCameraTarget = pos.target;
                if (widget.isDragPinMode) {
                  widget.onCameraMove?.call(pos.target);
                }
              },
              onCameraIdle: () {
                if (_isDisposed) return;
                if (widget.isDragPinMode && _lastCameraTarget != null) {
                  widget.onCameraIdle?.call(_lastCameraTarget!);
                }
              },
              onTap:
                  (!widget.isDragPinMode && widget.allowMapTaps)
                      ? (LatLng position) {
                        // Handle map taps differently based on selection mode
                        if (widget.isPickupSelection) {
                          mapProvider.setPickupLocationFromMap(position);
                        } else if (widget.stopIndex >= 0) {
                          mapProvider.setStopLocationFromMap(
                            position,
                            widget.stopIndex,
                          );
                        } else {
                          mapProvider.setDropoffLocationFromMap(position);
                        }
                      }
                      : null,
            ),

            // Custom current location button with loading indicator
            // Positioned(
            //   right: 10,
            //   bottom: 10, // Position above the zoom controls
            //   child: FloatingActionButton(
            //     mini: true,
            //     backgroundColor: const Color.fromARGB(255, 255, 193, 0),
            //     onPressed: mapProvider.isLoading
            //         ? null // Disable when loading
            //         : () => mapProvider.moveToCurrentLocation(),
            //     child: mapProvider.isLoading
            //         ? const SizedBox(
            //             height: 5,
            //             width: 5,
            //             child: CircularProgressIndicator(
            //               color: Colors.amber,
            //               strokeWidth: 2,
            //             ),
            //           )
            //         : const Icon(
            //             Icons.my_location,
            //             color: Colors.blue,
            //           ),
            //   ),
            // ),

            // Small non-blocking GPS chip — shown while background GPS resolves
            if (mapProvider.isLoading)
              Positioned(
                top: 12,
                left: 12,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 12,
                          width: 12,
                          child: CircularProgressIndicator(
                            color: Colors.amber,
                            strokeWidth: 2,
                          ),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Locating you...',
                          style: TextStyle(fontSize: 11, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
