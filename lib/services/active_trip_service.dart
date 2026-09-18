import 'package:cloud_firestore/cloud_firestore.dart';

class ActiveTripService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // List of statuses that indicate an active (in-progress) trip
  static const List<String> _activeStatuses = [
    'searching',
    'driver_notified',
    'driver_accepted',
    'driver_arrived',
    'in_progress',
  ];

  // Find active trip for a user
  Future<String?> findActiveTripForUser(String userId) async {
    try {
      print('Checking Firestore for active trips for user: $userId');
      
      final querySnapshot = await _firestore
          .collection('trips')
          .where('userId', isEqualTo: userId)
          .where('status', whereIn: _activeStatuses)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final tripDoc = querySnapshot.docs.first;
        final tripId = tripDoc.id;
        print('Found active trip in Firestore: $tripId');
        return tripId;
      }

      print('No active trips found in Firestore for user: $userId');
      return null;
    } catch (e) {
      print('Error finding active trip for user $userId: $e');
      // Don't throw - network errors shouldn't break the app
      return null;
    }
  }

  // Check if user has any active trips
  Future<bool> hasActiveTrip(String userId) async {
    final tripId = await findActiveTripForUser(userId);
    return tripId != null;
  }

  // Get detailed trip data by ID
  Future<Map<String, dynamic>?> getActiveTripData(String tripId) async {
    try {
      print('Fetching trip data from Firestore: $tripId');
      
      final tripDoc = await _firestore
          .collection('trips')
          .doc(tripId)
          .get();

      if (!tripDoc.exists) {
        print('Trip $tripId not found in Firestore');
        return null;
      }

      final tripData = tripDoc.data() as Map<String, dynamic>;
      tripData['tripId'] = tripId; // Include trip ID in the data
      
      print('Retrieved trip data for: $tripId');
      return tripData;
    } catch (e) {
      print('Error getting trip data for $tripId: $e');
      return null;
    }
  }

  // Verify trip is still active and belongs to user
  Future<bool> verifyActiveTrip(String tripId, String userId) async {
    try {
      print('Verifying trip $tripId belongs to user $userId');
      
      final tripDoc = await _firestore
          .collection('trips')
          .doc(tripId)
          .get();

      if (!tripDoc.exists) {
        print('Trip $tripId does not exist');
        return false;
      }

      final tripData = tripDoc.data() as Map<String, dynamic>;
      final tripUserId = tripData['userId']?.toString();
      final status = tripData['status']?.toString();

      // Check if trip belongs to user AND is still active
      final belongsToUser = tripUserId == userId;
      final isActive = status != null && _activeStatuses.contains(status);

      print('Trip verification: belongsToUser=$belongsToUser, isActive=$isActive, status=$status');
      
      return belongsToUser && isActive;
    } catch (e) {
      print('Error verifying trip $tripId: $e');
      return false;
    }
  }

  // Get all active trips (for debugging/admin purposes)
  Future<List<Map<String, dynamic>>> getAllActiveTrips() async {
    try {
      final querySnapshot = await _firestore
          .collection('trips')
          .where('status', whereIn: _activeStatuses)
          .orderBy('createdAt', descending: true)
          .get();

      final trips = querySnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['tripId'] = doc.id;
        return data;
      }).toList();

      print('Found ${trips.length} active trips total');
      return trips;
    } catch (e) {
      print('Error getting all active trips: $e');
      return [];
    }
  }

  // Check if a trip is in a completed/final state
  static bool isTripCompletedOrCancelled(String status) {
    final completedStatuses = ['completed', 'cancelled', 'no_drivers_available'];
    return completedStatuses.contains(status);
  }

  // Check if a trip status is active
  static bool isTripStatusActive(String status) {
    return _activeStatuses.contains(status);
  }
}
