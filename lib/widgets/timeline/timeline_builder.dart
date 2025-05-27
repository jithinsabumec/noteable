import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/timeline_models.dart';
import 'timeline_box.dart';

class TimelineBuilder extends StatelessWidget {
  final Map<String, List<TimelineEntry>> timelineEntriesByDate;
  final Function(Map<String, dynamic>, String) onItemDrop;
  final Function(Map<String, dynamic>, String, Map<String, dynamic>)
      onItemDropOnExisting;

  const TimelineBuilder({
    super.key,
    required this.timelineEntriesByDate,
    required this.onItemDrop,
    required this.onItemDropOnExisting,
  });

  @override
  Widget build(BuildContext context) {
    if (timelineEntriesByDate.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/icons/home-emptystate.svg',
              width: 219,
              height: 137,
            ),
            const SizedBox(height: 16),
            Text(
              'You haven\'t added anything yet.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontFamily: 'Geist',
              ),
            ),
          ],
        ),
      );
    }

    final sortedTimestamps = timelineEntriesByDate.keys.toList()
      ..sort((a, b) => _compareTimestamps(b, a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sortedTimestamps.map((timestamp) {
        final entries = timelineEntriesByDate[timestamp]!;
        return TimelineBox(
          entry: entries.first,
          timestamp: timestamp,
          onItemDrop: onItemDrop,
          onItemDropOnExisting: onItemDropOnExisting,
        );
      }).toList(),
    );
  }

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
}
