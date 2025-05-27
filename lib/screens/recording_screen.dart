import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:rive/rive.dart' as rive;
import 'package:flutter/services.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  _RecordingScreenState createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen>
    with SingleTickerProviderStateMixin {
  final _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _isPaused = false;
  String? _recordedFilePath;

  // For recording duration
  int _recordingDuration = 0; // in seconds
  Timer? _timer;

  // Rive animation controllers
  rive.StateMachineController? _controller;
  rive.SMIInput<bool>? _clickInput;
  rive.SMIInput<bool>? _isPauseInput; // Store in class field

  // For the Rive animation widget
  rive.Artboard? _riveArtboard;
  bool _riveLoaded = false;

  // Add a new state to handle seamless transitions to the animation sequence
  bool _isSubmitting = false;
  rive.Artboard? _transcribeArtboard;
  bool _transcribeLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadRiveAnimation();
    // Preload the transcribe animation for seamless transition
    _preloadTranscribeAnimation();
  }

  // Preload the transcribe animation for seamless transitions
  void _preloadTranscribeAnimation() async {
    try {
      final data = await rootBundle.load('assets/animations/transcribe.riv');
      final file = rive.RiveFile.import(data);
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

      setState(() {
        _transcribeArtboard = artboard;
        _transcribeLoaded = true;
      });
    } catch (e) {}
  }

  void _loadRiveAnimation() async {
    try {
      // Make sure Rive is initialized
      await rive.RiveFile.initialize();

      // Load the Rive file
      final data = await rootBundle.load('assets/animations/record.riv');

      final file = rive.RiveFile.import(data);

      // Get available artboards for debugging

      for (final artboard in file.artboards) {}

      // Setup the artboard - use the main artboard named "Artboard"
      final artboard = file.mainArtboard;

      // Setup Rive artboard with callback
      var controller = rive.StateMachineController.fromArtboard(
        artboard,
        'State Machine 1', // Your state machine name
      );

      if (controller != null) {
        // Set up controller listener before adding it to the artboard
        controller.addEventListener((event) {
          // Check if Click input is triggered in the state machine
          // Re-get the input value each time to ensure we have the latest value
          rive.SMIInput<bool>? clickInput = controller.findInput<bool>('Click');
          if (clickInput != null && clickInput.value && !_isRecording) {
            // Start recording in the next frame to avoid build issues
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_isRecording) {
                // Ensure isPause is false when starting
                if (_isPauseInput != null) {
                  _isPauseInput!.value = false;
                }
                _startRecordingAudio();
              }
            });
          }
        });

        // Add controller to artboard
        artboard.addController(controller);

        // Find inputs
        _clickInput = controller.findInput<bool>('Click');
        _isPauseInput =
            controller.findInput<bool>('isPause'); // Store in class field
        var isRecordingInput = controller.findInput<bool>('IsRecording');

        _controller = controller;
      } else {}

      setState(() {
        _riveArtboard = artboard;
        _riveLoaded = true;
      });
    } catch (error) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  // Start recording function
  Future<void> _startRecordingAudio() async {
    try {
      // Permissions are already checked before calling this method in the GestureDetector's onTapDown

      // Get temporary directory for saving the recording
      final directory = await getTemporaryDirectory();
      _recordedFilePath =
          '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // Start recording
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _recordedFilePath!,
      );

      setState(() {
        _isRecording = true;
        _isPaused = false;
        _recordingDuration = 0;
      });

      // We don't need to trigger the animation manually here
      // since it should already be triggered by the GestureDetector

      // Start timer for duration
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_isRecording && !_isPaused) {
          setState(() {
            _recordingDuration++;
          });
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Recording error: ${e.toString()}'),
          duration: const Duration(seconds: 5),
          backgroundColor: Colors.red,
        ),
      );
      // Reset animation state if recording fails
      if (_clickInput != null) {
        _clickInput!.value = false;
      }
    }
  }

  // Pause/Resume recording
  Future<void> _pauseResumeRecording() async {
    if (!_isRecording) return;

    try {
      if (_isPaused) {
        // Currently paused, so we are resuming
        await _audioRecorder.resume();

        // Update Rive animation state - resuming
        if (_isPauseInput != null) {
          _isPauseInput!.value =
              false; // Set isPause to false to resume animation
        }
      } else {
        // Currently recording, so we are pausing
        await _audioRecorder.pause();

        // Update Rive animation state - pausing
        if (_isPauseInput != null) {
          _isPauseInput!.value = true; // Set isPause to true to pause animation
        }
      }

      // This setState call should be outside the try-catch or at least not cause issues if input is null.
      // It's primarily for updating the UI based on _isPaused.
      setState(() {
        _isPaused = !_isPaused; // Toggle the pause state for UI updates
      });
    } catch (e) {
      // Avoid calling setState here if the context might be invalid due to an error.
      // Show SnackBar for user feedback.
      if (mounted) {
        // Check if the widget is still in the tree
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error pausing/resuming recording: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Stop recording and discard
  Future<void> _stopRecording({bool submit = false}) async {
    if (!_isRecording) return;

    try {
      final path = await _audioRecorder.stop();

      // Reset Rive animation state
      if (_clickInput != null) {
        _clickInput!.value = false; // Reset Click input
      }
      if (_isPauseInput != null) {
        _isPauseInput!.value = false; // Ensure isPause is set to false
      }

      setState(() {
        _isRecording = false;
        _isPaused = false;
      });

      _timer?.cancel();

      if (submit && path != null) {
        // First show the transcribe animation directly in this screen
        setState(() {
          _isSubmitting = true;
        });

        // Wait a brief moment to ensure animation starts
        await Future.delayed(const Duration(milliseconds: 100));

        // Then return result to previous screen to continue the animation sequence
        Navigator.pop(context, {
          'success': true,
          'filePath': path,
          'preStartAnimation': true, // Signal that animation is already started
        });
      } else {
        // Just close the recording page without processing
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error stopping recording: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // Format duration as MM:SS
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  // Check permissions (reusing the method from MainScreen)
  Future<bool> _checkPermissions() async {
    final micStatus = await Permission.microphone.status;

    if (micStatus.isGranted) return true;

    final newMicStatus = await Permission.microphone.request();
    return newMicStatus.isGranted;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            // Show transcribe animation when submitting
            if (_isSubmitting &&
                _transcribeLoaded &&
                _transcribeArtboard != null)
              Positioned.fill(
                child: rive.Rive(
                  artboard: _transcribeArtboard!,
                  fit: BoxFit.contain,
                ),
              )
            // Rive animation - centered and enlarged to full width
            else if (_riveLoaded && _riveArtboard != null)
              Align(
                alignment:
                    const Alignment(0, -0.75), // Moves it up 20% from center
                child: SizedBox(
                  width: screenWidth, // Use full screen width
                  height: screenWidth, // Same height for aspect ratio
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Original artboard dimensions
                      const originalWidth = 500.0;
                      const originalHeight = 684.0;

                      // Original touch area properties
                      const touchAreaCenterX = 250.0;
                      const touchAreaCenterY = 334.0;
                      const touchAreaSize = 235.0;

                      // Calculate scale factors for width and height
                      final containerWidth = constraints.maxWidth;
                      final containerHeight = constraints.maxHeight;

                      // Calculate how the animation is actually scaled with BoxFit.cover
                      double scaleX = containerWidth / originalWidth;
                      double scaleY = containerHeight / originalHeight;

                      // For BoxFit.cover, we use the larger scale factor
                      final scale = scaleX > scaleY ? scaleX : scaleY;

                      // Calculate the actual size of the Rive animation
                      final actualWidth = originalWidth * scale;
                      final actualHeight = originalHeight * scale;

                      // Calculate position offsets if animation is centered
                      final offsetX = (containerWidth - actualWidth) / 2;
                      final offsetY = (containerHeight - actualHeight) / 2;

                      // Calculate the scaled touch area position and size
                      final scaledTouchAreaCenterX =
                          touchAreaCenterX * scale + offsetX;
                      final scaledTouchAreaCenterY =
                          touchAreaCenterY * scale + offsetY;
                      final scaledTouchAreaSize = touchAreaSize * scale;

                      // Calculate the top-left position for Positioned widget
                      final touchAreaLeft =
                          scaledTouchAreaCenterX - scaledTouchAreaSize / 2;
                      final touchAreaTop =
                          scaledTouchAreaCenterY - scaledTouchAreaSize / 2;

                      return Stack(
                        children: [
                          // The Rive animation
                          rive.Rive(
                            artboard: _riveArtboard!,
                            antialiasing: true,
                            useArtboardSize: false,
                            fit: BoxFit
                                .cover, // Keep your current BoxFit setting
                          ),

                          // GestureDetector precisely positioned over the touch area
                          Positioned(
                            left: touchAreaLeft,
                            top: touchAreaTop,
                            width: scaledTouchAreaSize,
                            height: scaledTouchAreaSize,
                            child: GestureDetector(
                              onTapDown: (_) async {
                                if (!_isRecording) {
                                  // Check permissions first before starting animation or recording
                                  final permissionsGranted =
                                      await _checkPermissions();
                                  if (!permissionsGranted) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'Cannot start recording - permissions required'),
                                          duration: Duration(seconds: 3),
                                        ),
                                      );
                                    }
                                    return;
                                  }

                                  // Only trigger animation and recording after permissions granted
                                  if (_clickInput != null) {
                                    _clickInput!.value = true;
                                  }

                                  // Ensure isPause is false
                                  if (_isPauseInput != null) {
                                    _isPauseInput!.value = false;
                                  }

                                  // Start recording now that permissions are confirmed
                                  _startRecordingAudio();
                                }
                              },
                              child: Container(
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.transparent,
                                  // Uncomment below for debugging to see touch area
                                  // border: Border.all(color: Colors.red.withOpacity(0.3), width: 2),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(),
              ),

            // Content overlay - hide when submitting
            if (!_isSubmitting)
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Close button
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          if (_isRecording) {
                            _stopRecording(submit: false);
                          } else {
                            Navigator.pop(context);
                          }
                        },
                      ),
                    ),

                    const Spacer(),

                    // REC indicator with pulsing dot
                    if (_isRecording)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Pulsing red dot (stops when paused)
                            PulsingDot(isPaused: _isPaused),
                            const SizedBox(width: 6),
                            // REC text
                            const Text(
                              "REC",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500, // Medium
                                fontFamily: 'GeistMono',
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Recording duration
                    if (_isRecording)
                      Text(
                        _formatDuration(_recordingDuration),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'GeistMono',
                          color: Colors.black,
                        ),
                      ),

                    // Instruction text - not tappable anymore
                    if (!_isRecording)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 170.0),
                        child: IgnorePointer(
                          ignoring: true, // Allow taps to pass through
                          child: Text(
                            'click to start recording',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Geist',
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),

                    const SizedBox(height: 30),

                    // Control buttons with SVG icons
                    if (_isRecording)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Pause/Play button
                          GestureDetector(
                            onTap: _pauseResumeRecording,
                            child: Container(
                              width: 64,
                              height: 64,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              clipBehavior: Clip.antiAlias,
                              decoration: ShapeDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment(-0.00, -0.00),
                                  end: Alignment(1.00, 1.00),
                                  colors: [
                                    Color.fromARGB(255, 197, 197, 197),
                                    Color.fromARGB(255, 157, 157, 157)
                                  ],
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(120),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SvgPicture.asset(
                                    _isPaused
                                        ? 'assets/icons/play.svg'
                                        : 'assets/icons/pause.svg',
                                    width: 32,
                                    height: 32,
                                    colorFilter: const ColorFilter.mode(
                                        Colors.white, BlendMode.srcIn),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(width: 24),

                          // Stop button
                          GestureDetector(
                            onTap: () => _stopRecording(submit: false),
                            child: Container(
                              width: 64,
                              height: 64,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              clipBehavior: Clip.antiAlias,
                              decoration: ShapeDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment(-0.00, -0.00),
                                  end: Alignment(1.00, 1.00),
                                  colors: [
                                    Color.fromARGB(255, 197, 197, 197),
                                    Color.fromARGB(255, 157, 157, 157)
                                  ],
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(120),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SvgPicture.asset(
                                    'assets/icons/stop.svg',
                                    width: 32,
                                    height: 32,
                                    colorFilter: const ColorFilter.mode(
                                        Colors.white, BlendMode.srcIn),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(width: 24),

                          // Submit button
                          GestureDetector(
                            onTap: () => _stopRecording(submit: true),
                            child: Container(
                              width: 64,
                              height: 64,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              clipBehavior: Clip.antiAlias,
                              decoration: ShapeDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment(-0.00, -0.00),
                                  end: Alignment(1.00, 1.00),
                                  colors: [
                                    Color(0xFF588EFF),
                                    Color(0xFF1D44FF)
                                  ],
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(120),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SvgPicture.asset(
                                    'assets/icons/submit.svg',
                                    width: 32,
                                    height: 32,
                                    colorFilter: const ColorFilter.mode(
                                        Colors.white, BlendMode.srcIn),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                    // Add spacing to position buttons 200px from bottom
                    const SizedBox(height: 200),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// PulsingDot widget for the recording indicator
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key, this.isPaused = false});

  @override
  State<PulsingDot> createState() => _PulsingDotState();

  final bool isPaused;
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _opacityAnimation =
        Tween<double>(begin: 1.0, end: 0.4).animate(_animationController);

    // Initialize with correct state
    if (widget.isPaused) {
      _animationController.stop();
    }
  }

  @override
  void didUpdateWidget(PulsingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pause or resume animation based on isPaused state
    if (widget.isPaused && _animationController.isAnimating) {
      _animationController.stop();
    } else if (!widget.isPaused && !_animationController.isAnimating) {
      _animationController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(_opacityAnimation.value),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
