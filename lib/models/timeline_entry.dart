import 'package:hive/hive.dart';

part 'timeline_entry.g.dart';

@HiveType(typeId: 0)
class TimelineEntry {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String content;

  @HiveField(2)
  final DateTime timestamp;

  @HiveField(3)
  final EntryType type;

  @HiveField(4)
  bool completed;

  TimelineEntry({
    required this.id,
    required this.content,
    required this.timestamp,
    required this.type,
    this.completed = false,
  });

  String get timeString {
    final hour = timestamp.hour;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final formattedHour = hour > 12
        ? hour - 12
        : hour == 0
            ? 12
            : hour;
    return '$formattedHour:$minute $period';
  }

  // Create a copy with updated values
  TimelineEntry copyWith({
    String? id,
    String? content,
    DateTime? timestamp,
    EntryType? type,
    bool? completed,
  }) {
    return TimelineEntry(
      id: id ?? this.id,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      completed: completed ?? this.completed,
    );
  }
}

@HiveType(typeId: 1)
enum EntryType {
  @HiveField(0)
  note,

  @HiveField(1)
  task
}
 