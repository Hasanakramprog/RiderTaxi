import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/map_provider.dart';
import '../providers/firestore_provider.dart';
import '../widgets/map_widget.dart';
import 'trip_tracking_screen.dart';

class TripRequestScreen extends StatefulWidget {
  const TripRequestScreen({Key? key}) : super(key: key);

  @override
  State<TripRequestScreen> createState() => _TripRequestScreenState();
}

class _TripRequestScreenState extends State<TripRequestScreen>
    with TickerProviderStateMixin {
  bool _showFullMap = false;
  bool _isMapSelectionMode = false;
  bool _isPickupSelection = true;
  int _currentStopIndex = -1;
  String _selectedCarType = 'standard';

  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  final double _stopCharge = 2.0;
  final double _waitingChargePerMinute = 0.5;

  final List<Map<String, dynamic>> _carTypes = [
    {
      'id': 'standard',
      'name': 'Standard',
      'icon': Icons.directions_car,
      'description': 'Comfortable & Affordable',
      'capacity': '4 seats',
      'price': 1.0,
    },
    {
      'id': 'xl',
      'name': 'XL',
      'icon': Icons.airport_shuttle,
      'description': 'Extra Space',
      'capacity': '6 seats',
      'price': 1.5,
    },
    {
      'id': 'vip',
      'name': 'VIP',
      'icon': Icons.electric_car,
      'description': 'Premium Experience',
      'capacity': '4 seats',
      'price': 2.0,
    },
  ];

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeIn));

    _slideController.forward();
    _fadeController.forward();

    Future.delayed(Duration.zero, () {
      final mapProvider = Provider.of<MapProvider>(context, listen: false);
      if (!mapProvider.hasInitializedLocation) {
        mapProvider.initializeUserLocation();
      }
    });
  }

  @override
  void dispose() {
    _slideController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // Helper method to show map selection mode
  void _showMapSelectionMode({required bool isPickup, int stopIndex = -1}) {
    setState(() {
      _isMapSelectionMode = true;
      _showFullMap = true;
      _isPickupSelection = isPickup;
      _currentStopIndex = stopIndex;
    });
  }

  // Add a new stop
  void _addStop() {
    final mapProvider = Provider.of<MapProvider>(context, listen: false);

    if (mapProvider.mapController != null) {
      mapProvider.addStop();

      // Show map selection for the new stop after a short delay
      Future.delayed(const Duration(milliseconds: 300), () {
        _showMapSelectionMode(
          isPickup: false,
          stopIndex: mapProvider.stops.length - 1,
        );
      });
    } else {
      mapProvider.addStop();
    }
  }

  // Remove a stop
  void _removeStop(int index) {
    final mapProvider = Provider.of<MapProvider>(context, listen: false);
    mapProvider.removeStop(index);
  }

  // Update waiting time for a stop
  void _updateWaitingTime(int index, int minutes) {
    final mapProvider = Provider.of<MapProvider>(context, listen: false);
    mapProvider.updateStop(index, waitingTime: minutes);
  }

  // Clear all locations and stops
  void _clearAll() {
    final mapProvider = Provider.of<MapProvider>(context, listen: false);

    // IMPORTANT: Clear locations FIRST before stops
    // If we clear stops first, _updateRoute() is called while pickup/dropoff still exist,
    // which causes the route to be redrawn without stops
    mapProvider.clearPickupLocation();
    mapProvider.clearDropoffLocation();

    // Now clear stops (won't redraw route since locations are already null)
    mapProvider.clearStops();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFFFFC107)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isMapSelectionMode
              ? 'Select ${_isPickupSelection
                  ? 'Pickup'
                  : _currentStopIndex >= 0
                  ? 'Stop #${_currentStopIndex + 1}'
                  : 'Dropoff'} Location'
              : 'Book Your Ride',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          if (_isMapSelectionMode)
            TextButton(
              onPressed: () {
                setState(() {
                  _isMapSelectionMode = false;
                });
              },
              child: const Text(
                'CANCEL',
                style: TextStyle(
                  color: Color(0xFFFFC107),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Map Section
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            height:
                _showFullMap || _isMapSelectionMode
                    ? MediaQuery.of(context).size.height * 0.65
                    : 220,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Stack(
              children: [
                MapWidget(
                  allowMapTaps: _isMapSelectionMode,
                  isPickupSelection: _isPickupSelection,
                  stopIndex: _currentStopIndex,
                ),

                // Location Status Badge
                Consumer<MapProvider>(
                  builder: (context, mapProvider, _) {
                    if (!mapProvider.isInitializing &&
                        mapProvider.hasInitializedLocation) {
                      return const SizedBox.shrink();
                    }

                    return Positioned(
                      top: 16,
                      left: 16,
                      right: 100,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFFFC107),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (mapProvider.isInitializing)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFFFFC107),
                                  ),
                                ),
                              ),
                            if (mapProvider.isInitializing)
                              const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                mapProvider.isInitializing
                                    ? 'Getting your location...'
                                    : 'Location ready',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                // Map Controls
                Positioned(
                  top: 16,
                  right: 16,
                  child: Column(
                    children: [
                      _buildMapControlButton(
                        icon:
                            _showFullMap
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                        onPressed: () {
                          setState(() {
                            _showFullMap = !_showFullMap;
                          });
                        },
                      ),
                      if (!_isMapSelectionMode) const SizedBox(height: 8),
                      if (!_isMapSelectionMode)
                        _buildMapControlButton(
                          icon: Icons.my_location,
                          onPressed: () {
                            Provider.of<MapProvider>(
                              context,
                              listen: false,
                            ).setCurrentLocationAsPickup();
                          },
                        ),
                    ],
                  ),
                ),

                // Map Selection Confirmation
                if (_isMapSelectionMode)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Tap on the map to select',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Consumer<MapProvider>(
                            builder: (context, mapProvider, _) {
                              String address;

                              if (_isPickupSelection) {
                                address =
                                    mapProvider.pickupLocation?.address ?? '';
                              } else if (_currentStopIndex >= 0) {
                                // Selecting a stop
                                if (_currentStopIndex <
                                    mapProvider.stops.length) {
                                  address =
                                      mapProvider
                                          .stops[_currentStopIndex]['address'] ??
                                      '';
                                } else {
                                  address = '';
                                }
                              } else {
                                // Selecting dropoff
                                address =
                                    mapProvider.dropoffLocation?.address ?? '';
                              }

                              return Text(
                                address.isEmpty
                                    ? 'No location selected'
                                    : address,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _isMapSelectionMode = false;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFC107),
                                foregroundColor: Colors.black,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'CONFIRM LOCATION',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Content Section
          if (!_isMapSelectionMode)
            Expanded(
              child: SlideTransition(
                position: _slideAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Location Section
                          _buildLocationSection(),

                          const SizedBox(height: 24),

                          // Car Selection
                          _buildCarSelectionSection(),

                          const SizedBox(height: 24),

                          // Trip Summary
                          Consumer<MapProvider>(
                            builder: (context, mapProvider, _) {
                              if (mapProvider.pickupLocation != null &&
                                  mapProvider.dropoffLocation != null) {
                                return _buildTripSummary(mapProvider);
                              }
                              return const SizedBox.shrink();
                            },
                          ),

                          const SizedBox(height: 24),

                          // Book Button
                          _buildBookButton(),

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMapControlButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFC107), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: const Color(0xFFFFC107)),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildLocationSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFC107).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.location_on,
                      color: Color(0xFFFFC107),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Trip Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
              // Clear All Button
              TextButton.icon(
                onPressed: _clearAll,
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text(
                  'Clear All',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade600,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Pickup Location
          _buildLocationField(
            icon: Icons.radio_button_checked,
            iconColor: Colors.green,
            label: 'Pickup',
            isPickup: true,
          ),

          // Stops Section
          Consumer<MapProvider>(
            builder: (context, mapProvider, _) {
              return Column(
                children: List.generate(mapProvider.stops.length, (index) {
                  final stop = mapProvider.stops[index];

                  return Column(
                    children: [
                      const SizedBox(height: 16),
                      _buildStopField(index, stop),
                    ],
                  );
                }),
              );
            },
          ),

          const SizedBox(height: 16),

          // Add Stop Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addStop,
              icon: const Icon(Icons.add_location_alt, size: 20),
              label: const Text(
                'Add Stop',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFFC107),
                side: const BorderSide(color: Color(0xFFFFC107), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Dropoff Location
          _buildLocationField(
            icon: Icons.location_on,
            iconColor: Colors.red,
            label: 'Dropoff',
            isPickup: false,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationField({
    required IconData icon,
    required Color iconColor,
    required String label,
    required bool isPickup,
  }) {
    return Consumer<MapProvider>(
      builder: (context, mapProvider, child) {
        final address =
            isPickup
                ? mapProvider.pickupLocation?.address ?? ''
                : mapProvider.dropoffLocation?.address ?? '';

        return Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  _isMapSelectionMode = true;
                  _isPickupSelection = isPickup;
                  _currentStopIndex =
                      -1; // Reset stop index for pickup/dropoff selection
                });
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(icon, color: iconColor, size: 24),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            address.isEmpty
                                ? 'Tap to select $label location'
                                : address,
                            style: TextStyle(
                              fontSize: 15,
                              color:
                                  address.isEmpty
                                      ? Colors.grey.shade400
                                      : Colors.black,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFC107).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.edit_location_alt,
                        color: Color(0xFFFFC107),
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStopField(int index, Map<String, dynamic> stop) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFC107).withOpacity(0.3)),
      ),
      child: Column(
        children: [
          // Stop Location Field
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              onTap: () {
                _showMapSelectionMode(isPickup: false, stopIndex: index);
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Numbered Circle
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFC107),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Stop #${index + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            stop['address']?.isEmpty ?? true
                                ? 'Tap to select stop location'
                                : stop['address'],
                            style: TextStyle(
                              fontSize: 15,
                              color:
                                  stop['address']?.isEmpty ?? true
                                      ? Colors.grey.shade400
                                      : Colors.black,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Map Selection Button
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFC107).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.edit_location_alt,
                        color: Color(0xFFFFC107),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Remove Button
                    IconButton(
                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                      onPressed: () => _removeStop(index),
                      tooltip: 'Remove Stop',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Waiting Time Selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'Wait Time:',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: stop['waitingTime'] ?? 0,
                        isExpanded: true,
                        icon: const Icon(
                          Icons.arrow_drop_down,
                          color: Color(0xFFFFC107),
                        ),
                        items:
                            [0, 5, 10, 15, 20, 30].map((minutes) {
                              return DropdownMenuItem<int>(
                                value: minutes,
                                child: Text(
                                  minutes == 0 ? 'No Wait' : '$minutes Minutes',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              );
                            }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            _updateWaitingTime(index, value);
                          }
                        },
                      ),
                    ),
                  ),
                ),
                if ((stop['waitingTime'] ?? 0) > 0) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Text(
                      '+\$${((stop['waitingTime'] ?? 0) * _waitingChargePerMinute).toStringAsFixed(2)}',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarSelectionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC107).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.local_taxi,
                color: Color(0xFFFFC107),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Choose Your Ride',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _carTypes.length,
            itemBuilder: (context, index) {
              final car = _carTypes[index];
              final isSelected = car['id'] == _selectedCarType;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedCarType = car['id'];
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 12),
                  width: 140,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.black : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color:
                          isSelected
                              ? const Color(0xFFFFC107)
                              : Colors.grey.shade200,
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow:
                        isSelected
                            ? [
                              BoxShadow(
                                color: const Color(0xFFFFC107).withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ]
                            : [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          car['icon'],
                          size: 40,
                          color:
                              isSelected
                                  ? const Color(0xFFFFC107)
                                  : Colors.black,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          car['name'],
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          car['capacity'],
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                isSelected
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTripSummary(MapProvider mapProvider) {
    final baseFare = mapProvider.estimatedFare;
    final additionalCharges = mapProvider.calculateAdditionalCharges(
      _stopCharge,
      _waitingChargePerMinute,
    );
    final selectedCar = _carTypes.firstWhere(
      (car) => car['id'] == _selectedCarType,
      orElse: () => _carTypes[0],
    );
    final totalFare = (baseFare + additionalCharges) * selectedCar['price'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC107).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.receipt_long,
                  color: Color(0xFFFFC107),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Trip Summary',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Route Visualization
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pickup
                Row(
                  children: [
                    const Icon(
                      Icons.radio_button_checked,
                      color: Colors.green,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        mapProvider.pickupLocation?.address ?? 'Pickup',
                        style: const TextStyle(fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                // Stops
                if (mapProvider.stops.isNotEmpty)
                  ...List.generate(mapProvider.stops.length, (index) {
                    final stop = mapProvider.stops[index];
                    return Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 9),
                          child: Icon(
                            Icons.more_vert,
                            size: 14,
                            color: Colors.grey,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFFC107),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    stop['address'] ?? 'Stop #${index + 1}',
                                    style: const TextStyle(fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if ((stop['waitingTime'] ?? 0) > 0)
                                    Text(
                                      'Wait ${stop['waitingTime']} min (+\$${(stop['waitingTime'] * _waitingChargePerMinute).toStringAsFixed(2)})',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green.shade700,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  }),

                // Dropoff
                if (mapProvider.stops.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(left: 9),
                    child: Icon(Icons.more_vert, size: 14, color: Colors.grey),
                  ),
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        mapProvider.dropoffLocation?.address ?? 'Dropoff',
                        style: const TextStyle(fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          _buildSummaryRow(
            'Distance',
            '${mapProvider.estimatedDistance.toStringAsFixed(1)} km',
          ),
          const SizedBox(height: 8),
          _buildSummaryRow('Duration', '~${mapProvider.estimatedDuration} min'),
          const SizedBox(height: 8),
          _buildSummaryRow('Base Fare', '\$${baseFare.toStringAsFixed(2)}'),

          // Stops Charges
          if (mapProvider.stops.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildSummaryRow(
              'Stops (${mapProvider.stops.length})',
              '+\$${(mapProvider.stops.length * _stopCharge).toStringAsFixed(2)}',
            ),
          ],

          // Waiting Time Charges
          if (mapProvider.stops.any(
            (stop) => (stop['waitingTime'] ?? 0) > 0,
          )) ...[
            const SizedBox(height: 8),
            _buildSummaryRow(
              'Waiting Time',
              '+\$${(mapProvider.stops.fold<int>(0, (sum, stop) => sum + (stop['waitingTime'] as int? ?? 0)) * _waitingChargePerMinute).toStringAsFixed(2)}',
            ),
          ],

          if (additionalCharges > 0 && mapProvider.stops.isEmpty) ...[
            const SizedBox(height: 8),
            _buildSummaryRow(
              'Additional Charges',
              '\$${additionalCharges.toStringAsFixed(2)}',
            ),
          ],
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Estimated Fare',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC107),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '\$${totalFare.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
      ],
    );
  }

  Widget _buildBookButton() {
    return Consumer<MapProvider>(
      builder: (context, mapProvider, _) {
        final canBook =
            mapProvider.pickupLocation != null &&
            mapProvider.dropoffLocation != null;

        return SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: canBook ? () => _requestRide(context) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFC107),
              foregroundColor: Colors.black,
              disabledBackgroundColor: Colors.grey.shade300,
              elevation: canBook ? 4 : 0,
              shadowColor: const Color(0xFFFFC107).withOpacity(0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.local_taxi,
                  size: 24,
                  color: canBook ? Colors.black : Colors.grey.shade500,
                ),
                const SizedBox(width: 12),
                Text(
                  'BOOK NOW',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: canBook ? Colors.black : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _requestRide(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFC107),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.local_taxi,
                      size: 40,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Booking Your Ride',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFFFFC107),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Please wait...',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
    );

    try {
      final selectedCar = _carTypes.firstWhere(
        (car) => car['id'] == _selectedCarType,
        orElse: () => _carTypes[0],
      );

      final mapProvider = Provider.of<MapProvider>(context, listen: false);
      final firestoreProvider = Provider.of<FirestoreProvider>(
        context,
        listen: false,
      );

      final baseFare = mapProvider.estimatedFare;
      final additionalCharges = mapProvider.calculateAdditionalCharges(
        _stopCharge,
        _waitingChargePerMinute,
      );
      final adjustedFare =
          (baseFare + additionalCharges) * selectedCar['price'];

      final tripData = {
        'carType': _selectedCarType,
        'fare': adjustedFare,
        'distance': mapProvider.estimatedDistance,
        'duration': mapProvider.estimatedDuration,
        'paymentMethod': 'cash',
        'pickup': {
          'address': mapProvider.pickupLocation?.address,
          'placeId': mapProvider.pickupLocation?.placeId,
          'name': mapProvider.pickupLocation?.name,
          'latitude': mapProvider.pickupLocation?.coordinates.latitude,
          'longitude': mapProvider.pickupLocation?.coordinates.longitude,
        },
        'dropoff': {
          'address': mapProvider.dropoffLocation?.address,
          'placeId': mapProvider.dropoffLocation?.placeId,
          'name': mapProvider.dropoffLocation?.name,
          'latitude': mapProvider.dropoffLocation?.coordinates.latitude,
          'longitude': mapProvider.dropoffLocation?.coordinates.longitude,
        },
        'stops':
            mapProvider.stops
                .map(
                  (stop) => {
                    'address': stop['address'],
                    'placeId': stop['location']?.placeId,
                    'name': stop['location']?.name,
                    'latitude': stop['location']?.coordinates.latitude,
                    'longitude': stop['location']?.coordinates.longitude,
                    'waitingTime': stop['waitingTime'] ?? 0,
                  },
                )
                .toList(),
        'searchStartedAt': DateTime.now().millisecondsSinceEpoch,
      };

      final tripRef = await firestoreProvider.createTrip(tripData);

      Navigator.of(context).pop();

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => TripTrackingScreen(tripId: tripRef.id),
        ),
      );
    } catch (e) {
      Navigator.of(context).pop();

      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red),
                  SizedBox(width: 12),
                  Text('Booking Failed'),
                ],
              ),
              content: Text('Failed to create trip request: $e'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    }
  }
}
