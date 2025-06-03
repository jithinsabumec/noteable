import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:noteable/screens/login_screen.dart';
import 'package:noteable/services/auth_service.dart';

class AuthWrapper extends StatefulWidget {
  final Widget child;

  const AuthWrapper({super.key, required this.child});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isGuestMode = false;

  void _enableGuestMode() {
    setState(() {
      _isGuestMode = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AuthService authService = AuthService();

    // If guest mode is enabled, show the main app without indicator
    if (_isGuestMode) {
      return widget.child;
    }

    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // While waiting for the authentication state to be determined
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        } else {
          // Check if the user is logged in
          if (snapshot.hasData) {
            // User is logged in, show the main app
            return widget.child;
          } else {
            // User is not logged in, show the login screen with guest mode option
            return LoginScreen(onGuestMode: _enableGuestMode);
          }
        }
      },
    );
  }
}
