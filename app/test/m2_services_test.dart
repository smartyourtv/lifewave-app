import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifewave_app/services/compliance.dart';
import 'package:lifewave_app/services/emotion.dart';
import 'package:lifewave_app/services/speech_input.dart';
import 'package:lifewave_app/services/translation_service.dart';
import 'package:lifewave_app/services/voice_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class FakeTtsPlatform implements TtsPlatform {
  final List<String> spoken = [];
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setPitch(double pitch) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setVoice(Map<String, String> voice) async {}
  @override
  Future<dynamic> getVoices() async => [
        {'name': 'Voice One', 'locale': 'en-US'},
        {'name': 'Voice Two', 'locale': 'es-ES'},
      ];
  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {}
  @override
  void setCompletionHandler(void Function() handler) {}
}

class FakeSttPlatform implements SttPlatform {
  bool permission = true;
  bool initResult = true;
  int initCalls = 0;
  String heard = 'what is x39';
  @override
  Future<bool> initialize() async {
    initCalls++;
    return initResult;
  }

  @override
  Future<bool> hasPermission() async => permission;
  @override
  Future<bool> requestPermission() async => permission;
  @override
  bool get isListening => false;
  @override
  Future<void> listen({
    required void Function(String words, bool isFinal) onResult,
    String? localeId,
  }) async {
    onResult(heard, true);
  }

  @override
  Future<void> stop() async {}
}

class FakeTranslationEngine implements TranslationEngine {
  final Set<String> downloaded = {};
  final List<String> calls = [];
  Duration delay = Duration.zero;
  bool failTranslate = false;
  String detected = 'und';

  @override
  bool get isSupportedOnPlatform => true;
  @override
  Future<bool> isModelDownloaded(String code) async =>
      downloaded.contains(code);
  @override
  Future<void> downloadModel(String code) async {
    downloaded.add(code);
  }

  @override
  Future<void> deleteModel(String code) async {
    downloaded.remove(code);
  }

  @override
  Future<String> translate(String text, String fromCode, String toCode) async {
    calls.add('ondevice:$fromCode>$toCode');
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (failTranslate) throw const TranslationException('fake failure');
    return '[$toCode] $text';
  }

  @override
  Future<String> detectLanguage(String text) async => detected;
}

class FakeCloudTranslator implements CloudTranslator {
  final List<String> calls = [];
  final bool configured;
  FakeCloudTranslator({this.configured = true});
  @override
  bool get isConfigured => configured;
  @override
  Future<String> translate(String text, String fromCode, String toCode) async {
    calls.add('cloud:$fromCode>$toCode');
    if (!configured) {
      throw const TranslationException("Cloud translation isn't set up.");
    }
    return '[cloud $toCode] $text';
  }
}

VoiceService fakeVoiceService(FakeTtsPlatform tts) => VoiceService(
      deviceEngine: DeviceTtsEngine(platform: tts),
      modelManager: VoiceModelManager(
        dirProvider: () async => Directory.systemTemp.path,
        downloader: (url, dest, progress) async {},
      ),
    );

// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('EmotionParser', () {
    test('tags are stripped from display text; segments carry emotions', () {
      final parsed = EmotionParser.parse(
          '[warm] Hello there. [chuckle] That is funny.');
      expect(parsed.displayText, 'Hello there. That is funny.');
      expect(parsed.displayText, isNot(contains('[')));
      expect(parsed.segments.length, 2);
      expect(parsed.segments[0].emotion, Emotion.warm);
      expect(parsed.segments[1].emotion, Emotion.chuckle);
      expect(parsed.context, SpeechContext.normal);
    });

    test('unknown tags are stripped and do not change the emotion', () {
      final parsed = EmotionParser.parse('[sparkle] Plain words [zzz] here.');
      expect(parsed.displayText, 'Plain words here.');
      expect(parsed.segments.single.emotion, Emotion.neutral);
    });

    test('[urgent] switches the whole utterance to the urgent context', () {
      final parsed = EmotionParser.parse('[urgent] Warning: check this now.');
      expect(parsed.context, SpeechContext.urgent);
      expect(parsed.displayText, 'Warning: check this now.');
    });

    test('untagged text is one neutral segment', () {
      final parsed = EmotionParser.parse('Just a sentence.');
      expect(parsed.segments.single.emotion, Emotion.neutral);
    });
  });

  group('ProsodyMapper — mapping + level scaling', () {
    const mapper = ProsodyMapper();
    test('surprise raises pitch; sigh lowers rate and pitch', () {
      final surprise = mapper.map(
        emotion: Emotion.surprise,
        level: EmotionLevel.warm,
        context: SpeechContext.normal,
        seed: 42,
        segmentText: 'Oh!',
      );
      final sigh = mapper.map(
        emotion: Emotion.sigh,
        level: EmotionLevel.warm,
        context: SpeechContext.normal,
        seed: 42,
        segmentText: 'Oh well.',
      );
      expect(surprise.pitch, greaterThan(1.0));
      expect(sigh.pitch, lessThan(1.0));
      expect(sigh.rate, lessThan(surprise.rate));
    });

    test('level scaling: Full-hearted moves pitch further than Calm', () {
      double delta(EmotionLevel level) {
        final p = mapper.map(
          emotion: Emotion.surprise,
          level: level,
          context: SpeechContext.normal,
          seed: 7,
          segmentText: 'Wow!',
        );
        return (p.pitch - 1.0).abs();
      }

      expect(delta(EmotionLevel.fullHearted),
          greaterThan(delta(EmotionLevel.calm)));
      expect(delta(EmotionLevel.warm), greaterThan(delta(EmotionLevel.calm)));
    });

    test('intensity: laugh marker is smaller at Calm than at Full-hearted',
        () {
      String marker(EmotionLevel level) => mapper
          .map(
            emotion: Emotion.laugh,
            level: level,
            context: SpeechContext.normal,
            seed: 99,
            segmentText: 'That is funny.',
          )
          .marker;
      expect(marker(EmotionLevel.calm), 'ha ha! ');
      expect('ha ha ha ha! ', contains(marker(EmotionLevel.fullHearted).trim().isEmpty ? 'x' : 'ha'));
      expect(marker(EmotionLevel.fullHearted).split('ha').length,
          greaterThan(marker(EmotionLevel.calm).split('ha').length));
    });
  });

  group('ProsodyMapper — voice-realism rules (variation / situation / urgent)',
      () {
    const mapper = ProsodyMapper();

    test('(a) two renders of the same tag with different seeds differ', () {
      final a = mapper.map(
        emotion: Emotion.chuckle,
        level: EmotionLevel.warm,
        context: SpeechContext.normal,
        seed: 1001,
        segmentText: 'That is a fun way to look at it.',
      );
      final b = mapper.map(
        emotion: Emotion.chuckle,
        level: EmotionLevel.warm,
        context: SpeechContext.normal,
        seed: 2002,
        segmentText: 'That is a fun way to look at it.',
      );
      expect(a, isNot(equals(b)),
          reason: 'no two renders may be byte-identical');
      // And the same seed reproduces (deterministic core).
      final a2 = mapper.map(
        emotion: Emotion.chuckle,
        level: EmotionLevel.warm,
        context: SpeechContext.normal,
        seed: 1001,
        segmentText: 'That is a fun way to look at it.',
      );
      expect(a, equals(a2));
    });

    test('(a2) breath parameters vary per render and scale with length', () {
      ProsodyParams forLen(int len, int seed) => mapper.map(
            emotion: Emotion.warm,
            level: EmotionLevel.warm,
            context: SpeechContext.normal,
            seed: seed,
            segmentText: 'x' * len,
          );
      final short = forLen(30, 5);
      final longA = forLen(200, 5);
      final longB = forLen(200, 6);
      expect(longA.breathBefore.character, 'deepReset');
      expect(longA.breathBefore.depth, greaterThan(short.breathBefore.depth));
      expect(longA.breathBefore, isNot(equals(longB.breathBefore)));
    });

    test('(b) urgent context suppresses breaths and playful emotions', () {
      final p = mapper.map(
        emotion: Emotion.laugh,
        level: EmotionLevel.fullHearted,
        context: SpeechContext.urgent,
        seed: 3,
        segmentText: 'x' * 200,
      );
      expect(p.effectiveEmotion, Emotion.neutral);
      expect(p.marker, isEmpty);
      expect(p.breathBefore.present, isFalse);
      expect(p.breathAfter.present, isFalse);
      final chuckle = mapper.map(
        emotion: Emotion.chuckle,
        level: EmotionLevel.warm,
        context: SpeechContext.urgent,
        seed: 3,
        segmentText: 'hi',
      );
      expect(chuckle.marker, isEmpty);
      expect(chuckle.effectiveEmotion, Emotion.neutral);
    });

    test('(c) urgent suppression holds at every level; scaling still applies normally',
        () {
      for (final level in EmotionLevel.values) {
        final urgent = mapper.map(
          emotion: Emotion.surprise,
          level: level,
          context: SpeechContext.urgent,
          seed: 11,
          segmentText: 'Watch out.',
        );
        expect(urgent.breathBefore.present, isFalse);
        expect(urgent.marker, isEmpty);
      }
      // Non-urgent scaling still monotone in pitch delta.
      double d(EmotionLevel l) => (mapper
              .map(
                emotion: Emotion.surprise,
                level: l,
                context: SpeechContext.normal,
                seed: 11,
                segmentText: 'Watch out.',
              )
              .pitch -
          1.0);
      expect(d(EmotionLevel.fullHearted), greaterThan(d(EmotionLevel.gentle)));
    });

    test('breath character fits the situation: sigh/empathy soft, laugh breathy',
        () {
      final sigh = mapper.map(
        emotion: Emotion.sigh,
        level: EmotionLevel.warm,
        context: SpeechContext.normal,
        seed: 21,
        segmentText: 'Some days are harder.',
      );
      expect(sigh.breathBefore.character, 'softSlow');
      final laugh = mapper.map(
        emotion: Emotion.laugh,
        level: EmotionLevel.warm,
        context: SpeechContext.normal,
        seed: 21,
        segmentText: 'That is funny.',
      );
      expect(laugh.breathAfter.character, 'breathyAfterLaugh');
    });
  });

  group('ComplianceScanner', () {
    const scanner = ComplianceScanner();
    test('flags cure / treats / diagnoses style claims', () {
      final report = scanner.scan('This patch cures pain and treats arthritis.');
      expect(report.isClean, isFalse);
      final terms = report.hits.map((h) => h.term.toLowerCase()).toList();
      expect(terms, contains('cures'));
      expect(terms, contains('treats'));
      final r2 = scanner.scan('It diagnoses the problem early.');
      expect(r2.hits.map((h) => h.term.toLowerCase()), contains('diagnoses'));
    });

    test('passes compliant official-style text', () {
      final report = scanner.scan(
          'The company says X39 supports exercise performance and '
          'recovery. Many people add it to their daily routine.');
      expect(report.isClean, isTrue);
    });

    test('word boundaries: "secure" does not trip on "cure"', () {
      expect(scanner.scan('A secure, accurate summary.').isClean, isTrue);
    });

    test('flags terms in non-English final-language text', () {
      final es = scanner.scan('Este parche cura el dolor.');
      expect(es.isClean, isFalse);
      expect(es.hits.map((h) => h.term.toLowerCase()), contains('cura'));
      final vi = scanner.scan('Miếng dán này chữa được bệnh.');
      expect(vi.isClean, isFalse);
    });

    test('flags promised results and income claims', () {
      expect(scanner.scan('You will feel it working fast.').isClean, isFalse);
      expect(scanner.scan('Get rich from home!').isClean, isFalse);
    });
  });

  group('SpeechInputService', () {
    test('permission denied -> honest failure, typing fallback message', () async {
      final fake = FakeSttPlatform()..permission = false;
      final svc = SpeechInputService(platform: fake, isWindows: false);
      final result = await svc.listenOnce();
      expect(result.ok, isFalse);
      expect(result.message, contains('microphone'));
      expect(svc.state, SpeechInputState.permissionDenied);
    });

    test('Windows reports unavailable honestly (no parity promise)', () async {
      final svc = SpeechInputService(platform: FakeSttPlatform(), isWindows: true);
      final result = await svc.listenOnce();
      expect(result.ok, isFalse);
      expect(result.message, contains('Windows'));
      expect(svc.availabilityLabel, contains('Windows'));
    });

    test('initialize happens ONCE across repeated sessions', () async {
      final fake = FakeSttPlatform();
      final svc = SpeechInputService(platform: fake, isWindows: false);
      final r1 = await svc.listenOnce();
      final r2 = await svc.listenOnce();
      expect(r1.ok, isTrue);
      expect(r1.text, 'what is x39');
      expect(r2.ok, isTrue);
      expect(fake.initCalls, 1);
    });
  });

  group('VoiceModelManager (fake downloader)', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('kokoro_test_');
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    Future<void> writeSized(String path, int bytes) async {
      final f = File(path);
      final raf = await f.open(mode: FileMode.write);
      await raf.setPosition(bytes - 1);
      await raf.writeByte(0);
      await raf.close();
    }

    // v1.1.0: download() also verifies (hash) and unpacks. These tests
    // inject a pass-through verifier and a fake extractor that lays
    // down the model-file tree the real one would.
    Future<void> fakeExtract(String archive, String destDir) async {
      final dir =
          Directory('$destDir/${KokoroModelSource.extractedDirName}');
      await dir.create(recursive: true);
      for (final name in [
        KokoroModelSource.modelFileName,
        KokoroModelSource.voicesFileName,
        KokoroModelSource.tokensFileName,
      ]) {
        await File('${dir.path}/$name').writeAsString('fake');
      }
    }

    test('state transitions: not-downloaded -> downloading -> ready -> deleted',
        () async {
      final manager = VoiceModelManager(
        dirProvider: () async => tmp.path,
        verifier: (_) async => true,
        extractor: fakeExtract,
        downloader: (url, dest, onProgress) async {
          onProgress(0.5);
          await writeSized(dest, KokoroModelSource.expectedBytes);
          onProgress(1.0);
        },
      );
      await manager.refresh();
      expect(manager.state, VoiceModelState.notDownloaded);
      final ok = await manager.download();
      expect(ok, isTrue);
      expect(manager.state, VoiceModelState.ready);
      expect(manager.isReady, isTrue);
      await manager.deleteModel();
      expect(manager.state, VoiceModelState.notDownloaded);
    });

    test('wrong-size download lands in error state, not ready', () async {
      final manager = VoiceModelManager(
        dirProvider: () async => tmp.path,
        verifier: (_) async => true,
        extractor: fakeExtract,
        downloader: (url, dest, onProgress) async {
          await writeSized(dest, 1024); // truncated download
        },
      );
      final ok = await manager.download();
      expect(ok, isFalse);
      expect(manager.state, VoiceModelState.error);
      expect(manager.errorMessage, isNotEmpty);
    });

    test('downloader throwing lands in error state with a plain message',
        () async {
      final manager = VoiceModelManager(
        dirProvider: () async => tmp.path,
        verifier: (_) async => true,
        extractor: fakeExtract,
        downloader: (url, dest, onProgress) async =>
            throw Exception('no network'),
      );
      expect(await manager.download(), isFalse);
      expect(manager.state, VoiceModelState.error);
    });
  });

  group('VoiceService (fake TTS platform)', () {
    test('device engine lists voices; speak strips markup and reports renderer',
        () async {
      final tts = FakeTtsPlatform();
      final voice = fakeVoiceService(tts);
      final voices = await voice.listVoices();
      expect(voices.length, 2);
      expect(voices.first.engineId, 'device');
      final result = await voice.speak(
        '[warm] Hello there.',
        level: EmotionLevel.warm,
      );
      expect(result.spoken, isTrue);
      expect(tts.spoken.single, 'Hello there.');
      expect(result.renderedBy, contains('Device voice'));
      // Kokoro is a real engine in v1.1.0, but its voice file is not
      // downloaded in this fake setup — so it is unavailable, with an
      // honest reason, and the device engine speaks.
      expect(voice.kokoroEngine.isAvailable, isFalse);
      expect(
          voice.kokoroEngine.unavailableReason, contains('not been downloaded'));
      expect(voice.activeEngine.engineId, 'device');
      expect(voice.activeEngineLabel, 'Device voice');
    });

    test('urgent context: playful marker never reaches the TTS platform',
        () async {
      final tts = FakeTtsPlatform();
      final voice = fakeVoiceService(tts);
      await voice.speak(
        '[laugh] Warning words.',
        level: EmotionLevel.fullHearted,
        context: SpeechContext.urgent,
      );
      expect(tts.spoken.single, 'Warning words.');
    });
  });

  group('TranslationService (fakes)', () {
    test('pack bookkeeping: download / list / delete', () async {
      final engine = FakeTranslationEngine();
      final svc = TranslationService(engine: engine);
      expect(await svc.downloadPack('es'), isTrue);
      expect(svc.downloadedCodes, contains('es'));
      final packs = await svc.listPacks();
      expect(packs.firstWhere((p) => p.language.code == 'es').downloaded,
          isTrue);
      expect(packs.firstWhere((p) => p.language.code == 'fr').downloaded,
          isFalse);
      await svc.deletePack('es');
      expect(svc.downloadedCodes, isNot(contains('es')));
    });

    test('cascade: on-device success is tier 1', () async {
      final engine = FakeTranslationEngine();
      final svc = TranslationService(engine: engine);
      final r = await svc.translateWithCascade('Hello',
          fromCode: 'en', toCode: 'es');
      expect(r.tier, TranslationTier.onDevice);
      expect(r.text, '[es] Hello');
    });

    test('cascade order: on-device failure falls to cloud (tier 2)', () async {
      final engine = FakeTranslationEngine()..failTranslate = true;
      final cloud = FakeCloudTranslator();
      final svc = TranslationService(engine: engine, cloud: cloud);
      final r = await svc.translateWithCascade('Hello',
          fromCode: 'en', toCode: 'es');
      expect(r.tier, TranslationTier.cloud);
      expect(engine.calls, ['ondevice:en>es']);
      expect(cloud.calls, ['cloud:en>es']); // order: device first, cloud second
    });

    test('timeout path: slow on-device + unconfigured cloud = original preserved',
        () async {
      final engine = FakeTranslationEngine()
        ..delay = const Duration(milliseconds: 500);
      final svc = TranslationService(
        engine: engine,
        cloud: const NotConfiguredCloudTranslator(),
        onDeviceTimeout: const Duration(milliseconds: 50),
      );
      final r = await svc.translateWithCascade('Hello friend',
          fromCode: 'en', toCode: 'es');
      expect(r.tier, TranslationTier.failed);
      expect(r.usedOriginal, isTrue);
      expect(r.text, 'Hello friend');
      expect(r.message, contains("Couldn't translate"));
    });
  });

  group('ConversationTranslator (turn state machine)', () {
    ConversationTranslator makeConvo(
      FakeTranslationEngine engine, {
      CloudTranslator? cloud,
      Duration timeout = const Duration(seconds: 5),
    }) {
      final tts = FakeTtsPlatform();
      return ConversationTranslator(
        translation: TranslationService(
          engine: engine,
          cloud: cloud ?? const NotConfiguredCloudTranslator(),
          onDeviceTimeout: timeout,
        ),
        voice: fakeVoiceService(tts),
      );
    }

    test('turn appends with original + translation, side-coded', () async {
      final engine = FakeTranslationEngine();
      final convo = makeConvo(engine);
      final turn = await convo.processTurn(
        speaker: ConversationSide.a,
        inputText: 'Hello, how are you?',
        emotionLevel: EmotionLevel.warm,
        speakResult: false,
      );
      expect(convo.turns.length, 1);
      expect(turn.speaker, ConversationSide.a);
      expect(turn.originalText, 'Hello, how are you?');
      expect(turn.translatedText, '[es] Hello, how are you?');
      expect(turn.sourceCode, 'en');
      expect(turn.targetCode, 'es');
      expect(turn.failed, isFalse);
    });

    test('auto-detect flips the direction when the other language is heard',
        () async {
      final engine = FakeTranslationEngine()..detected = 'es';
      final convo = makeConvo(engine);
      final turn = await convo.processTurn(
        speaker: ConversationSide.a,
        inputText: 'Hola, ¿cómo estás?',
        emotionLevel: EmotionLevel.warm,
        speakResult: false,
      );
      expect(turn.sourceCode, 'es');
      expect(turn.targetCode, 'en');
    });

    test('timeout turn never hangs: original shown, failed flagged', () async {
      final engine = FakeTranslationEngine()
        ..delay = const Duration(milliseconds: 500);
      final convo = makeConvo(engine, timeout: const Duration(milliseconds: 50));
      final turn = await convo.processTurn(
        speaker: ConversationSide.b,
        inputText: 'Buenas tardes',
        emotionLevel: EmotionLevel.warm,
        speakResult: false,
      );
      expect(turn.failed, isTrue);
      expect(turn.translatedText, 'Buenas tardes');
      expect(convo.turns.length, 1);
    });

    test('compliance hits attach to the turn from the final-language text',
        () async {
      final engine = FakeTranslationEngine();
      final convo = makeConvo(engine);
      final turn = await convo.processTurn(
        speaker: ConversationSide.a,
        inputText: 'This cures everything',
        emotionLevel: EmotionLevel.warm,
        speakResult: false,
      );
      // Fake engine echoes the English inside the translation, so the
      // final-language scan must still catch "cures".
      expect(turn.complianceHits, isNotEmpty);
    });
  });
}
