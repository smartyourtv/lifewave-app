import 'dart:async';

import 'package:flutter/material.dart';

import '../services/demo.dart';
import '../services/emotion.dart';
import '../services/translation_service.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import '../widgets/common.dart' show LogoImage;
import '../widgets/social_widgets.dart';
import 'fact_cards_screen.dart' show FactCardView;
import 'guide_screen.dart';

/// 60-second demo mode (SPEC §7.8 item 2): a guided, skippable
/// showcase. Every step runs the REAL feature with a sample input
/// (see services/demo.dart). Progress shows "step n of 6" + elapsed;
/// pause = stop tapping Next (the demo only advances on Next); Exit
/// leaves at any time. Fully offline by construction.
class DemoScreen extends StatefulWidget {
  final SocialDeps deps;
  final EmotionLevel emotionLevel;
  final VoiceInfo? selectedVoice;
  const DemoScreen({
    super.key,
    required this.deps,
    this.emotionLevel = EmotionLevel.warm,
    this.selectedVoice,
  });

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  AppLanguage _target = languageByCode('es');
  DemoRunner? _runner;
  DemoStepResult? _current;
  bool _busy = false;
  Timer? _ticker;
  int _elapsedSeconds = 0;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _ticker?.cancel();
    _elapsedSeconds = 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  Future<void> _begin() async {
    final engines = RealDemoEngines(
      db: widget.deps.db,
      services: widget.deps.m2,
      imageFor: widget.deps.brand.productImageFor,
      emotionLevel: widget.emotionLevel,
      selectedVoice: widget.selectedVoice,
    );
    final runner = DemoRunner(
      engines: engines,
      db: widget.deps.db,
      targetLanguage: _target,
    );
    setState(() => _runner = runner);
    _startTimer();
    await _advance();
  }

  Future<void> _advance() async {
    final runner = _runner;
    if (runner == null || _busy) return;
    setState(() => _busy = true);
    final result = await runner.next();
    if (!mounted) return;
    setState(() {
      _current = result;
      _busy = false;
      if (runner.isFinished) _ticker?.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final runner = _runner;
    final current = _current;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Demo — what the app can do'),
        actions: [
          HelpButton(
            screenKey: 'demo',
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
          if (runner == null) ...[
            Center(
              child: LogoImage(
                  assetPath: widget.deps.brand.logoAssetPath, height: 44),
            ),
            const SizedBox(height: 12),
            Text(
              'Show me what you can do',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'A one-minute guided tour. Every step really happens — '
              'a spoken answer from the database, a real translation, '
              'a real post draft, a real fact card. Works offline.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<AppLanguage>(
              value: _target,
              decoration: const InputDecoration(
                labelText: 'Demo translation language',
                border: OutlineInputBorder(),
              ),
              items: kAppLanguages
                  .where((l) => l.code != 'en')
                  .map((l) => DropdownMenuItem(value: l, child: Text(l.name)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _target = v);
              },
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _begin,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start the demo'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ] else ...[
            // Progress: step n of 6 + elapsed, with pause-by-omission
            // explained honestly (the demo advances only on Next).
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: runner.currentStepNumber / runner.totalSteps,
                    color: LwColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Step ${runner.currentStepNumber} of '
                  '${runner.totalSteps} • ${_elapsedSeconds}s',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'The demo only moves when you tap Next — take your time. '
              'Use the back arrow any time to exit.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (_busy || current == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              Text(
                current.step.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              if (current.step == DemoStep.factCard &&
                  current.factCard != null)
                Center(child: FactCardView(card: current.factCard!))
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      current.bodyText,
                      style: const TextStyle(fontSize: 16, height: 1.4),
                    ),
                  ),
                ),
              if (current.note.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  current.note,
                  style: const TextStyle(
                      fontSize: 13, fontStyle: FontStyle.italic),
                ),
              ],
              const SizedBox(height: 20),
              if (!runner.isFinished)
                FilledButton.icon(
                  onPressed: _advance,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Next'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.check),
                  label: const Text('Done — back to the app'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}
