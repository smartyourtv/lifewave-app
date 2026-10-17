import 'package:flutter/material.dart';

import '../services/brand_assets.dart';
import '../services/compliance.dart';
import '../services/compliance_guide.dart';
import '../services/knowledge_db.dart';
import '../services/m2_services.dart';
import '../services/share_service.dart';
import '../services/social_store.dart';
import '../theme.dart';

/// Everything the M3 screens need, bundled so navigation stays simple.
/// Created once in main and passed down (same pattern as M2Services).
class SocialDeps {
  final KnowledgeDb db;
  final BrandAssets brand;
  final M2Services m2;
  final SocialStore store;
  final ShareGateway share;
  const SocialDeps({
    required this.db,
    required this.brand,
    required this.m2,
    required this.store,
    required this.share,
  });
}

/// Mic button using the M2 SpeechInput service (tap-to-talk, initialize-
/// once). On failure it shows the service's plain-language message —
/// typing always remains available (audit §1 denial path).
class DictateButton extends StatelessWidget {
  final M2Services services;
  final ValueChanged<String> onText;
  final String tooltip;
  const DictateButton({
    super.key,
    required this.services,
    required this.onText,
    this.tooltip = 'Dictate by voice instead of typing',
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: const Icon(Icons.mic_outlined),
      onPressed: () async {
        final result = await services.speechInput.listenOnce();
        if (!context.mounted) return;
        if (result.ok) {
          onText(result.text);
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(result.message)));
        }
      },
    );
  }
}

/// Compliance results, shared by the checker screen, the post
/// generator and reply drafts (SPEC §7.9: one service, many doors).
/// Shows the flagged phrases grouped by category with plain-language
/// "why" + a suggested compliant direction. Never rewrites the text.
class ComplianceResultsView extends StatelessWidget {
  final ComplianceReport report;
  final ComplianceGuide guide;
  const ComplianceResultsView({
    super.key,
    required this.report,
    required this.guide,
  });

  @override
  Widget build(BuildContext context) {
    if (report.isClean) {
      return const Card(
        color: LwColors.tint,
        child: ListTile(
          leading: Icon(Icons.check_circle, color: Colors.green),
          title: Text('No problems found'),
          subtitle: Text(
            'This text passed the compliance check: no medical claims, '
            'restricted terms, promised results or income claims were '
            'found. You still make the final call before sharing '
            'anything.',
          ),
        ),
      );
    }
    final grouped = guide.groupByCategory(report);
    final explanations = {
      for (final e in guide.explain(report)) e.hit: e,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: const Color(0xFFFFF3E0),
          child: ListTile(
            leading: const Icon(Icons.warning_amber, color: Colors.orange),
            title: Text('${report.hits.length} thing(s) to fix'),
            subtitle: const Text(
              'The checker flags wording — it never rewrites your text. '
              'Fix the wording yourself, or (posts/replies only) '
              'override on purpose with the flags acknowledged.',
            ),
          ),
        ),
        for (final entry in grouped.entries) ...[
          const SizedBox(height: 8),
          Text(
            entry.value.first.categoryLabel,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          for (final hit in entry.value)
            Card(
              child: ListTile(
                leading: const Icon(Icons.flag_outlined,
                    color: Colors.orange),
                title: Text('“${hit.term}”'),
                subtitle: Text(
                  '${explanations[hit]?.why ?? ''}\n'
                  '${explanations[hit]?.suggestion ?? ''}',
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Picks a date then a time; returns the combined local DateTime or
/// null when the user cancels either step.
Future<DateTime?> pickDateTime(BuildContext context,
    {DateTime? initial}) async {
  final now = DateTime.now();
  final start = initial ?? now.add(const Duration(hours: 1));
  final date = await showDatePicker(
    context: context,
    initialDate: start,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: now.add(const Duration(days: 60)),
    helpText: 'Pick the day',
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(start),
    helpText: 'Pick the time (reminders are approximate)',
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// Plain-language explanation of the Page vs profile distinction,
/// shown wherever a destination is picked. v1 truth: with no account
/// connection, BOTH resolve to a reminder + one-tap handoff.
const String kDestinationExplainer =
    'Facebook Page posts can be truly scheduled ahead — but only once '
    'an account connection exists. This version has no account '
    'connection yet, so Page and Personal profile posts both work the '
    'same honest way for now: the app reminds you around the time you '
    'pick, and you share the post yourself in one tap. Personal profile '
    'posts can never be scheduled by any app — the reminder is the '
    'real mechanic there, not a placeholder.';
