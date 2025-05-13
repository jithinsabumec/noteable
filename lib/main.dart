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

void main() {
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
  final List<TodoItem> _todos = [];
  final List<IdeaItem> _ideas = [];
  final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();

  @override
  void initState() {
    super.initState();
    // Initialize with sample data that matches the image
    _todos.addAll([
      TodoItem(task: 'official launch', dueDate: '1 September'),
      TodoItem(task: 'start user testing', dueDate: '5 August'),
      TodoItem(task: 'secure initial funding', dueDate: '15 July'),
      TodoItem(task: 'launch the MVP', dueDate: '20 June'),
      TodoItem(task: 'find a co-founder', dueDate: '11 May', completed: true),
      TodoItem(
          task: 'partner with a visionary co-founder',
          dueDate: '1 May',
          completed: true),
    ]);

    _ideas.addAll([
      IdeaItem(idea: 'official launch', date: '1 September'),
      IdeaItem(idea: 'beta testing', date: '15 August'),
      IdeaItem(idea: 'design review', date: '5 June'),
      IdeaItem(idea: 'prototype completion', date: '10 May'),
    ]);
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
        return;
      }

      final directory = await getTemporaryDirectory();
      _recordedFilePath =
          '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      print('Recording file path: $_recordedFilePath');

      // Start recording directly without checking permissions again
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
        _transcribedText = '';
      });
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

      setState(() {
        if (result['todos'] != null && result['todos'].isNotEmpty) {
          final todoStrings = List<String>.from(result['todos']);
          _todos.addAll(todoStrings.map((todoText) => TodoItem(
                task: todoText,
                dueDate:
                    '', // Empty date since it's not parsed from the transcription
              )));
        }
        if (result['ideas'] != null && result['ideas'].isNotEmpty) {
          final ideaStrings = List<String>.from(result['ideas']);
          _ideas.addAll(ideaStrings.map((ideaText) => IdeaItem(
                idea: ideaText,
                date:
                    '', // Empty date since it's not parsed from the transcription
              )));
        }
        _isAnalyzing = false;
      });

      // Show a snackbar with the results
      final String message = _buildResultMessage(result);
      if (message.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('Error analyzing with DeepSeek: $e');
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  String _buildResultMessage(Map<String, dynamic> result) {
    final todoCount = result['todos']?.length ?? 0;
    final ideaCount = result['ideas']?.length ?? 0;

    if (todoCount > 0 && ideaCount > 0) {
      return 'Added $todoCount to-dos and $ideaCount ideas';
    } else if (todoCount > 0) {
      return 'Added $todoCount to-do${todoCount > 1 ? 's' : ''}';
    } else if (ideaCount > 0) {
      return 'Added $ideaCount idea${ideaCount > 1 ? 's' : ''}';
    }

    return '';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(
                  bottom: 80.0, top: 16.0, left: 16.0, right: 16.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // To-do Box
                    Container(
                      margin: const EdgeInsets.only(bottom: 16.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEEEEE),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFE4E4E4),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x19000000),
                            blurRadius: 17.60,
                            offset: const Offset(0, 4),
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Container(
                            padding: const EdgeInsets.only(
                                top: 8.0, left: 16.0, right: 16.0, bottom: 8.0),
                            decoration: const BoxDecoration(
                              color: Color(0xFFEEEEEE),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_box_outlined,
                                  color: Colors.black,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'to-do',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF282828),
                                    fontFamily: 'InstrumentSerif',
                                    letterSpacing: 0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Content - Todo list
                          Container(
                            margin: const EdgeInsets.only(
                                top: 0, left: 4.0, right: 4.0, bottom: 4.0),
                            padding: EdgeInsets.zero,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFFE1E1E1),
                                width: 1,
                              ),
                            ),
                            child: _todos.isEmpty
                                ? const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: Text(
                                          'No to-dos yet. Record your first to-do!'),
                                    ),
                                  )
                                : Column(
                                    children:
                                        _todos.asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final todo = entry.value;
                                      return Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Padding(
                                          padding: EdgeInsets.only(
                                            left: 12.0,
                                            right: 12.0,
                                            top: index == 0 ? 12.0 : 0.0,
                                            bottom: 8.0,
                                          ),
                                          child: Row(
                                            children: [
                                              GestureDetector(
                                                onTap: () {
                                                  setState(() {
                                                    todo.completed =
                                                        !todo.completed;
                                                  });
                                                },
                                                child: Container(
                                                  width: 16,
                                                  height: 16,
                                                  decoration: BoxDecoration(
                                                    color: todo.completed
                                                        ? Colors.black
                                                        : Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4.0),
                                                    border: Border.all(
                                                      width: 1.0,
                                                      color: const Color(
                                                          0xFF282828),
                                                    ),
                                                  ),
                                                  child: todo.completed
                                                      ? Center(
                                                          child: CustomPaint(
                                                            size: const Size(
                                                                10, 7.5),
                                                            painter:
                                                                CheckmarkPainter(),
                                                          ),
                                                        )
                                                      : null,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  todo.task,
                                                  style: TextStyle(
                                                    fontSize: 18,
                                                    fontWeight:
                                                        FontWeight.normal,
                                                    decoration: todo.completed
                                                        ? TextDecoration
                                                            .lineThrough
                                                        : null,
                                                    decorationColor: todo
                                                            .completed
                                                        ? Colors.grey.shade400
                                                        : null,
                                                    color: todo.completed
                                                        ? Colors.grey.shade400
                                                        : Colors.black,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                todo.dueDate,
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  color: todo.completed
                                                      ? Colors.grey.shade400
                                                      : const Color(0xFF9D9D9D),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                          ),
                        ],
                      ),
                    ),

                    // Ideas Box
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEEEEE),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFE4E4E4),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x19000000),
                            blurRadius: 17.60,
                            offset: const Offset(0, 4),
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Container(
                            padding: const EdgeInsets.only(
                                top: 8.0, left: 16.0, right: 16.0, bottom: 8.0),
                            decoration: const BoxDecoration(
                              color: Color(0xFFEEEEEE),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.lightbulb_outline,
                                  color: Colors.black,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'ideas',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF282828),
                                    fontFamily: 'InstrumentSerif',
                                    letterSpacing: 0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Content - Ideas list
                          Container(
                            margin: const EdgeInsets.only(
                                top: 8.0, left: 4.0, right: 4.0, bottom: 4.0),
                            padding: EdgeInsets.zero,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFFE1E1E1),
                                width: 1,
                              ),
                            ),
                            child: _ideas.isEmpty
                                ? const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: Text(
                                          'No ideas yet. Record your first idea!'),
                                    ),
                                  )
                                : Column(
                                    children:
                                        _ideas.asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final idea = entry.value;
                                      return Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Padding(
                                          padding: EdgeInsets.only(
                                            left: 12.0,
                                            right: 12.0,
                                            top: index == 0 ? 12.0 : 16.0,
                                            bottom: 16.0,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                margin: const EdgeInsets.only(
                                                    top: 8),
                                                width: 6,
                                                height: 6,
                                                decoration: const BoxDecoration(
                                                  color: Colors.black,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  idea.idea,
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                idea.date,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  color: Color(0xFF9D9D9D),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                          ),
                        ],
                      ),
                    ),
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
                                  : 'Analyzing for todos and ideas...',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Fixed recording button at the bottom of the screen
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Container(
                alignment: Alignment.center,
                child: !_isRecording
                    ? FloatingActionButton.extended(
                        onPressed: _startRecording,
                        icon: const Icon(Icons.mic),
                        label: const Text('Record'),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FloatingActionButton(
                            onPressed: _pauseRecording,
                            tooltip: _isPaused ? 'Resume' : 'Pause',
                            backgroundColor: Colors.orange,
                            child: Icon(
                                _isPaused ? Icons.play_arrow : Icons.pause),
                          ),
                          const SizedBox(width: 16),
                          FloatingActionButton(
                            onPressed: _stopRecording,
                            tooltip: 'Stop',
                            backgroundColor: Colors.red,
                            child: const Icon(Icons.stop),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TodoItem {
  String task;
  String dueDate;
  bool completed;

  TodoItem({
    required this.task,
    required this.dueDate,
    this.completed = false,
  });
}

class IdeaItem {
  String idea;
  String date;

  IdeaItem({
    required this.idea,
    required this.date,
  });
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
