import 'package:noteable/services/storage_service.dart';
import 'package:noteable/models/timeline_entry.dart' as models;
import '../models/timeline_models.dart';
import 'package:flutter/foundation.dart';

class ItemManagementService {
  final StorageService _storageService = StorageService();

  // Update an item (note or task) in both storage and UI
  void updateItem({
    required String timestamp,
    required int orderIndexInItemOrder,
    required ItemType newItemType,
    required String newContent,
    required bool newCompleted,
    required ItemType originalItemType,
    required String storageId,
    required DateTime selectedDate,
    required Map<String, List<TimelineEntry>> timelineEntriesByDate,
    required Function() onStateUpdate,
  }) {
    // Update in storage - find the entry by ID from current date entries
    final currentEntries = _storageService.getEntriesForDate(selectedDate);
    final storageEntry = currentEntries.firstWhere(
      (entry) => entry.id == storageId,
      orElse: () => models.TimelineEntry(
        id: storageId,
        content: newContent,
        timestamp: DateTime.now(),
        type: newItemType == ItemType.note
            ? models.EntryType.note
            : models.EntryType.task,
        completed: newCompleted,
      ),
    );

    final updatedEntry = models.TimelineEntry(
      id: storageEntry.id,
      content: newContent,
      timestamp: storageEntry.timestamp,
      type: newItemType == ItemType.note
          ? models.EntryType.note
          : models.EntryType.task,
      completed: newCompleted,
    );
    _storageService.updateEntry(updatedEntry);

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
  void createNoteEntry({
    required String noteText,
    required DateTime selectedDate,
    required Map<String, List<TimelineEntry>> timelineEntriesByDate,
    required Function() onStateUpdate,
  }) {
    debugPrint('📝 ItemManagementService: Creating note entry...');
    debugPrint('   Note text: "$noteText"');
    debugPrint('   Selected date: $selectedDate');

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

    debugPrint('   Timestamp: $timestamp');

    // Create a new timeline entry for storage
    final storageEntry = models.TimelineEntry(
      id: _storageService.generateId(),
      content: noteText,
      timestamp: now,
      type: models.EntryType.note,
      completed: false,
    );

    debugPrint('   Storage entry ID: ${storageEntry.id}');

    try {
      // Save to storage
      _storageService.saveEntry(storageEntry);
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
  void createTaskEntry({
    required String taskText,
    required DateTime selectedDate,
    required Map<String, List<TimelineEntry>> timelineEntriesByDate,
    required Function() onStateUpdate,
  }) {
    debugPrint('✅ ItemManagementService: Creating task entry...');
    debugPrint('   Task text: "$taskText"');
    debugPrint('   Selected date: $selectedDate');

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

    debugPrint('   Timestamp: $timestamp');

    // Create a new timeline entry for storage
    final storageEntry = models.TimelineEntry(
      id: _storageService.generateId(),
      content: taskText,
      timestamp: now,
      type: models.EntryType.task,
      completed: false,
    );

    debugPrint('   Storage entry ID: ${storageEntry.id}');

    try {
      // Save to storage
      _storageService.saveEntry(storageEntry);
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
  void deleteItem({
    required String timestamp,
    required int orderIndexInItemOrder,
    required ItemType itemType,
    required String storageId,
    required Map<String, List<TimelineEntry>> timelineEntriesByDate,
    required Function() onStateUpdate,
  }) {
    // Delete from persistent storage first
    _storageService.deleteEntry(storageId);

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
  void createItemsFromProcessedAudio({
    required List<String> notes,
    required List<TaskItem> tasks,
    required DateTime selectedDate,
    required Map<String, List<TimelineEntry>> timelineEntriesByDate,
    required Function() onStateUpdate,
  }) {
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

    // Save each note and task to storage
    for (final note in notes) {
      final storageEntry = models.TimelineEntry(
        id: _storageService.generateId(),
        content: note,
        timestamp: now,
        type: models.EntryType.note,
        completed: false,
      );
      _storageService.saveEntry(storageEntry);
    }

    for (final task in tasks) {
      final storageEntry = models.TimelineEntry(
        id: _storageService.generateId(),
        content: task.task,
        timestamp: now,
        type: models.EntryType.task,
        completed: task.completed,
      );
      _storageService.saveEntry(storageEntry);
    }

    // Update UI if we're viewing today
    if (selectedDate.year == today.year &&
        selectedDate.month == today.month &&
        selectedDate.day == today.day) {
      final existingUiEntry = timelineEntriesByDate[timestamp]?.first;

      if (existingUiEntry != null) {
        // Add to existing entry for this timestamp
        for (final note in notes) {
          final newNoteIndex = existingUiEntry.notes.length;
          existingUiEntry.notes.add(note);
          existingUiEntry.itemOrder.add(TimelineItemRef(
            type: ItemType.note,
            index: newNoteIndex,
            storageId: _storageService.generateId(),
          ));
        }

        for (final task in tasks) {
          final newTaskIndex = existingUiEntry.tasks.length;
          existingUiEntry.tasks.add(task);
          existingUiEntry.itemOrder.add(TimelineItemRef(
            type: ItemType.task,
            index: newTaskIndex,
            storageId: _storageService.generateId(),
          ));
        }
      } else {
        // Create new entry for this timestamp
        List<TimelineItemRef> itemOrder = [];

        for (int i = 0; i < notes.length; i++) {
          itemOrder.add(TimelineItemRef(
            type: ItemType.note,
            index: i,
            storageId: _storageService.generateId(),
          ));
        }

        for (int i = 0; i < tasks.length; i++) {
          itemOrder.add(TimelineItemRef(
            type: ItemType.task,
            index: i,
            storageId: _storageService.generateId(),
          ));
        }

        final newUiEntry = TimelineEntry(
          timestamp: timestamp,
          isDaytime: isDaytime,
          notes: notes,
          tasks: tasks,
          itemOrder: itemOrder,
        );
        timelineEntriesByDate[timestamp] = [newUiEntry];
      }

      onStateUpdate();
    }
  }
}
