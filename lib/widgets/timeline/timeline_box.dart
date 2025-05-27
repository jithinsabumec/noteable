import 'package:flutter/material.dart';
import '../../models/timeline_models.dart';

import 'draggable_note.dart';
import 'draggable_task.dart';

class TimelineBox extends StatelessWidget {
  final TimelineEntry entry;
  final String timestamp;
  final Function(Map<String, dynamic>, String) onItemDrop;
  final Function(Map<String, dynamic>, String, Map<String, dynamic>)
      onItemDropOnExisting;

  const TimelineBox({
    super.key,
    required this.entry,
    required this.timestamp,
    required this.onItemDrop,
    required this.onItemDropOnExisting,
  });

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
            DraggableNote(
              note: note,
              timestamp: timestamp,
              contentListIndex: itemRef.index,
              orderIndex: orderIndex,
              storageId: itemRef.storageId,
              onItemDropOnExisting: onItemDropOnExisting,
            ),
          );
        }
      } else if (itemRef.type == ItemType.task) {
        if (itemRef.index < entry.tasks.length) {
          final task = entry.tasks[itemRef.index];
          contentWidgets.add(
            DraggableTask(
              task: task,
              timestamp: timestamp,
              contentListIndex: itemRef.index,
              orderIndex: orderIndex,
              storageId: itemRef.storageId,
              onItemDropOnExisting: onItemDropOnExisting,
            ),
          );
        }
      }
    }

    // Show message if no content (and itemOrder was indeed empty)
    if (contentWidgets.isEmpty) {
      contentWidgets.add(
        Container(
          margin: const EdgeInsets.only(left: 4.0, right: 4.0, bottom: 4.0),
          padding: const EdgeInsets.all(16.0),
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

    // Wrap the entire box in a DragTarget
    return DragTarget<Map<String, dynamic>>(
      onWillAccept: (data) => true,
      onAccept: (data) {
        onItemDrop(data, timestamp);
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          margin: const EdgeInsets.only(bottom: 16.0),
          decoration: BoxDecoration(
            color: candidateData.isNotEmpty
                ? const Color(0xFFE5E5E5) // Slightly darker when dragging over
                : const Color(0xFFEEEEEE),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: candidateData.isNotEmpty
                  ? const Color(0xFFD0D0D0)
                  : const Color(0xFFE4E4E4),
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

              // Content widgets (individual cards for each item)
              if (candidateData.isNotEmpty && contentWidgets.isEmpty)
                // Show drop indicator when dragging over an empty box
                Container(
                  margin: const EdgeInsets.all(4.0),
                  padding: const EdgeInsets.all(16.0),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.blue.shade300,
                      width: 1,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      'Drop here',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
              else
                Column(
                  children: contentWidgets,
                ),
            ],
          ),
        );
      },
    );
  }

  // Simple time icon implementation
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

    // Return appropriate icon based on time
    if (hour >= 6 && hour < 12) {
      // Morning
      return const Icon(
        Icons.wb_sunny_outlined,
        size: 16,
        color: Color(0xFF666666),
      );
    } else if (hour >= 12 && hour < 18) {
      // Afternoon
      return const Icon(
        Icons.wb_sunny,
        size: 16,
        color: Color(0xFF666666),
      );
    } else {
      // Evening/Night
      return const Icon(
        Icons.nightlight_round,
        size: 16,
        color: Color(0xFF666666),
      );
    }
  }
}
