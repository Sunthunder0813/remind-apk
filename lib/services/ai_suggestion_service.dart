// This service scans note text for time-related keywords and phrases,
// then suggests a DateTime for the reminder. No internet or API needed —
// it's all pattern matching against common English phrases.
class AiSuggestionService {
  AiSuggestionService._();
  static final AiSuggestionService instance = AiSuggestionService._();

  // Main entry point: give it note content, get back a suggested DateTime
  // (or null if nothing time-related was found).
  DateTime? suggestReminderTime(String content) {
    final text = content.toLowerCase();
    final now = DateTime.now();

    // Try each detection strategy in order of specificity.
    // More specific patterns (exact times) are checked first.

    final explicitTime = _extractExplicitTime(text);
    final relativeDay = _extractRelativeDay(text, now);
    final namedWeekday = _extractNamedWeekday(text, now);

    // Determine the date part
    DateTime? datePart = relativeDay ?? namedWeekday;

    // Determine the time-of-day part
    final timeOfDay = explicitTime ?? _extractTimeOfDayKeyword(text);

    // If we found neither a date nor a time, nothing to suggest
    if (datePart == null && timeOfDay == null) return null;

    // If we only found a time (e.g. "3pm") with no day mentioned,
    // assume today if that time hasn't passed yet, otherwise tomorrow.
    datePart ??= now;

    // Combine date and time
    final hour = timeOfDay?.hour ?? 9; // default to 9 AM if no time found
    final minute = timeOfDay?.minute ?? 0;

    var result = DateTime(
      datePart.year,
      datePart.month,
      datePart.day,
      hour,
      minute,
    );

    // If the resulting time is in the past and no explicit day was mentioned,
    // push it to tomorrow instead
    if (result.isBefore(now) && relativeDay == null && namedWeekday == null) {
      result = result.add(const Duration(days: 1));
    }

    return result;
  }

  // ── Explicit time extraction (e.g. "3pm", "3:30 pm", "15:00") ────────────
  DateTime? _extractExplicitTime(String text) {
    // Matches things like "3pm", "3 pm", "3:30pm", "3:30 pm"
    final twelveHourPattern =
        RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)');
    final match = twelveHourPattern.firstMatch(text);

    if (match != null) {
      int hour = int.parse(match.group(1)!);
      final minute = match.group(2) != null ? int.parse(match.group(2)!) : 0;
      final period = match.group(3)!;

      if (period == 'pm' && hour != 12) hour += 12;
      if (period == 'am' && hour == 12) hour = 0;

      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day, hour, minute);
    }

    // Matches 24-hour format like "15:00" or "9:30"
    final twentyFourHourPattern = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b');
    final match24 = twentyFourHourPattern.firstMatch(text);
    if (match24 != null) {
      final hour = int.parse(match24.group(1)!);
      final minute = int.parse(match24.group(2)!);
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day, hour, minute);
    }

    return null;
  }

  // ── Time-of-day keyword extraction (e.g. "morning", "afternoon") ─────────
  DateTime? _extractTimeOfDayKeyword(String text) {
    final now = DateTime.now();

    if (text.contains('morning')) {
      return DateTime(now.year, now.month, now.day, 9, 0);
    }
    if (text.contains('noon')) {
      return DateTime(now.year, now.month, now.day, 12, 0);
    }
    if (text.contains('afternoon')) {
      return DateTime(now.year, now.month, now.day, 14, 0);
    }
    if (text.contains('evening')) {
      return DateTime(now.year, now.month, now.day, 18, 0);
    }
    if (text.contains('night')) {
      return DateTime(now.year, now.month, now.day, 20, 0);
    }
    return null;
  }

  // ── Relative day extraction (e.g. "today", "tomorrow", "next week") ──────
  DateTime? _extractRelativeDay(String text, DateTime now) {
    if (text.contains('tomorrow')) {
      return now.add(const Duration(days: 1));
    }
    if (text.contains('next week')) {
      return now.add(const Duration(days: 7));
    }
    if (text.contains('today') || text.contains('tonight')) {
      return now;
    }
    // "in 3 days", "in 2 weeks"
    final inDaysPattern = RegExp(r'in (\d+) day');
    final daysMatch = inDaysPattern.firstMatch(text);
    if (daysMatch != null) {
      final days = int.parse(daysMatch.group(1)!);
      return now.add(Duration(days: days));
    }
    final inWeeksPattern = RegExp(r'in (\d+) week');
    final weeksMatch = inWeeksPattern.firstMatch(text);
    if (weeksMatch != null) {
      final weeks = int.parse(weeksMatch.group(1)!);
      return now.add(Duration(days: weeks * 7));
    }
    return null;
  }

  // ── Named weekday extraction (e.g. "monday", "next friday") ──────────────
  DateTime? _extractNamedWeekday(String text, DateTime now) {
    const weekdays = {
      'monday': DateTime.monday,
      'tuesday': DateTime.tuesday,
      'wednesday': DateTime.wednesday,
      'thursday': DateTime.thursday,
      'friday': DateTime.friday,
      'saturday': DateTime.saturday,
      'sunday': DateTime.sunday,
    };

    for (final entry in weekdays.entries) {
      if (text.contains(entry.key)) {
        // Calculate days until that weekday (always forward, never today)
        int daysUntil = (entry.value - now.weekday) % 7;
        if (daysUntil == 0) daysUntil = 7; // if today, push to next week
        return now.add(Duration(days: daysUntil));
      }
    }
    return null;
  }

  // Returns a short human-readable explanation of why this time was suggested.
  // Useful to show the user "Suggested because you mentioned 'tomorrow'".
  String explainSuggestion(String content) {
    final text = content.toLowerCase();

    if (text.contains('tomorrow')) return 'You mentioned "tomorrow"';
    if (text.contains('next week')) return 'You mentioned "next week"';
    if (text.contains('tonight')) return 'You mentioned "tonight"';
    if (text.contains('today')) return 'You mentioned "today"';
    if (text.contains('morning')) return 'You mentioned "morning"';
    if (text.contains('afternoon')) return 'You mentioned "afternoon"';
    if (text.contains('evening')) return 'You mentioned "evening"';

    const weekdays = [
      'monday', 'tuesday', 'wednesday', 'thursday',
      'friday', 'saturday', 'sunday'
    ];
    for (final day in weekdays) {
      if (text.contains(day)) return 'You mentioned "$day"';
    }

    final timePattern = RegExp(r'\d{1,2}(:\d{2})?\s*(am|pm)');
    if (timePattern.hasMatch(text)) return 'You mentioned a specific time';

    return 'Based on your note content';
  }
}