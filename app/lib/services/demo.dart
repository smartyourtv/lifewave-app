import '../models/entry.dart';
import 'emotion.dart';
import 'fact_card.dart';
import 'knowledge_db.dart';
import 'm2_services.dart';
import 'post_generator.dart';
import 'retrieval.dart';
import 'translation_service.dart';
import 'voice_service.dart' show VoiceInfo;

/// 60-second demo mode (SPEC §7.8 item 2): "Show me what you can do."
///
/// HONESTY RULE FOR THE DEMO: every step runs the REAL feature code
/// with sample inputs — the retrieval answer is a real retrieval
/// answer, the translation is a real translation, the post is a real
/// generated draft, the fact card is a real composed card. No fake
/// screenshots, no scripted outcomes.
///
/// OFFLINE-SAFE: if an engine is unavailable on the device (no speech
/// input, no language pack), the step ADAPTS and says so in the step —
/// the demo never fails or hangs because of one engine.
///
/// Pacing is caller-driven ([DemoRunner.next]) so the screen can
/// pause or exit between steps at any time.

/// The demo steps, in the exact order they run.
enum DemoStep { intro, voiceQa, translator, post, factCard, closing }

const List<DemoStep> kDemoStepOrder = [
  DemoStep.intro,
  DemoStep.voiceQa,
  DemoStep.translator,
  DemoStep.post,
  DemoStep.factCard,
  DemoStep.closing,
];

extension DemoStepLabel on DemoStep {
  String get title {
    switch (this) {
      case DemoStep.intro:
        return 'Welcome';
      case DemoStep.voiceQa:
        return 'Ask — and hear the answer';
      case DemoStep.translator:
        return 'Say it in another language';
      case DemoStep.post:
        return 'A curiosity post, written for you';
      case DemoStep.factCard:
        return 'A fact card you can share';
      case DemoStep.closing:
        return 'That is the tour';
    }
  }
}

/// The sample product question the voice Q&A step asks for real.
const String kDemoSampleQuestion = 'What is X39?';

/// The sample line the translator step translates for real.
const String kDemoSampleLine =
    'Hello! Would you like to hear how this works?';

/// What one finished step produced — real outputs, shown by the screen.
class DemoStepResult {
  final DemoStep step;

  /// Main text the screen shows (the real answer / translation / post).
  final String bodyText;

  /// Plain note about how the step ran ('' when unremarkable) — this
  /// is where adaptations are stated honestly.
  final String note;

  /// The real fact card, on the fact-card step only.
  final FactCardData? factCard;

  const DemoStepResult({
    required this.step,
    required this.bodyText,
    this.note = '',
    this.factCard,
  });
}

/// The engines the demo drives. The production implementation wraps
/// the app's real services; tests use fakes.
abstract class DemoEngines {
  /// True when tap-to-talk speech input can run on this device.
  Future<bool> speechInputAvailable();

  /// A REAL retrieval answer to [question]: display text + the
  /// speakable (emotion-marked) form.
  Future<({String display, String speakable})> answerQuestion(String question);

  /// Speaks [markedText] through the single voice controller.
  /// Returns false when nothing was spoken (screen notes it).
  Future<bool> speak(String markedText);

  /// A REAL translation of [text] into [toCode]; [adapted] explains
  /// any fallback (original shown, pack missing, …).
  Future<({String text, String adapted})> translateSample(
      String text, String toCode);

  /// A REAL generated curiosity post for the sample product.
  Future<String> generateSamplePost(KnowledgeEntry product);

  /// A REAL composed fact card for the sample product.
  FactCardData sampleFactCard(KnowledgeEntry product);
}

/// Step-by-step demo runner. The screen calls [next] when the user
/// taps Next (or on its own timer); pausing = not calling [next];
/// exiting = abandoning the runner. [next] never throws.
class DemoRunner {
  final DemoEngines engines;
  final KnowledgeDb db;
  final AppLanguage targetLanguage;

  int _index = -1;
  final List<DemoStepResult> results = [];

  DemoRunner({
    required this.engines,
    required this.db,
    required this.targetLanguage,
  });

  int get totalSteps => kDemoStepOrder.length;

  /// 1-based number of the NEXT step to run is currentStep+1; after
  /// [next], this is the step that just ran (for "step n of 6").
  int get currentStepNumber => _index + 1;
  bool get isFinished => _index >= kDemoStepOrder.length - 1 && _index >= 0;
  DemoStep? get nextStep =>
      _index + 1 < kDemoStepOrder.length ? kDemoStepOrder[_index + 1] : null;

  KnowledgeEntry get _sampleProduct =>
      db.byId('prod-x39') ?? db.byTopic('products').first;

  /// Runs the next step and returns its real result. Any engine
  /// failure becomes an honest adaptation note in the step — the demo
  /// completes regardless (offline-safe rule).
  Future<DemoStepResult> next() async {
    final step = nextStep ?? DemoStep.closing;
    _index++;
    final result = await _run(step);
    results.add(result);
    return result;
  }

  Future<DemoStepResult> _run(DemoStep step) async {
    try {
      switch (step) {
        case DemoStep.intro:
          return DemoStepResult(
            step: step,
            bodyText: 'This is LifeWave AI — your helper for product '
                'questions, posts, replies and practice. Everything you '
                'are about to see is the real app working, with sample '
                'questions. Nothing here is a recording.',
          );
        case DemoStep.voiceQa:
          final sttOk = await engines.speechInputAvailable();
          final answer = await engines.answerQuestion(kDemoSampleQuestion);
          final spoken = await engines.speak(answer.speakable);
          return DemoStepResult(
            step: step,
            bodyText: 'Q: $kDemoSampleQuestion\n\n${answer.display}',
            note: [
              if (!sttOk)
                'Voice typing is not available on this device, so this '
                    'sample question was typed instead — the answer is '
                    'the same either way.',
              if (!spoken)
                'The spoken answer could not play on this device, so '
                    'the answer is on the screen instead.',
              if (sttOk && spoken)
                'That answer was found in the built-in database and '
                    'spoken out loud, with feeling.',
            ].join(' '),
          );
        case DemoStep.translator:
          final t = await engines.translateSample(
              kDemoSampleLine, targetLanguage.code);
          var note = t.adapted;
          if (note.isEmpty) {
            final spoken = await engines.speak('[warm] ${t.text}');
            if (!spoken) {
              note = 'Translated on this device. The spoken version '
                  'could not play, so read it on the screen.';
            } else {
              note = 'Translated on this device into '
                  '${targetLanguage.name} and spoken out loud.';
            }
          }
          return DemoStepResult(
            step: step,
            bodyText: '"$kDemoSampleLine"\n\nIn ${targetLanguage.name}: '
                '"${t.text}"',
            note: note,
          );
        case DemoStep.post:
          final post = await engines.generateSamplePost(_sampleProduct);
          return DemoStepResult(
            step: step,
            bodyText: post,
            note: 'A real draft from the post writer, using the '
                'playbook style. In the Posts screen you would check '
                'it, approve it, and share it yourself.',
          );
        case DemoStep.factCard:
          final card = engines.sampleFactCard(_sampleProduct);
          return DemoStepResult(
            step: step,
            bodyText: '${card.productTitle}\n${card.fact}\n${card.question}',
            note: 'A real fact card — one official fact and one '
                'curiosity question, checked for compliance. In Fact '
                'cards you can export it as a picture.',
            factCard: card,
          );
        case DemoStep.closing:
          return const DemoStepResult(
            step: DemoStep.closing,
            bodyText: 'That was the short tour. Find these any time: '
                'Chat for questions, Translator and Talk together in '
                'More, Posts and Replies in More, and the Guide in '
                'More explains everything in plain words.',
          );
      }
    } catch (e) {
      // A step's engine failed hard: adapt, say so, keep going.
      return DemoStepResult(
        step: step,
        bodyText: 'This step could not run on this device right now.',
        note: 'The demo continues — the rest of the app still works, '
            'and Diagnostics can show what is happening.',
      );
    }
  }
}

/// Production engines: the app's real M2 services + database features.
class RealDemoEngines implements DemoEngines {
  final KnowledgeDb db;
  final M2Services services;
  final String? Function(String productId) imageFor;
  final EmotionLevel emotionLevel;
  final VoiceInfo? selectedVoice;

  RealDemoEngines({
    required this.db,
    required this.services,
    required this.imageFor,
    required this.emotionLevel,
    required this.selectedVoice,
  });

  @override
  Future<bool> speechInputAvailable() async {
    try {
      return await services.speechInput.ensureReady();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<({String display, String speakable})> answerQuestion(
      String question) async {
    final results = Retrieval(db.entries).search(question);
    final answer = composeAnswer(question, results);
    if (!answer.hasMatches) {
      return (
        display: noMatchAnswerText,
        speakable: '[warm] $noMatchAnswerText',
      );
    }
    final display =
        answer.fragments.map((f) => '${f.entry.title}. ${f.entry.body}').join('\n\n');
    final speakable = answer.fragments
        .map((f) => '[warm] ${f.entry.title}. ${f.entry.body}')
        .join(' ');
    return (display: display, speakable: speakable);
  }

  @override
  Future<bool> speak(String markedText) async {
    final result = await services.voice.speak(
      markedText,
      level: emotionLevel,
      voice: selectedVoice,
    );
    return result.spoken;
  }

  @override
  Future<({String text, String adapted})> translateSample(
      String text, String toCode) async {
    final result = await services.translation.translateWithCascade(
      text,
      fromCode: 'en',
      toCode: toCode,
    );
    return (
      text: result.text,
      adapted: result.usedOriginal ? result.message : '',
    );
  }

  @override
  Future<String> generateSamplePost(KnowledgeEntry product) async {
    final gen = PostGenerator(db);
    final template = gen.templates.first;
    return gen.compose(template: template, product: product);
  }

  @override
  FactCardData sampleFactCard(KnowledgeEntry product) {
    return composeFactCard(
      product,
      imageAssetPath: imageFor(product.id),
      focus: focusForProduct(product),
    );
  }
}
