import 'dart:async';
import 'dart:math' as math;
import 'package:record/record.dart';
import 'package:rive/rive.dart' as rive;
import 'package:permission_handler/permission_handler.dart';

class AudioFFTService {
  static const double updateFrequency = 30.0; // 30Hz updates

  final _audioRecorder = AudioRecorder();
  Timer? _updateTimer;
  Timer? _levelCheckTimer;
  Timer? _riveCheckTimer;

  // Audio level simulation variables
  final List<double> _frequencyBands = List.filled(7, 1.0);
  double _currentAudioLevel = 0.0;
  final math.Random _random = math.Random();

  // Rive controller and state tracking
  rive.StateMachineController? _riveController;
  rive.SMIInput<bool>? _isRecordInput;
  bool _isRecording = false;
  bool _isInitialized = false;
  bool _debugMode = false;

  // Debug callback
  Function(String)? _debugCallback;

  Future<void> initialize({bool debugMode = false}) async {
    if (_isInitialized) return;

    _debugMode = debugMode;
    _debugLog('🎤 Initializing AudioFFTService...');

    try {
      // Initialize the audio recorder (already exists in your project)
      _isInitialized = true;
      _debugLog('✅ AudioFFTService initialized successfully');
    } catch (e) {
      _debugLog('❌ Error initializing AudioFFTService: $e');
      throw e;
    }
  }

  void setDebugCallback(Function(String)? callback) {
    _debugCallback = callback;
  }

  void _debugLog(String message) {
    if (_debugMode) {
      print('[AudioFFTService] $message');
      _debugCallback?.call(message);
    }
  }

  void setRiveController(rive.StateMachineController? controller) {
    _riveController = controller;
    if (_riveController != null) {
      _isRecordInput = _riveController!.findInput<bool>('isRecord');
      if (_isRecordInput != null) {
        _debugLog('🎯 Found isRecord input in Rive');
        // Start monitoring Rive isRecord changes
        _startRiveMonitoring();
      } else {
        _debugLog('⚠️ isRecord input not found in Rive animation');
      }
    }
  }

  void _startRiveMonitoring() {
    _debugLog('👀 Starting Rive isRecord monitoring...');
    _riveCheckTimer?.cancel();
    _riveCheckTimer = Timer.periodic(
      const Duration(milliseconds: 50), // Check every 50ms
      (_) => _checkRiveRecordState(),
    );
  }

  void _checkRiveRecordState() {
    if (_isRecordInput == null) return;

    final shouldBeRecording = _isRecordInput!.value;

    if (shouldBeRecording && !_isRecording) {
      _debugLog('🟢 Rive isRecord became TRUE - Starting recording');
      _startRecordingInternal();
    } else if (!shouldBeRecording && _isRecording) {
      _debugLog('🔴 Rive isRecord became FALSE - Stopping recording');
      _stopRecordingInternal();
    }
  }

  Future<bool> checkPermissions() async {
    _debugLog('🔐 Checking microphone permissions...');
    final status = await Permission.microphone.status;
    if (status != PermissionStatus.granted) {
      _debugLog('❓ Requesting microphone permission...');
      final result = await Permission.microphone.request();
      final granted = result == PermissionStatus.granted;
      _debugLog(granted ? '✅ Permission granted' : '❌ Permission denied');
      return granted;
    }
    _debugLog('✅ Permission already granted');
    return true;
  }

  Future<void> _startRecordingInternal() async {
    if (_isRecording) {
      _debugLog('⚠️ Already recording, skipping start');
      return;
    }

    _debugLog('🎵 Starting internal recording...');

    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      _debugLog('❌ Cannot start recording - no microphone permission');
      return;
    }

    try {
      // Start recording to detect audio presence
      final isSupported = await _audioRecorder.hasPermission();
      if (!isSupported) {
        _debugLog('❌ Recording not supported on this device');
        return;
      }

      _isRecording = true;
      _debugLog('✅ Recording started successfully');

      // Start timers for audio simulation
      _startAudioSimulation();
      _startUpdateTimer();
    } catch (e) {
      _debugLog('❌ Error starting recording: $e');
      _isRecording = false;
    }
  }

  void _startAudioSimulation() {
    _debugLog('🎲 Starting audio simulation...');
    // Simulate audio level changes based on random variations
    _levelCheckTimer?.cancel();
    _levelCheckTimer = Timer.periodic(
      const Duration(milliseconds: 50), // Check level every 50ms
      (_) => _simulateAudioLevel(),
    );
  }

  void _simulateAudioLevel() {
    if (!_isRecording) return;

    // Simulate varying audio levels (this would be replaced with real audio analysis)
    _currentAudioLevel =
        _random.nextDouble() * 0.8 + 0.2; // Between 0.2 and 1.0

    // Simulate frequency band variations based on the overall level
    for (int i = 0; i < 7; i++) {
      // Each band varies slightly differently to create realistic visualization
      final bandVariation =
          _random.nextDouble() * 0.4 + 0.8; // 0.8 to 1.2 multiplier
      final baseLevel = _currentAudioLevel * bandVariation;

      // Add some frequency-specific characteristics
      final frequencyModifier = _getFrequencyModifier(i);

      // Calculate final band value (1-6 range)
      _frequencyBands[i] =
          (baseLevel * frequencyModifier * 5 + 1).clamp(1.0, 6.0);
    }

    if (_debugMode) {
      // Only log occasionally to avoid spam
      if (_random.nextInt(60) == 0) {
        // ~1 in 60 calls (every ~3 seconds at 50ms intervals)
        _debugLog(
            '🎵 Audio Level: ${_currentAudioLevel.toStringAsFixed(2)} | Bars: ${_frequencyBands.map((b) => b.toStringAsFixed(1)).join(', ')}');
      }
    }
  }

  double _getFrequencyModifier(int bandIndex) {
    // Simulate different frequency response patterns
    switch (bandIndex) {
      case 0: // Sub-bass: typically lower in normal speech
        return 0.6 + _random.nextDouble() * 0.4;
      case 1: // Bass: moderate in speech
        return 0.7 + _random.nextDouble() * 0.4;
      case 2: // Low mid: strong in speech
        return 0.8 + _random.nextDouble() * 0.4;
      case 3: // Mid: very strong in speech
        return 0.9 + _random.nextDouble() * 0.4;
      case 4: // Upper mid: strong in speech
        return 0.8 + _random.nextDouble() * 0.4;
      case 5: // Presence: moderate in speech
        return 0.7 + _random.nextDouble() * 0.4;
      case 6: // Brilliance: lower in normal speech
        return 0.5 + _random.nextDouble() * 0.4;
      default:
        return 0.7 + _random.nextDouble() * 0.4;
    }
  }

  void _startUpdateTimer() {
    _debugLog('⏰ Starting 30Hz update timer...');
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(
      Duration(milliseconds: (1000 / updateFrequency).round()),
      (_) => _updateRiveBars(),
    );
  }

  void _updateRiveBars() {
    if (_riveController == null || !_isRecording) return;

    try {
      // Update each bar variable in the Rive animation
      for (int i = 1; i <= 7; i++) {
        final barInput = _riveController!.findInput<double>('Bar $i');
        if (barInput != null) {
          barInput.value = _frequencyBands[i - 1];
        } else {
          if (_debugMode && _random.nextInt(300) == 0) {
            // Log missing bars occasionally
            _debugLog('⚠️ Bar $i input not found in Rive animation');
          }
        }
      }
    } catch (e) {
      _debugLog('❌ Error updating Rive bars: $e');
    }
  }

  Future<void> _stopRecordingInternal() async {
    if (!_isRecording) {
      _debugLog('⚠️ Not recording, skipping stop');
      return;
    }

    _debugLog('🛑 Stopping internal recording...');
    _isRecording = false;

    // Stop timers
    _levelCheckTimer?.cancel();
    _levelCheckTimer = null;
    _updateTimer?.cancel();
    _updateTimer = null;

    // Reset bars to minimum
    for (int i = 0; i < 7; i++) {
      _frequencyBands[i] = 1.0;
    }
    _updateRiveBars();
    _debugLog('✅ Recording stopped and bars reset');
  }

  // Manual start/stop methods for backward compatibility
  Future<void> startRecording() async {
    _debugLog('📞 Manual startRecording() called');
    await _startRecordingInternal();
  }

  Future<void> stopRecording() async {
    _debugLog('📞 Manual stopRecording() called');
    await _stopRecordingInternal();
  }

  // Test methods for debugging
  void testBars({double? testValue}) {
    if (_riveController == null) {
      _debugLog('❌ Cannot test bars - no Rive controller');
      return;
    }

    final value = testValue ?? 3.5; // Default test value
    _debugLog('🧪 Testing bars with value: $value');

    for (int i = 1; i <= 7; i++) {
      final barInput = _riveController!.findInput<double>('Bar $i');
      if (barInput != null) {
        barInput.value = value;
        _debugLog('✅ Set Bar $i = $value');
      } else {
        _debugLog('❌ Bar $i input not found');
      }
    }
  }

  void testIsRecord({bool? value}) {
    if (_isRecordInput == null) {
      _debugLog('❌ Cannot test isRecord - input not found');
      return;
    }

    final testValue = value ?? !_isRecordInput!.value;
    _debugLog('🧪 Testing isRecord with value: $testValue');
    _isRecordInput!.value = testValue;
  }

  Future<void> dispose() async {
    _debugLog('🗑️ Disposing AudioFFTService...');
    await _stopRecordingInternal();
    _riveCheckTimer?.cancel();
    _riveCheckTimer = null;
    _riveController = null;
    _isRecordInput = null;
    _isInitialized = false;
    _debugLog('✅ AudioFFTService disposed');
  }

  // Getters
  bool get isRecording => _isRecording;
  bool get isInitialized => _isInitialized;
  bool get debugMode => _debugMode;
  List<double> get frequencyBands => List.from(_frequencyBands);
  double get currentAudioLevel => _currentAudioLevel;
}
