import 'package:flutter/material.dart';
import 'dart:async';
import 'package:noteable/services/storage_service.dart';
import 'package:noteable/models/timeline_entry.dart' as models;
import 'package:noteable/services/auth_service.dart';
import 'package:noteable/services/guest_mode_service.dart';
import '../services/ai_analysis_service.dart';
import '../services/assembly_ai_service.dart';
import '../models/timeline_models.dart';
import '../widgets/timeline/weekday_selector.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../utils/date_formatter.dart';
import '../widgets/rive_animation_widget.dart';
import '../widgets/bottom_sheets/add_item_bottom_sheet.dart';
import '../widgets/timeline/timeline_renderer.dart';
import '../widgets/guest_recording_counter.dart';
import 'subscription_screen.dart';
import 'tasks_screen.dart';
import '../services/item_management_service.dart';
import '../services/purchase_service.dart';
import '../widgets/dialogs/item_options_dialog.dart';
import '../widgets/dialogs/edit_item_dialog.dart';

class MainScreen extends StatefulWidget {
  final bool isGuestMode;
  final VoidCallback onExitGuestMode;

  const MainScreen({
    super.key,
    required this.isGuestMode,
    required this.onExitGuestMode,
  });

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
  // Guest mode service
  final _guestModeService = GuestModeService();
  // Purchase service
  final _purchaseService = PurchaseService();

  // Map to store entries by timestamp for the currently selected date
  final Map<String, List<TimelineEntry>> _timelineEntriesByDate = {};

  // Recording and animation state
  final _aiAnalysisService = AIAnalysisService();
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

  // Guest mode recording count state
  int _guestRecordingCount = 0;

  // Add AuthService instance
  final _authService = AuthService();

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

    // Load guest recording count if in guest mode
    if (widget.isGuestMode) {
      _loadGuestRecordingCount();
    }
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
        await _storageService.getEntriesForDate(_selectedDate);
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
            scheduledDate: sEntry.scheduledDate,
            scheduledTime: sEntry.scheduledTime,
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

  // Load guest mode recording count
  Future<void> _loadGuestRecordingCount() async {
    if (!widget.isGuestMode) return;

    final count = await _guestModeService.getRecordingCount();
    if (mounted) {
      setState(() {
        _guestRecordingCount = count;
      });
    }
  }

  // Sign out the user
  Future<void> _signOut() async {
    try {
      await _authService.signOut();
      // Reset guest mode if applicable
      widget.onExitGuestMode();
      // The AuthWrapper will automatically handle the UI transition back to login screen
    } catch (e) {
      // Show error dialog if signout fails
      if (mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Sign Out Error'),
              content: Text('Failed to sign out: ${e.toString()}'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      }
    }
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
  Future<void> _handleAddItem(String content, String type) async {
    if (type == 'Notes') {
      await _itemManagementService.createNoteEntry(
        noteText: content,
        selectedDate: _selectedDate,
        timelineEntriesByDate: _timelineEntriesByDate,
        onStateUpdate: () => setState(() {}),
      );
    } else {
      await _itemManagementService.createTaskEntry(
        taskText: content,
        selectedDate: _selectedDate,
        timelineEntriesByDate: _timelineEntriesByDate,
        onStateUpdate: () => setState(() {}),
      );
    }
  }

  // Wrapper for _updateItem to match TimelineRenderer signature
  Future<void> _updateItemWrapper(
      String timestamp,
      int orderIndex,
      ItemType itemType,
      String content,
      bool completed,
      String storageId) async {
    await _itemManagementService.updateItem(
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
      {bool? completed, DateTime? scheduledDate, String? scheduledTime}) {
    showItemOptionsDialog(
      context: context,
      timestamp: timestamp,
      contentListIndex: contentListIndex,
      orderIndex: orderIndex,
      itemType: itemType,
      content: content,
      storageId: storageId,
      completed: completed,
      scheduledDate: scheduledDate,
      scheduledTime: scheduledTime,
      itemManagementService: _itemManagementService,
      selectedDate: _selectedDate,
      timelineEntriesByDate: _timelineEntriesByDate,
      onStateUpdate: () => setState(() {}),
    );
  }

  void _showEditItemDialogWrapper(String timestamp, int contentListIndex,
      int orderIndex, ItemType itemType, String content, String storageId,
      {bool? completed, DateTime? scheduledDate, String? scheduledTime}) {
    showEditItemDialog(
      context: context,
      timestamp: timestamp,
      contentListIndex: contentListIndex,
      orderIndex: orderIndex,
      itemType: itemType,
      content: content,
      storageId: storageId,
      completed: completed,
      scheduledDate: scheduledDate,
      scheduledTime: scheduledTime,
      itemManagementService: _itemManagementService,
      selectedDate: _selectedDate,
      timelineEntriesByDate: _timelineEntriesByDate,
      onStateUpdate: () => setState(() {}),
    );
  }

  // Start recording audio
  void _startRecording() async {
    debugPrint(
        '🎙️ Legacy recording screen removed; using Rive bottom bar flow');
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

    // Reset transcribed text at the beginning of each sequence
    _transcribedText = '';

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
      final transcribedText =
          await _assemblyAIService.transcribeAudio(filePath);
      debugPrint('Transcribed text: $transcribedText');

      // Store the transcribed text in the class variable
      if (mounted) {
        setState(() {
          _transcribedText = transcribedText;
        });
      }
    } catch (e) {
      debugPrint('Transcription error: $e');
      if (mounted) {
        setState(() {
          _transcribedText = 'Error transcribing audio: $e';
        });
      }
    }
  }

  // Perform the actual text processing after animations
  Future<void> _performActualTextProcessing(String text) async {
    try {
      debugPrint(
          'Starting text processing with initial text length: ${text.length}');

      // ------------------------------------------------------------------
      // 1. Ensure we have transcription text. If `text` is empty, wait for
      //    `_transcribedText` to be populated by the transcription future.
      // ------------------------------------------------------------------

      String textToProcess = text.trim();

      if (textToProcess.isEmpty) {
        // Wait (up to 30 s) for transcription to finish.
        const int maxWaitSeconds = 30;
        int waited = 0;
        while (waited < maxWaitSeconds && _transcribedText.trim().isEmpty) {
          await Future.delayed(const Duration(seconds: 1));
          waited++;
        }

        // Use whatever we have now.
        textToProcess = _transcribedText.trim();
      }

      // If still empty or contains an error string, abort gracefully.
      if (textToProcess.isEmpty ||
          textToProcess.contains('Error transcribing audio')) {
        debugPrint('Skipping processing due to empty or error text');
        setState(() {
          _showAnimations = false;
          _isTranscribing = false;
          _isUnderstanding = false;
          _isAnalyzing = false;
        });

        // Show error message to user if applicable
        if (mounted && textToProcess.contains('Error transcribing audio')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to process audio. Please try again.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // At this point we have valid transcription text.

      final String finalText = textToProcess;

      final result = await _aiAnalysisService.analyzeTranscription(
        finalText,
        today: DateTime.now(),
      );
      debugPrint('AI Analysis result: $result');

      // Extract notes and tasks from the LLM result
      List<String> notes = [];
      List<Map<String, dynamic>> tasks = [];

      if (result['notes'] != null && result['notes'].isNotEmpty) {
        notes = List<String>.from(result['notes']);
        debugPrint('Extracted ${notes.length} notes: $notes');
      }

      if (result['tasks'] != null && result['tasks'].isNotEmpty) {
        tasks = List<Map<String, dynamic>>.from(
          (result['tasks'] as List).map((task) {
            if (task is Map) {
              return {
                'text': (task['text'] ?? task['task'] ?? '').toString(),
                'scheduledDate': task['scheduledDate'],
                'scheduledTime': task['scheduledTime'],
              };
            }
            return {
              'text': task.toString(),
              'scheduledDate': null,
              'scheduledTime': null,
            };
          }),
        );
        debugPrint(
            'Extracted ${tasks.length} tasks: ${tasks.map((t) => t['text']).toList()}');
      }

      // Use the item management service to create items from processed audio
      await _itemManagementService.createItemsFromProcessedAudio(
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
        await _itemManagementService.createNoteEntry(
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

      // Show error message to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing audio: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isLoading = _showAnimations;

    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 40.0), // Move up by 40 pixels
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Guest recording counter above the Rive animation
            if (widget.isGuestMode && !_purchaseService.isPremium) ...[
              GuestRecordingCounter(
                recordingsUsed: _guestRecordingCount,
                maxRecordings: _guestModeService.maxRecordings,
              ),
              const SizedBox(height: 12),
            ],

            // Bottom bar Rive animation
            Container(
              width: 341, // Slightly wider touch/crop area (+6px)
              height: 70,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(35.0),
              ),
              child: ClipRect(
                child: OverflowBox(
                  minWidth: 606, // Slightly larger interaction area (+6px)
                  maxWidth: 606,
                  minHeight: 250, // Keep original Rive animation height
                  maxHeight: 250,
                  child: Container(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16.0),
                      child: RiveAnimationWidget(
                        timelineEntriesByDate: _timelineEntriesByDate,
                        selectedDate: _selectedDate,
                        onStateUpdate: () => setState(() {}),
                        isGuestMode: widget.isGuestMode,
                        guestModeService: _guestModeService,
                        onGuestRecordingCountUpdate: _loadGuestRecordingCount,
                        onShowPaywall: widget.isGuestMode
                            ? () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const SubscriptionScreen(),
                                  ),
                                ).then((_) => setState(() {}));
                              }
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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
                      padding: const EdgeInsets.only(top: 36.0, bottom: 24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Day indicator with upgrade button for guest mode
                          Padding(
                            padding: const EdgeInsets.only(
                                top: 16.0,
                                left: 24.0,
                                right: 24.0,
                                bottom: 16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Day text
                                Text(
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

                                // Buttons row - upgrade (guest mode) and signout
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Upgrade button for guest mode only
                                    if (widget.isGuestMode &&
                                        !_purchaseService.isPremium) ...[
                                      GestureDetector(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const SubscriptionScreen(),
                                            ),
                                          );
                                        },
                                        child: Container(
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              width: 1,
                                              color: const Color(0xFF4772FF),
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 5),
                                            decoration: ShapeDecoration(
                                              gradient: const LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  Color(0xFF5387FF),
                                                  Color(0xFF244CFF),
                                                ],
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.start,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                SvgPicture.asset(
                                                  'assets/icons/upgrade.svg',
                                                  width: 14,
                                                  height: 14,
                                                  colorFilter:
                                                      const ColorFilter.mode(
                                                    Colors.white,
                                                    BlendMode.srcIn,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                const Text(
                                                  'Upgrade',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 14,
                                                    fontFamily: 'Geist',
                                                    fontWeight: FontWeight.w600,
                                                    height: 1.50,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],

                                    GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                const TasksScreen(),
                                          ),
                                        ).then((_) =>
                                            _loadEntriesForSelectedDate());
                                      },
                                      child: Container(
                                        width: 31,
                                        height: 31,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 1, vertical: 2),
                                        clipBehavior: Clip.antiAlias,
                                        decoration: ShapeDecoration(
                                          color: const Color(0xFFE6EFFF),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            SvgPicture.asset(
                                              'assets/icons/tasks.svg',
                                              width: 13,
                                              height: 13,
                                              colorFilter:
                                                  const ColorFilter.mode(
                                                Color(0xFF001778),
                                                BlendMode.srcIn,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Signout button
                                    GestureDetector(
                                      onTap: () {
                                        // Show confirmation dialog
                                        showDialog(
                                          context: context,
                                          builder: (BuildContext context) {
                                            return AlertDialog(
                                              title: const Text('Sign Out'),
                                              content: const Text(
                                                  'Are you sure you want to sign out?'),
                                              actions: [
                                                TextButton(
                                                  onPressed: () {
                                                    Navigator.of(context).pop();
                                                  },
                                                  child: const Text('Cancel'),
                                                ),
                                                TextButton(
                                                  onPressed: () {
                                                    Navigator.of(context).pop();
                                                    _signOut();
                                                  },
                                                  child: const Text('Sign Out'),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                      },
                                      child: Container(
                                        width: 31,
                                        height: 31,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 1, vertical: 2),
                                        clipBehavior: Clip.antiAlias,
                                        decoration: ShapeDecoration(
                                          color: const Color(0xFFE6EFFF),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            SvgPicture.asset(
                                              'assets/icons/signout.svg',
                                              width: 11,
                                              height: 11,
                                              colorFilter:
                                                  const ColorFilter.mode(
                                                Color(0xFF001778),
                                                BlendMode.srcIn,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
                              onUpdateItem: _updateItemWrapper,
                              onShowItemOptions: _showItemOptionsWrapper,
                              onEditItem: _showEditItemDialogWrapper,
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
