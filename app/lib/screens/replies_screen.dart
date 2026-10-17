import 'package:flutter/material.dart';

import '../services/emotion.dart';
import 'package:flutter/services.dart';

import '../models/social.dart';
import '../services/compliance.dart';
import '../services/compliance_guide.dart';
import '../services/post_generator.dart';
import '../services/translation_service.dart';
import '../theme.dart';
import '../widgets/social_widgets.dart';
import 'guide_screen.dart';

/// AI reply drafts (SPEC §7.2): paste a comment/message -> the app
/// drafts a reply from the database (brief answer + invite into
/// LW Team Learning) -> compliance scan -> you approve/edit -> Copy or
/// share-sheet handoff. You send it from your own Facebook — there is
/// no account connection and no silent send, ever.
class RepliesScreen extends StatefulWidget {
  final SocialDeps deps;
  const RepliesScreen({super.key, required this.deps});

  @override
  State<RepliesScreen> createState() => _RepliesScreenState();
}

class _RepliesScreenState extends State<RepliesScreen> {
  late final ReplyComposer _composer = ReplyComposer(widget.deps.db);
  late final ComplianceGuide _guide =
      ComplianceGuide.fromDb(widget.deps.db.entries);
  final _incomingController = TextEditingController();
  final _draftController = TextEditingController();
  ReplyDraft? _current;
  AppLanguage _replyLanguage = languageByCode('en');
  bool _busy = false;

  @override
  void dispose() {
    _incomingController.dispose();
    _draftController.dispose();
    super.dispose();
  }

  void _feedback(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  ComplianceReport get _report =>
      const ComplianceScanner().scan(_draftController.text);

  Future<void> _draftIt() async {
    final incoming = _incomingController.text.trim();
    if (incoming.isEmpty) {
      _feedback('Paste or dictate the comment first.');
      return;
    }
    final text = _composer.composeReply(incoming);
    final draft = ReplyDraft(
      id: widget.deps.store.newId('reply'),
      incomingText: incoming,
      draftText: text,
    );
    await widget.deps.store.addReply(draft);
    if (!mounted) return;
    setState(() {
      _current = draft;
      _draftController.text = text;
      _replyLanguage = languageByCode('en');
    });
  }

  /// Inserts a pre-approved quick template as the current draft.
  Future<void> _useTemplate(QuickReplyTemplate t, String incoming) async {
    final draft = ReplyDraft(
      id: widget.deps.store.newId('reply'),
      incomingText: incoming.isEmpty ? '(quick template)' : incoming,
      draftText: t.text,
    );
    await widget.deps.store.addReply(draft);
    if (!mounted) return;
    setState(() {
      _current = draft;
      _draftController.text = t.text;
    });
    _feedback('Template inserted. Edit it if you like, then copy or '
        'share it — you send it yourself.');
  }

  Future<void> _translateIncoming() async {
    final incoming = _incomingController.text.trim();
    if (incoming.isEmpty) {
      _feedback('Paste the comment first, then translate it.');
      return;
    }
    setState(() => _busy = true);
    final translation = widget.deps.m2.translation;
    final detected = await translation.detectLanguage(incoming);
    final from = detected == 'und' || detected.isEmpty ? 'es' : detected;
    final result = await translation.translateWithCascade(
      incoming,
      fromCode: from,
      toCode: 'en',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.usedOriginal) {
      _feedback(result.message);
    } else {
      _incomingController.text = result.text;
      _feedback('Translated into English so you can draft a reply. '
          'The original sender\'s words are replaced above.');
    }
  }

  /// Translates the DRAFT into the prospect's language and scans the
  /// FINAL-language text (SPEC §7.4) — the visible scan updates with it.
  Future<void> _translateDraft() async {
    final current = _current;
    if (current == null || _draftController.text.trim().isEmpty) {
      _feedback('Draft a reply first.');
      return;
    }
    if (_replyLanguage.code == current.languageCode) {
      _feedback('The draft is already in ${_replyLanguage.name}.');
      return;
    }
    setState(() => _busy = true);
    final result = await widget.deps.m2.translation.translateWithCascade(
      _draftController.text,
      fromCode: current.languageCode,
      toCode: _replyLanguage.code,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.usedOriginal) {
      _feedback(result.message);
      return;
    }
    current.languageCode = _replyLanguage.code;
    await widget.deps.store.updateReplyText(current, result.text);
    if (!mounted) return;
    setState(() => _draftController.text = result.text);
    _feedback('Draft translated into ${_replyLanguage.name}. The '
        'compliance check below now reads the translated text.');
  }

  Future<void> _saveEdits() async {
    final current = _current;
    if (current == null) return;
    await widget.deps.store.updateReplyText(current, _draftController.text);
    if (!mounted) return;
    setState(() {});
    _feedback('Draft saved on this device.');
  }

  /// Copy/share gate: flagged text needs a fix or an explicit override
  /// first — the same rule as posts.
  Future<bool> _gate() async {
    final current = _current;
    if (current == null) return false;
    if (_draftController.text != current.draftText) {
      await widget.deps.store.updateReplyText(current, _draftController.text);
    }
    final report = const ComplianceScanner().scan(_draftController.text);
    if (report.isClean || current.complianceOverride) return true;
    if (!mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('This reply has compliance flags'),
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
    if (proceed != true) return false;
    await widget.deps.store.recordReplyOverride(current, report);
    return true;
  }

  Future<void> _copy() async {
    if (!await _gate()) return;
    await Clipboard.setData(ClipboardData(text: _draftController.text));
    final current = _current;
    if (current != null) {
      await widget.deps.store.setReplyStatus(current, ReplyStatus.handled);
    }
    _feedback('Copied. Paste it into Facebook or Messenger yourself — '
        'the app does not send replies for you.');
    if (mounted) setState(() {});
  }

  Future<void> _share() async {
    if (!await _gate()) return;
    final opened = await widget.deps.share.shareText(_draftController.text);
    if (!mounted) return;
    if (opened) {
      final current = _current;
      if (current != null) {
        await widget.deps.store
            .setReplyStatus(current, ReplyStatus.handled);
      }
      _feedback('Share sheet opened — you choose where it goes and '
          'send it yourself.');
    } else {
      _feedback('The share sheet could not open. Use Copy instead.');
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.deps.store;
    final templates = store.approvedTemplates;
    return Scaffold(
      appBar: AppBar(title: const Text('Replies'), actions: [HelpButton(screenKey: 'replies', brand: widget.deps.brand, services: widget.deps.m2, db: widget.deps.db, share: widget.deps.share, emotionLevel: EmotionLevel.warm)],),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final waiting =
              store.replies.where((r) => r.status == ReplyStatus.waiting).toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Paste a comment or message someone sent you. The app '
                'drafts a short reply from the built-in answers and '
                'invites them into LW Team Learning. You approve, edit, '
                'then copy or share it — you send it from your own '
                'Facebook. Nothing is ever sent automatically.',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: null,
                decoration: const InputDecoration(
                  labelText: 'Or pick a common question',
                  hintText: 'Common questions people ask',
                  border: OutlineInputBorder(),
                ),
                items: widget.deps.db
                    .byTopic('faq')
                    .map((e) => DropdownMenuItem(
                          value: e.title,
                          child: Text(e.title,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _incomingController.text = v);
                  _draftIt();
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _incomingController,
                maxLines: 4,
                minLines: 2,
                decoration: InputDecoration(
                  labelText: 'What they wrote',
                  hintText: 'Paste their comment or message here…',
                  border: const OutlineInputBorder(),
                  suffixIcon: DictateButton(
                    services: widget.deps.m2,
                    onText: (t) =>
                        setState(() => _incomingController.text = t),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _translateIncoming,
                    icon: const Icon(Icons.translate, size: 18),
                    label: const Text('Translate what they wrote'),
                  ),
                  FilledButton.icon(
                    onPressed: _draftIt,
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: const Text('Draft a reply'),
                  ),
                ],
              ),
              if (templates.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Your approved quick replies',
                    style: Theme.of(context).textTheme.titleSmall),
                const Text(
                  'Templates you pre-approved in Settings. One tap '
                  'inserts one — you still send it yourself.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in templates)
                      ActionChip(
                        label: Text(t.title),
                        onPressed: () => _useTemplate(
                            t, _incomingController.text.trim()),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _draftController,
                maxLines: 6,
                minLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Your reply draft',
                  hintText: 'The drafted reply appears here — edit freely.',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<AppLanguage>(
                      value: _replyLanguage,
                      decoration: const InputDecoration(
                        labelText: 'Reply language',
                        border: OutlineInputBorder(),
                      ),
                      items: kAppLanguages
                          .map((l) => DropdownMenuItem(
                              value: l, child: Text(l.name)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _replyLanguage = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _translateDraft,
                    icon: const Icon(Icons.translate, size: 18),
                    label: const Text('Translate draft'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'The compliance check always reads the FINAL language '
                'of the reply — translation never gets a free pass.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              if (_draftController.text.isNotEmpty)
                ComplianceResultsView(report: _report, guide: _guide),
              if (_current?.complianceOverride == true)
                const Card(
                  color: Color(0xFFFFF3E0),
                  child: ListTile(
                    leading: Icon(Icons.history_edu_outlined),
                    title: Text('Compliance override recorded'),
                    subtitle: Text(
                        'You acknowledged this draft\'s flags on purpose.'),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _current == null ? null : _saveEdits,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save edits'),
                  ),
                  FilledButton.icon(
                    onPressed: _current == null ? null : _copy,
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: const Text('Copy reply'),
                  ),
                  FilledButton.icon(
                    onPressed: _current == null ? null : _share,
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Share…'),
                  ),
                ],
              ),
              const Divider(height: 32),
              Text('Replies waiting (${waiting.length})',
                  style: Theme.of(context).textTheme.titleMedium),
              const Text(
                'Drafts you made but have not copied, shared or '
                'dismissed yet. This is the count on the Today card.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              if (waiting.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.inbox_outlined),
                    title: Text('Nothing waiting'),
                    subtitle:
                        Text('Draft a reply above and it will wait here.'),
                  ),
                ),
              for (final r in waiting)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text(r.draftText,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('For: "${r.incomingText}"',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'open') {
                          setState(() {
                            _current = r;
                            _incomingController.text = r.incomingText;
                            _draftController.text = r.draftText;
                            _replyLanguage =
                                languageByCode(r.languageCode);
                          });
                        } else if (v == 'handled') {
                          await store.setReplyStatus(
                              r, ReplyStatus.handled);
                        } else if (v == 'dismiss') {
                          await store.setReplyStatus(
                              r, ReplyStatus.dismissed);
                        } else if (v == 'delete') {
                          await store.deleteReply(r);
                        }
                      },
                      itemBuilder: (ctx) => const [
                        PopupMenuItem(value: 'open', child: Text('Open')),
                        PopupMenuItem(
                            value: 'handled', child: Text('Mark handled')),
                        PopupMenuItem(
                            value: 'dismiss', child: Text('Dismiss')),
                        PopupMenuItem(
                            value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              const Card(
                color: LwColors.tint,
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('You send it yourself'),
                  subtitle: Text(
                    'This app has no Facebook account connection, so it '
                    'cannot read your comments or send replies for you. '
                    'It drafts; you paste and send from your own '
                    'account.',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
