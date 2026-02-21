import 'package:flutter/material.dart';
import '../../models/timeline_models.dart';
import '../rive_checkbox.dart';

class TimelineTaskItem extends StatelessWidget {
  final TaskItem task;
  final String timestamp;
  final int orderIndex;
  final int contentListIndex;
  final String storageId;
  final Function(String timestamp, int orderIndex, ItemType itemType,
      String content, bool completed, String storageId) onUpdateItem;
  final Function(String timestamp, int contentListIndex, int orderIndex,
      ItemType itemType, String content, String storageId,
      {bool? completed}) onShowItemOptions;
  final bool isFirstItem;

  const TimelineTaskItem({
    super.key,
    required this.task,
    required this.timestamp,
    required this.orderIndex,
    required this.contentListIndex,
    required this.storageId,
    required this.onUpdateItem,
    required this.onShowItemOptions,
    this.isFirstItem = false,
  });

  @override
  Widget build(BuildContext context) {
    const double riveDisplaySize = 28.0;
    const double desiredLayoutHeight = riveDisplaySize; // Don't reduce height

    // Original X/Y offset values
    const double xOffset = -2.0;
    const double yOffset = -2.0;

    // Estimate if the text is likely a single line - this is a rough estimate based on character count
    final bool isLikelySingleLine =
        task.task.length < 40; // Assuming average 40 chars fit on a line

    // Conditional styling based on line count
    final double riveTopPadding = isLikelySingleLine ? 2.0 : 4.0;
    final double textTopPadding = isLikelySingleLine ? 8.0 : 6.0;
    final double textBottomPadding = isLikelySingleLine ? 8.0 : 4.0;

    return GestureDetector(
      onLongPress: () {
        onShowItemOptions(
          timestamp,
          contentListIndex,
          orderIndex,
          ItemType.task,
          task.task,
          storageId,
          completed: task.completed,
        );
      },
      child: Container(
        margin: const EdgeInsets.only(left: 4.0, right: 4.0, bottom: 4.0),
        width: double.infinity,
        padding: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: const Color(0xFFE1E1E1),
            width: 1,
          ),
        ),
        child: Container(
          padding: EdgeInsets.only(
            left: 3.0, // Exact left padding as requested
            right: 12.0, // Keep original right padding
            top: isFirstItem ? 5.0 : 3.0, // Exact top padding as requested
            bottom:
                isLikelySingleLine ? 4.0 : 8.0, // Conditional bottom padding
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment
                .start, // Changed back to start for top alignment
            children: [
              Padding(
                padding: EdgeInsets.only(
                    left: 2.0, top: riveTopPadding), // Reduced left padding from 8.0 to 2.0
                child: RiveCheckbox(
                  isChecked: task.completed,
                  onChanged: (bool? newValue) {
                    if (newValue == null) return;
                    onUpdateItem(
                      timestamp,
                      orderIndex,
                      ItemType.task,
                      task.task,
                      newValue,
                      storageId,
                    );
                  },
                  size: riveDisplaySize,
                ),
              ),
              const SizedBox(width: 3), // Reduced gap from 8 to 2
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    top: textTopPadding, // Conditional top padding
                    bottom: textBottomPadding, // Conditional bottom padding
                  ),
                  child: GestureDetector(
                    onTap: () {
                      onUpdateItem(
                        timestamp,
                        orderIndex,
                        ItemType.task,
                        task.task,
                        !task.completed,
                        storageId,
                      );
                    },
                    child: Text(
                      task.task,
                      style: TextStyle(
                        fontSize: 16,
                        fontFamily: 'Geist',
                        fontWeight: FontWeight.w500,
                        decoration:
                            task.completed ? TextDecoration.lineThrough : null,
                        decorationColor:
                            task.completed ? Colors.grey.shade400 : null,
                        color: task.completed
                            ? Colors.grey.shade400
                            : Colors.black,
                        height: isLikelySingleLine
                            ? 1.0
                            : 1.5, // Tighter line height for single line text
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
