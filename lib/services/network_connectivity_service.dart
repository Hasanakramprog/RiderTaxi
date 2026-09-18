import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

class NetworkConnectivityService {
  static final NetworkConnectivityService _instance = NetworkConnectivityService._internal();
  factory NetworkConnectivityService() => _instance;
  NetworkConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  List<ConnectivityResult> _currentConnectivity = [ConnectivityResult.none];
  
  // Listeners for connectivity changes
  final List<Function(bool)> _connectivityListeners = [];
  
  // Get current connectivity status
  List<ConnectivityResult> get currentConnectivity => _currentConnectivity;
  
  // Check if network is available
  bool get isConnected {
    if (_currentConnectivity.isEmpty) return false;
    return _currentConnectivity.any((r) => r != ConnectivityResult.none);
  }
  
  // Initialize network monitoring
  Future<void> initialize() async {
    try {
      // Get initial connectivity status
      final results = await _connectivity.checkConnectivity();
      _currentConnectivity = results;
      
      // Listen for connectivity changes
      _connectivitySubscription?.cancel();
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) {
        _currentConnectivity = results;
        _notifyListeners(isConnected);
        print('Network connectivity changed: $results, isConnected: $isConnected');
      });
      
      print('Network connectivity service initialized: $_currentConnectivity, isConnected: $isConnected');
    } catch (e) {
      print('Error initializing network connectivity: $e');
    }
  }
  
  // Add listener for connectivity changes
  void addListener(Function(bool) listener) {
    _connectivityListeners.add(listener);
  }
  
  // Remove listener
  void removeListener(Function(bool) listener) {
    _connectivityListeners.remove(listener);
  }
  
  // Notify all listeners
  void _notifyListeners(bool isConnected) {
    for (final listener in _connectivityListeners) {
      try {
        listener(isConnected);
      } catch (e) {
        print('Error notifying connectivity listener: $e');
      }
    }
  }
  
  // Check connectivity with retry mechanism
  Future<bool> checkConnectivityWithRetry({int maxRetries = 3}) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        final results = await _connectivity.checkConnectivity();
        _currentConnectivity = results;
        
        // Check if any connection type is available (not none)
        if (results.any((result) => result != ConnectivityResult.none)) {
          return true;
        }
        
        if (i < maxRetries - 1) {
          await Future.delayed(const Duration(seconds: 1));
        }
      } catch (e) {
        print('Error checking connectivity (attempt ${i + 1}/$maxRetries): $e');
      }
    }
    
    return false;
  }
  
  // Dispose resources
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivityListeners.clear();
  }
  
  // Static helper to get connectivity status
  static Future<bool> isNetworkAvailable() async {
    try {
      final connectivity = Connectivity();
      final results = await connectivity.checkConnectivity();
      return results.any((result) => result != ConnectivityResult.none);
    } catch (e) {
      print('Error checking network availability: $e');
      return false;
    }
  }
}
