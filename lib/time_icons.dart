import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class TimeIcons {
  static Widget getTimeIcon(String timestamp) {
    // Parse the timestamp to get the hour
    final timeParts = timestamp.split(' ');
    final hourMinute = timeParts[0].split(':');
    int hour = int.parse(hourMinute[0]);
    final ampm = timeParts[1];

    // Convert to 24-hour format
    if (ampm == 'PM' && hour != 12) {
      hour += 12;
    } else if (ampm == 'AM' && hour == 12) {
      hour = 0;
    }

    String svgAsset;

    if (hour < 12) {
      // Morning icon (before 12:00 PM)
      svgAsset = 'assets/icons/morning.svg';
    } else if (hour >= 12 && hour < 16) {
      // Afternoon icon (12:00 PM to 4:00 PM)
      svgAsset = 'assets/icons/afternoon.svg';
    } else {
      // Evening icon (after 4:00 PM)
      svgAsset = 'assets/icons/evening.svg';
    }

    return SvgPicture.asset(
      svgAsset,
      width: 18,
      height: 18,
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      allowDrawingOutsideViewBox: true,
    );
  }
}
