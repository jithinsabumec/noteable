// ignore_for_file: empty_catches, duplicate_ignore

import 'dart:math';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../models/timeline_entry.dart';
import '../models/item_type_model.dart';
import '../models/task_item_model.dart';

class StorageService {
  static const String entriesBoxName = 'timeline_entries';
  late Box<TimelineEntry> _entriesBox;

  // Singleton instance
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  Future<void> initialize() async {
    try {
      // Initialize Hive with proper Flutter integration
      // This will use the appropriate directory for each platform
      await Hive.initFlutter();

      // Register adapters only if they haven't been registered already
      if (!Hive.isAdapterRegistered(0))
        Hive.registerAdapter(TimelineEntryAdapter());
      if (!Hive.isAdapterRegistered(1))
        Hive.registerAdapter(EntryTypeAdapter());
      if (!Hive.isAdapterRegistered(2))
        Hive.registerAdapter(TaskItemModelAdapter());
      if (!Hive.isAdapterRegistered(3))
        Hive.registerAdapter(ItemTypeModelAdapter());
      if (!Hive.isAdapterRegistered(4))
        Hive.registerAdapter(TimelineItemRefModelAdapter());

      // Open box
      _entriesBox = await Hive.openBox<TimelineEntry>(entriesBoxName);

      // Verify box is opened successfully
      if (!Hive.isBoxOpen(entriesBoxName)) {
        // Try opening with a specific path if default fails
        final appDocumentDir = await getApplicationDocumentsDirectory();
        _entriesBox = await Hive.openBox<TimelineEntry>(
          entriesBoxName,
          path: appDocumentDir.path,
        );
      }
    } catch (e) {
      print('Hive initialization error: $e');
      // Try with a fallback approach
      try {
        final appDocumentDir = await getApplicationDocumentsDirectory();
        await Hive.initFlutter(appDocumentDir.path);
        _entriesBox = await Hive.openBox<TimelineEntry>(entriesBoxName);
      } catch (fallbackError) {
        print('Hive fallback initialization error: $fallbackError');
        // Create an in-memory box as a last resort
        _entriesBox =
            await Hive.openBox<TimelineEntry>(entriesBoxName, path: '');
      }
    }
  }

  // Save a new entry
  Future<void> saveEntry(TimelineEntry entry) async {
    try {
      await _entriesBox.put(entry.id, entry);
      // Verify entry was saved
      final saved = _entriesBox.get(entry.id);
      if (saved == null) {
        print('Entry was not saved successfully: ${entry.id}');
      }
    } catch (e) {
      print('Error saving entry: $e');
      // Attempt to save again with a retry
      try {
        await _entriesBox.put(entry.id, entry);
      } catch (e) {
        print('Retry error saving entry: $e');
      }
    }
  }

  // Update an existing entry
  Future<void> updateEntry(TimelineEntry entry) async {
    try {
      await _entriesBox.put(entry.id, entry);
    } catch (e) {
      print('Error updating entry: $e');
      // Attempt to update again with a retry
      try {
        await _entriesBox.put(entry.id, entry);
      } catch (e) {
        print('Retry error updating entry: $e');
      }
    }
  }

  // Delete an entry
  Future<void> deleteEntry(String id) async {
    try {
      await _entriesBox.delete(id);
    } catch (e) {
      print('Error deleting entry: $e');
    }
  }

  // Get all entries for a specific date
  List<TimelineEntry> getEntriesForDate(DateTime date) {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);

      return _entriesBox.values.where((entry) {
        final entryDate = DateTime(
            entry.timestamp.year, entry.timestamp.month, entry.timestamp.day);
        return entryDate.year == startOfDay.year &&
            entryDate.month == startOfDay.month &&
            entryDate.day == startOfDay.day;
      }).toList();
    } catch (e) {
      print('Error getting entries for date: $e');
      return [];
    }
  }

  // Get all notes for a specific date
  List<TimelineEntry> getNotesForDate(DateTime date) {
    return getEntriesForDate(date)
        .where((entry) => entry.type == EntryType.note)
        .toList();
  }

  // Get all tasks for a specific date
  List<TimelineEntry> getTasksForDate(DateTime date) {
    return getEntriesForDate(date)
        .where((entry) => entry.type == EntryType.task)
        .toList();
  }

  // Generate a unique ID
  String generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        Random().nextInt(1000).toString();
  }

  // Clear all entries (for testing)
  Future<void> clearAll() async {
    await _entriesBox.clear();
  }
}
