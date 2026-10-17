import 'package:flutter/material.dart';

import '../services/emotion.dart';

import '../models/social.dart';
import '../services/calendar_logic.dart';
import '../theme.dart';
import '../widgets/social_widgets.dart';
import 'guide_screen.dart';

/// Content calendar (SPEC §7.9 rider): this week's queued posts by
/// their reminder day, plus LABELED suggestion slots from the playbook
/// cadence guidance. Tapping a queued post opens it in the queue;
/// tapping a suggestion opens the generator pre-filled for that slot.
class CalendarScreen extends StatefulWidget {
  final SocialDeps deps;

  /// Opens a queued post in the Posts queue.
  final void Function(String postId) onOpenPost;

  /// Opens the generator pre-filled for a suggested slot.
  final void Function(DateTime when) onDraftForSlot;
  const CalendarScreen({
    super.key,
    required this.deps,
    required this.onOpenPost,
    required this.onDraftForSlot,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  int _weekOffset = 0;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final anchor = now.add(Duration(days: _weekOffset * 7));
    return Scaffold(
      appBar: AppBar(title: const Text('Content calendar'), actions: [HelpButton(screenKey: 'calendar', brand: widget.deps.brand, services: widget.deps.m2, db: widget.deps.db, share: widget.deps.share, emotionLevel: EmotionLevel.warm)],),
      body: AnimatedBuilder(
        animation: widget.deps.store,
        builder: (context, _) {
          final days = buildWeek(
            posts: widget.deps.store.posts,
            anchor: anchor,
            now: now,
          );
          final cadence = widget.deps.db.byId('play-cadence-and-replies');
          final guidance = cadenceGuidance(cadence);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Your week at a glance: queued posts on the day their '
                'reminder is set. Empty rhythm days show a suggestion '
                'from the playbook — a suggestion, not a promise about '
                '"best times": this app has no engagement data, and it '
                'will not pretend otherwise.',
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _weekOffset--),
                    icon: const Icon(Icons.chevron_left, size: 18),
                    label: const Text('Earlier'),
                  ),
                  Text(
                    _weekOffset == 0
                        ? 'This week'
                        : _weekOffset == 1
                            ? 'Next week'
                            : _weekOffset == -1
                                ? 'Last week'
                                : 'Week offset $_weekOffset',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _weekOffset++),
                    icon: const Icon(Icons.chevron_right, size: 18),
                    label: const Text('Later'),
                  ),
                ],
              ),
              for (final day in days)
                _DayCard(
                  day: day,
                  isToday: day.date.year == now.year &&
                      day.date.month == now.month &&
                      day.date.day == now.day,
                  onOpenPost: widget.onOpenPost,
                  onDraftForSlot: widget.onDraftForSlot,
                ),
              const SizedBox(height: 8),
              Card(
                color: LwColors.tint,
                child: ListTile(
                  leading: const Icon(Icons.lightbulb_outline,
                      color: LwColors.primary),
                  title: const Text('Where suggestions come from'),
                  subtitle: Text(guidance),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final CalendarDay day;
  final bool isToday;
  final void Function(String postId) onOpenPost;
  final void Function(DateTime when) onDraftForSlot;
  const _DayCard({
    required this.day,
    required this.isToday,
    required this.onOpenPost,
    required this.onDraftForSlot,
  });

  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    'Sunday',
  ];
  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final d = day.date;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: isToday ? LwColors.tint : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_weekdayNames[d.weekday - 1]}, ${_monthNames[d.month - 1]} ${d.day}'
              '${isToday ? ' — today' : ''}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            if (day.posts.isEmpty && !day.hasSuggestion)
              const Text('Nothing queued.',
                  style: TextStyle(fontSize: 13, color: Colors.black54)),
            for (final post in day.posts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_outlined,
                    color: LwColors.primary),
                title: Text(post.text,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle:
                    Text('Reminder: ${formatWhen(post.scheduledFor!)} — '
                        '${post.destination.label}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpenPost(post.id),
              ),
            if (day.hasSuggestion)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lightbulb_outline,
                    color: Colors.orange),
                title: const Text('Good slot — want to draft a post?'),
                subtitle: Text(
                    'Suggestion from the playbook rhythm: '
                    '${formatWhen(day.suggestion!)}. Tap to draft a '
                    'post for this slot.'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => onDraftForSlot(day.suggestion!),
              ),
          ],
        ),
      ),
    );
  }
}
