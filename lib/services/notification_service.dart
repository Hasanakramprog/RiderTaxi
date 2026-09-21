import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../main.dart' show navigatorKey;
import '../screens/trip_tracking_screen.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handles notifications when app is in the background or terminated
  debugPrint('Background message received: ${message.messageId}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'Used for ride status updates, arrival, and emergency alerts',
    importance: Importance.max,
    playSound: true,
  );

  bool _isInitialized = false;

  /// Initialize notification service, request permissions, and register handlers
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // 1. Request notification permissions (iOS & Android 13+)
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint('FCM AuthorizationStatus: ${settings.authorizationStatus}');

      // 2. iOS foreground presentation options
      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 3. Configure local notifications for foreground popups
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      await _localNotifications.initialize(
        settings: const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            _handleNotificationNavigation(payload);
          }
        },
      );

      // 4. Create high-importance Android channel
      if (Platform.isAndroid) {
        final androidImplementation = _localNotifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        await androidImplementation?.createNotificationChannel(_androidChannel);
      }

      // 5. Listen for incoming foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Foreground FCM message received: ${message.notification?.title}');
        // On iOS, setForegroundNotificationPresentationOptions already presents the native banner.
        // We only trigger local notification on Android (where foreground banners are suppressed by default)
        // or for data-only payloads.
        if (Platform.isAndroid || message.notification == null) {
          _showForegroundNotification(message);
        }
      });

      // 6. Handle notification click when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('App opened from background notification: ${message.data}');
        final tripId = message.data['tripId']?.toString();
        if (tripId != null && tripId.isNotEmpty) {
          _handleNotificationNavigation(tripId);
        }
      });

      // 7. Check if app was launched from a terminated notification click
      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('App opened from terminated notification: ${initialMessage.data}');
        final tripId = initialMessage.data['tripId']?.toString();
        if (tripId != null && tripId.isNotEmpty) {
          // Delay navigation slightly so that the app's widget tree is mounted
          Future.delayed(const Duration(milliseconds: 1000), () {
            _handleNotificationNavigation(tripId);
          });
        }
      }

      // 8. Listen for token refreshes
      _fcm.onTokenRefresh.listen((newToken) {
        debugPrint('FCM token refreshed: $newToken');
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        if (currentUserId != null) {
          _saveTokenToFirestore(currentUserId, newToken);
        }
      });

      _isInitialized = true;
      debugPrint('NotificationService successfully initialized');
    } catch (e) {
      debugPrint('Error initializing NotificationService: $e');
    }
  }

  /// Save FCM device token for the current user in Firestore
  Future<void> saveUserFcmToken({String? userId}) async {
    final uid = userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      if (Platform.isIOS) {
        // Wait for APNs token to be set by iOS before requesting FCM token
        String? apnsToken = await _fcm.getAPNSToken();
        if (apnsToken == null) {
          // Retry briefly for APNs token generation in development
          await Future.delayed(const Duration(seconds: 2));
          apnsToken = await _fcm.getAPNSToken();
        }
        debugPrint('iOS APNs Token: $apnsToken');
      }

      final fcmToken = await _fcm.getToken();
      if (fcmToken != null) {
        debugPrint('FCM Token obtained: $fcmToken');
        await _saveTokenToFirestore(uid, fcmToken);
      }
    } catch (e) {
      debugPrint('Error getting or saving FCM token: $e');
    }
  }

  /// Remove FCM device token from Firestore when user signs out
  Future<void> clearUserFcmToken({String? userId}) async {
    final uid = userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmToken': FieldValue.delete(),
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('Cleared FCM token for user $uid');
    } catch (e) {
      debugPrint('Error clearing FCM token: $e');
    }
  }

  Future<void> _saveTokenToFirestore(String userId, String token) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        'devicePlatform': Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'other'),
      }, SetOptions(merge: true));
      debugPrint('Saved FCM token to Firestore for user $userId');
    } catch (e) {
      debugPrint('Error saving FCM token to Firestore: $e');
    }
  }

  /// Display a local pop-up notification when the app is active in foreground
  void _showForegroundNotification(RemoteMessage message) {
    // If iOS already showed the system banner, avoid duplicate
    if (Platform.isIOS && message.notification != null) return;

    final notification = message.notification;
    final tripId = message.data['tripId']?.toString();

    if (notification != null) {
      _localNotifications.show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannel.id,
            _androidChannel.name,
            channelDescription: _androidChannel.description,
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: tripId,
      );
    }
  }

  /// Route the user directly to the active TripTrackingScreen
  void _handleNotificationNavigation(String tripId) {
    if (tripId.isEmpty) return;

    debugPrint('Navigating to trip tracking screen for trip: $tripId');
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => TripTrackingScreen(tripId: tripId),
      ),
    );
  }
}
