import 'package:google_maps_flutter/google_maps_flutter.dart';

class LocationModel {
  final LatLng coordinates;
  final String address;
  final String name;
  final String placeId;
  
  LocationModel({
    required this.coordinates,
    required this.address,
    required this.name,
    required this.placeId,
  });
}