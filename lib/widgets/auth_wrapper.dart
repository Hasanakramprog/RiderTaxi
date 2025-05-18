import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_auth_app/providers/auth_provider.dart';
import 'package:taxi_auth_app/screens/home_screen.dart';
import 'package:taxi_auth_app/screens/login_screen.dart';
import 'package:taxi_auth_app/screens/register_screen.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _showLoginScreen = true;

  void _toggleAuthScreen() {
    setState(() {
      _showLoginScreen = !_showLoginScreen;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    
    // Return HomeScreen if authenticated, otherwise show login/register screens
    if (authProvider.isAuthenticated) {
      return const HomeScreen();
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