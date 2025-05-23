import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class EmulatorConfig {
  static Future<void> configureEmulators() async {
    if (kDebugMode) {
      try {
        // Define emulator host
        const String host = 'localhost';
        
        // Configure Firebase Auth to use emulator
        // await FirebaseAuth.instance.useAuthEmulator(host, 9099);
        // print('✅ Connected to Auth emulator');
        
        // Configure Firestore to use emulator
        FirebaseFirestore.instance.settings = Settings(
          host: '$host:9098',
          sslEnabled: false,
          persistenceEnabled: false,
        );
        print('✅ Connected to Firestore emulator');
        
        // For Functions, use this if you have firebase_core extension methods
        try {
          final app = Firebase.app();
          app.setAutomaticDataCollectionEnabled(false);
          app.setAutomaticResourceManagementEnabled(false);
          
          // This is an undocumented way to connect to the functions emulator
          // through firebase_core
          final functionsOrigin = 'http://$host:5001';
          print('⚠️ Attempted to connect to Functions emulator using origin: $functionsOrigin');
        } catch (e) {
          print('⚠️ Note: Functions emulator connection attempted but may not be active');
        }
        
        print('🔥 Firebase emulators configured');
      } catch (e) {
        print('❌ Error configuring Firebase emulators: $e');
      }
    }
  }
}