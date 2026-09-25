import 'package:flutter/foundation.dart';

/// Centralized application configuration loaded from environment variables (.env).
class AppConfig {
  /// Google Maps API Key loaded via `--dart-define` or `--dart-define-from-file=.env`
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  /// Helper to verify if the Google Maps API key has been injected.
  static bool get hasGoogleMapsApiKey => googleMapsApiKey.isNotEmpty;

  /// Log configuration status for debugging
  static void logConfigStatus() {
    if (kDebugMode) {
      if (googleMapsApiKey.isEmpty) {
        debugPrint(
          '⚠️ [AppConfig] GOOGLE_MAPS_API_KEY is not set.\n'
          '   To provide it, pass --dart-define-from-file=.env when running the app.',
        );
      } else {
        debugPrint('✅ [AppConfig] GOOGLE_MAPS_API_KEY loaded successfully.');
      }
    }
  }
}
