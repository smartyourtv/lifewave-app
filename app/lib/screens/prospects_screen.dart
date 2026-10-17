import 'package:flutter/material.dart';

import '../services/emotion.dart';

import '../models/social.dart';
import '../widgets/social_widgets.dart';
import 'guide_screen.dart';

/// Prospect pipeline (SPEC §7.9 rider): Commented -> Invited ->
/// Joined group -> Customer, with a follow-up date per person so
/// nobody falls through. All of this lives on this device only — it
/// is never synced, shared or sent anywhere.
class ProspectsScreen extends StatelessWidget {
  final SocialDeps deps;
  const ProspectsScreen({super.key, required this.deps});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Prospects'), actions: [HelpButton(screenKey: 'prospects', brand: deps.brand, services: deps.m2, db: deps.db, share: deps.share, emotionLevel: EmotionLevel.warm)],),
      body: AnimatedBuilder(
        animation: deps.store,
        builder: (context, _) {
          final now = DateTime.now();
          final prospects = deps.store.sortedProspects(now);
          final dueCount =
              prospects.where((p) => p.isDueOn(now)).length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'The people you are talking with, and where each one '
                'is: commented on a post, invited, joined the learning '
                'group, or became a customer. Set a follow-up date so '
                'nobody falls through.',
              ),
              const SizedBox(height: 6),
              const Card(
                color: Color(0xFFECF5FA),
                child: ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('Private — stays on this device'),
                  subtitle: Text(
                    'This list is your own data. It is never synced, '
                    'uploaded or shared anywhere.',
                  ),
                ),
              ),
              if (dueCount > 0)
                Card(
                  color: const Color(0xFFFFF3E0),
                  child: ListTile(
                    leading: const Icon(Icons.flag_outlined,
                        color: Colors.orange),
                    title: Text('$dueCount follow-up(s) due'),
                    subtitle: const Text(
                        'These are the follow-ups counted on the Today '
                        'card.'),
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => _addProspect(context),
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Add a person'),
              ),
              const SizedBox(height: 8),
              if (prospects.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.people_outline),
                    title: Text('Nobody here yet'),
                    subtitle: Text(
                        'When someone comments on a post and you start '
                        'talking, add them here so the follow-up is '
                        'never forgotten.'),
                  ),
                ),
              for (final p in prospects)
                _ProspectCard(deps: deps, prospect: p, now: now),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addProspect(BuildContext context) async {
    final nameController = TextEditingController();
    final noteController = TextEditingController();
    DateTime? followUp;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add a person'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'Who are you talking with?',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  decoration: InputDecoration(
                    labelText: 'Note (optional)',
                    hintText: 'For example: asked about sleep posts',
                    border: const OutlineInputBorder(),
                    suffixIcon: DictateButton(
                      services: deps.m2,
                      onText: (t) => noteController.text = t,
                    ),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.flag_outlined),
                  title: Text(followUp == null
                      ? 'No follow-up date'
                      : 'Follow up: ${formatWhen(followUp!)}'),
                  trailing: TextButton(
                    onPressed: () async {
                      final picked = await pickDateTime(ctx);
                      if (picked != null) {
                        setDialogState(() => followUp = picked);
                      }
                    },
                    child: const Text('Set date'),
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
    await deps.store.addProspect(
      name: name,
      note: noteController.text.trim(),
      followUpDate: followUp,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name added at stage "Commented".')));
    }
  }
}

class _ProspectCard extends StatelessWidget {
  final SocialDeps deps;
  final Prospect prospect;
  final DateTime now;
  const _ProspectCard({
    required this.deps,
    required this.prospect,
    required this.now,
  });

  void _feedback(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final store = deps.store;
    final p = prospect;
    final due = p.isDueOn(now);
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
                  child: Text(p.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (due)
                  const Chip(
                    label: Text('Follow-up due',
                        style: TextStyle(fontSize: 12)),
                    backgroundColor: Color(0xFFFFF3E0),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (p.note.isNotEmpty) Text(p.note),
            const SizedBox(height: 8),
            // Stage stepper: every stage shown; tapping one moves them.
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final stage in ProspectStage.values)
                  ChoiceChip(
                    label: Text(stage.label, style: const TextStyle(fontSize: 12)),
                    selected: p.stage == stage,
                    onSelected: (_) async {
                      await store.setProspectStage(p, stage);
                      if (context.mounted) {
                        _feedback(context,
                            '${p.name} is now at "${stage.label}".');
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.flag_outlined,
                    size: 16, color: due ? Colors.orange : null),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    p.followUpDate == null
                        ? 'No follow-up date set'
                        : 'Follow up: ${formatWhen(p.followUpDate!)}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: due ? FontWeight.w700 : null),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (p.stage.next != null)
                  FilledButton.icon(
                    onPressed: () async {
                      await store.advanceProspect(p);
                      if (context.mounted) {
                        _feedback(context,
                            '${p.name} moved to "${p.stage.label}".');
                      }
                    },
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: Text('Move to ${p.stage.next!.label}'),
                  ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final when = await pickDateTime(context,
                        initial: p.followUpDate);
                    if (when == null) return;
                    await store.setFollowUp(p, when);
                    if (context.mounted) {
                      _feedback(context,
                          'Follow-up set for ${formatWhen(when)}.');
                    }
                  },
                  icon: const Icon(Icons.event_outlined, size: 16),
                  label: const Text('Set follow-up'),
                ),
                if (p.followUpDate != null) ...[
                  OutlinedButton.icon(
                    onPressed: () async {
                      await store.markFollowUpDone(p);
                      if (context.mounted) {
                        _feedback(context,
                            'Follow-up for ${p.name} marked done.');
                      }
                    },
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Done'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await store.snoozeFollowUp(p, days: 3);
                      if (context.mounted) {
                        _feedback(context,
                            'Follow-up moved 3 days later.');
                      }
                    },
                    icon: const Icon(Icons.snooze_outlined, size: 16),
                    label: const Text('Snooze 3 days'),
                  ),
                ],
                TextButton.icon(
                  onPressed: () async {
                    await store.deleteProspect(p);
                    if (context.mounted) {
                      _feedback(context, '${p.name} removed.');
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
}
