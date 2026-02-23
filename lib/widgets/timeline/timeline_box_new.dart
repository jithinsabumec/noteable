import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/timeline_models.dart';
import 'timeline_task_item.dart';
import 'timeline_note_item.dart';

class TimelineBoxNew extends StatelessWidget {
  final TimelineEntry entry;
  final String timestamp;
  final Function(String timestamp, int orderIndex, ItemType itemType,
      String content, bool completed, String storageId) onUpdateItem;
  final Function(String timestamp, int contentListIndex, int orderIndex,
      ItemType itemType, String content, String storageId,
      {bool? completed,
      DateTime? scheduledDate,
      String? scheduledTime}) onShowItemOptions;
  final Function(String timestamp, int contentListIndex, int orderIndex,
      ItemType itemType, String content, String storageId,
      {bool? completed,
      DateTime? scheduledDate,
      String? scheduledTime})? onEditItem;

  const TimelineBoxNew({
    super.key,
    required this.entry,
    required this.timestamp,
    required this.onUpdateItem,
    required this.onShowItemOptions,
    this.onEditItem,
  });

  // Time icon implementation using SVG assets
  Widget _getTimeIcon(String timestamp) {
    // Parse the timestamp to determine time of day
    final parts = timestamp.split(' ');
    final timeParts = parts[0].split(':');
    int hour = int.parse(timeParts[0]);

    // Convert to 24-hour format
    if (parts[1] == 'PM' && hour < 12) {
      hour += 12;
    } else if (parts[1] == 'AM' && hour == 12) {
      hour = 0;
    }

    // Return appropriate SVG icon based on time
    String iconPath;
    if (hour >= 6 && hour < 12) {
      // Morning
      iconPath = 'assets/icons/morning.svg';
    } else if (hour >= 12 && hour < 18) {
      // Afternoon
      iconPath = 'assets/icons/afternoon.svg';
    } else {
      // Evening/Night
      iconPath = 'assets/icons/evening.svg';
    }

    return SvgPicture.asset(
      iconPath,
      width: 16,
      height: 16,
      colorFilter: const ColorFilter.mode(
        Color(0xFF666666),
        BlendMode.srcIn,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get appropriate time icon based on timestamp
    final timeIcon = _getTimeIcon(entry.timestamp);

    List<Widget> contentWidgets = [];

    for (int i = 0; i < entry.itemOrder.length; i++) {
      final itemRef = entry.itemOrder[i];
      final orderIndex = i; // This is the item's index in itemOrder

      if (itemRef.type == ItemType.note) {
        if (itemRef.index < entry.notes.length) {
          final note = entry.notes[itemRef.index];
          contentWidgets.add(
            TimelineNoteItem(
              note: note,
              timestamp: timestamp,
              contentListIndex: itemRef.index,
              orderIndex: orderIndex,
              storageId: itemRef.storageId,
              onShowItemOptions: onShowItemOptions,
            ),
          );
        }
      } else if (itemRef.type == ItemType.task) {
        if (itemRef.index < entry.tasks.length) {
          final task = entry.tasks[itemRef.index];

          contentWidgets.add(
            TimelineTaskItem(
              task: task,
              timestamp: timestamp,
              orderIndex: orderIndex,
              storageId: itemRef.storageId,
              onUpdateItem: onUpdateItem,
              onShowItemOptions: onShowItemOptions,
              contentListIndex: itemRef.index,
              onTagTap: () {
                if (onEditItem == null) {
                  onShowItemOptions(
                    timestamp,
                    itemRef.index,
                    orderIndex,
                    ItemType.task,
                    task.task,
                    itemRef.storageId,
                    completed: task.completed,
                    scheduledDate: task.scheduledDate,
                    scheduledTime: task.scheduledTime,
                  );
                  return;
                }

                onEditItem!(
                  timestamp,
                  itemRef.index,
                  orderIndex,
                  ItemType.task,
                  task.task,
                  itemRef.storageId,
                  completed: task.completed,
                  scheduledDate: task.scheduledDate,
                  scheduledTime: task.scheduledTime,
                );
              },
            ),
          );
        }
      }
    }

    // Show message if no content
    if (contentWidgets.isEmpty) {
      contentWidgets.add(
        Container(
          margin: const EdgeInsets.only(left: 4.0, right: 4.0, bottom: 4.0),
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: const Color(0xFFE1E1E1),
              width: 1,
            ),
          ),
          child: const Center(
            child: Text('Drop items here'),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEEEE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFE4E4E4),
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x19000000),
            blurRadius: 17.60,
            offset: Offset(0, 4),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp header
          Padding(
            padding: const EdgeInsets.only(
                top: 4.0, bottom: 4.0, left: 4.0, right: 4.0),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: timeIcon,
                ),
                const SizedBox(width: 6),
                Text(
                  entry.timestamp,
                  style: const TextStyle(
                    fontSize: 14,
                    fontFamily: 'GeistMono',
                    color: Color(0xFF666666),
                  ),
                ),
              ],
            ),
          ),
          // Content widgets
          Column(
            children: contentWidgets,
          ),
        ],
      ),
    );
  }
}
