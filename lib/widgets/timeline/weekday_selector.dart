import 'package:flutter/material.dart';

class WeekdaySelector extends StatelessWidget {
  final DateTime selectedDate;
  final PageController pageController;
  final int initialPage;
  final Function(DateTime) onDateSelected;
  final Function(int) onPageChanged;

  const WeekdaySelector({
    super.key,
    required this.selectedDate,
    required this.pageController,
    required this.initialPage,
    required this.onDateSelected,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: SizedBox(
        height: 80,
        child: Stack(
          children: [
            // Main date selector
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                // Track when user is manually scrolling
                return false;
              },
              child: PageView.builder(
                controller: pageController,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                onPageChanged: onPageChanged,
                itemBuilder: (context, pageIndex) {
                  // Only build pages for current week and past weeks
                  if (pageIndex > initialPage) {
                    return Container(); // Empty container for future weeks
                  }

                  // For current week (offset 0) or past weeks (offset > 0)
                  final weekOffset = initialPage - pageIndex;
                  final startOfWeek = now.subtract(
                      Duration(days: now.weekday - 1 + (weekOffset * 7)));

                  final weekdays = [
                    'Mon',
                    'Tue',
                    'Wed',
                    'Thu',
                    'Fri',
                    'Sat',
                    'Sun'
                  ];

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: List.generate(7, (index) {
                      final dayDate = startOfWeek.add(Duration(days: index));
                      final normalizedDayDate =
                          DateTime(dayDate.year, dayDate.month, dayDate.day);

                      final isSelectedDay = selectedDate.year == dayDate.year &&
                          selectedDate.month == dayDate.month &&
                          selectedDate.day == dayDate.day;

                      final isCurrentDay = dayDate.year == today.year &&
                          dayDate.month == today.month &&
                          dayDate.day == today.day;

                      // Check if date is after today (future date)
                      final bool isFuture = normalizedDayDate.isAfter(today);

                      // Set text color:
                      // - Future dates: light grey
                      // - Today: blue
                      // - Selected day: dark grey
                      // - Other dates: medium grey
                      final Color textColor = isFuture
                          ? const Color(
                              0xFFD0D0D0) // Lighter gray for disabled dates
                          : isCurrentDay
                              ? const Color(
                                  0xFF225AFF) // Blue for today instead of orange
                              : isSelectedDay
                                  ? const Color(0xFF191919)
                                  : const Color(0xFF9D9D9D);

                      // Set background color for selected dates:
                      // - Light blue for today
                      // - Light grey for other dates
                      final Color selectionColor = isCurrentDay
                          ? const Color.fromARGB(255, 236, 242,
                              255) // Light blue for today instead of light orange
                          : const Color(
                              0xFFEEEEEE); // Light grey for other dates

                      return InkWell(
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        onTap: isFuture
                            ? null
                            : () {
                                onDateSelected(dayDate);
                              },
                        child: Container(
                          width: 45, // Increase width slightly
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            children: [
                              Text(
                                weekdays[index],
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600, // SemiBold
                                  fontFamily: 'Geist',
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: 30,
                                height: 30,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isSelectedDay && !isFuture
                                      ? selectionColor // Use dynamic selection color
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Text(
                                  '${dayDate.day}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600, // SemiBold
                                    fontFamily: 'GeistMono',
                                    color: textColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),

            // Left gradient overlay
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 24,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.white,
                      Colors.white.withOpacity(0.0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),

            // Right gradient overlay
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 24,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    colors: [
                      Colors.white,
                      Colors.white.withOpacity(0.0),
                    ],
                    stops: const [0.0, 1.0],
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
