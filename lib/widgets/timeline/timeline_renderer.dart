import 'package:flutter/material.dart';
import '../../models/timeline_models.dart';
import '../rive_checkbox.dart';
import 'timeline_box_new.dart';
import 'timeline_empty_state.dart';

class TimelineRenderer extends StatelessWidget {
  final Map<String, List<TimelineEntry>> timelineEntriesByDate;
  final DateTime selectedDate;
  final Function(String timestamp, int orderIndex, ItemType itemType,
      String content, bool completed, String storageId) onUpdateItem;
  final Function(String timestamp, int contentListIndex, int orderIndex,
      ItemType itemType, String content, String storageId,
      {bool? completed}) onShowItemOptions;

  const TimelineRenderer({
    super.key,
    required this.timelineEntriesByDate,
    required this.selectedDate,
    required this.onUpdateItem,
    required this.onShowItemOptions,
  });

  // Compare timestamps for sorting
  int _compareTimestamps(String a, String b) {
    final aParts = a.split(' ');
    final bParts = b.split(' ');

    final aTime = aParts[0].split(':');
    final bTime = bParts[0].split(':');

    int aHour = int.parse(aTime[0]);
    int bHour = int.parse(bTime[0]);

    // Convert to 24-hour format for comparison
    if (aParts[1] == 'PM' && aHour < 12) aHour += 12;
    if (aParts[1] == 'AM' && aHour == 12) aHour = 0;
    if (bParts[1] == 'PM' && bHour < 12) bHour += 12;
    if (bParts[1] == 'AM' && bHour == 12) bHour = 0;

    if (aHour != bHour) return aHour - bHour;

    int aMinute = int.parse(aTime[1]);
    int bMinute = int.parse(bTime[1]);

    return aMinute - bMinute;
  }

  @override
  Widget build(BuildContext context) {
    if (timelineEntriesByDate.isEmpty) {
      return TimelineEmptyState(selectedDate: selectedDate);
    }

    final sortedTimestamps = timelineEntriesByDate.keys.toList()
      ..sort((a, b) => _compareTimestamps(b, a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sortedTimestamps.map((timestamp) {
        final entries = timelineEntriesByDate[timestamp]!;
        final entry = entries.first;

        return TimelineBoxNew(
          entry: entry,
          timestamp: timestamp,
          onUpdateItem: onUpdateItem,
          onShowItemOptions: onShowItemOptions,
        );
      }).toList(),
    );
  }
}
