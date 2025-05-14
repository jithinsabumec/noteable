import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'config.dart';
import 'services/deepseek_service.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:device_info_plus/device_info_plus.dart';
import 'time_icons.dart';
import 'package:zelo/services/storage_service.dart';
import 'package:zelo/models/timeline_entry.dart' as models;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
      home: const MainScreen(),
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
  bool _isAnalyzing = false;
  final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();
  DateTime _selectedDate = DateTime.now();

  // State for drag mode
  String? _dragItemTimestamp;
  int? _dragItemIndex;
  bool? _dragItemIsTask;

  // Use the new storage service
  final _storageService = StorageService();
  // Map to store entries by timestamp for the currently selected date
  final Map<String, List<TimelineEntry>> _timelineEntriesByDate = {};

  @override
  void initState() {
    super.initState();
    // Clear any placeholder data (run this only once when testing)
    _clearPlaceholderData();
    // Load entries for the current date
    _loadEntriesForSelectedDate();
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
            _timelineEntriesByDate[timestamp] = [
              TimelineEntry(
                timestamp: timestamp,
                isDaytime: isDaytime,
                notes: [entry.content],
                tasks: [],
              )
            ];
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
              ));
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
              )
            ];
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
              ));
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

  @override
  void dispose() {
    _audioRecorder.dispose();
    super.dispose();
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

  Future<void> _startRecording() async {
    try {
      // Dismiss keyboard explicitly to ensure clean UI
      FocusManager.instance.primaryFocus?.unfocus();

      // Check permissions before starting recording
      final permissionsGranted = await _checkPermissions();
      if (!permissionsGranted) {
        // Show explicit error message for emulators
        final deviceInfo = await _deviceInfoPlugin.androidInfo;
        final isEmulator = deviceInfo.isPhysicalDevice != null &&
            !deviceInfo.isPhysicalDevice!;

        if (isEmulator) {
          // For emulators, show a specific message and try to request permissions directly
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Running on emulator - requesting storage permission directly'),
              duration: Duration(seconds: 3),
            ),
          );

          // Directly request storage permissions for emulators
          if (await Permission.storage.request().isGranted ||
              await Permission.manageExternalStorage.request().isGranted) {
            // If granted, continue with recording
            await _startRecordingProcess();
            return;
          }
        }
        return;
      }

      await _startRecordingProcess();
    } catch (e) {
      print('Error starting recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Error starting recording: ${e.toString().substring(0, math.min(100, e.toString().length))}'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Extracted method to start the actual recording process
  Future<void> _startRecordingProcess() async {
    final directory = await getTemporaryDirectory();
    _recordedFilePath =
        '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

    print('Recording file path: $_recordedFilePath');

    // Start recording with updated configuration for Record 6.0.0
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
      _transcribedText = '';
    });
  }

  Future<void> _pauseRecording() async {
    try {
      if (_isPaused) {
        await _audioRecorder.resume();
      } else {
        await _audioRecorder.pause();
      }
      setState(() => _isPaused = !_isPaused);
    } catch (e) {
      print('Error pausing/resuming recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error pausing/resuming recording: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _transcribeAudio(String filePath) async {
    setState(() {
      _isTranscribing = true;
      _transcribedText = 'Transcribing...';
    });

    try {
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
          setState(() {
            _transcribedText = statusData['text'];
            _isTranscribing = false;
          });

          // Now analyze the text with DeepSeek
          await _analyzeWithDeepSeek(_transcribedText);
          break;
        } else if (statusData['status'] == 'error') {
          throw Exception('Transcription failed: ${statusData['error']}');
        }

        await Future.delayed(const Duration(seconds: 3));
      }
    } catch (e) {
      print('Error transcribing audio: $e');
      setState(() {
        _transcribedText = 'Error transcribing audio: $e';
        _isTranscribing = false;
      });
    }
  }

  Future<void> _analyzeWithDeepSeek(String text) async {
    if (text.isEmpty) return;

    setState(() {
      _isAnalyzing = true;
    });

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
          )
        ];

        _isAnalyzing = false;
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(
                  bottom: 80.0, top: 16.0, left: 24.0, right: 24.0),
              child: SingleChildScrollView(
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
                  ],
                ),
              ),
            ),

            if (_isTranscribing || _isAnalyzing)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                  child: Center(
                    child: Card(
                      color: Theme.of(context).cardColor,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              _isTranscribing
                                  ? 'Transcribing your recording...'
                                  : 'Analyzing your recording...',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Expandable FAB at the bottom right corner
            Positioned(
              right: 16,
              bottom: 16,
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
    // Get appropriate time icon based on timestamp
    final timeIcon = TimeIcons.getTimeIcon(entry.timestamp);

    // Combined items list for sorting
    List<Widget> contentWidgets = [];

    // Create individual cards for each note
    for (int i = 0; i < entry.notes.length; i++) {
      final note = entry.notes[i];
      contentWidgets.add(
        _buildDraggableNote(note, timestamp, i),
      );
    }

    // Create individual cards for each task
    for (int i = 0; i < entry.tasks.length; i++) {
      final task = entry.tasks[i];
      contentWidgets.add(
        _buildDraggableTask(task, timestamp, i),
      );
    }

    // Show message if no content
    if (entry.notes.isEmpty && entry.tasks.isEmpty) {
      contentWidgets.add(
        DragTarget<Map<String, dynamic>>(
          onAccept: (data) {
            _handleItemDrop(data, timestamp);
          },
          builder: (context, candidateData, rejectedData) {
            return Container(
              margin: const EdgeInsets.only(left: 4.0, right: 4.0, bottom: 4.0),
              padding: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: candidateData.isNotEmpty
                    ? Colors.grey.shade200
                    : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFFE1E1E1),
                  width: 1,
                ),
              ),
              child: const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Drop items here'),
                ),
              ),
            );
          },
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEEEE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFE4E4E4),
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
          // Wrap the content in a DragTarget to allow dropping items
          DragTarget<Map<String, dynamic>>(
            onAccept: (data) {
              _handleItemDrop(data, timestamp);
            },
            builder: (context, candidateData, rejectedData) {
              return Column(
                children: contentWidgets,
              );
            },
          ),
        ],
      ),
    );
  }

  // Build a draggable note item
  Widget _buildDraggableNote(String note, String timestamp, int index) {
    final bool isDragMode = _dragItemTimestamp == timestamp &&
        _dragItemIndex == index &&
        _dragItemIsTask == false;

    if (isDragMode) {
      return LongPressDraggable<Map<String, dynamic>>(
        data: {
          'type': 'note',
          'content': note,
          'source_timestamp': timestamp,
          'index': index,
        },
        feedback: Material(
          elevation: 4.0,
          child: Container(
            width: MediaQuery.of(context).size.width - 80,
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.blue.shade200,
                width: 2,
              ),
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
        childWhenDragging: Opacity(
          opacity: 0.5,
          child: Container(
            margin: const EdgeInsets.only(left: 4.0, right: 4.0, bottom: 4.0),
            padding: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFFE1E1E1),
                width: 1,
              ),
            ),
            child: _buildNoteItem(note, isFirstItem: true),
          ),
        ),
        onDragCompleted: () {
          // Reset drag mode when done
          setState(() {
            _dragItemTimestamp = null;
            _dragItemIndex = null;
            _dragItemIsTask = null;
          });
        },
        onDraggableCanceled: (_, __) {
          // Reset drag mode if canceled
          setState(() {
            _dragItemTimestamp = null;
            _dragItemIndex = null;
            _dragItemIsTask = null;
          });
        },
        child: Container(
          margin: const EdgeInsets.only(left: 4.0, right: 4.0, bottom: 4.0),
          width: double.infinity,
          padding: EdgeInsets.zero,
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
              _buildNoteItem(note, isFirstItem: true),
              Positioned(
                top: 0,
                right: 0,
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
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onLongPress: () {
        _showItemOptions(
          context: context,
          timestamp: timestamp,
          index: index,
          isTask: false,
          content: note,
        );
      },
      child: DragTarget<Map<String, dynamic>>(
        onAccept: (data) {
          _handleItemDropOnExistingItem(
              data, timestamp, {'type': 'note', 'index': index});
        },
        builder: (context, candidateData, rejectedData) {
          return Container(
            margin: const EdgeInsets.only(left: 4.0, right: 4.0, bottom: 4.0),
            width: double.infinity,
            padding: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color:
                  candidateData.isNotEmpty ? Colors.blue.shade50 : Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: candidateData.isNotEmpty
                    ? Colors.blue.shade200
                    : const Color(0xFFE1E1E1),
                width: 1,
              ),
            ),
            child: _buildNoteItem(note, isFirstItem: true),
          );
        },
      ),
    );
  }

  // Build a draggable task item
  Widget _buildDraggableTask(TaskItem task, String timestamp, int index) {
    final bool isDragMode = _dragItemTimestamp == timestamp &&
        _dragItemIndex == index &&
        _dragItemIsTask == true;

    if (isDragMode) {
      return LongPressDraggable<Map<String, dynamic>>(
        data: {
          'type': 'task',
          'content': task.task,
          'completed': task.completed,
          'source_timestamp': timestamp,
          'index': index,
        },
        feedback: Material(
          elevation: 4.0,
          child: Container(
            width: MediaQuery.of(context).size.width - 80,
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.green.shade200,
                width: 2,
              ),
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
                      decoration:
                          task.completed ? TextDecoration.lineThrough : null,
                      decorationColor:
                          task.completed ? Colors.grey.shade400 : null,
                      color:
                          task.completed ? Colors.grey.shade400 : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.5,
          child: Container(
            margin: const EdgeInsets.only(left: 4.0, right: 4.0, bottom: 4.0),
            padding: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFFE1E1E1),
                width: 1,
              ),
            ),
            child: _buildTaskItem(task, isFirstItem: true),
          ),
        ),
        onDragCompleted: () {
          // Reset drag mode when done
          setState(() {
            _dragItemTimestamp = null;
            _dragItemIndex = null;
            _dragItemIsTask = null;
          });
        },
        onDraggableCanceled: (_, __) {
          // Reset drag mode if canceled
          setState(() {
            _dragItemTimestamp = null;
            _dragItemIndex = null;
            _dragItemIsTask = null;
          });
        },
        child: Container(
          margin: const EdgeInsets.only(left: 4.0, right: 4.0, bottom: 4.0),
          width: double.infinity,
          padding: EdgeInsets.zero,
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
              _buildTaskItem(task, isFirstItem: true),
              Positioned(
                top: 0,
                right: 0,
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
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onLongPress: () {
        _showItemOptions(
          context: context,
          timestamp: timestamp,
          index: index,
          isTask: true,
          content: task.task,
          completed: task.completed,
        );
      },
      child: DragTarget<Map<String, dynamic>>(
        onAccept: (data) {
          _handleItemDropOnExistingItem(
              data, timestamp, {'type': 'task', 'index': index});
        },
        builder: (context, candidateData, rejectedData) {
          return Container(
            margin: const EdgeInsets.only(left: 4.0, right: 4.0, bottom: 4.0),
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
    required int index,
    required bool isTask,
    required String content,
    bool? completed,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                      index: index,
                      isTask: isTask,
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
                    _deleteItem(timestamp, index, isTask);
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
                      _dragItemIndex = index;
                      _dragItemIsTask = isTask;
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
    required int index,
    required bool isTask,
    required String content,
    bool? completed,
  }) {
    final TextEditingController controller =
        TextEditingController(text: content);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(isTask ? 'Edit Task' : 'Edit Note'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLines: isTask ? 1 : 5,
                decoration: InputDecoration(
                  hintText: isTask ? 'Task' : 'Note',
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              if (isTask)
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
                  index: index,
                  isTask: isTask,
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
    required int index,
    required bool isTask,
    required String newContent,
    bool? newCompleted,
  }) {
    if (newContent.isEmpty) return;

    setState(() {
      if (isTask) {
        _timelineEntriesByDate[timestamp]![index] = TimelineEntry(
          timestamp: timestamp,
          isDaytime: _timelineEntriesByDate[timestamp]![index].isDaytime,
          notes: [newContent],
          tasks: [
            TaskItem(
              task: newContent,
              completed: newCompleted ??
                  _timelineEntriesByDate[timestamp]![index]
                      .tasks[index]
                      .completed,
            ),
          ],
        );
      } else {
        _timelineEntriesByDate[timestamp]![index] = TimelineEntry(
          timestamp: timestamp,
          isDaytime: _timelineEntriesByDate[timestamp]![index].isDaytime,
          notes: [newContent],
          tasks: _timelineEntriesByDate[timestamp]!
              .map((e) => e.tasks[index])
              .toList(),
        );
      }
    });
  }

  // Delete a note or task
  void _deleteItem(String timestamp, int index, bool isTask) {
    setState(() {
      if (isTask) {
        _timelineEntriesByDate[timestamp]!.removeAt(index);
      } else {
        _timelineEntriesByDate[timestamp]![index] = TimelineEntry(
          timestamp: timestamp,
          isDaytime: _timelineEntriesByDate[timestamp]![index].isDaytime,
          notes: [],
          tasks: [],
        );
      }

      // Remove the timestamp entry if it's now empty
      if (_timelineEntriesByDate[timestamp]!.isEmpty) {
        _timelineEntriesByDate.remove(timestamp);
      }
    });
  }

  // Handle dropping item onto a timestamp section
  void _handleItemDrop(Map<String, dynamic> data, String targetTimestamp) {
    final sourceTimestamp = data['source_timestamp'];
    final index = data['index'];
    final type = data['type'];

    setState(() {
      if (type == 'note') {
        // Get the note content
        final noteContent =
            _timelineEntriesByDate[sourceTimestamp]![0].notes[index];

        // Remove it from source
        _timelineEntriesByDate[sourceTimestamp]![0].notes.removeAt(index);

        // Remove the source entry if it's now empty
        if (_timelineEntriesByDate[sourceTimestamp]![0].notes.isEmpty &&
            _timelineEntriesByDate[sourceTimestamp]![0].tasks.isEmpty) {
          _timelineEntriesByDate.remove(sourceTimestamp);
        }

        // Add it to the target timestamp
        if (_timelineEntriesByDate.containsKey(targetTimestamp)) {
          _timelineEntriesByDate[targetTimestamp]![0].notes.add(noteContent);
        } else {
          // Create a new entry if needed
          final isDaytime = _isTimestampDaytime(targetTimestamp);
          _timelineEntriesByDate[targetTimestamp] = [
            TimelineEntry(
              timestamp: targetTimestamp,
              isDaytime: isDaytime,
              notes: [noteContent],
              tasks: [],
            )
          ];
        }
      } else if (type == 'task') {
        // Get the task
        final task = _timelineEntriesByDate[sourceTimestamp]![0].tasks[index];

        // Remove it from source
        _timelineEntriesByDate[sourceTimestamp]![0].tasks.removeAt(index);

        // Remove the source entry if it's now empty
        if (_timelineEntriesByDate[sourceTimestamp]![0].notes.isEmpty &&
            _timelineEntriesByDate[sourceTimestamp]![0].tasks.isEmpty) {
          _timelineEntriesByDate.remove(sourceTimestamp);
        }

        // Add it to the target timestamp
        if (_timelineEntriesByDate.containsKey(targetTimestamp)) {
          _timelineEntriesByDate[targetTimestamp]![0].tasks.add(task);
        } else {
          // Create a new entry if needed
          final isDaytime = _isTimestampDaytime(targetTimestamp);
          _timelineEntriesByDate[targetTimestamp] = [
            TimelineEntry(
              timestamp: targetTimestamp,
              isDaytime: isDaytime,
              notes: [],
              tasks: [task],
            )
          ];
        }
      }
    });
  }

  // Handle dropping item onto another item (for re-ordering)
  void _handleItemDropOnExistingItem(Map<String, dynamic> droppedItemData,
      String targetTimestamp, Map<String, dynamic> targetItemData) {
    final sourceTimestamp = droppedItemData['source_timestamp'];
    final sourceIndex = droppedItemData['index'];
    final sourceType = droppedItemData['type'];

    final targetIndex = targetItemData['index'];
    final targetType = targetItemData['type'];

    // If it's the same type and timestamp, it's a reordering
    if (sourceType == targetType && sourceTimestamp == targetTimestamp) {
      setState(() {
        if (sourceType == 'note') {
          final notesArray =
              _timelineEntriesByDate[sourceTimestamp]!.first.notes;
          final note = notesArray.removeAt(sourceIndex);
          // Add at the new position
          notesArray.insert(targetIndex, note);
        } else if (sourceType == 'task') {
          final tasksArray =
              _timelineEntriesByDate[sourceTimestamp]!.first.tasks;
          final task = tasksArray.removeAt(sourceIndex);
          // Add at the new position
          tasksArray.insert(targetIndex, task);
        }
      });
    } else {
      // Different types or timestamps, handle as a regular move
      _handleItemDrop(droppedItemData, targetTimestamp);
    }
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
                  height: 24 / 16,
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
        // Add note button (visible when expanded)
        if (_isFabExpanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: FloatingActionButton(
              heroTag: 'note',
              onPressed: _addNote,
              backgroundColor: Colors.green,
              child: const Icon(Icons.edit_note),
            ),
          ),

        // Add task button (visible when expanded)
        if (_isFabExpanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: FloatingActionButton(
              heroTag: 'task',
              onPressed: _addTask,
              backgroundColor: Colors.blue,
              child: const Icon(Icons.check_box_outlined),
            ),
          ),

        // Record button (visible when expanded)
        if (_isFabExpanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: FloatingActionButton(
              heroTag: 'record',
              onPressed: _startRecording,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.mic),
            ),
          ),

        // Main FAB (plus/close)
        FloatingActionButton(
          onPressed: _toggleFabExpanded,
          backgroundColor: _isFabExpanded
              ? Colors.black
              : Theme.of(context).colorScheme.primary,
          child: Icon(_isFabExpanded ? Icons.close : Icons.add),
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

    // Create a controller for the text field
    final TextEditingController controller = TextEditingController();

    // Create a dialog to get note content
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Note'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Enter your note here...',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              _createNoteEntry(value);
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _createNoteEntry(controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // Add a new task directly
  void _addTask() {
    _toggleFabExpanded(); // Close the menu

    // Create a controller for the text field
    final TextEditingController controller = TextEditingController();

    // Create a dialog to get task content
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Task'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter your task here...',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              _createTaskEntry(value);
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _createTaskEntry(controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
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
    final entry = models.TimelineEntry(
      id: _storageService.generateId(),
      content: noteText,
      timestamp: now,
      type: models.EntryType.note,
      completed: false,
    );

    // Save to storage
    _storageService.saveEntry(entry);

    // Update UI
    setState(() {
      final existingEntry = _timelineEntriesByDate[timestamp];

      if (existingEntry != null) {
        // Add to existing entry for this timestamp
        existingEntry.first.notes.add(noteText);
      } else {
        // Create new entry for this timestamp
        _timelineEntriesByDate[timestamp] = [
          TimelineEntry(
            timestamp: timestamp,
            isDaytime: isDaytime,
            notes: [noteText],
            tasks: [],
          )
        ];
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
    final entry = models.TimelineEntry(
      id: _storageService.generateId(),
      content: taskText,
      timestamp: now,
      type: models.EntryType.task,
      completed: false,
    );

    // Save to storage
    _storageService.saveEntry(entry);

    // Update UI
    setState(() {
      final existingEntry = _timelineEntriesByDate[timestamp];

      if (existingEntry != null) {
        // Add to existing entry for this timestamp
        existingEntry.first.tasks.add(TaskItem(
          task: taskText,
          completed: false,
        ));
      } else {
        // Create new entry for this timestamp
        _timelineEntriesByDate[timestamp] = [
          TimelineEntry(
            timestamp: timestamp,
            isDaytime: isDaytime,
            notes: [],
            tasks: [
              TaskItem(
                task: taskText,
                completed: false,
              )
            ],
          )
        ];
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

  TimelineEntry({
    required this.timestamp,
    required this.isDaytime,
    required this.notes,
    required this.tasks,
  });
}

class TaskItem {
  String task;
  bool completed;

  TaskItem({
    required this.task,
    this.completed = false,
  });
}
