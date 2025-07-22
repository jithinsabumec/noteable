import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart' as rive;
import 'services/audio_fft_service.dart';

class TestAudioVisualization extends StatefulWidget {
  const TestAudioVisualization({super.key});

  @override
  State<TestAudioVisualization> createState() => _TestAudioVisualizationState();
}

class _TestAudioVisualizationState extends State<TestAudioVisualization> {
  final _audioFFTService = AudioFFTService();
  final List<String> _debugLogs = [];
  final ScrollController _debugScrollController = ScrollController();

  rive.Artboard? _riveArtboard;
  rive.StateMachineController? _controller;
  bool _riveLoaded = false;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadRiveAnimation();
  }

  Future<void> _initializeServices() async {
    try {
      await _audioFFTService.initialize(debugMode: true, useRealAudio: false);
      _audioFFTService.setDebugCallback(_addDebugLog);
      _addDebugLog('✅ AudioFFTService initialized');
    } catch (e) {
      _addDebugLog('❌ Error initializing audio service: $e');
    }
  }

  void _addDebugLog(String message) {
    if (mounted) {
      setState(() {
        _debugLogs
            .add('${DateTime.now().toString().substring(11, 19)} $message');
        if (_debugLogs.length > 50) {
          _debugLogs.removeAt(0);
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_debugScrollController.hasClients) {
          _debugScrollController.animateTo(
            _debugScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _loadRiveAnimation() async {
    try {
      _addDebugLog('🎨 Loading Rive animation...');

      final data = await rootBundle.load('assets/animations/record.riv');
      final file = rive.RiveFile.import(data);
      final artboard = file.mainArtboard;

      var controller = rive.StateMachineController.fromArtboard(
        artboard,
        'State Machine 1',
      );

      if (controller != null) {
        _addDebugLog('✅ Found state machine');
        artboard.addController(controller);

        // List all available inputs
        final inputsList = controller.inputs.toList();
        _addDebugLog('📋 Available inputs (${inputsList.length} total):');
        for (int i = 0; i < inputsList.length; i++) {
          final input = inputsList[i];
          _addDebugLog('   $i: "${input.name}" (${input.runtimeType})');
        }

        // Check for specific inputs
        final isRecordInput = controller.findInput<bool>('isRecord');
        final clickInput = controller.findInput<bool>('Click');
        final isPauseInput = controller.findInput<bool>('isPause');

        _addDebugLog('🔍 Input search results:');
        _addDebugLog('   isRecord: ${isRecordInput != null}');
        _addDebugLog('   Click: ${clickInput != null}');
        _addDebugLog('   isPause: ${isPauseInput != null}');

        // Check for Bar Heights view model inputs
        _addDebugLog('🎯 Checking Bar Heights view model:');
        int foundBars = 0;
        for (int i = 1; i <= 7; i++) {
          final barInput = controller.findInput<double>('Bar $i');
          if (barInput != null) {
            foundBars++;
            _addDebugLog('   ✅ Bar $i: found');
          } else {
            _addDebugLog('   ❌ Bar $i: not found');
          }
        }
        _addDebugLog('📊 Total Bar Heights inputs found: $foundBars/7');

        _controller = controller;
        _audioFFTService.connectToRiveController(controller);
        _addDebugLog('✅ Rive controller connected to AudioFFTService');
      } else {
        _addDebugLog('❌ State machine not found');
      }

      setState(() {
        _riveArtboard = artboard;
        _riveLoaded = true;
      });

      _addDebugLog('✅ Rive animation loaded');
    } catch (error) {
      _addDebugLog('❌ Error loading Rive: $error');
    }
  }

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
    });

    if (_isRecording) {
      _addDebugLog('🎵 Starting audio visualization test');
      _audioFFTService.startRecording();
    } else {
      _addDebugLog('🛑 Stopping audio visualization test');
      _audioFFTService.stopRecording();
    }
  }

  void _testBars(double value) {
    _addDebugLog('🧪 Testing Bar Heights with value: $value');
    _audioFFTService.testBars(testValue: value);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _audioFFTService.dispose();
    _debugScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Visualization Test'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Rive Animation
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              color: Colors.grey[100],
              child: _riveLoaded && _riveArtboard != null
                  ? rive.Rive(
                      artboard: _riveArtboard!,
                      fit: BoxFit.contain,
                    )
                  : const Center(
                      child: CircularProgressIndicator(),
                    ),
            ),
          ),

          // Controls
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Status
                Text(
                  'Status: ${_isRecording ? "🟢 Recording" : "🔴 Stopped"}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Control buttons
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: _toggleRecording,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isRecording ? Colors.red : Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(_isRecording ? 'Stop' : 'Start'),
                    ),
                    ElevatedButton(
                      onPressed: () => _testBars(1.0),
                      child: const Text('Bar Heights: 1.0'),
                    ),
                    ElevatedButton(
                      onPressed: () => _testBars(3.5),
                      child: const Text('Bar Heights: 3.5'),
                    ),
                    ElevatedButton(
                      onPressed: () => _testBars(6.0),
                      child: const Text('Bar Heights: 6.0'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Debug logs
          Expanded(
            flex: 1,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Debug Logs:',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      controller: _debugScrollController,
                      itemCount: _debugLogs.length,
                      itemBuilder: (context, index) {
                        return Text(
                          _debugLogs[index],
                          style: const TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
 