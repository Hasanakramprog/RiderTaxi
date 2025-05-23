import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:taxi_auth_app/providers/auth_provider.dart';
import 'package:taxi_auth_app/providers/map_provider.dart';
import 'package:taxi_auth_app/providers/firestore_provider.dart';
import 'package:taxi_auth_app/widgets/auth_wrapper.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // await EmulatorConfig.configureEmulators();
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
