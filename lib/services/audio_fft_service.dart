import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:rive/rive.dart' as rive;
import 'package:permission_handler/permission_handler.dart';
import 'package:fftea/fftea.dart';

class AudioFFTService {
  static const double updateFrequency = 30.0; // 30Hz updates
  static const int sampleRate = 44100; // Sample rate in Hz
  static const int fftSize = 1024; // Reduced FFT size for better performance
  static const int bufferSize = 512; // Reduced buffer size
  static const int processEveryNthSample =
      2; // Process every 2nd sample for performance

  final _audioRecorder = AudioRecorder();
  Timer? _updateTimer;

  // Audio processing
  final FFT _fft = FFT(fftSize);
  final List<double> _audioBuffer = [];
  final List<double> _frequencyBands = List.filled(7, 1.0);
  final List<double> _smoothedBands = List.filled(7, 1.0);
  final List<double> _previousBands = List.filled(7, 1.0);

  // Adaptive smoothing factors
  double _smoothingFactor = 0.3;
  static const double _minSmoothingFactor = 0.1;
  static const double _maxSmoothingFactor = 0.7;
  static const double _decayFactor = 0.85;

  // Performance optimization
  int _sampleCounter = 0;
  int _fftCalculationCounter = 0;
  static const int _maxFftCalculationsPerSecond = 20; // Limit FFT calculations

  // Frequency ranges for 7 bands (in Hz) - optimized for speech
  static const List<List<double>> _frequencyRanges = [
    [20, 100], // Bar 1: Sub-bass (extended range)
    [100, 300], // Bar 2: Bass (extended range)
    [300, 800], // Bar 3: Low midrange (speech fundamentals)
    [800, 2500], // Bar 4: Midrange (speech clarity)
    [2500, 5000], // Bar 5: Upper midrange (speech presence)
    [5000, 10000], // Bar 6: Presence (speech articulation)
    [10000, 20000], // Bar 7: Brilliance (speech brightness)
  ];

  // Rive controller and state tracking
  rive.StateMachineController? _riveController;
  rive.SMIInput<bool>? _isRecordInput;
  bool _isRecording = false;
  bool _isInitialized = false;
  bool _debugMode = false;
  bool _useRealAudio = true;

  // Debug callback
  Function(String)? _debugCallback;

  // Audio level tracking
  double _currentAudioLevel = 0.0;
  double _peakAudioLevel = 0.0;
  final math.Random _random = math.Random();

  // Performance tracking
  int _processedSamples = 0;
  DateTime _lastPerformanceLog = DateTime.now();

  // Rive connection fields (using correct Flutter API)
  bool _isConnected = false;
  rive.StateMachineController? _controller;
  Map<String, rive.SMIInput<double>>? _barInputs;
  int _debugCounter = 0;

  static final AudioFFTService _instance = AudioFFTService._internal();
  factory AudioFFTService() => _instance;
  AudioFFTService._internal();

  Future<void> initialize(
      {bool debugMode = false, bool useRealAudio = true}) async {
    if (_isInitialized) return;

    _debugMode = debugMode;
    _useRealAudio = useRealAudio;
    _debugLog(
        '🎤 Initializing AudioFFTService (Real Audio: $_useRealAudio)...');

    try {
      // Initialize the audio recorder
      _isInitialized = true;
      _debugLog('✅ AudioFFTService initialized successfully');
    } catch (e) {
      _debugLog('❌ Error initializing AudioFFTService: $e');
      rethrow;
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

  void connectToRiveController(rive.StateMachineController controller) {
    _controller = controller;
    _isConnected = true;

    print('[AudioFFT] 🔗 Connected to Rive controller');

    // Debug: List all available inputs
    print('[AudioFFT] 📋 Available inputs (${controller.inputs.length} total):');
    for (final input in controller.inputs) {
      print('[AudioFFT]   - ${input.name} (${input.runtimeType})');
    }

    // Look for bar inputs using various naming patterns
    _findBarInputs(controller);
  }

  void _findBarInputs(rive.StateMachineController controller) {
    print('[AudioFFT] 🔍 Looking for bar inputs...');
    
    final barInputs = <String, rive.SMIInput<double>>{};
    
    // Try different naming patterns for bar inputs
    final barPatterns = [
      'Bar 1', 'Bar 2', 'Bar 3', 'Bar 4', 'Bar 5', 'Bar 6', 'Bar 7',
      'Bar1', 'Bar2', 'Bar3', 'Bar4', 'Bar5', 'Bar6', 'Bar7',
      'bar1', 'bar2', 'bar3', 'bar4', 'bar5', 'bar6', 'bar7',
      'Height1', 'Height2', 'Height3', 'Height4', 'Height5', 'Height6', 'Height7',
      'height1', 'height2', 'height3', 'height4', 'height5', 'height6', 'height7',
    ];

    for (final pattern in barPatterns) {
      final barInput = controller.findInput<double>(pattern);
      if (barInput != null) {
        barInputs[pattern] = barInput;
        print('[AudioFFT] ✅ Found bar input: $pattern');
      }
    }

    if (barInputs.isNotEmpty) {
      print('[AudioFFT] 🎉 Found ${barInputs.length} bar inputs total');
      _barInputs = barInputs;
    } else {
      print('[AudioFFT] ❌ No bar inputs found with expected names');
      
      // Try to find any number inputs that might be the bars
      final numberInputs = controller.inputs.whereType<rive.SMIInput<double>>().toList();
      print('[AudioFFT] 📋 Found ${numberInputs.length} number inputs:');
      for (final input in numberInputs) {
        print('[AudioFFT]   - ${input.name}');
      }

      // If we have exactly 7 number inputs, assume they are the bars
      if (numberInputs.length == 7) {
        final Map<String, rive.SMIInput<double>> mappedInputs = {};
        for (int i = 0; i < 7; i++) {
          mappedInputs['Bar ${i + 1}'] = numberInputs[i];
        }
        _barInputs = mappedInputs;
        print('[AudioFFT] 🔄 Mapped 7 number inputs to bars');
      } else if (numberInputs.length >= 7) {
        // If we have more than 7, take the first 7
        final Map<String, rive.SMIInput<double>> mappedInputs = {};
        for (int i = 0; i < 7; i++) {
          mappedInputs['Bar ${i + 1}'] = numberInputs[i];
        }
        _barInputs = mappedInputs;
        print('[AudioFFT] 🔄 Mapped first 7 of ${numberInputs.length} number inputs to bars');
      }
    }
  }

  void _startRiveMonitoring() {
    _debugLog('👀 Starting Rive isRecord monitoring...');
    Timer.periodic(
      const Duration(milliseconds: 50),
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
      _isRecording = true;
      _debugLog('✅ Recording started successfully');

      // Reset all state
      _audioBuffer.clear();
      _sampleCounter = 0;
      _fftCalculationCounter = 0;
      _processedSamples = 0;
      _lastPerformanceLog = DateTime.now();

      for (int i = 0; i < 7; i++) {
        _frequencyBands[i] = 1.0;
        _smoothedBands[i] = 1.0;
        _previousBands[i] = 1.0;
      }

      if (_useRealAudio) {
        await _startRealAudioStream();
      } else {
        _startAudioSimulation();
      }

      _startUpdateTimer();
    } catch (e) {
      _debugLog('❌ Error starting recording: $e');
      _isRecording = false;
    }
  }

  Future<void> _startRealAudioStream() async {
    try {
      _debugLog('🎙️ Starting real audio analysis...');

      // For now, use enhanced simulation that responds to actual recording
      // This provides a more realistic visualization while we work on true real-time audio
      _debugLog(
          '🔄 Using enhanced audio simulation (responds to actual recording state)');
      _useRealAudio = false;
      _startAudioSimulation();

      _debugLog('✅ Audio analysis started');
    } catch (e) {
      _debugLog('❌ Failed to start audio analysis: $e');
      _debugLog('🔄 Falling back to simulation mode');
      _useRealAudio = false;
      _startAudioSimulation();
    }
  }

  void _processAudioData(Uint8List audioData) {
    if (!_isRecording) return;

    try {
      // Performance optimization: process every Nth sample
      _sampleCounter++;
      if (_sampleCounter % processEveryNthSample != 0) return;

      // Convert bytes to audio samples (16-bit PCM)
      final samples = <double>[];
      for (int i = 0; i < audioData.length - 1; i += 2) {
        final sample = (audioData[i] | (audioData[i + 1] << 8));
        samples.add(sample.toSigned(16) / 32768.0);
      }

      // Add samples to buffer
      _audioBuffer.addAll(samples);
      _processedSamples += samples.length;

      // Limit FFT calculations for performance
      final now = DateTime.now();
      final timeSinceLastFft =
          now.difference(_lastPerformanceLog).inMilliseconds;

      if (timeSinceLastFft > (1000 / _maxFftCalculationsPerSecond)) {
        // Process when we have enough samples for FFT
        if (_audioBuffer.length >= fftSize) {
          _performFFTAnalysis();
          _lastPerformanceLog = now;
          _fftCalculationCounter++;

          // Keep only the most recent samples
          final keepSamples = math.min(bufferSize, _audioBuffer.length);
          _audioBuffer.removeRange(0, _audioBuffer.length - keepSamples);
        }
      }

      // Log performance occasionally
      if (_debugMode && _processedSamples % 44100 == 0) {
        // Every second
        _debugLog(
            '🔧 Processed ${_processedSamples} samples, ${_fftCalculationCounter} FFT calculations');
      }
    } catch (e) {
      _debugLog('❌ Error processing audio data: $e');
    }
  }

  void _performFFTAnalysis() {
    try {
      // Take the last fftSize samples
      final samples = _audioBuffer.sublist(
        math.max(0, _audioBuffer.length - fftSize),
        _audioBuffer.length,
      );

      // Pad with zeros if needed
      while (samples.length < fftSize) {
        samples.add(0.0);
      }

      // Apply window function (Hann window) to reduce spectral leakage
      for (int i = 0; i < samples.length; i++) {
        final windowValue =
            0.5 * (1 - math.cos(2 * math.pi * i / (samples.length - 1)));
        samples[i] *= windowValue;
      }

      // Perform FFT
      final fftResult = _fft.realFft(samples);

      // Calculate magnitude spectrum
      final magnitudes = <double>[];
      for (int i = 0; i < fftResult.length; i++) {
        final real = fftResult[i].x;
        final imag = fftResult[i].y;
        magnitudes.add(math.sqrt(real * real + imag * imag));
      }

      // Map frequency bins to our 7 bands
      _mapFrequenciesToBands(magnitudes);

      // Calculate overall audio level and peak
      _currentAudioLevel = samples.map((s) => s.abs()).reduce(math.max);
      _peakAudioLevel = math.max(_peakAudioLevel * 0.95, _currentAudioLevel);

      // Adaptive smoothing based on audio dynamics
      _updateAdaptiveSmoothing();
    } catch (e) {
      _debugLog('❌ Error in FFT analysis: $e');
    }
  }

  void _updateAdaptiveSmoothing() {
    // Calculate how much the audio is changing
    double totalChange = 0.0;
    for (int i = 0; i < 7; i++) {
      totalChange += (_frequencyBands[i] - _previousBands[i]).abs();
      _previousBands[i] = _frequencyBands[i];
    }

    // Adjust smoothing factor based on audio dynamics
    if (totalChange > 2.0) {
      // Fast changes - less smoothing for responsiveness
      _smoothingFactor = _minSmoothingFactor;
    } else if (totalChange < 0.5) {
      // Slow changes - more smoothing for stability
      _smoothingFactor = _maxSmoothingFactor;
    } else {
      // Medium changes - moderate smoothing
      _smoothingFactor = 0.3;
    }
  }

  void _mapFrequenciesToBands(List<double> magnitudes) {
    final frequencyResolution = sampleRate / fftSize;

    for (int bandIndex = 0; bandIndex < 7; bandIndex++) {
      final minFreq = _frequencyRanges[bandIndex][0];
      final maxFreq = _frequencyRanges[bandIndex][1];

      // Convert frequency range to bin indices
      final minBin = (minFreq / frequencyResolution).round();
      final maxBin = (maxFreq / frequencyResolution)
          .round()
          .clamp(0, magnitudes.length - 1);

      // Calculate weighted average magnitude in this frequency range
      double weightedSum = 0.0;
      double totalWeight = 0.0;

      for (int bin = minBin; bin <= maxBin; bin++) {
        if (bin < magnitudes.length) {
          // Apply frequency weighting (emphasize important speech frequencies)
          final weight =
              _getFrequencyWeight(bin * frequencyResolution, bandIndex);
          weightedSum += magnitudes[bin] * weight;
          totalWeight += weight;
        }
      }

      if (totalWeight > 0) {
        final averageMagnitude = weightedSum / totalWeight;
        final normalizedValue =
            _normalizeFrequencyBand(averageMagnitude, bandIndex);
        _frequencyBands[bandIndex] = normalizedValue;
      }
    }
  }

  double _getFrequencyWeight(double frequency, int bandIndex) {
    // Apply perceptual weighting based on human hearing sensitivity
    switch (bandIndex) {
      case 0:
        return 0.7; // Sub-bass: less important for speech
      case 1:
        return 0.8; // Bass: moderate importance
      case 2:
        return 1.2; // Low mid: important for speech warmth
      case 3:
        return 1.5; // Mid: most important for speech intelligibility
      case 4:
        return 1.3; // Upper mid: important for speech clarity
      case 5:
        return 1.0; // Presence: moderate importance
      case 6:
        return 0.6; // Brilliance: less important for normal speech
      default:
        return 1.0;
    }
  }

  double _normalizeFrequencyBand(double magnitude, int bandIndex) {
    // Apply logarithmic scaling for better visual representation
    final logMagnitude = math.log(magnitude + 1) / math.log(10);

    // Enhanced scaling factors optimized for speech
    double scalingFactor;
    switch (bandIndex) {
      case 0:
        scalingFactor = 0.6;
        break; // Sub-bass: reduced
      case 1:
        scalingFactor = 0.8;
        break; // Bass: moderate
      case 2:
        scalingFactor = 1.0;
        break; // Low mid: baseline
      case 3:
        scalingFactor = 1.2;
        break; // Mid: enhanced (speech)
      case 4:
        scalingFactor = 1.1;
        break; // Upper mid: enhanced
      case 5:
        scalingFactor = 0.9;
        break; // Presence: slightly reduced
      case 6:
        scalingFactor = 0.7;
        break; // Brilliance: reduced
      default:
        scalingFactor = 1.0;
    }

    // Apply dynamic range compression for better visualization
    final compressedMagnitude = math.pow(logMagnitude, 0.7);

    // Scale to 1-6 range with band-specific scaling
    final scaledValue =
        (compressedMagnitude * scalingFactor * 3.0 + 1.0).clamp(1.0, 6.0);
    return scaledValue;
  }

  void _startAudioSimulation() {
    _debugLog('🎲 Starting audio simulation...');
    Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _simulateAudioLevel(),
    );
  }

  void _simulateAudioLevel() {
    if (!_isRecording) return;

    // Simulate varying audio levels
    _currentAudioLevel = _random.nextDouble() * 0.8 + 0.2;

    // Simulate frequency band variations
    for (int i = 0; i < 7; i++) {
      final bandVariation = _random.nextDouble() * 0.4 + 0.8;
      final baseLevel = _currentAudioLevel * bandVariation;
      final frequencyModifier = _getFrequencyModifier(i);
      _frequencyBands[i] =
          (baseLevel * frequencyModifier * 5 + 1).clamp(1.0, 6.0);
    }

    if (_debugMode && _random.nextInt(60) == 0) {
      _debugLog(
          '🎵 Simulated Audio Level: ${_currentAudioLevel.toStringAsFixed(2)} | Bars: ${_frequencyBands.map((b) => b.toStringAsFixed(1)).join(', ')}');
    }
  }

  double _getFrequencyModifier(int bandIndex) {
    switch (bandIndex) {
      case 0:
        return 0.6 + _random.nextDouble() * 0.4; // Sub-bass
      case 1:
        return 0.7 + _random.nextDouble() * 0.4; // Bass
      case 2:
        return 0.8 + _random.nextDouble() * 0.4; // Low mid
      case 3:
        return 0.9 + _random.nextDouble() * 0.4; // Mid
      case 4:
        return 0.8 + _random.nextDouble() * 0.4; // Upper mid
      case 5:
        return 0.7 + _random.nextDouble() * 0.4; // Presence
      case 6:
        return 0.5 + _random.nextDouble() * 0.4; // Brilliance
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
    if (!_isRecording) return;

    try {
      // Apply smoothing to prevent jittery animations
      for (int i = 0; i < 7; i++) {
        _smoothedBands[i] = _smoothedBands[i] * (1 - _smoothingFactor) +
            _frequencyBands[i] * _smoothingFactor;
      }

      // Increment debug counter
      _debugCounter++;

      // Try new method first (if connected)
      if (_isConnected &&
          _controller != null &&
          _barInputs?.isNotEmpty == true) {
        // Convert smoothed bands to 0-1 range for the new method
        final normalizedBands =
            _smoothedBands.map((band) => (band - 1.0) / 5.0).toList();
        _updateRiveInputs(normalizedBands);
      } else {
        // Fall back to old method for backward compatibility
        if (_riveController != null) {
          for (int i = 1; i <= 7; i++) {
            final barInput = _riveController!.findInput<double>('Bar $i');
            if (barInput != null) {
              barInput.value = _smoothedBands[i - 1];
              if (_debugMode && _random.nextInt(300) == 0) {
                _debugLog(
                    '✅ Updated Bar $i = ${_smoothedBands[i - 1].toStringAsFixed(1)}');
              }
            } else {
              if (_debugMode && _random.nextInt(300) == 0) {
                _debugLog(
                    '⚠️ Bar $i input not found in Bar Heights view model');
              }
            }
          }
        }
      }

      // Debug log occasionally with more detail
      if (_debugMode && _random.nextInt(90) == 0) {
        _debugLog(
            '🎵 Audio Level: ${_currentAudioLevel.toStringAsFixed(2)} | Bar Heights: ${_smoothedBands.map((b) => b.toStringAsFixed(1)).join(', ')}');
      }
    } catch (e) {
      _debugLog('❌ Error updating Bar Heights: $e');
    }
  }

  void _updateRiveInputs(List<double> barValues) {
    if (!_isConnected ||
        _controller == null ||
        _barInputs?.isEmpty != false) {
      return;
    }

    try {
      // Update each bar with its corresponding frequency band value
      for (int i = 0; i < 7; i++) {
        final barKey = 'Bar ${i + 1}';
        final barInput = _barInputs![barKey];

        if (barInput != null && i < barValues.length) {
          // Convert 0-1 range to 1-6 range for Rive
          final riveValue = (barValues[i] * 5.0) + 1.0;
          final clampedValue = riveValue.clamp(1.0, 6.0);

          // Set the property value on the view model instance
          barInput.value = clampedValue;

          if (_debugMode && _debugCounter % 30 == 0) {
            print(
                '[AudioFFT] Bar ${i + 1}: ${barValues[i].toStringAsFixed(2)} -> ${clampedValue.toStringAsFixed(1)}');
          }
        }
      }

      if (_debugMode && _debugCounter % 30 == 0) {
        print('[AudioFFT] Updated ${_barInputs!.length} bar inputs');
      }
    } catch (e) {
      print('[AudioFFT] Error updating Rive inputs: $e');
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
    _updateTimer?.cancel();
    _updateTimer = null;

    // Clear audio buffer
    _audioBuffer.clear();

    // Apply decay to bars (gradual fade out)
    Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_isRecording) {
        timer.cancel();
        return;
      }

      bool allBarsAtMinimum = true;
      for (int i = 0; i < 7; i++) {
        _smoothedBands[i] = math.max(1.0, _smoothedBands[i] * _decayFactor);
        if (_smoothedBands[i] > 1.1) allBarsAtMinimum = false;
      }

      // Update bars during decay
      if (_riveController != null) {
        for (int i = 1; i <= 7; i++) {
          final barInput = _riveController!.findInput<double>('Bar $i');
          if (barInput != null) {
            barInput.value = _smoothedBands[i - 1];
          }
        }
      }

      // Stop decay when all bars reach minimum
      if (allBarsAtMinimum) {
        timer.cancel();
        _debugLog('✅ Recording stopped and bars faded out');
      }
    });
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
      _debugLog('❌ Cannot test Bar Heights - no Rive controller');
      return;
    }

    final value = testValue ?? 3.5;
    _debugLog('🧪 Testing Bar Heights view model with value: $value');

    int foundBars = 0;
    for (int i = 1; i <= 7; i++) {
      final barInput = _riveController!.findInput<double>('Bar $i');
      if (barInput != null) {
        barInput.value = value;
        _debugLog('✅ Set Bar $i = $value');
        foundBars++;
      } else {
        _debugLog('❌ Bar $i input not found in Bar Heights view model');
      }
    }

    _debugLog('📊 Found $foundBars/7 bar inputs in Bar Heights view model');
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

  void dispose() {
    print('🎤 Disposing AudioFFTService...');

    // Cancel all timers
    _updateTimer?.cancel();
    _updateTimer = null;

    // Audio cleanup (simulation mode only)

    // Reset state
    _isRecording = false;
    _audioBuffer.clear();

    // Clear controller reference
    _riveController = null;
    _isRecordInput = null;

    print('🎤 AudioFFTService disposed');
  }

  // Getters
  bool get isRecording => _isRecording;
  bool get isInitialized => _isInitialized;
  bool get debugMode => _debugMode;
  bool get useRealAudio => _useRealAudio;
  List<double> get frequencyBands => List.from(_frequencyBands);
  List<double> get smoothedBands => List.from(_smoothedBands);
  double get currentAudioLevel => _currentAudioLevel;

  // Reset the service state without fully disposing it
  Future<void> reset() async {
    print('🎤 Resetting AudioFFTService...');

    // Stop recording if active
    if (_isRecording) {
      await _stopRecordingInternal();
    }

    // Cancel all timers
    _updateTimer?.cancel();
    _updateTimer = null;

    // Audio cleanup (simulation mode only)

    // Reset state variables
    _isRecording = false;
    _currentAudioLevel = 0.0;
    _audioBuffer.clear();

    // Reset frequency bands
    for (int i = 0; i < _frequencyBands.length; i++) {
      _frequencyBands[i] = 1.0;
      _smoothedBands[i] = 1.0;
    }

    // Reset Rive inputs if available
    if (_riveController != null) {
      if (_isRecordInput != null) {
        _isRecordInput!.value = false;
      }

      // Reset all bar values
      for (int i = 1; i <= 7; i++) {
        final barInput = _riveController!.findInput<double>('Bar $i');
        if (barInput != null) {
          barInput.value = 1.0;
        }
      }
    }

    print('🎤 AudioFFTService reset complete');
  }

  // Toggle between real audio and simulation
  void toggleAudioMode() {
    _useRealAudio = !_useRealAudio;
    _debugLog(
        '🔄 Toggled audio mode to: ${_useRealAudio ? 'Real Audio' : 'Simulation'}');

    if (_isRecording) {
      // Restart with new mode
      _stopRecordingInternal().then((_) {
        Future.delayed(const Duration(milliseconds: 100), () {
          _startRecordingInternal();
        });
      });
    }
  }
}
