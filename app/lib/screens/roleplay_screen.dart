import 'package:flutter/material.dart';

import '../services/compliance_guide.dart';
import '../services/emotion.dart';
import '../services/roleplay.dart';
import '../services/translation_service.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import '../widgets/social_widgets.dart';
import 'guide_screen.dart';

/// Roleplay practice (SPEC §7.8 item 1). The app plays a skeptical
/// prospect from the built-in scenario bank; the user answers by voice
/// or text; the coach reviews every answer (compliance flags, key
/// points covered, a stronger phrasing from the database).
class RoleplayScreen extends StatefulWidget {
  final SocialDeps deps;
  final EmotionLevel emotionLevel;
  final VoiceInfo? selectedVoice;
  const RoleplayScreen({
    super.key,
    required this.deps,
    this.emotionLevel = EmotionLevel.warm,
    this.selectedVoice,
  });

  @override
  State<RoleplayScreen> createState() => _RoleplayScreenState();
}

class _RoleplayScreenState extends State<RoleplayScreen> {
  late final RoleplayEngine _engine = RoleplayEngine(widget.deps.db);
  final _answerController = TextEditingController();
  ProspectPersona? _persona;
  RoleplaySession? _session;
  String? _currentMarkedLine;
  String? _translatedLine;
  CoachReview? _lastReview;
  bool _finished = false;
  AppLanguage _practiceLanguage = languageByCode('en');
  bool _busy = false;

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  void _feedback(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _start(ProspectPersona persona) async {
    final session = _engine.start(persona);
    if (session == null) {
      _feedback('That practice partner is not available — their '
          'database entry is missing.');
      return;
    }
    setState(() {
      _persona = persona;
      _session = session;
      _currentMarkedLine = session.openingMarked;
      _translatedLine = null;
      _lastReview = null;
      _finished = false;
      _answerController.clear();
    });
    await _speakCurrent();
  }

  /// Speaks the prospect's current line. When a practice language
  /// other than English is picked, the line is translated first (M2)
  /// and the translation is what is spoken + shown as the line.
  Future<void> _speakCurrent() async {
    final marked = _currentMarkedLine;
    if (marked == null) return;
    var toSpeak = marked;
    if (_practiceLanguage.code != 'en') {
      final plain = marked.replaceAll(RegExp(r'\[[A-Za-z]+\]\s*'), '');
      final result = await widget.deps.m2.translation.translateWithCascade(
        plain,
        fromCode: 'en',
        toCode: _practiceLanguage.code,
      );
      if (!mounted) return;
      if (result.usedOriginal) {
        _feedback(result.message);
      } else {
        // Keep the emotion tag, swap in the translated words.
        final tag = RegExp(r'^\[[A-Za-z]+\]').firstMatch(marked)?.group(0) ?? '[warm]';
        toSpeak = '$tag ${result.text}';
        setState(() => _translatedLine = result.text);
      }
    }
    await widget.deps.m2.voice.speak(
      toSpeak,
      level: widget.emotionLevel,
      voice: widget.selectedVoice,
    );
  }

  Future<void> _submit() async {
    final session = _session;
    final answer = _answerController.text.trim();
    if (session == null) return;
    if (answer.isEmpty) {
      _feedback('Say or type your answer first.');
      return;
    }
    setState(() => _busy = true);
    final outcome = session.answer(answer);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastReview = outcome.review;
      _answerController.clear();
      _translatedLine = null;
      if (outcome.nextMarkedLine != null) {
        _currentMarkedLine = outcome.nextMarkedLine;
      } else {
        _finished = true;
        _currentMarkedLine = session.closingMarked;
      }
    });
    await _speakCurrent();
  }

  String _plain(String marked) =>
      marked.replaceAll(RegExp(r'\[[A-Za-z]+\]\s*'), '');

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice conversations'),
        actions: [
          HelpButton(
            screenKey: 'roleplay',
            brand: widget.deps.brand,
            services: widget.deps.m2,
            db: widget.deps.db,
            share: widget.deps.share,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            color: LwColors.tint,
            child: ListTile(
              leading: Icon(Icons.school_outlined),
              title: Text('Practice partner — built-in practice, not a real person'),
              subtitle: Text(
                'The prospect below is played by the app from its '
                'built-in practice bank. The coach checks your answers '
                'against the database and the compliance rules.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (session == null) ...[
            Text('Pick who to practice with',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final p in _engine.personas)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline,
                      color: LwColors.primary),
                  title: Text(p.name),
                  subtitle: Text(p.description),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _start(p),
                ),
              ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Practicing with ${_persona!.name}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _session = null;
                    _persona = null;
                    _lastReview = null;
                    _finished = false;
                  }),
                  icon: const Icon(Icons.swap_horiz_outlined, size: 18),
                  label: const Text('Change'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<AppLanguage>(
              value: _practiceLanguage,
              decoration: const InputDecoration(
                labelText: 'Prospect speaks (practice language)',
                border: OutlineInputBorder(),
              ),
              items: kAppLanguages
                  .map((l) => DropdownMenuItem(value: l, child: Text(l.name)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _practiceLanguage = v;
                  _translatedLine = null;
                });
                _speakCurrent();
              },
            ),
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFFFFF8E1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_persona!.name.split('—').first.trim()} says:',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _translatedLine ?? _plain(_currentMarkedLine!),
                      style: const TextStyle(fontSize: 17, height: 1.35),
                    ),
                    if (_translatedLine != null)
                      Text(
                        'In English: "${_plain(_currentMarkedLine!)}"',
                        style: const TextStyle(
                            fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _speakCurrent,
                      icon: const Icon(Icons.volume_up_outlined, size: 18),
                      label: const Text('Hear them again'),
                    ),
                  ],
                ),
              ),
            ),
            if (!_finished) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _answerController,
                maxLines: 4,
                minLines: 2,
                decoration: InputDecoration(
                  labelText: 'Your answer',
                  hintText: 'Talk or type your answer, like you '
                      'would in a real conversation…',
                  border: const OutlineInputBorder(),
                  suffixIcon: DictateButton(
                    services: widget.deps.m2,
                    onText: (t) =>
                        setState(() => _answerController.text = t),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: const Icon(Icons.send_outlined, size: 18),
                label: const Text('Answer'),
              ),
            ] else
              const Card(
                color: LwColors.tint,
                child: ListTile(
                  leading: Icon(Icons.celebration_outlined),
                  title: Text('Practice round complete'),
                  subtitle: Text(
                    'Read the coach notes below, then practice again '
                    'or try another prospect.',
                  ),
                ),
              ),
            if (_finished)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.icon(
                  onPressed: () => _start(_persona!),
                  icon: const Icon(Icons.replay, size: 18),
                  label: const Text('Practice again'),
                ),
              ),
            if (_lastReview != null) ...[
              const SizedBox(height: 16),
              Text('Coach notes on your last answer',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ComplianceResultsView(
                report: _lastReview!.report,
                guide: ComplianceGuide.fromDb(widget.deps.db.entries),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Key points',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      for (final p in _lastReview!.coveredPoints)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.check_circle,
                              color: Colors.green, size: 20),
                          title: Text(p),
                        ),
                      for (final p in _lastReview!.missedPoints)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.circle_outlined,
                              color: Colors.orange, size: 20),
                          title: Text('Still to cover: $p'),
                        ),
                      const Divider(),
                      const Text('A stronger way to say it '
                          '(from the database answer):',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        '"${_lastReview!.suggestedPhrasing}"',
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
