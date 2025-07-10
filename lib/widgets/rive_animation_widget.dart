import 'package:flutter/material.dart';
import 'package:rive/rive.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/assembly_ai_service.dart';
import '../services/ai_analysis_service.dart';
import '../services/storage_service.dart';
import '../services/item_management_service.dart';
import '../services/guest_mode_service.dart';
import '../models/timeline_models.dart';
import '../widgets/bottom_sheets/add_item_bottom_sheet.dart';
import 'dart:io';
import 'dart:async';

class RiveAnimationWidget extends StatefulWidget {
  final Map<String, List<TimelineEntry>> timelineEntriesByDate;
  final DateTime selectedDate;
  final Function() onStateUpdate;
  final bool isGuestMode;
  final GuestModeService? guestModeService;
  final VoidCallback? onGuestRecordingCountUpdate;

  const RiveAnimationWidget({
    super.key,
    required this.timelineEntriesByDate,
    required this.selectedDate,
    required this.onStateUpdate,
    this.isGuestMode = false,
    this.guestModeService,
    this.onGuestRecordingCountUpdate,
  });

  @override
  State<RiveAnimationWidget> createState() => _RiveAnimationWidgetState();
}

class _RiveAnimationWidgetState extends State<RiveAnimationWidget> {
  // Rive controller
  StateMachineController? controller;
  RiveAnimation? anim;

  // Audio services
  // AudioRecorder is recreated for every recording cycle to prevent the
  // underlying recorder from getting stuck after the first use on some
  // devices.
  AudioRecorder _audioRecorder = AudioRecorder();
  final _assemblyAIService = AssemblyAIService();
  final _aiAnalysisService = AIAnalysisService();
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

  // Error tracking
  String? _lastError;
  bool _hasProcessingError = false;

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
    bool previousIsRecord = false; // Track previous isRecord state
    bool previousIsSubmit = false; // Track previous isSubmit state
    bool previousTaskSelected = false; // Track previous taskSelected state
    bool previousNoteSelected = false; // Track previous noteSelected state

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
      if (currentIsRecord != previousIsRecord) {
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
        previousIsRecord = currentIsRecord;
      }

      // Process recording when isSubmit becomes true (and we're recording)
      if (currentIsSubmit != previousIsSubmit) {
        if (currentIsSubmit && _isRecording) {
          // Play end recording sound immediately
          unawaited(_playEndRecordingSound());
          _stopRecording();
        }
        previousIsSubmit = currentIsSubmit;
      }

      // Handle taskSelected state changes
      if (currentTaskSelected != previousTaskSelected) {
        if (currentTaskSelected) {
          _showTaskBottomSheet();
        }
        previousTaskSelected = currentTaskSelected;
      }

      // Handle noteSelected state changes
      if (currentNoteSelected != previousNoteSelected) {
        if (currentNoteSelected) {
          _showNoteBottomSheet();
        }
        previousNoteSelected = currentNoteSelected;
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

    // Reset processing states immediately when starting a new recording
    // This ensures we don't block subsequent recordings
    if (_isTranscribing || _isAnalyzing) {
      debugPrint('🔄 Resetting processing states for new recording');
      setState(() {
        _isTranscribing = false;
        _isAnalyzing = false;
        _hasProcessingError = false;
        _lastError = null;
        _transcribedText = '';
      });

      // Reset Rive inputs
      if (_isDoneInput != null) {
        _isDoneInput!.value = false;
      }
      if (_isSubmitInput != null) {
        _isSubmitInput!.value = false;
      }
    }

    // Check guest mode recording limits
    if (widget.isGuestMode && widget.guestModeService != null) {
      final canRecord = await widget.guestModeService!.canRecord();
      if (!canRecord) {
        // Show a message that guest mode limit has been reached
        debugPrint('❌ Guest mode recording limit reached');
        return;
      }
    }

    try {
      // Check permissions
      final hasPermission = await _checkPermissions();
      if (!hasPermission) {
        debugPrint('❌ Recording permission not granted');
        return;
      }

      // Dispose any previous recorder instance and create a fresh one
      try {
        await _audioRecorder.dispose();
      } catch (_) {}
      _audioRecorder = AudioRecorder();

      // Get temporary directory for saving the recording
      final directory = await getTemporaryDirectory();
      _recordedFilePath =
          '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      debugPrint('🎙️ Starting recording to: $_recordedFilePath');

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
        _hasProcessingError = false;
        _lastError = null;
      });

      // Reset isDone to false when starting new recording
      if (_isDoneInput != null) {
        _isDoneInput!.value = false;
      }

      debugPrint('✅ Recording started successfully');
    } catch (e) {
      debugPrint('❌ Failed to start recording: $e');
      // Reset state on error
      setState(() {
        _isRecording = false;
      });
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) {
      debugPrint('⚠️ Stop recording called but not currently recording');
      return;
    }

    try {
      debugPrint('🛑 Stopping recording...');
      final path = await _audioRecorder.stop();
      debugPrint('✅ Recording stopped, path: $path');

      setState(() {
        _isRecording = false;
      });

      if (path != null) {
        // Comprehensive file validation
        await _validateAudioFile(path);
        debugPrint('✅ Audio file validation passed');

        // Start the transcription and processing workflow
        await _processRecording(path);
      } else {
        debugPrint('❌ Recording path is null');
        throw Exception('Recording failed - no file path returned');
      }

      // Dispose the recorder so we can recreate a fresh instance next time
      try {
        await _audioRecorder.dispose();
      } catch (_) {}
    } catch (e) {
      debugPrint('❌ Error stopping recording: $e');
      // Reset state on error
      setState(() {
        _isRecording = false;
        _isTranscribing = false;
        _isAnalyzing = false;
        _hasProcessingError = true;
        _lastError = e.toString();
      });

      // Show error to user
      _showErrorSnackBar('Recording failed: ${e.toString()}');

      // Set isDone to true to stop loading animation
      if (_isDoneInput != null) {
        _isDoneInput!.value = true;
      }

      // Schedule reset after error
      _scheduleStateReset();
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
        debugPrint('🎙️ Starting transcription for: $filePath');
        _transcribedText = await _assemblyAIService.transcribeAudio(filePath);
        debugPrint(
            '✅ Transcription successful. Length: ${_transcribedText.length} characters');
        debugPrint('📝 Transcribed text: $_transcribedText');

        if (_transcribedText.trim().isEmpty) {
          throw Exception(
              'Transcription returned empty text - no speech detected');
        }
      } catch (e) {
        debugPrint('❌ Transcription failed: $e');
        throw Exception('Transcription failed: $e');
      }

      // Continue with AI analysis
      await _processTranscriptionResult();
    } catch (e) {
      debugPrint('❌ Processing failed: $e');
      if (!mounted) return;

      setState(() {
        _isTranscribing = false;
        _isAnalyzing = false;
        _hasProcessingError = true;
        _lastError = e.toString();
      });

      // Show error to user
      _showErrorSnackBar('Recording processing failed: ${e.toString()}');

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

    // Step 2: Analyze with Mistral
    setState(() {
      _isTranscribing = false;
      _isAnalyzing = true;
    });

    try {
      debugPrint('🤖 Starting AI analysis with Mistral...');
      debugPrint('📝 Text to analyze: $_transcribedText');

      final result =
          await _aiAnalysisService.analyzeTranscription(_transcribedText);

      debugPrint('✅ AI analysis completed');
      debugPrint('📊 Analysis result: $result');

      if (!mounted) return;

      // Validate result structure
      if ((!result.containsKey('notes') && !result.containsKey('tasks'))) {
        throw Exception('Invalid response format from AI analysis');
      }

      // Check if we got any content
      final hasNotes =
          result['notes'] != null && (result['notes'] as List).isNotEmpty;
      final hasTasks =
          result['tasks'] != null && (result['tasks'] as List).isNotEmpty;

      if (!hasNotes && !hasTasks) {
        debugPrint('⚠️ No notes or tasks extracted from transcription');
        // Still proceed to show completion, but with a different message
        _showInfoSnackBar(
            'Audio transcribed successfully, but no actionable items were found.');
      } else {
        debugPrint(
            '📝 Found ${result['notes']?.length ?? 0} notes and ${result['tasks']?.length ?? 0} tasks');
      }

      // Step 3: Add to timeline using ItemManagementService
      debugPrint('📅 Adding items to timeline...');
      await _addItemsToTimeline(result);

      debugPrint('✅ Processing completed successfully');

      // Set isDone to true to show completion
      if (_isDoneInput != null) {
        _isDoneInput!.value = true;
        debugPrint('✅ Set isDone to true');
      }

      // --------------------------------------------------------------
      // Fast-reset the inputs one second after the DONE animation is
      // shown so the user can immediately start a new recording.  We
      // still keep the existing _scheduleStateReset() (2 s) as a
      // fallback, but this makes the UX responsive without requiring
      // an app restart.
      // --------------------------------------------------------------
      Timer(const Duration(seconds: 1), () {
        if (mounted) {
          _immediateStateReset();
        }
      });

      // Show success message
      if (hasNotes || hasTasks) {
        _showSuccessSnackBar(
            'Recording processed successfully! Added ${result['notes']?.length ?? 0} notes and ${result['tasks']?.length ?? 0} tasks.');
      }

      // Schedule reset for next recording
      _scheduleStateReset();
    } catch (e) {
      debugPrint('❌ AI analysis failed: $e');
      if (!mounted) return;

      setState(() {
        _isTranscribing = false;
        _isAnalyzing = false;
        _hasProcessingError = true;
        _lastError = e.toString();
      });

      // Show error to user
      _showErrorSnackBar('AI analysis failed: ${e.toString()}');

      // Set isDone to true even on error to stop loading animation
      if (_isDoneInput != null) {
        _isDoneInput!.value = true;
        debugPrint('✅ Set isDone to true after error');
      }

      // Schedule reset even after error
      _scheduleStateReset();
    }
  }

  Future<void> _addItemsToTimeline(Map<String, dynamic> result) async {
    try {
      debugPrint('📅 Adding items to timeline...');

      int notesAdded = 0;
      int tasksAdded = 0;

      // Add notes to timeline
      if (result['notes'] != null && result['notes'].isNotEmpty) {
        final notes = List<String>.from(result['notes']);
        debugPrint('📝 Adding ${notes.length} notes: $notes');

        for (final note in notes) {
          if (note.trim().isNotEmpty) {
            _itemManagementService.createNoteEntry(
              noteText: note.trim(),
              selectedDate: widget.selectedDate,
              timelineEntriesByDate: widget.timelineEntriesByDate,
              onStateUpdate: widget.onStateUpdate,
            );
            notesAdded++;
            debugPrint('✅ Added note: ${note.trim()}');
          }
        }
      }

      // Add tasks to timeline
      if (result['tasks'] != null && result['tasks'].isNotEmpty) {
        final tasks = List<String>.from(result['tasks']);
        debugPrint('✅ Adding ${tasks.length} tasks: $tasks');

        for (final task in tasks) {
          if (task.trim().isNotEmpty) {
            _itemManagementService.createTaskEntry(
              taskText: task.trim(),
              selectedDate: widget.selectedDate,
              timelineEntriesByDate: widget.timelineEntriesByDate,
              onStateUpdate: widget.onStateUpdate,
            );
            tasksAdded++;
            debugPrint('✅ Added task: ${task.trim()}');
          }
        }
      }

      debugPrint(
          '✅ Successfully added $notesAdded notes and $tasksAdded tasks to timeline');

      // Increment guest mode recording count if in guest mode and processing was successful
      if (widget.isGuestMode && widget.guestModeService != null) {
        await widget.guestModeService!.incrementRecordingCount();
        // Update the UI counter
        widget.onGuestRecordingCountUpdate?.call();
        debugPrint('✅ Incremented guest mode recording count');
      }
    } catch (e) {
      debugPrint('❌ Failed to add items to timeline: $e');
      throw Exception('Failed to add items to timeline: $e');
    }
  }

  // Immediately reset all states for the next recording cycle
  void _immediateStateReset() {
    if (!mounted) {
      debugPrint('⚠️ Widget not mounted, skipping immediate state reset');
      return;
    }

    debugPrint('🔄 Immediate state reset for next recording');
    // Reset all processing states
    setState(() {
      _isRecording = false;
      _isTranscribing = false;
      _isAnalyzing = false;
      _transcribedText = '';
      _recordingStartTime = null;
      _hasProcessingError = false;
      _lastError = null;
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

    // Ensure the Click input is reset so that the button can be pressed again
    if (_clickInput != null) {
      _clickInput!.value = false;
      debugPrint('🔄 Reset click input');
    }

    debugPrint('✅ Immediate state reset complete - ready for next recording');
  }

  // Reset all states for the next recording cycle
  void _scheduleStateReset() {
    debugPrint('⏰ Scheduling state reset in 2 seconds...');
    Timer(const Duration(seconds: 2), () {
      if (!mounted) {
        debugPrint('⚠️ Widget not mounted, skipping state reset');
        return;
      }

      debugPrint('🔄 Resetting all states for next recording');
      // Reset all processing states
      setState(() {
        _isRecording = false;
        _isTranscribing = false;
        _isAnalyzing = false;
        _transcribedText = '';
        _recordingStartTime = null;
        _hasProcessingError = false;
        _lastError = null;
      });

      // Reset all Rive inputs
      if (_isRecordInput != null) {
        _isRecordInput!.value = false;
        debugPrint('🔄 Reset isRecord input');
      }

      if (_isSubmitInput != null) {
        _isSubmitInput!.value = false;
        debugPrint('🔄 Reset isSubmit input');
      }

      if (_isDoneInput != null) {
        _isDoneInput!.value = false;
        debugPrint('🔄 Reset isDone input');
      }

      // Ensure the Click input is reset so that the button can be pressed again
      if (_clickInput != null) {
        _clickInput!.value = false;
        debugPrint('🔄 Reset click input');
      }

      debugPrint('✅ State reset complete - ready for next recording');
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

  // Helper methods for user feedback
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
