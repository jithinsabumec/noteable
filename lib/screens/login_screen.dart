import 'package:flutter/material.dart';
import 'package:noteable/services/auth_service.dart';
import 'package:flutter_svg/flutter_svg.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback? onGuestMode;

  const LoginScreen({super.key, this.onGuestMode});

  @override
  // ignore: library_private_types_in_public_api
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  bool _isGoogleLoading = false;
  String _errorMessage = '';

  final AuthService _authService = AuthService();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isGoogleLoading = true;
      _errorMessage = '';
    });

    try {
      await _authService.signInWithGoogle();
    } catch (e) {
      String errorMessage = e.toString().replaceAll('Exception: ', '');

      // Check for specific error types and provide user-friendly messages
      if (errorMessage.contains('time synchronization') ||
          errorMessage.contains('600 seconds') ||
          errorMessage.contains('time is more than')) {
        _showTimeSyncDialog();
        return;
      } else if (errorMessage.contains('network')) {
        errorMessage = 'Please check your internet connection and try again.';
      } else if (errorMessage.contains('cancelled') ||
          errorMessage.contains('canceled')) {
        errorMessage = 'Sign-in was cancelled. Please try again.';
      } else if (errorMessage.contains('invalid-credential')) {
        errorMessage =
            'There was an issue with your Google account. Please try again.';
      } else if (errorMessage.contains('operation-not-allowed')) {
        errorMessage =
            'Google Sign-In is currently not available. Please try again later.';
      }

      setState(() {
        _errorMessage = errorMessage;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
        });
      }
    }
  }

  void _showTimeSyncDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.access_time, color: Colors.orange.shade600),
              const SizedBox(width: 8),
              const Text(
                'Time Sync Issue',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Google Sign-In failed due to a time synchronization issue. This can happen when your device time is incorrect.',
                style: TextStyle(fontFamily: 'Geist', fontSize: 16),
              ),
              SizedBox(height: 16),
              Text(
                'To fix this:',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '• Check your device date and time settings\n'
                '• Enable automatic date & time\n'
                '• Ensure you have a stable internet connection\n'
                '• Try signing in again',
                style: TextStyle(fontFamily: 'Geist', fontSize: 14),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'OK',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(0.50, -0.00),
            end: Alignment(0.50, 1.00),
            colors: [Color(0xFF5387FF), Color(0xFF244CFF)],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Stack(
              children: [
                // Login illustration at the top (enlarged and positioned to cut off top portion)
                Positioned(
                  top: -140,
                  left: -60,
                  right: -60,
                  child: Center(
                    child: Image.asset(
                      'assets/icons/login.png',
                      height: 550,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

                // Main content with SafeArea
                SafeArea(
                  child: Column(
                    children: [
                      // Top spacing to account for illustration
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.37,
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return SingleChildScrollView(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight - 12,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32.0,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // Welcome text
                              const Text(
                                'Welcome to',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w400,
                                  fontFamily: 'Geist',
                                  color: Colors.white70,
                                  height: 1.2,
                                ),
                                textAlign: TextAlign.center,
                              ),

                              const SizedBox(height: 2),

                              const Text(
                                'Noteable',
                                style: TextStyle(
                                  fontSize: 52,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Geist',
                                  color: Colors.white,
                                  height: 1.1,
                                  letterSpacing: -1.0,
                                ),
                                textAlign: TextAlign.center,
                              ),

                              const SizedBox(height: 80),

                              // Google Sign-In Button
                              _buildGoogleButton(),

                              const SizedBox(height: 24),

                              // Divider with "or" text
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 1,
                                      color: Colors.white.withOpacity(0.3),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Text(
                                      'or',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontFamily: 'Geist',
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      height: 1,
                                      color: Colors.white.withOpacity(0.3),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 24),

                              // Guest mode text and button
                              Text(
                                'Use guest mode to try the app',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontFamily: 'Geist',
                                  color: Colors.white.withOpacity(0.65),
                                  fontWeight: FontWeight.w400,
                                ),
                                textAlign: TextAlign.center,
                              ),

                              const SizedBox(height: 2),

                              RichText(
                                textAlign: TextAlign.center,
                                text: TextSpan(
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontFamily: 'Geist',
                                    color: Colors.white.withOpacity(0.65),
                                    fontWeight: FontWeight.w400,
                                  ),
                                  children: [
                                    const TextSpan(text: 'Includes '),
                                    TextSpan(
                                      text:
                                          '3 free voice-to-insight generations',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        decoration: TextDecoration.underline,
                                        decorationColor:
                                            Colors.white.withOpacity(0.85),
                                        color: Colors.white.withOpacity(0.85),
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 24),

                              // Guest mode button
                              if (widget.onGuestMode != null)
                                _buildGuestButton(),

                              // Error message
                              if (_errorMessage.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.red.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: Colors.red.shade600,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _errorMessage,
                                          style: TextStyle(
                                            color: Colors.red.shade700,
                                            fontSize: 14,
                                            fontFamily: 'Geist',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                                      const SizedBox(height: 40),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: _isGoogleLoading ? null : _signInWithGoogle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isGoogleLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF4F46E5),
                      ),
                    ),
                  )
                else
                  SvgPicture.asset(
                    'assets/icons/google_logo.svg',
                    width: 20,
                    height: 20,
                  ),
                const SizedBox(width: 12),
                const Text(
                  'Continue with Google',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Geist',
                    color: Color(0xFF1F2937),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGuestButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: widget.onGuestMode,
          child: const Center(
            child: Text(
              'Continue as a guest',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                fontFamily: 'Geist',
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Custom painter for organic shapes
class OrganicShapesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    // Create organic blob shapes
    final path1 = Path();
    path1.moveTo(size.width * 0.2, 0);
    path1.quadraticBezierTo(
      size.width * 0.4,
      size.height * 0.2,
      size.width * 0.8,
      size.height * 0.15,
    );
    path1.quadraticBezierTo(
      size.width * 1.2,
      size.height * 0.1,
      size.width * 1.0,
      size.height * 0.5,
    );
    path1.quadraticBezierTo(
      size.width * 0.8,
      size.height * 0.8,
      size.width * 0.3,
      size.height * 0.7,
    );
    path1.quadraticBezierTo(
      size.width * -0.1,
      size.height * 0.6,
      size.width * 0.0,
      size.height * 0.3,
    );
    path1.quadraticBezierTo(
      size.width * 0.1,
      size.height * 0.1,
      size.width * 0.2,
      0,
    );
    path1.close();

    canvas.drawPath(path1, paint);

    // Second organic shape
    final paint2 = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.fill;

    final path2 = Path();
    path2.moveTo(size.width * 0.6, size.height * 0.1);
    path2.quadraticBezierTo(
      size.width * 0.9,
      size.height * 0.3,
      size.width * 0.7,
      size.height * 0.6,
    );
    path2.quadraticBezierTo(
      size.width * 0.5,
      size.height * 0.9,
      size.width * 0.2,
      size.height * 0.8,
    );
    path2.quadraticBezierTo(
      size.width * -0.1,
      size.height * 0.7,
      size.width * 0.1,
      size.height * 0.4,
    );
    path2.quadraticBezierTo(
      size.width * 0.3,
      size.height * 0.1,
      size.width * 0.6,
      size.height * 0.1,
    );
    path2.close();

    canvas.drawPath(path2, paint2);

    // Third smaller organic shape
    final paint3 = Paint()
      ..color = Colors.white.withOpacity(0.12)
      ..style = PaintingStyle.fill;

    final path3 = Path();
    path3.moveTo(size.width * 0.8, size.height * 0.2);
    path3.quadraticBezierTo(
      size.width * 1.1,
      size.height * 0.4,
      size.width * 0.9,
      size.height * 0.7,
    );
    path3.quadraticBezierTo(
      size.width * 0.7,
      size.height * 1.0,
      size.width * 0.4,
      size.height * 0.9,
    );
    path3.quadraticBezierTo(
      size.width * 0.1,
      size.height * 0.8,
      size.width * 0.3,
      size.height * 0.5,
    );
    path3.quadraticBezierTo(
      size.width * 0.5,
      size.height * 0.2,
      size.width * 0.8,
      size.height * 0.2,
    );
    path3.close();

    canvas.drawPath(path3, paint3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
