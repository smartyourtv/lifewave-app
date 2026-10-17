import 'package:flutter/material.dart';

import '../models/social.dart';
import '../services/brand_assets.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Tabs in the bottom navigation.
enum AppTab { today, catalog, chat, more }

/// Home screen: branded header + the Today card (SPEC §7.8 item 7).
/// The Today rows read the REAL on-device stores (reply drafts, post
/// queue, prospect pipeline — and since M4, journey reorders: customers
/// on day 25+ who have not reordered). Every row is one tap to its
/// screen. The first-run welcome card was replaced by the first-run
/// TOUR in M4 (SPEC §7.6) — [showWelcomeCard] is retained for
/// compatibility but main no longer shows it.
class HomeScreen extends StatelessWidget {
  final BrandAssets brand;
  final String? displayName;
  final bool showWelcomeCard;
  final VoidCallback onDismissWelcome;
  final void Function(AppTab) onGoTab;
  final TodayCounts counts;
  final VoidCallback? onOpenReplies;
  final VoidCallback? onOpenPosts;
  final VoidCallback? onOpenProspects;
  final VoidCallback? onOpenJourney;
  final VoidCallback? onOpenDemo;
  final Widget? helpAction;

  /// M5: the dismissible update banner, when an update is available
  /// and not yet dismissed for that version (built by main).
  final Widget? updateBanner;

  const HomeScreen({
    super.key,
    required this.brand,
    required this.displayName,
    required this.showWelcomeCard,
    required this.onDismissWelcome,
    required this.onGoTab,
    this.counts = TodayCounts.zero,
    this.onOpenReplies,
    this.onOpenPosts,
    this.onOpenProspects,
    this.onOpenJourney,
    this.onOpenDemo,
    this.helpAction,
    this.updateBanner,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Branded header — official logo (§7.12 home/Today header).
            Card(
              color: LwColors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        LogoImage(assetPath: brand.logoAssetPath, height: 40),
                        const Spacer(),
                        if (helpAction != null) helpAction!,
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      displayName == null
                          ? 'Welcome to your LifeWave helper'
                          : 'Welcome back, $displayName',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text(
                      'Answers from the built-in database — works offline.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            if (updateBanner != null) ...[
              const SizedBox(height: 12),
              updateBanner!,
            ],
            if (showWelcomeCard) ...[
              const SizedBox(height: 12),
              Card(
                color: LwColors.tint,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'First time here?',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Ask a question in Chat, or browse the product '
                        'catalog. Every answer shows where it came from '
                        'and whether it is an official fact or a '
                        'distributor claim.',
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        AppInfo.independentToolLine,
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: onDismissWelcome,
                          child: const Text('Got it — hide this'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Today card — real counts from the M3 stores.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Your business at a glance. Tap a row to open it.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const Divider(),
                    _TodayRow(
                      icon: Icons.reply_outlined,
                      label: 'Replies waiting',
                      value: counts.repliesWaiting == 0
                          ? '0 — Nothing waiting'
                          : '${counts.repliesWaiting} waiting',
                      onTap: onOpenReplies,
                    ),
                    _TodayRow(
                      icon: Icons.schedule_outlined,
                      label: 'Posts scheduled',
                      value: counts.postsScheduled == 0
                          ? '0 — Nothing scheduled'
                          : '${counts.postsScheduled} scheduled',
                      onTap: onOpenPosts,
                    ),
                    _TodayRow(
                      icon: Icons.flag_outlined,
                      label: 'Follow-ups due',
                      value: counts.followUpsDue == 0
                          ? '0 — Nothing due'
                          : '${counts.followUpsDue} due',
                      onTap: onOpenProspects,
                    ),
                    _TodayRow(
                      icon: Icons.autorenew_outlined,
                      label: 'Reorders due',
                      value: counts.reordersDue == 0
                          ? '0 — Nothing due'
                          : '${counts.reordersDue} due',
                      onTap: onOpenJourney,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'From your Customer Journey: customers on day 25 '
                      'or later of their first 30 days who have not '
                      'reordered yet.',
                      style:
                          TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ),
            if (onOpenDemo != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onOpenDemo,
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Show me what you can do'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const Text(
                'A 60-second demo — the real features, with sample '
                'questions. Great for showing a friend.',
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 12),
            Text('Quick links', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _QuickLink(
              icon: Icons.chat_bubble_outline,
              title: 'Ask a question',
              subtitle: 'Chat answers from the built-in database',
              onTap: () => onGoTab(AppTab.chat),
            ),
            _QuickLink(
              icon: Icons.storefront_outlined,
              title: 'Browse products',
              subtitle: 'The full catalog, with official pictures',
              onTap: () => onGoTab(AppTab.catalog),
            ),
            if (onOpenPosts != null)
              _QuickLink(
                icon: Icons.auto_awesome_outlined,
                title: 'Write a curiosity post',
                subtitle: 'Playbook-style drafts, checked, queued by you',
                onTap: onOpenPosts!,
              ),
            if (onOpenReplies != null)
              _QuickLink(
                icon: Icons.reply_outlined,
                title: 'Draft a reply',
                subtitle: 'Brief answer + group invite — you send it',
                onTap: onOpenReplies!,
              ),
            if (onOpenProspects != null)
              _QuickLink(
                icon: Icons.people_outline,
                title: 'Prospects & follow-ups',
                subtitle: 'Your pipeline, private on this device',
                onTap: onOpenProspects!,
              ),
            if (onOpenJourney != null)
              _QuickLink(
                icon: Icons.route_outlined,
                title: 'Customer journey',
                subtitle: '30-day check-ins, journal and reorder nudges',
                onTap: onOpenJourney!,
              ),
            _QuickLink(
              icon: Icons.health_and_safety_outlined,
              title: 'Diagnostics',
              subtitle: 'Check the app is working — versions and self-tests',
              onTap: () => onGoTab(AppTab.more),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  const _TodayRow(
      {required this.icon, required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: LwColors.primary),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (onTap != null) const Icon(Icons.chevron_right, size: 18),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _QuickLink extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _QuickLink({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: LwColors.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
