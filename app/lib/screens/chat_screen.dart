import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/entry.dart';
import '../services/brand_assets.dart';
import '../services/cloud_escalation.dart';
import '../services/compliance.dart';
import '../services/emotion.dart';
import '../services/knowledge_db.dart';
import '../services/m2_services.dart';
import '../services/retrieval.dart';
import '../services/translation_service.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'catalog_screen.dart' show EntryDetailScreen;
import 'guide_screen.dart';

class _ChatMessage {
  final bool fromUser;
  final String? userText;
  final ComposedAnswer? answer;
  final String? noteText;
  String? translatedText;
  String? translationNote;
  List<ComplianceHit> translationHits = const [];
  _ChatMessage.user(this.userText)
      : fromUser = true,
        answer = null,
        noteText = null;
  _ChatMessage.answer(this.answer)
      : fromUser = false,
        userText = null,
        noteText = null;
  _ChatMessage.note(this.noteText)
      : fromUser = false,
        userText = null,
        answer = null;
}

/// Chat Q&A: on-device retrieval first, answers grounded in retrieved
/// entries with claim labels ALWAYS visible. No match => the honest
/// answer, never a fabrication. Cloud escalation is the M1 stub
/// interface (no network, no keys).
///
/// M2 additions: tap-to-talk questions (speech input service), spoken
/// answers via the single voice controller (markup parsed out of the
/// displayed text), and a Translate action per answer — compliance is
/// checked on the FINAL-LANGUAGE text and hits are shown, never
/// silently rewritten.
class ChatScreen extends StatefulWidget {
  final KnowledgeDb db;
  final BrandAssets brand;
  final CloudEscalation cloud;
  final M2Services? services; // optional so M1 widget tests still build it
  final EmotionLevel emotionLevel;
  final VoiceInfo? selectedVoice;
  final AppLanguage chatLanguage;
  const ChatScreen({
    super.key,
    required this.db,
    required this.brand,
    required this.cloud,
    this.services,
    this.emotionLevel = EmotionLevel.warm,
    this.selectedVoice,
    this.chatLanguage = const AppLanguage('es', 'Spanish'),
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<_ChatMessage> _messages = [];
  late final Retrieval _retrieval = Retrieval(widget.db.entries);
  int? _speakingIndex;
  bool _micBusy = false;
  bool _micExplained = false;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _ask() {
    final question = _controller.text.trim();
    if (question.isEmpty) return;
    _controller.clear();
    final results = _retrieval.search(question);
    final answer = composeAnswer(question, results);
    setState(() {
      _messages.add(_ChatMessage.user(question));
      _messages.add(_ChatMessage.answer(answer));
    });
    _scrollToEnd();
  }

  Future<void> _askCloud() async {
    String lastQuestion = '';
    for (final m in _messages) {
      if (m.fromUser && m.userText != null) lastQuestion = m.userText!;
    }
    final result = await widget.cloud.escalate(
      question: lastQuestion,
      retrievedEntries: const [],
    );
    if (!mounted) return;
    setState(() => _messages.add(_ChatMessage.note(result.message)));
    _scrollToEnd();
  }

  // --- M2: voice input -------------------------------------------------
  Future<void> _micAsk() async {
    final services = widget.services;
    if (services == null) return;
    if (!_micExplained) {
      _micExplained = true;
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ask by voice'),
          content: const Text(
            'Tap OK, then say your question out loud. The app listens '
            'using this device\'s speech feature and turns it into '
            'words here. If listening does not work on this device, '
            'you can always type instead.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('OK — listen'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    setState(() => _micBusy = true);
    final result = await services.speechInput.listenOnce();
    if (!mounted) return;
    setState(() => _micBusy = false);
    if (result.ok) {
      _controller.text = result.text;
      _ask();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  // --- M2: spoken answers ----------------------------------------------
  String _speakableText(ComposedAnswer answer) {
    final parts = <String>[];
    for (final f in answer.fragments) {
      parts.add('[warm] ${f.entry.title}. ${f.entry.body}');
    }
    return parts.join(' ');
  }

  String _plainAnswerText(ComposedAnswer answer) {
    final parts = <String>[];
    for (final f in answer.fragments) {
      parts.add('${f.entry.title}. ${f.entry.body}');
    }
    return parts.join(' ');
  }

  Future<void> _toggleSpeak(int index, _ChatMessage m) async {
    final services = widget.services;
    if (services == null || m.answer == null) return;
    if (_speakingIndex == index) {
      await services.voice.stop();
      if (mounted) setState(() => _speakingIndex = null);
      return;
    }
    setState(() => _speakingIndex = index);
    final result = await services.voice.speak(
      _speakableText(m.answer!),
      level: widget.emotionLevel,
      voice: widget.selectedVoice,
    );
    if (!mounted) return;
    setState(() => _speakingIndex = null);
    if (!result.spoken && result.message.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  // --- M2: translate an answer ------------------------------------------
  Future<void> _translateAnswer(_ChatMessage m) async {
    final services = widget.services;
    if (services == null || m.answer == null) return;
    final lang = widget.chatLanguage;
    final result = await services.translation.translateWithCascade(
      _plainAnswerText(m.answer!),
      fromCode: 'en',
      toCode: lang.code,
    );
    if (!mounted) return;
    setState(() {
      m.translatedText = result.text;
      m.translationNote = result.tier == TranslationTier.failed
          ? result.message
          : 'In ${lang.name}'
              '${result.tier == TranslationTier.cloud ? ' (cloud help)' : ' — translated on this device'}.';
      // Compliance on the FINAL-LANGUAGE text (SPEC §7.4).
      m.translationHits = const ComplianceScanner().scan(result.text).hits;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ask a question'), actions: [HelpButton(screenKey: 'chat', brand: widget.brand, services: widget.services, db: widget.db, share: null, emotionLevel: widget.emotionLevel)],),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Answers come from the built-in database and always show '
                'their source and claim label. Works fully offline.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Try asking: "What is X39?" or "How long do I '
                        'wear a patch?" — or tap the microphone and ask '
                        'out loud.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) =>
                        _buildMessage(i, _messages[i]),
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  if (widget.services != null)
                    IconButton(
                      onPressed: _micBusy ? null : _micAsk,
                      icon: Icon(_micBusy ? Icons.hearing : Icons.mic_none),
                      tooltip: _micBusy
                          ? 'Listening…'
                          : 'Ask by voice — tap and talk',
                    ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Type your question…',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _ask(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _ask,
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('Ask'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(int index, _ChatMessage m) {
    if (m.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: LwColors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(m.userText!,
              style: const TextStyle(color: Colors.white)),
        ),
      );
    }
    if (m.noteText != null) {
      return Card(
        color: LwColors.tint,
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(m.noteText!)),
            ],
          ),
        ),
      );
    }
    final answer = m.answer!;
    if (!answer.hasMatches) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(noMatchAnswerText),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _askCloud,
                icon: const Icon(Icons.cloud_outlined, size: 18),
                label: const Text('Try cloud help'),
              ),
              const Text(
                'Cloud help is an extra service that is not set up yet.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    final speaking = _speakingIndex == index;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'From the database:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            for (final fragment in answer.fragments)
              _FragmentView(
                fragment: fragment,
                onOpenSource: _openUrl,
                onOpenDetail: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EntryDetailScreen(
                      entry: fragment.entry,
                      brand: widget.brand,
                    ),
                  ),
                ),
              ),
            if (widget.services != null)
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _toggleSpeak(index, m),
                    icon: Icon(
                        speaking ? Icons.stop : Icons.volume_up_outlined,
                        size: 18),
                    label: Text(speaking ? 'Stop' : 'Listen'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _translateAnswer(m),
                    icon: const Icon(Icons.translate, size: 18),
                    label: Text('Translate (${widget.chatLanguage.name})'),
                  ),
                ],
              ),
            if (m.translatedText != null) ...[
              const Divider(),
              Text(m.translatedText!),
              if (m.translationNote != null)
                Text(
                  m.translationNote!,
                  style: const TextStyle(
                      fontSize: 12, fontStyle: FontStyle.italic),
                ),
              if (m.translationHits.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Compliance check on the translated words: '
                    '${m.translationHits.map((h) => '"${h.term}"').join(', ')} '
                    '— please review before sharing.',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.deepOrange),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FragmentView extends StatelessWidget {
  final AnswerFragment fragment;
  final void Function(String url) onOpenSource;
  final VoidCallback onOpenDetail;
  const _FragmentView({
    required this.fragment,
    required this.onOpenSource,
    required this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    final KnowledgeEntry entry = fragment.entry;
    final groupUrl = firstUrl(entry.sourceRef) ?? firstUrl(entry.body);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  entry.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              ClaimChip(entry: entry),
            ],
          ),
          Text(
            'Source topic: ${topicLabel(entry.topic)}',
            style:
                const TextStyle(fontSize: 12, color: LwColors.deepNavy),
          ),
          const SizedBox(height: 4),
          Text(fragment.text),
          Row(
            children: [
              TextButton(
                onPressed: onOpenDetail,
                child: const Text('See full entry'),
              ),
              if (entry.isPointer && groupUrl != null)
                TextButton.icon(
                  onPressed: () => onOpenSource(groupUrl),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open the group'),
                ),
            ],
          ),
          const Divider(height: 8),
        ],
      ),
    );
  }
}
