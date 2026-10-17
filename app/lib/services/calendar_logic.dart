import '../models/entry.dart';
import '../models/social.dart';

/// Content-calendar logic (SPEC §7.9 rider): a week view of queued
/// posts by reminder time, with honest suggestion slots.
///
/// Suggestions come from the playbook cadence entry (a sustainable
/// rhythm of question-led posts a few times a week) — they are LABELED
/// suggestions in the UI, never presented as measured "best times":
/// v1 has no engagement data and must not pretend otherwise
/// (SPEC §7.11 honesty rule).
class CalendarDay {
  final DateTime date; // date at local midnight
  final List<PostDraft> posts; // queued posts due this day, time order
  final DateTime? suggestion; // suggested slot time, or null
  const CalendarDay({
    required this.date,
    required this.posts,
    required this.suggestion,
  });

  bool get hasSuggestion => suggestion != null;
}

/// Days of the week (Mon/Wed/Fri) the cadence guidance maps to —
/// "a few times a week".
const Set<int> kSuggestionWeekdays = {
  DateTime.monday,
  DateTime.wednesday,
  DateTime.friday,
};

/// Suggested clock time for an empty slot: 9:00 AM local.
const int kSuggestionHour = 9;

/// The cadence guidance sentence shown as the suggestion's source.
String cadenceGuidance(KnowledgeEntry? cadenceEntry) {
  if (cadenceEntry == null) {
    return 'Playbook guidance: a sustainable rhythm of question-led '
        'posts a few times a week.';
  }
  final flat = cadenceEntry.body.replaceAll(RegExp(r'\s+'), ' ').trim();
  final firstSentence = flat.split(RegExp(r'(?<=[.!?])\s+')).first;
  return 'Playbook guidance: $firstSentence';
}

/// Builds the 7 days of the week containing [anchor] (Monday first).
/// A day gets a suggestion slot when: it is a cadence weekday, it has
/// no queued post, and the suggested time is not in the past.
List<CalendarDay> buildWeek({
  required List<PostDraft> posts,
  required DateTime anchor,
  required DateTime now,
}) {
  final anchorDay = DateTime(anchor.year, anchor.month, anchor.day);
  final monday = anchorDay.subtract(Duration(days: anchorDay.weekday - 1));
  final days = <CalendarDay>[];
  for (var i = 0; i < 7; i++) {
    final day = monday.add(Duration(days: i));
    final dayPosts = posts
        .where((p) =>
            p.status == PostStatus.queued &&
            p.scheduledFor != null &&
            p.scheduledFor!.year == day.year &&
            p.scheduledFor!.month == day.month &&
            p.scheduledFor!.day == day.day)
        .toList()
      ..sort((a, b) => a.scheduledFor!.compareTo(b.scheduledFor!));
    DateTime? suggestion;
    if (dayPosts.isEmpty && kSuggestionWeekdays.contains(day.weekday)) {
      final slot =
          DateTime(day.year, day.month, day.day, kSuggestionHour);
      if (slot.isAfter(now)) suggestion = slot;
    }
    days.add(CalendarDay(date: day, posts: dayPosts, suggestion: suggestion));
  }
  return days;
}
