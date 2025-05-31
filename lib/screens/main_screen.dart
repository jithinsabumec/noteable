import 'package:flutter/material.dart';
import 'dart:async';
import 'package:noteable/services/storage_service.dart';
import 'package:noteable/models/timeline_entry.dart' as models;
import '../services/deepseek_service.dart';
import '../services/assembly_ai_service.dart';
import '../models/timeline_models.dart';
import '../widgets/timeline/weekday_selector.dart';

import '../widgets/rive_checkbox.dart';
import '../utils/date_formatter.dart';
import '../widgets/rive_animation_widget.dart';
import '../widgets/bottom_sheets/add_item_bottom_sheet.dart';
import '../widgets/timeline/timeline_renderer.dart';
import 'recording_screen.dart';
import '../services/item_management_service.dart';
import '../widgets/dialogs/item_options_dialog.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  DateTime _selectedDate = DateTime.now();

  // Add a PageController for horizontal sliding between weeks
  late PageController _pageController;
  final int _initialPage =
      1000; // Start at a high number to allow going back in time

  // Use the new storage service
  final _storageService = StorageService();
  // Use the new item management service
  final _itemManagementService = ItemManagementService();
  // Map to store entries by timestamp for the currently selected date
  final Map<String, List<TimelineEntry>> _timelineEntriesByDate = {};

  // Recording and animation state
  final _deepseekService = DeepseekService();
  final _assemblyAIService = AssemblyAIService();
  String _transcribedText = '';
  bool _isTranscribing = false;
  bool _isUnderstanding = false;
  bool _isAnalyzing = false;

  // Timer for animation sequence
  Timer? _animationSequenceTimer;

  // Controller for the animation sequence (for future use)
  // final _animationController = GlobalKey();

  // Flag to track if animations are visible or not
  bool _showAnimations = false;

  // Map to store RiveCheckboxControllers for each task item
  final Map<String, RiveCheckboxController> _taskCheckboxControllers = {};

  @override
  void initState() {
    super.initState();
    // Initialize the PageController
    _pageController = PageController(
      initialPage: _initialPage,
      viewportFraction: 1.0,
    );

    // Initialize the current selected page
    // _currentSelectedPage = _initialPage; // Commented out as it's not currently used

    // Load entries for the current date
    _loadEntriesForSelectedDate();
  }

  @override
  void dispose() {
    // Cancel any pending page animations
    if (_pageController.hasClients) {
      _pageController.dispose();
    }

    // Dispose recording and animation resources
    _animationSequenceTimer?.cancel();

    super.dispose();
  }

  // Load entries for the selected date
  Future<void> _loadEntriesForSelectedDate() async {
    final List<models.TimelineEntry> sEntries =
        _storageService.getEntriesForDate(_selectedDate);
    // Sort entries by timestamp to ensure consistent order if multiple items share the same UI timestamp string
    sEntries.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    setState(() {
      // Clear existing entries before repopulating
      _timelineEntriesByDate.clear();

      // Temporary map to build UI entries
      Map<String, TimelineEntry> tempUiEntries = {};

      for (final sEntry in sEntries) {
        final String uiTimestamp = sEntry.timeString; // e.g., "10:00 AM"
        final bool isDaytime =
            DateFormatter.isTimestamp24HourDaytime(sEntry.timestamp);

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

        if (sEntry.type == models.EntryType.note) {
          final newNoteIndex = uiEntry.notes.length;
          uiEntry.notes.add(sEntry.content);
          uiEntry.itemOrder.add(TimelineItemRef(
            type: ItemType.note,
            index: newNoteIndex,
            storageId: sEntry.id, // Store the original ID
          ));
        } else {
          // Task
          final newTaskIndex = uiEntry.tasks.length;
          uiEntry.tasks.add(TaskItem(
            task: sEntry.content,
            completed: sEntry.completed,
          ));
          uiEntry.itemOrder.add(TimelineItemRef(
            type: ItemType.task,
            index: newTaskIndex,
            storageId: sEntry.id, // Store the original ID
          ));
        }
      }

      // Convert the temporary map to the final structure and update the UI
      _timelineEntriesByDate
          .addAll(tempUiEntries.map((key, value) => MapEntry(key, [value])));
    });

    // Debug print to verify entries are loaded
    debugPrint('Loaded ${sEntries.length} entries for $_selectedDate');
  }

  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
    });
    _loadEntriesForSelectedDate().then((_) {
      debugPrint(
          "Entries loaded for ${DateFormatter.formatDate(_selectedDate)}");
    });
  }

  void _onPageChanged(int pageIndex) {
    if (!mounted) return;

    // Only update the page tracking - don't modify the selected date
    // setState(() {
    //   _currentSelectedPage = pageIndex;
    // }); // Commented out as _currentSelectedPage is not currently used

    // Keep these debug prints but don't use them to modify state
    final now = DateTime.now();
    final weekOffset = _initialPage - pageIndex;
    debugPrint("Week offset: $weekOffset weeks before current");

    final newStartOfWeek =
        now.subtract(Duration(days: now.weekday - 1 + (weekOffset * 7)));
    debugPrint("Week starting date: ${newStartOfWeek.toString()}");
  }

  // Add a new note directly
  void _addNote() {
    showAddItemBottomSheet(
      context: context,
      initialTab: 'Notes',
      onAddItem: _handleAddItem,
      onReloadEntries: _loadEntriesForSelectedDate,
    );
  }

  // Add a new task directly
  void _addTask() {
    showAddItemBottomSheet(
      context: context,
      initialTab: 'Tasks',
      onAddItem: _handleAddItem,
      onReloadEntries: _loadEntriesForSelectedDate,
    );
  }

  // Handle adding an item from the bottom sheet
  void _handleAddItem(String content, String type) {
    if (type == 'Notes') {
      _itemManagementService.createNoteEntry(
        noteText: content,
        selectedDate: _selectedDate,
        timelineEntriesByDate: _timelineEntriesByDate,
        onStateUpdate: () => setState(() {}),
      );
    } else {
      _itemManagementService.createTaskEntry(
        taskText: content,
        selectedDate: _selectedDate,
        timelineEntriesByDate: _timelineEntriesByDate,
        onStateUpdate: () => setState(() {}),
      );
    }
  }

  // Wrapper for _updateItem to match TimelineRenderer signature
  void _updateItemWrapper(String timestamp, int orderIndex, ItemType itemType,
      String content, bool completed, String storageId) {
    _itemManagementService.updateItem(
      timestamp: timestamp,
      orderIndexInItemOrder: orderIndex,
      newItemType: itemType,
      newContent: content,
      newCompleted: completed,
      originalItemType: itemType,
      storageId: storageId,
      selectedDate: _selectedDate,
      timelineEntriesByDate: _timelineEntriesByDate,
      onStateUpdate: () => setState(() {}),
    );
  }

  // Wrapper for _showItemOptions to match TimelineRenderer signature
  void _showItemOptionsWrapper(String timestamp, int contentListIndex,
      int orderIndex, ItemType itemType, String content, String storageId,
      {bool? completed}) {
    showItemOptionsDialog(
      context: context,
      timestamp: timestamp,
      contentListIndex: contentListIndex,
      orderIndex: orderIndex,
      itemType: itemType,
      content: content,
      storageId: storageId,
      completed: completed,
      itemManagementService: _itemManagementService,
      selectedDate: _selectedDate,
      timelineEntriesByDate: _timelineEntriesByDate,
      onStateUpdate: () => setState(() {}),
    );
  }

  // Start recording audio
  void _startRecording() async {
    // Prepare for seamless transition by setting up states
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
            const RecordingScreen(),
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
      setState(() {
        _isTranscribing = true;
        _isUnderstanding = false;
        _isAnalyzing = false;
        _showAnimations = true; // Show animations immediately
      });

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

    // Start a sequence of timers for the animations
    _animationSequenceTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) {
        _animationSequenceTimer?.cancel();
        return;
      }

      setState(() {
        _isTranscribing = false;
        _isUnderstanding = true;
        _isAnalyzing = false;
      });

      _animationSequenceTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted) {
          _animationSequenceTimer?.cancel();
          return;
        }

        setState(() {
          _isTranscribing = false;
          _isUnderstanding = false;
          _isAnalyzing = true;
        });

        _performActualTextProcessing(
            _transcribedText.isNotEmpty ? _transcribedText : text);
      });
    });
  }

  // Transcribe audio using AssemblyAI
  Future<void> _transcribeAudio(String filePath) async {
    try {
      _transcribedText = await _assemblyAIService.transcribeAudio(filePath);
      debugPrint('Transcribed text: $_transcribedText');
    } catch (e) {
      debugPrint('Transcription error: $e');
      _transcribedText = 'Error transcribing audio: $e';
    }
  }

  // Perform the actual text processing after animations
  Future<void> _performActualTextProcessing(String text) async {
    try {
      debugPrint('Starting text processing with: $text');

      if (text.isEmpty || text.contains('Error transcribing audio')) {
        debugPrint('Skipping processing due to empty or error text');
        setState(() {
          _showAnimations = false;
          _isTranscribing = false;
          _isUnderstanding = false;
          _isAnalyzing = false;
        });
        return;
      }

      final result = await _deepseekService.analyzeTranscription(text);
      debugPrint('Deepseek analysis result: $result');

      // Extract notes and tasks from the LLM result
      List<String> notes = [];
      List<TaskItem> tasks = [];

      if (result['notes'] != null && result['notes'].isNotEmpty) {
        notes = List<String>.from(result['notes']);
        debugPrint('Extracted ${notes.length} notes: $notes');
      }

      if (result['tasks'] != null && result['tasks'].isNotEmpty) {
        final taskStrings = List<String>.from(result['tasks']);
        tasks = taskStrings
            .map((taskText) => TaskItem(
                  task: taskText,
                  completed: false,
                ))
            .toList();
        debugPrint(
            'Extracted ${tasks.length} tasks: ${tasks.map((t) => t.task).toList()}');
      }

      // Use the item management service to create items from processed audio
      _itemManagementService.createItemsFromProcessedAudio(
        notes: notes,
        tasks: tasks,
        selectedDate: _selectedDate,
        timelineEntriesByDate: _timelineEntriesByDate,
        onStateUpdate: () => setState(() {}),
      );

      debugPrint(
          'Successfully created ${notes.length} notes and ${tasks.length} tasks');

      // Hide animations after processing
      setState(() {
        _showAnimations = false;
        _isTranscribing = false;
        _isUnderstanding = false;
        _isAnalyzing = false;
      });
    } catch (e) {
      debugPrint('Processing error: $e');

      // Create a note with the transcribed text as fallback
      if (text.isNotEmpty && !text.contains('Error transcribing audio')) {
        debugPrint('Creating fallback note with transcribed text');
        _itemManagementService.createNoteEntry(
          noteText: 'Transcribed: $text',
          selectedDate: _selectedDate,
          timelineEntriesByDate: _timelineEntriesByDate,
          onStateUpdate: () => setState(() {}),
        );
      }

      setState(() {
        _showAnimations = false;
        _isTranscribing = false;
        _isUnderstanding = false;
        _isAnalyzing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isLoading = _showAnimations;

    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: SizedBox(
        width: 600,
        height: 250,
        child: const RiveAnimationWidget(),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Stack(
        children: [
          // Main content
          SafeArea(
            top: false,
            child: LayoutBuilder(
              builder:
                  (BuildContext context, BoxConstraints viewportConstraints) {
                return SingleChildScrollView(
                  clipBehavior: Clip.none,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        minHeight: viewportConstraints.maxHeight),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 24.0, bottom: 24.0),
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
                              DateFormatter.formatDate(_selectedDate)
                                  .toLowerCase(),
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
                          WeekdaySelector(
                            selectedDate: _selectedDate,
                            pageController: _pageController,
                            initialPage: _initialPage,
                            onDateSelected: _onDateSelected,
                            onPageChanged: _onPageChanged,
                          ),

                          // Timeline entries with horizontal padding
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 24.0,
                              right: 24.0,
                              top: 16.0,
                            ),
                            child: TimelineRenderer(
                              timelineEntriesByDate: _timelineEntriesByDate,
                              selectedDate: _selectedDate,
                              taskCheckboxControllers: _taskCheckboxControllers,
                              onUpdateItem: _updateItemWrapper,
                              onShowItemOptions: _showItemOptionsWrapper,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Animation overlay
          if (isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.white,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isTranscribing)
                        const Text(
                          'Transcribing...',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else if (_isUnderstanding)
                        const Text(
                          'Understanding...',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else if (_isAnalyzing)
                        const Text(
                          'Analyzing...',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const SizedBox(height: 20),
                      const CircularProgressIndicator(),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
