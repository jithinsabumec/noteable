import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/timeline_models.dart';
import '../../services/item_management_service.dart';
import 'edit_item_dialog.dart';

class ItemOptionsDialog extends StatelessWidget {
  final String timestamp;
  final int contentListIndex;
  final int orderIndex;
  final ItemType itemType;
  final String content;
  final String storageId;
  final bool? completed;
  final ItemManagementService itemManagementService;
  final DateTime selectedDate;
  final Map<String, List<TimelineEntry>> timelineEntriesByDate;
  final VoidCallback onStateUpdate;

  const ItemOptionsDialog({
    super.key,
    required this.timestamp,
    required this.contentListIndex,
    required this.orderIndex,
    required this.itemType,
    required this.content,
    required this.storageId,
    this.completed,
    required this.itemManagementService,
    required this.selectedDate,
    required this.timelineEntriesByDate,
    required this.onStateUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding:
            const EdgeInsets.only(left: 24, right: 24, top: 12, bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 60,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Edit and Delete buttons in a Row
            Row(
              children: [
                // Edit button
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      showEditItemDialog(
                        context: context,
                        timestamp: timestamp,
                        contentListIndex: contentListIndex,
                        orderIndex: orderIndex,
                        itemType: itemType,
                        content: content,
                        completed: completed,
                        storageId: storageId,
                        itemManagementService: itemManagementService,
                        selectedDate: selectedDate,
                        timelineEntriesByDate: timelineEntriesByDate,
                        onStateUpdate: onStateUpdate,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE0E8FF),
                      foregroundColor: const Color(0xFF0038DD),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      elevation: 0,
                      shadowColor: Colors.transparent,
                    ).copyWith(
                      overlayColor: MaterialStateProperty.resolveWith<Color?>(
                        (Set<MaterialState> states) {
                          if (states.contains(MaterialState.pressed)) {
                            return const Color(0xFF0038DD)
                                .withValues(alpha: 0.1);
                          }
                          if (states.contains(MaterialState.hovered)) {
                            return const Color(0xFF0038DD)
                                .withValues(alpha: 0.05);
                          }
                          return null;
                        },
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.asset(
                          'assets/icons/pen.svg',
                          width: 18,
                          height: 18,
                          colorFilter: const ColorFilter.mode(
                            Color(0xFF0038DD),
                            BlendMode.srcIn,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Edit',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Geist',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Delete button
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      itemManagementService.deleteItem(
                        timestamp: timestamp,
                        orderIndexInItemOrder: orderIndex,
                        itemType: itemType,
                        storageId: storageId,
                        timelineEntriesByDate: timelineEntriesByDate,
                        onStateUpdate: onStateUpdate,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFDFDF),
                      foregroundColor: const Color(0xFFC70000),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      elevation: 0,
                      shadowColor: Colors.transparent,
                    ).copyWith(
                      overlayColor: MaterialStateProperty.resolveWith<Color?>(
                        (Set<MaterialState> states) {
                          if (states.contains(MaterialState.pressed)) {
                            return const Color(0xFFC70000)
                                .withValues(alpha: 0.1);
                          }
                          if (states.contains(MaterialState.hovered)) {
                            return const Color(0xFFC70000)
                                .withValues(alpha: 0.05);
                          }
                          return null;
                        },
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.asset(
                          'assets/icons/delete.svg',
                          width: 18,
                          height: 18,
                          colorFilter: const ColorFilter.mode(
                            Color(0xFFC70000),
                            BlendMode.srcIn,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Delete',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Geist',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Helper function to show the item options dialog
void showItemOptionsDialog({
  required BuildContext context,
  required String timestamp,
  required int contentListIndex,
  required int orderIndex,
  required ItemType itemType,
  required String content,
  required String storageId,
  bool? completed,
  required ItemManagementService itemManagementService,
  required DateTime selectedDate,
  required Map<String, List<TimelineEntry>> timelineEntriesByDate,
  required VoidCallback onStateUpdate,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext context) {
      return ItemOptionsDialog(
        timestamp: timestamp,
        contentListIndex: contentListIndex,
        orderIndex: orderIndex,
        itemType: itemType,
        content: content,
        storageId: storageId,
        completed: completed,
        itemManagementService: itemManagementService,
        selectedDate: selectedDate,
        timelineEntriesByDate: timelineEntriesByDate,
        onStateUpdate: onStateUpdate,
      );
    },
  );
}
