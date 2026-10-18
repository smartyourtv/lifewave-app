import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifewave_app/services/emotion.dart';
import 'package:lifewave_app/services/voice_service.dart';

// ---------------------------------------------------------------------------
// Fakes for the v1.1.0 Kokoro seams (synthesis + PCM sink + manager I/O)
// ---------------------------------------------------------------------------

class FakeSynthesizer implements KokoroSynthesizer {
  bool _initialized = false;
  bool failInit = false;
  String? initializedDir;
  final List<({String text, int speakerId, double speed})> calls = [];

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize(String modelDir) async {
    if (failInit) throw StateError('fake native load failure');
    initializedDir = modelDir;
    _initialized = true;
  }

  @override
  Future<KokoroAudio> synthesize(
    String text, {
    required int speakerId,
    required double speed,
  }) async {
    calls.add((text: text, speakerId: speakerId, speed: speed));
    // 0.1 s of silence-ish samples at Kokoro's 24 kHz.
    return KokoroAudio(Float32List(2400)..fillRange(0, 2400, 0.25), 24000);
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
  }
}

class FakePcmPlayer implements PcmPlayer {
  final List<({int sampleCount, int sampleRate, double volume, double pitch})>
      plays = [];
  int stopCalls = 0;

  @override
  Future<void> play(
    Float32List samples, {
    required int sampleRate,
    required double volume,
    required double pitch,
  }) async {
    plays.add((
      sampleCount: samples.length,
      sampleRate: sampleRate,
      volume: volume,
      pitch: pitch,
    ));
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

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
  Future<dynamic> getVoices() async => const [];
  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {}
  @override
  void setCompletionHandler(void Function() handler) {}
}

/// Lays down the extracted model tree the real extractor would.
Future<void> fakeExtractTree(String archive, String destDir) async {
  final dir = Directory('$destDir/${KokoroModelSource.extractedDirName}');
  await dir.create(recursive: true);
  for (final name in [
    KokoroModelSource.modelFileName,
    KokoroModelSource.voicesFileName,
    KokoroModelSource.tokensFileName,
  ]) {
    await File('${dir.path}/$name').writeAsString('fake');
  }
}

Future<void> writeSizedFile(String path, int bytes) async {
  final raf = await File(path).open(mode: FileMode.write);
  await raf.setPosition(bytes - 1);
  await raf.writeByte(0);
  await raf.close();
}

ProsodyParams flatProsody({String marker = ''}) => ProsodyParams(
      rate: 0.5,
      pitch: 1.0,
      volume: 0.95,
      pauseBeforeMs: 0,
      pauseAfterMs: 0,
      marker: marker,
      canRenderMarker: marker.isNotEmpty,
      breathBefore: BreathSpec.none,
      breathAfter: BreathSpec.none,
      effectiveEmotion: Emotion.neutral,
    );

void main() {
  group('VoiceModelManager — verification + extraction (v1.1.0)', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('kokoro_m6_');
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    VoiceModelManager managerWith({
      required Future<void> Function(String, String, void Function(double))
          downloader,
      bool verifyOk = true,
      ModelExtractor? extractor,
    }) =>
        VoiceModelManager(
          dirProvider: () async => tmp.path,
          downloader: downloader,
          verifier: (_) async => verifyOk,
          extractor: extractor ?? fakeExtractTree,
        );

    test('hash mismatch -> error state, archive removed, never ready',
        () async {
      final manager = managerWith(
        verifyOk: false,
        downloader: (url, dest, onProgress) async {
          await writeSizedFile(dest, KokoroModelSource.expectedBytes);
        },
      );
      final ok = await manager.download();
      expect(ok, isFalse);
      expect(manager.state, VoiceModelState.error);
      expect(manager.errorMessage, contains('safety check'));
      final archive =
          File('${tmp.path}/${KokoroModelSource.archiveName}');
      expect(await archive.exists(), isFalse);
      expect(
          await File('${tmp.path}/${KokoroModelSource.markerName}').exists(),
          isFalse);
    });

    test('extraction failure -> error state, no marker', () async {
      final manager = managerWith(
        downloader: (url, dest, onProgress) async {
          await writeSizedFile(dest, KokoroModelSource.expectedBytes);
        },
        extractor: (archive, destDir) async =>
            throw Exception('corrupt archive'),
      );
      expect(await manager.download(), isFalse);
      expect(manager.state, VoiceModelState.error);
    });

    test('extraction producing no model files -> error state', () async {
      final manager = managerWith(
        downloader: (url, dest, onProgress) async {
          await writeSizedFile(dest, KokoroModelSource.expectedBytes);
        },
        extractor: (archive, destDir) async {}, // unpacks "nothing"
      );
      expect(await manager.download(), isFalse);
      expect(manager.state, VoiceModelState.error);
      expect(manager.errorMessage, contains('unpacked'));
    });

    test('valid archive already on disk is unpacked, NOT re-downloaded',
        () async {
      await writeSizedFile(
        '${tmp.path}/${KokoroModelSource.archiveName}',
        KokoroModelSource.expectedBytes,
      );
      var downloads = 0;
      final manager = managerWith(
        downloader: (url, dest, onProgress) async {
          downloads++;
        },
      );
      await manager.refresh();
      expect(manager.state, VoiceModelState.notDownloaded);
      expect(await manager.download(), isTrue);
      expect(downloads, 0);
      expect(manager.state, VoiceModelState.ready);
    });

    test('refresh: marker + unpacked model = ready (post-restart state)',
        () async {
      await fakeExtractTree('unused', tmp.path);
      await File('${tmp.path}/${KokoroModelSource.markerName}')
          .writeAsString('kokoro-multi-lang-v1_0');
      final manager = managerWith(
        downloader: (url, dest, onProgress) async {},
      );
      await manager.refresh();
      expect(manager.state, VoiceModelState.ready);
      expect(manager.isReady, isTrue);
    });

    test('refresh: v1.0 state (marker + archive, never unpacked) is NOT ready',
        () async {
      await writeSizedFile(
        '${tmp.path}/${KokoroModelSource.archiveName}',
        KokoroModelSource.expectedBytes,
      );
      await File('${tmp.path}/${KokoroModelSource.markerName}')
          .writeAsString('kokoro-multi-lang-v1_0');
      final manager = managerWith(
        downloader: (url, dest, onProgress) async {},
      );
      await manager.refresh();
      expect(manager.state, VoiceModelState.notDownloaded);
      expect(manager.isReady, isFalse);
    });

    test('deleteModel removes the unpacked tree as well', () async {
      final manager = managerWith(
        downloader: (url, dest, onProgress) async {
          await writeSizedFile(dest, KokoroModelSource.expectedBytes);
        },
      );
      expect(await manager.download(), isTrue);
      final extracted =
          Directory('${tmp.path}/${KokoroModelSource.extractedDirName}');
      expect(await extracted.exists(), isTrue);
      await manager.deleteModel();
      expect(await extracted.exists(), isFalse);
      expect(manager.state, VoiceModelState.notDownloaded);
    });

    test('pinned integrity constants match the official asset record', () {
      expect(KokoroModelSource.expectedBytes, 132303094);
      expect(KokoroModelSource.expectedSha256,
          '4c3052abaa60943a341f193888cf6abd68787dae6ab8ae5c925a706caa247e4e');
    });
  });

  group('KokoroEngine (fake synthesizer + fake PCM player)', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('kokoro_eng_');
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    Future<VoiceModelManager> readyManager() async {
      final manager = VoiceModelManager(
        dirProvider: () async => tmp.path,
        downloader: (url, dest, onProgress) async {
          await writeSizedFile(dest, KokoroModelSource.expectedBytes);
        },
        verifier: (_) async => true,
        extractor: fakeExtractTree,
      );
      expect(await manager.download(), isTrue);
      return manager;
    }

    test('unavailable until the model is ready; reason is honest', () async {
      final manager = VoiceModelManager(
        dirProvider: () async => tmp.path,
        downloader: (url, dest, onProgress) async {},
      );
      final engine = KokoroEngine(
        manager,
        synthesizer: FakeSynthesizer(),
        player: FakePcmPlayer(),
      );
      expect(engine.isAvailable, isFalse);
      expect(engine.unavailableReason, contains('not been downloaded'));
      expect(await engine.ensureReady(), isFalse);
      expect(await engine.listVoices(), isEmpty);
    });

    test('speak: marker synthesized in-voice, prosody applied, sid resolved',
        () async {
      final synth = FakeSynthesizer();
      final player = FakePcmPlayer();
      final engine = KokoroEngine(
        await readyManager(),
        synthesizer: synth,
        player: player,
      );
      expect(engine.isAvailable, isTrue);
      expect(engine.unavailableReason, isEmpty);
      final voices = await engine.listVoices();
      expect(voices.length, KokoroEngine.kokoroVoiceIds.length);
      expect(voices.first.id, 'af_heart');

      await engine.speakSegment(
        'Hello there.',
        prosody: flatProsody(marker: 'heh heh, '),
        voice: const VoiceInfo(
            id: 'am_michael', name: 'am_michael', engineId: 'kokoro'),
      );
      expect(synth.initializedDir,
          '${tmp.path}/${KokoroModelSource.extractedDirName}');
      expect(synth.calls.single.text, 'heh heh, Hello there.');
      // 'am_michael' is index 5 in the catalogue.
      expect(synth.calls.single.speakerId, 5);
      // rate 0.5 (device scale) -> sherpa speed 1.0 at pitch 1.0.
      expect(synth.calls.single.speed, 1.0);
      expect(player.plays.single.sampleCount, 2400);
      expect(player.plays.single.sampleRate, 24000);
      expect(player.plays.single.pitch, 1.0);
      expect(player.plays.single.volume, 0.95);
    });

    test('pitch is applied at the sink and speed compensated', () async {
      final synth = FakeSynthesizer();
      final player = FakePcmPlayer();
      final engine = KokoroEngine(
        await readyManager(),
        synthesizer: synth,
        player: player,
      );
      await engine.speakSegment(
        'Warmer words.',
        prosody: const ProsodyParams(
          rate: 0.5,
          pitch: 1.2,
          volume: 0.9,
          pauseBeforeMs: 0,
          pauseAfterMs: 0,
          marker: '',
          canRenderMarker: false,
          breathBefore: BreathSpec.none,
          breathAfter: BreathSpec.none,
          effectiveEmotion: Emotion.warm,
        ),
      );
      // speed = (0.5 * 2) / 1.2 = 0.833… so duration stays natural while
      // the sink plays back at 1.2x rate (pitch up).
      expect(synth.calls.single.speed, closeTo(1.0 / 1.2, 0.001));
      expect(player.plays.single.pitch, 1.2);
    });

    test('engine start failure latches: unavailable + honest reason',
        () async {
      final synth = FakeSynthesizer()..failInit = true;
      final engine = KokoroEngine(
        await readyManager(),
        synthesizer: synth,
        player: FakePcmPlayer(),
      );
      expect(engine.isAvailable, isTrue); // model ready, start not tried yet
      expect(await engine.ensureReady(), isFalse);
      expect(engine.isAvailable, isFalse);
      expect(engine.unavailableReason, contains('could not start'));
    });

    test('stop() cuts the PCM player', () async {
      final player = FakePcmPlayer();
      final engine = KokoroEngine(
        await readyManager(),
        synthesizer: FakeSynthesizer(),
        player: player,
      );
      await engine.stop();
      expect(player.stopCalls, 1);
    });
  });

  group('VoiceService — Kokoro integration', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('kokoro_svc_');
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    Future<VoiceModelManager> readyManager() async {
      final manager = VoiceModelManager(
        dirProvider: () async => tmp.path,
        downloader: (url, dest, onProgress) async {
          await writeSizedFile(dest, KokoroModelSource.expectedBytes);
        },
        verifier: (_) async => true,
        extractor: fakeExtractTree,
      );
      expect(await manager.download(), isTrue);
      return manager;
    }

    VoiceService serviceWith({
      required FakeTtsPlatform tts,
      required VoiceModelManager manager,
      required KokoroSynthesizer synth,
      required FakePcmPlayer player,
    }) =>
        VoiceService(
          deviceEngine: DeviceTtsEngine(platform: tts),
          kokoroEngine:
              KokoroEngine(manager, synthesizer: synth, player: player),
        );

    test('when Kokoro is ready it renders, and says so', () async {
      final player = FakePcmPlayer();
      final svc = serviceWith(
        tts: FakeTtsPlatform(),
        manager: await readyManager(),
        synth: FakeSynthesizer(),
        player: player,
      );
      expect(svc.activeEngine.engineId, 'kokoro');
      expect(svc.activeEngineLabel, 'Kokoro voice');
      final result = await svc.speak(
        '[warm] Good morning.',
        level: EmotionLevel.warm,
      );
      expect(result.spoken, isTrue);
      expect(result.renderedBy, contains('Kokoro voice'));
      expect(player.plays, isNotEmpty);
    });

    test('Kokoro start failure falls back to the device voice, honestly',
        () async {
      final tts = FakeTtsPlatform();
      final svc = serviceWith(
        tts: tts,
        manager: await readyManager(),
        synth: FakeSynthesizer()..failInit = true,
        player: FakePcmPlayer(),
      );
      final result = await svc.speak(
        'Hello there.',
        level: EmotionLevel.warm,
      );
      expect(result.spoken, isTrue);
      expect(result.renderedBy, contains('Device voice'));
      expect(tts.spoken.single, 'Hello there.');
      // And the label now honestly reports the device voice.
      expect(svc.activeEngineLabel, 'Device voice');
      expect(svc.activeEngine.engineId, 'device');
    });
  });

  group('pcm16LeFromFloat', () {
    test('scales by volume, clamps, little-endian', () {
      final bytes = pcm16LeFromFloat(
        Float32List.fromList([0.0, 0.5, -0.5, 2.0, -2.0]),
        0.5,
      );
      final data = ByteData.sublistView(bytes);
      expect(data.getInt16(0, Endian.little), 0);
      expect(data.getInt16(2, Endian.little), (0.25 * 32767).round());
      expect(data.getInt16(4, Endian.little), (-0.25 * 32767).round());
      expect(data.getInt16(6, Endian.little), 32767); // clamped
      expect(data.getInt16(8, Endian.little), -32767); // clamped
    });
  });
}
