import 'dart:math';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../models/timeline_entry.dart';

class StorageService {
  static const String entriesBoxName = 'timeline_entries';
  late Box<TimelineEntry> _entriesBox;

  // Singleton instance
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  Future<void> initialize() async {
    // Initialize Hive
    final appDocumentDir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(appDocumentDir.path);

    // Register adapters
    Hive.registerAdapter(TimelineEntryAdapter());
    Hive.registerAdapter(EntryTypeAdapter());

    // Open box
    _entriesBox = await Hive.openBox<TimelineEntry>(entriesBoxName);
  }

  // Save a new entry
  Future<void> saveEntry(TimelineEntry entry) async {
    try {
      await _entriesBox.put(entry.id, entry);
      // Verify entry was saved
      final saved = _entriesBox.get(entry.id);
      if (saved == null) {
        print('Warning: Entry with ID ${entry.id} was not saved properly');
      }
    } catch (e) {
      print('Error saving entry: $e');
      // Attempt to save again with a retry
      try {
        await _entriesBox.put(entry.id, entry);
      } catch (e) {
        print('Fatal error saving entry: $e');
        // In a production app, you might want to log this to an error reporting service
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
        print('Fatal error updating entry: $e');
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
      final endOfDay =
          DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

      return _entriesBox.values.where((entry) {
        final entryDate = DateTime(
            entry.timestamp.year, entry.timestamp.month, entry.timestamp.day);
        return entryDate.year == startOfDay.year &&
            entryDate.month == startOfDay.month &&
            entryDate.day == startOfDay.day;
      }).toList();
    } catch (e) {
      print('Error retrieving entries for date: $e');
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
