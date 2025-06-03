import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart' as rive;
import '../services/audio_fft_service.dart';

class RiveAudioVisualizer extends StatefulWidget {
  final String rivePath;
  final String stateMachineName;
  final bool debugMode;

  const RiveAudioVisualizer({
    super.key,
    required this.rivePath,
    this.stateMachineName = 'State Machine 1',
    this.debugMode = true,
  });

  @override
  State<RiveAudioVisualizer> createState() => _RiveAudioVisualizerState();
}

class _RiveAudioVisualizerState extends State<RiveAudioVisualizer> {
  final _audioFFTService = AudioFFTService();
  final List<String> _debugLogs = [];
  final ScrollController _debugScrollController = ScrollController();

  rive.Artboard? _riveArtboard;
  rive.StateMachineController? _controller;
  rive.SMIInput<bool>? _isRecordInput;
  bool _riveLoaded = false;
  bool _showDebugPanel = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadRiveAnimation();
  }

  Future<void> _initializeServices() async {
    try {
      await _audioFFTService.initialize(debugMode: widget.debugMode);
      if (widget.debugMode) {
        _audioFFTService.setDebugCallback(_addDebugLog);
      }
    } catch (e) {
      _addDebugLog('❌ Error initializing audio service: $e');
    }
  }

  void _addDebugLog(String message) {
    if (mounted) {
      setState(() {
        _debugLogs
            .add('${DateTime.now().toString().substring(11, 19)} $message');
        // Keep only last 100 logs
        if (_debugLogs.length > 100) {
          _debugLogs.removeAt(0);
        }
      });
      // Auto-scroll to bottom
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
      _addDebugLog('🎨 Loading Rive animation from ${widget.rivePath}');

      // Load the Rive file
      final data = await rootBundle.load(widget.rivePath);
      final file = rive.RiveFile.import(data);
      final artboard = file.mainArtboard;

      // Setup Rive artboard with state machine
      var controller = rive.StateMachineController.fromArtboard(
        artboard,
        widget.stateMachineName,
      );

      if (controller != null) {
        _addDebugLog('✅ Found state machine: ${widget.stateMachineName}');

        // Add controller to artboard
        artboard.addController(controller);

        // Find the isRecord input
        _isRecordInput = controller.findInput<bool>('isRecord');
        if (_isRecordInput != null) {
          _addDebugLog('✅ Found isRecord input');
        } else {
          _addDebugLog('❌ isRecord input not found');
        }

        // Check for bar inputs
        for (int i = 1; i <= 7; i++) {
          final barInput = controller.findInput<double>('Bar $i');
          if (barInput != null) {
            _addDebugLog('✅ Found Bar $i input');
          } else {
            _addDebugLog('❌ Bar $i input not found');
          }
        }

        _controller = controller;

        // Set the Rive controller in the FFT service
        _audioFFTService.setRiveController(controller);
      } else {
        _addDebugLog('❌ State machine not found: ${widget.stateMachineName}');
      }

      setState(() {
        _riveArtboard = artboard;
        _riveLoaded = true;
      });

      _addDebugLog('✅ Rive animation loaded successfully');
    } catch (error) {
      _addDebugLog('❌ Error loading Rive animation: $error');
    }
  }

  Widget _buildDebugControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Text(
                '🛠️ Debug Controls',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => setState(() => _showDebugPanel = false),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Test buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton(
                onPressed: () => _audioFFTService.testBars(testValue: 1.0),
                child: const Text('Test Min (1.0)'),
              ),
              ElevatedButton(
                onPressed: () => _audioFFTService.testBars(testValue: 3.5),
                child: const Text('Test Mid (3.5)'),
              ),
              ElevatedButton(
                onPressed: () => _audioFFTService.testBars(testValue: 6.0),
                child: const Text('Test Max (6.0)'),
              ),
              ElevatedButton(
                onPressed: () => _audioFFTService.testIsRecord(value: true),
                child: const Text('Force Start'),
              ),
              ElevatedButton(
                onPressed: () => _audioFFTService.testIsRecord(value: false),
                child: const Text('Force Stop'),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Current status
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status: ${_audioFFTService.isRecording ? "🟢 Recording" : "🔴 Stopped"}',
                  style: const TextStyle(color: Colors.white),
                ),
                Text(
                  'Audio Level: ${_audioFFTService.currentAudioLevel.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white),
                ),
                Text(
                  'isRecord: ${_isRecordInput?.value ?? "null"}',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Current frequency bands
          const Text(
            'Frequency Bands:',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (int i = 0; i < 7; i++)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'B${i + 1}: ${_audioFFTService.frequencyBands[i].toStringAsFixed(1)}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Debug logs
          const Text(
            'Debug Logs:',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Container(
            height: 150,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(4),
            ),
            child: ListView.builder(
              controller: _debugScrollController,
              itemCount: _debugLogs.length,
              itemBuilder: (context, index) {
                return Text(
                  _debugLogs[index],
                  style: const TextStyle(
                    color: Colors.green,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
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
        title: const Text('Audio Visualizer'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          if (widget.debugMode)
            IconButton(
              onPressed: () =>
                  setState(() => _showDebugPanel = !_showDebugPanel),
              icon: Icon(_showDebugPanel
                  ? Icons.bug_report
                  : Icons.bug_report_outlined),
            ),
        ],
      ),
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Main content
          Column(
            children: [
              // Rive Animation
              Expanded(
                child: _riveLoaded && _riveArtboard != null
                    ? rive.Rive(
                        artboard: _riveArtboard!,
                        fit: BoxFit.contain,
                      )
                    : const Center(
                        child: CircularProgressIndicator(),
                      ),
              ),

              // Simple status display
              if (!_showDebugPanel && widget.debugMode)
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        'Status: ${_audioFFTService.isRecording ? "🟢 Recording" : "🔴 Stopped"}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap the debug icon to see controls and logs',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          // Debug panel overlay
          if (_showDebugPanel && widget.debugMode)
            Positioned(
              top: 20,
              left: 20,
              right: 20,
              child: _buildDebugControls(),
            ),
        ],
      ),
    );
  }
}
