import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:taxi_auth_app/models/user_model.dart';
import 'package:taxi_auth_app/services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  
  User? _user;
  bool _isLoading = false;
  String _error = '';
  
  // Getters
  User? get user => _user;
  bool get isLoading => _isLoading;
  String get error => _error;
  bool get isAuthenticated => _user != null;
  UserModel? get userModel => _user != null 
    ? UserModel.fromFirebaseUser(_user) 
    : null;

  // Constructor
  AuthProvider() {
    _initAuthState();
  }

  // Initialize auth state
  void _initAuthState() {
    _authService.authStateChanges.listen((User? user) {
      _user = user;
      notifyListeners();
    });
  }

  // Sign in with email and password
  Future<bool> signIn(String email, String password) async {
    _setLoading(true);
    try {
      await _authService.signInWithEmailAndPassword(email, password);
      _setLoading(false);
      return true;
    } on FirebaseAuthException catch (e) {
      _handleError(e);
      return false;
    }
  }

  // Register with email and password
  Future<bool> register(String email, String password) async {
    _setLoading(true);
    try {
      await _authService.registerWithEmailAndPassword(email, password);
      _setLoading(false);
      return true;
    } on FirebaseAuthException catch (e) {
      _handleError(e);
      return false;
    }
  }

  // Sign out
  Future<void> signOut() async {
    _setLoading(true);
    try {
      await _authService.signOut();
    } finally {
      _setLoading(false);
    }
  }

  // Reset password
  Future<bool> resetPassword(String email) async {
    _setLoading(true);
    try {
      await _authService.resetPassword(email);
      _setLoading(false);
      return true;
    } on FirebaseAuthException catch (e) {
      _handleError(e);
      return false;
    }
  }

  // Helper methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    if (loading) _error = '';
    notifyListeners();
  }

  void _handleError(FirebaseAuthException e) {
    _isLoading = false;
    switch (e.code) {
      case 'user-not-found':
        _error = 'No user found with this email.';
        break;
      case 'wrong-password':
        _error = 'Wrong password provided.';
        break;
      case 'email-already-in-use':
        _error = 'The email is already in use by another account.';
        break;
      case 'weak-password':
        _error = 'The password provided is too weak.';
        break;
      case 'invalid-email':
        _error = 'The email address is not valid.';
        break;
      default:
        _error = e.message ?? 'An unknown error occurred.';
    }
    notifyListeners();
  }
}