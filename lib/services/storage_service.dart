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

  Map<String, dynamic> _toMap(TimelineEntry entry) {
    return {
      'content': entry.content,
      'timestamp': Timestamp.fromDate(entry.timestamp),
      'type': entry.type.name,
      'completed': entry.completed,
    };
  }

  TimelineEntry _fromMap(String id, Map<String, dynamic> data) {
    final String type = (data['type'] as String?) ?? 'note';
    final Timestamp? ts = data['timestamp'] as Timestamp?;

    return TimelineEntry(
      id: id,
      content: (data['content'] as String?) ?? '',
      timestamp: ts?.toDate() ?? DateTime.now(),
      type: type == EntryType.task.name ? EntryType.task : EntryType.note,
      completed: (data['completed'] as bool?) ?? false,
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
