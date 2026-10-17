import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/entry.dart';
import '../models/social.dart';
import '../services/compliance.dart';
import '../services/compliance_guide.dart';
import '../services/cross_post.dart';
import '../services/post_generator.dart';
import '../theme.dart';
import '../widgets/social_widgets.dart';
import 'guide_screen.dart';
import 'settings_about.dart' show PrefKeys;

/// Posts (SPEC §7.1): curiosity-post generator + draft/queue/approval.
///
/// HONEST STATES ONLY (SPEC §7.11): nothing auto-sends, ever. A queued
/// post gets an inexact OS reminder; at the due time the user taps
/// "Post now" and shares it THEMSELVES via the share sheet or copy.
/// The state after that is "Handed off" or "Copied" — never "Posted".
class PostsScreen extends StatefulWidget {
  final SocialDeps deps;

  /// When opened from the calendar suggestion slot, the generator is
  /// pre-filled to queue for this time.
  final DateTime? prefillWhen;

  /// When opened from a reminder tap / calendar item, scroll intent:
  /// the queue tab opens first.
  final bool openQueueFirst;
  const PostsScreen({
    super.key,
    required this.deps,
    this.prefillWhen,
    this.openQueueFirst = false,
  });

  @override
  State<PostsScreen> createState() => _PostsScreenState();
}

class _PostsScreenState extends State<PostsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.openQueueFirst ? 1 : 0,
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Posts'),
        actions: [HelpButton(screenKey: 'posts', brand: widget.deps.brand, services: widget.deps.m2, db: widget.deps.db, share: widget.deps.share)],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.auto_awesome_outlined), text: 'New post'),
            Tab(icon: Icon(Icons.schedule_outlined), text: 'Queue'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _GeneratorTab(deps: widget.deps, prefillWhen: widget.prefillWhen),
          _QueueTab(deps: widget.deps),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Generator tab
// ---------------------------------------------------------------------------

class _GeneratorTab extends StatefulWidget {
  final SocialDeps deps;
  final DateTime? prefillWhen;
  const _GeneratorTab({required this.deps, this.prefillWhen});

  @override
  State<_GeneratorTab> createState() => _GeneratorTabState();
}

class _GeneratorTabState extends State<_GeneratorTab> {
  late final PostGenerator _generator = PostGenerator(widget.deps.db);
  late final ComplianceGuide _guide =
      ComplianceGuide.fromDb(widget.deps.db.entries);
  final _textController = TextEditingController();
  KnowledgeEntry? _template;
  KnowledgeEntry? _product;
  String? _focus;
  int _variant = 0;
  PostDraft? _draft;
  bool _reminderWasSet = true;
  PostDestination _defaultDestination = PostDestination.personalProfile;

  List<KnowledgeEntry> get _products => widget.deps.db.byTopic('products');

  @override
  void initState() {
    super.initState();
    final templates = _generator.templates;
    if (templates.isNotEmpty) _template = templates.first;
    _compose();
    _loadDefaultDestination();
  }

  /// The per-user default destination from Settings — each new draft
  /// starts headed there; the queue dialog can still change it per post.
  Future<void> _loadDefaultDestination() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(PrefKeys.defaultDestination);
      if (raw != null && mounted) {
        setState(() =>
            _defaultDestination = PostDestination.fromName(raw));
      }
    } catch (_) {
      // Personal profile default applies.
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _compose() {
    final template = _template;
    if (template == null) return;
    final text = _generator.compose(
      template: template,
      product: _product,
      focus: _focus,
      variant: _variant,
    );
    _textController.text = text;
    // A fresh composition replaces the working draft.
    _draft = null;
  }

  ComplianceReport get _report =>
      const ComplianceScanner().scan(_textController.text);

  void _feedback(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<PostDraft> _ensureDraft() async {
    final existing = _draft;
    if (existing != null) {
      if (existing.text != _textController.text) {
        await widget.deps.store.updatePostText(existing, _textController.text);
      }
      return existing;
    }
    final store = widget.deps.store;
    final draft = PostDraft(
      id: store.newId('post'),
      text: _textController.text,
      productId: _product?.id,
      productTitle: _product?.title,
      templateId: _template?.id,
      destination: _defaultDestination,
    );
    await store.addPost(draft);
    _draft = draft;
    return draft;
  }

  Future<void> _approve() async {
    if (_textController.text.trim().isEmpty) {
      _feedback('Write or generate a post first.');
      return;
    }
    final draft = await _ensureDraft();
    await widget.deps.store.approvePost(draft);
    if (!mounted) return;
    setState(() {});
    _feedback(_report.isClean
        ? 'Approved. Now pick a time in the Queue step below, or open '
            'the Queue tab.'
        : 'Approved — but it has compliance flags. You will need to fix '
            'them, or override on purpose, before it can be queued.');
  }

  /// The full queue flow from the generator: approve (if needed) ->
  /// compliance gate -> pick time + destination -> queue + reminder.
  Future<void> _queueFlow() async {
    if (_textController.text.trim().isEmpty) {
      _feedback('Write or generate a post first.');
      return;
    }
    final store = widget.deps.store;
    final draft = await _ensureDraft();
    if (draft.status == PostStatus.draft) {
      await store.approvePost(draft);
    }
    if (!mounted) return;
    final report = store.scanPost(draft);
    if (report.hasHits && !draft.complianceOverride) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('This post has compliance flags'),
          content: SingleChildScrollView(
            child: ComplianceResultsView(report: report, guide: _guide),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Go back and fix it'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Override — I have read the flags'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
      await store.recordPostOverride(draft, report);
    }
    if (!mounted) return;
    final when = widget.prefillWhen ??
        await pickDateTime(context,
            initial: DateTime.now().add(const Duration(hours: 2)));
    if (when == null || !mounted) return;
    var destination = draft.destination;
    final picked = await showDialog<PostDestination>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Where will this post go?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(kDestinationExplainer),
            const SizedBox(height: 12),
            RadioListTile<PostDestination>(
              value: PostDestination.facebookPage,
              groupValue: destination,
              title: const Text('Facebook Page'),
              onChanged: (v) => Navigator.of(ctx).pop(v),
            ),
            RadioListTile<PostDestination>(
              value: PostDestination.personalProfile,
              groupValue: destination,
              title: const Text('Personal profile'),
              onChanged: (v) => Navigator.of(ctx).pop(v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (picked == null) return;
    destination = picked;
    final result = await store.queuePost(draft,
        when: when, destination: destination);
    if (!mounted) return;
    setState(() => _reminderWasSet = result.reminderScheduled);
    _feedback(result.reminderScheduled
        ? 'Queued. Reminder set for ${formatWhen(when)} (approximate). '
            'At that time, open the Queue and tap "Post now" — you '
            'share it yourself.'
        : 'Queued for ${formatWhen(when)}. A phone reminder could not '
            'be set, so check the Queue or Today card at that time — '
            'you share it yourself from there.');
  }

  @override
  Widget build(BuildContext context) {
    final templates = _generator.templates;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'The app writes a curiosity post in the playbook\'s '
          'question-led style — it asks a genuine everyday question and '
          'lets the answers start the conversation. The product is '
          'never pitched in the post itself; picking one just steers '
          'the topic. Nothing is ever sent automatically: you approve '
          'every post, and you share it yourself.',
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<KnowledgeEntry>(
          value: _template,
          decoration: const InputDecoration(
            labelText: 'Post style (playbook template)',
            border: OutlineInputBorder(),
          ),
          items: templates
              .map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(t.title.replaceFirst(
                        RegExp(r'^Original template \d+ - '), '')),
                  ))
              .toList(),
          onChanged: (v) {
            setState(() {
              _template = v;
              _compose();
            });
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<KnowledgeEntry?>(
          value: _product,
          decoration: const InputDecoration(
            labelText: 'Steer the topic with a product (optional)',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<KnowledgeEntry?>(
              value: null,
              child: Text('No product — general topic'),
            ),
            ..._products.map((p) => DropdownMenuItem(
                  value: p,
                  child: Text(p.title, overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: (v) {
            setState(() {
              _product = v;
              _focus = null;
              _compose();
            });
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          value: _focus,
          decoration: const InputDecoration(
            labelText: 'Question topic (optional)',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Let the style/product decide'),
            ),
            ...kFocusTopics.map((f) => DropdownMenuItem(
                  value: f,
                  child: Text(f[0].toUpperCase() + f.substring(1)),
                )),
          ],
          onChanged: (v) {
            setState(() {
              _focus = v;
              _compose();
            });
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _textController,
          maxLines: 6,
          minLines: 3,
          decoration: const InputDecoration(
            labelText: 'Your post draft',
            hintText: 'Your curiosity post…',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _variant++;
                  _compose();
                });
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Another version'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final edited = await _showComplianceDialog(context);
                if (edited) setState(() {});
              },
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Check compliance'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ComplianceResultsView(report: _report, guide: _guide),
        if (_draft?.complianceOverride == true) ...[
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFFFFF3E0),
            child: ListTile(
              leading: const Icon(Icons.history_edu_outlined),
              title: const Text('Compliance override recorded'),
              subtitle: Text(
                'You acknowledged these flags on purpose: '
                '${_draft!.overrideAcknowledgedFlags.join('; ')}',
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _approve,
              icon: const Icon(Icons.thumb_up_outlined, size: 18),
              label: const Text('Approve draft'),
            ),
            FilledButton.icon(
              onPressed: _queueFlow,
              icon: const Icon(Icons.schedule, size: 18),
              label: const Text('Approve & set reminder…'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _draft == null
              ? 'Status: not saved yet — approving saves the draft.'
              : 'Status: ${_draft!.status.label(scheduledFor: _draft!.scheduledFor)}',
          style: const TextStyle(fontSize: 12),
        ),
        if (!_reminderWasSet)
          const Text(
            'Note: the last reminder could not be set with the phone '
            'system. The queue and Today card still track the post.',
            style: TextStyle(fontSize: 12),
          ),
      ],
    );
  }

  /// "Check" dialog: same scanner + guide as the standalone checker.
  /// Returns true when the text was edited inside (it cannot be —
  /// kept simple: the dialog is read-only guidance).
  Future<bool> _showComplianceDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Compliance check'),
        content: SingleChildScrollView(
          child: ComplianceResultsView(report: _report, guide: _guide),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    return false;
  }
}

// ---------------------------------------------------------------------------
// Queue tab
// ---------------------------------------------------------------------------

class _QueueTab extends StatelessWidget {
  final SocialDeps deps;
  const _QueueTab({required this.deps});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: deps.store,
      builder: (context, _) {
        final store = deps.store;
        final now = DateTime.now();
        final due = store.duePosts(now);
        final posts = [...store.posts]
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Your post queue. A queued post is NOT posted — the app '
              'reminds you around the time you picked, and you share it '
              'yourself with "Post now". Statuses say exactly what has '
              'happened so far.',
            ),
            if (due.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                color: LwColors.tint,
                child: ListTile(
                  leading: const Icon(Icons.notifications_active_outlined,
                      color: LwColors.primary),
                  title: Text('${due.length} post(s) ready to share'),
                  subtitle: const Text(
                      'Their reminder time has arrived — use "Post now" '
                      'on each one below.'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (posts.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.inbox_outlined),
                  title: Text('Nothing here yet'),
                  subtitle: Text(
                      'Draft a post in the "New post" tab and it will '
                      'appear here once you approve it.'),
                ),
              ),
            for (final post in posts) _QueueItem(deps: deps, post: post),
          ],
        );
      },
    );
  }
}

class _QueueItem extends StatelessWidget {
  final SocialDeps deps;
  final PostDraft post;
  const _QueueItem({required this.deps, required this.post});

  void _feedback(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _postNow(BuildContext context) async {
    final opened = await deps.share.shareText(post.text);
    if (!context.mounted) return;
    if (opened) {
      await deps.store.markHandedOff(post, copied: false);
      if (!context.mounted) return;
      _feedback(context,
          'Share sheet opened. You choose where it goes — the app has '
          'not posted anything for you.');
    } else {
      _feedback(context,
          'The share sheet could not open. Use Copy instead.');
    }
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: post.text));
    await deps.store.markHandedOff(post, copied: true);
    if (!context.mounted) return;
    _feedback(context,
        'Copied. Paste it into Facebook yourself when you are ready.');
  }

  Future<void> _reschedule(BuildContext context) async {
    final when = await pickDateTime(context, initial: post.scheduledFor);
    if (when == null || !context.mounted) return;
    final ok = await deps.store.reschedulePost(post, when);
    if (!context.mounted) return;
    _feedback(
        context,
        ok
            ? 'Reminder moved to ${formatWhen(when)} (approximate).'
            : 'That post cannot be rescheduled from its current state.');
  }

  /// Cross-posting (M4): format this post for [platform], show the
  /// variant with its own compliance scan, and hand it to the share
  /// sheet. The handoff is recorded honestly — never as "posted".
  Future<void> _shareVariant(
      BuildContext context, SharePlatform platform) async {
    const formatter = CrossPostFormatter();
    final variant = formatter.format(platform, post.text);
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${platform.label} version'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(variant.text),
              const SizedBox(height: 8),
              Text(
                '${variant.charCount} characters'
                '${variant.guidance.isEmpty ? '' : ' — ${variant.guidance}'}',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              ComplianceResultsView(
                report: variant.report,
                guide: ComplianceGuide.fromDb(deps.db.entries),
              ),
              const SizedBox(height: 4),
              const Text(
                'Sharing opens the share sheet with this text — you '
                'finish the post in the app yourself. Nothing is '
                'posted by this app.',
                style: TextStyle(fontSize: 12),
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
            child: const Text('Open share sheet'),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;
    final opened = await deps.share.shareText(variant.text);
    if (!context.mounted) return;
    if (opened) {
      await deps.store.markPlatformHandoff(post, platform);
      if (!context.mounted) return;
      _feedback(context,
          'Share sheet opened for ${platform.label}. You finish and '
          'post it there yourself.');
    } else {
      _feedback(context, 'The share sheet could not open.');
    }
  }

  Future<void> _queueExisting(BuildContext context) async {
    final store = deps.store;
    final report = store.scanPost(post);
    if (report.hasHits && !post.complianceOverride) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('This post has compliance flags'),
          content: SingleChildScrollView(
            child: ComplianceResultsView(
              report: report,
              guide: ComplianceGuide.fromDb(deps.db.entries),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Go back and fix it'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Override — I have read the flags'),
            ),
          ],
        ),
      );
      if (proceed != true || !context.mounted) return;
      await store.recordPostOverride(post, report);
      if (!context.mounted) return;
    }
    final when = await pickDateTime(context,
        initial: DateTime.now().add(const Duration(hours: 2)));
    if (when == null || !context.mounted) return;
    final result = await store.queuePost(post,
        when: when, destination: post.destination);
    if (!context.mounted) return;
    _feedback(
        context,
        result.blockedBy != null
            ? 'Still flagged — fix the wording or override on purpose '
                'before queueing.'
            : result.reminderScheduled
                ? 'Reminder set for ${formatWhen(when)} (approximate).'
                : 'Queued for ${formatWhen(when)}. A phone reminder '
                    'could not be set; the Today card will show it.');
  }

  @override
  Widget build(BuildContext context) {
    final store = deps.store;
    final report = store.scanPost(post);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(
                    post.status.label(scheduledFor: post.scheduledFor),
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: LwColors.tint,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                Chip(
                  label: Text(post.destination.label,
                      style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                ),
                if (post.complianceOverride)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Chip(
                      label: Text('Override recorded',
                          style: TextStyle(fontSize: 12)),
                      backgroundColor: Color(0xFFFFF3E0),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(post.text),
            if (report.hasHits)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Compliance flags: '
                  '${report.hits.map((h) => '"${h.term}"').join(', ')}',
                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (post.status == PostStatus.draft)
                  FilledButton.icon(
                    onPressed: () async {
                      await store.approvePost(post);
                      if (context.mounted) {
                        _feedback(context, 'Approved.');
                      }
                    },
                    icon: const Icon(Icons.thumb_up_outlined, size: 16),
                    label: const Text('Approve'),
                  ),
                if (post.status == PostStatus.approved)
                  FilledButton.icon(
                    onPressed: () => _queueExisting(context),
                    icon: const Icon(Icons.schedule, size: 16),
                    label: const Text('Set reminder…'),
                  ),
                if (post.status == PostStatus.queued ||
                    post.status == PostStatus.handedOff ||
                    post.status == PostStatus.copied) ...[
                  FilledButton.icon(
                    onPressed: () => _postNow(context),
                    icon: const Icon(Icons.share_outlined, size: 16),
                    label: const Text('Post now'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _copy(context),
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    label: const Text('Copy'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _reschedule(context),
                    icon: const Icon(Icons.update, size: 16),
                    label: const Text('Reschedule'),
                  ),
                ],
                if (post.status != PostStatus.cancelled)
                  TextButton.icon(
                    onPressed: () async {
                      await store.cancelPost(post);
                      if (context.mounted) {
                        _feedback(context,
                            'Cancelled — no reminder will fire for it.');
                      }
                    },
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Cancel'),
                  ),
                TextButton.icon(
                  onPressed: () async {
                    await store.deletePost(post);
                    if (context.mounted) {
                      _feedback(context, 'Deleted from this device.');
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Delete'),
                ),
              ],
            ),
            const Text(
              '"Post now" opens your phone\'s share sheet — you pick '
              'Facebook and post it yourself. The app never posts for '
              'you.',
              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
            ),
            if (post.status == PostStatus.approved ||
                post.status == PostStatus.queued ||
                post.status == PostStatus.handedOff ||
                post.status == PostStatus.copied) ...[
              const Divider(),
              const Text(
                'Share to… (formatted for each platform)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final platform in SharePlatform.values)
                    OutlinedButton.icon(
                      onPressed: () => _shareVariant(context, platform),
                      icon: Icon(
                        platform == SharePlatform.facebook
                            ? Icons.facebook
                            : platform == SharePlatform.instagram
                                ? Icons.camera_alt_outlined
                                : Icons.alternate_email_outlined,
                        size: 16,
                      ),
                      label: Text(platform.label),
                    ),
                ],
              ),
              for (final entry in post.platformHandoffs.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    entry.value,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
