import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Add this import
import 'package:taxi_auth_app/providers/auth_provider.dart';
import 'package:taxi_auth_app/providers/map_provider.dart';
import 'package:taxi_auth_app/providers/firestore_provider.dart';
import 'package:taxi_auth_app/widgets/auth_wrapper.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
Future<void> createTestTrips() async {
  final now = Timestamp.now();
  
  // Test trips in Rex Manor area (37.4042° N, 122.0852° W) - 6 trips
  final testTrips = [
    {
      'status': 'completed',
      'createdAt': now,
      'pickup': {
        'latitude': 37.4042,
        'longitude': -122.0852,
        'address': 'Rex Manor, Trip 1'
      },
      'dropoff': {
        'latitude': 37.4068,
        'longitude': -122.0815,
        'address': 'Rex Manor Center'
      },
      'driverId': 'test_driver_1',
      'userId': 'test_user_1',
      'fare': 12.50,
      'distance': 1.2,
      'duration': 8,
    },
    {
      'status': 'completed',
      'createdAt': now,
      'pickup': {
        'latitude': 37.4044, // Very close to first trip
        'longitude': -122.0854,
        'address': 'Rex Manor, Trip 2'
      },
      'dropoff': {
        'latitude': 37.4070,
        'longitude': -122.0817,
        'address': 'Rex Manor Plaza'
      },
      'driverId': 'test_driver_2',
      'userId': 'test_user_2',
      'fare': 13.25,
      'distance': 1.3,
      'duration': 9,
    },
    {
      'status': 'completed',
      'createdAt': now,
      'pickup': {
        'latitude': 37.4046, // Close cluster
        'longitude': -122.0856,
        'address': 'Rex Manor, Trip 3'
      },
      'dropoff': {
        'latitude': 37.4072,
        'longitude': -122.0819,
        'address': 'Rex Manor Mall'
      },
      'driverId': 'test_driver_3',
      'userId': 'test_user_3',
      'fare': 11.75,
      'distance': 1.1,
      'duration': 7,
    },
    {
      'status': 'completed',
      'createdAt': now,
      'pickup': {
        'latitude': 37.4048, // Still in same cluster
        'longitude': -122.0858,
        'address': 'Rex Manor, Trip 4'
      },
      'dropoff': {
        'latitude': 37.4074,
        'longitude': -122.0821,
        'address': 'Rex Manor Station'
      },
      'driverId': 'test_driver_4',
      'userId': 'test_user_4',
      'fare': 14.00,
      'distance': 1.4,
      'duration': 10,
    },
    {
      'status': 'completed',
      'createdAt': now,
      'pickup': {
        'latitude': 37.4025, // Slightly different area in Rex Manor
        'longitude': -122.0875,
        'address': 'Rex Manor South, Trip 5'
      },
      'dropoff': {
        'latitude': 37.4051,
        'longitude': -122.0838,
        'address': 'Rex Manor Hospital'
      },
      'driverId': 'test_driver_5',
      'userId': 'test_user_5',
      'fare': 15.50,
      'distance': 1.8,
      'duration': 12,
    },
    {
      'status': 'completed',
      'createdAt': now,
      'pickup': {
        'latitude': 37.4027, // Close to trip 5
        'longitude': -122.0877,
        'address': 'Rex Manor South, Trip 6'
      },
      'dropoff': {
        'latitude': 37.4053,
        'longitude': -122.0840,
        'address': 'Rex Manor Park'
      },
      'driverId': 'test_driver_6',
      'userId': 'test_user_6',
      'fare': 16.25,
      'distance': 1.9,
      'duration': 13,
    },
  ];
  
  for (int i = 0; i < testTrips.length; i++) {
    await FirebaseFirestore.instance
        .collection('trips')
        .add(testTrips[i]);
  }
  
  print('Created ${testTrips.length} test completed trips in Rex Manor');
}
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // await EmulatorConfig.configureEmulators();
  // createTestTrips(); // Create test trips for demo purposes
  // Configure Firestore for better real-time performance
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    sslEnabled: true,
  );
  
  runApp(MyApp(navigatorKey: navigatorKey));
}

class MyApp extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const MyApp({Key? key, required this.navigatorKey}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => MapProvider()),
        ChangeNotifierProvider(create: (_) => FirestoreProvider()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Ismail Taxi',
        theme: ThemeData(
          primarySwatch: Colors.amber,
          primaryColor: Colors.amber,
          colorScheme: ColorScheme.fromSwatch(
            primarySwatch: Colors.amber,
            accentColor: Colors.amberAccent,
          ),
          visualDensity: VisualDensity.adaptivePlatformDensity,
          appBarTheme: const AppBarTheme(
            elevation: 2,
            centerTitle: false,
          ),
          buttonTheme: const ButtonThemeData(
            buttonColor: Colors.amber,
            textTheme: ButtonTextTheme.primary,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 95, 92, 84),
              foregroundColor: Colors.black87,
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
        home: const AuthWrapper(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
