import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../providers/firestore_provider.dart';
import 'trip_tracking_screen.dart';

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({Key? key}) : super(key: key);

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DateFormat _dateFormat = DateFormat('MMM d, yyyy • h:mm a');
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Trips'),
        backgroundColor: Colors.amber,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.black87,
          unselectedLabelColor: Colors.black54,
          indicatorColor: Colors.black87,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Completed'),
            Tab(text: 'Cancelled'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTripList('active'),
          _buildTripList('completed'),
          _buildTripList('cancelled'),
        ],
      ),
    );
  }
  
  Widget _buildTripList(String filterType) {
    return Consumer<FirestoreProvider>(
      builder: (context, firestoreProvider, _) {
        return StreamBuilder<QuerySnapshot>(
          stream: _getTripStream(firestoreProvider, filterType),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getEmptyIcon(filterType),
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _getEmptyMessage(filterType),
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }
            
            return ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final tripDoc = snapshot.data!.docs[index];
                final tripData = tripDoc.data() as Map<String, dynamic>;
                
                // Convert Firestore timestamp to DateTime
                final Timestamp? createdTimestamp = tripData['createdAt'];
                final DateTime? createdDate = createdTimestamp?.toDate();
                
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: InkWell(
                    onTap: () {
                      // Navigate to trip details
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => TripTrackingScreen(
                            tripId: tripDoc.id,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Trip date and status
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                createdDate != null 
                                    ? _dateFormat.format(createdDate) 
                                    : 'Unknown date',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                              _buildStatusChip(tripData['status']),
                            ],
                          ),
                          const Divider(),
                          
                          // Pickup and dropoff locations
                          Row(
                            children: [
                              const SizedBox(
                                width: 30,
                                child: Center(
                                  child: Icon(
                                    Icons.radio_button_on,
                                    color: Colors.green,
                                    size: 16,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  tripData['pickup']['address'] ?? 'Unknown pickup location',
                                  style: const TextStyle(
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          
                          // Show stops if any
                          if (tripData['stops'] != null && 
                              (tripData['stops'] as List).isNotEmpty)
                            ..._buildStopsWidgets(tripData['stops']),
                          
                          Row(
                            children: [
                              const SizedBox(
                                width: 30,
                                child: Center(
                                  child: Icon(
                                    Icons.location_on,
                                    color: Colors.red,
                                    size: 16,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  tripData['dropoff']['address'] ?? 'Unknown destination',
                                  style: const TextStyle(
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 12),
                          
                          // Trip details (fare, car type, etc.)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _getCarTypeIcon(tripData['carType']),
                                    size: 16,
                                    color: Colors.grey.shade700,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatCarType(tripData['carType']),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '\$${(tripData['fare'] ?? 0.0).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
  
  List<Widget> _buildStopsWidgets(List stops) {
    return List.generate(
      stops.length,
      (index) => Row(
        children: [
          const SizedBox(
            width: 30,
            child: Center(
              child: Icon(
                Icons.circle,
                color: Colors.orange,
                size: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              stops[index]['address'] ?? 'Stop ${index + 1}',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatusChip(String status) {
    Color chipColor;
    String statusText;
    
    switch (status) {
      case 'searching':
        chipColor = Colors.blue;
        statusText = 'Searching';
        break;
      case 'accepted':
        chipColor = Colors.orange;
        statusText = 'Accepted';
        break;
      case 'arriving':
      case 'arrived':
        chipColor = Colors.amber;
        statusText = status == 'arriving' ? 'Driver on way' : 'Driver arrived';
        break;
      case 'inprogress':
        chipColor = Colors.purple;
        statusText = 'In Progress';
        break;
      case 'completed':
        chipColor = Colors.green;
        statusText = 'Completed';
        break;
      case 'cancelled':
        chipColor = Colors.red;
        statusText = 'Cancelled';
        break;
      default:
        chipColor = Colors.grey;
        statusText = status.capitalize();
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.1),
        border: Border.all(color: chipColor, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        statusText,
        style: TextStyle(
          color: chipColor,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
  
  Stream<QuerySnapshot> _getTripStream(FirestoreProvider firestoreProvider, String filterType) {
    // Get base query for user's trips
    Query query = FirebaseFirestore.instance.collection('trips')
      .where('userId', isEqualTo: firestoreProvider.currentUserId)
      .orderBy('createdAt', descending: true);
    
    // Apply filters based on tab
    switch (filterType) {
      case 'active':
        return query.where('status', whereIn: ['searching', 'accepted', 'arriving', 'arrived', 'inprogress']).snapshots();
      case 'completed':
        return query.where('status', isEqualTo: 'completed').snapshots();
      case 'cancelled':
        return query.where('status', isEqualTo: 'cancelled').snapshots();
      default:
        return query.snapshots();
    }
  }
  
  IconData _getEmptyIcon(String filterType) {
    switch (filterType) {
      case 'active':
        return Icons.local_taxi_outlined;
      case 'completed':
        return Icons.done_all;
      case 'cancelled':
        return Icons.cancel_outlined;
      default:
        return Icons.history;
    }
  }
  
  String _getEmptyMessage(String filterType) {
    switch (filterType) {
      case 'active':
        return 'No active trips.\nBook a ride to get started!';
      case 'completed':
        return 'No completed trips yet.\nYour trip history will appear here.';
      case 'cancelled':
        return 'No cancelled trips.\nThat\'s a good thing!';
      default:
        return 'No trips found.';
    }
  }
  
  IconData _getCarTypeIcon(String? carType) {
    switch (carType) {
      case 'economy':
        return Icons.directions_car;
      case 'standard':
        return Icons.directions_car;
      case 'premium':
        return Icons.airline_seat_recline_extra;
      case 'xl':
        return Icons.airport_shuttle;
      default:
        return Icons.local_taxi;
    }
  }
  
  String _formatCarType(String? carType) {
    if (carType == null) return 'Standard';
    
    return carType.split('_').map((word) => word.capitalize()).join(' ');
  }
}

// Extension method for string capitalization
extension StringExtension on String {
  String capitalize() {
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}