import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'dart:convert';
import 'dart:math' as math;
import '../providers/auth_provider.dart';
import '../widgets/animated_taxi_road.dart';
import 'trip_request_screen.dart';
import 'trip_history_screen.dart';

// Global navigator key to access context from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _floatController;
  late AnimationController _slideController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _floatAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    
    // Pulse animation for the main button
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Float animation for cards
    _floatController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    
    _floatAnimation = Tween<double>(begin: -5, end: 5).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );
    
    // Slide animation for initial appearance
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    
    _slideController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _floatController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.amber.shade400, Colors.orange.shade600],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.local_taxi, size: 24, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Text(
              'Ismail Taxi',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 22,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Colors.amber.shade400, Colors.orange.shade600],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.amber.withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.account_circle, color: Colors.white),
              onPressed: () {
                _showProfileDialog(context, authProvider);
              },
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.amber.shade50,
              Colors.orange.shade50,
              Colors.amber.shade100,
            ],
          ),
        ),
        child: Column(
        children: [
          // Add our custom animated taxi on road
          const AnimatedTaxiRoad(),
          
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      'Welcome to Ismail Taxi',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Where do you want to go?',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 30),
                    // Quick destination options
                    _buildDestinationOptions(),
                    const SizedBox(height: 40),
                    // CTA button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const TripRequestScreen()),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black87,
                          elevation: 4,
                          shadowColor: Colors.amberAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_rounded, size: 28),
                            SizedBox(width: 8),
                            Text(
                              'BOOK A TAXI',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Bottom options
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildCircleButton(
                          icon: Icons.history,
                          label: 'My Trips',
                          onPressed: () {
                            // Navigate to trip history screen
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const TripHistoryScreen()),
                            );
                          },
                        ),
                        _buildCircleButton(
                          icon: Icons.card_giftcard,
                          label: 'Promotions',
                          onPressed: () {
                            // Navigate to promotions screen
                          },
                        ),
                        _buildCircleButton(
                          icon: Icons.support_agent,
                          label: 'Support',
                          onPressed: () {
                            // Navigate to support screen or show support dialog
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // ElevatedButton(
                    //   onPressed: () {
                    //     // First time, create test drivers
                    //     // firestoreProvider.createTestDrivers();
                        
                    //     // Test the cloud function
                    //     testFindNearbyDriversFunction();
                    //   },
                    //   child: Text('Test Cloud Function'),
                    // ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDestinationOptions() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildDestinationCard(
                icon: Icons.home,
                title: 'Home',
                address: '123 Main St',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDestinationCard(
                icon: Icons.work,
                title: 'Work',
                address: '456 Office Blvd',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildDestinationCard(
                icon: Icons.shopping_bag,
                title: 'Shopping',
                address: 'City Mall',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDestinationCard(
                icon: Icons.restaurant,
                title: 'Restaurant',
                address: 'Food Street',
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildDestinationCard({
    required IconData icon,
    required String title,
    required String address,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.amber.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              address,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCircleButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  spreadRadius: 1,
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.amber.shade800,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }
  
  // Add this to your main app to trigger a test trip
Future<void> testFindNearbyDriversFunction() async {
  try {
    final firestore = FirebaseFirestore.instance;
    
    // First, create test drivers
    print('Creating test drivers...');
    await _createTestDrivers();
    
    // Create a test trip with 'searching' status
    final tripData = {
      'pickup': {
        'latitude': 37.7749,
        'longitude': -122.4194,
        'address': '123 Test St, San Francisco, CA'
      },
      'dropoff': {
        'latitude': 37.7833,
        'longitude': -122.4167,
        'address': '456 Demo Ave, San Francisco, CA'
      },
      'distance': 2.5, // km
      'duration': 10, // minutes
      'fare': 15.0, // dollars
      'status': 'searching', // This is crucial
      'createdAt': FieldValue.serverTimestamp(),
      'userId': firebase_auth.FirebaseAuth.instance.currentUser?.uid ?? 'test-user'
    };
    
    print('Creating test trip...');
    final tripRef = await firestore.collection('trips').add(tripData);
    print('Test trip created with ID: ${tripRef.id}');
    
    // // Listen for updates on this trip
    // tripRef.snapshots().listen((snapshot) {
    //   if (snapshot.exists) {
    //     final data = snapshot.data()!;
    //     print('Trip updated: ${jsonEncode(data)}');
        
    //     if (data['nearbyDrivers'] != null) {
    //       print('Found nearby drivers: ${data['nearbyDrivers'].length}');
          
    //       if (data['notifiedDriverId'] != null) {
    //         print('Driver was notified! Function worked!');
    //         _showDriverAcceptDialog(data['notifiedDriverId']);
    //       }
    //     }
        
    //     if (data['noDriversAvailable'] == true) {
    //       print('No drivers available. Function processed the trip but found no drivers.');
    //     }
    //   }
    // });
    
  } catch (e) {
    print('Error testing function: $e');
  }
}

// Helper method to create test drivers
Future<void> _createTestDrivers() async {
  try {
    final firestore = FirebaseFirestore.instance;
    
    // Check if test drivers already exist
    final existingDrivers = await firestore.collection('drivers')
        .where('isTestDriver', isEqualTo: true)
        .get();
    
    if (existingDrivers.docs.isNotEmpty) {
      print('Test drivers already exist (${existingDrivers.docs.length} drivers)');
      return;
    }
    
    // Create a batch for adding multiple drivers efficiently
    final batch = firestore.batch();
    
    // Driver 1 - Very close to the pickup location
    final driver1Ref = firestore.collection('drivers').doc('test-driver-1');
    batch.set(driver1Ref, {
      'displayName': 'Test Driver 1',
      'isOnline': true,
      'isAvailable': true,
      'isTestDriver': true,
      'location': {
        'latitude': 37.7751, // Very close to pickup
        'longitude': -122.4196
      },
      'fcmToken': 'test-token-1',
      'rating': 4.8,
      'carDetails': {
        'model': 'Toyota Camry',
        'color': 'Black',
        'plateNumber': 'TEST-123'
      }
    });
    
    // Driver 2 - A bit further away
    final driver2Ref = firestore.collection('drivers').doc('test-driver-2');
    batch.set(driver2Ref, {
      'displayName': 'Test Driver 2',
      'isOnline': true,
      'isAvailable': true,
      'isTestDriver': true,
      'location': {
        'latitude': 37.7780, // ~0.5km away
        'longitude': -122.4220
      },
      'fcmToken': 'test-token-2',
      'rating': 4.5,
      'carDetails': {
        'model': 'Honda Accord',
        'color': 'White',
        'plateNumber': 'TEST-456'
      }
    });
    
    // Driver 3 - Even further away
    final driver3Ref = firestore.collection('drivers').doc('test-driver-3');
    batch.set(driver3Ref, {
      'displayName': 'Test Driver 3',
      'isOnline': true,
      'isAvailable': true,
      'isTestDriver': true,
      'location': {
        'latitude': 37.7700, // ~1km away
        'longitude': -122.4150
      },
      'fcmToken': 'test-token-3',
      'rating': 4.9,
      'carDetails': {
        'model': 'Tesla Model 3',
        'color': 'Red',
        'plateNumber': 'TEST-789'
      }
    });
    
    // Commit the batch
    await batch.commit();
    print('Successfully created 3 test drivers');
  } catch (e) {
    print('Error creating test drivers: $e');
  }
}

// Helper method to simulate driver accepting a trip
void _showDriverAcceptDialog(String driverId) {
  // This would be shown to simulate driver accepting the trip
  // In a real app, this would come from the driver app
  
  // Get the BuildContext - you'll need to refactor this if used in a StatelessWidget
  final context = navigatorKey.currentContext;
  if (context == null) return;
  
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Driver Found!'),
      content: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('drivers').doc(driverId).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const CircularProgressIndicator();
          }
          
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Text('Driver information not available');
          }
          
          final driverData = snapshot.data!.data() as Map<String, dynamic>;
          final carDetails = driverData['carDetails'] as Map<String, dynamic>?;
          
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Name: ${driverData['displayName'] ?? 'Unknown'}'),
              Text('Rating: ${driverData['rating'] ?? 'N/A'} ⭐'),
              if (carDetails != null) ...[
                const SizedBox(height: 8),
                Text('Car: ${carDetails['model'] ?? 'Unknown'}'),
                Text('Color: ${carDetails['color'] ?? 'Unknown'}'),
                Text('Plate: ${carDetails['plateNumber'] ?? 'Unknown'}'),
              ],
              const SizedBox(height: 12),
              const Text('Driver is on the way!'),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          child: const Text('Cancel Trip'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        ElevatedButton(
          child: const Text('OK'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    ),
  );
  
  // Optional: Simulate driver arriving after a delay
  Future.delayed(const Duration(seconds: 5), () {
    _simulateDriverArrival(driverId);
  });
}

// Helper method to simulate driver arrival
void _simulateDriverArrival(String driverId) {
  final context = navigatorKey.currentContext;
  if (context == null) return;
  
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Driver Has Arrived!'),
      content: const Text('Your driver is waiting outside.'),
      actions: [
        ElevatedButton(
          child: const Text('I\'m Coming'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    ),
  );
}
}