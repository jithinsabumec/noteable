import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class TimelineEmptyState extends StatelessWidget {
  final DateTime selectedDate;

  const TimelineEmptyState({
    super.key,
    required this.selectedDate,
  });

  @override
  Widget build(BuildContext context) {
    // Check if we're viewing today or a previous day
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay =
        DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final isToday = selectedDay.isAtSameMomentAs(today);

    String emptyStateText;
    if (isToday) {
      emptyStateText = 'You haven\'t added anything yet.';
    } else {
      emptyStateText = 'No entries for this day.';
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate available height for centering
        final screenHeight = MediaQuery.of(context).size.height;
        final safeAreaTop = MediaQuery.of(context).padding.top;
        final safeAreaBottom = MediaQuery.of(context).padding.bottom;

        // Approximate heights of other elements
        const titleHeight = 36.0 + 16.0 + 16.0; // title + top + bottom padding
        const weekdaySelectorHeight = 80.0; // approximate height
        const topPadding = 24.0 + 16.0; // top padding + timeline top padding
        const bottomPadding = 24.0;

        final availableHeight = screenHeight -
            safeAreaTop -
            safeAreaBottom -
            titleHeight -
            weekdaySelectorHeight -
            topPadding -
            bottomPadding;

        return SizedBox(
          height: availableHeight,
          child: Center(
            child: Transform.translate(
              offset: const Offset(0, 180), // Move up 20px from center
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SvgPicture.asset(
                    'assets/icons/home-emptystate.svg',
                    width: 219,
                    height: 137,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    emptyStateText,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                      fontFamily: 'Geist',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
