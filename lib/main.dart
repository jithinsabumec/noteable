// ignore_for_file: unused_field, unused_local_variable, library_private_types_in_public_api, empty_catches, unused_element, non_constant_identifier_names, use_build_context_synchronously, deprecated_member_use, duplicate_ignore

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:noteable/services/storage_service.dart';
import 'package:rive/rive.dart' as rive;
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/auth_wrapper.dart';
import 'screens/main_screen.dart';

void main() async {
  // Ensure Flutter is properly initialized with all bindings
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize Rive
  await rive.RiveFile.initialize();

  // Initialize storage service
  await StorageService().initialize();

  // Request storage permissions on startup
  await _requestStoragePermissions();

  runApp(const MyApp());
}

// Standalone function to request storage permissions at app startup
Future<void> _requestStoragePermissions() async {
  try {
    // Check current platform
    if (Platform.isAndroid || Platform.isIOS) {
      final storageStatus = await Permission.storage.request();
      if (!storageStatus.isGranted) {
        print('Storage permission not granted: $storageStatus');
      }
    }
  } catch (e) {
    print('Error requesting storage permissions: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Noteable',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        fontFamily: 'Geist',
      ),
      home: AuthWrapper(
        child: (isGuestMode) => MainScreen(isGuestMode: isGuestMode),
      ),
    );
  }
}

class CheckmarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Scale factor to enlarge the original SVG path
    const scale = 1.25;

    final path = Path();
    // Scale the original coordinates
    path.moveTo(1.39636 * scale, 3.37194 * scale);
    path.lineTo(3.13211 * scale, 4.85972 * scale);
    path.lineTo(6.60359 * scale, 1.14027 * scale);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Add these custom painters after the CheckmarkPainter class
class MorningIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF666666)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.fill;

    // Draw the morning icon (sun rising)
    final path = Path();
    // Main sun shape
    path.moveTo(size.width * 0.5, size.height * 0.35);
    canvas.drawCircle(
        Offset(size.width * 0.5, size.height * 0.4), size.width * 0.15, paint);

    // Rays
    for (int i = 0; i < 8; i++) {
      final angle = i * (math.pi / 4);
      final startX = size.width * 0.5 + math.cos(angle) * size.width * 0.2;
      final startY = size.height * 0.4 + math.sin(angle) * size.width * 0.2;
      final endX = size.width * 0.5 + math.cos(angle) * size.width * 0.3;
      final endY = size.height * 0.4 + math.sin(angle) * size.width * 0.3;
      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
    }

    // Horizon line
    canvas.drawLine(Offset(size.width * 0.2, size.height * 0.7),
        Offset(size.width * 0.8, size.height * 0.7), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AfternoonIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF666666)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.fill;

    // Draw the afternoon icon (sun)
    canvas.drawCircle(
        Offset(size.width * 0.5, size.height * 0.5), size.width * 0.2, paint);

    // Rays
    for (int i = 0; i < 8; i++) {
      final angle = i * (math.pi / 4);
      final startX = size.width * 0.5 + math.cos(angle) * size.width * 0.25;
      final startY = size.height * 0.5 + math.sin(angle) * size.width * 0.25;
      final endX = size.width * 0.5 + math.cos(angle) * size.width * 0.35;
      final endY = size.height * 0.5 + math.sin(angle) * size.width * 0.35;
      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class EveningIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF666666)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.fill;

    // Draw the evening icon (moon and stars)
    // Moon crescent
    final path = Path();
    canvas.drawCircle(
        Offset(size.width * 0.5, size.height * 0.5), size.width * 0.2, paint);

    final erasePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(size.width * 0.6, size.height * 0.4),
        size.width * 0.18, erasePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Timeline data classes have been moved to lib/models/timeline_models.dart

class PlusIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.52941
      ..strokeCap = StrokeCap.round;

    // Scale factors if the CustomPaint size is different from viewBox (24x24)
    // Here, assuming size passed to CustomPaint is the intended drawing area (e.g., 24x24)
    double scaleX = size.width / 24.0;
    double scaleY = size.height / 24.0;

    // Vertical line (M12 2 V22)
    canvas.drawLine(
      Offset(12 * scaleX, 2 * scaleY),
      Offset(12 * scaleX, 22 * scaleY),
      paint,
    );

    // Horizontal line (M2 12 L22 12)
    canvas.drawLine(
      Offset(2 * scaleX, 12 * scaleY),
      Offset(22 * scaleX, 12 * scaleY),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false; // The icon itself doesn't change, only its rotation
  }
}

// Add this class near the end of the file
class RiveAnimationFullscreen extends StatefulWidget {
  final String animationPath;
  final String? message; // Make message optional

  const RiveAnimationFullscreen({
    super.key,
    required this.animationPath,
    this.message, // Optional parameter
  });

  @override
  _RiveAnimationFullscreenState createState() =>
      _RiveAnimationFullscreenState();
}

class _RiveAnimationFullscreenState extends State<RiveAnimationFullscreen>
    with SingleTickerProviderStateMixin {
  rive.Artboard? _riveArtboard;
  bool _isLoaded = false;
  rive.StateMachineController? _controller;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  String? _currentAnimationPath;

  @override
  void initState() {
    super.initState();

    // Setup fade animation
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400), // Faster fade in
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut));
    _fadeController.forward();

    _loadRiveAnimation();
  }

  @override
  void didUpdateWidget(RiveAnimationFullscreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If animation path changed, reload the animation
    if (widget.animationPath != oldWidget.animationPath) {
      // Reset state
      setState(() {
        _isLoaded = false;
        _riveArtboard = null;
        _controller?.dispose();
        _controller = null;
      });

      // Reload with new animation
      _loadRiveAnimation();

      // Reset and restart fade animation
      _fadeController.reset();
      _fadeController.forward();
    }
  }

  void _loadRiveAnimation() async {
    _currentAnimationPath = widget.animationPath;
    final loadingPath = _currentAnimationPath;

    try {
      // Load the Rive file
      final data = await rootBundle.load(widget.animationPath);

      // Check if widget was disposed or animation path changed during loading
      if (!mounted || loadingPath != _currentAnimationPath) {
        return;
      }

      final file = rive.RiveFile.import(data);

      // Get available artboards for debugging

      for (final artboard in file.artboards) {}

      // Setup the artboard - use the main artboard
      final artboard = file.mainArtboard;

      // Setup Rive artboard with state machine if available
      var controller = rive.StateMachineController.fromArtboard(
        artboard,
        'State Machine 1', // Try standard state machine name
      );

      if (controller != null) {
        artboard.addController(controller);
        _controller = controller;
      } else {
        // If no state machine, try to play a simple animation if available
        if (artboard.animations.isNotEmpty) {
          artboard.addController(
              rive.SimpleAnimation(artboard.animations.first.name));
        }
      }

      if (mounted && loadingPath == _currentAnimationPath) {
        setState(() {
          _riveArtboard = artboard;
          _isLoaded = true;
        });
      }
    } catch (error) {
      // Prevent state update if widget was disposed during loading
      if (mounted && loadingPath == _currentAnimationPath) {
        setState(() {
          _isLoaded = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        color: Colors.white,
        width: double.infinity,
        height: double.infinity,
        child: _isLoaded && _riveArtboard != null
            ? rive.Rive(
                artboard: _riveArtboard!,
                fit: BoxFit.contain,
              )
            : const Center(
                child: CircularProgressIndicator(),
              ),
      ),
    );
  }
}

// Create a new animation controller class that holds all animations
class AnimationSequenceController extends StatefulWidget {
  const AnimationSequenceController({super.key});

  @override
  _AnimationSequenceControllerState createState() =>
      _AnimationSequenceControllerState();
}

class _AnimationSequenceControllerState
    extends State<AnimationSequenceController>
    with SingleTickerProviderStateMixin {
  // Keep track of which animation is currently showing
  String _currentAnimation = 'transcribe';
  String _previousAnimation = ''; // Track previous animation for crossfade

  // Store loaded Rive artboards for each animation
  rive.Artboard? _transcribeArtboard;
  rive.Artboard? _understandArtboard;
  rive.Artboard? _extractArtboard;

  // Track loading state for each animation
  bool _transcribeLoaded = false;
  bool _understandLoaded = false;
  bool _extractLoaded = false;

  // Controllers for the animations
  rive.StateMachineController? _transcribeController;
  rive.StateMachineController? _understandController;
  rive.StateMachineController? _extractController;

  // For cross-fade animations
  AnimationController? _fadeController;
  Animation<double>? _fadeInAnimation;
  Animation<double>? _fadeOutAnimation;
  double _currentOpacity = 1.0;
  double _previousOpacity = 0.0;

  @override
  void initState() {
    super.initState();
    // Set up fade controller
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _fadeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController!,
        curve: const Interval(0.0, 1.0, curve: Curves.easeInOut),
      ),
    );

    _fadeOutAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _fadeController!,
        curve: const Interval(0.0, 0.7, curve: Curves.easeInOut),
      ),
    );

    _fadeController!.addListener(() {
      if (mounted) {
        setState(() {
          _currentOpacity = _fadeInAnimation!.value;
          _previousOpacity = _fadeOutAnimation!.value;
        });
      }
    });

    // Load all animations at startup
    _loadAllAnimations();
  }

  void _loadAllAnimations() async {
    await _loadRiveAnimation('transcribe', 'assets/animations/transcribe.riv');
    await _loadRiveAnimation('understand', 'assets/animations/understand.riv');
    await _loadRiveAnimation('extract', 'assets/animations/extract.riv');
  }

  Future<void> _loadRiveAnimation(String name, String path) async {
    try {
      // Load the file data
      final data = await rootBundle.load(path);
      final file = rive.RiveFile.import(data);

      // Get the main artboard
      final artboard = file.mainArtboard;

      // Setup state machine if available
      rive.StateMachineController? controller =
          rive.StateMachineController.fromArtboard(artboard, 'State Machine 1');

      if (controller != null) {
        artboard.addController(controller);
      } else if (artboard.animations.isNotEmpty) {
        artboard.addController(
            rive.SimpleAnimation(artboard.animations.first.name));
      }

      // Update the state for the specific animation
      if (mounted) {
        setState(() {
          if (name == 'transcribe') {
            _transcribeArtboard = artboard;
            _transcribeController = controller;
            _transcribeLoaded = true;
          } else if (name == 'understand') {
            _understandArtboard = artboard;
            _understandController = controller;
            _understandLoaded = true;
          } else if (name == 'extract') {
            _extractArtboard = artboard;
            _extractController = controller;
            _extractLoaded = true;
          }
        });
      }

      // ignore: empty_catches
    } catch (e) {}
  }

  // Change which animation is currently showing
  void showAnimation(String animationName) {
    if (_currentAnimation != animationName) {
      _fadeController!.reset();

      setState(() {
        _previousAnimation = _currentAnimation;
        _currentAnimation = animationName;
      });

      _fadeController!.forward();
    }
  }

  @override
  void dispose() {
    // Clean up all controllers
    _fadeController?.dispose();
    _transcribeController?.dispose();
    _understandController?.dispose();
    _extractController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Current animation widget
    Widget? currentAnimationWidget;
    if (_currentAnimation == 'transcribe' &&
        _transcribeLoaded &&
        _transcribeArtboard != null) {
      currentAnimationWidget = Opacity(
        opacity: _currentOpacity,
        child: rive.Rive(
          artboard: _transcribeArtboard!,
          fit: BoxFit.contain,
        ),
      );
    } else if (_currentAnimation == 'understand' &&
        _understandLoaded &&
        _understandArtboard != null) {
      currentAnimationWidget = Opacity(
        opacity: _currentOpacity,
        child: rive.Rive(
          artboard: _understandArtboard!,
          fit: BoxFit.contain,
        ),
      );
    } else if (_currentAnimation == 'extract' &&
        _extractLoaded &&
        _extractArtboard != null) {
      currentAnimationWidget = Opacity(
        opacity: _currentOpacity,
        child: rive.Rive(
          artboard: _extractArtboard!,
          fit: BoxFit.contain,
        ),
      );
    }

    // Previous animation widget (for crossfade)
    Widget? previousAnimationWidget;
    if (_previousAnimation == 'transcribe' &&
        _transcribeLoaded &&
        _transcribeArtboard != null) {
      previousAnimationWidget = Opacity(
        opacity: _previousOpacity,
        child: rive.Rive(
          artboard: _transcribeArtboard!,
          fit: BoxFit.contain,
        ),
      );
    } else if (_previousAnimation == 'understand' &&
        _understandLoaded &&
        _understandArtboard != null) {
      previousAnimationWidget = Opacity(
        opacity: _previousOpacity,
        child: rive.Rive(
          artboard: _understandArtboard!,
          fit: BoxFit.contain,
        ),
      );
    } else if (_previousAnimation == 'extract' &&
        _extractLoaded &&
        _extractArtboard != null) {
      previousAnimationWidget = Opacity(
        opacity: _previousOpacity,
        child: rive.Rive(
          artboard: _extractArtboard!,
          fit: BoxFit.contain,
        ),
      );
    }

    // Return the container with crossfading animations
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.white,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (previousAnimationWidget != null)
            Positioned.fill(
              child: previousAnimationWidget,
            ),
          if (currentAnimationWidget != null)
            Positioned.fill(
              child: currentAnimationWidget,
            ),
          if (currentAnimationWidget == null && previousAnimationWidget == null)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
