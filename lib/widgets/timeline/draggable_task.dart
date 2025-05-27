import 'package:flutter/material.dart';
import '../../models/timeline_models.dart';

class DraggableTask extends StatelessWidget {
  final TaskItem task;
  final String timestamp;
  final int contentListIndex;
  final int orderIndex;
  final String storageId;
  final Function(Map<String, dynamic>, String, Map<String, dynamic>)
      onItemDropOnExisting;

  const DraggableTask({
    super.key,
    required this.task,
    required this.timestamp,
    required this.contentListIndex,
    required this.orderIndex,
    required this.storageId,
    required this.onItemDropOnExisting,
  });

  @override
  Widget build(BuildContext context) {
    // For now, return a simplified version without drag functionality
    // This will be expanded with the full drag logic later
    return Container(
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
        padding: const EdgeInsets.only(
          left: 3.0,
          right: 12.0,
          top: 5.0,
          bottom: 4.0,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Simple checkbox for now
            Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(top: 8.0),
              child: Checkbox(
                value: task.completed,
                onChanged: (bool? value) {
                  // TODO: Implement task completion toggle
                },
              ),
            ),
            const SizedBox(width: 0),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8.0),
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
                    color: task.completed ? Colors.grey.shade400 : Colors.black,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
