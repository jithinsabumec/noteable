class DateFormatter {
  static const List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const List<String> _shortMonths = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static DateTime startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String formatIsoDate(DateTime date) {
    final normalized = startOfDay(date);
    final month = normalized.month.toString().padLeft(2, '0');
    final day = normalized.day.toString().padLeft(2, '0');
    return '${normalized.year}-$month-$day';
  }

  // Format the selected date as required
  static String formatDate(DateTime date) {
    final now = DateTime.now();
    final today = startOfDay(now);
    final yesterday = today.subtract(const Duration(days: 1));
    final selectedDay = startOfDay(date);

    if (selectedDay == today) {
      return 'Today';
    } else if (selectedDay == yesterday) {
      return 'Yesterday';
    } else {
      // Format as "Month Date"
      return '${_months[date.month - 1]} ${date.day}';
    }
  }

  static String formatShortMonthDay(DateTime date) {
    return '${_shortMonths[date.month - 1]} ${date.day}';
  }

  static String formatScheduledDateLabel(DateTime? date,
      {DateTime? referenceDate}) {
    if (date == null) return '';

    final now = startOfDay(referenceDate ?? DateTime.now());
    final target = startOfDay(date);
    final tomorrow = now.add(const Duration(days: 1));
    final yesterday = now.subtract(const Duration(days: 1));

    if (isSameDay(target, now)) return 'Today';
    if (isSameDay(target, tomorrow)) return 'Tomorrow';
    if (isSameDay(target, yesterday)) return 'Yesterday';

    return formatShortMonthDay(target);
  }

  static String? normalizeScheduledTime(dynamic rawValue) {
    if (rawValue == null) return null;

    final value = rawValue.toString().trim();
    if (value.isEmpty) return null;

    final hhmmMatch = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)$').firstMatch(value);
    if (hhmmMatch != null) {
      final hour = int.parse(hhmmMatch.group(1)!);
      final minute = int.parse(hhmmMatch.group(2)!);
      return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    }

    final amPmMatch =
        RegExp(r'^(1[0-2]|0?[1-9])(?::([0-5]\d))?\s*([AaPp][Mm])$')
            .firstMatch(value);
    if (amPmMatch != null) {
      int hour = int.parse(amPmMatch.group(1)!);
      final minute = int.parse(amPmMatch.group(2) ?? '00');
      final period = amPmMatch.group(3)!.toUpperCase();

      if (period == 'PM' && hour < 12) {
        hour += 12;
      } else if (period == 'AM' && hour == 12) {
        hour = 0;
      }

      return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    }

    final lower = value.toLowerCase();
    if (lower.contains('morning')) return '09:00';
    if (lower.contains('afternoon')) return '15:00';
    if (lower.contains('evening')) return '19:00';
    if (lower.contains('night')) return '21:00';

    return null;
  }

  static int? scheduledTimeToMinutes(String? value) {
    final normalized = normalizeScheduledTime(value);
    if (normalized == null) return null;

    final parts = normalized.split(':');
    if (parts.length != 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;

    return (hour * 60) + minute;
  }

  static String formatScheduledTimeLabel(String? value) {
    final normalized = normalizeScheduledTime(value);
    if (normalized == null) return value?.trim() ?? '';

    final parts = normalized.split(':');
    if (parts.length != 2) return normalized;

    final hour24 = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour24 == null || minute == null) return normalized;

    final period = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 == 0
        ? 12
        : hour24 > 12
            ? hour24 - 12
            : hour24;
    return '$hour12:${minute.toString().padLeft(2, '0')} $period';
  }

  // Helper method to check if a timestamp is during the day or night (24-hour format)
  static bool isTimestamp24HourDaytime(DateTime time) {
    final hour = time.hour;
    return hour >= 6 && hour < 18;
  }

  // Helper method to check if a timestamp is during the day or night
  static bool isTimestampDaytime(String timestamp) {
    // Parse hours from "hh:mm AM/PM" format
    final parts = timestamp.split(' ');
    final timeParts = parts[0].split(':');
    int hour = int.parse(timeParts[0]);

    // Convert to 24-hour format
    if (parts[1] == 'PM' && hour < 12) {
      hour += 12;
    } else if (parts[1] == 'AM' && hour == 12) {
      hour = 0;
    }

    // Daytime is between 6 AM and 6 PM
    return hour >= 6 && hour < 18;
  }
}
