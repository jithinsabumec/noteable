import 'package:flutter/material.dart';
import '../../models/timeline_models.dart';
import '../../utils/date_formatter.dart';
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
      {bool? completed,
      DateTime? scheduledDate,
      String? scheduledTime}) onShowItemOptions;
  final bool isFirstItem;
  final VoidCallback? onTagTap;

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
    this.onTagTap,
  });

  @override
  Widget build(BuildContext context) {
    const double riveDisplaySize = 28.0;
    final dateLabel = task.scheduledDate == null
        ? ''
        : DateFormatter.formatScheduledDateLabel(task.scheduledDate);
    final timeLabel = task.scheduledTime == null
        ? ''
        : DateFormatter.formatScheduledTimeLabel(task.scheduledTime);
    final hasDateTag = dateLabel.isNotEmpty;
    final hasTimeTag = timeLabel.isNotEmpty;
    final hasTags = hasDateTag || hasTimeTag;

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
          scheduledDate: task.scheduledDate,
          scheduledTime: task.scheduledTime,
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
                    left: 2.0,
                    top:
                        riveTopPadding), // Reduced left padding from 8.0 to 2.0
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
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
                            decoration: task.completed
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor:
                                task.completed ? Colors.grey.shade400 : null,
                            color: task.completed
                                ? Colors.grey.shade400
                                : Colors.black,
                            height: isLikelySingleLine ? 1.0 : 1.5,
                          ),
                        ),
                      ),
                      if (hasTags) const SizedBox(height: 8),
                      if (hasTags)
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (hasDateTag)
                              _TaskMetaChip(
                                label: dateLabel,
                                icon: Icons.calendar_today_outlined,
                                onTap: onTagTap,
                              ),
                            if (hasTimeTag)
                              _TaskMetaChip(
                                label: timeLabel,
                                icon: Icons.schedule_outlined,
                                onTap: onTagTap,
                              ),
                          ],
                        ),
                    ],
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

class _TaskMetaChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _TaskMetaChip({
    required this.label,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F5FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFD9E2FF),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: const Color(0xFF2F55CC),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'Geist',
                fontWeight: FontWeight.w600,
                color: Color(0xFF2F55CC),
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
