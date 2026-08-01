import 'package:intl/intl.dart';

class DaySegment {
  final DateTime date;
  final DateTime segmentStart;
  final DateTime segmentEnd;
  final Duration duration;

  const DaySegment({
    required this.date,
    required this.segmentStart,
    required this.segmentEnd,
    required this.duration,
  });
}

class IntervalSplitter {
  static List<DaySegment> splitAtMidnight(DateTime start, DateTime end) {
    final segments = <DaySegment>[];

    if (start.isAfter(end)) return segments;

    final localStart = DateTime(start.year, start.month, start.day, start.hour, start.minute, start.second);
    final localEnd = DateTime(end.year, end.month, end.day, end.hour, end.minute, end.second);

    var cursor = localStart;
    final dayAfterEnd = DateTime(localEnd.year, localEnd.month, localEnd.day).add(const Duration(days: 1));

    while (cursor.isBefore(dayAfterEnd)) {
      final midnight = DateTime(cursor.year, cursor.month, cursor.day).add(const Duration(days: 1));

      final segmentEnd = midnight.isBefore(localEnd) || midnight.isAtSameMomentAs(localEnd) ? midnight : localEnd;

      final segmentDuration = segmentEnd.difference(cursor);

      if (segmentDuration.inSeconds > 0) {
        segments.add(DaySegment(
          date: DateTime(cursor.year, cursor.month, cursor.day),
          segmentStart: cursor,
          segmentEnd: segmentEnd,
          duration: segmentDuration,
        ));
      }

      cursor = midnight;
    }

    return segments;
  }

  static List<DaySegment> splitVisitsAtMidnight({
    required DateTime enterTs,
    DateTime? exitTs,
  }) {
    final effectiveEnd = exitTs ?? DateTime.now();
    return splitAtMidnight(enterTs, effectiveEnd);
  }

  static String formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  static String formatTime(DateTime dt) {
    return DateFormat('h:mm a').format(dt);
  }

  static String formatDate(DateTime dt) {
    return DateFormat('MMM d, yyyy').format(dt);
  }
}