import 'package:flutter/material.dart';

class GuestRecordingCounter extends StatelessWidget {
  final int recordingsUsed;
  final int maxRecordings;

  const GuestRecordingCounter({
    super.key,
    required this.recordingsUsed,
    required this.maxRecordings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Recording icon
          Icon(
            Icons.mic,
            size: 14,
            color: Colors.white.withOpacity(0.9),
          ),
          const SizedBox(width: 6),
          // Counter text
          Text(
            '$recordingsUsed/$maxRecordings',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'GeistMono',
              color: Colors.white.withOpacity(0.9),
              height: 1.0,
            ),
          ),
          const SizedBox(width: 4),
          // Dots indicator
          Row(
            children: List.generate(maxRecordings, (index) {
              final isUsed = index < recordingsUsed;
              return Container(
                margin: const EdgeInsets.only(left: 2),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isUsed
                      ? const Color(0xFF588EFF)
                      : Colors.white.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
