import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/entry.dart';
import '../models/journey.dart';
import '../models/social.dart' show formatWhen;
import '../services/compliance_guide.dart';
import '../services/journey.dart';
import '../theme.dart';
import '../widgets/social_widgets.dart';
import 'guide_screen.dart';

/// 30-day customer journey (SPEC §7.8 item 5 + §7.9 check-ins):
/// day counter, timeline (check-ins 3/7/30, reorder nudge day 25),
/// compliance-scanned check-in drafts with honest handoff states,
/// official-usage placement POINTERS (never protocol content), and a
/// private on-device journal.
class JourneyScreen extends StatelessWidget {
  final SocialDeps deps;
  const JourneyScreen({super.key, required this.deps});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer journey'),
        actions: [
          HelpButton(
            screenKey: 'journey',
            brand: deps.brand,
            services: deps.m2,
            db: deps.db,
            share: deps.share,
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: deps.store,
        builder: (context, _) {
          final now = DateTime.now();
          final customers = deps.store.sortedCustomers(now);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Your customers\' first 30 days: a day counter, '
                'friendly check-ins on days 3, 7 and 30, and a reorder '
                'nudge on day 25. Check-in messages are drafts — you '
                'send them yourself.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _addCustomer(context),
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Add a customer'),
              ),
              const SizedBox(height: 8),
              if (customers.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.route_outlined),
                    title: Text('No customers on a journey yet'),
                    subtitle: Text(
                      'When someone buys their first order, add them '
                      'here with the day they started.',
                    ),
                  ),
                ),
              for (final c in customers)
                _CustomerCard(deps: deps, customer: c, now: now),
              const SizedBox(height: 8),
              _PlacementPointersCard(deps: deps),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addCustomer(BuildContext context) async {
    final nameController = TextEditingController();
    KnowledgeEntry? product;
    var startDate = DateTime.now();
    final products = deps.db.byTopic('products');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Add a customer'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Customer name',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<KnowledgeEntry?>(
                  value: product,
                  decoration: const InputDecoration(
                    labelText: 'What they started with (optional)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<KnowledgeEntry?>(
                      value: null,
                      child: Text('Not sure / several things'),
                    ),
                    ...products.map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(p.title,
                              overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (v) => setDialog(() => product = v),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text('Started: ${formatWhen(startDate)}'),
                  subtitle: const Text('Day 1 is the start date.'),
                  trailing: TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: startDate,
                        firstDate: DateTime.now()
                            .subtract(const Duration(days: 365)),
                        lastDate: DateTime.now()
                            .add(const Duration(days: 30)),
                      );
                      if (picked != null) {
                        setDialog(() => startDate = picked);
                      }
                    },
                    child: const Text('Change'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final name = nameController.text.trim();
    if (name.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('A name is needed — nothing was added.')));
      }
      return;
    }
    await deps.store.addCustomer(
      name: name,
      productId: product?.id,
      productTitle: product?.title ?? '',
      startDate: startDate,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name added — day 1 starts their journey.')));
    }
  }
}

/// Official general usage entries + the pointer framing. Pointers
/// only — detailed placement guidance lives in the group (§3/§4).
class _PlacementPointersCard extends StatelessWidget {
  final SocialDeps deps;
  const _PlacementPointersCard({required this.deps});

  @override
  Widget build(BuildContext context) {
    final pointers = PlacementPointers.fromDb(deps.db);
    return Card(
      color: LwColors.tint,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Placement reminders — the official basics',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            for (final e in pointers.usageEntries.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.push_pin_outlined, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${e.title}: '
                        '${e.body.split(RegExp(r'(?<=[.!?])\s+')).first}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(),
            const Text(
              PlacementPointers.pointerLine,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  final SocialDeps deps;
  final Customer customer;
  final DateTime now;
  const _CustomerCard({
    required this.deps,
    required this.customer,
    required this.now,
  });

  void _feedback(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final day = journeyDay(c, now);
    final due = dueCheckIns(c, now);
    final reorder = reorderDue(c, now);
    final store = deps.store;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(c.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Chip(
                  label: Text(
                    day == 0
                        ? 'Starts ${formatWhen(c.startDate)}'
                        : day > kJourneyDays
                            ? 'Day $day (past day 30)'
                            : 'Day $day of $kJourneyDays',
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: LwColors.tint,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (c.productTitle.isNotEmpty)
              Text('Started with: ${c.productTitle}',
                  style: const TextStyle(fontSize: 13)),
            Text('Started ${formatWhen(c.startDate)}',
                style: const TextStyle(fontSize: 13)),
            if (reorder)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Chip(
                  label: Text('Reorder due — counted on the Today card',
                      style: TextStyle(fontSize: 12)),
                  backgroundColor: Color(0xFFFFF3E0),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            for (final m in due)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Chip(
                  label: Text('Day $m check-in due',
                      style: const TextStyle(fontSize: 12)),
                  backgroundColor: const Color(0xFFFFF3E0),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            const SizedBox(height: 8),
            // Timeline.
            for (final ms in journeyTimeline())
              _TimelineRow(
                milestone: ms,
                currentDay: day,
                handedOff: c.checkInsHandedOff.contains(ms.day),
                done: c.checkInsDone.contains(ms.day),
                reordered: c.reordered,
              ),
            const Divider(),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final m in kCheckInDays)
                  if (day >= m &&
                      !c.checkInsDone.contains(m) &&
                      !c.checkInsHandedOff.contains(m))
                    FilledButton.icon(
                      onPressed: () => _draftCheckIn(context, m),
                      icon: const Icon(Icons.chat_outlined, size: 16),
                      label: Text('Draft day $m check-in'),
                    ),
                for (final m in c.checkInsHandedOff)
                  if (!c.checkInsDone.contains(m))
                    OutlinedButton.icon(
                      onPressed: () async {
                        await store.markCheckInDone(c, m);
                        if (context.mounted) {
                          _feedback(context,
                              'Day $m check-in marked done.');
                        }
                      },
                      icon: const Icon(Icons.done_all, size: 16),
                      label: Text('Mark day $m check-in done'),
                    ),
                if (reorder)
                  FilledButton.icon(
                    onPressed: () => _draftCheckIn(context, kReorderDay),
                    icon: const Icon(Icons.autorenew_outlined, size: 16),
                    label: const Text('Draft reorder nudge'),
                  ),
                if (reorder)
                  OutlinedButton.icon(
                    onPressed: () async {
                      await store.markReordered(c);
                      if (context.mounted) {
                        _feedback(context,
                            '${c.name} marked reordered — the nudge clears.');
                      }
                    },
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Mark reordered'),
                  ),
                if (c.reordered)
                  OutlinedButton.icon(
                    onPressed: () async {
                      await store.unmarkReordered(c);
                      if (context.mounted) {
                        _feedback(context, 'Reorder mark removed.');
                      }
                    },
                    icon: const Icon(Icons.undo, size: 16),
                    label: const Text('Reordered ✓ (tap to undo)'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _journal(context),
                  icon: const Icon(Icons.lock_outline, size: 16),
                  label: Text('Journal (${c.journal.length})'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await store.deleteCustomer(c);
                    if (context.mounted) {
                      _feedback(context, '${c.name} removed.');
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Check-in draft flow: compose from playbook/faq content -> show
  /// with its compliance scan -> Copy / Share handoff -> record the
  /// handoff honestly ("handed off", never "sent").
  Future<void> _draftCheckIn(BuildContext context, int day) async {
    final store = deps.store;
    final text = day == kReorderDay
        ? composeReorderDraft(customer: customer, db: deps.db)
        : composeCheckInDraft(customer: customer, day: day, db: deps.db);
    final report = scanJourneyDraft(text);
    final controller = TextEditingController(text: text);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(day == kReorderDay
            ? 'Reorder nudge for ${customer.name}'
            : 'Day $day check-in for ${customer.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLines: 7,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Your message draft',
                ),
              ),
              const SizedBox(height: 8),
              ComplianceResultsView(
                report: report,
                guide: ComplianceGuide.fromDb(deps.db.entries),
              ),
              const SizedBox(height: 4),
              const Text(
                'You send this yourself, from your own account. '
                'Copy or share it, then it is recorded here as handed '
                'off — never as "sent" by the app.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Not now'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop('copy'),
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('share'),
            child: const Text('Share…'),
          ),
        ],
      ),
    );
    if (action == null || !context.mounted) return;
    var handedOff = false;
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: controller.text));
      handedOff = true;
    } else if (action == 'share') {
      handedOff = await deps.share.shareText(controller.text);
    }
    if (handedOff && day != kReorderDay) {
      await store.markCheckInHandedOff(customer, day);
    }
    if (!context.mounted) return;
    _feedback(
      context,
      handedOff
          ? (action == 'copy'
              ? 'Copied — paste it and send it yourself. Recorded as handed off.'
              : 'Share sheet opened. Recorded as handed off — you send it yourself.')
          : 'The handoff did not happen, so nothing was recorded.',
    );
  }

  /// Private journal: per-customer, per-day notes, on-device only.
  Future<void> _journal(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _JournalSheet(deps: deps, customer: customer),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final JourneyMilestone milestone;
  final int currentDay;
  final bool handedOff;
  final bool done;
  final bool reordered;
  const _TimelineRow({
    required this.milestone,
    required this.currentDay,
    required this.handedOff,
    required this.done,
    required this.reordered,
  });

  @override
  Widget build(BuildContext context) {
    final reached = currentDay >= milestone.day;
    final isReorder = milestone.kind == 'reorder';
    final complete = done ||
        handedOff ||
        (isReorder && reordered);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        complete
            ? Icons.check_circle
            : reached
                ? Icons.radio_button_checked
                : Icons.circle_outlined,
        size: 20,
        color: complete
            ? Colors.green
            : reached
                ? LwColors.primary
                : Colors.grey,
      ),
      title: Text(
        milestone.label,
        style: TextStyle(
          fontWeight: reached ? FontWeight.w600 : null,
          color: reached ? null : Colors.grey,
        ),
      ),
      subtitle: Text(
        done
            ? 'Marked done'
            : handedOff
                ? 'Draft handed off (you sent it yourself)'
                : isReorder && reordered
                    ? 'Reordered'
                    : milestone.detail,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

class _JournalSheet extends StatefulWidget {
  final SocialDeps deps;
  final Customer customer;
  const _JournalSheet({required this.deps, required this.customer});

  @override
  State<_JournalSheet> createState() => _JournalSheetState();
}

class _JournalSheetState extends State<_JournalSheet> {
  final _noteController = TextEditingController();
  int _day = 1;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.deps.store;
    final c = widget.customer;
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final entries = store.journalFor(c);
        final currentDay = journeyDay(c, DateTime.now());
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Journal — ${c.name}',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Card(
                  color: Color(0xFFECF5FA),
                  child: ListTile(
                    leading: Icon(Icons.lock_outline),
                    title: Text('Private — only on this device'),
                    subtitle: Text(
                      'Journal notes are never synced, never shared, '
                      'and never leave this phone. They are your own '
                      'notes about how things are going — keep them '
                      'about routines and life, in your customer\'s '
                      'own words.',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _day.clamp(1, 999),
                        decoration: const InputDecoration(
                          labelText: 'Journey day',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (var d = 1; d <= (currentDay > 30 ? currentDay : 30); d++)
                            DropdownMenuItem(value: d, child: Text('Day $d')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _day = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Note for day $_day',
                    hintText: 'For example: said mornings feel easier',
                    border: const OutlineInputBorder(),
                    suffixIcon: DictateButton(
                      services: widget.deps.m2,
                      onText: (t) =>
                          setState(() => _noteController.text = t),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () async {
                    final text = _noteController.text.trim();
                    if (text.isEmpty) return;
                    await store.addJournalEntry(c, _day, text);
                    _noteController.clear();
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add note'),
                ),
                const SizedBox(height: 12),
                if (entries.isEmpty)
                  const Text('No notes yet.')
                else
                  for (final e in entries)
                    Card(
                      child: ListTile(
                        leading: Chip(label: Text('Day ${e.day}')),
                        title: Text(e.text),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete this note',
                          onPressed: () async {
                            await store.deleteJournalEntry(c, e);
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}
