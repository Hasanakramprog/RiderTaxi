import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class TripPersistenceService {
  static const String _activeTripKey = 'active_trip_data';
  static const String _activeTripIdKey = 'active_trip_id';
  static const String _tripStatusKey = 'trip_status';
  static const String _tripUserIdKey = 'trip_user_id';

  // Save active trip data to local storage
  static Future<void> saveActiveTrip({
    required String tripId,
    required String userId,
    required Map<String, dynamic> tripData,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Save trip ID and user ID
      await prefs.setString(_activeTripIdKey, tripId);
      await prefs.setString(_tripUserIdKey, userId);
      
      // Save trip status if available
      if (tripData['status'] != null) {
        await prefs.setString(_tripStatusKey, tripData['status'].toString());
      }
      
      // Save minimal trip data for quick resume
      final minimalTripData = {
        'tripId': tripId,
        'userId': userId,
        'status': tripData['status'] ?? 'searching',
        'pickup': tripData['pickup'],
        'dropoff': tripData['dropoff'],
        'createdAt': tripData['createdAt'] != null 
            ? tripData['createdAt'].toString() 
            : DateTime.now().toIso8601String(),
        'updatedAt': tripData['updatedAt'] != null
            ? tripData['updatedAt'].toString()
            : DateTime.now().toIso8601String(),
      };
      
      final tripDataJson = jsonEncode(minimalTripData);
      await prefs.setString(_activeTripKey, tripDataJson);
      
      print('Saved active trip to persistence: $tripId for user $userId');
    } catch (e) {
      print('Error saving active trip to persistence: $e');
      // Don't throw - persistence failure shouldn't break the app
    }
  }

  // Get active trip data from local storage
  static Future<Map<String, dynamic>?> getActiveTrip() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check if we have a trip ID
      final tripId = prefs.getString(_activeTripIdKey);
      final userId = prefs.getString(_tripUserIdKey);
      
      if (tripId == null || userId == null) {
        return null;
      }
      
      // Get the full trip data
      final tripDataJson = prefs.getString(_activeTripKey);
      if (tripDataJson == null) {
        // Try to return at least the IDs
        return {
          'tripId': tripId,
          'userId': userId,
          'status': prefs.getString(_tripStatusKey) ?? 'unknown',
        };
      }
      
      final tripData = jsonDecode(tripDataJson) as Map<String, dynamic>;

      // Check if persisted trip is expired (> 1 hour old)
      final createdAtStr = tripData['createdAt']?.toString();
      final updatedAtStr = tripData['updatedAt']?.toString();
      DateTime? tripTime = createdAtStr != null ? DateTime.tryParse(createdAtStr) : null;
      tripTime ??= updatedAtStr != null ? DateTime.tryParse(updatedAtStr) : null;
      if (tripTime != null && DateTime.now().difference(tripTime).inMinutes >= 60) {
        print('Persisted trip $tripId is > 1 hour old, clearing persistence');
        await clearActiveTrip();
        return null;
      }
      
      print('Retrieved active trip from persistence: $tripId');
      return tripData;
    } catch (e) {
      print('Error getting active trip from persistence: $e');
      return null;
    }
  }

  // Check if there's an active trip in persistence
  static Future<bool> hasActiveTrip() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tripId = prefs.getString(_activeTripIdKey);
      return tripId != null && tripId.isNotEmpty;
    } catch (e) {
      print('Error checking for active trip: $e');
      return false;
    }
  }

  // Clear active trip data from local storage
  static Future<void> clearActiveTrip() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get trip ID before clearing for logging
      final tripId = prefs.getString(_activeTripIdKey);
      
      await prefs.remove(_activeTripKey);
      await prefs.remove(_activeTripIdKey);
      await prefs.remove(_tripStatusKey);
      await prefs.remove(_tripUserIdKey);
      
      print('Cleared active trip from persistence: $tripId');
    } catch (e) {
      print('Error clearing active trip from persistence: $e');
      // Don't throw - continue clearing other data
    }
  }

  // Clear active trip only if it belongs to a specific user
  static Future<void> clearActiveTripForUser(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUserId = prefs.getString(_tripUserIdKey);
      
      if (savedUserId == userId) {
        await clearActiveTrip();
        print('Cleared active trip for user: $userId');
      } else {
        print('Active trip belongs to different user (saved: $savedUserId, current: $userId)');
      }
    } catch (e) {
      print('Error clearing active trip for user: $e');
    }
  }

  // Update only the trip status in persistence
  static Future<void> updateTripStatus(String status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tripStatusKey, status);
      
      // Also update in the full trip data if it exists
      final tripDataJson = prefs.getString(_activeTripKey);
      if (tripDataJson != null) {
        final tripData = jsonDecode(tripDataJson) as Map<String, dynamic>;
        tripData['status'] = status;
        tripData['updatedAt'] = DateTime.now().toIso8601String();
        await prefs.setString(_activeTripKey, jsonEncode(tripData));
      }
      
      print('Updated trip status in persistence: $status');
    } catch (e) {
      print('Error updating trip status in persistence: $e');
    }
  }
}
