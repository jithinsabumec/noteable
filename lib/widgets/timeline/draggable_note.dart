import 'package:flutter/material.dart';

class DraggableNote extends StatelessWidget {
  final String note;
  final String timestamp;
  final int contentListIndex;
  final int orderIndex;
  final String storageId;
  final Function(Map<String, dynamic>, String, Map<String, dynamic>)
      onItemDropOnExisting;

  const DraggableNote({
    super.key,
    required this.note,
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
          left: 12.0,
          right: 12.0,
          top: 8.0,
          bottom: 8.0,
        ),
        child: Text(
          note,
          style: const TextStyle(
            fontSize: 16,
            fontFamily: 'Geist',
            fontWeight: FontWeight.w500,
            height: 24 / 16,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
