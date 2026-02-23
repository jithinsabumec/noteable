import 'package:noteable/services/storage_service.dart';
import 'package:noteable/models/timeline_entry.dart' as models;
import '../models/timeline_models.dart';
import 'package:flutter/foundation.dart';
import '../utils/date_formatter.dart';

class ItemManagementService {
  final StorageService _storageService = StorageService();

  DateTime _timestampForSelectedDate(DateTime selectedDate) {
    final now = DateTime.now();
    return DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      now.hour,
      now.minute,
      now.second,
      now.millisecond,
      now.microsecond,
    );
  }

  String _toUiTimestamp(DateTime timestamp) {
    final hour = timestamp.hour > 12
        ? timestamp.hour - 12
        : timestamp.hour == 0
            ? 12
            : timestamp.hour;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final ampm = timestamp.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }

  DateTime? _parseScheduledDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return DateFormatter.startOfDay(value);

    final asString = value.toString().trim();
    if (asString.isEmpty) return null;

    final parsed = DateTime.tryParse(asString);
    if (parsed == null) {
      debugPrint('⚠️ Invalid scheduledDate from AI: $value');
      return null;
    }
    return DateFormatter.startOfDay(parsed);
  }

  String? _normalizeScheduledTime(dynamic value) {
    final normalized = DateFormatter.normalizeScheduledTime(value);
    if (value != null &&
        value.toString().trim().isNotEmpty &&
        normalized == null) {
      debugPrint('⚠️ Invalid scheduledTime from AI: $value');
    }
    return normalized;
  }

  // Update an item (note or task) in both storage and UI
  Future<void> updateItem({
    required String timestamp,
    required int orderIndexInItemOrder,
    required ItemType newItemType,
    required String newContent,
    required bool newCompleted,
    required ItemType originalItemType,
    required String storageId,
    DateTime? newScheduledDate,
    String? newScheduledTime,
    bool applyScheduleUpdates = false,
    required DateTime selectedDate,
    required Map<String, List<TimelineEntry>> timelineEntriesByDate,
    required Function() onStateUpdate,
  }) async {
    final existingEntry = await _storageService.getEntryById(storageId);

    final scheduledDateForTask = applyScheduleUpdates
        ? (newScheduledDate == null
            ? null
            : DateFormatter.startOfDay(newScheduledDate))
        : existingEntry?.scheduledDate;
    final scheduledTimeForTask = applyScheduleUpdates
        ? _normalizeScheduledTime(newScheduledTime)
        : existingEntry?.scheduledTime;

    final updatedEntry = models.TimelineEntry(
      id: storageId,
      content: newContent,
      timestamp: existingEntry?.timestamp ?? DateTime.now(),
      type: newItemType == ItemType.note
          ? models.EntryType.note
          : models.EntryType.task,
      completed: newCompleted,
      scheduledDate: newItemType == ItemType.task ? scheduledDateForTask : null,
      scheduledTime: newItemType == ItemType.task ? scheduledTimeForTask : null,
    );
    await _storageService.updateEntry(updatedEntry);

    // Update in UI
    final uiEntry = timelineEntriesByDate[timestamp]?.first;
    if (uiEntry != null && orderIndexInItemOrder < uiEntry.itemOrder.length) {
      final itemRef = uiEntry.itemOrder[orderIndexInItemOrder];

      if (itemRef.type == ItemType.task &&
          itemRef.index < uiEntry.tasks.length) {
        // Update the task
        uiEntry.tasks[itemRef.index] = TaskItem(
          task: newContent,
          completed: newCompleted,
          scheduledDate: scheduledDateForTask,
          scheduledTime: scheduledTimeForTask,
        );
      } else if (itemRef.type == ItemType.note &&
          itemRef.index < uiEntry.notes.length) {
        // Update the note
        uiEntry.notes[itemRef.index] = newContent;
      }
    }

    onStateUpdate();
  }

  // Create a new note entry with the current timestamp
  Future<void> createNoteEntry({
    required String noteText,
    required DateTime selectedDate,
    required Map<String, List<TimelineEntry>> timelineEntriesByDate,
    required Function() onStateUpdate,
  }) async {
    debugPrint('📝 ItemManagementService: Creating note entry...');
    debugPrint('   Note text: "$noteText"');
    debugPrint('   Selected date: $selectedDate');

    final entryTimestamp = _timestampForSelectedDate(selectedDate);
    final timestamp = _toUiTimestamp(entryTimestamp);
    final isDaytime = DateFormatter.isTimestamp24HourDaytime(entryTimestamp);

    debugPrint('   Timestamp: $timestamp');

    // Create a new timeline entry for storage
    final storageEntry = models.TimelineEntry(
      id: _storageService.generateId(),
      content: noteText,
      timestamp: entryTimestamp,
      type: models.EntryType.note,
      completed: false,
    );

    debugPrint('   Storage entry ID: ${storageEntry.id}');

    try {
      // Save to storage
      await _storageService.saveEntry(storageEntry);
      debugPrint('✅ Successfully saved note to storage');
    } catch (e) {
      debugPrint('❌ Failed to save note to storage: $e');
      rethrow;
    }

    // Update UI
    final existingUiEntry = timelineEntriesByDate[timestamp]?.first;

    if (existingUiEntry != null) {
      debugPrint('   Adding to existing UI entry for timestamp: $timestamp');
      // Add to existing entry for this timestamp
      final newNoteIndex = existingUiEntry.notes.length;
      existingUiEntry.notes.add(noteText);
      existingUiEntry.itemOrder.add(TimelineItemRef(
          type: ItemType.note,
          index: newNoteIndex,
          storageId: storageEntry.id));
      debugPrint('   Added at note index: $newNoteIndex');
    } else {
      debugPrint('   Creating new UI entry for timestamp: $timestamp');
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
      timelineEntriesByDate[timestamp] = [newUiEntry];
      debugPrint('   Created new UI entry with note at index: $newNoteIndex');
    }

    debugPrint(
        '   Current timeline entries: ${timelineEntriesByDate.keys.toList()}');

    try {
      onStateUpdate();
      debugPrint('✅ Successfully called onStateUpdate()');
    } catch (e) {
      debugPrint('❌ Error in onStateUpdate(): $e');
    }

    debugPrint('✅ Note entry creation completed');
  }

  // Create a new task entry with the current timestamp
  Future<void> createTaskEntry({
    required String taskText,
    required DateTime selectedDate,
    required Map<String, List<TimelineEntry>> timelineEntriesByDate,
    required Function() onStateUpdate,
    DateTime? scheduledDate,
    String? scheduledTime,
  }) async {
    debugPrint('✅ ItemManagementService: Creating task entry...');
    debugPrint('   Task text: "$taskText"');
    debugPrint('   Selected date: $selectedDate');

    final entryTimestamp = _timestampForSelectedDate(selectedDate);
    final timestamp = _toUiTimestamp(entryTimestamp);
    final isDaytime = DateFormatter.isTimestamp24HourDaytime(entryTimestamp);

    debugPrint('   Timestamp: $timestamp');

    // Create a new timeline entry for storage
    final storageEntry = models.TimelineEntry(
      id: _storageService.generateId(),
      content: taskText,
      timestamp: entryTimestamp,
      type: models.EntryType.task,
      completed: false,
      scheduledDate: scheduledDate == null
          ? null
          : DateFormatter.startOfDay(scheduledDate),
      scheduledTime: _normalizeScheduledTime(scheduledTime),
    );

    debugPrint('   Storage entry ID: ${storageEntry.id}');

    try {
      // Save to storage
      await _storageService.saveEntry(storageEntry);
      debugPrint('✅ Successfully saved task to storage');
    } catch (e) {
      debugPrint('❌ Failed to save task to storage: $e');
      rethrow;
    }

    // Update UI
    final existingUiEntry = timelineEntriesByDate[timestamp]?.first;

    if (existingUiEntry != null) {
      debugPrint('   Adding to existing UI entry for timestamp: $timestamp');
      // Add to existing entry for this timestamp
      final newTaskIndex = existingUiEntry.tasks.length;
      existingUiEntry.tasks.add(TaskItem(
        task: taskText,
        completed: false,
        scheduledDate: storageEntry.scheduledDate,
        scheduledTime: storageEntry.scheduledTime,
      ));
      existingUiEntry.itemOrder.add(TimelineItemRef(
          type: ItemType.task,
          index: newTaskIndex,
          storageId: storageEntry.id));
      debugPrint('   Added at task index: $newTaskIndex');
    } else {
      debugPrint('   Creating new UI entry for timestamp: $timestamp');
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
            scheduledDate: storageEntry.scheduledDate,
            scheduledTime: storageEntry.scheduledTime,
          )
        ],
        itemOrder: [
          TimelineItemRef(
              type: ItemType.task,
              index: newTaskIndex,
              storageId: storageEntry.id)
        ],
      );
      timelineEntriesByDate[timestamp] = [newUiEntry];
      debugPrint('   Created new UI entry with task at index: $newTaskIndex');
    }

    debugPrint(
        '   Current timeline entries: ${timelineEntriesByDate.keys.toList()}');

    try {
      onStateUpdate();
      debugPrint('✅ Successfully called onStateUpdate()');
    } catch (e) {
      debugPrint('❌ Error in onStateUpdate(): $e');
    }

    debugPrint('✅ Task entry creation completed');
  }

  // Delete a note or task
  Future<void> deleteItem({
    required String timestamp,
    required int orderIndexInItemOrder,
    required ItemType itemType,
    required String storageId,
    required Map<String, List<TimelineEntry>> timelineEntriesByDate,
    required Function() onStateUpdate,
  }) async {
    // Delete from persistent storage first
    await _storageService.deleteEntry(storageId);

    final uiEntry = timelineEntriesByDate[timestamp]?.first;
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
      timelineEntriesByDate.remove(timestamp);
    }

    onStateUpdate();
  }

  // Create multiple items from processed audio (notes and tasks)
  Future<void> createItemsFromProcessedAudio({
    required List<String> notes,
    required List<Map<String, dynamic>> tasks,
    required DateTime selectedDate,
    required Map<String, List<TimelineEntry>> timelineEntriesByDate,
    required Function() onStateUpdate,
  }) async {
    final now = DateTime.now();
    final today = DateFormatter.startOfDay(now);

    // Format timestamp for UI display
    final timestamp = _toUiTimestamp(now);
    final isDaytime = now.hour >= 6 && now.hour < 18;

    // Save each note and task to storage
    final savedNoteEntries = <models.TimelineEntry>[];
    for (final note in notes) {
      final storageEntry = models.TimelineEntry(
        id: _storageService.generateId(),
        content: note,
        timestamp: now,
        type: models.EntryType.note,
        completed: false,
      );
      savedNoteEntries.add(storageEntry);
    }

    final savedTaskEntries = <models.TimelineEntry>[];
    final uiTasks = <TaskItem>[];
    for (final taskData in tasks) {
      final taskText = (taskData['text'] ?? '').toString().trim();
      if (taskText.isEmpty) {
        continue;
      }

      final scheduledDate = _parseScheduledDate(taskData['scheduledDate']);
      final scheduledTime = _normalizeScheduledTime(taskData['scheduledTime']);

      final storageEntry = models.TimelineEntry(
        id: _storageService.generateId(),
        content: taskText,
        timestamp: now,
        type: models.EntryType.task,
        completed: false,
        scheduledDate: scheduledDate,
        scheduledTime: scheduledTime,
      );
      savedTaskEntries.add(storageEntry);

      uiTasks.add(TaskItem(
        task: taskText,
        completed: false,
        scheduledDate: scheduledDate,
        scheduledTime: scheduledTime,
      ));
    }

    for (final entry in savedNoteEntries) {
      await _storageService.saveEntry(entry);
    }
    for (final entry in savedTaskEntries) {
      await _storageService.saveEntry(entry);
    }

    // Update UI if we're viewing today
    if (DateFormatter.isSameDay(selectedDate, today)) {
      final existingUiEntry = timelineEntriesByDate[timestamp]?.first;

      if (existingUiEntry != null) {
        // Add to existing entry for this timestamp
        for (int i = 0; i < notes.length; i++) {
          final note = notes[i];
          final newNoteIndex = existingUiEntry.notes.length;
          existingUiEntry.notes.add(note);
          existingUiEntry.itemOrder.add(TimelineItemRef(
            type: ItemType.note,
            index: newNoteIndex,
            storageId: savedNoteEntries[i].id,
          ));
        }

        for (int i = 0; i < uiTasks.length; i++) {
          final task = uiTasks[i];
          final newTaskIndex = existingUiEntry.tasks.length;
          existingUiEntry.tasks.add(task);
          existingUiEntry.itemOrder.add(TimelineItemRef(
            type: ItemType.task,
            index: newTaskIndex,
            storageId: savedTaskEntries[i].id,
          ));
        }
      } else {
        // Create new entry for this timestamp
        List<TimelineItemRef> itemOrder = [];

        for (int i = 0; i < notes.length; i++) {
          itemOrder.add(TimelineItemRef(
            type: ItemType.note,
            index: i,
            storageId: savedNoteEntries[i].id,
          ));
        }

        for (int i = 0; i < uiTasks.length; i++) {
          itemOrder.add(TimelineItemRef(
            type: ItemType.task,
            index: i,
            storageId: savedTaskEntries[i].id,
          ));
        }

        final newUiEntry = TimelineEntry(
          timestamp: timestamp,
          isDaytime: isDaytime,
          notes: notes,
          tasks: uiTasks,
          itemOrder: itemOrder,
        );
        timelineEntriesByDate[timestamp] = [newUiEntry];
      }

      onStateUpdate();
    }
  }
}
