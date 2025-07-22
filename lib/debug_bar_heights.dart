import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart' as rive;
import 'services/audio_fft_service.dart';
import 'dart:async'; // Added for Timer
import 'dart:math' as math; // Added for math.sin

class DebugBarHeights extends StatefulWidget {
  const DebugBarHeights({super.key});

  @override
  State<DebugBarHeights> createState() => _DebugBarHeightsState();
}

class _DebugBarHeightsState extends State<DebugBarHeights> {
  rive.Artboard? _riveArtboard;
  rive.StateMachineController? _controller;
  final AudioFFTService _audioFFTService = AudioFFTService();
  final List<String> _debugLogs = [];

  // List of available Rive files to test
  final List<String> _riveFiles = [
    'assets/animations/record.riv',
    'assets/animations/transcribe.riv',
    'assets/animations/understand.riv',
    'assets/animations/extract.riv',
    'assets/animations/bottom_bar.riv',
    'assets/animations/tick.riv',
    'assets/animations/todo_tick.riv',
  ];

  int _currentFileIndex = 0;

  // Test values for manual bar testing
  final List<double> _testBarValuesList = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 3.5];

  @override
  void initState() {
    super.initState();
    _loadRiveAnimation();
  }

  void _addDebugLog(String message) {
    setState(() {
      _debugLogs.add(
          '${DateTime.now().toIso8601String().substring(11, 19)}: $message');
      // Keep only last 30 logs
      if (_debugLogs.length > 30) {
        _debugLogs.removeAt(0);
      }
    });
    print('[DEBUG] $message');
  }

  void _loadRiveAnimation() async {
    final currentFile = _riveFiles[_currentFileIndex];
    final fileName = currentFile.split('/').last;

    _addDebugLog('🔄 Loading Rive animation: $fileName');

    try {
      // Load the Rive file
      final data = await rootBundle.load(currentFile);
      final file = rive.RiveFile.import(data);
      final artboard = file.mainArtboard;

      // Debug: List all available artboards
      _addDebugLog('📋 Available artboards (${file.artboards.length} total):');
      for (final ab in file.artboards) {
        _addDebugLog('   - ${ab.name}');
      }

      // Debug: List all available state machines
      _addDebugLog('📋 Available state machines in main artboard:');
      for (final sm in artboard.stateMachines) {
        _addDebugLog('   - ${sm.name}');
      }

      // Try different state machine names
      var controller = rive.StateMachineController.fromArtboard(
        artboard,
        'State Machine 1',
      );

      // If State Machine 1 not found, try other common names
      if (controller == null && artboard.stateMachines.isNotEmpty) {
        final firstStateMachine = artboard.stateMachines.first;
        _addDebugLog('🔄 Trying state machine: ${firstStateMachine.name}');
        controller = rive.StateMachineController.fromArtboard(
          artboard,
          firstStateMachine.name,
        );
      }

      if (controller != null) {
        artboard.addController(controller);
        _controller = controller;

        _addDebugLog('✅ $fileName loaded successfully');
        _addDebugLog(
            '📋 Available inputs (${controller.inputs.length} total):');

        // Look for all inputs and categorize them
        int barCount = 0;
        int boolCount = 0;
        int triggerCount = 0;
        int numberCount = 0;

        for (final input in controller.inputs) {
          _addDebugLog('   - ${input.name} (${input.runtimeType})');

          if (input is rive.SMIInput<double>) {
            numberCount++;
          } else if (input is rive.SMIInput<bool>) {
            boolCount++;
          } else if (input is rive.SMITrigger) {
            triggerCount++;
          }

          // Check if it's a bar input
          if (input.name.toLowerCase().contains('bar') ||
              input.name.toLowerCase().contains('height')) {
            barCount++;
          }
        }

        _addDebugLog('📊 Input Summary:');
        _addDebugLog('   - Numbers: $numberCount');
        _addDebugLog('   - Booleans: $boolCount');
        _addDebugLog('   - Triggers: $triggerCount');
        _addDebugLog('   - Potential bars: $barCount');

        if (barCount > 0) {
          _addDebugLog('🎯 Found $barCount potential bar inputs!');
        } else {
          _addDebugLog('❌ No bar inputs found');
          _addDebugLog('');
          _addDebugLog('🔧 TO FIX THIS ISSUE:');
          _addDebugLog('1. Create a new Rive file with audio visualization');
          _addDebugLog('2. Add a State Machine with 7 number inputs:');
          _addDebugLog('   - Bar 1, Bar 2, Bar 3, Bar 4, Bar 5, Bar 6, Bar 7');
          _addDebugLog('3. Connect these inputs to visual bars/rectangles');
          _addDebugLog('4. Set input ranges from 1 to 6 for each bar');
          _addDebugLog('5. Save as audio_visualizer.riv');
          _addDebugLog('');
        }

        // Connect to AudioFFTService
        _audioFFTService.connectToRiveController(controller);
        _addDebugLog('🔗 Connected to AudioFFTService');

        setState(() {
          _riveArtboard = artboard;
        });
      } else {
        _addDebugLog('❌ No state machine found in $fileName');

        // Still set the artboard for display even without state machine
        setState(() {
          _riveArtboard = artboard;
        });
      }
    } catch (e) {
      _addDebugLog('❌ Error loading $fileName: $e');
    }
  }

  void _testBarValues() {
    _addDebugLog('🧪 Testing bar values...');

    if (_controller == null) {
      _addDebugLog('❌ No controller available for testing');
      return;
    }

    // Test with different values
    int foundBars = 0;
    for (int i = 0; i < 7; i++) {
      final barName = 'Bar ${i + 1}';
      final barInput = _controller?.findInput<double>(barName);

      if (barInput != null) {
        barInput.value = _testBarValuesList[i];
        _addDebugLog('✅ Set $barName = ${_testBarValuesList[i]}');
        foundBars++;
      } else {
        _addDebugLog('❌ $barName input not found');
      }
    }

    _addDebugLog('📊 Total bars found: $foundBars/7');

    if (foundBars == 0) {
      _addDebugLog('');
      _addDebugLog('💡 SOLUTION: Create a Rive file with:');
      _addDebugLog('   - 7 visual bars (rectangles)');
      _addDebugLog('   - State machine with 7 number inputs');
      _addDebugLog('   - Each input controls a bar height');
      _addDebugLog('   - Input range: 1.0 to 6.0');
    }
  }

  void _animateBarValues() {
    _addDebugLog('🎬 Starting bar animation test...');

    if (_controller == null) {
      _addDebugLog('❌ No controller available for animation');
      return;
    }

    // Find available bar inputs
    final barInputs = <rive.SMIInput<double>>[];
    for (int i = 0; i < 7; i++) {
      final barName = 'Bar ${i + 1}';
      final barInput = _controller?.findInput<double>(barName);
      if (barInput != null) {
        barInputs.add(barInput);
      }
    }

    if (barInputs.isEmpty) {
      _addDebugLog('❌ No bar inputs found for animation');
      return;
    }

    _addDebugLog('🎯 Found ${barInputs.length} bar inputs for animation');

    // Animate bars with sine wave pattern
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final time = timer.tick * 0.1;
      for (int i = 0; i < barInputs.length; i++) {
        final value = 3.5 + 2.5 * math.sin(time + i * 0.5);
        barInputs[i].value = value.clamp(1.0, 6.0);
      }

      // Stop after 10 seconds
      if (timer.tick > 100) {
        timer.cancel();
        _addDebugLog('🛑 Animation test completed');
      }
    });
  }

  void _nextFile() {
    _currentFileIndex = (_currentFileIndex + 1) % _riveFiles.length;
    _loadRiveAnimation();
  }

  void _previousFile() {
    _currentFileIndex =
        (_currentFileIndex - 1 + _riveFiles.length) % _riveFiles.length;
    _loadRiveAnimation();
  }

  @override
  Widget build(BuildContext context) {
    final currentFileName = _riveFiles[_currentFileIndex].split('/').last;

    return Scaffold(
      appBar: AppBar(
        title: Text('Debug Bar Heights - $currentFileName'),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          // File navigation
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: _previousFile,
                  child: const Text('← Previous'),
                ),
                Text(
                  'File ${_currentFileIndex + 1}/${_riveFiles.length}: $currentFileName',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                ElevatedButton(
                  onPressed: _nextFile,
                  child: const Text('Next →'),
                ),
              ],
            ),
          ),

          // Rive animation
          Container(
            height: 250,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            margin: const EdgeInsets.all(16),
            child: _riveArtboard != null
                ? rive.Rive(artboard: _riveArtboard!)
                : const Center(child: CircularProgressIndicator()),
          ),

          // Test buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _testBarValues,
                  child: const Text('Test Bar Values'),
                ),
                ElevatedButton(
                  onPressed: _animateBarValues,
                  child: const Text('Animate Bars'),
                ),
              ],
            ),
          ),

          // Instructions
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              border: Border.all(color: Colors.orange),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🔧 Missing Audio Visualizer',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'None of your current Rive files have the required Bar Heights inputs for audio visualization. You need to create a new Rive file with:\n\n'
                  '• 7 visual bars (rectangles)\n'
                  '• State machine with 7 number inputs named "Bar 1" through "Bar 7"\n'
                  '• Each input should control the height of a bar\n'
                  '• Input range: 1.0 to 6.0\n'
                  '• Save as "audio_visualizer.riv"',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),

          // Debug logs
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                itemCount: _debugLogs.length,
                itemBuilder: (context, index) {
                  return Text(
                    _debugLogs[index],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
