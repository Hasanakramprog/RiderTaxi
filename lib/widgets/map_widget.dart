import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/map_provider.dart';

class MapWidget extends StatefulWidget {
  final bool allowMapTaps;
  final bool isPickupSelection;
  final int stopIndex; // -1 for pickup/dropoff, 0+ for stops
  
  const MapWidget({
    Key? key, 
    this.allowMapTaps = false,
    this.isPickupSelection = true,
    this.stopIndex = -1,
  }) : super(key: key);

  @override
  State<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends State<MapWidget> {
  @override
  void initState() {
    super.initState();
    // Initialize user location when widget is created
    Future.delayed(Duration.zero, () {
      final mapProvider = Provider.of<MapProvider>(context, listen: false);
      mapProvider.initializeUserLocation();
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Consumer<MapProvider>(
      builder: (context, mapProvider, _) {
        // Use the current user location if available, otherwise default coordinates
        final initialPosition = mapProvider.hasInitializedLocation 
            ? mapProvider.currentUserLocation 
            : const LatLng(0, 0);
            
        return Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: initialPosition,
                zoom: 15,
              ),
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              mapType: MapType.normal,
              zoomControlsEnabled: false,
              markers: mapProvider.markers,
              polylines: mapProvider.polylines,
              onMapCreated: (GoogleMapController controller) {
                mapProvider.setMapController(controller);
              },
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
            ),
            
            // Loading indicator
            if (mapProvider.isLoading)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        );
      },
    );
  }
}
