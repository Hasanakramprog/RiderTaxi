import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/map_provider.dart';
import '../widgets/map_widget.dart';
import '../widgets/location_input.dart';
import '../models/location_model.dart';

class TripRequestScreen extends StatefulWidget {
  const TripRequestScreen({Key? key}) : super(key: key);

  @override
  State<TripRequestScreen> createState() => _TripRequestScreenState();
}

class _TripRequestScreenState extends State<TripRequestScreen> {
  bool _showFullMap = false;
  bool _isMapSelectionMode = false;
  bool _isPickupSelection = true;
  int _currentStopIndex = -1; // -1 for pickup, 0+ for stops
  String _selectedCarType = 'standard';
  
  // Constants for pricing
  final double _stopCharge = 2.0; 
  final double _waitingChargePerMinute = 0.5;
  
  // Car type options
  final List<Map<String, dynamic>> _carTypes = [
    {
      'id': 'standard',
      'name': 'Standard',
      'image': 'assets/car_standard.webp',
      'description': 'Economy, 4 seats',
      'price': 1.0,
    },
    {
      'id': 'xl',
      'name': 'XL',
      'image': 'assets/car_xl.webp',
      'description': 'Spacious, 5-6 seats',
      'price': 1.5,
    },
    {
      'id': 'vip',
      'name': 'VIP',
      'image': 'assets/car_vip.webp',
      'description': 'Premium, 4 seats',
      'price': 2.0,
    },
  ];
  
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () {
      final mapProvider = Provider.of<MapProvider>(context, listen: false);
      if (!mapProvider.hasInitializedLocation) {
        mapProvider.initializeUserLocation();
      }
    });
  }

  void _showMapSelectionMode({required bool isPickup, int stopIndex = -1}) {
    setState(() {
      _isMapSelectionMode = true;
      _showFullMap = true;
      _isPickupSelection = isPickup;
      _currentStopIndex = stopIndex;
    });
  }
  
  // Add a new stop using MapProvider
  void _addStop() {
    final mapProvider = Provider.of<MapProvider>(context, listen: false);
    
    // Use the current map center as the default location
    if (mapProvider.mapController != null) {
      setState(() {
        // Show loading indicator if needed
        // You could add a local loading state if desired
      });
      
      // Call the updated addStop method
      mapProvider.addStop();
      
      // Immediately show map selection for the new stop
      Future.delayed(const Duration(milliseconds: 300), () {
        _showMapSelectionMode(
          isPickup: false,
          stopIndex: mapProvider.stops.length - 1,
        );
      });
    } else {
      // Fallback if map controller isn't available
      mapProvider.addStop();
    }
  }
  
  // Remove a stop using MapProvider
  void _removeStop(int index) {
    final mapProvider = Provider.of<MapProvider>(context, listen: false);
    mapProvider.removeStop(index);
  }
  
  // Update waiting time using MapProvider
  void _updateWaitingTime(int index, int minutes) {
    final mapProvider = Provider.of<MapProvider>(context, listen: false);
    mapProvider.updateStop(index, waitingTime: minutes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isMapSelectionMode 
            ? 'Tap on Map to Set ${_isPickupSelection ? 'Pickup' : _currentStopIndex >= 0 ? 'Stop #${_currentStopIndex + 1}' : 'Dropoff'}' 
            : 'Request a Ride'),
        backgroundColor: Colors.amber,
        actions: [
          if (_isMapSelectionMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isMapSelectionMode = false;
                });
              },
            ),
        ],
      ),
      body: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: _showFullMap || _isMapSelectionMode
                ? MediaQuery.of(context).size.height * 0.6
                : 200,
            child: Stack(
              children: [
                MapWidget(
                  allowMapTaps: _isMapSelectionMode,
                  isPickupSelection: _isPickupSelection,
                  stopIndex: _currentStopIndex,
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Column(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'fullscreen',
                        onPressed: () {
                          setState(() {
                            _showFullMap = !_showFullMap;
                          });
                        },
                        backgroundColor: const Color.fromARGB(255, 255, 193, 0),
                        child: Icon(
                          _showFullMap ? Icons.fullscreen_exit : Icons.fullscreen,
                          color: Colors.black87,
                        ),
                      ),
                      if (!_isMapSelectionMode) const SizedBox(height: 8),
                      if (!_isMapSelectionMode)
                        FloatingActionButton.small(
                          heroTag: 'currentLocation',
                          onPressed: () {
                            Provider.of<MapProvider>(context, listen: false)
                                .resetPickupToCurrentLocation();
                          },
                          backgroundColor: const Color.fromARGB(255, 255, 193, 0),
                          child: const Icon(
                            Icons.my_location,
                            color: Colors.blue,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_isMapSelectionMode)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Text(
                              'Tap anywhere on the map to set your ${_isPickupSelection ? 'pickup' : _currentStopIndex >= 0 ? 'stop #${_currentStopIndex + 1}' : 'dropoff'} location',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Consumer<MapProvider>(
                              builder: (context, mapProvider, _) {
                                return Text(
                                  _isPickupSelection 
                                    ? mapProvider.pickupLocation?.address ?? ''
                                    : mapProvider.dropoffLocation?.address ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildMapSelectionConfirmButton(),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!_isMapSelectionMode)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Consumer<MapProvider>(
                            builder: (context, mapProvider, child) {
                              String pickupAddress = mapProvider.pickupLocation?.address ?? '';

                              return LocationInput(
                                isPickup: true,
                                hintText: 'Pickup Location',
                                initialValue: pickupAddress,
                                onClear: () {
                                  mapProvider.clearPickupLocation();
                                },
                              );
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.pin_drop, color: Colors.green),
                          onPressed: () => _showMapSelectionMode(isPickup: true),
                          tooltip: 'Pick on map',
                        ),
                      ],
                    ),
                    
                    Consumer<MapProvider>(
                      builder: (context, mapProvider, _) {
                        return Column(
                          children: List.generate(mapProvider.stops.length, (index) {
                            final stop = mapProvider.stops[index];
                            
                            return Column(
                              children: [
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: Colors.orange,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${index + 1}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: LocationInput(
                                        isPickup: false,
                                        hintText: 'Stop #${index + 1} Location',
                                        initialValue: stop['address'] ?? '',
                                        onClear: () {
                                          mapProvider.updateStop(index, address: '', location: null);
                                        },
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.pin_drop, color: Colors.orange),
                                      onPressed: () => _showMapSelectionMode(
                                        isPickup: false,
                                        stopIndex: index,
                                      ),
                                      tooltip: 'Pick on map',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                                      onPressed: () => _removeStop(index),
                                      tooltip: 'Remove stop',
                                    ),
                                  ],
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(left: 32.0),
                                  child: Row(
                                    children: [
                                      const Text('Wait time: '),
                                      DropdownButton<int>(
                                        value: stop['waitingTime'] ?? 0,
                                        items: [0, 5, 10, 15, 20, 30].map((minutes) {
                                          return DropdownMenuItem<int>(
                                            value: minutes,
                                            child: Text(minutes == 0 
                                              ? 'No wait' 
                                              : '$minutes min'),
                                          );
                                        }).toList(),
                                        onChanged: (value) {
                                          if (value != null) {
                                            _updateWaitingTime(index, value);
                                          }
                                        },
                                      ),
                                      if ((stop['waitingTime'] ?? 0) > 0)
                                        Padding(
                                          padding: const EdgeInsets.only(left: 8.0),
                                          child: Text(
                                            '+\$${((stop['waitingTime'] ?? 0) * _waitingChargePerMinute).toStringAsFixed(2)}',
                                            style: TextStyle(
                                              color: Colors.green.shade700,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const Divider(),
                              ],
                            );
                          }),
                        );
                      },
                    ),
                    
                    Row(
                      children: [
                        Expanded(
                          child: Consumer<MapProvider>(
                            builder: (context, mapProvider, child) {
                              String dropoffAddress = mapProvider.dropoffLocation?.address ?? '';
                              
                              return LocationInput(
                                isPickup: false,
                                hintText: 'Final Destination',
                                initialValue: dropoffAddress,
                                onClear: () {
                                  mapProvider.clearDropoffLocation();
                                },
                              );
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.pin_drop, color: Colors.red),
                          onPressed: () => _showMapSelectionMode(isPickup: false),
                          tooltip: 'Pick on map',
                        ),
                      ],
                    ),
                    
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      child: OutlinedButton.icon(
                        onPressed: _addStop,
                        icon: const Icon(Icons.add_location_alt),
                        label: const Text('Add Stop'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          side: const BorderSide(color: Colors.orange),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),

                    const Text(
                      'Choose your ride',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    SizedBox(
                      height: 150,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _carTypes.length,
                        itemBuilder: (context, index) {
                          final carType = _carTypes[index];
                          final isSelected = carType['id'] == _selectedCarType;
                          
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedCarType = carType['id'];
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(right: 12),
                              width: 130,
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.amber.shade100 : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? Colors.amber : Colors.grey.shade300,
                                  width: isSelected ? 2 : 1,
                                ),
                                boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: Colors.amber.withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      )
                                    ]
                                  : [
                                      BoxShadow(
                                        color: Colors.grey.withOpacity(0.2),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      )
                                    ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    height: 70,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    child: _buildCarImage(carType['id']),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    carType['name'],
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  Text(
                                    carType['description'],
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    Consumer<MapProvider>(
                      builder: (context, mapProvider, _) {
                        if (mapProvider.pickupLocation != null &&
                            mapProvider.dropoffLocation != null) {
                          final baseFare = mapProvider.estimatedFare;
                          final additionalCharges = mapProvider.calculateAdditionalCharges(_stopCharge, _waitingChargePerMinute);
                          final adjustedFare = (baseFare + additionalCharges) * _carTypes.firstWhere((car) => car['id'] == _selectedCarType)['price'];
                          
                          return Column(
                            children: [
                              Card(
                                margin: const EdgeInsets.only(bottom: 16),
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Trip Summary',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Column(
                                            children: [
                                              Icon(Icons.circle_outlined, color: Colors.green, size: 18),
                                              SizedBox(height: 4),
                                              Icon(Icons.more_vert, size: 14, color: Colors.grey),
                                            ],
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              mapProvider.pickupLocation?.address ?? 'Pickup location',
                                              style: const TextStyle(fontSize: 13),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      
                                      if (mapProvider.stops.isNotEmpty)
                                        ...List.generate(mapProvider.stops.length, (index) {
                                          final stop = mapProvider.stops[index];
                                          return Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Column(
                                                children: [
                                                  SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child: Center(
                                                      child: Text(
                                                        '${index + 1}',
                                                        style: const TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.orange,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  const Icon(Icons.more_vert, size: 14, color: Colors.grey),
                                                ],
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
                                                    if (stop['waitingTime'] > 0)
                                                      Text(
                                                        'Wait ${stop['waitingTime']} min (+\$${(stop['waitingTime'] * _waitingChargePerMinute).toStringAsFixed(2)})',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.green.shade700,
                                                          fontStyle: FontStyle.italic,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          );
                                        }),
                                      
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.location_on, color: Colors.red, size: 18),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              mapProvider.dropoffLocation?.address ?? 'Destination',
                                              style: const TextStyle(fontSize: 13),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      
                                      const Divider(height: 24),
                                      
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('Car Type:'),
                                          Text(
                                            _carTypes.firstWhere(
                                              (car) => car['id'] == _selectedCarType
                                            )['name'],
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('Base Fare:'),
                                          Text('\$${baseFare.toStringAsFixed(2)}'),
                                        ],
                                      ),
                                      
                                      if (mapProvider.stops.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 8.0),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text('Stops (${mapProvider.stops.length}):'),
                                              Text('+\$${(mapProvider.stops.length * _stopCharge).toStringAsFixed(2)}'),
                                            ],
                                          ),
                                        ),
                                      
                                      if (mapProvider.stops.any((stop) => stop['waitingTime'] > 0))
                                        Padding(
                                          padding: const EdgeInsets.only(top: 8.0),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text('Waiting Time:'),
                                              Text('+\$${(mapProvider.stops.fold<int>(0, (sum, stop) => sum + (stop['waitingTime'] as int)) * _waitingChargePerMinute).toStringAsFixed(2)}'),
                                            ],
                                          ),
                                        ),
                                      
                                      if (_selectedCarType != 'standard')
                                        Padding(
                                          padding: const EdgeInsets.only(top: 8.0),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text('${_carTypes.firstWhere((car) => car['id'] == _selectedCarType)['name']} Rate:'),
                                              Text('×${_carTypes.firstWhere((car) => car['id'] == _selectedCarType)['price']}'),
                                            ],
                                          ),
                                        ),
                                      
                                      const Divider(height: 24),
                                      
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'Total Fare:',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            '\$${adjustedFare.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      
                                      const SizedBox(height: 8),
                                      const Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Payment Method:'),
                                          Text('Cash'),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: () {
                                    _requestRide(context);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.amber,
                                    foregroundColor: Colors.black,
                                  ),
                                  child: const Text(
                                    'REQUEST RIDE',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        } else {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text(
                                'Please select pickup and dropoff locations',
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCarImage(String carType) {
    try {
      return Image.asset(
        'assets/car_${carType}.webp',
        fit: BoxFit.contain,
      );
    } catch (e) {
      switch (carType) {
        case 'standard':
          return Icon(
            Icons.directions_car, 
            size: 50,
            color: Colors.amber.shade700,
          );
        case 'xl':
          return Icon(
            Icons.airport_shuttle,
            size: 50,
            color: Colors.amber.shade700,
          );
        case 'vip':
          return Icon(
            Icons.electric_car,
            size: 50,
            color: Colors.amber.shade700,
          );
        default:
          return Icon(
            Icons.directions_car,
            size: 50,
            color: Colors.amber.shade700,
          );
      }
    }
  }

  void _requestRide(BuildContext context) {
    final selectedCar = _carTypes.firstWhere(
      (car) => car['id'] == _selectedCarType,
      orElse: () => _carTypes[0],
    );

    final mapProvider = Provider.of<MapProvider>(context, listen: false);
    final baseFare = mapProvider.estimatedFare;
    final additionalCharges = mapProvider.calculateAdditionalCharges(_stopCharge, _waitingChargePerMinute);
    final adjustedFare = (baseFare + additionalCharges) * _carTypes.firstWhere((car) => car['id'] == _selectedCarType)['price'];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ride Requested'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Car type: ${selectedCar['name']}'),
            Text('Total stops: ${mapProvider.stops.length}'),
            if (mapProvider.stops.any((stop) => stop['waitingTime'] > 0))
              Text('Total waiting time: ${mapProvider.stops.fold<int>(0, (sum, stop) => sum + (stop['waitingTime'] as int))} min'),
            Text('Estimated fare: \$${adjustedFare.toStringAsFixed(2)}'),
            const SizedBox(height: 8),
            const Text('Looking for drivers nearby...'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildMapSelectionConfirmButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          final mapProvider = Provider.of<MapProvider>(context, listen: false);
          
          if (!_isPickupSelection && _currentStopIndex >= 0) {
          }
          
          setState(() {
            _isMapSelectionMode = false;
          });
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: _isPickupSelection 
            ? Colors.green 
            : _currentStopIndex >= 0 
              ? Colors.orange 
              : Colors.red,
        ),
        child: const Text('CONFIRM LOCATION'),
      ),
    );
  }
}