import 'package:flutter/material.dart';
import '../../models/timeline_models.dart';

class TimelineNoteItem extends StatelessWidget {
  final String note;
  final String timestamp;
  final int contentListIndex;
  final int orderIndex;
  final String storageId;
  final Function(String timestamp, int contentListIndex, int orderIndex,
      ItemType itemType, String content, String storageId,
      {bool? completed}) onShowItemOptions;

  const TimelineNoteItem({
    super.key,
    required this.note,
    required this.timestamp,
    required this.contentListIndex,
    required this.orderIndex,
    required this.storageId,
    required this.onShowItemOptions,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        onShowItemOptions(
          timestamp,
          contentListIndex,
          orderIndex,
          ItemType.note,
          note,
          storageId,
        );
      },
      child: Container(
        margin: const EdgeInsets.only(left: 4.0, right: 4.0, bottom: 4.0),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: const Color(0xFFE1E1E1),
            width: 1,
          ),
        ),
        child: Text(
          note,
          style: const TextStyle(
            fontSize: 16,
            fontFamily: 'Geist',
            fontWeight: FontWeight.w500,
            color: Colors.black,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
