import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/firestore_provider.dart';
import '../widgets/map_widget.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TripTrackingScreen extends StatefulWidget {
  final String tripId;
  
  const TripTrackingScreen({Key? key, required this.tripId}) : super(key: key);

  @override
  State<TripTrackingScreen> createState() => _TripTrackingScreenState();
}

class _TripTrackingScreenState extends State<TripTrackingScreen> {
  Map<String, dynamic>? _tripData;

  @override
  Widget build(BuildContext context) {
    return Consumer<FirestoreProvider>(
      builder: (context, firestoreProvider, _) {
        return StreamBuilder<DocumentSnapshot>(
          stream: firestoreProvider.getTrip(widget.tripId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            
            if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
              return Scaffold(
                appBar: AppBar(
                  title: const Text('Trip Details'),
                  backgroundColor: Colors.amber,
                ),
                body: Center(
                  child: Text(snapshot.hasError 
                    ? 'Error: ${snapshot.error}' 
                    : 'Trip not found'),
                ),
              );
            }
            
            // Get trip data
            _tripData = snapshot.data!.data() as Map<String, dynamic>;
            final status = _tripData!['status'] as String;
            
            // Only show cancel button if trip is in a cancellable state
            final bool canCancel = ['searching', 'accepted', 'arriving', 'arrived'].contains(status);
            
            return Scaffold(
              appBar: AppBar(
                title: Text(_getTripStatusTitle(status)),
                backgroundColor: Colors.amber,
              ),
              body: Column(
                children: [
                  // Map view showing the trip
                  Expanded(
                    flex: 3,
                    child: MapWidget(
                      allowMapTaps: false,
                    ),
                  ),
                  
                  // Trip status information
                  Expanded(
                    flex: 2,
                    child: _buildTripStatusWidget(),
                  ),
                ],
              ),
              // Only show FAB if trip is in a cancellable state
              floatingActionButton: canCancel ? FloatingActionButton(
                onPressed: () {
                  _showCancelTripDialog();
                },
                backgroundColor: Colors.red,
                child: const Icon(Icons.close),
              ) : null, // Set to null to hide the FAB
            );
          },
        );
      },
    );
  }
  
  String _getTripStatusTitle(String status) {
    switch (status) {
      case 'searching':
        return 'Finding Driver';
      case 'accepted':
        return 'Driver Accepted';
      case 'arriving':
        return 'Driver Arriving';
      case 'arrived':
        return 'Driver Arrived';
      case 'inprogress':
        return 'Trip in Progress';
      case 'completed':
        return 'Trip Completed';
      case 'cancelled':
        return 'Trip Cancelled';
      default:
        return 'Trip Details';
    }
  }
  
  Widget _buildTripStatusWidget() {
    return Consumer<FirestoreProvider>(
      builder: (context, firestoreProvider, _) {
        return StreamBuilder<DocumentSnapshot>(
          stream: firestoreProvider.getTrip(widget.tripId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Center(child: Text('Trip not found'));
            }
            
            // Get trip data
            final tripData = snapshot.data!.data() as Map<String, dynamic>;
            final status = tripData['status'] as String;
            
            return Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trip Status: ${_formatStatus(status)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Status progress indicator
                    _buildStatusProgress(status),
                    
                    const SizedBox(height: 16),
                    
                    // Trip details
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left column - Pickup
                        Expanded(
                          flex: 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Pickup'),
                              Text(
                                tripData['pickup']?['address'] ?? 'Unknown',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(width: 16), // Add some space between columns
                        
                        // Right column - Dropoff
                        Expanded(
                          flex: 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('Dropoff'),
                              Text(
                                tripData['dropoff']?['address'] ?? 'Unknown',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    const Divider(height: 24),
                    
                    // Payment info
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Estimated Fare'),
                        Text(
                          '\$${(tripData['fare'] ?? 0.0).toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
  
  Widget _buildStatusProgress(String status) {
    final statusIndex = _getStatusIndex(status);
    
    return Column(
      children: [
        Row(
          children: List.generate(5, (index) {
            bool isActive = index <= statusIndex;
            
            return Expanded(
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive ? Colors.amber : Colors.grey.shade300,
                    ),
                    child: Center(
                      child: Icon(
                        _getStatusIcon(index),
                        color: isActive ? Colors.black : Colors.grey.shade600,
                        size: 16,
                      ),
                    ),
                  ),
                  if (index < 4)
                    Expanded(
                      child: Container(
                        height: 3,
                        color: index < statusIndex ? Colors.amber : Colors.grey.shade300,
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Center(
                child: Text(
                  'Searching',
                  style: TextStyle(fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  'Accepted',
                  style: TextStyle(fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  'Arriving',
                  style: TextStyle(fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  'In Trip',
                  style: TextStyle(fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  'Completed',
                  style: TextStyle(fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  IconData _getStatusIcon(int index) {
    switch (index) {
      case 0:
        return Icons.search;
      case 1:
        return Icons.check_circle;
      case 2:
        return Icons.directions_car;
      case 3:
        return Icons.navigation;
      case 4:
        return Icons.flag;
      default:
        return Icons.circle;
    }
  }
  
  int _getStatusIndex(String status) {
    switch (status) {
      case 'searching':
        return 0;
      case 'accepted':
        return 1;
      case 'arriving':
        return 2;
      case 'inprogress':
        return 3;
      case 'completed':
        return 4;
      default:
        return 0;
    }
  }
  
  String _formatStatus(String status) {
    switch (status) {
      case 'searching':
        return 'Searching for Driver';
      case 'accepted':
        return 'Driver Accepted';
      case 'arriving':
        return 'Driver is Arriving';
      case 'inprogress':
        return 'Trip in Progress';
      case 'completed':
        return 'Trip Completed';
      default:
        return status;
    }
  }
  
  void _showCancelTripDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Trip?'),
        content: const Text('Are you sure you want to cancel your trip request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('NO'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _cancelTrip();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('YES, CANCEL'),
          ),
        ],
      ),
    );
  }
  
  void _cancelTrip() async {
    try {
      final firestoreProvider = Provider.of<FirestoreProvider>(context, listen: false);
      await firestoreProvider.updateTripStatus(widget.tripId, 'cancelled');
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Trip cancelled successfully'),
          backgroundColor: Colors.green,
        ),
      );
      
      Navigator.of(context).pop(); // Go back to previous screen
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cancelling trip: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}