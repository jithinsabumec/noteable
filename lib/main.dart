import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:math'; // Import for Random and sqrt
import 'dart:async'; // Import for Timer
import 'config.dart';
import 'services/deepseek_service.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:device_info_plus/device_info_plus.dart';
import 'time_icons.dart';
import 'package:zelo/services/storage_service.dart';
import 'package:zelo/models/timeline_entry.dart' as models;
import 'package:flutter_svg/flutter_svg.dart'; // Add this import
import 'package:rive/rive.dart' as rive; // Import Rive with an alias
import 'package:flutter/services.dart'; // Import for rootBundle
import 'package:flutter/rendering.dart'; // Import for RepaintBoundary
import 'package:flutter/widgets.dart'; // Import for FlutterView

// Add a GlobalKey to keep track of the MainScreen state
final mainScreenKey = GlobalKey<_MainScreenState>();

void main() async {
  // Ensure Flutter is properly initialized with all bindings
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Rive
  await rive.RiveFile.initialize();

  // Initialize storage service
  await StorageService().initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zelo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        fontFamily: 'Geist',
      ),
      home: MainScreen(key: mainScreenKey),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  final _audioRecorder = AudioRecorder();
  final _deepseekService = DeepseekService();
  bool _isRecording = false;
  bool _isPaused = false;
  String? _recordedFilePath;
  String _transcribedText = '';
  bool _isTranscribing = false;
  bool _isUnderstanding = false; // New state for understanding phase
  bool _isAnalyzing = false;
  final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();
  DateTime _selectedDate = DateTime.now();

  // Timer for animation sequence
  Timer? _animationSequenceTimer;

  // Controller for the animation sequence
  final _animationController = GlobalKey<_AnimationSequenceControllerState>();

  // Flag to track if animations are visible or not
  bool _showAnimations = false;

  // State for drag mode
  String? _dragItemTimestamp;
  int?
      _dragItemIndex; // This will now consistently refer to the CONTENT LIST INDEX
  ItemType? _dragItemType; // NEW: To store the type of the item being dragged
  int?
      _dragItemOrderIndex; // NEW: To store the order_index of the item being dragged

  // Global variable to track drag position
  Offset _currentDragPosition = Offset.zero;

  // Use the new storage service
  final _storageService = StorageService();
  // Map to store entries by timestamp for the currently selected date
  final Map<String, List<TimelineEntry>> _timelineEntriesByDate = {};

  List<FocusNode> _sheetFocusNodes =
      []; // Moved here to be accessible for disposal

  @override
  void initState() {
    super.initState();
    // Clear any placeholder data (run this only once when testing)
    _clearPlaceholderData();
    // Load entries for the current date
    _loadEntriesForSelectedDate();

    // Preload all Rive animations to avoid delays
    _preloadRiveAnimations();
  }

  // Preload Rive animations
  Future<void> _preloadRiveAnimations() async {
    try {
      print('Preloading Rive animations');
      // List of animations to preload
      final animations = [
        'assets/animations/transcribe.riv',
        'assets/animations/understand.riv',
        'assets/animations/extract.riv',
      ];

      // Load each animation in parallel
      await Future.wait(animations.map((path) async {
        try {
          print('Preloading: $path');
          final data = await rootBundle.load(path);
          final file = rive.RiveFile.import(data);
          print('Preloaded: $path');
        } catch (e) {
          print('Error preloading Rive animation $path: $e');
        }
      }));

      print('All Rive animations preloaded');
    } catch (e) {
      print('Error in preloading Rive animations: $e');
    }
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    // Dispose all focus nodes from the last shown bottom sheet
    for (var node in _sheetFocusNodes) {
      node.dispose();
    }
    _sheetFocusNodes.clear();
    _animationSequenceTimer?.cancel(); // Cancel animation sequence timer
    super.dispose();
  }

  // Clear placeholder data from storage
  Future<void> _clearPlaceholderData() async {
    await _storageService.clearAll();
  }

  // Load entries for the selected date
  Future<void> _loadEntriesForSelectedDate() async {
    final entries = _storageService.getEntriesForDate(_selectedDate);
    setState(() {
      // Group entries by timestamp for display
      _timelineEntriesByDate.clear();

      // Convert each entry to UI TimelineEntry
      for (final entry in entries) {
        final timestamp = entry.timeString;
        final isDaytime = _isTimestamp24HourDaytime(entry.timestamp);

        if (entry.type == models.EntryType.note) {
          // Handle notes
          if (!_timelineEntriesByDate.containsKey(timestamp)) {
            final newUiEntry = TimelineEntry(
              timestamp: timestamp,
              isDaytime: isDaytime,
              notes: [entry.content],
              tasks: [],
              itemOrder: [], // Initialize empty
            );
            newUiEntry.itemOrder.add(TimelineItemRef(
                type: ItemType.note, index: 0)); // Add ref for the note
            _timelineEntriesByDate[timestamp] = [newUiEntry];
          } else {
            // Find appropriate entry or create new one
            bool found = false;
            for (var uiEntry in _timelineEntriesByDate[timestamp]!) {
              uiEntry.notes.add(entry.content);
              found = true;
              break;
            }

            if (!found) {
              _timelineEntriesByDate[timestamp]!.add(TimelineEntry(
                timestamp: timestamp,
                isDaytime: isDaytime,
                notes: [entry.content],
                tasks: [],
                itemOrder: [], // Initialize empty
              ));
              _timelineEntriesByDate[timestamp]!.first.itemOrder.add(
                  TimelineItemRef(
                      type: ItemType.note, index: 0)); // Add ref for the note
            }
          }
        } else {
          // Handle tasks
          if (!_timelineEntriesByDate.containsKey(timestamp)) {
            _timelineEntriesByDate[timestamp] = [
              TimelineEntry(
                timestamp: timestamp,
                isDaytime: isDaytime,
                notes: [],
                tasks: [
                  TaskItem(
                    task: entry.content,
                    completed: entry.completed,
                  ),
                ],
                itemOrder: [], // Initialize empty
              )
            ];
            _timelineEntriesByDate[timestamp]!.first.itemOrder.add(
                TimelineItemRef(
                    type: ItemType.task, index: 0)); // Add ref for the task
          } else {
            // Find appropriate entry or create new one
            bool found = false;
            for (var uiEntry in _timelineEntriesByDate[timestamp]!) {
              uiEntry.tasks.add(
                TaskItem(
                  task: entry.content,
                  completed: entry.completed,
                ),
              );
              found = true;
              break;
            }

            if (!found) {
              _timelineEntriesByDate[timestamp]!.add(TimelineEntry(
                timestamp: timestamp,
                isDaytime: isDaytime,
                notes: [],
                tasks: [
                  TaskItem(
                    task: entry.content,
                    completed: entry.completed,
                  ),
                ],
                itemOrder: [], // Initialize empty
              ));
              _timelineEntriesByDate[timestamp]!.first.itemOrder.add(
                  TimelineItemRef(
                      type: ItemType.task, index: 0)); // Add ref for the task
            }
          }
        }
      }
    });
  }

  // Helper method to check if a timestamp is during the day or night (24-hour format)
  bool _isTimestamp24HourDaytime(DateTime time) {
    final hour = time.hour;
    return hour >= 6 && hour < 18;
  }

  Future<bool> _checkPermissions() async {
    // Always check microphone permission
    final micStatus = await Permission.microphone.status;

    // For Android 11+, we need MANAGE_EXTERNAL_STORAGE permission
    // For Android 10 and below, we need regular storage permission
    bool needsManageStorage = false;
    bool needsRegularStorage = false;

    if (Platform.isAndroid) {
      try {
        // Use device info plugin to get Android version
        final androidInfo = await _deviceInfoPlugin.androidInfo;
        final sdkVersion = androidInfo.version.sdkInt;

        needsManageStorage = sdkVersion >= 30; // Android 11+
        needsRegularStorage = sdkVersion < 30; // Android 10 and below
      } catch (e) {
        // If there's an error determining the version, request both permissions
        // Better to ask for more permissions than to have insufficient access
        print('Error determining Android version: $e');
        needsRegularStorage = true;
      }
    } else {
      // For non-Android platforms, use regular storage permission
      needsRegularStorage = true;
    }

    // Check storage permissions based on Android version
    final regularStorageStatus = needsRegularStorage
        ? await Permission.storage.status
        : PermissionStatus.granted;
    final manageStorageStatus = needsManageStorage
        ? await Permission.manageExternalStorage.status
        : PermissionStatus.granted;

    // Consider storage permission granted if either regular storage is granted (Android 10-)
    // or manage storage is granted (Android 11+)
    final storagePermissionGranted =
        (needsRegularStorage && regularStorageStatus.isGranted) ||
            (needsManageStorage && manageStorageStatus.isGranted);

    // If already granted, return true immediately
    if (micStatus.isGranted && storagePermissionGranted) {
      return true;
    }

    // Build permission message based on Android version
    String permissionMessage =
        'Zelo needs microphone access to record your voice';
    if (needsManageStorage) {
      permissionMessage += ' and storage access to save recordings';
    } else if (needsRegularStorage) {
      permissionMessage += ' and storage access to save recordings';
    }

    // Show explanation dialog if permissions weren't previously granted
    if (micStatus.isDenied ||
        (needsRegularStorage && regularStorageStatus.isDenied) ||
        (needsManageStorage && manageStorageStatus.isDenied)) {
      // Show explanation before requesting
      final bool shouldRequest = await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('Permissions Required'),
              content: Text(
                  '$permissionMessage. These permissions are necessary for the app to function properly.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Continue'),
                ),
              ],
            ),
          ) ??
          false;

      if (!shouldRequest) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Permissions are required to use the recording feature'),
            duration: Duration(seconds: 3),
          ),
        );
        return false;
      }
    }

    // Handle permanently denied cases first
    if (micStatus.isPermanentlyDenied ||
        (needsRegularStorage && regularStorageStatus.isPermanentlyDenied) ||
        (needsManageStorage && manageStorageStatus.isPermanentlyDenied)) {
      return _handlePermanentlyDeniedPermissions(
          needsRegularStorage, needsManageStorage);
    }

    // Request permissions
    final newMicStatus = await Permission.microphone.request();

    // Request appropriate storage permissions based on Android version
    PermissionStatus newRegularStorageStatus = PermissionStatus.granted;
    PermissionStatus newManageStorageStatus = PermissionStatus.granted;

    if (needsRegularStorage) {
      newRegularStorageStatus = await Permission.storage.request();
    }

    if (needsManageStorage) {
      // For MANAGE_EXTERNAL_STORAGE, we need to send users to settings on Android 11+
      newManageStorageStatus = await Permission.manageExternalStorage.request();

      // If not granted, try to send user to settings
      if (!newManageStorageStatus.isGranted) {
        final shouldOpenSettings = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('Special Permission Required'),
                content: const Text(
                    'For Android 11 and above, Zelo needs special storage permission. '
                    'Please enable "Allow management of all files" for Zelo in the next screen.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Open Settings'),
                  ),
                ],
              ),
            ) ??
            false;

        if (shouldOpenSettings) {
          await openAppSettings();
          // We need to check the permission again after returning from settings
          newManageStorageStatus =
              await Permission.manageExternalStorage.status;
        }
      }
    }

    // Check for permanently denied after request
    if (newMicStatus.isPermanentlyDenied ||
        (needsRegularStorage && newRegularStorageStatus.isPermanentlyDenied) ||
        (needsManageStorage && newManageStorageStatus.isPermanentlyDenied)) {
      return _handlePermanentlyDeniedPermissions(
          needsRegularStorage, needsManageStorage);
    }

    // Check for regular denied
    final storagePermissionDenied =
        (needsRegularStorage && newRegularStorageStatus.isDenied) ||
            (needsManageStorage && newManageStorageStatus.isDenied);

    if (newMicStatus.isDenied || storagePermissionDenied) {
      String deniedMessage = 'Microphone';
      if (storagePermissionDenied) {
        deniedMessage += ' and storage';
      }
      deniedMessage += ' permissions are required to record';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(deniedMessage),
          duration: const Duration(seconds: 3),
        ),
      );
      return false;
    }

    // Storage permission is granted if either regular storage or manage storage is granted
    final newStoragePermissionGranted =
        (needsRegularStorage && newRegularStorageStatus.isGranted) ||
            (needsManageStorage && newManageStorageStatus.isGranted);

    // All permissions granted
    return newMicStatus.isGranted && newStoragePermissionGranted;
  }

  Future<bool> _handlePermanentlyDeniedPermissions(
      bool needsRegularStorage, bool needsManageStorage) async {
    String permissionMessage = 'Microphone';
    if (needsRegularStorage || needsManageStorage) {
      permissionMessage += ' and storage';
    }
    permissionMessage += ' permissions are required for this app to work.';

    final result = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Permissions Required'),
            content: Text(
                '$permissionMessage Please enable them in your device settings.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ) ??
        false;

    if (result) {
      await openAppSettings();
      // After returning from settings, check permissions again
      final micStatus = await Permission.microphone.status;

      // Check appropriate storage permissions based on Android version
      PermissionStatus regularStorageStatus = PermissionStatus.granted;
      PermissionStatus manageStorageStatus = PermissionStatus.granted;

      if (needsRegularStorage) {
        regularStorageStatus = await Permission.storage.status;
      }

      if (needsManageStorage) {
        manageStorageStatus = await Permission.manageExternalStorage.status;
      }

      // Storage permission is granted if either regular storage or manage storage is granted
      final storagePermissionGranted =
          (needsRegularStorage && regularStorageStatus.isGranted) ||
              (needsManageStorage && manageStorageStatus.isGranted);

      if (micStatus.isGranted && storagePermissionGranted) {
        return true;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permissions are still not granted'),
            duration: Duration(seconds: 3),
          ),
        );
        return false;
      }
    }

    return false;
  }

  // Add a new recording directly
  void _startRecording() async {
    print("_startRecording called - Opening recording page");
    _toggleFabExpanded(); // Close the menu

    // Prepare for seamless transition by setting up states
    // This prevents flash of original UI when returning from RecordingPage
    setState(() {
      _showAnimations = false; // Don't show animations yet
      _isTranscribing = false;
      _isUnderstanding = false;
      _isAnalyzing = false;
    });

    // Navigate to the recording page
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            RecordingPage(),
        transitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );

    // Handle result from recording page if needed
    if (result != null &&
        result['success'] == true &&
        result['filePath'] != null) {
      // When we return from recording, the animation has already started there
      // Just continue it here without any visual interruption
      setState(() {
        _isTranscribing = true;
        _isUnderstanding = false;
        _isAnalyzing = false;
        _showAnimations = true; // Show animations immediately
      });

      // Ensure the animation controller shows the first animation
      if (_animationController.currentState != null) {
        _animationController.currentState!.showAnimation('transcribe');
      }

      print("Recording completed - Continuing animation sequence");

      // Start the animation sequence with a small delay to ensure smooth transition
      await Future.delayed(Duration(milliseconds: 50));
      _startProcessingAnimationSequence("");

      // Start actual transcription in the background
      await _transcribeAudio(result['filePath']);
    } else {
      // If recording was cancelled, make sure no animations are showing
      _animationSequenceTimer?.cancel();
      setState(() {
        _showAnimations = false;
        _isTranscribing = false;
        _isUnderstanding = false;
        _isAnalyzing = false;
      });
    }
  }

  Future<void> _pauseRecording() async {
    // This method in _MainScreenState was incorrectly trying to control Rive's _clickInput.
    // The Rive animation is self-contained in RecordingPage.
    // If _MainScreenState initiated a recording that it needs to pause via its own _audioRecorder instance,
    // it should do so here. However, the primary recording flow seems to have moved to RecordingPage.
    // For now, we'll ensure it doesn't crash due to _clickInput.
    print(
        "_MainScreenState._pauseRecording called. Current recording logic primarily in RecordingPage.");
    try {
      // Example: if _MainScreenState still had its own recording session it could manage
      // This is a placeholder, as the main recording is in RecordingPage
      if (await _audioRecorder.isRecording() ||
          await _audioRecorder.isPaused()) {
        if (_isPaused) {
          // await _audioRecorder.resume(); // If _MainScreenState's recorder was active
          print(
              "_MainScreenState: Attempting to resume its own recorder (if any).");
        } else {
          // await _audioRecorder.pause(); // If _MainScreenState's recorder was active
          print(
              "_MainScreenState: Attempting to pause its own recorder (if any).");
        }
        // setState(() => _isPaused = !_isPaused); // Update _MainScreenState's own _isPaused
      }
    } catch (e) {
      print('_MainScreenState: Error in _pauseRecording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error in _MainScreenState._pauseRecording: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Start a timed animation sequence
  void _startProcessingAnimationSequence(String text) {
    // Cancel any existing timer first
    _animationSequenceTimer?.cancel();

    // Show animations and set the first animation type - don't need setState here
    // as the state should already be set correctly from _startRecording
    if (!_showAnimations) {
      setState(() {
        _showAnimations = true;
        _isTranscribing = true;
        _isUnderstanding = false;
        _isAnalyzing = false;
      });
    }

    print(
        "Starting/continuing animation sequence: transcribe -> understand -> extract");

    // Start with the transcribe animation if not already showing
    if (_animationController.currentState != null) {
      _animationController.currentState!.showAnimation('transcribe');
    }

    // Start a sequence of timers for the animations
    // First 5 seconds: Transcribing (this animation is already showing from RecordingPage)
    _animationSequenceTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        print("Animation transition: transcribe -> understand");

        // Update the state for compatibility
        setState(() {
          _isTranscribing = false;
          _isUnderstanding = true;
          _isAnalyzing = false;
        });

        // Show the understand animation without any fade
        if (_animationController.currentState != null) {
          _animationController.currentState!.showAnimation('understand');
        }

        // Next 5 seconds: Understanding
        _animationSequenceTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) {
            print("Animation transition: understand -> extract");

            // Update the state for compatibility
            setState(() {
              _isTranscribing = false;
              _isUnderstanding = false;
              _isAnalyzing = true;
            });

            // Show the extract animation without any fade
            if (_animationController.currentState != null) {
              _animationController.currentState!.showAnimation('extract');
            }

            // Start the actual processing - use the most recent transcribed text
            // rather than the original text passed to this method
            _performActualTextProcessing(
                _transcribedText.isNotEmpty ? _transcribedText : text);
          }
        });
      }
    });
  }

  // Perform the actual text processing after animations
  Future<void> _performActualTextProcessing(String text) async {
    try {
      final result = await _deepseekService.analyzeTranscription(text);

      // Create a new timeline entry with current timestamp
      final now = DateTime.now();
      final hour = now.hour > 12
          ? now.hour - 12
          : now.hour == 0
              ? 12
              : now.hour;
      final minute = now.minute.toString().padLeft(2, '0');
      final ampm = now.hour >= 12 ? 'PM' : 'AM';
      final timestamp = '$hour:$minute $ampm';
      final isDaytime = now.hour >= 6 && now.hour < 18;

      setState(() {
        // Extract notes and tasks from the LLM result
        List<String> notes = [];
        List<TaskItem> tasks = [];

        if (result['notes'] != null && result['notes'].isNotEmpty) {
          notes = List<String>.from(result['notes']);
        }

        if (result['tasks'] != null && result['tasks'].isNotEmpty) {
          final taskStrings = List<String>.from(result['tasks']);
          tasks = taskStrings
              .map((taskText) => TaskItem(
                    task: taskText,
                    completed: false,
                  ))
              .toList();
        }

        // Create a new timeline entry
        _timelineEntriesByDate[timestamp] = [
          TimelineEntry(
              timestamp: timestamp,
              isDaytime: isDaytime,
              notes: notes,
              tasks: tasks,
              itemOrder: [] // Initialize and then populate below
              )
        ];
        // Explicitly build itemOrder after notes and tasks are set for the new entry from DeepSeek
        if (_timelineEntriesByDate[timestamp]!.isNotEmpty) {
          _timelineEntriesByDate[timestamp]!.first.rebuildItemOrder();
        }

        _isAnalyzing = false;

        // Only now, hide the animations after processing is complete
        _showAnimations = false;
      });

      // Show a snackbar with the results
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your recording has been processed'),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      print('Error analyzing with DeepSeek: $e');
      setState(() {
        _isAnalyzing = false;
        _showAnimations = false; // Hide animations on error
      });
      // Show error message to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error processing recording: ${e.toString()}'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _transcribeAudio(String filePath) async {
    try {
      // We don't need to start animation sequence here anymore
      // as it's already started in _startRecording

      // Upload the file to AssemblyAI
      const uploadUrl = 'https://api.assemblyai.com/v2/upload';
      final file = File(filePath);
      final bytes = await file.readAsBytes();

      print('Uploading file: $filePath');
      print('File size: ${bytes.length} bytes');

      final uploadResponse = await http.post(
        Uri.parse(uploadUrl),
        headers: {
          'authorization': Config.assemblyAIKey,
          'content-type': 'audio/m4a',
        },
        body: bytes,
      );

      print('Upload response status: ${uploadResponse.statusCode}');
      print('Upload response body: ${uploadResponse.body}');

      if (uploadResponse.statusCode != 200) {
        throw Exception('Failed to upload audio file: ${uploadResponse.body}');
      }

      final uploadData = json.decode(uploadResponse.body);
      final audioUrl = uploadData['upload_url'];

      // Start transcription
      const transcriptUrl = 'https://api.assemblyai.com/v2/transcript';
      final transcriptResponse = await http.post(
        Uri.parse(transcriptUrl),
        headers: {
          'authorization': Config.assemblyAIKey,
          'content-type': 'application/json',
        },
        body: json.encode({
          'audio_url': audioUrl,
          'speech_model': 'universal',
        }),
      );

      print('Transcript response status: ${transcriptResponse.statusCode}');
      print('Transcript response body: ${transcriptResponse.body}');

      if (transcriptResponse.statusCode != 200) {
        throw Exception(
            'Failed to start transcription: ${transcriptResponse.body}');
      }

      final transcriptData = json.decode(transcriptResponse.body);
      final transcriptId = transcriptData['id'];

      // Poll for transcription completion
      String transcribedText = '';
      while (true) {
        final statusResponse = await http.get(
          Uri.parse('https://api.assemblyai.com/v2/transcript/$transcriptId'),
          headers: {
            'authorization': Config.assemblyAIKey,
          },
        );

        if (statusResponse.statusCode != 200) {
          throw Exception(
              'Failed to get transcription status: ${statusResponse.body}');
        }

        final statusData = json.decode(statusResponse.body);
        print('Transcription status: ${statusData['status']}');

        if (statusData['status'] == 'completed') {
          transcribedText = statusData['text'];
          break;
        } else if (statusData['status'] == 'error') {
          throw Exception('Transcription failed: ${statusData['error']}');
        }

        await Future.delayed(const Duration(seconds: 3));
      }

      // Set the transcribed text - the animation sequence is already running
      // so we don't need to restart it
      _transcribedText = transcribedText;
    } catch (e) {
      print('Error transcribing audio: $e');
      // Cancel animation sequence and hide animations
      _animationSequenceTimer?.cancel();
      setState(() {
        _transcribedText = 'Error transcribing audio: $e';
        _showAnimations = false; // Hide animations
        _isTranscribing = false;
        _isUnderstanding = false;
        _isAnalyzing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error transcribing audio: ${e.toString()}'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _analyzeWithDeepSeek(String text) async {
    if (text.isEmpty) return;

    // Now this method is obsolete as we handle everything in the animation sequence
    // Just start the animation sequence
    _startProcessingAnimationSequence(text);
  }

  Future<void> _stopRecording() async {
    try {
      if (_isRecording) {
        final path = await _audioRecorder.stop();
        setState(() {
          _isRecording = false;
          _isPaused = false;
        });
        print('Recording saved to: $path');

        // Start transcription
        if (path != null) {
          // Start animation sequence immediately
          _startProcessingAnimationSequence("");

          // Then start actual transcription in the background
          await _transcribeAudio(path);
        }
      }
    } catch (e) {
      print('Error stopping recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error stopping recording: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // Update the WeekdaySelector to reload data when date changes
  Widget _buildWeekdaySelector() {
    final now = DateTime.now();
    final today = now.weekday; // 1 for Monday, 7 for Sunday

    // Calculate the start of the week (Monday)
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));

    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (index) {
        final dayDate = startOfWeek.add(Duration(days: index));
        final isSelectedDay = _selectedDate.year == dayDate.year &&
            _selectedDate.month == dayDate.month &&
            _selectedDate.day == dayDate.day;
        final isCurrentDay = now.year == dayDate.year &&
            now.month == dayDate.month &&
            now.day == dayDate.day;

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedDate = dayDate;
            });
            _loadEntriesForSelectedDate();
          },
          child: Container(
            width: 40,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Text(
                  weekdays[index],
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600, // SemiBold
                    fontFamily: 'Geist',
                    color: isSelectedDay
                        ? const Color(0xFF191919)
                        : const Color(0xFF9D9D9D),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelectedDay
                        ? const Color(0xFFEEEEEE)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '${dayDate.day}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600, // SemiBold
                      fontFamily: 'GeistMono',
                      color: isSelectedDay
                          ? const Color(0xFF191919)
                          : const Color(0xFF9D9D9D),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // Format the selected date as required (keeping this for other parts of the app)
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final selectedDay = DateTime(date.year, date.month, date.day);

    if (selectedDay == today) {
      return 'Today';
    } else if (selectedDay == yesterday) {
      return 'Yesterday';
    } else {
      // Format as "Month Date"
      final months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December'
      ];
      return '${months[date.month - 1]} ${date.day}';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if any loading state is active
    final bool isLoading = _showAnimations;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // Main content
            Padding(
              padding: const EdgeInsets.only(
                  bottom: 24.0, top: 16.0, left: 24.0, right: 24.0),
              child: LayoutBuilder(
                // Added LayoutBuilder
                builder:
                    (BuildContext context, BoxConstraints viewportConstraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      // Added ConstrainedBox
                      constraints: BoxConstraints(
                          minHeight: viewportConstraints.maxHeight),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Static "today" text and weekday row
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Static "today" text
                                const Text(
                                  'today',
                                  style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Geist',
                                    color: Color(0xFF171717),
                                    height: 1.0,
                                    letterSpacing: -0.72,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                // Weekday selector
                                _buildWeekdaySelector(),
                              ],
                            ),
                          ),

                          // Timeline entries
                          ..._buildTimelineEntries(),
                        ], // End of Column
                      ), // End of ConstrainedBox
                    ), // End of SingleChildScrollView
                  ); // End of LayoutBuilder
                }, // End of LayoutBuilder builder
              ), // End of LayoutBuilder
            ),

            // Animation sequence controller - always there but only visible when needed
            if (_showAnimations)
              Positioned.fill(
                child: AnimationSequenceController(key: _animationController),
              ),

            // Expandable FAB at the bottom right corner - only show when not loading
            if (!isLoading)
              Positioned(
                right: 24, // Changed from 16
                bottom: 100, // Changed from 16
                child: _buildExpandableFAB(),
              ),
          ],
        ),
      ),
    );
  }

  // Build the timeline entries from the new data structure
  List<Widget> _buildTimelineEntries() {
    if (_timelineEntriesByDate.isEmpty) {
      return [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Text(
              'No entries for this day',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontFamily: 'Geist',
              ),
            ),
          ),
        )
      ];
    }

    final sortedTimestamps = _timelineEntriesByDate.keys.toList()
      ..sort((a, b) => _compareTimestamps(b, a));

    return sortedTimestamps.map((timestamp) {
      final entries = _timelineEntriesByDate[timestamp]!;
      return _buildTimelineBox(entries.first, timestamp);
    }).toList();
  }

  // Compare timestamps for sorting
  int _compareTimestamps(String a, String b) {
    final aParts = a.split(' ');
    final bParts = b.split(' ');

    final aTime = aParts[0].split(':');
    final bTime = bParts[0].split(':');

    int aHour = int.parse(aTime[0]);
    int bHour = int.parse(bTime[0]);

    // Convert to 24-hour format for comparison
    if (aParts[1] == 'PM' && aHour < 12) aHour += 12;
    if (aParts[1] == 'AM' && aHour == 12) aHour = 0;
    if (bParts[1] == 'PM' && bHour < 12) bHour += 12;
    if (bParts[1] == 'AM' && bHour == 12) bHour = 0;

    if (aHour != bHour) return aHour - bHour;

    int aMinute = int.parse(aTime[1]);
    int bMinute = int.parse(bTime[1]);

    return aMinute - bMinute;
  }

  // Build a single timeline entry box
  Widget _buildTimelineBox(TimelineEntry entry, String timestamp) {
    print(
        'Building timeline box for $timestamp with ${entry.itemOrder.length} items in itemOrder. Notes: ${entry.notes.length}, Tasks: ${entry.tasks.length}');

    // Get appropriate time icon based on timestamp
    final timeIcon = TimeIcons.getTimeIcon(entry.timestamp);

    List<Widget> contentWidgets = [];

    if (entry.itemOrder.isEmpty) {
      // If itemOrder is empty, but notes or tasks might exist (e.g. data inconsistency),
      // try to rebuild it. This is a fallback.
      if (entry.notes.isNotEmpty || entry.tasks.isNotEmpty) {
        print(
            'Warning: itemOrder is empty but notes/tasks exist for $timestamp. Rebuilding itemOrder.');
        // This rebuilds notes first, then tasks. If a mixed order was intended
        // to be preserved from storage and itemOrder was lost, this won't restore it.
        entry.rebuildItemOrder();
      }
    }

    for (int i = 0; i < entry.itemOrder.length; i++) {
      final itemRef = entry.itemOrder[i];
      final orderIndex = i; // This is the item's index in itemOrder

      if (itemRef.type == ItemType.note) {
        if (itemRef.index < entry.notes.length) {
          final note = entry.notes[itemRef.index];
          contentWidgets.add(
            _buildDraggableNote(note, timestamp, itemRef.index, orderIndex),
          );
        } else {
          print(
              'Error: Stale note reference in itemOrder for $timestamp. Ref: $itemRef, Notes length: ${entry.notes.length}');
        }
      } else if (itemRef.type == ItemType.task) {
        if (itemRef.index < entry.tasks.length) {
          final task = entry.tasks[itemRef.index];
          contentWidgets.add(
            _buildDraggableTask(task, timestamp, itemRef.index, orderIndex),
          );
        } else {
          print(
              'Error: Stale task reference in itemOrder for $timestamp. Ref: $itemRef, Tasks length: ${entry.tasks.length}');
        }
      }
    }

    // Show message if no content (and itemOrder was indeed empty)
    if (contentWidgets.isEmpty) {
      contentWidgets.add(
        Container(
          margin: const EdgeInsets.only(left: 4.0, right: 4.0, bottom: 4.0),
          padding: const EdgeInsets.all(16.0),
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: const Color(0xFFE1E1E1),
              width: 1,
            ),
          ),
          child: const Center(
            child: Text('Drop items here'),
          ),
        ),
      );
    }

    // Wrap the entire box in a DragTarget
    return DragTarget<Map<String, dynamic>>(
      onWillAccept: (data) => true,
      onAccept: (data) {
        print('Dropping on timeline $timestamp');
        _handleItemDrop(data, timestamp);
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          margin: const EdgeInsets.only(bottom: 16.0),
          decoration: BoxDecoration(
            color: candidateData.isNotEmpty
                ? const Color(0xFFE5E5E5) // Slightly darker when dragging over
                : const Color(0xFFEEEEEE),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: candidateData.isNotEmpty
                  ? const Color(0xFFD0D0D0)
                  : const Color(0xFFE4E4E4),
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x19000000),
                blurRadius: 17.60,
                offset: Offset(0, 4),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Timestamp header
              Padding(
                padding: const EdgeInsets.only(
                    top: 4.0, bottom: 4.0, left: 4.0, right: 4.0),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: timeIcon,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      entry.timestamp,
                      style: const TextStyle(
                        fontSize: 14,
                        fontFamily: 'GeistMono',
                        color: Color(0xFF666666),
                      ),
                    ),
                  ],
                ),
              ),

              // Content widgets (individual cards for each item)
              if (candidateData.isNotEmpty && contentWidgets.isEmpty)
                // Show drop indicator when dragging over an empty box
                Container(
                  margin: const EdgeInsets.all(4.0),
                  padding: const EdgeInsets.all(16.0),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.blue.shade300,
                      width: 1,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      'Drop here',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
              else
                Column(
                  children: contentWidgets,
                ),
            ],
          ),
        );
      },
    );
  }

  // Build a draggable note item
  Widget _buildDraggableNote(
      String note, String timestamp, int contentListIndex, int orderIndex) {
    final bool isDragMode = _dragItemTimestamp == timestamp &&
        _dragItemIndex == contentListIndex &&
        _dragItemType ==
            ItemType
                .note; // Use _dragItemIndex and _dragItemType for isDragMode

    if (isDragMode) {
      return Container(
        margin: const EdgeInsets.only(left: 4.0, right: 4.0, bottom: 4.0),
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Colors.blue.shade400,
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            // Content part (not draggable)
            _buildNoteItem(note, isFirstItem: true),

            // Draggable handle on the right
            Positioned(
              top: 0,
              right: 0,
              child: Draggable<Map<String, dynamic>>(
                data: {
                  'type': 'note',
                  'content': note,
                  'source_timestamp': timestamp,
                  'content_list_index':
                      contentListIndex, // Index in the notes list
                  'order_index': orderIndex, // Index in the itemOrder list
                  'dragPosition': Offset.zero,
                },
                feedback: Material(
                  elevation: 8.0,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: MediaQuery.of(context).size.width - 80,
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.blue.shade400,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Text(
                      note,
                      style: const TextStyle(
                        fontSize: 16,
                        fontFamily: 'Geist',
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                onDragUpdate: (details) {
                  setState(() {
                    _currentDragPosition = details.globalPosition;
                  });
                },
                childWhenDragging: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade200,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(6),
                    ),
                  ),
                  child: Icon(
                    Icons.drag_indicator,
                    color: Colors.white.withOpacity(0.5),
                    size: 16,
                  ),
                ),
                onDragCompleted: () {
                  // Reset drag mode when done
                  setState(() {
                    _dragItemTimestamp = null;
                    _dragItemIndex = null;
                    // _dragItemIsTask = null; // Deprecated
                    _dragItemType = null;
                    _dragItemOrderIndex = null;
                  });
                },
                onDraggableCanceled: (_, __) {
                  // Reset drag mode if canceled
                  setState(() {
                    _dragItemTimestamp = null;
                    _dragItemIndex = null;
                    // _dragItemIsTask = null; // Deprecated
                    _dragItemType = null;
                    _dragItemOrderIndex = null;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade400,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(6),
                    ),
                  ),
                  child: Icon(
                    Icons.drag_indicator,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onLongPress: () {
        _showItemOptions(
          context: context,
          timestamp: timestamp,
          contentListIndex: contentListIndex, // Pass contentListIndex
          orderIndex: orderIndex, // Pass orderIndex
          itemType: ItemType.note,
          content: note,
        );
      },
      child: DragTarget<Map<String, dynamic>>(
        onWillAccept: (data) => true, // Accept any draggable item
        onAccept: (data) {
          final RenderBox box = context.findRenderObject() as RenderBox;
          final topHalf = box.size.height / 2;
          final position = box.globalToLocal(_currentDragPosition);
          final insertPosition = position.dy < topHalf ? 'before' : 'after';

          // Get the TimelineEntry for the current timestamp
          final TimelineEntry? currentEntry =
              _timelineEntriesByDate[timestamp]?.first;
          if (currentEntry == null) {
            print(
                "Error: Could not find TimelineEntry for timestamp $timestamp in _buildDraggableNote's DragTarget");
            return;
          }

          // Find the target item's TimelineItemRef using contentListIndex and ItemType.note
          // This assumes contentListIndex is unique for notes within this entry.
          // A more robust way would be to use the orderIndex if the DragTarget is directly for an item from itemOrder.
          // Since this DragTarget is part of _buildDraggableNote, 'orderIndex' (passed as parameter) is the actual order index of this note.

          _handleItemDropOnExistingItem(
            data, // This is the droppedItemData
            timestamp, // Target timestamp is the timestamp of this note's container
            {
              'type': 'note', // Type of the target item (this note)
              'content_list_index':
                  contentListIndex, // Content list index of this note
              'order_index': orderIndex, // Order index of this note
              'position': insertPosition,
            },
          );
        },
        builder: (context, candidateData, rejectedData) {
          // Determine which half of the box is being hovered over
          Widget snapIndicator = const SizedBox.shrink();

          if (candidateData.isNotEmpty) {
            // Create a snap indicator based on the hover position
            snapIndicator = Builder(builder: (context) {
              final RenderBox? box = context.findRenderObject() as RenderBox?;
              if (box == null || !box.hasSize) return const SizedBox.shrink();

              final topHalf = box.size.height / 2;
              final position = box.globalToLocal(_currentDragPosition);
              final isTopHalf = position.dy < topHalf;

              return Positioned(
                top: isTopHalf ? -1.5 : null,
                bottom: isTopHalf ? null : -1.5,
                left: 4,
                right: 4,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade500,
                    borderRadius: BorderRadius.circular(1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        blurRadius: 3,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              );
            });
          }

          return Stack(
            children: [
              Container(
                margin:
                    const EdgeInsets.only(left: 4.0, right: 4.0, bottom: 4.0),
                width: double.infinity,
                padding: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: candidateData.isNotEmpty
                      ? Colors.blue.shade50
                      : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: candidateData.isNotEmpty
                        ? Colors.blue.shade200
                        : const Color(0xFFE1E1E1),
                    width: 1,
                  ),
                ),
                child: _buildNoteItem(note, isFirstItem: true),
              ),
              if (candidateData.isNotEmpty) snapIndicator,
            ],
          );
        },
      ),
    );
  }

  // Build a draggable task item
  Widget _buildDraggableTask(
      TaskItem task, String timestamp, int contentListIndex, int orderIndex) {
    final bool isDragMode = _dragItemTimestamp == timestamp &&
        _dragItemIndex == contentListIndex &&
        _dragItemType ==
            ItemType
                .task; // Use _dragItemIndex and _dragItemType for isDragMode

    if (isDragMode) {
      return Container(
        margin: const EdgeInsets.only(left: 4.0, right: 4.0, bottom: 4.0),
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Colors.green.shade400,
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            // Content part (not draggable)
            _buildTaskItem(task, isFirstItem: true),

            // Draggable handle on the right
            Positioned(
              top: 0,
              right: 0,
              child: Draggable<Map<String, dynamic>>(
                data: {
                  'type': 'task',
                  'content': task
                      .task, // Or pass the whole TaskItem if needed by drop handler for content
                  'completed': task.completed,
                  'source_timestamp': timestamp,
                  'content_list_index':
                      contentListIndex, // Index in the tasks list
                  'order_index': orderIndex, // Index in the itemOrder list
                  'dragPosition': Offset.zero,
                },
                feedback: Material(
                  elevation: 8.0,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: MediaQuery.of(context).size.width - 80,
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.green.shade400,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: task.completed ? Colors.black : Colors.white,
                            borderRadius: BorderRadius.circular(6.0),
                            border: Border.all(
                              width: 1.5,
                              color: task.completed
                                  ? Colors.black
                                  : const Color(0xFFC0C0C0),
                            ),
                          ),
                          child: task.completed
                              ? Center(
                                  child: CustomPaint(
                                    size: const Size(10, 7.5),
                                    painter: CheckmarkPainter(),
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            task.task,
                            style: TextStyle(
                              fontSize: 16,
                              fontFamily: 'Geist',
                              fontWeight: FontWeight.w500,
                              decoration: task.completed
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor:
                                  task.completed ? Colors.grey.shade400 : null,
                              color: task.completed
                                  ? Colors.grey.shade400
                                  : Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                onDragUpdate: (details) {
                  setState(() {
                    _currentDragPosition = details.globalPosition;
                  });
                },
                childWhenDragging: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade200,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(6),
                    ),
                  ),
                  child: Icon(
                    Icons.drag_indicator,
                    color: Colors.white.withOpacity(0.5),
                    size: 16,
                  ),
                ),
                onDragCompleted: () {
                  // Reset drag mode when done
                  setState(() {
                    _dragItemTimestamp = null;
                    _dragItemIndex = null;
                    // _dragItemIsTask = null; // Deprecated
                    _dragItemType = null;
                    _dragItemOrderIndex = null;
                  });
                },
                onDraggableCanceled: (_, __) {
                  // Reset drag mode if canceled
                  setState(() {
                    _dragItemTimestamp = null;
                    _dragItemIndex = null;
                    // _dragItemIsTask = null; // Deprecated
                    _dragItemType = null;
                    _dragItemOrderIndex = null;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade400,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(6),
                    ),
                  ),
                  child: Icon(
                    Icons.drag_indicator,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onLongPress: () {
        _showItemOptions(
          context: context,
          timestamp: timestamp,
          contentListIndex: contentListIndex,
          orderIndex: orderIndex,
          itemType: ItemType.task,
          content: task.task,
          completed: task.completed,
        );
      },
      child: DragTarget<Map<String, dynamic>>(
        onWillAccept: (data) => true, // Accept any draggable item
        onAccept: (data) {
          final RenderBox box = context.findRenderObject() as RenderBox;
          final topHalf = box.size.height / 2;
          final position = box.globalToLocal(_currentDragPosition);
          final insertPosition = position.dy < topHalf ? 'before' : 'after';

          _handleItemDropOnExistingItem(
            data,
            timestamp,
            {
              'type': 'task',
              'index': contentListIndex,
              'order_index': 0,
              'position': insertPosition,
            },
          );
        },
        builder: (context, candidateData, rejectedData) {
          // Determine which half of the box is being hovered over
          Widget snapIndicator = const SizedBox.shrink();

          if (candidateData.isNotEmpty) {
            // Create a snap indicator based on the hover position
            snapIndicator = Builder(builder: (context) {
              final RenderBox? box = context.findRenderObject() as RenderBox?;
              if (box == null || !box.hasSize) return const SizedBox.shrink();

              final topHalf = box.size.height / 2;
              final position = box.globalToLocal(_currentDragPosition);
              final isTopHalf = position.dy < topHalf;

              return Positioned(
                top: isTopHalf ? -1.5 : null,
                bottom: isTopHalf ? null : -1.5,
                left: 4,
                right: 4,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.green.shade500,
                    borderRadius: BorderRadius.circular(1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.3),
                        blurRadius: 3,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              );
            });
          }

          return Stack(
            children: [
              Container(
                margin:
                    const EdgeInsets.only(left: 4.0, right: 4.0, bottom: 4.0),
                width: double.infinity,
                padding: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: candidateData.isNotEmpty
                      ? Colors.green.shade50
                      : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: candidateData.isNotEmpty
                        ? Colors.green.shade200
                        : const Color(0xFFE1E1E1),
                    width: 1,
                  ),
                ),
                child: _buildTaskItem(task, isFirstItem: true),
              ),
              if (candidateData.isNotEmpty) snapIndicator,
            ],
          );
        },
      ),
    );
  }

  // Show drag instructions when user selects drag mode
  void _showDragInstructions() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Long press and drag to move the item to another position or time'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  // Show options when long pressing a note or task
  void _showItemOptions({
    required BuildContext context,
    required String timestamp,
    required int contentListIndex, // Changed from 'index'
    required int orderIndex, // Added
    required ItemType itemType, // Changed from 'isTask'
    required String content,
    bool? completed,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Important for keyboard visibility
      backgroundColor: Colors.white, // Set bottom sheet background to white
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.blue),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditDialog(
                      context: context,
                      timestamp: timestamp,
                      contentListIndex: contentListIndex,
                      orderIndex: orderIndex,
                      itemType: itemType,
                      content: content,
                      completed: completed,
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Delete'),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteItem(timestamp, orderIndex,
                        itemType); // Use orderIndex and itemType
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.swap_vert, color: Colors.green),
                  title: const Text('Move or Reorder'),
                  subtitle: const Text('Drag to another time or position'),
                  onTap: () {
                    Navigator.pop(context);
                    // Enable drag mode for this specific item
                    setState(() {
                      _dragItemTimestamp = timestamp;
                      _dragItemIndex = contentListIndex;
                      _dragItemOrderIndex = orderIndex;
                      _dragItemType = itemType;
                      // _dragItemIsTask = isTask; // Deprecated
                    });
                    _showDragInstructions();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Show edit dialog for a note or task
  void _showEditDialog({
    required BuildContext context,
    required String timestamp,
    required int contentListIndex, // Changed from 'index'
    required int orderIndex, // Added
    required ItemType itemType, // Changed from 'isTask'
    required String content,
    bool? completed,
  }) {
    final TextEditingController controller =
        TextEditingController(text: content);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(itemType == ItemType.note ? 'Edit Note' : 'Edit Task'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLines: itemType == ItemType.note ? 1 : 5,
                decoration: InputDecoration(
                  hintText: itemType == ItemType.note ? 'Note' : 'Task',
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              if (itemType == ItemType.task)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Row(
                    children: [
                      Checkbox(
                        value: completed,
                        onChanged: (bool? value) {
                          setState(() {
                            completed = value ?? false;
                          });
                        },
                      ),
                      const Text('Completed'),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _updateItem(
                  timestamp: timestamp,
                  orderIndex: orderIndex, // Pass orderIndex
                  itemType: itemType, // Pass itemType
                  newContent: controller.text,
                  newCompleted: completed,
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  // Update a note or task
  void _updateItem({
    required String timestamp,
    required int
        orderIndex, // Changed from index, now refers to itemOrder index
    required ItemType itemType, // Changed from isTask
    required String newContent,
    bool? newCompleted,
  }) {
    if (newContent.isEmpty) return;

    setState(() {
      if (itemType == ItemType.note) {
        _timelineEntriesByDate[timestamp]![orderIndex] = TimelineEntry(
          timestamp: timestamp,
          isDaytime: _timelineEntriesByDate[timestamp]![orderIndex].isDaytime,
          notes: [newContent],
          tasks: _timelineEntriesByDate[timestamp]![orderIndex].tasks,
          itemOrder: _timelineEntriesByDate[timestamp]![orderIndex].itemOrder,
        );
      } else {
        _timelineEntriesByDate[timestamp]![orderIndex] = TimelineEntry(
          timestamp: timestamp,
          isDaytime: _timelineEntriesByDate[timestamp]![orderIndex].isDaytime,
          notes: _timelineEntriesByDate[timestamp]![orderIndex].notes,
          tasks: [
            TaskItem(
              task: newContent,
              completed: newCompleted ??
                  _timelineEntriesByDate[timestamp]![orderIndex]
                      .tasks[orderIndex]
                      .completed,
            ),
          ],
          itemOrder: _timelineEntriesByDate[timestamp]![orderIndex].itemOrder,
        );
      }
    });
  }

  // Delete a note or task
  void _deleteItem(String timestamp, int orderIndex, ItemType itemType) {
    // Use orderIndex and itemType
    setState(() {
      if (itemType == ItemType.note) {
        _timelineEntriesByDate[timestamp]!.removeAt(orderIndex);
      } else {
        _timelineEntriesByDate[timestamp]![orderIndex] = TimelineEntry(
          timestamp: timestamp,
          isDaytime: _timelineEntriesByDate[timestamp]![orderIndex].isDaytime,
          notes: [],
          tasks: [],
          itemOrder: _timelineEntriesByDate[timestamp]![orderIndex].itemOrder,
        );
      }

      // Remove the timestamp entry if it's now empty
      if (_timelineEntriesByDate[timestamp]!.isEmpty) {
        _timelineEntriesByDate.remove(timestamp);
      }
    });
  }

  // Handle dropping item onto another item (for re-ordering)
  void _handleItemDropOnExistingItem(
    Map<String, dynamic> droppedItemData,
    String targetTimestamp,
    Map<String, dynamic> targetItemData,
  ) {
    final sourceTimestamp = droppedItemData['source_timestamp'] as String;
    final sourceContentListIndex =
        droppedItemData['content_list_index'] as int?; // Made nullable
    final sourceTypeString = droppedItemData['type'] as String? ?? 'note';
    final sourceType =
        sourceTypeString == 'note' ? ItemType.note : ItemType.task;
    final sourceOrderIndex = droppedItemData['order_index'] as int?;

    final targetContentListIndex =
        targetItemData['content_list_index'] as int?; // Made nullable
    final targetTypeString = targetItemData['type'] as String? ?? 'note';
    final targetType =
        targetTypeString == 'note' ? ItemType.note : ItemType.task;
    final targetOrderIndex =
        targetItemData['order_index'] as int?; // Made nullable
    final insertPosition = targetItemData['position'] as String;

    if (sourceOrderIndex == null) {
      print('Error: sourceOrderIndex is null. Drag data is likely missing it.');
      return;
    }
    if (sourceContentListIndex == null) {
      // Added check for sourceContentListIndex
      print(
          'Error: sourceContentListIndex is null. Drag data is likely missing it.');
      return;
    }
    if (targetOrderIndex == null) {
      // Added check for targetOrderIndex
      print(
          'Error: targetOrderIndex is null. Target data is likely missing it.');
      return;
    }
    // targetContentListIndex might be legitimately null if dropping on a timeline box, but not here.
    // However, for _handleItemDropOnExistingItem, targetContentListIndex is expected.
    if (targetContentListIndex == null) {
      print('Error: targetContentListIndex is null for drop on existing item.');
      return;
    }

    print(
        '_handleItemDropOnExistingItem: $sourceType from $sourceTimestamp (contentIdx: $sourceContentListIndex, orderIdx: $sourceOrderIndex) -> onto $targetType (contentIdx: $targetContentListIndex, orderIdx: $targetOrderIndex) in $targetTimestamp, pos: $insertPosition');

    if (!_timelineEntriesByDate.containsKey(sourceTimestamp) ||
        _timelineEntriesByDate[sourceTimestamp]!.isEmpty) {
      print('Error: Source timeline $sourceTimestamp not found or empty.');
      return;
    }
    final sourceEntry = _timelineEntriesByDate[sourceTimestamp]!.first;

    if (!_timelineEntriesByDate.containsKey(targetTimestamp)) {
      print('Error: Target timeline $targetTimestamp not found. Creating it.');
      final isDaytime = _isTimestampDaytime(targetTimestamp);
      _timelineEntriesByDate[targetTimestamp] = [
        TimelineEntry(
          timestamp: targetTimestamp,
          isDaytime: isDaytime,
          notes: [],
          tasks: [],
          itemOrder: [],
        )
      ];
    }
    final targetEntry = _timelineEntriesByDate[targetTimestamp]!.first;

    setState(() {
      try {
        if (sourceOrderIndex < 0 ||
            sourceOrderIndex >= sourceEntry.itemOrder.length) {
          print(
              'Error: sourceOrderIndex $sourceOrderIndex is out of bounds for sourceEntry.itemOrder with length ${sourceEntry.itemOrder.length}');
          return;
        }
        final TimelineItemRef movedItemOrderRef =
            sourceEntry.itemOrder[sourceOrderIndex];

        if (movedItemOrderRef.type != sourceType ||
            movedItemOrderRef.index != sourceContentListIndex) {
          print(
              'Error: Mismatch in _handleItemDropOnExistingItem. Draggable: $sourceType[$sourceContentListIndex], Found: ${movedItemOrderRef.type}[${movedItemOrderRef.index}]');
          return;
        }

        final ItemType currentMovedItemType = movedItemOrderRef.type;
        final int currentMovedItemContentListIndex = movedItemOrderRef.index;
        dynamic movedItemContent;

        if (currentMovedItemType == ItemType.note) {
          if (currentMovedItemContentListIndex < 0 ||
              currentMovedItemContentListIndex >= sourceEntry.notes.length) {
            print(
                'Error: note index $currentMovedItemContentListIndex out of bounds for notes list length ${sourceEntry.notes.length}');
            return;
          }
          movedItemContent =
              sourceEntry.notes.removeAt(currentMovedItemContentListIndex);
        } else {
          if (currentMovedItemContentListIndex < 0 ||
              currentMovedItemContentListIndex >= sourceEntry.tasks.length) {
            print(
                'Error: task index $currentMovedItemContentListIndex out of bounds for tasks list length ${sourceEntry.tasks.length}');
            return;
          }
          movedItemContent =
              sourceEntry.tasks.removeAt(currentMovedItemContentListIndex);
        }
        print('  Extracted content: $movedItemContent');

        sourceEntry.itemOrder.removeAt(sourceOrderIndex);
        print(
            '  Removed from source itemOrder at order index: $sourceOrderIndex');

        for (final ref in sourceEntry.itemOrder) {
          if (ref.type == currentMovedItemType &&
              ref.index > currentMovedItemContentListIndex) {
            ref.index--;
          }
        }
        print('  Updated internal list indices in source itemOrder');

        int finalTargetOrderIndex = targetOrderIndex!;
        if (sourceTimestamp == targetTimestamp &&
            sourceOrderIndex < targetOrderIndex) {
          finalTargetOrderIndex--;
        }
        if (insertPosition == 'after') {
          finalTargetOrderIndex++;
        }
        finalTargetOrderIndex = math.min(
            math.max(0, finalTargetOrderIndex), targetEntry.itemOrder.length);
        print(
            '  Calculated finalTargetOrderIndex for targetEntry.itemOrder: $finalTargetOrderIndex');

        int newContentListIndexInTarget;
        if (currentMovedItemType == ItemType.note) {
          newContentListIndexInTarget = targetEntry.notes.length;
          targetEntry.notes.add(movedItemContent as String);
        } else {
          newContentListIndexInTarget = targetEntry.tasks.length;
          targetEntry.tasks.add(movedItemContent as TaskItem);
        }
        print(
            '  Added content to target list at new index $newContentListIndexInTarget');

        final TimelineItemRef newTargetItemOrderRef = TimelineItemRef(
          type: currentMovedItemType,
          index: newContentListIndexInTarget,
        );
        targetEntry.itemOrder
            .insert(finalTargetOrderIndex, newTargetItemOrderRef);
        print(
            '  Inserted new ref ($newTargetItemOrderRef) into targetEntry.itemOrder at order index: $finalTargetOrderIndex');

        if (sourceEntry.notes.isEmpty &&
            sourceEntry.tasks.isEmpty &&
            sourceEntry.itemOrder.isEmpty) {
          _timelineEntriesByDate.remove(sourceTimestamp);
          print('  Removed empty source timeline: $sourceTimestamp');
        }
        print('DropOnItem successful.');
      } catch (e, s) {
        print('Error in _handleItemDropOnExistingItem: $e\n$s');
      }
    });
  }

  // Handle dropping item onto a timeline box (not a specific item)
  void _handleItemDrop(Map<String, dynamic> data, String targetTimestamp) {
    final sourceTimestamp = data['source_timestamp'] as String;
    final sourceContentListIndex =
        data['content_list_index'] as int?; // Made nullable
    final sourceItemTypeFromDraggableString = data['type'] as String? ?? 'note';
    final sourceItemTypeFromDraggable =
        sourceItemTypeFromDraggableString == 'note'
            ? ItemType.note
            : ItemType.task;
    final sourceOrderIndex = data['order_index'] as int?;

    if (sourceOrderIndex == null) {
      print(
          'Error: sourceOrderIndex is null in _handleItemDrop. Drag data is likely missing it.');
      return;
    }
    if (sourceContentListIndex == null) {
      // Added check for sourceContentListIndex
      print(
          'Error: sourceContentListIndex is null in _handleItemDrop. Drag data is likely missing it.');
      return;
    }

    print(
        'DropOnTimelineBox: $sourceItemTypeFromDraggable from $sourceTimestamp (contentIdx: $sourceContentListIndex, orderIdx: $sourceOrderIndex) -> to $targetTimestamp');

    if (!_timelineEntriesByDate.containsKey(sourceTimestamp) ||
        _timelineEntriesByDate[sourceTimestamp]!.isEmpty) {
      print('Error: Source timeline $sourceTimestamp not found or empty.');
      return;
    }
    final sourceEntry = _timelineEntriesByDate[sourceTimestamp]!.first;

    if (!_timelineEntriesByDate.containsKey(targetTimestamp)) {
      print('Target timeline $targetTimestamp not found. Creating it.');
      final isDaytime = _isTimestampDaytime(targetTimestamp);
      _timelineEntriesByDate[targetTimestamp] = [
        TimelineEntry(
          timestamp: targetTimestamp,
          isDaytime: isDaytime,
          notes: [],
          tasks: [],
          itemOrder: [],
        )
      ];
    }
    final targetEntry = _timelineEntriesByDate[targetTimestamp]!.first;

    setState(() {
      try {
        // 1. Extract item from source
        if (sourceOrderIndex < 0 ||
            sourceOrderIndex >= sourceEntry.itemOrder.length) {
          print(
              'Error: sourceOrderIndex $sourceOrderIndex is out of bounds for sourceEntry.itemOrder with length ${sourceEntry.itemOrder.length}');
          return;
        }
        final TimelineItemRef movedItemOrderRef =
            sourceEntry.itemOrder[sourceOrderIndex];

        if (movedItemOrderRef.type != sourceItemTypeFromDraggable ||
            movedItemOrderRef.index != sourceContentListIndex) {
          print(
              'Error: Mismatch between draggable data and sourceEntry.itemOrder[$sourceOrderIndex] in _handleItemDrop. Draggable: $sourceItemTypeFromDraggable[$sourceContentListIndex], Found: ${movedItemOrderRef.type}[${movedItemOrderRef.index}]');
          return;
        }

        final ItemType actualMovedItemType = movedItemOrderRef.type;
        final int actualMovedItemContentListIndex = movedItemOrderRef.index;
        dynamic movedItemContent;

        if (actualMovedItemType == ItemType.note) {
          if (actualMovedItemContentListIndex < 0 ||
              actualMovedItemContentListIndex >= sourceEntry.notes.length) {
            print('Error: note index out of bounds in _handleItemDrop');
            return;
          }
          movedItemContent =
              sourceEntry.notes.removeAt(actualMovedItemContentListIndex);
        } else {
          // ItemType.task
          if (actualMovedItemContentListIndex < 0 ||
              actualMovedItemContentListIndex >= sourceEntry.tasks.length) {
            print('Error: task index out of bounds in _handleItemDrop');
            return;
          }
          movedItemContent =
              sourceEntry.tasks.removeAt(actualMovedItemContentListIndex);
        }
        print(
            '  Extracted content: $movedItemContent of type $actualMovedItemType from content list index $actualMovedItemContentListIndex');

        sourceEntry.itemOrder.removeAt(sourceOrderIndex);
        print(
            '  Removed from source itemOrder at order index: $sourceOrderIndex');

        for (final ref in sourceEntry.itemOrder) {
          if (ref.type == actualMovedItemType &&
              ref.index > actualMovedItemContentListIndex) {
            ref.index--;
          }
        }
        print(
            '  Updated internal list indices in source itemOrder for type $actualMovedItemType');

        // 2. Add item to target content list (always at the end)
        int newContentListIndexInTarget;
        if (actualMovedItemType == ItemType.note) {
          newContentListIndexInTarget = targetEntry.notes.length;
          targetEntry.notes.add(movedItemContent as String);
          print(
              '  Added note content to targetEntry.notes at new list index $newContentListIndexInTarget');
        } else {
          // ItemType.task
          newContentListIndexInTarget = targetEntry.tasks.length;
          targetEntry.tasks.add(movedItemContent as TaskItem);
          print(
              '  Added task content to targetEntry.tasks at new list index $newContentListIndexInTarget');
        }

        // 3. Create new TimelineItemRef and append to targetEntry.itemOrder
        final TimelineItemRef newTargetItemOrderRef = TimelineItemRef(
          type:
              actualMovedItemType, // Use the actual type of the item that was moved
          index: newContentListIndexInTarget,
        );
        targetEntry.itemOrder.add(newTargetItemOrderRef); // Append to the end
        print(
            '  Appended new ref ($newTargetItemOrderRef) to targetEntry.itemOrder');

        // 4. Cleanup source entry if empty
        if (sourceEntry.notes.isEmpty &&
            sourceEntry.tasks.isEmpty &&
            sourceEntry.itemOrder.isEmpty) {
          _timelineEntriesByDate.remove(sourceTimestamp);
          print('  Removed empty source timeline: $sourceTimestamp');
        }
        print('DropOnTimelineBox successful.');
      } catch (e, s) {
        print('Error in _handleItemDrop: $e\n$s');
      }
    });
  }

  // Helper method to check if a timestamp is during the day or night
  bool _isTimestampDaytime(String timestamp) {
    // Parse hours from "hh:mm AM/PM" format
    final parts = timestamp.split(' ');
    final timeParts = parts[0].split(':');
    int hour = int.parse(timeParts[0]);

    // Convert to 24-hour format
    if (parts[1] == 'PM' && hour < 12) {
      hour += 12;
    } else if (parts[1] == 'AM' && hour == 12) {
      hour = 0;
    }

    // Daytime is between 6 AM and 6 PM
    return hour >= 6 && hour < 18;
  }

  // Build a single note item
  Widget _buildNoteItem(String note, {bool isFirstItem = false}) {
    return Container(
      padding: EdgeInsets.only(
        left: 12.0,
        right: 12.0,
        top: isFirstItem ? 8.0 : 0.0,
        bottom: 8.0,
      ),
      child: Text(
        note,
        style: const TextStyle(
          fontSize: 16,
          fontFamily: 'Geist',
          fontWeight: FontWeight.w500,
          height: 24 / 16,
          color: Colors.black,
        ),
      ),
    );
  }

  // Build a single task item with checkbox
  Widget _buildTaskItem(TaskItem task, {bool isFirstItem = false}) {
    return Container(
      padding: EdgeInsets.only(
        left: 12.0,
        right: 12.0,
        top: isFirstItem ? 8.0 : 0.0,
        bottom: 8.0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                task.completed = !task.completed;
              });
            },
            child: Container(
              margin: const EdgeInsets.only(top: 5),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: task.completed ? Colors.black : Colors.white,
                borderRadius: BorderRadius.circular(6.0),
                border: Border.all(
                  width: 1.5,
                  color:
                      task.completed ? Colors.black : const Color(0xFFC0C0C0),
                ),
              ),
              child: task.completed
                  ? Center(
                      child: CustomPaint(
                        size: const Size(10, 7.5),
                        painter: CheckmarkPainter(),
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  task.completed = !task.completed;
                });
              },
              child: Text(
                task.task,
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: 'Geist',
                  fontWeight: FontWeight.w500,
                  decoration:
                      task.completed ? TextDecoration.lineThrough : null,
                  decorationColor: task.completed ? Colors.grey.shade400 : null,
                  color: task.completed ? Colors.grey.shade400 : Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build the expandable FAB with recording and adding options
  Widget _buildExpandableFAB() {
    // If currently recording, show the recording controls
    if (_isRecording) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            onPressed: _pauseRecording,
            tooltip: _isPaused ? 'Resume' : 'Pause',
            backgroundColor: Colors.orange,
            child: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
          ),
          const SizedBox(width: 16),
          FloatingActionButton(
            onPressed: _stopRecording,
            tooltip: 'Stop',
            backgroundColor: Colors.red,
            child: const Icon(Icons.stop),
          ),
        ],
      );
    }

    // Otherwise show the expandable FAB
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Note button (visible when expanded)
        if (_isFabExpanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: MaterialButton(
              onPressed: () {
                print("Note button pressed");
                _addNote();
              },
              elevation: 0, // Set to 0 to use our custom shadow
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(width: 2, color: const Color(0xFFE1E1E1)),
              ),
              color: Colors.white,
              padding: EdgeInsets.zero,
              minWidth: 62,
              height: 62,
              child: Container(
                width: 62,
                height: 62,
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  shadows: [
                    BoxShadow(
                      color: Color(
                          0x15000000), // Reduced opacity from 0x26 to 0x15
                      blurRadius: 10.0, // Reduced from 17.60
                      offset: Offset(0, 3), // Reduced from Offset(0, 4)
                      spreadRadius: 0,
                    )
                  ],
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/notes.svg',
                    width: 22,
                    height: 22,
                  ),
                ),
              ),
            ),
          ),

        // Task button (visible when expanded)
        if (_isFabExpanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: MaterialButton(
              onPressed: () {
                print("Task button pressed");
                _addTask();
              },
              elevation: 0, // Set to 0 to use our custom shadow
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(width: 2, color: const Color(0xFFE1E1E1)),
              ),
              color: Colors.white,
              padding: EdgeInsets.zero,
              minWidth: 62,
              height: 62,
              child: Container(
                width: 62,
                height: 62,
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  shadows: [
                    BoxShadow(
                      color: Color(
                          0x15000000), // Reduced opacity from 0x26 to 0x15
                      blurRadius: 10.0, // Reduced from 17.60
                      offset: Offset(0, 3), // Reduced from Offset(0, 4)
                      spreadRadius: 0,
                    )
                  ],
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/tasks.svg',
                    width: 28,
                    height: 28,
                  ),
                ),
              ),
            ),
          ),

        // Record button (visible when expanded)
        if (_isFabExpanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: MaterialButton(
              onPressed: () {
                print("Record button pressed");
                _startRecording();
              },
              elevation: 0, // Set to 0 to use our custom shadow
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(width: 2, color: Colors.white),
              ),
              padding: EdgeInsets.zero,
              minWidth: 62,
              height: 62,
              color: Colors.transparent,
              child: Container(
                width: 62,
                height: 62,
                decoration: ShapeDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-0.00, -0.00),
                    end: Alignment(1.00, 1.00),
                    colors: [const Color(0xFFFD6F00), const Color(0xFFFC3505)],
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  shadows: [
                    BoxShadow(
                      color: Color(
                          0x15000000), // Reduced opacity from 0x26 to 0x15
                      blurRadius: 10.0, // Reduced from 17.60
                      offset: Offset(0, 3), // Reduced from Offset(0, 4)
                      spreadRadius: 0,
                    )
                  ],
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/record_icon.svg',
                    width: 24,
                    height: 24,
                  ),
                ),
              ),
            ),
          ),

        // Main FAB (plus/close)
        MaterialButton(
          onPressed: _toggleFabExpanded,
          elevation: 0, // Set to 0 to use our custom shadow
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: EdgeInsets.zero,
          minWidth: 62,
          height: 62,
          child: Container(
            width: 62,
            height: 62,
            padding: const EdgeInsets.all(12),
            decoration: ShapeDecoration(
              gradient: LinearGradient(
                begin: Alignment(-0.00, -0.00),
                end: Alignment(1.00, 1.00),
                colors: [const Color(0xFF413F3F), const Color(0xFF0C0C0C)],
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              shadows: [
                BoxShadow(
                  color: Color(0x15000000), // Reduced opacity from 0x26 to 0x15
                  blurRadius: 10.0, // Reduced from 17.60
                  offset: Offset(0, 3), // Reduced from Offset(0, 4)
                  spreadRadius: 0,
                )
              ],
            ),
            child: Center(
              child: AnimatedRotation(
                turns: _isFabExpanded ? 0.125 : 0, // 0.125 turns = 45 degrees
                duration: const Duration(milliseconds: 200),
                curve: Curves.fastOutSlowIn,
                child: CustomPaint(
                  size: const Size(24, 24),
                  painter: PlusIconPainter(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // State variable for FAB expansion
  bool _isFabExpanded = false;

  // Toggle FAB expansion
  void _toggleFabExpanded() {
    setState(() {
      _isFabExpanded = !_isFabExpanded;
    });
  }

  // Add a new note directly
  void _addNote() {
    print("_addNote called - Opening note bottom sheet");
    _toggleFabExpanded(); // Close the menu
    _showAddNoteBottomSheet(initialTab: 'Notes'); // Specify 'Notes' tab
  }

  // Show the bottom sheet for adding a new note or task
  void _showAddNoteBottomSheet({String initialTab = 'Notes'}) {
    // Dispose any previous sheet's focus nodes before creating new ones
    for (var node in _sheetFocusNodes) {
      node.dispose();
    }
    _sheetFocusNodes.clear();

    List<TextEditingController> _textControllers = [TextEditingController()];
    _sheetFocusNodes
        .add(FocusNode()); // Add initial focus node to the class-level list

    String selectedType = initialTab;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sheetFocusNodes.isNotEmpty) {
        _sheetFocusNodes.first.requestFocus();
      }
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          // Re-added StatefulBuilder
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Segmented Control (Notes/Tasks) - with animated background
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final containerWidth = constraints.maxWidth;
                        final gap = 4.0; // 4 pixel gap between tabs
                        final tabWidth = (containerWidth - 8 - gap) /
                            2; // Account for container padding and gap

                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEEEEE),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE4E4E4)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x19000000),
                                blurRadius: 17.60,
                                offset: Offset(0, 4),
                                spreadRadius: 0,
                              )
                            ],
                          ),
                          height: 46, // Fixed height for the container
                          child: Stack(
                            children: [
                              // Animated background that slides
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                                left: selectedType == 'Notes'
                                    ? 0
                                    : tabWidth +
                                        gap, // Add gap for Tasks position
                                top: 0,
                                bottom: 0,
                                width: tabWidth, // Equal width for both tabs
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 5,
                                        offset: const Offset(0, 2),
                                      )
                                    ],
                                  ),
                                ),
                              ),

                              // Tab buttons
                              Row(
                                children: <Widget>[
                                  // Notes Tab - Exactly half width
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        setModalState(() {
                                          selectedType = 'Notes';
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            SvgPicture.asset(
                                              'assets/icons/notes.svg',
                                              width: 18,
                                              height: 18,
                                              colorFilter: ColorFilter.mode(
                                                selectedType == 'Notes'
                                                    ? Colors.black
                                                    : Colors.grey.shade600,
                                                BlendMode.srcIn,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Notes',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontFamily: 'Geist',
                                                color: selectedType == 'Notes'
                                                    ? Colors.black
                                                    : Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Tasks Tab - Exactly half width
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        setModalState(() {
                                          selectedType = 'Tasks';
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            SvgPicture.asset(
                                              'assets/icons/tasks.svg',
                                              width: 18,
                                              height: 18,
                                              colorFilter: ColorFilter.mode(
                                                selectedType == 'Tasks'
                                                    ? Colors.black
                                                    : Colors.grey.shade600,
                                                BlendMode.srcIn,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Tasks',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontFamily: 'Geist',
                                                color: selectedType == 'Tasks'
                                                    ? Colors.black
                                                    : Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    // Text Field(s) and "Add new note" button - Completely refactored structure
                    Column(
                      children: [
                        const SizedBox(
                            height:
                                24), // Add 24px space between toggle and text

                        // Title - Different text based on selected type
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            selectedType == 'Notes'
                                ? "What's on your mind?"
                                : "What's important today?",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Geist',
                              color: Color(0xFF4B4B4B),
                            ),
                          ),
                        ),

                        const SizedBox(
                            height:
                                12), // Add 12px space between text and text box

                        // ListView for text fields
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _textControllers.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: EdgeInsets.only(bottom: 8.0),
                              child: TextField(
                                key: ValueKey(
                                    'textfield_${index}_${_textControllers[index].hashCode}'), // Unique key for each field
                                controller: _textControllers[index],
                                focusNode: _sheetFocusNodes[
                                    index], // Use class-level list
                                minLines: 3,
                                maxLines: 5,
                                // autofocus: index == 0, // Replaced by manual requestFocus
                                decoration: InputDecoration(
                                  hintText: selectedType == 'Notes'
                                      ? "I\'ve been thinking about..."
                                      : "I need to...",
                                  hintStyle:
                                      const TextStyle(color: Color(0xFFB3B3B3)),
                                  fillColor: const Color(0xFFF9F9F9),
                                  filled: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFE1E1E1),
                                      width: 1.0,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFE1E1E1),
                                      width: 1.0,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFE1E1E1),
                                      width: 1.0,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

                        // Add new note button
                        Padding(
                          padding: const EdgeInsets.only(
                              top: 0), // Removed the top padding
                          child: Center(
                            child: TextButton(
                              onPressed: () {
                                print(
                                    "Add new note button pressed! Current count: ${_textControllers.length}");
                                setModalState(() {
                                  final newController = TextEditingController();
                                  final newFocusNode = FocusNode();
                                  _textControllers.add(newController);
                                  _sheetFocusNodes.add(
                                      newFocusNode); // Add to class-level list
                                  print(
                                      "Added new controller. New count: ${_textControllers.length}");

                                  Future.delayed(
                                      const Duration(milliseconds: 50), () {
                                    newFocusNode.requestFocus();
                                  });
                                });
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical:
                                      6, // Exact 12px horizontal, 6px vertical
                                ),
                                backgroundColor: const Color(0xFFFFFFFF),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  side: const BorderSide(
                                      color: Color(0xFFE1E1E1), width: 1.0),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  const Icon(Icons.add,
                                      color: Color(0xFF858585), size: 20),
                                  const SizedBox(width: 6),
                                  Text(
                                    selectedType == 'Notes'
                                        ? 'Add new note'
                                        : 'Add new task',
                                    style: const TextStyle(
                                      color: Color(0xFF848484),
                                      fontFamily: 'Geist',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 48),

                    // Bottom Action Buttons
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.pop(context); // Close bottom sheet
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Geist'),
                              foregroundColor: const Color(0xFF4B4B4B),
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Close'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              bool anEntryWasAdded = false;
                              for (var controller in _textControllers) {
                                if (controller.text.isNotEmpty) {
                                  if (selectedType == 'Notes') {
                                    _createNoteEntry(controller.text);
                                  } else {
                                    _createTaskEntry(controller.text);
                                  }
                                  anEntryWasAdded = true;
                                }
                              }

                              if (anEntryWasAdded) {
                                Navigator.pop(context); // Close bottom sheet
                              } else {
                                // Optionally show a message if all fields are empty
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Please enter a ${selectedType.toLowerCase().substring(0, selectedType.length - 1)} to add.'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Geist'),
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(selectedType == 'Notes'
                                ? 'Add note'
                                : 'Add task'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16), // Padding at the bottom
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Add a new task directly
  void _addTask() {
    print("_addTask called - Opening task bottom sheet");
    _toggleFabExpanded(); // Close the menu
    _showAddNoteBottomSheet(
        initialTab:
            'Tasks'); // Call same bottom sheet but with 'Tasks' pre-selected
  }

  // Create a new note entry with the current timestamp
  void _createNoteEntry(String noteText) {
    final now = DateTime.now();
    final hour = now.hour > 12
        ? now.hour - 12
        : now.hour == 0
            ? 12
            : now.hour;
    final minute = now.minute.toString().padLeft(2, '0');
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final timestamp = '$hour:$minute $ampm';
    final isDaytime = now.hour >= 6 && now.hour < 18;

    // Create a new timeline entry for storage
    final storageEntry = models.TimelineEntry(
      id: _storageService.generateId(),
      content: noteText,
      timestamp: now,
      type: models.EntryType.note,
      completed: false,
    );

    // Save to storage
    _storageService.saveEntry(storageEntry);

    // Update UI
    setState(() {
      final existingUiEntry = _timelineEntriesByDate[timestamp]?.first;

      if (existingUiEntry != null) {
        // Add to existing entry for this timestamp
        final newNoteIndex = existingUiEntry.notes.length;
        existingUiEntry.notes.add(noteText);
        existingUiEntry.itemOrder
            .add(TimelineItemRef(type: ItemType.note, index: newNoteIndex));
      } else {
        // Create new entry for this timestamp
        final newNoteIndex = 0;
        final newUiEntry = TimelineEntry(
          timestamp: timestamp,
          isDaytime: isDaytime,
          notes: [noteText],
          tasks: [],
          itemOrder: [
            TimelineItemRef(type: ItemType.note, index: newNoteIndex)
          ],
        );
        _timelineEntriesByDate[timestamp] = [newUiEntry];
      }
    });
  }

  // Create a new task entry with the current timestamp
  void _createTaskEntry(String taskText) {
    final now = DateTime.now();
    final hour = now.hour > 12
        ? now.hour - 12
        : now.hour == 0
            ? 12
            : now.hour;
    final minute = now.minute.toString().padLeft(2, '0');
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final timestamp = '$hour:$minute $ampm';
    final isDaytime = now.hour >= 6 && now.hour < 18;

    // Create a new timeline entry for storage
    final storageEntry = models.TimelineEntry(
      id: _storageService.generateId(),
      content: taskText,
      timestamp: now,
      type: models.EntryType.task,
      completed: false,
    );

    // Save to storage
    _storageService.saveEntry(storageEntry);

    // Update UI
    setState(() {
      final existingUiEntry = _timelineEntriesByDate[timestamp]?.first;

      if (existingUiEntry != null) {
        // Add to existing entry for this timestamp
        final newTaskIndex = existingUiEntry.tasks.length;
        existingUiEntry.tasks.add(TaskItem(
          task: taskText,
          completed: false,
        ));
        existingUiEntry.itemOrder
            .add(TimelineItemRef(type: ItemType.task, index: newTaskIndex));
      } else {
        // Create new entry for this timestamp
        final newTaskIndex = 0;
        final newUiEntry = TimelineEntry(
          timestamp: timestamp,
          isDaytime: isDaytime,
          notes: [],
          tasks: [
            TaskItem(
              task: taskText,
              completed: false,
            )
          ],
          itemOrder: [
            TimelineItemRef(type: ItemType.task, index: newTaskIndex)
          ],
        );
        _timelineEntriesByDate[timestamp] = [newUiEntry];
      }
    });
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

// New data classes for the redesigned timeline
class TimelineEntry {
  final String timestamp;
  final bool isDaytime;
  final List<String> notes;
  final List<TaskItem> tasks;
  final List<TimelineItemRef> itemOrder;

  TimelineEntry({
    required this.timestamp,
    required this.isDaytime,
    required this.notes,
    required this.tasks,
    required this.itemOrder,
  });

  // Recreate the item order based on current notes and tasks
  void rebuildItemOrder() {
    itemOrder.clear();

    // First add all notes
    for (int i = 0; i < notes.length; i++) {
      itemOrder.add(TimelineItemRef(type: ItemType.note, index: i));
    }

    // Then add all tasks
    for (int i = 0; i < tasks.length; i++) {
      itemOrder.add(TimelineItemRef(type: ItemType.task, index: i));
    }
  }

  // Add a convenience method to access items by their ordered position
  dynamic getItemAt(int orderIndex) {
    if (orderIndex < 0 || orderIndex >= itemOrder.length) return null;

    final ref = itemOrder[orderIndex];
    if (ref.type == ItemType.note && ref.index < notes.length) {
      return notes[ref.index];
    } else if (ref.type == ItemType.task && ref.index < tasks.length) {
      return tasks[ref.index];
    }
    return null;
  }

  // Method to calculate reference index for a specific item
  TimelineItemRef? findItemRef(ItemType type, int index) {
    for (int i = 0; i < itemOrder.length; i++) {
      if (itemOrder[i].type == type && itemOrder[i].index == index) {
        return itemOrder[i];
      }
    }
    return null;
  }

  // Get the ordered position of an item
  int getOrderPosition(ItemType type, int index) {
    for (int i = 0; i < itemOrder.length; i++) {
      if (itemOrder[i].type == type && itemOrder[i].index == index) {
        return i;
      }
    }
    return -1; // Not found
  }
}

class TaskItem {
  String task;
  bool completed;

  TaskItem({
    required this.task,
    this.completed = false,
  });
}

// Helper classes for managing ordered items in TimelineEntry
enum ItemType { note, task }

class TimelineItemRef {
  final ItemType type;
  int index; // Index within the original notes or tasks list

  TimelineItemRef({required this.type, required this.index});

  @override
  String toString() => '$type:$index';
}

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

// Add this class at the end of the file, before the existing CustomPainter classes
class RecordingPage extends StatefulWidget {
  const RecordingPage({Key? key}) : super(key: key);

  @override
  _RecordingPageState createState() => _RecordingPageState();
}

class _RecordingPageState extends State<RecordingPage>
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
      print('Preloading transcribe animation');
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

      print('Transcribe animation preloaded');
    } catch (e) {
      print('Error preloading transcribe animation: $e');
    }
  }

  void _loadRiveAnimation() async {
    try {
      print('Loading Rive animation from assets/animations/record.riv');

      // Make sure Rive is initialized
      await rive.RiveFile.initialize();

      // Load the Rive file
      final data = await rootBundle.load('assets/animations/record.riv');
      print('Rive file loaded, size: ${data.lengthInBytes} bytes');

      final file = rive.RiveFile.import(data);
      print('Rive file imported successfully');

      // Get available artboards for debugging
      print('Available artboards:');
      for (final artboard in file.artboards) {
        print(' - ${artboard.name}');
      }

      // Setup the artboard - use the main artboard named "Artboard"
      final artboard = file.mainArtboard;
      print('Using artboard: ${artboard.name}');

      // Setup Rive artboard with callback
      var controller = rive.StateMachineController.fromArtboard(
        artboard,
        'State Machine 1', // Your state machine name
      );

      if (controller != null) {
        print('State machine controller found');

        // Set up controller listener before adding it to the artboard
        controller.addEventListener((event) {
          print('Rive event: $event');

          // Check if Click input is triggered in the state machine
          // Re-get the input value each time to ensure we have the latest value
          rive.SMIInput<bool>? clickInput = controller.findInput<bool>('Click');
          if (clickInput != null && clickInput.value && !_isRecording) {
            print('Click input detected as activated - Touch Area was clicked');

            // Start recording in the next frame to avoid build issues
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_isRecording) {
                // Ensure isPause is false when starting
                if (_isPauseInput != null) {
                  print('Ensuring isPause is false');
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

        print(
            'Found inputs: Click=${_clickInput != null}, isPause=${_isPauseInput != null}, IsRecording=${isRecordingInput != null}');

        _controller = controller;
      } else {
        print('State machine controller NOT found');
      }

      setState(() {
        _riveArtboard = artboard;
        _riveLoaded = true;
      });

      print('Rive animation loaded successfully');
    } catch (error) {
      print('Error loading Rive animation: $error');
    }
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
      // Check permissions
      final permissionsGranted = await _checkPermissions();
      if (!permissionsGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot start recording - permissions required'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Get temporary directory for saving the recording
      final directory = await getTemporaryDirectory();
      _recordedFilePath =
          '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      print('Recording to file path: $_recordedFilePath');

      // Start recording
      await _audioRecorder.start(
        RecordConfig(
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
      print('Error starting recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Recording error: ${e.toString()}'),
          duration: const Duration(seconds: 5),
          backgroundColor: Colors.red,
        ),
      );
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
          print('Rive: Resuming animation (isPause -> false)');
          _isPauseInput!.value =
              false; // Set isPause to false to resume animation
        }
      } else {
        // Currently recording, so we are pausing
        await _audioRecorder.pause();

        // Update Rive animation state - pausing
        if (_isPauseInput != null) {
          print('Rive: Pausing animation (isPause -> true)');
          _isPauseInput!.value = true; // Set isPause to true to pause animation
        }
      }

      // This setState call should be outside the try-catch or at least not cause issues if input is null.
      // It's primarily for updating the UI based on _isPaused.
      setState(() {
        _isPaused = !_isPaused; // Toggle the pause state for UI updates
      });
    } catch (e) {
      print('Error pausing/resuming recording: $e');
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
      print('Error stopping recording: $e');
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
                alignment: Alignment(0, -0.75), // Moves it up 20% from center
                child: Container(
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
                              onTapDown: (_) {
                                if (!_isRecording && _clickInput != null) {
                                  print('Mic touch area tapped!');
                                  _clickInput!.value = true;

                                  if (!_isRecording) {
                                    // Ensure isPause is false
                                    if (_isPauseInput != null) {
                                      _isPauseInput!.value = false;
                                    }
                                    _startRecordingAudio();
                                  }
                                }
                              },
                              child: Container(
                                decoration: BoxDecoration(
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
                          fontWeight: FontWeight.w600,
                          fontFamily: 'GeistMono',
                          color: Colors.black,
                        ),
                      ),

                    // Instruction text - not tappable anymore
                    if (!_isRecording)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 170.0),
                        child: IgnorePointer(
                          ignoring: true, // Allow taps to pass through
                          child: Text(
                            'click to start recording',
                            style: const TextStyle(
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
                                    Color(0xFFC6C5C5),
                                    Color.fromARGB(255, 158, 156, 156)
                                  ],
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(120),
                                ),
                              ),
                              child: Center(
                                child: SvgPicture.asset(
                                  _isPaused
                                      ? 'assets/icons/play.svg'
                                      : 'assets/icons/pause.svg',
                                  width: 32,
                                  height: 32,
                                  colorFilter: const ColorFilter.mode(
                                      Colors.white, BlendMode.srcIn),
                                ),
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
                                    Color(0xFFFF5A5A),
                                    Color.fromARGB(255, 210, 1, 1)
                                  ],
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(120),
                                ),
                              ),
                              child: Center(
                                child: SvgPicture.asset(
                                  'assets/icons/stop.svg',
                                  width: 32,
                                  height: 32,
                                ),
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
                                    Color(0xFF00FF72),
                                    Color(0xFF00CD5C)
                                  ],
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(120),
                                ),
                              ),
                              child: Center(
                                child: SvgPicture.asset(
                                  'assets/icons/submit.svg',
                                  width: 32,
                                  height: 32,
                                ),
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

// Add PulsingDot class at the end of the file
class PulsingDot extends StatefulWidget {
  const PulsingDot({Key? key, this.isPaused = false}) : super(key: key);

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

// Add this class near the end of the file
class RiveAnimationFullscreen extends StatefulWidget {
  final String animationPath;
  final String? message; // Make message optional

  const RiveAnimationFullscreen({
    Key? key,
    required this.animationPath,
    this.message, // Optional parameter
  }) : super(key: key);

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
      print(
          'Animation path changed from ${oldWidget.animationPath} to ${widget.animationPath}');
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
      print('Loading Rive animation from ${widget.animationPath}');

      // Load the Rive file
      final data = await rootBundle.load(widget.animationPath);
      print('Rive file loaded, size: ${data.lengthInBytes} bytes');

      // Check if widget was disposed or animation path changed during loading
      if (!mounted || loadingPath != _currentAnimationPath) {
        print('Widget disposed or animation changed during loading');
        return;
      }

      final file = rive.RiveFile.import(data);
      print('Rive file imported successfully');

      // Get available artboards for debugging
      print('Available artboards:');
      for (final artboard in file.artboards) {
        print(' - ${artboard.name}');
      }

      // Setup the artboard - use the main artboard
      final artboard = file.mainArtboard;
      print('Using artboard: ${artboard.name}');

      // Setup Rive artboard with state machine if available
      var controller = rive.StateMachineController.fromArtboard(
        artboard,
        'State Machine 1', // Try standard state machine name
      );

      if (controller != null) {
        print('State machine controller found');
        artboard.addController(controller);
        _controller = controller;
      } else {
        print('No state machine controller found, using simple animation');

        // If no state machine, try to play a simple animation if available
        if (artboard.animations.isNotEmpty) {
          print('Found ${artboard.animations.length} animations');
          print('Playing animation: ${artboard.animations.first.name}');
          artboard.addController(
              rive.SimpleAnimation(artboard.animations.first.name));
        }
      }

      if (mounted && loadingPath == _currentAnimationPath) {
        setState(() {
          _riveArtboard = artboard;
          _isLoaded = true;
        });
        print('Rive animation loaded successfully');
      }
    } catch (error) {
      print('Error loading Rive animation: $error');
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
            : Center(
                child: CircularProgressIndicator(),
              ),
      ),
    );
  }
}

// Create a new animation controller class that holds all animations
class AnimationSequenceController extends StatefulWidget {
  const AnimationSequenceController({Key? key}) : super(key: key);

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
        curve: Interval(0.0, 1.0, curve: Curves.easeInOut),
      ),
    );

    _fadeOutAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _fadeController!,
        curve: Interval(0.0, 0.7, curve: Curves.easeInOut),
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
      print('Loading Rive animation $name from $path');

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

      print('Rive animation $name loaded successfully');
    } catch (e) {
      print('Error loading Rive animation $name: $e');
    }
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
        children: [
          if (previousAnimationWidget != null) previousAnimationWidget,
          if (currentAnimationWidget != null) currentAnimationWidget,
          if (currentAnimationWidget == null && previousAnimationWidget == null)
            Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
