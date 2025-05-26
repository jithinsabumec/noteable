// ignore_for_file: unused_field, unused_local_variable, library_private_types_in_public_api, empty_catches, unused_element, non_constant_identifier_names, use_build_context_synchronously, deprecated_member_use, duplicate_ignore

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
import 'dart:math' as math;
import 'package:device_info_plus/device_info_plus.dart';
import 'time_icons.dart';
import 'package:noteable/services/storage_service.dart';
import 'package:noteable/models/timeline_entry.dart' as models;
import 'package:flutter_svg/flutter_svg.dart'; // Add this import
import 'package:rive/rive.dart' as rive; // Import Rive with an alias
import 'package:flutter/services.dart'; // Import for rootBundle
// Import for RepaintBoundary
// Import for FlutterView
import 'package:firebase_core/firebase_core.dart'; // Import Firebase Core
import 'firebase_options.dart'; // Import Firebase options
import 'screens/auth_wrapper.dart'; // Import AuthWrapper
// ignore: unused_import
import 'services/auth_service.dart'; // Import AuthService
import 'widgets/rive_checkbox.dart'; // Import the RiveCheckbox widget

// Add a GlobalKey to keep track of the MainScreen state
final mainScreenKey = GlobalKey<_MainScreenState>();

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
        child: MainScreen(key: mainScreenKey),
      ),
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

  final List<FocusNode> _sheetFocusNodes =
      []; // Moved here to be accessible for disposal

  // Add a PageController for horizontal sliding between weeks
  late PageController _pageController;
  final int _initialPage =
      1000; // Start at a high number to allow going back in time

  // Add a variable to track previously selected date
  DateTime? _previouslySelectedDate;

  // Add this new instance variable to track the currently selected page
  late int _currentSelectedPage;

  // Map to store RiveCheckboxControllers for each task item
  final Map<String, RiveCheckboxController> _taskCheckboxControllers = {};

  // Helper to get or create a RiveCheckboxController for a task
  RiveCheckboxController _getTaskCheckboxController(String storageId) {
    return _taskCheckboxControllers.putIfAbsent(
        storageId, () => RiveCheckboxController());
  }

  @override
  void initState() {
    super.initState();
    // Initialize the PageController
    _pageController = PageController(
      initialPage: _initialPage,
      viewportFraction: 1.0,
    );

    // Initialize the current selected page
    _currentSelectedPage = _initialPage;

    // Clear any placeholder data (run this only once when testing)
    _clearPlaceholderData();
    // Load entries for the current date
    _loadEntriesForSelectedDate();

    // Store initial selected date
    _previouslySelectedDate = _selectedDate;

    // Preload all Rive animations to avoid delays
    _preloadRiveAnimations();
  }

  // Preload Rive animations
  Future<void> _preloadRiveAnimations() async {
    try {
      // List of animations to preload
      final animations = [
        'assets/animations/transcribe.riv',
        'assets/animations/understand.riv',
        'assets/animations/extract.riv',
        'assets/animations/todo_tick.riv', // Add the new todo checkbox animation
      ];

      // Load each animation in parallel
      await Future.wait(animations.map((path) async {
        try {
          final data = await rootBundle.load(path);
          final file = rive.RiveFile.import(data);
        } catch (e) {}
      }));
    } catch (e) {}
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    // Dispose all focus nodes from the last shown bottom sheet
    for (var node in _sheetFocusNodes) {
      node.dispose();
    }
    _sheetFocusNodes.clear();

    // Cancel animation sequence timer and reset states
    _animationSequenceTimer?.cancel();
    _animationSequenceTimer = null;
    _showAnimations = false;
    _isTranscribing = false;
    _isUnderstanding = false;
    _isAnalyzing = false;

    // Cancel any pending page animations
    if (_pageController.hasClients) {
      _pageController.dispose();
    }

    super.dispose();
  }

  // Clear placeholder data from storage
  Future<void> _clearPlaceholderData() async {
    await _storageService.clearAll();
  }

  // Load entries for the selected date
  Future<void> _loadEntriesForSelectedDate() async {
    // Don't modify page selection here - we'll handle it in the date selection
    final List<models.TimelineEntry> sEntries =
        _storageService.getEntriesForDate(_selectedDate);
    // Sort entries by timestamp to ensure consistent order if multiple items share the same UI timestamp string
    sEntries.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    setState(() {
      // Clear existing entries before repopulating
      _timelineEntriesByDate.clear();

      // Temporary map to build UI entries
      Map<String, TimelineEntry> tempUiEntries = {};

      for (final S_entry in sEntries) {
        final String uiTimestamp = S_entry.timeString; // e.g., "10:00 AM"
        final bool isDaytime = _isTimestamp24HourDaytime(S_entry.timestamp);

        // Get or create the UI TimelineEntry for this uiTimestamp
        TimelineEntry uiEntry = tempUiEntries.putIfAbsent(uiTimestamp, () {
          return TimelineEntry(
            timestamp: uiTimestamp,
            isDaytime: isDaytime,
            notes: [],
            tasks: [],
            itemOrder: [],
          );
        });

        if (S_entry.type == models.EntryType.note) {
          final newNoteIndex = uiEntry.notes.length;
          uiEntry.notes.add(S_entry.content);
          uiEntry.itemOrder.add(TimelineItemRef(
            type: ItemType.note,
            index: newNoteIndex,
            storageId: S_entry.id, // Store the original ID
          ));
        } else {
          // Task
          final newTaskIndex = uiEntry.tasks.length;
          uiEntry.tasks.add(TaskItem(
            task: S_entry.content,
            completed: S_entry.completed,
          ));
          uiEntry.itemOrder.add(TimelineItemRef(
            type: ItemType.task,
            index: newTaskIndex,
            storageId: S_entry.id, // Store the original ID
          ));
        }
      }

      // Convert the temporary map to the final structure and update the UI
      _timelineEntriesByDate
          .addAll(tempUiEntries.map((key, value) => MapEntry(key, [value])));

      // Update previous date tracker
      _previouslySelectedDate = _selectedDate;
    });

    // Debug print to verify entries are loaded
    debugPrint('Loaded ${sEntries.length} entries for $_selectedDate');
  }

  // Helper method to check if a timestamp is during the day or night (24-hour format)
  bool _isTimestamp24HourDaytime(DateTime time) {
    final hour = time.hour;
    return hour >= 6 && hour < 18;
  }

  Future<bool> _checkPermissions() async {
    try {
      // Always check microphone permission
      final micStatus = await Permission.microphone.status;

      // Storage permission handling for different platform versions
      bool storagePermissionGranted = false;

      if (Platform.isAndroid) {
        // For all Android versions, request storage permission
        final storageStatus = await Permission.storage.status;
        storagePermissionGranted = storageStatus.isGranted;

        // If Android 13+ (API 33+), we might need additional permissions
        // but for Hive, storage permission should be sufficient
      } else if (Platform.isIOS) {
        // For iOS, we usually don't need explicit storage permission for Hive
        storagePermissionGranted = true;
      } else {
        // For other platforms, assume permission is granted
        storagePermissionGranted = true;
      }

      // If already granted, return true immediately
      if (micStatus.isGranted && storagePermissionGranted) {
        return true;
      }

      // Build permission message
      String permissionMessage = 'Zelo needs ';
      if (!micStatus.isGranted) {
        permissionMessage += 'microphone access to record your voice';
      }
      if (!storagePermissionGranted) {
        permissionMessage += micStatus.isGranted ? ' and ' : '';
        permissionMessage += 'storage access to save your data';
      }

      // Show explanation dialog if permissions weren't previously granted
      if (micStatus.isDenied || !storagePermissionGranted) {
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
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permissions are required to use the app features'),
              duration: Duration(seconds: 3),
            ),
          );
          return false;
        }
      }

      // Handle permanently denied cases with a more user-friendly approach
      final isPermanentlyDenied = micStatus.isPermanentlyDenied ||
          (Platform.isAndroid && await Permission.storage.isPermanentlyDenied);

      if (isPermanentlyDenied) {
        final bool shouldOpenSettings = await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('Permissions Required'),
                content: const Text(
                    'Permissions are required but have been denied. Please open settings to enable them manually.'),
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
        }
        return false;
      }

      // Request permissions
      List<Future<PermissionStatus>> permissionsToRequest = [];

      if (!micStatus.isGranted) {
        permissionsToRequest.add(Permission.microphone.request());
      }

      if (!storagePermissionGranted && Platform.isAndroid) {
        permissionsToRequest.add(Permission.storage.request());
      }

      // Wait for all permissions
      final List<PermissionStatus> results =
          await Future.wait(permissionsToRequest);

      // Check if all requested permissions were granted
      final bool allGranted = results.every((status) => status.isGranted);

      // If we didn't need to request any new permissions, consider it a success
      return allGranted || permissionsToRequest.isEmpty;
    } catch (e) {
      print('Error checking permissions: $e');
      // If there's an error, return false but don't crash
      return false;
    }
  }

  // Add a new recording directly
  void _startRecording() async {
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
            const RecordingPage(),
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

      // Start the animation sequence with a small delay to ensure smooth transition
      await Future.delayed(const Duration(milliseconds: 50));
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
    try {
      // Example: if _MainScreenState still had its own recording session it could manage
      // This is a placeholder, as the main recording is in RecordingPage
      if (await _audioRecorder.isRecording() ||
          await _audioRecorder.isPaused()) {
        if (_isPaused) {
          // await _audioRecorder.resume(); // If _MainScreenState's recorder was active
        } else {
          // await _audioRecorder.pause(); // If _MainScreenState's recorder was active
        }
        // setState(() => _isPaused = !_isPaused); // Update _MainScreenState's own _isPaused
      }
    } catch (e) {
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

    if (!mounted) return;

    // Show animations and set the first animation type
    if (!_showAnimations) {
      setState(() {
        _showAnimations = true;
        _isTranscribing = true;
        _isUnderstanding = false;
        _isAnalyzing = false;
      });
    }

    // Start with the transcribe animation if not already showing
    if (_animationController.currentState != null) {
      _animationController.currentState!.showAnimation('transcribe');
    }

    // Start a sequence of timers for the animations
    // First 5 seconds: Transcribing (this animation is already showing from RecordingPage)
    _animationSequenceTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) {
        _animationSequenceTimer?.cancel();
        return;
      }

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
        if (!mounted) {
          _animationSequenceTimer?.cancel();
          return;
        }

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
      });
    });
  }

  // Perform the actual text processing after animations
  Future<void> _performActualTextProcessing(String text) async {
    try {
      final result = await _deepseekService.analyzeTranscription(text);

      // Always save to the current date (today)
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Format timestamp for UI display
      final hour = now.hour > 12
          ? now.hour - 12
          : now.hour == 0
              ? 12
              : now.hour;
      final minute = now.minute.toString().padLeft(2, '0');
      final ampm = now.hour >= 12 ? 'PM' : 'AM';
      final timestamp = '$hour:$minute $ampm';
      final isDaytime = now.hour >= 6 && now.hour < 18;

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

      // Important: Save ALL entries to persistent storage first
      List<models.TimelineEntry> createdStorageEntries = [];

      // Save notes to storage with the current timestamp
      if (result['notes'] != null && result['notes'].isNotEmpty) {
        for (final note in result['notes']) {
          final storageEntry = models.TimelineEntry(
            id: _storageService.generateId(), // Generate ID here
            content: note,
            timestamp: now, // Use exact now with time
            type: models.EntryType.note,
            completed: false,
          );
          await _storageService.saveEntry(storageEntry);
          createdStorageEntries
              .add(storageEntry); // Add to list for later UI use
        }
      }

      // Save tasks to storage with the current timestamp
      if (result['tasks'] != null && result['tasks'].isNotEmpty) {
        for (final task in result['tasks']) {
          final storageEntry = models.TimelineEntry(
            id: _storageService.generateId(), // Generate ID here
            content: task,
            timestamp: now, // Use exact now with time
            type: models.EntryType.task,
            completed: false,
          );
          await _storageService.saveEntry(storageEntry);
          createdStorageEntries
              .add(storageEntry); // Add to list for later UI use
        }
      }

      // Check if we're currently viewing today
      final currentlyViewingToday = _selectedDate.year == today.year &&
          _selectedDate.month == today.month &&
          _selectedDate.day == today.day;

      // Update the UI accordingly
      setState(() {
        // Only update the UI immediately if we're viewing today
        if (currentlyViewingToday) {
          // Create or update timeline entry for the UI
          if (!_timelineEntriesByDate.containsKey(timestamp)) {
            // Create new entry for this timestamp
            _timelineEntriesByDate[timestamp] = [
              TimelineEntry(
                timestamp: timestamp,
                isDaytime: isDaytime,
                notes: [],
                tasks: [],
                itemOrder: [],
              )
            ];
          }

          // Get the first (and usually only) entry for this timestamp
          final uiEntry = _timelineEntriesByDate[timestamp]!.first;

          // Iterate over createdStorageEntries to add them to the UI
          for (final S_entry in createdStorageEntries) {
            if (S_entry.type == models.EntryType.note) {
              final newNoteIndex = uiEntry.notes.length;
              uiEntry.notes.add(S_entry.content);
              uiEntry.itemOrder.add(TimelineItemRef(
                type: ItemType.note,
                index: newNoteIndex,
                storageId: S_entry.id, // Use the ID from the saved entry
              ));
            } else {
              // Task
              final newTaskIndex = uiEntry.tasks.length;
              uiEntry.tasks.add(TaskItem(
                task: S_entry.content,
                completed: S_entry.completed,
              ));
              uiEntry.itemOrder.add(TimelineItemRef(
                type: ItemType.task,
                index: newTaskIndex,
                storageId: S_entry.id, // Use the ID from the saved entry
              ));
            }
          }
        }

        // Finish animation sequence
        _isAnalyzing = false;
        _showAnimations = false;
      });

      // Display appropriate notification
      if (!currentlyViewingToday) {
        // Show option to navigate to today if we're on a different date
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Insights saved to today\'s date'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'View Today',
              onPressed: () {
                setState(() {
                  _selectedDate = today;
                });
                // Always reload data when changing dates to ensure we have fresh data
                _loadEntriesForSelectedDate().then((_) {
                  debugPrint(
                      "Entries loaded for ${_formatDate(_selectedDate)}");
                });
              },
            ),
          ),
        );
      } else {
        // Simple confirmation if already on today
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your recording has been processed'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
        _showAnimations = false;
      });

      // Show error message
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

      final uploadResponse = await http.post(
        Uri.parse(uploadUrl),
        headers: {
          'authorization': Config.assemblyAIKey,
          'content-type': 'audio/m4a',
        },
        body: bytes,
      );

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

  Future<void> _stopRecording() async {
    try {
      if (_isRecording) {
        final path = await _audioRecorder.stop();
        setState(() {
          _isRecording = false;
          _isPaused = false;
        });

        // Start transcription
        if (path != null) {
          // Start animation sequence immediately
          _startProcessingAnimationSequence("");

          // Then start actual transcription in the background
          await _transcribeAudio(path);
        }
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

  // Update the WeekdaySelector to reload data when date changes and make it horizontally slidable
  Widget _buildWeekdaySelector() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Track if we're currently manually scrolling to avoid interrupting user
    bool isUserScrolling = false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: SizedBox(
        height: 80,
        child: Stack(
          children: [
            // Main date selector
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                // Track when user is manually scrolling
                if (notification is ScrollStartNotification) {
                  isUserScrolling = true;
                } else if (notification is ScrollEndNotification) {
                  // Reset after scrolling ends with a small delay
                  Future.delayed(const Duration(milliseconds: 300), () {
                    isUserScrolling = false;
                  });
                }
                return false;
              },
              child: PageView.builder(
                controller: _pageController,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                onPageChanged: (pageIndex) {
                  if (!mounted) return;

                  // Only update the page tracking - don't modify the selected date
                  setState(() {
                    _currentSelectedPage = pageIndex;
                    // We're completely removing any date selection logic from here
                    // This was the root cause of the problem
                  });

                  // Keep these debug prints but don't use them to modify state
                  final weekOffset = _initialPage - pageIndex;
                  debugPrint("Week offset: $weekOffset weeks before current");

                  final newStartOfWeek = now.subtract(
                      Duration(days: now.weekday - 1 + (weekOffset * 7)));
                  debugPrint(
                      "Week starting date: ${newStartOfWeek.toString()}");
                },
                itemBuilder: (context, pageIndex) {
                  // Only build pages for current week and past weeks
                  if (pageIndex > _initialPage) {
                    return Container(); // Empty container for future weeks
                  }

                  // For current week (offset 0) or past weeks (offset > 0)
                  final weekOffset = _initialPage - pageIndex;
                  final startOfWeek = now.subtract(
                      Duration(days: now.weekday - 1 + (weekOffset * 7)));

                  final weekdays = [
                    'Mon',
                    'Tue',
                    'Wed',
                    'Thu',
                    'Fri',
                    'Sat',
                    'Sun'
                  ];

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: List.generate(7, (index) {
                      final dayDate = startOfWeek.add(Duration(days: index));
                      final normalizedDayDate =
                          DateTime(dayDate.year, dayDate.month, dayDate.day);

                      // For debugging
                      if (index == 0) {
                        debugPrint(
                            "First day of week: ${dayDate.toString()} (Page: $pageIndex)");
                      }

                      final isSelectedDay =
                          _selectedDate.year == dayDate.year &&
                              _selectedDate.month == dayDate.month &&
                              _selectedDate.day == dayDate.day;

                      final isCurrentDay = dayDate.year == today.year &&
                          dayDate.month == today.month &&
                          dayDate.day == today.day;

                      // Check if date is after today (future date)
                      final bool isFuture = normalizedDayDate.isAfter(today);

                      // Set text color:
                      // - Future dates: light grey
                      // - Today: blue
                      // - Selected day: dark grey
                      // - Other dates: medium grey
                      final Color textColor = isFuture
                          ? const Color(
                              0xFFD0D0D0) // Lighter gray for disabled dates
                          : isCurrentDay
                              ? const Color(
                                  0xFF225AFF) // Blue for today instead of orange
                              : isSelectedDay
                                  ? const Color(0xFF191919)
                                  : const Color(0xFF9D9D9D);

                      // Set background color for selected dates:
                      // - Light blue for today
                      // - Light grey for other dates
                      final Color selectionColor = isCurrentDay
                          ? const Color.fromARGB(255, 236, 242,
                              255) // Light blue for today instead of light orange
                          : const Color(
                              0xFFEEEEEE); // Light grey for other dates

                      return InkWell(
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        onTap: isFuture
                            ? null
                            : () {
                                debugPrint(
                                    "Date tapped: ${dayDate.toString()}, isFuture: $isFuture, pageIndex: $pageIndex");

                                setState(() {
                                  _selectedDate = dayDate;
                                });

                                // Make sure to reload entries whenever date changes
                                _loadEntriesForSelectedDate().then((_) {
                                  debugPrint(
                                      "Entries loaded for ${_formatDate(_selectedDate)}");
                                });
                              },
                        child: Container(
                          width: 45, // Increase width slightly
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
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: 30,
                                height: 30,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isSelectedDay && !isFuture
                                      ? selectionColor // Use dynamic selection color
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Text(
                                  '${dayDate.day}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600, // SemiBold
                                    fontFamily: 'GeistMono',
                                    color: textColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),

            // Left gradient overlay
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 24,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.white,
                      Colors.white.withOpacity(0.0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),

            // Right gradient overlay
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 24,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    colors: [
                      Colors.white,
                      Colors.white.withOpacity(0.0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            top: false,
            child: Stack(
              children: [
                // Main content
                LayoutBuilder(
                  builder: (BuildContext context,
                      BoxConstraints viewportConstraints) {
                    return SingleChildScrollView(
                      clipBehavior: Clip.none,
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                            minHeight: viewportConstraints.maxHeight),
                        child: Padding(
                          padding:
                              const EdgeInsets.only(top: 24.0, bottom: 24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Static "today" text with horizontal padding
                              Padding(
                                padding: const EdgeInsets.only(
                                    top: 16.0,
                                    left: 24.0,
                                    right: 24.0,
                                    bottom: 16.0),
                                child: Text(
                                  _formatDate(_selectedDate).toLowerCase(),
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Geist',
                                    color: Color(0xFF171717),
                                    height: 1.0,
                                    letterSpacing: -0.72,
                                  ),
                                ),
                              ),

                              // Weekday selector without horizontal padding
                              // to allow full width scrolling
                              _buildWeekdaySelector(),

                              // Timeline entries with horizontal padding
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 24.0,
                                  right: 24.0,
                                  top: 16.0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: _buildTimelineEntries(),
                                ),
                              ),
                            ], // End of Column
                          ), // End of ConstrainedBox
                        ), // End of SingleChildScrollView
                      ), // End of LayoutBuilder
                    ); // End of SingleChildScrollView
                  }, // End of LayoutBuilder builder
                ),
              ],
            ),
          ),

          // Animation sequence controller - always there but only visible when needed
          if (_showAnimations)
            AnimationSequenceController(key: _animationController),

          // Expandable FAB at the bottom right corner - only show when not loading
          if (!isLoading)
            Positioned(
              right: 24,
              bottom: 100,
              child: _buildExpandableFAB(),
            ),
        ],
      ),
    );
  }

  // Build the timeline entries from the new data structure
  List<Widget> _buildTimelineEntries() {
    if (_timelineEntriesByDate.isEmpty) {
      return [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                'assets/icons/home-emptystate.svg',
                width: 219,
                height: 137,
              ),
              const SizedBox(height: 16),
              Text(
                'You haven\'t added anything yet.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                  fontFamily: 'Geist',
                ),
              ),
            ],
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
    // Get appropriate time icon based on timestamp
    final timeIcon = TimeIcons.getTimeIcon(entry.timestamp);

    List<Widget> contentWidgets = [];

    for (int i = 0; i < entry.itemOrder.length; i++) {
      final itemRef = entry.itemOrder[i];
      final orderIndex = i; // This is the item's index in itemOrder

      if (itemRef.type == ItemType.note) {
        if (itemRef.index < entry.notes.length) {
          final note = entry.notes[itemRef.index];
          contentWidgets.add(
            _buildDraggableNote(note, timestamp, itemRef.index, orderIndex),
          );
        } else {}
      } else if (itemRef.type == ItemType.task) {
        if (itemRef.index < entry.tasks.length) {
          final task = entry.tasks[itemRef.index];
          contentWidgets.add(
            _buildDraggableTask(task, timestamp, itemRef.index, orderIndex),
          );
        } else {}
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
        _dragItemType == ItemType.note;

    final TimelineEntry? entry = _timelineEntriesByDate[timestamp]?.first;
    final String currentStorageId =
        entry?.itemOrder[orderIndex].storageId ?? ''; // Get storageId

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
                  'storage_id': currentStorageId, // <<< ADDED
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
                  child: const Icon(
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
          storageId: currentStorageId, // Pass storageId
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
              'storage_id': currentStorageId, // <<< ADDED
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

              // Add a threshold to prevent flickering
              const threshold = 10.0; // 10 pixel threshold
              bool isTopHalf;

              if (position.dy < topHalf - threshold) {
                isTopHalf = true;
              } else if (position.dy > topHalf + threshold) {
                isTopHalf = false;
              } else {
                // If within threshold, maintain previous state to prevent flickering
                isTopHalf = position.dy < topHalf;
              }

              return Positioned(
                top: isTopHalf ? 1.5 : null,
                bottom: isTopHalf ? null : 3,
                left: 4,
                right: 4,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color(
                        0xFF2196F3), // Using same color for consistency
                    borderRadius: BorderRadius.circular(1.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2196F3).withOpacity(0.3),
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
        _dragItemType == ItemType.task;

    final TimelineEntry? entry = _timelineEntriesByDate[timestamp]?.first;
    final String currentStorageId =
        entry?.itemOrder[orderIndex].storageId ?? ''; // Get storageId

    // Get or create the controller for this task
    final riveCheckboxController = _getTaskCheckboxController(currentStorageId);

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
            _buildTaskItem(task, timestamp, orderIndex, currentStorageId,
                riveCheckboxController,
                isFirstItem: true),

            // Draggable handle on the right
            Positioned(
              top: 0,
              right: 0,
              child: Draggable<Map<String, dynamic>>(
                data: {
                  'type': 'task',
                  'content': task.task,
                  'completed': task.completed,
                  'source_timestamp': timestamp,
                  'content_list_index':
                      contentListIndex, // Index in the tasks list
                  'order_index': orderIndex, // Index in the itemOrder list
                  'dragPosition': Offset.zero,
                  'storage_id': currentStorageId, // <<< ADDED
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
                        // Translate the RiveCheckbox to offset its internal boundary
                        Transform.translate(
                          offset:
                              const Offset(-2.0, -6.0), // Move 2px left, 2px up
                          child: RiveCheckbox(
                            isChecked: task.completed,
                            controller:
                                riveCheckboxController, // Pass the controller
                            onChanged: null, // Not interactive in feedback
                            size: 16, // Adjust size as needed
                          ),
                        ),
                        const SizedBox(width: 4), // Reduced from 8 to 4
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
                  child: const Icon(
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
          storageId: currentStorageId, // Pass storageId
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
              'content_list_index': contentListIndex,
              'order_index': orderIndex,
              'position': insertPosition,
              'storage_id': currentStorageId, // <<< ADDED
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

              // Add a threshold to prevent flickering
              const threshold = 10.0; // 10 pixel threshold
              bool isTopHalf;

              if (position.dy < topHalf - threshold) {
                isTopHalf = true;
              } else if (position.dy > topHalf + threshold) {
                isTopHalf = false;
              } else {
                // If within threshold, maintain previous state to prevent flickering
                isTopHalf = position.dy < topHalf;
              }

              return Positioned(
                top: isTopHalf ? 1.5 : null,
                bottom: isTopHalf ? null : 3,
                left: 4,
                right: 4,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color(
                        0xFF2196F3), // Using same color for consistency
                    borderRadius: BorderRadius.circular(1.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2196F3).withOpacity(0.3),
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
                child: _buildTaskItem(task, timestamp, orderIndex,
                    currentStorageId, riveCheckboxController,
                    isFirstItem: true),
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
    required String storageId, // Added storageId
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
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                const SizedBox(height: 24),

                // Edit and Delete buttons in a Row
                Row(
                  children: [
                    // Edit button
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _showEditDialog(
                            context: context,
                            timestamp: timestamp,
                            contentListIndex: contentListIndex,
                            orderIndex: orderIndex,
                            itemType: itemType,
                            content: content,
                            completed: completed,
                            storageId: storageId, // Pass storageId
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE0E8FF), // Blue
                          foregroundColor: const Color(0xFF0038DD),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                          shadowColor: Colors.transparent,
                        ).copyWith(
                          overlayColor:
                              MaterialStateProperty.resolveWith<Color?>(
                            (Set<MaterialState> states) {
                              if (states.contains(MaterialState.pressed)) {
                                return const Color(0xFF0038DD).withOpacity(0.1);
                              }
                              if (states.contains(MaterialState.hovered)) {
                                return const Color(0xFF0038DD)
                                    .withOpacity(0.05);
                              }
                              return null;
                            },
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SvgPicture.asset(
                              'assets/icons/pen.svg',
                              width: 18,
                              height: 18,
                              colorFilter: const ColorFilter.mode(
                                Color(0xFF0038DD),
                                BlendMode.srcIn,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Edit',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Geist',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Delete button
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _deleteItem(timestamp, orderIndex, itemType,
                              storageId); // Pass storageId
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFDFDF), // Red
                          foregroundColor: const Color(0xFFC70000),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                          shadowColor: Colors.transparent,
                        ).copyWith(
                          overlayColor:
                              MaterialStateProperty.resolveWith<Color?>(
                            (Set<MaterialState> states) {
                              if (states.contains(MaterialState.pressed)) {
                                return const Color(0xFFC70000).withOpacity(0.1);
                              }
                              if (states.contains(MaterialState.hovered)) {
                                return const Color(0xFFC70000)
                                    .withOpacity(0.05);
                              }
                              return null;
                            },
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SvgPicture.asset(
                              'assets/icons/delete.svg',
                              width: 18,
                              height: 18,
                              colorFilter: const ColorFilter.mode(
                                Color(0xFFC70000),
                                BlendMode.srcIn,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Delete',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Geist',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Move or Order section
                const Text(
                  'Move or Order',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Geist',
                    color: Color(0xFF4B4B4B),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Press and hold to enter drag mode, then move the item to another time or position',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF737373),
                    fontFamily: 'Geist',
                  ),
                ),
                const SizedBox(height: 16),

                // Move or Order button
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // Enable drag mode for this specific item
                    setState(() {
                      _dragItemTimestamp = timestamp;
                      _dragItemIndex = contentListIndex;
                      _dragItemOrderIndex = orderIndex;
                      _dragItemType = itemType;
                    });
                    _showDragInstructions();
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Color(0xFFE5E5E5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.swap_vert, color: Color(0xFF4B4B4B)),
                      SizedBox(width: 8),
                      Text(
                        'Start Drag Mode',
                        style: TextStyle(
                          color: Color(0xFF4B4B4B),
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Geist',
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Show edit dialog for a note or task - now using the bottom sheet UI like when adding
  void _showEditDialog({
    required BuildContext context,
    required String timestamp,
    required int contentListIndex,
    required int orderIndex,
    required ItemType itemType,
    required String content,
    required String storageId, // Added storageId
    bool? completed,
  }) {
    // Dispose any previous sheet's focus nodes before creating new ones
    for (var node in _sheetFocusNodes) {
      node.dispose();
    }
    _sheetFocusNodes.clear();

    // Create a new controller initialized with the existing content
    List<TextEditingController> textControllers = [
      TextEditingController(text: content)
    ];
    _sheetFocusNodes
        .add(FocusNode()); // Add initial focus node to the class-level list

    // Initialize with the type of the current item
    String selectedType = itemType == ItemType.note ? 'Notes' : 'Tasks';

    // Initialize completed status for tasks
    bool isTaskCompleted = completed ?? false;

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
                        const gap = 4.0; // 4 pixel gap between tabs
                        final tabWidth = (containerWidth - 8 - gap) / 2;

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
                                        // Reload entries when switching tabs to ensure fresh data
                                        // This ensures we're properly refreshing from storage
                                        if (mounted) {
                                          _loadEntriesForSelectedDate();
                                        }
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
                                        // Reload entries when switching tabs to ensure fresh data
                                        // This ensures we're properly refreshing from storage
                                        if (mounted) {
                                          _loadEntriesForSelectedDate();
                                        }
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

                    // Text Field and checkbox for completed (if task)
                    Column(
                      children: [
                        const SizedBox(height: 24),

                        // Title - Different text based on selected type
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            selectedType == 'Notes' ? "Edit Note" : "Edit Task",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Geist',
                              color: Color(0xFF4B4B4B),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Text field for content
                        TextField(
                          controller: textControllers[0],
                          focusNode: _sheetFocusNodes[0],
                          minLines: 3,
                          maxLines: 5,
                          decoration: InputDecoration(
                            hintText: selectedType == 'Notes'
                                ? "I've been thinking about..."
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

                        // Completed checkbox for tasks
                        if (selectedType == 'Tasks')
                          Padding(
                            padding: const EdgeInsets.only(top: 16.0),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: isTaskCompleted,
                                  onChanged: (bool? value) {
                                    setModalState(() {
                                      isTaskCompleted = value ?? false;
                                    });
                                  },
                                ),
                                const Text('Completed'),
                              ],
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
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              final newContent = textControllers[0].text;
                              if (newContent.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please enter some content'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                                return;
                              }

                              Navigator.pop(context);

                              // Call _updateItem with the new content and type
                              _updateItem(
                                timestamp: timestamp,
                                orderIndexInItemOrder: orderIndex,
                                newItemType: selectedType == 'Notes'
                                    ? ItemType.note
                                    : ItemType.task,
                                newContent: newContent,
                                newCompleted: selectedType == 'Tasks'
                                    ? isTaskCompleted
                                    : null,
                                originalItemType:
                                    itemType, // Pass the original type to handle conversions
                                storageId: storageId, // Pass storageId
                              );
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
                            child: const Text('Save'),
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

  // Update a note or task - modified to handle type conversion
  void _updateItem({
    required String timestamp,
    required int orderIndexInItemOrder, // Renamed from orderIndex for clarity
    required ItemType newItemType, // Renamed from itemType to newItemType
    required String newContent,
    bool? newCompleted,
    required ItemType originalItemType, // Made required
    required String storageId,
  }) {
    if (newContent.isEmpty) return;

    setState(() {
      final currentUiEntry = _timelineEntriesByDate[timestamp]?.first;
      if (currentUiEntry == null) {
        return;
      }

      if (orderIndexInItemOrder < 0 ||
          orderIndexInItemOrder >= currentUiEntry.itemOrder.length) {
        return;
      }

      final TimelineItemRef itemRefToUpdate =
          currentUiEntry.itemOrder[orderIndexInItemOrder];
      // Make a mutable copy for storageId if it needs to change due to type conversion
      String currentStorageId = storageId;

      final int originalContentListIndex = itemRefToUpdate.index;

      // Case 1: Type has changed
      if (originalItemType != newItemType) {
        // 1. Delete old entry from Hive
        _storageService.deleteEntry(
            currentStorageId); // Use currentStorageId (which is the original ID here)

        // 2. Create and save new entry in Hive with a new ID
        final newGeneratedStorageId = _storageService.generateId();

        // Attempt to get original DateTime from storage to preserve it across type change
        // This is a bit convoluted because we only have the ID. Ideally, StorageService would have a getEntryById.
        // For now, we search all entries for the day.
        DateTime sOriginaltimestamp = DateTime.now(); // Fallback
        final sEntriesforday = _storageService.getEntriesForDate(_selectedDate);
        final sOriginalentryfortimestamp = sEntriesforday
            .firstWhere((e) => e.id == currentStorageId, orElse: () {
          return models.TimelineEntry(
              id: '',
              content: '',
              timestamp: DateTime.now(),
              type: models.EntryType
                  .note); // Dummy to avoid null, timestamp will be now()
        });
        sOriginaltimestamp = sOriginalentryfortimestamp.timestamp;

        final sNewentry = models.TimelineEntry(
          id: newGeneratedStorageId,
          content: newContent,
          timestamp:
              sOriginaltimestamp, // Preserve original timestamp if possible
          type: newItemType == ItemType.note
              ? models.EntryType.note
              : models.EntryType.task,
          completed:
              newItemType == ItemType.task ? (newCompleted ?? false) : false,
        );
        _storageService.saveEntry(sNewentry);
        currentStorageId =
            newGeneratedStorageId; // Update storageId to the new one for the UI ref

        // 3. Update UI
        //  a. Remove from old content list and update subsequent indices in itemOrder
        if (originalItemType == ItemType.note) {
          if (originalContentListIndex < currentUiEntry.notes.length) {
            currentUiEntry.notes.removeAt(originalContentListIndex);
          }
        } else {
          // Task
          if (originalContentListIndex < currentUiEntry.tasks.length) {
            currentUiEntry.tasks.removeAt(originalContentListIndex);
          }
        }
        // Adjust indices for items of the original type that were after the removed item
        for (final ref in currentUiEntry.itemOrder) {
          if (ref.type == originalItemType &&
              ref.index > originalContentListIndex) {
            ref.index--;
          }
        }

        //  b. Add to new content list (at the end of that list)
        int newContentListIndexInNewTypeList;
        if (newItemType == ItemType.note) {
          newContentListIndexInNewTypeList = currentUiEntry.notes.length;
          currentUiEntry.notes.add(newContent);
        } else {
          // Task
          newContentListIndexInNewTypeList = currentUiEntry.tasks.length;
          currentUiEntry.tasks.add(
              TaskItem(task: newContent, completed: newCompleted ?? false));
        }

        //  c. Replace the TimelineItemRef in itemOrder with a new one
        // itemRefToUpdate.type = newItemType; // Cannot do this, type is final
        // itemRefToUpdate.index = newContentListIndexInNewTypeList; // index is not final, but set in constructor below
        // itemRefToUpdate.storageId = currentStorageId; // storageId is final

        currentUiEntry.itemOrder[orderIndexInItemOrder] = TimelineItemRef(
            type: newItemType,
            index: newContentListIndexInNewTypeList,
            storageId: currentStorageId // This is the newGeneratedStorageId
            );
      } else {
        // Case 2: No type change, just content/completion update
        // Fetch the existing models.TimelineEntry using the original storageId
        // This also feels like it needs a direct getById from StorageService
        models.TimelineEntry? sEntrytoupdate;
        final sEntriesforday = _storageService.getEntriesForDate(_selectedDate);
        for (var e in sEntriesforday) {
          if (e.id == currentStorageId) {
            sEntrytoupdate = e;
            break;
          }
        }

        if (sEntrytoupdate == null) {
          _loadEntriesForSelectedDate(); // Force reload
          return;
        }

        final updatedSEntry = sEntrytoupdate.copyWith(
          content: newContent,
          completed: newItemType == ItemType.task
              ? (newCompleted ?? sEntrytoupdate.completed)
              : sEntrytoupdate.completed,
        );
        _storageService.updateEntry(updatedSEntry);

        // Update UI content list (notes or tasks)
        if (newItemType == ItemType.note) {
          if (originalContentListIndex < currentUiEntry.notes.length) {
            currentUiEntry.notes[originalContentListIndex] = newContent;
          }
        } else {
          // Task
          if (originalContentListIndex < currentUiEntry.tasks.length) {
            currentUiEntry.tasks[originalContentListIndex] = TaskItem(
              task: newContent,
              completed: newCompleted ??
                  currentUiEntry.tasks[originalContentListIndex].completed,
            );
          }
        }
        // itemRefToUpdate.storageId remains the same (currentStorageId)
        // itemRefToUpdate.type remains the same (newItemType which is same as originalItemType)
        // itemRefToUpdate.index remains the same (originalContentListIndex)
      }
    });
  }

  // Delete a note or task
  void _deleteItem(String timestamp, int orderIndexInItemOrder,
      ItemType itemType, String storageId) {
    // Delete from persistent storage first
    _storageService.deleteEntry(storageId);

    setState(() {
      final uiEntry = _timelineEntriesByDate[timestamp]?.first;
      if (uiEntry == null) {
        return;
      }

      if (orderIndexInItemOrder < 0 ||
          orderIndexInItemOrder >= uiEntry.itemOrder.length) {
        return;
      }

      // Get the reference to the item being deleted BEFORE modifying itemOrder
      final itemRefToDelete = uiEntry.itemOrder[orderIndexInItemOrder];
      final int contentListIndexToDelete = itemRefToDelete.index;

      // Remove from the specific content list (notes or tasks)
      if (itemType == ItemType.note) {
        if (contentListIndexToDelete < uiEntry.notes.length) {
          uiEntry.notes.removeAt(contentListIndexToDelete);
        } else {
          return; // Avoid further errors
        }
      } else {
        // Task
        if (contentListIndexToDelete < uiEntry.tasks.length) {
          uiEntry.tasks.removeAt(contentListIndexToDelete);
        } else {
          return; // Avoid further errors
        }
      }

      // Remove from itemOrder
      uiEntry.itemOrder.removeAt(orderIndexInItemOrder);

      // Update indices in itemOrder for items of the same type that came after the deleted item
      for (int i = 0; i < uiEntry.itemOrder.length; i++) {
        final currentRef = uiEntry.itemOrder[i];
        if (currentRef.type == itemType &&
            currentRef.index > contentListIndexToDelete) {
          currentRef.index--; // Decrement the index
        }
      }

      // If the UI entry is now empty (no notes, no tasks, and thus itemOrder should be empty)
      if (uiEntry.notes.isEmpty && uiEntry.tasks.isEmpty) {
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
    final sourceStorageId =
        droppedItemData['storage_id'] as String? ?? ''; // <<< EXTRACTED

    final targetContentListIndex =
        targetItemData['content_list_index'] as int?; // Made nullable
    final targetTypeString = targetItemData['type'] as String? ?? 'note';
    final targetType =
        targetTypeString == 'note' ? ItemType.note : ItemType.task;
    final targetOrderIndex =
        targetItemData['order_index'] as int?; // Made nullable
    final insertPosition = targetItemData['position'] as String;

    if (sourceOrderIndex == null) {
      return;
    }
    if (sourceContentListIndex == null) {
      // Added check for sourceContentListIndex
      return;
    }
    if (targetOrderIndex == null) {
      // Added check for targetOrderIndex
      return;
    }
    // targetContentListIndex might be legitimately null if dropping on a timeline box, but not here.
    // However, for _handleItemDropOnExistingItem, targetContentListIndex is expected.
    if (targetContentListIndex == null) {
      return;
    }

    if (!_timelineEntriesByDate.containsKey(sourceTimestamp) ||
        _timelineEntriesByDate[sourceTimestamp]!.isEmpty) {
      return;
    }
    final sourceEntry = _timelineEntriesByDate[sourceTimestamp]!.first;

    if (!_timelineEntriesByDate.containsKey(targetTimestamp)) {
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
          return;
        }
        final TimelineItemRef movedItemOrderRef =
            sourceEntry.itemOrder[sourceOrderIndex];

        if (movedItemOrderRef.type != sourceType ||
            movedItemOrderRef.index != sourceContentListIndex) {
          return;
        }

        final ItemType currentMovedItemType = movedItemOrderRef.type;
        final int currentMovedItemContentListIndex = movedItemOrderRef.index;
        dynamic movedItemContent;

        if (currentMovedItemType == ItemType.note) {
          if (currentMovedItemContentListIndex < 0 ||
              currentMovedItemContentListIndex >= sourceEntry.notes.length) {
            return;
          }
          movedItemContent =
              sourceEntry.notes.removeAt(currentMovedItemContentListIndex);
        } else {
          if (currentMovedItemContentListIndex < 0 ||
              currentMovedItemContentListIndex >= sourceEntry.tasks.length) {
            return;
          }
          movedItemContent =
              sourceEntry.tasks.removeAt(currentMovedItemContentListIndex);
        }

        sourceEntry.itemOrder.removeAt(sourceOrderIndex);

        for (final ref in sourceEntry.itemOrder) {
          if (ref.type == currentMovedItemType &&
              ref.index > currentMovedItemContentListIndex) {
            ref.index--;
          }
        }

        int finalTargetOrderIndex = targetOrderIndex;
        if (sourceTimestamp == targetTimestamp &&
            sourceOrderIndex < targetOrderIndex) {
          finalTargetOrderIndex--;
        }
        if (insertPosition == 'after') {
          finalTargetOrderIndex++;
        }
        finalTargetOrderIndex = math.min(
            math.max(0, finalTargetOrderIndex), targetEntry.itemOrder.length);

        int newContentListIndexInTarget;
        if (currentMovedItemType == ItemType.note) {
          newContentListIndexInTarget = targetEntry.notes.length;
          targetEntry.notes.add(movedItemContent as String);
        } else {
          newContentListIndexInTarget = targetEntry.tasks.length;
          targetEntry.tasks.add(movedItemContent as TaskItem);
        }

        final TimelineItemRef newTargetItemOrderRef = TimelineItemRef(
          type: currentMovedItemType,
          index: newContentListIndexInTarget,
          storageId: sourceStorageId, // Ensure storageId is passed
        );
        targetEntry.itemOrder
            .insert(finalTargetOrderIndex, newTargetItemOrderRef);

        if (sourceEntry.notes.isEmpty &&
            sourceEntry.tasks.isEmpty &&
            sourceEntry.itemOrder.isEmpty) {
          _timelineEntriesByDate.remove(sourceTimestamp);
        }
      } catch (e) {}
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
    final sourceStorageId =
        data['storage_id'] as String? ?? ''; // <<< EXTRACTED

    if (sourceOrderIndex == null) {
      return;
    }
    if (sourceContentListIndex == null) {
      // Added check for sourceContentListIndex
      return;
    }

    if (!_timelineEntriesByDate.containsKey(sourceTimestamp) ||
        _timelineEntriesByDate[sourceTimestamp]!.isEmpty) {
      return;
    }
    final sourceEntry = _timelineEntriesByDate[sourceTimestamp]!.first;

    if (!_timelineEntriesByDate.containsKey(targetTimestamp)) {
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
          return;
        }
        final TimelineItemRef movedItemOrderRef =
            sourceEntry.itemOrder[sourceOrderIndex];

        if (movedItemOrderRef.type != sourceItemTypeFromDraggable ||
            movedItemOrderRef.index != sourceContentListIndex) {
          return;
        }

        final ItemType actualMovedItemType = movedItemOrderRef.type;
        final int actualMovedItemContentListIndex = movedItemOrderRef.index;
        dynamic movedItemContent;

        if (actualMovedItemType == ItemType.note) {
          if (actualMovedItemContentListIndex < 0 ||
              actualMovedItemContentListIndex >= sourceEntry.notes.length) {
            return;
          }
          movedItemContent =
              sourceEntry.notes.removeAt(actualMovedItemContentListIndex);
        } else {
          // ItemType.task
          if (actualMovedItemContentListIndex < 0 ||
              actualMovedItemContentListIndex >= sourceEntry.tasks.length) {
            return;
          }
          movedItemContent =
              sourceEntry.tasks.removeAt(actualMovedItemContentListIndex);
        }

        sourceEntry.itemOrder.removeAt(sourceOrderIndex);

        for (final ref in sourceEntry.itemOrder) {
          if (ref.type == actualMovedItemType &&
              ref.index > actualMovedItemContentListIndex) {
            ref.index--;
          }
        }

        // 2. Add item to target content list (always at the end)
        int newContentListIndexInTarget;
        if (actualMovedItemType == ItemType.note) {
          newContentListIndexInTarget = targetEntry.notes.length;
          targetEntry.notes.add(movedItemContent as String);
        } else {
          // ItemType.task
          newContentListIndexInTarget = targetEntry.tasks.length;
          targetEntry.tasks.add(movedItemContent as TaskItem);
        }

        // 3. Create new TimelineItemRef and append to targetEntry.itemOrder
        final TimelineItemRef newTargetItemOrderRef = TimelineItemRef(
          type:
              actualMovedItemType, // Use the actual type of the item that was moved
          index: newContentListIndexInTarget,
          storageId: sourceStorageId, // Ensure storageId is passed
        );
        targetEntry.itemOrder.add(newTargetItemOrderRef); // Append to the end

        // 4. Cleanup source entry if empty
        if (sourceEntry.notes.isEmpty &&
            sourceEntry.tasks.isEmpty &&
            sourceEntry.itemOrder.isEmpty) {
          _timelineEntriesByDate.remove(sourceTimestamp);
        }
      } catch (e) {}
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
  Widget _buildTaskItem(TaskItem task, String timestamp, int orderIndex,
      String storageId, RiveCheckboxController controller,
      {bool isFirstItem = false}) {
    const double riveDisplaySize = 36.0; // Set exact size as requested
    const double desiredLayoutHeight = riveDisplaySize; // Don't reduce height

    // Original X/Y offset values
    const double xOffset = -2.0;
    const double yOffset = -2.0;

    // Estimate if the text is likely a single line - this is a rough estimate based on character count
    // You may need to adjust this threshold based on your font size and container width
    final bool isLikelySingleLine =
        task.task.length < 40; // Assuming average 40 chars fit on a line

    // Adjust padding based on line count
    final double textTopPadding = isLikelySingleLine ? 8.0 : 3.0;
    final double containerBottomPadding = isLikelySingleLine
        ? 4.0
        : 8.0; // Reduced bottom padding for single line

    return Container(
      padding: EdgeInsets.only(
        left: 3.0, // Exact left padding as requested
        right: 12.0, // Keep original right padding
        top: isFirstItem ? 5.0 : 3.0, // Exact top padding as requested
        bottom:
            containerBottomPadding, // Adjusted bottom padding based on line count
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: riveDisplaySize,
            height: desiredLayoutHeight,
            child: ClipRect(
              child: Transform.translate(
                offset: Offset(xOffset, yOffset),
                child: RiveCheckbox(
                  isChecked: task.completed,
                  controller: controller,
                  onChanged: (bool? newValue) {
                    if (newValue == null) return;
                    _updateItem(
                      timestamp: timestamp,
                      orderIndexInItemOrder: orderIndex,
                      newItemType: ItemType.task,
                      newContent: task.task,
                      newCompleted: newValue,
                      originalItemType: ItemType.task,
                      storageId: storageId,
                    );
                  },
                  size: riveDisplaySize,
                ),
              ),
            ),
          ),
          const SizedBox(width: 0), // No gap as requested
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                top: textTopPadding, // Adjusted based on line count
                bottom: isLikelySingleLine
                    ? 0.0
                    : 1.0, // Slight adjustment to vertical spacing for single line
              ),
              child: GestureDetector(
                onTap: () {
                  _updateItem(
                    timestamp: timestamp,
                    orderIndexInItemOrder: orderIndex,
                    newItemType: ItemType.task,
                    newContent: task.task,
                    newCompleted: !task.completed,
                    originalItemType: ItemType.task,
                    storageId: storageId,
                  );
                  controller.fire();
                },
                child: Text(
                  task.task,
                  style: TextStyle(
                    fontSize: 16,
                    fontFamily: 'Geist',
                    fontWeight: FontWeight.w500,
                    decoration:
                        task.completed ? TextDecoration.lineThrough : null,
                    decorationColor:
                        task.completed ? Colors.grey.shade400 : null,
                    color: task.completed ? Colors.grey.shade400 : Colors.black,
                    height: isLikelySingleLine
                        ? 1.0
                        : 1.5, // Tighter line height for single line text
                  ),
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
                _addNote();
              },
              elevation: 0, // Set to 0 to use our custom shadow
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(width: 2, color: Color(0xFFE1E1E1)),
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
                  shadows: const [
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
                _addTask();
              },
              elevation: 0, // Set to 0 to use our custom shadow
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(width: 2, color: Color(0xFFE1E1E1)),
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
                  shadows: const [
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
                _startRecording();
              },
              elevation: 0, // Set to 0 to use our custom shadow
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(width: 2, color: Colors.white),
              ),
              padding: EdgeInsets.zero,
              minWidth: 62,
              height: 62,
              color: Colors.transparent,
              child: Container(
                width: 62,
                height: 62,
                clipBehavior: Clip.antiAlias,
                decoration: ShapeDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment(-0.00, -0.00),
                    end: Alignment(1.00, 1.00),
                    colors: [Color(0xFF598FFF), Color(0xFF1E44FF)],
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  shadows: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 17.60,
                      offset: Offset(0, 4),
                      spreadRadius: 0,
                    )
                  ],
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/record_icon.svg',
                    width: 24,
                    height: 24,
                    colorFilter:
                        const ColorFilter.mode(Colors.white, BlendMode.srcIn),
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
              gradient: const LinearGradient(
                begin: Alignment(-0.00, -0.00),
                end: Alignment(1.00, 1.00),
                colors: [Color(0xFF413F3F), Color(0xFF0C0C0C)],
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              shadows: const [
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

    List<TextEditingController> textControllers = [TextEditingController()];
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
                        const gap = 4.0; // 4 pixel gap between tabs
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
                                        // Reload entries when switching tabs to ensure fresh data
                                        // This ensures we're properly refreshing from storage
                                        if (mounted) {
                                          _loadEntriesForSelectedDate();
                                        }
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
                                        // Reload entries when switching tabs to ensure fresh data
                                        // This ensures we're properly refreshing from storage
                                        if (mounted) {
                                          _loadEntriesForSelectedDate();
                                        }
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
                          itemCount: textControllers.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: TextField(
                                key: ValueKey(
                                    'textfield_${index}_${textControllers[index].hashCode}'), // Unique key for each field
                                controller: textControllers[index],
                                focusNode: _sheetFocusNodes[
                                    index], // Use class-level list
                                minLines: 3,
                                maxLines: 5,
                                // autofocus: index == 0, // Replaced by manual requestFocus
                                decoration: InputDecoration(
                                  hintText: selectedType == 'Notes'
                                      ? "I've been thinking about..."
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
                                setModalState(() {
                                  final newController = TextEditingController();
                                  final newFocusNode = FocusNode();
                                  textControllers.add(newController);
                                  _sheetFocusNodes.add(
                                      newFocusNode); // Add to class-level list

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
                                  borderRadius: BorderRadius.circular(8),
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
                                      fontWeight: FontWeight.w600,
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
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              bool anEntryWasAdded = false;
                              for (var controller in textControllers) {
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
        existingUiEntry.itemOrder.add(TimelineItemRef(
            type: ItemType.note,
            index: newNoteIndex,
            storageId: storageEntry.id));
      } else {
        // Create new entry for this timestamp
        const newNoteIndex = 0;
        final newUiEntry = TimelineEntry(
          timestamp: timestamp,
          isDaytime: isDaytime,
          notes: [noteText],
          tasks: [],
          itemOrder: [
            TimelineItemRef(
                type: ItemType.note,
                index: newNoteIndex,
                storageId: storageEntry.id)
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
        existingUiEntry.itemOrder.add(TimelineItemRef(
            type: ItemType.task,
            index: newTaskIndex,
            storageId: storageEntry.id));
      } else {
        // Create new entry for this timestamp
        const newTaskIndex = 0;
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
            TimelineItemRef(
                type: ItemType.task,
                index: newTaskIndex,
                storageId: storageEntry.id)
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
  final String storageId; // ID from models.TimelineEntry

  TimelineItemRef(
      {required this.type, required this.index, required this.storageId});

  @override
  String toString() => '$type:$index (ID:$storageId)';
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
  const RecordingPage({super.key});

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

// Add PulsingDot class at the end of the file
class PulsingDot extends StatefulWidget {
  // ignore: use_super_parameters
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
