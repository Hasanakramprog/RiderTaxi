import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/map_provider.dart';
import '../services/location_service.dart';
import '../models/location_model.dart';

class LocationInput extends StatefulWidget {
  final bool isPickup;
  final String hintText;
  final String? initialValue;
  final Function()? onClear;
  
  const LocationInput({
    Key? key,
    required this.isPickup,
    required this.hintText,
    this.initialValue,
    this.onClear,
  }) : super(key: key);

  @override
  State<LocationInput> createState() => _LocationInputState();
}

class _LocationInputState extends State<LocationInput> {
  late TextEditingController _controller;
  final LocationService _locationService = LocationService();
  List<LocationModel> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounce;
  final FocusNode _focusNode = FocusNode();
  bool _showPredictions = false;
  
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode.addListener(_onFocusChange);
  }
  
  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      setState(() {
        _showPredictions = true;
      });
    }
  }
  
  @override
  void didUpdateWidget(LocationInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue) {
      _controller.text = widget.initialValue ?? '';
    }
  }
  
  void _onSearchChanged(String query) {
    // Debounce search to avoid too many API calls
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      // Only search if we have at least 3 characters
      if (query.length >= 3) {
        _searchLocations(query);
      } else {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    });
  }
  
  Future<void> _searchLocations(String query) async {
    setState(() {
      _isSearching = true;
    });
    
    try {
      final results = await _locationService.searchPlaces(query);
      setState(() {
        _searchResults = results;
        _isSearching = false;
        _showPredictions = results.isNotEmpty;
      });
    } catch (e) {
      print('Error searching locations: $e');
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
    }
  }
  
void _selectLocation(LocationModel location) {
  final mapProvider = Provider.of<MapProvider>(context, listen: false);
  
  // Update the controller text
  _controller.text = location.address;
  
  // Set the location in the map provider
  if (widget.isPickup) {
    mapProvider.setPickupLocation(location);
  } else {
    mapProvider.setDropoffLocation(location);
  }
  
  // Hide predictions
  setState(() {
    _showPredictions = false;
  });
  
  // Dismiss keyboard and remove focus
  FocusScope.of(context).unfocus();
}
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: Icon(
              widget.isPickup ? Icons.location_on : Icons.location_searching,
              color: widget.isPickup ? Colors.green : Colors.red,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      // Clear the text
                      _controller.clear();
                      
                      // Clear search results
                      setState(() {
                        _searchResults = [];
                        _showPredictions = false;
                      });
                      
                      // Call the onClear callback if provided
                      if (widget.onClear != null) {
                        widget.onClear!();
                      }
                    },
                  )
                : null,
          ),
        ),
        
        // Show predictions if available
        if (_showPredictions && _searchResults.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(
              maxHeight: 200,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _searchResults.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final location = _searchResults[index];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.place,
                      color: widget.isPickup ? Colors.green : Colors.red,
                    ),
                    title: Text(
                      location.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      location.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    onTap: () => _selectLocation(location),
                  );
                },
              ),
            ),
          )
        else if (_isSearching)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
  
  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }
}