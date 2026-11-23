import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/car_type.dart';
import '../providers/firestore_provider.dart';
import 'trip_tracking_screen.dart';
import '../theme/app_colors.dart';

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({Key? key}) : super(key: key);

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen>
    with SingleTickerProviderStateMixin {
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Trip History',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
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
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.local_taxi,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading trips...',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: AppColors.danger,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading trips',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _buildEmptyState(filterType);
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              physics: const BouncingScrollPhysics(),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final tripDoc = snapshot.data!.docs[index];
                final tripData = tripDoc.data() as Map<String, dynamic>;

                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: Duration(milliseconds: 300 + (index * 100)),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 20 * (1 - value)),
                        child: child,
                      ),
                    );
                  },
                  child: _buildTripCard(tripDoc.id, tripData),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(String filterType) {
    IconData icon;
    String message;
    String description;

    switch (filterType) {
      case 'active':
        icon = Icons.local_taxi;
        message = 'No Active Trips';
        description = 'Book a ride to get started!';
        break;
      case 'completed':
        icon = Icons.done_all;
        message = 'No Completed Trips';
        description = 'Your trip history will appear here';
        break;
      case 'cancelled':
        icon = Icons.cancel_outlined;
        message = 'No Cancelled Trips';
        description = 'That\'s a good thing!';
        break;
      default:
        icon = Icons.history;
        message = 'No Trips Found';
        description = '';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 64, color: AppColors.textMuted),
          ),
          const SizedBox(height: 24),
          Text(
            message,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTripCard(String tripId, Map<String, dynamic> tripData) {
    final Timestamp? createdTimestamp = tripData['createdAt'];
    final DateTime? createdDate = createdTimestamp?.toDate();
    final status = tripData['status'] ?? 'unknown';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TripTrackingScreen(tripId: tripId),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.local_taxi,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatCarType(tripData['carType']),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              createdDate != null
                                  ? _dateFormat.format(createdDate)
                                  : 'Unknown date',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    _buildStatusBadge(status),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),

                // Locations
                _buildLocationRow(
                  Icons.radio_button_checked,
                  Colors.green,
                  tripData['pickup']['address'] ?? 'Unknown pickup',
                ),
                const SizedBox(height: 12),
                _buildLocationRow(
                  Icons.location_on,
                  Colors.red,
                  tripData['dropoff']['address'] ?? 'Unknown destination',
                ),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),

                // Footer
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildInfoChip(
                      Icons.straighten,
                      '${(tripData['distance'] ?? 0.0).toStringAsFixed(1)} km',
                    ),
                    _buildInfoChip(
                      Icons.access_time,
                      '${tripData['duration'] ?? 0} min',
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '\$${(tripData['fare'] ?? 0.0).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, Color color, String address) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            address,
            style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textPrimary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;
    String statusText;

    switch (status) {
      case 'searching':
        bgColor = AppColors.primarySoft;
        textColor = AppColors.primary;
        statusText = 'Searching';
        break;
      case 'accepted':
      case 'driver_accepted':
        bgColor = AppColors.warning.withOpacity(0.12);
        textColor = AppColors.warning;
        statusText = 'Accepted';
        break;
      case 'arriving':
      case 'arrived':
      case 'driver_arrived':
        bgColor = AppColors.warning.withOpacity(0.12);
        textColor = AppColors.warning;
        statusText = 'Arriving';
        break;
      case 'inprogress':
      case 'in_progress':
        bgColor = AppColors.primarySoft;
        textColor = AppColors.primary;
        statusText = 'In Progress';
        break;
      case 'completed':
        bgColor = AppColors.success.withOpacity(0.12);
        textColor = AppColors.success;
        statusText = 'Completed';
        break;
      case 'cancelled':
        bgColor = AppColors.danger.withOpacity(0.12);
        textColor = AppColors.danger;
        statusText = 'Cancelled';
        break;
      default:
        bgColor = AppColors.surfaceAlt;
        textColor = AppColors.textPrimary;
        statusText = status.capitalize();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        statusText,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Stream<QuerySnapshot> _getTripStream(
    FirestoreProvider firestoreProvider,
    String filterType,
  ) {
    Query query = FirebaseFirestore.instance
        .collection('trips')
        .where('userId', isEqualTo: firestoreProvider.currentUserId)
        .orderBy('createdAt', descending: true);

    switch (filterType) {
      case 'active':
        return query
            .where(
              'status',
              whereIn: [
                'searching',
                'accepted',
                'driver_accepted',
                'arriving',
                'arrived',
                'driver_arrived',
                'inprogress',
                'in_progress',
              ],
            )
            .snapshots();
      case 'completed':
        return query.where('status', isEqualTo: 'completed').snapshots();
      case 'cancelled':
        return query.where('status', isEqualTo: 'cancelled').snapshots();
      default:
        return query.snapshots();
    }
  }

  String _formatCarType(String? carType) {
    if (carType == null) return CarType.byId(CarType.defaultId).name;
    if (CarType.ids.contains(carType)) {
      return CarType.byId(carType).name;
    }
    return carType.split('_').map((word) => word.capitalize()).join(' ');
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
