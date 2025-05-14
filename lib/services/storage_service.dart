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
    await _entriesBox.put(entry.id, entry);
  }

  // Update an existing entry
  Future<void> updateEntry(TimelineEntry entry) async {
    await _entriesBox.put(entry.id, entry);
  }

  // Delete an entry
  Future<void> deleteEntry(String id) async {
    await _entriesBox.delete(id);
  }

  // Get all entries for a specific date
  List<TimelineEntry> getEntriesForDate(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

    return _entriesBox.values.where((entry) {
      return entry.timestamp.isAfter(startOfDay) &&
          entry.timestamp.isBefore(endOfDay);
    }).toList();
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
