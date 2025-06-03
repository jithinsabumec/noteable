import 'package:flutter/material.dart';
import 'package:rive/rive.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/assembly_ai_service.dart';
import '../services/deepseek_service.dart';
import '../services/storage_service.dart';
import '../services/item_management_service.dart';
import '../models/timeline_models.dart';
import '../widgets/bottom_sheets/add_item_bottom_sheet.dart';
import 'dart:io';
import 'dart:async';

class RiveAnimationWidget extends StatefulWidget {
  final Map<String, List<TimelineEntry>> timelineEntriesByDate;
  final DateTime selectedDate;
  final Function() onStateUpdate;

  const RiveAnimationWidget({
    super.key,
    required this.timelineEntriesByDate,
    required this.selectedDate,
    required this.onStateUpdate,
  });

  @override
  State<RiveAnimationWidget> createState() => _RiveAnimationWidgetState();
}

class _RiveAnimationWidgetState extends State<RiveAnimationWidget> {
  // Rive controller
  StateMachineController? controller;
  RiveAnimation? anim;

  // Audio services
  final _audioRecorder = AudioRecorder();
  final _assemblyAIService = AssemblyAIService();
  final _deepseekService = DeepseekService();
  final _storageService = StorageService();
  final _itemManagementService = ItemManagementService();

  // Recording state
  bool _isRecording = false;
  String? _recordedFilePath;
  DateTime? _recordingStartTime;

  // Processing states
  bool _isTranscribing = false;
  bool _isAnalyzing = false;
  String _transcribedText = '';

  // Rive inputs
  SMIInput<bool>? _isRecordInput;
  SMIInput<bool>? _clickInput;
  SMIInput<bool>? _isSubmitInput;
  SMIInput<bool>? _isDoneInput;
  SMIInput<bool>? _taskSelectedInput;
  SMIInput<bool>? _noteSelectedInput;

  // Monitoring timer
  Timer? _monitoringTimer;

  // Audio player
  late AudioPlayer _audioPlayer;

  @override
  void initState() {
    super.initState();
    _loadRiveAnimation();
    _initAudioPlayer();
  }

  void _loadRiveAnimation() {
    anim = RiveAnimation.asset(
      'assets/animations/bottom_bar.riv',
      artboard: 'Artboard',
      fit: BoxFit.contain,
      onInit: onRiveInit,
    );
  }

  void onRiveInit(Artboard artboard) {
    // Try to find the state machine
    controller = StateMachineController.fromArtboard(artboard, 'Record');

    if (controller != null) {
      artboard.addController(controller!);

      // Find inputs
      _isRecordInput = controller!.findInput<bool>('isRecord');
      _clickInput = controller!.findInput<bool>('Click');
      _isSubmitInput = controller!.findInput<bool>('isSubmit');
      _isDoneInput = controller!.findInput<bool>('isDone');
      _taskSelectedInput = controller!.findInput<bool>('Task Selected');
      _noteSelectedInput = controller!.findInput<bool>('Note Selected');

      // Set up event listener for clicks
      controller!.addEventListener(_onRiveEvent);

      // Start monitoring isRecord state changes
      _startIsRecordMonitoring();
    }
  }

  // Monitor isRecord state changes to detect when recording should start/stop
  void _startIsRecordMonitoring() {
    bool _previousIsRecord = false; // Track previous isRecord state
    bool _previousIsSubmit = false; // Track previous isSubmit state
    bool _previousTaskSelected = false; // Track previous taskSelected state
    bool _previousNoteSelected = false; // Track previous noteSelected state

    // Check both input states every 100ms
    _monitoringTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || _isRecordInput == null) {
        timer.cancel();
        return;
      }

      final currentIsRecord = _isRecordInput!.value;
      final currentIsSubmit = _isSubmitInput?.value ?? false;
      final currentTaskSelected = _taskSelectedInput?.value ?? false;
      final currentNoteSelected = _noteSelectedInput?.value ?? false;

      // Only act on state changes, not continuous states

      // Handle isRecord state changes
      if (currentIsRecord != _previousIsRecord) {
        if (currentIsRecord &&
            !_isRecording &&
            !_isTranscribing &&
            !_isAnalyzing) {
          // Play start recording sound immediately
          unawaited(_playStartRecordingSound());
          // Start recording when isRecord becomes true
          _startRecording();
        } else if (!currentIsRecord && _isRecording) {
          // Play end recording sound immediately
          unawaited(_playEndRecordingSound());
          // Stop recording when isRecord becomes false
          _stopRecording();
        }
        _previousIsRecord = currentIsRecord;
      }

      // Process recording when isSubmit becomes true (and we're recording)
      if (currentIsSubmit != _previousIsSubmit) {
        if (currentIsSubmit && _isRecording) {
          // Play end recording sound immediately
          unawaited(_playEndRecordingSound());
          _stopRecording();
        }
        _previousIsSubmit = currentIsSubmit;
      }

      // Handle taskSelected state changes
      if (currentTaskSelected != _previousTaskSelected) {
        if (currentTaskSelected) {
          _showTaskBottomSheet();
        }
        _previousTaskSelected = currentTaskSelected;
      }

      // Handle noteSelected state changes
      if (currentNoteSelected != _previousNoteSelected) {
        if (currentNoteSelected) {
          _showNoteBottomSheet();
        }
        _previousNoteSelected = currentNoteSelected;
      }
    });
  }

  void _onRiveEvent(RiveEvent event) {
    // Event handler for Rive events
  }

  Future<void> _startRecording() async {
    if (_isRecording) {
      return;
    }

    if (_isTranscribing || _isAnalyzing) {
      return;
    }

    try {
      // Check permissions
      final hasPermission = await _checkPermissions();
      if (!hasPermission) {
        return;
      }

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

      _recordingStartTime = DateTime.now();

      setState(() {
        _isRecording = true;
        _isTranscribing = false;
        _isAnalyzing = false;
        _transcribedText = '';
      });

      // Reset isDone to false when starting new recording
      if (_isDoneInput != null) {
        _isDoneInput!.value = false;
      }
    } catch (e) {
      // Reset state on error
      setState(() {
        _isRecording = false;
      });
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) {
      return;
    }

    try {
      final path = await _audioRecorder.stop();

      setState(() {
        _isRecording = false;
      });

      if (path != null) {
        // Comprehensive file validation
        await _validateAudioFile(path);

        // Start the transcription and processing workflow
        await _processRecording(path);
      }
    } catch (e) {
      // Reset state on error
      setState(() {
        _isRecording = false;
      });
    }
  }

  Future<void> _validateAudioFile(String filePath) async {
    try {
      final file = File(filePath);

      // Check if file exists
      if (!await file.exists()) {
        throw Exception('Recording file not found');
      }

      // Check file size
      final fileStats = await file.stat();

      // Validation checks
      if (fileStats.size == 0) {
        throw Exception('Recording file is empty (0 bytes)');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _processRecording(String filePath) async {
    try {
      // Step 1: Transcribe audio
      setState(() {
        _isTranscribing = true;
        _isAnalyzing = false;
      });

      try {
        _transcribedText = await _assemblyAIService.transcribeAudio(filePath);

        if (_transcribedText.trim().isEmpty) {
          throw Exception(
              'Transcription returned empty text - no speech detected');
        }
      } catch (e) {
        throw Exception('Transcription failed: $e');
      }

      // Continue with AI analysis
      await _processTranscriptionResult();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isTranscribing = false;
        _isAnalyzing = false;
      });

      // Set isDone to true even on error to stop loading animation
      if (_isDoneInput != null) {
        _isDoneInput!.value = true;
      }

      // Schedule reset even after error
      _scheduleStateReset();
    }
  }

  Future<void> _processTranscriptionResult() async {
    if (!mounted) return;

    // Step 2: Analyze with DeepSeek
    setState(() {
      _isTranscribing = false;
      _isAnalyzing = true;
    });

    try {
      final result =
          await _deepseekService.analyzeTranscription(_transcribedText);

      if (!mounted) return;

      // Step 3: Add to timeline using ItemManagementService
      await _addToTimeline(result);

      if (!mounted) return;

      // Step 4: Complete the process
      setState(() {
        _isTranscribing = false;
        _isAnalyzing = false;
      });

      // Set isDone to true to indicate completion
      if (_isDoneInput != null) {
        _isDoneInput!.value = true;
      }

      // Schedule a reset after the completion animation finishes
      _scheduleStateReset();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTranscribing = false;
          _isAnalyzing = false;
        });

        // Set isDone to true even on error
        if (_isDoneInput != null) {
          _isDoneInput!.value = true;
        }

        // Schedule reset even after error
        _scheduleStateReset();
      }
      throw Exception('AI analysis failed: $e');
    }
  }

  Future<void> _addToTimeline(Map<String, dynamic> result) async {
    // Add notes to timeline
    if (result['notes'] != null && result['notes'].isNotEmpty) {
      for (final note in result['notes']) {
        _itemManagementService.createNoteEntry(
          noteText: note,
          selectedDate: widget.selectedDate,
          timelineEntriesByDate: widget.timelineEntriesByDate,
          onStateUpdate: widget.onStateUpdate,
        );
      }
    }

    // Add tasks to timeline
    if (result['tasks'] != null && result['tasks'].isNotEmpty) {
      for (final task in result['tasks']) {
        _itemManagementService.createTaskEntry(
          taskText: task,
          selectedDate: widget.selectedDate,
          timelineEntriesByDate: widget.timelineEntriesByDate,
          onStateUpdate: widget.onStateUpdate,
        );
      }
    }
  }

  // Reset all states for the next recording cycle
  void _scheduleStateReset() {
    Timer(const Duration(seconds: 3), () {
      if (!mounted) return;

      // Reset all processing states
      setState(() {
        _isRecording = false;
        _isTranscribing = false;
        _isAnalyzing = false;
        _transcribedText = '';
        _recordingStartTime = null;
      });

      // Reset all Rive inputs
      if (_isRecordInput != null) {
        _isRecordInput!.value = false;
      }

      if (_isSubmitInput != null) {
        _isSubmitInput!.value = false;
      }

      if (_isDoneInput != null) {
        _isDoneInput!.value = false;
      }
    });
  }

  Future<bool> _checkPermissions() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) {
      return true;
    }

    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  void _initAudioPlayer() {
    _audioPlayer = AudioPlayer();
  }

  Future<void> _playStartRecordingSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/record-start.mp3'));
    } catch (e) {
      // Handle error silently - don't break recording functionality if sound fails
      debugPrint('Failed to play start recording sound: $e');
    }
  }

  Future<void> _playEndRecordingSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/record-end.mp3'));
    } catch (e) {
      // Handle error silently - don't break recording functionality if sound fails
      debugPrint('Failed to play end recording sound: $e');
    }
  }

  // Show task bottom sheet and reset the taskSelected boolean
  void _showTaskBottomSheet() {
    showAddItemBottomSheet(
      context: context,
      initialTab: 'Tasks',
      onAddItem: _handleAddItem,
      onReloadEntries: () {
        // Reset the taskSelected boolean when modal is dismissed
        _resetTaskSelected();
      },
    );
    // Reset immediately after showing
    _resetTaskSelected();
  }

  // Show note bottom sheet and reset the noteSelected boolean
  void _showNoteBottomSheet() {
    showAddItemBottomSheet(
      context: context,
      initialTab: 'Notes',
      onAddItem: _handleAddItem,
      onReloadEntries: () {
        // Reset the noteSelected boolean when modal is dismissed
        _resetNoteSelected();
      },
    );
    // Reset immediately after showing
    _resetNoteSelected();
  }

  // Handle adding an item from the bottom sheet
  void _handleAddItem(String content, String type) {
    if (type == 'Notes') {
      _itemManagementService.createNoteEntry(
        noteText: content,
        selectedDate: widget.selectedDate,
        timelineEntriesByDate: widget.timelineEntriesByDate,
        onStateUpdate: widget.onStateUpdate,
      );
      _resetNoteSelected();
    } else {
      _itemManagementService.createTaskEntry(
        taskText: content,
        selectedDate: widget.selectedDate,
        timelineEntriesByDate: widget.timelineEntriesByDate,
        onStateUpdate: widget.onStateUpdate,
      );
      _resetTaskSelected();
    }
  }

  // Reset taskSelected boolean in Rive
  void _resetTaskSelected() {
    if (_taskSelectedInput != null) {
      _taskSelectedInput!.value = false;
    }
  }

  // Reset noteSelected boolean in Rive
  void _resetNoteSelected() {
    if (_noteSelectedInput != null) {
      _noteSelectedInput!.value = false;
    }
  }

  @override
  void dispose() {
    _monitoringTimer?.cancel();
    controller?.removeEventListener(_onRiveEvent);
    controller?.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (anim == null) {
      return const SizedBox(
        width: 600,
        height: 250,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return anim!;
  }
}
