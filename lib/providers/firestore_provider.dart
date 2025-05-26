import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Collection references
  CollectionReference get usersCollection => _firestore.collection('users');
  CollectionReference get driversCollection => _firestore.collection('drivers');
  CollectionReference get tripsCollection => _firestore.collection('trips');
  CollectionReference get paymentsCollection => _firestore.collection('payments');
  CollectionReference get vehiclesCollection => _firestore.collection('vehicles');
  
  // Current user data
  Map<String, dynamic> _currentUserData = {};
  Map<String, dynamic> get currentUserData => _currentUserData;
  
  // Check if current user is a driver
  bool _isDriver = false;
  bool get isDriver => _isDriver;
  
  // Current user ID getter
  String? get currentUserId => _auth.currentUser?.uid;
  
  // Initialize data for current user
  Future<void> initializeUserData() async {
    if (_auth.currentUser == null) return;
    
    try {
      // Get user document
      DocumentSnapshot userDoc = await usersCollection
          .doc(_auth.currentUser!.uid)
          .get();
      
      // Check if user exists in users collection
      if (userDoc.exists) {
        _currentUserData = userDoc.data() as Map<String, dynamic>;
        _isDriver = false;
        notifyListeners();
        return;
      }
      
      // If not found in users, check drivers collection
      DocumentSnapshot driverDoc = await driversCollection
          .doc(_auth.currentUser!.uid)
          .get();
      
      if (driverDoc.exists) {
        _currentUserData = driverDoc.data() as Map<String, dynamic>;
        _isDriver = true;
        notifyListeners();
        return;
      }
      
      // If not found in either collection, create a new user
      if (!userDoc.exists && !driverDoc.exists) {
        await createNewUser();
      }
    } catch (e) {
      print('Error initializing user data: $e');
    }
  }
  
  // Create a new user in Firestore
  Future<void> createNewUser() async {
    if (_auth.currentUser == null) return;
    
    try {
      final user = _auth.currentUser!;
      
      // Basic user data
      final userData = {
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName ?? '',
        'phoneNumber': user.phoneNumber ?? '',
        'photoURL': user.photoURL ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'favoriteLocations': [],
        'paymentMethods': [],
        'rating': 5.0,
        'tripCount': 0,
      };
      
      // Store in users collection
      await usersCollection.doc(user.uid).set(userData);
      
      // Update local data
      _currentUserData = userData;
      _isDriver = false;
      notifyListeners();
    } catch (e) {
      print('Error creating new user: $e');
    }
  }
  
  // Update user profile
  Future<void> updateUserProfile({
    String? displayName,
    String? phoneNumber,
    String? photoURL,
  }) async {
    if (currentUserId == null) return;
    
    try {
      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      if (displayName != null) updates['displayName'] = displayName;
      if (phoneNumber != null) updates['phoneNumber'] = phoneNumber;
      if (photoURL != null) updates['photoURL'] = photoURL;
      
      final collectionRef = isDriver ? driversCollection : usersCollection;
      
      await collectionRef.doc(currentUserId).update(updates);
      
      // Update local data
      _currentUserData.addAll(updates);
      notifyListeners();
    } catch (e) {
      print('Error updating profile: $e');
    }
  }
  
  // Add a favorite location
  Future<void> addFavoriteLocation(Map<String, dynamic> location) async {
    if (currentUserId == null) return;
    
    try {
      final collectionRef = isDriver ? driversCollection : usersCollection;
      
      await collectionRef.doc(currentUserId).update({
        'favoriteLocations': FieldValue.arrayUnion([location]),
      });
      
      // Update local data
      if (_currentUserData['favoriteLocations'] == null) {
        _currentUserData['favoriteLocations'] = [];
      }
      (_currentUserData['favoriteLocations'] as List).add(location);
      notifyListeners();
    } catch (e) {
      print('Error adding favorite location: $e');
    }
  }
  
  // Create a new trip request
  Future<DocumentReference> createTrip(Map<String, dynamic> tripData) async {
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }
    
    try {
      // Add user info to trip data
      tripData['userId'] = currentUserId;
      tripData['userInfo'] = {
        'name': _currentUserData['displayName'] ?? '',
        'photoURL': _currentUserData['photoURL'] ?? '',
        'rating': _currentUserData['rating'] ?? 5.0,
      };
      
      // Add timestamps
      tripData['status'] = 'searching';
      tripData['createdAt'] = FieldValue.serverTimestamp();
      tripData['updatedAt'] = FieldValue.serverTimestamp();
      
      // // Add initial status
      // tripData['status'] = 'requested';
      
      // Create the trip in Firestore
      final tripRef = await tripsCollection.add(tripData);
      
      // Update user's trip count
      final collectionRef = isDriver ? driversCollection : usersCollection;
      await collectionRef.doc(currentUserId).update({
        'tripCount': FieldValue.increment(1),
      });
      
      return tripRef;
    } catch (e) {
      print('Error creating trip: $e');
      throw Exception('Failed to create trip: $e');
    }
  }
  
  // Get trips by user
  Stream<QuerySnapshot> getUserTrips() {
    if (currentUserId == null) {
      // Return empty stream if user is not logged in
      return Stream.fromIterable([]);
    }
    
    return tripsCollection
        .where('userId', isEqualTo: currentUserId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
  
  // Get a single trip by ID
  Stream<DocumentSnapshot> getTrip(String tripId) {
    return tripsCollection.doc(tripId).snapshots();
  }
  
  // Update trip status
  Future<void> updateTripStatus(String tripId, String status) async {
    try {
      await tripsCollection.doc(tripId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error updating trip status: $e');
    }
  }
  
  // Add payment record
  Future<void> addPayment({
    required String tripId,
    required double amount,
    required String paymentMethod,
    String? paymentId,
    String? receiptUrl,
  }) async {
    if (currentUserId == null) return;
    
    try {
      final paymentData = {
        'tripId': tripId,
        'userId': currentUserId,
        'amount': amount,
        'paymentMethod': paymentMethod,
        'status': 'completed',
        'timestamp': FieldValue.serverTimestamp(),
      };
      
      if (paymentId != null) paymentData['paymentId'] = paymentId;
      if (receiptUrl != null) paymentData['receiptUrl'] = receiptUrl;
      
      // Add to payments collection
      await paymentsCollection.add(paymentData);
      
      // Update trip with payment info
      await tripsCollection.doc(tripId).update({
        'paymentCompleted': true,
        'paymentAmount': amount,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error adding payment: $e');
    }
  }
  
  // Add driver vehicle
  Future<void> addVehicle(Map<String, dynamic> vehicleData) async {
    if (currentUserId == null) return;
    
    try {
      vehicleData['driverId'] = currentUserId;
      vehicleData['createdAt'] = FieldValue.serverTimestamp();
      vehicleData['updatedAt'] = FieldValue.serverTimestamp();
      
      // Add to vehicles collection
      final vehicleRef = await vehiclesCollection.add(vehicleData);
      
      // Link vehicle to driver
      await driversCollection.doc(currentUserId).update({
        'vehicles': FieldValue.arrayUnion([vehicleRef.id]),
      });
    } catch (e) {
      print('Error adding vehicle: $e');
    }
  }
  
  // Rate a driver
  Future<void> rateDriver(String driverId, double rating, String? comment) async {
    try {
      // Get driver's current rating data
      final driverDoc = await driversCollection.doc(driverId).get();
      final driverData = driverDoc.data() as Map<String, dynamic>? ?? {};
      
      final currentRating = driverData['rating'] ?? 5.0;
      final ratingCount = driverData['ratingCount'] ?? 0;
      
      // Calculate new average rating
      final newRatingCount = ratingCount + 1;
      final newAvgRating = ((currentRating * ratingCount) + rating) / newRatingCount;
      
      // Update driver document
      await driversCollection.doc(driverId).update({
        'rating': newAvgRating,
        'ratingCount': newRatingCount,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      // Add rating to ratings subcollection
      await driversCollection
          .doc(driverId)
          .collection('ratings')
          .add({
            'rating': rating,
            'comment': comment,
            'userId': currentUserId,
            'timestamp': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      print('Error rating driver: $e');
    }
  }
  
  // Create test drivers
  Future<void> createTestDrivers() async {
    try {
      // Create 3 test drivers at different distances from a central point
      List<Map<String, dynamic>> testDrivers = [
        {
          'displayName': 'Test Driver 1',
          'isOnline': true,
          'isAvailable': true,
          'location': {
            'latitude': 37.7749, // Base location
            'longitude': -122.4194
          },
          'fcmToken': 'test-token-1',
          'rating': 4.8,
          'carDetails': {
            'model': 'Toyota Camry',
            'color': 'Black',
            'plateNumber': 'TEST-123'
          }
        },
        {
          'displayName': 'Test Driver 2',
          'isOnline': true,
          'isAvailable': true,
          'location': {
            'latitude': 37.7849, // ~1km away
            'longitude': -122.4294
          },
          'fcmToken': 'test-token-2',
          'rating': 4.5
        },
        {
          'displayName': 'Test Driver 3',
          'isOnline': true,
          'isAvailable': true,
          'location': {
            'latitude': 37.7649, // ~2km away
            'longitude': -122.4094
          },
          'fcmToken': 'test-token-3',
          'rating': 4.9
        }
      ];
      
      // Add drivers to Firestore
      for (var driverData in testDrivers) {
        await driversCollection.add(driverData);
      }
      
      print('Test drivers created successfully');
    } catch (e) {
      print('Error creating test drivers: $e');
    }
  }
}