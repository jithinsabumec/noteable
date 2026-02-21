import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:noteable/screens/login_screen.dart';
import 'package:noteable/services/auth_service.dart';

class AuthWrapper extends StatefulWidget {
  final Widget Function(bool isGuestMode, VoidCallback onExitGuestMode) child;

  const AuthWrapper({super.key, required this.child});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isGuestMode = false;
  bool _hasError = false;
  String _errorMessage = '';

  void _enableGuestMode() {
    setState(() {
      _isGuestMode = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AuthService authService = AuthService();

    // If guest mode is enabled, show the main app with guest mode indicator
    if (_isGuestMode) {
      return widget.child(_isGuestMode, () {
        setState(() {
          _isGuestMode = false;
        });
      });
    }

    // If there was an error, show error screen
    if (_hasError) {
      return _buildErrorScreen();
    }

    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        // Handle stream error state
        if (snapshot.hasError) {
          // Log the error for debugging
          print('AUTH STREAM ERROR: ${snapshot.error}');

          // Update state to show error screen on next build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() {
              _hasError = true;
              _errorMessage = 'Authentication error: ${snapshot.error}';
            });
          });

          // Show loading indicator while state updates
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          // While waiting for the authentication state to be determined
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        } else {
          // Check if the user is logged in
          if (snapshot.hasData) {
            try {
              // User is logged in, show the main app with authenticated user state
              return widget.child(false, () {}); // Not guest mode, empty callback
            } catch (e) {
              // Log the error for debugging
              print('MAIN APP RENDERING ERROR: $e');

              // Update state to show error screen on next build
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() {
                  _hasError = true;
                  _errorMessage = 'App initialization error: $e';
                });
              });

              // Show loading indicator while state updates
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
          } else {
            // User is not logged in, show the login screen with guest mode option
            return LoginScreen(onGuestMode: _enableGuestMode);
          }
        }
      },
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Authentication Error'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _hasError = false;
                _errorMessage = '';
              });
            },
          ),
          TextButton(
            onPressed: _enableGuestMode,
            child: const Text('Guest Mode'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 24),
              const Text(
                'Authentication Error',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _hasError = false;
                    _errorMessage = '';
                  });
                },
                child: const Text('Try Again'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _enableGuestMode,
                child: const Text('Continue in Guest Mode'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
