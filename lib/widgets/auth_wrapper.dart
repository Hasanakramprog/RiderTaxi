import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_auth_app/providers/auth_provider.dart';
import 'package:taxi_auth_app/screens/home_screen_pro.dart';
import 'package:taxi_auth_app/screens/login_screen_pro.dart';
import 'package:taxi_auth_app/screens/register_screen_pro.dart';
import '../providers/firestore_provider.dart';
import '../screens/trip_tracking_screen.dart';
import '../services/trip_persistence_service.dart';
import '../services/active_trip_service.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _showLoginScreen = true;
  bool _checkingActiveTrip = false;
  bool _hasCheckedForActiveTrip = false;
  String? _activeTripId;

  void _toggleAuthScreen() {
    setState(() {
      _showLoginScreen = !_showLoginScreen;
    });
  }

  // Check for active trips when user is authenticated
  Future<void> _checkForActiveTrip(String userId) async {
    if (_checkingActiveTrip || _hasCheckedForActiveTrip) return;
    
    setState(() {
      _checkingActiveTrip = true;
    });

    try {
      print('Checking for active trips for user: $userId');
      
      // First check local persistence
      final persistedTrip = await TripPersistenceService.getActiveTrip();
      
      if (persistedTrip != null) {
        final persistedTripId = persistedTrip['tripId']?.toString();
        final persistedUserId = persistedTrip['userId']?.toString();
        
        if (persistedTripId != null && persistedUserId == userId) {
          // Verify trip still exists and is active in Firestore
          final activeTripService = ActiveTripService();
          final isValid = await activeTripService.verifyActiveTrip(persistedTripId, userId);
          
          if (isValid) {
            print('Found valid active trip in persistence: $persistedTripId');
            setState(() {
              _activeTripId = persistedTripId;
            });
            return;
          } else {
            print('Persisted trip is no longer active, clearing persistence');
            await TripPersistenceService.clearActiveTripForUser(userId);
          }
        }
      }
      
      // If no valid persisted trip, check Firestore
      print('No valid persisted trip, checking Firestore...');
      final activeTripService = ActiveTripService();
      final firestoreTripId = await activeTripService.findActiveTripForUser(userId);
      
      if (firestoreTripId != null) {
        print('Found active trip in Firestore: $firestoreTripId');
        setState(() {
          _activeTripId = firestoreTripId;
        });
      } else {
        print('No active trips found for user');
        setState(() {
          _activeTripId = null;
        });
      }
    } catch (e) {
      print('Error checking for active trips: $e');
      setState(() {
        _activeTripId = null;
      });
    } finally {
      setState(() {
        _checkingActiveTrip = false;
        _hasCheckedForActiveTrip = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final firestoreProvider = Provider.of<FirestoreProvider>(
      context,
      listen: false,
    );

    // Return HomeScreen if authenticated, otherwise show login/register screens
    if (authProvider.isAuthenticated) {
      final currentUserId = authProvider.user?.uid;
      
      // Initialize user data
      firestoreProvider.initializeUserData();
      
      // Check for active trips if we have a user ID
      if (currentUserId != null && !_checkingActiveTrip && !_hasCheckedForActiveTrip && _activeTripId == null) {
        // Start checking for active trips
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _checkForActiveTrip(currentUserId);
          }
        });
      }
      
      // If we found an active trip, navigate to trip tracking
      if (_activeTripId != null) {
        print('Navigating to active trip: $_activeTripId');
        return TripTrackingScreen(tripId: _activeTripId!);
      }
      
      // Show loading while checking for active trips
      if (_checkingActiveTrip) {
        return Scaffold(
          backgroundColor: Colors.amber,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text(
                  'Checking for active trips...',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        );
      }
      
      // No active trips, show home screen
      return const HomeScreenPro();
    } else {
      // Toggle between login and register screens
      if (_showLoginScreen) {
        return LoginScreen(showRegisterScreen: _toggleAuthScreen);
      } else {
        return RegisterScreen(showLoginScreen: _toggleAuthScreen);
      }
    }
  }
}
