import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'config.dart';
import 'services/deepseek_service.dart';

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
    final micStatus = await Permission.microphone.request();
    final storageStatus = await Permission.storage.request();

    if (micStatus.isDenied || storageStatus.isDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone and storage permissions are required'),
          duration: Duration(seconds: 2),
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _startRecording() async {
    try {
      if (await _checkPermissions()) {
        final directory = await getTemporaryDirectory();
        _recordedFilePath =
            '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

        print('Recording file path: $_recordedFilePath');

        if (await _audioRecorder.hasPermission()) {
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
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No permission to record audio'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('Error starting recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error starting recording: $e'),
          duration: const Duration(seconds: 2),
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
      backgroundColor: const Color(0xFFF5F5F7),
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
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 12.0),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF5F5F7),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(12),
                                topRight: Radius.circular(12),
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
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Content - Todo list
                          Container(
                            color: Colors.white,
                            child: _todos.isEmpty
                                ? const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: Text(
                                          'No to-dos yet. Record your first to-do!'),
                                    ),
                                  )
                                : Column(
                                    children: _todos.map((todo) {
                                      return Container(
                                        decoration: BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(
                                              color:
                                                  Colors.grey.withOpacity(0.2),
                                              width: 0.5,
                                            ),
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16.0, vertical: 8.0),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 24,
                                                height: 24,
                                                child: Checkbox(
                                                  value: todo.completed,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4.0),
                                                  ),
                                                  side: const BorderSide(
                                                      width: 1.5,
                                                      color: Colors.black),
                                                  onChanged: (value) {
                                                    setState(() {
                                                      todo.completed =
                                                          value ?? false;
                                                    });
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  todo.task,
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight:
                                                        FontWeight.normal,
                                                    decoration: todo.completed
                                                        ? TextDecoration
                                                            .lineThrough
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
                                                      : Colors.grey[400],
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
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 12.0),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF5F5F7),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(12),
                                topRight: Radius.circular(12),
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
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Content - Ideas list
                          Container(
                            color: Colors.white,
                            child: _ideas.isEmpty
                                ? const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: Text(
                                          'No ideas yet. Record your first idea!'),
                                    ),
                                  )
                                : Column(
                                    children: _ideas.map((idea) {
                                      return Container(
                                        decoration: BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(
                                              color:
                                                  Colors.grey.withOpacity(0.2),
                                              width: 0.5,
                                            ),
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16.0, vertical: 16.0),
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
                                                    fontSize: 16,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                idea.date,
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  color: Colors.grey[400],
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
