import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_auth_app/providers/auth_provider.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({Key? key}) : super(key: key);

  @override
  _ForgotPasswordScreenState createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _resetSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset Password'),
        backgroundColor: Colors.amber,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _resetSent 
            ? _buildSuccessMessage() 
            : _buildResetForm(authProvider),
      ),
    );
  }

  Widget _buildSuccessMessage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.mark_email_read, size: 80, color: Colors.green),
          const SizedBox(height: 20),
          const Text(
            'Password Reset Email Sent',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          const Text(
            'Please check your email inbox and follow the instructions to reset your password.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
            ),
            child: const Text('Back to Login'),
          ),
        ],
      ),
    );
  }

  Widget _buildResetForm(AuthProvider authProvider) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.lock_reset, size: 70, color: Colors.amber),
          const SizedBox(height: 20),
          const Text(
            'Forgot Your Password?',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 15),
          const Text(
            'Enter your email address and we\'ll send you a link to reset your password.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email),
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your email';
              }
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                return 'Please enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: authProvider.isLoading
                ? null
                : () async {
                    if (_formKey.currentState!.validate()) {
                      bool success = await authProvider.resetPassword(
                        _emailController.text.trim(),
                      );
                      
                      if (!success && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(authProvider.error),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } else if (mounted) {
                        setState(() {
                          _resetSent = true;
                        });
                      }
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: authProvider.isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text(
                    'Send Reset Link',
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
          ),
        ],
      ),
    );
  }
}