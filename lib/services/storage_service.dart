import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/timeline_entry.dart';

class StorageService {
  static const String _usersCollection = 'users';
  static const String _entriesCollection = 'timeline_entries';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Map<String, TimelineEntry> _guestEntries = {};

  // Singleton instance
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  Future<void> initialize() async {}

  String? get _userId => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> _entriesRef(String userId) {
    return _firestore
        .collection(_usersCollection)
        .doc(userId)
        .collection(_entriesCollection);
  }

  DateTime _startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime? _parseTimestampValue(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value.trim());
    return null;
  }

  DateTime? _parseDateValue(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) {
      final date = value.toDate();
      return _startOfDay(date);
    }
    if (value is DateTime) {
      return _startOfDay(value);
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value.trim());
      if (parsed != null) {
        return _startOfDay(parsed);
      }
    }
    return null;
  }

  String? _normalizeScheduledTime(dynamic rawValue) {
    if (rawValue == null) return null;

    final value = rawValue.toString().trim();
    if (value.isEmpty) return null;

    final hhmmMatch = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)$').firstMatch(value);
    if (hhmmMatch != null) {
      final hour = int.parse(hhmmMatch.group(1)!);
      final minute = int.parse(hhmmMatch.group(2)!);
      return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    }

    final amPmMatch =
        RegExp(r'^(1[0-2]|0?[1-9])(?::([0-5]\d))?\s*([AaPp][Mm])$')
            .firstMatch(value);
    if (amPmMatch != null) {
      int hour = int.parse(amPmMatch.group(1)!);
      final minute = int.parse(amPmMatch.group(2) ?? '00');
      final period = amPmMatch.group(3)!.toUpperCase();

      if (period == 'PM' && hour < 12) {
        hour += 12;
      } else if (period == 'AM' && hour == 12) {
        hour = 0;
      }

      return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    }

    final lower = value.toLowerCase();
    if (lower.contains('morning')) return '09:00';
    if (lower.contains('afternoon')) return '15:00';
    if (lower.contains('evening')) return '19:00';
    if (lower.contains('night')) return '21:00';

    return null;
  }

  DateTime _effectiveTaskDate(TimelineEntry entry) {
    return _startOfDay(entry.scheduledDate ?? entry.timestamp);
  }

  bool _isTaskWithinRange(TimelineEntry entry, DateTime? from, DateTime? to) {
    final taskDate = _effectiveTaskDate(entry);
    if (from != null && taskDate.isBefore(from)) {
      return false;
    }
    if (to != null && taskDate.isAfter(to)) {
      return false;
    }
    return true;
  }

  int? _scheduledTimeToMinutes(String? value) {
    final normalized = _normalizeScheduledTime(value);
    if (normalized == null) return null;

    final parts = normalized.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;

    return (hour * 60) + minute;
  }

  int _compareTasks(TimelineEntry a, TimelineEntry b) {
    final dateCompare = _effectiveTaskDate(a).compareTo(_effectiveTaskDate(b));
    if (dateCompare != 0) return dateCompare;

    final aMinutes = _scheduledTimeToMinutes(a.scheduledTime) ?? 9999;
    final bMinutes = _scheduledTimeToMinutes(b.scheduledTime) ?? 9999;
    if (aMinutes != bMinutes) return aMinutes.compareTo(bMinutes);

    return a.timestamp.compareTo(b.timestamp);
  }

  Map<String, dynamic> _toMap(TimelineEntry entry) {
    return {
      'content': entry.content,
      'timestamp': Timestamp.fromDate(entry.timestamp),
      'type': entry.type.name,
      'completed': entry.completed,
      'scheduledDate': entry.scheduledDate == null
          ? null
          : Timestamp.fromDate(_startOfDay(entry.scheduledDate!)),
      'scheduledTime': _normalizeScheduledTime(entry.scheduledTime),
    };
  }

  TimelineEntry _fromMap(String id, Map<String, dynamic> data) {
    final String type = (data['type'] as String?) ?? 'note';
    final timestamp = _parseTimestampValue(data['timestamp']) ?? DateTime.now();

    return TimelineEntry(
      id: id,
      content: (data['content'] as String?) ?? '',
      timestamp: timestamp,
      type: type == EntryType.task.name ? EntryType.task : EntryType.note,
      completed: (data['completed'] as bool?) ?? false,
      scheduledDate: _parseDateValue(data['scheduledDate']),
      scheduledTime: _normalizeScheduledTime(data['scheduledTime']),
    );
  }

  // Save a new entry
  Future<void> saveEntry(TimelineEntry entry) async {
    final userId = _userId;
    if (userId == null) {
      _guestEntries[entry.id] = entry;
      return;
    }
    await _entriesRef(userId).doc(entry.id).set(_toMap(entry));
  }

  // Update an existing entry
  Future<void> updateEntry(TimelineEntry entry) async {
    final userId = _userId;
    if (userId == null) {
      _guestEntries[entry.id] = entry;
      return;
    }
    await _entriesRef(userId).doc(entry.id).set(_toMap(entry));
  }

  // Delete an entry
  Future<void> deleteEntry(String id) async {
    final userId = _userId;
    if (userId == null) {
      _guestEntries.remove(id);
      return;
    }
    await _entriesRef(userId).doc(id).delete();
  }

  // Get all entries for a specific date
  Future<List<TimelineEntry>> getEntriesForDate(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final userId = _userId;

    if (userId == null) {
      return _guestEntries.values.where((entry) {
        final entryDate = DateTime(
            entry.timestamp.year, entry.timestamp.month, entry.timestamp.day);
        return entryDate.year == startOfDay.year &&
            entryDate.month == startOfDay.month &&
            entryDate.day == startOfDay.day;
      }).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    final query = await _entriesRef(userId)
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay))
        .orderBy('timestamp')
        .get();

    return query.docs.map((doc) => _fromMap(doc.id, doc.data())).toList();
  }

  Future<TimelineEntry?> getEntryById(String id) async {
    final userId = _userId;
    if (userId == null) {
      return _guestEntries[id];
    }

    final doc = await _entriesRef(userId).doc(id).get();
    if (!doc.exists || doc.data() == null) {
      return null;
    }
    return _fromMap(doc.id, doc.data()!);
  }

  // Get all notes for a specific date
  Future<List<TimelineEntry>> getNotesForDate(DateTime date) async {
    final entries = await getEntriesForDate(date);
    return entries.where((entry) => entry.type == EntryType.note).toList();
  }

  // Get all tasks for a specific date
  Future<List<TimelineEntry>> getTasksForDate(DateTime date) async {
    final entries = await getEntriesForDate(date);
    return entries.where((entry) => entry.type == EntryType.task).toList();
  }

  Future<List<TimelineEntry>> getTasksInDateRange(
      DateTime? from, DateTime? to) async {
    final fromDate = from == null ? null : _startOfDay(from);
    final toDate = to == null ? null : _startOfDay(to);
    final userId = _userId;

    if (userId == null) {
      final tasks = _guestEntries.values
          .where((entry) => entry.type == EntryType.task)
          .where((entry) => _isTaskWithinRange(entry, fromDate, toDate))
          .toList()
        ..sort(_compareTasks);
      return tasks;
    }

    // For larger datasets, create an index on `type` + `timestamp`.
    final query = await _entriesRef(userId)
        .where('type', isEqualTo: EntryType.task.name)
        .orderBy('timestamp')
        .get();

    final tasks = query.docs
        .map((doc) => _fromMap(doc.id, doc.data()))
        .where((entry) => _isTaskWithinRange(entry, fromDate, toDate))
        .toList()
      ..sort(_compareTasks);

    return tasks;
  }

  // Generate a unique ID
  String generateId() {
    final userId = _userId;
    if (userId != null) {
      return _entriesRef(userId).doc().id;
    }
    return DateTime.now().millisecondsSinceEpoch.toString() +
        Random().nextInt(1000).toString();
  }

  // Clear all entries (for testing)
  Future<void> clearAll() async {
    final userId = _userId;
    if (userId == null) {
      _guestEntries.clear();
      return;
    }

    final snapshot = await _entriesRef(userId).get();
    for (final doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }
}
