import 'package:flutter/material.dart';

import '../services/compliance.dart';
import '../services/emotion.dart';
import '../services/m2_services.dart';
import '../services/speech_input.dart';
import '../services/translation_service.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import 'guide_screen.dart';

/// Shared small pieces for the two translator screens.

Widget _complianceBanner(ComplianceReport report) {
  if (report.isClean) return const SizedBox.shrink();
  return Card(
    color: const Color(0xFFFFF3E0),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_outlined, color: Colors.deepOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Please check before you share this: it contains wording '
              'the compliance rules flag — '
              '${report.hits.map((h) => '"${h.term}" (${h.categoryLabel.toLowerCase()})').join(', ')}. '
              'The words were NOT changed for you.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _languageDropdown({
  required String label,
  required AppLanguage value,
  required ValueChanged<AppLanguage> onChanged,
}) {
  return DropdownButtonFormField<AppLanguage>(
    value: value,
    decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    items: kAppLanguages
        .map((l) => DropdownMenuItem(value: l, child: Text(l.name)))
        .toList(),
    onChanged: (v) {
      if (v != null) onChanged(v);
    },
  );
}

Future<void> _micInto(
  BuildContext context,
  SpeechInputService speech,
  TextEditingController target,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await speech.listenOnce();
  if (result.ok) {
    target.text = result.text;
  } else {
    messenger.showSnackBar(SnackBar(content: Text(result.message)));
  }
}

// ---------------------------------------------------------------------------
// Free-text translator (SPEC §7.4)
// ---------------------------------------------------------------------------

class TranslatorScreen extends StatefulWidget {
  final M2Services services;
  final EmotionLevel emotionLevel;
  final VoiceInfo? selectedVoice;
  const TranslatorScreen({
    super.key,
    required this.services,
    required this.emotionLevel,
    required this.selectedVoice,
  });

  @override
  State<TranslatorScreen> createState() => _TranslatorScreenState();
}

class _TranslatorScreenState extends State<TranslatorScreen> {
  final _input = TextEditingController();
  AppLanguage _from = languageByCode('en');
  AppLanguage _to = languageByCode('es');
  TranslationResult? _result;
  ComplianceReport? _report;
  bool _busy = false;
  bool _packDownloaded = true;

  @override
  void initState() {
    super.initState();
    _refreshPack();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _refreshPack() async {
    final has =
        await widget.services.translation.engine.isModelDownloaded(_to.code);
    if (mounted) setState(() => _packDownloaded = has);
  }

  Future<void> _downloadPack() async {
    setState(() => _busy = true);
    final ok = await widget.services.translation.downloadPack(_to.code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _packDownloaded = ok;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'The ${_to.name} language pack is downloaded.'
          : 'The pack could not be downloaded. Check your internet and try again.'),
    ));
  }

  Future<void> _translate() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    final result = await widget.services.translation.translateWithCascade(
      text,
      fromCode: _from.code,
      toCode: _to.code,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
      // Compliance runs on the FINAL-LANGUAGE text (SPEC §7.4).
      _report = const ComplianceScanner().scan(result.text);
    });
  }

  Future<void> _speak() async {
    final r = _result;
    if (r == null) return;
    await widget.services.voice.speak(
      '[warm] ${r.text}',
      level: widget.emotionLevel,
      voice: widget.selectedVoice,
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Translator'), actions: [HelpButton(screenKey: 'translator', brand: null, services: widget.services, db: null, share: null, emotionLevel: widget.emotionLevel)],),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Translate words and messages. Translation happens on this '
            'device when the language pack is downloaded; typed text '
            'always works. Speech works only for languages this device '
            'supports.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _languageDropdown(
                  label: 'From',
                  value: _from,
                  onChanged: (v) => setState(() => _from = v),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.swap_horiz),
                tooltip: 'Swap languages',
                onPressed: () => setState(() {
                  final t = _from;
                  _from = _to;
                  _to = t;
                  _refreshPack();
                }),
              ),
              Expanded(
                child: _languageDropdown(
                  label: 'To',
                  value: _to,
                  onChanged: (v) {
                    setState(() => _to = v);
                    _refreshPack();
                  },
                ),
              ),
            ],
          ),
          if (!_packDownloaded) ...[
            const SizedBox(height: 8),
            Card(
              color: LwColors.tint,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.download_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'The ${_to.name} pack is not on this device yet. '
                        'Download it once to translate offline.',
                      ),
                    ),
                    FilledButton(
                      onPressed: _busy ? null : _downloadPack,
                      child: const Text('Download'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _input,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Words to translate',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _micInto(
                    context, widget.services.speechInput, _input),
                icon: const Icon(Icons.mic_none),
                label: const Text('Speak it'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _translate,
                  icon: const Icon(Icons.translate),
                  label: Text(_busy ? 'Translating…' : 'Translate'),
                ),
              ),
            ],
          ),
          if (result != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(result.text, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(
                      result.tier == TranslationTier.onDevice
                          ? 'Translated on this device.'
                          : result.tier == TranslationTier.cloud
                              ? 'Translated with cloud help.'
                              : result.message,
                      style: const TextStyle(
                          fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _speak,
                      icon: const Icon(Icons.volume_up_outlined),
                      label: const Text('Hear it'),
                    ),
                  ],
                ),
              ),
            ),
            if (_report != null) _complianceBanner(_report!),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2-way conversation translator (SPEC §7.5)
// ---------------------------------------------------------------------------

class ConversationScreen extends StatefulWidget {
  final M2Services services;
  final EmotionLevel emotionLevel;
  const ConversationScreen({
    super.key,
    required this.services,
    required this.emotionLevel,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  late final ConversationTranslator _convo = ConversationTranslator(
    translation: widget.services.translation,
    voice: widget.services.voice,
  );
  final _textA = TextEditingController();
  final _textB = TextEditingController();
  bool _busy = false;
  bool _listeningA = false;
  bool _listeningB = false;

  @override
  void dispose() {
    _textA.dispose();
    _textB.dispose();
    super.dispose();
  }

  Future<void> _speakSide(ConversationSide side) async {
    final isA = side == ConversationSide.a;
    setState(() {
      if (isA) {
        _listeningA = true;
      } else {
        _listeningB = true;
      }
    });
    final result = await widget.services.speechInput.listenOnce();
    if (!mounted) return;
    setState(() {
      _listeningA = false;
      _listeningB = false;
    });
    if (result.ok) {
      (isA ? _textA : _textB).text = result.text;
      await _send(side);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  Future<void> _send(ConversationSide side) async {
    final controller = side == ConversationSide.a ? _textA : _textB;
    final text = controller.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    await _convo.processTurn(
      speaker: side,
      inputText: text,
      emotionLevel: widget.emotionLevel,
      manualSourceCode: _convo.autoDetect
          ? null
          : _convo.languageFor(side).code,
    );
    if (!mounted) return;
    controller.clear();
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Talk together'), actions: [HelpButton(screenKey: 'conversation', brand: null, services: widget.services, db: null, share: null, emotionLevel: widget.emotionLevel)],),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Take turns talking. The app listens, works out the '
                  'language, translates, and says it out loud in the '
                  'other language. Speech works only for languages this '
                  'device supports — typing always works, on both sides.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _languageDropdown(
                        label: 'Person 1 speaks',
                        value: _convo.languageA,
                        onChanged: (v) =>
                            setState(() => _convo.languageA = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _languageDropdown(
                        label: 'Person 2 speaks',
                        value: _convo.languageB,
                        onChanged: (v) =>
                            setState(() => _convo.languageB = v),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Work out the language automatically'),
                  subtitle: const Text(
                    'On: each turn is detected. Off: the language above '
                    'is used for that person.',
                  ),
                  value: _convo.autoDetect,
                  onChanged: (v) => setState(() => _convo.autoDetect = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: _convo.turns.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Nothing said yet. Person 1 can tap their big '
                        'button below and talk.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _convo.turns.length,
                    itemBuilder: (context, i) {
                      final turn = _convo.turns[i];
                      final isA = turn.speaker == ConversationSide.a;
                      return Align(
                        alignment:
                            isA ? Alignment.centerLeft : Alignment.centerRight,
                        child: Card(
                          color: isA ? LwColors.white : LwColors.tint,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${isA ? 'Person 1' : 'Person 2'} '
                                  '(${languageByCode(turn.sourceCode).name})',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12),
                                ),
                                Text(turn.originalText),
                                const Divider(),
                                Text(
                                  turn.translatedText,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  turn.failed
                                      ? "Couldn't translate — original shown."
                                      : 'In ${languageByCode(turn.targetCode).name}'
                                          '${turn.tier == TranslationTier.cloud ? ' (cloud help)' : ''}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic),
                                ),
                                if (turn.complianceHits.isNotEmpty)
                                  Text(
                                    'Compliance check: ${turn.complianceHits.map((h) => '"${h.term}"').join(', ')} — please review before sharing.',
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.deepOrange),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _sideControls(
                      side: ConversationSide.a,
                      label: 'Person 1 — ${_convo.languageA.name}',
                      controller: _textA,
                      listening: _listeningA,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _sideControls(
                      side: ConversationSide.b,
                      label: 'Person 2 — ${_convo.languageB.name}',
                      controller: _textB,
                      listening: _listeningB,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sideControls({
    required ConversationSide side,
    required String label,
    required TextEditingController controller,
    required bool listening,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : () => _speakSide(side),
          icon: Icon(listening ? Icons.hearing : Icons.mic),
          label: Text(listening ? 'Listening…' : label),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: '…or type here',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _send(side),
              ),
            ),
            IconButton(
              onPressed: _busy ? null : () => _send(side),
              icon: const Icon(Icons.send),
              tooltip: 'Translate this',
            ),
          ],
        ),
      ],
    );
  }
}
