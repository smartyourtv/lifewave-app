import 'dart:async';
import 'dart:io' show Directory, File;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'emotion.dart';

/// Voice output (SPEC §7.3) — ONE speech controller (PRE-BUILD-AUDIT §3:
/// all playback goes through a single controller that tracks completion
/// and interruption; fire-and-forget speak() is the Scout mid-sentence
/// cut-off bug class and is forbidden here).
///
/// Engines:
///  - [DeviceTtsEngine] (flutter_tts) — functional fallback, always
///    available. Emotion renders as prosody + brief voiced markers in
///    the SELECTED device voice (never a stock clip of another person).
///  - [KokoroEngine] — the preferred Scout voice path. In M2 this is an
///    integration STUB: see the class doc for the exact blocker. The
///    [VoiceModelManager] (download-after-install) is fully implemented
///    and tested; only synthesis/playback is stubbed.

class VoiceInfo {
  final String id; // engine-local voice identifier
  final String name; // display name
  final String engineId; // 'device' | 'kokoro'
  const VoiceInfo({
    required this.id,
    required this.name,
    required this.engineId,
  });
  @override
  String toString() => '$engineId:$id ($name)';
}

/// One TTS engine behind the single [VoiceService] controller.
abstract class VoiceEngine {
  String get engineId;
  String get displayName;
  bool get isAvailable;

  /// Why this engine cannot be used right now ('' when available).
  String get unavailableReason;
  Future<List<VoiceInfo>> listVoices();
  Future<void> speakSegment(
    String text, {
    required ProsodyParams prosody,
    VoiceInfo? voice,
  });
  Future<void> stop();
}

/// Outcome of one speak request through the controller.
class SpeakResult {
  final bool spoken;
  final String renderedBy; // e.g. "Device voice (en-US …)" — diagnostics/UI
  final String message; // plain-language note when not spoken
  const SpeakResult({
    required this.spoken,
    required this.renderedBy,
    this.message = '',
  });
}

// ---------------------------------------------------------------------------
// Kokoro model management (download-after-install, SPEC §1/§7.3)
// ---------------------------------------------------------------------------

/// Kokoro model source — sherpa-onnx official release assets.
///  - Package: kokoro-int8-multi-lang-v1_0 (sherpa-onnx TTS models
///    release) — the int8 multi-language Kokoro v1.0 build.
///  - URL: https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-multi-lang-v1_0.tar.bz2
///  - Expected size: ~132 MB (131.8 MB archive, verified from the
///    sherpa-onnx release listing during the M2 build, 2026-10-17).
///  - LICENSE FINDING (M2, 2026-10-17): the Kokoro-82M model
///    (hexgrad/Kokoro-82M) is released under the Apache License 2.0,
///    which permits commercial use and redistribution — including
///    redistribution-by-download from the official source into the app,
///    with the license/attribution retained. sherpa-onnx itself is also
///    Apache-2.0. Download-after-install is therefore permitted; the app
///    downloads from the official sherpa-onnx release (above), never a
///    third-party mirror.
abstract class KokoroModelSource {
  static const String downloadUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-multi-lang-v1_0.tar.bz2';
  static const int expectedBytes = 138200000; // ~131.8 MiB archive

  /// Tolerance for the size check: the archive must land within ±10% of
  /// the expected size (guards truncated/corrupt downloads without
  /// bricking on a re-packed official asset). A published checksum is
  /// not provided for this asset, so size is the integrity check in M2.
  static const double sizeTolerance = 0.10;
  static const String archiveName = 'kokoro-model.tar.bz2';
  static const String markerName = 'kokoro-model.ready';
}

enum VoiceModelState { notDownloaded, downloading, ready, error }

/// Downloads a file to [destPath], reporting progress 0..1.
/// Injectable so the manager's state machine is unit-tested with fakes.
typedef ModelDownloader = Future<void> Function(
  String url,
  String destPath,
  void Function(double progress) onProgress,
);

/// Resolves the directory model files live in. Injectable for tests.
typedef ModelDirProvider = Future<String> Function();

Future<void> _httpDownloader(
  String url,
  String destPath,
  void Function(double) onProgress,
) async {
  final request = http.Request('GET', Uri.parse(url));
  final response = await http.Client()
      .send(request)
      .timeout(const Duration(minutes: 20));
  if (response.statusCode != 200) {
    throw Exception('Download failed (HTTP ${response.statusCode})');
  }
  final total = response.contentLength ?? KokoroModelSource.expectedBytes;
  var received = 0;
  final sink = File(destPath).openWrite();
  try {
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress((received / total).clamp(0.0, 1.0));
    }
  } finally {
    await sink.close();
  }
}

Future<String> _appDocsModelDir() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/voice-model');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir.path;
}

/// Voice-model lifecycle: not-downloaded / downloading / ready / error,
/// reported honestly everywhere (Settings, Diagnostics). A missing model
/// is a NORMAL state, never an exception path (PRE-BUILD-AUDIT §3).
class VoiceModelManager {
  final ModelDownloader _downloader;
  final ModelDirProvider _dirProvider;
  final String downloadUrl;

  VoiceModelState _state = VoiceModelState.notDownloaded;
  double _progress = 0;
  String _errorMessage = '';
  int _downloadedBytes = 0;

  VoiceModelManager({
    ModelDownloader? downloader,
    ModelDirProvider? dirProvider,
    this.downloadUrl = KokoroModelSource.downloadUrl,
  })  : _downloader = downloader ?? _httpDownloader,
        _dirProvider = dirProvider ?? _appDocsModelDir;

  VoiceModelState get state => _state;
  double get progress => _progress;
  String get errorMessage => _errorMessage;
  int get downloadedBytes => _downloadedBytes;
  bool get isReady => _state == VoiceModelState.ready;

  String get stateLabel {
    switch (_state) {
      case VoiceModelState.notDownloaded:
        return 'Not downloaded';
      case VoiceModelState.downloading:
        return 'Downloading… ${(_progress * 100).round()}%';
      case VoiceModelState.ready:
        return 'Ready';
      case VoiceModelState.error:
        return 'Download problem';
    }
  }

  Future<String> _archivePath() async =>
      '${await _dirProvider()}/${KokoroModelSource.archiveName}';
  Future<String> _markerPath() async =>
      '${await _dirProvider()}/${KokoroModelSource.markerName}';

  /// Refreshes [state] from what is actually on disk.
  Future<void> refresh() async {
    try {
      final marker = File(await _markerPath());
      final archive = File(await _archivePath());
      if (await marker.exists() && await archive.exists()) {
        _downloadedBytes = await archive.length();
        _state = VoiceModelState.ready;
      } else {
        _state = VoiceModelState.notDownloaded;
        _downloadedBytes = 0;
      }
    } catch (_) {
      _state = VoiceModelState.notDownloaded;
    }
  }

  bool _sizeOk(int bytes) {
    const expected = KokoroModelSource.expectedBytes;
    return (bytes - expected).abs() <= expected * KokoroModelSource.sizeTolerance;
  }

  Future<bool> download() async {
    if (_state == VoiceModelState.downloading) return false;
    _state = VoiceModelState.downloading;
    _progress = 0;
    _errorMessage = '';
    try {
      final archivePath = await _archivePath();
      await _downloader(downloadUrl, archivePath, (p) => _progress = p);
      final bytes = await File(archivePath).length();
      if (!_sizeOk(bytes)) {
        _state = VoiceModelState.error;
        _errorMessage =
            'The downloaded voice file looks incomplete ($bytes bytes). '
            'Delete it and try again on a good connection.';
        return false;
      }
      _downloadedBytes = bytes;
      await File(await _markerPath()).writeAsString('kokoro-multi-lang-v1_0');
      _state = VoiceModelState.ready;
      _progress = 1;
      return true;
    } catch (e) {
      _state = VoiceModelState.error;
      _errorMessage = 'The voice download did not finish. Check your '
          'internet connection and try again.';
      debugPrint('VoiceModelManager download error: $e');
      return false;
    }
  }

  Future<void> deleteModel() async {
    try {
      final a = File(await _archivePath());
      if (await a.exists()) await a.delete();
      final m = File(await _markerPath());
      if (await m.exists()) await m.delete();
    } catch (_) {
      // Deletion is best-effort; state still resets honestly below.
    }
    _downloadedBytes = 0;
    _progress = 0;
    _state = VoiceModelState.notDownloaded;
  }
}

// ---------------------------------------------------------------------------
// Device TTS engine (functional fallback)
// ---------------------------------------------------------------------------

/// Thin seam over flutter_tts so tests can substitute a fake.
abstract class TtsPlatform {
  Future<void> setRate(double rate);
  Future<void> setPitch(double pitch);
  Future<void> setVolume(double volume);
  Future<void> setVoice(Map<String, String> voice);
  Future<dynamic> getVoices();
  Future<void> speak(String text);
  Future<void> stop();
  void setCompletionHandler(void Function() handler);
}

class FlutterTtsPlatform implements TtsPlatform {
  final FlutterTts _tts = FlutterTts();
  FlutterTtsPlatform() {
    // Completion tracking ON — the audit's single-controller rule.
    _tts.awaitSpeakCompletion(true);
  }
  @override
  Future<void> setRate(double rate) async => _tts.setSpeechRate(rate);
  @override
  Future<void> setPitch(double pitch) async => _tts.setPitch(pitch);
  @override
  Future<void> setVolume(double volume) async => _tts.setVolume(volume);
  @override
  Future<void> setVoice(Map<String, String> voice) async =>
      _tts.setVoice(voice);
  @override
  Future<dynamic> getVoices() => _tts.getVoices;
  @override
  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }
  @override
  void setCompletionHandler(void Function() handler) =>
      _tts.setCompletionHandler(handler);
}

class DeviceTtsEngine implements VoiceEngine {
  final TtsPlatform _platform;
  DeviceTtsEngine({TtsPlatform? platform})
      : _platform = platform ?? FlutterTtsPlatform();

  @override
  String get engineId => 'device';
  @override
  String get displayName => 'Device voice';
  @override
  bool get isAvailable => true; // flutter_tts ships on every target here
  @override
  String get unavailableReason => '';

  @override
  Future<List<VoiceInfo>> listVoices() async {
    try {
      final raw = await _platform.getVoices();
      final voices = <VoiceInfo>[];
      if (raw is List) {
        for (final v in raw) {
          if (v is Map) {
            final name = '${v['name'] ?? ''}';
            final locale = '${v['locale'] ?? ''}';
            if (name.isEmpty) continue;
            voices.add(VoiceInfo(
              id: name,
              name: locale.isEmpty ? name : '$name ($locale)',
              engineId: engineId,
            ));
          }
        }
      }
      return voices;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> speakSegment(
    String text, {
    required ProsodyParams prosody,
    VoiceInfo? voice,
  }) async {
    await _platform.setRate(prosody.rate);
    await _platform.setPitch(prosody.pitch);
    await _platform.setVolume(prosody.volume);
    if (voice != null && voice.engineId == engineId) {
      try {
        await _platform.setVoice({'name': voice.id, 'locale': ''});
      } catch (_) {
        // Voice vanished: keep speaking with the device default voice.
      }
    }
    // Breaths on this engine are rendered as the varied pauses the
    // mapper folded into pauseBeforeMs (device TTS has no breath
    // synthesis); the marker syllables ARE spoken, in this voice.
    if (prosody.pauseBeforeMs > 0) {
      await Future<void>.delayed(
          Duration(milliseconds: prosody.pauseBeforeMs));
    }
    final spokenText =
        prosody.marker.isEmpty ? text : '${prosody.marker}$text';
    await _platform.speak(spokenText);
    if (prosody.pauseAfterMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: prosody.pauseAfterMs));
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _platform.stop();
    } catch (_) {
      // Already silent — stopping must never throw into the UI.
    }
  }
}

// ---------------------------------------------------------------------------
// Kokoro engine — INTEGRATION STUB (honest, labeled)
// ---------------------------------------------------------------------------

/// Kokoro via sherpa_onnx — STUB in M2. Exact blocker (measured during
/// the M2 build, 2026-10-17): `sherpa_onnx` 1.10.30 RESOLVES against
/// Flutter 3.24.5 / Dart 3.5.4, but (a) its Android platform package
/// resolved to a MISMATCHED version (sherpa_onnx_android 1.12.36;
/// iOS/macOS/Linux/Windows to 1.13.8), and (b) its bundled native
/// runtime is 97 MB of .so libraries across the four Android ABIs
/// (arm64-v8a 24 MB, armeabi-v7a 17 MB, x86 28 MB, x86_64 28 MB —
/// libonnxruntime.so alone is 19 MB on arm64). A universal release APK
/// would grow from ~21.5 MB (M1) to roughly 60-80 MB, far beyond the
/// ~30 MB installer budget SPEC §1 makes non-negotiable — before the
/// ~132 MB model download is even counted. Per the M2 brief: ship
/// DeviceTts functional + this stub, and report the blocker — do NOT
/// fake synthesis.
///
/// What IS real here: the [VoiceModelManager] download/verify/delete
/// lifecycle above, the shared [VoiceEngine] interface, the full emotion
/// prosody mapping, and the Kokoro voice catalogue below — so enabling
/// the engine later is: add the plugin (accepting the size cost, e.g.
/// via ABI-split APKs), synthesize PCM with OfflineTts, play it through
/// an audio sink, and flip [isAvailable] to follow the model state.
class KokoroEngine implements VoiceEngine {
  final VoiceModelManager modelManager;
  KokoroEngine(this.modelManager);

  /// Documented stub reason, surfaced verbatim in Settings/Diagnostics.
  static const String stubReason =
      'The Kokoro voice engine is not included in this build: its '
      'on-device runtime would make the app download much larger than '
      'the promised size. The device voice is used instead. The Kokoro '
      'voice file can still be downloaded below so the app is ready '
      'when the engine ships.';

  @override
  String get engineId => 'kokoro';
  @override
  String get displayName => 'Kokoro voice (Scout voice)';
  @override
  bool get isAvailable => false;
  @override
  String get unavailableReason => stubReason;

  /// The standard Kokoro multi-lang v1.0 speaker ids (speaker order in
  /// the sherpa-onnx package). Listed so the voice picker can show what
  /// the downloaded model will offer; selection is stored per-user.
  static const List<String> kokoroVoiceIds = [
    'af_heart', 'af_bella', 'af_sarah', 'af_nicole', 'af_sky',
    'am_michael', 'am_adam', 'am_eric', 'am_liam', 'am_puck',
    'bf_emma', 'bf_alice', 'bf_lily', 'bm_george', 'bm_daniel', 'bm_lewis',
    'jf_alpha', 'jm_kumo', 'zf_xiaoxiao', 'zf_xiaoyi', 'zm_yunyang',
    'zm_yunjian', 'ff_siwis', 'if_sara', 'im_nicola',
  ];

  @override
  Future<List<VoiceInfo>> listVoices() async {
    if (!modelManager.isReady) return const [];
    return kokoroVoiceIds
        .map((id) => VoiceInfo(id: id, name: id, engineId: engineId))
        .toList(growable: false);
  }

  @override
  Future<void> speakSegment(
    String text, {
    required ProsodyParams prosody,
    VoiceInfo? voice,
  }) async {
    // Never called by VoiceService while isAvailable is false. Throwing
    // (instead of silently "speaking") is the honest failure mode.
    throw StateError('KokoroEngine is a stub in this build: $stubReason');
  }

  @override
  Future<void> stop() async {}
}

// ---------------------------------------------------------------------------
// The single speech controller
// ---------------------------------------------------------------------------

/// THE speech controller. Every spoken answer, self-test line and
/// translator turn goes through here — one place owns interruption,
/// completion and engine choice (audit rule).
class VoiceService {
  final DeviceTtsEngine deviceEngine;
  final KokoroEngine kokoroEngine;
  final ProsodyMapper _mapper = const ProsodyMapper();

  bool _isSpeaking = false;
  int _utteranceSerial = 0; // interruption token: a stop() invalidates pending segments
  String _lastRenderedBy = 'Nothing spoken yet';

  VoiceService({
    DeviceTtsEngine? deviceEngine,
    KokoroEngine? kokoroEngine,
    VoiceModelManager? modelManager,
  })  : deviceEngine = deviceEngine ?? DeviceTtsEngine(),
        kokoroEngine =
            kokoroEngine ?? KokoroEngine(modelManager ?? VoiceModelManager());

  bool get isSpeaking => _isSpeaking;
  String get lastRenderedBy => _lastRenderedBy;

  /// The engine that will actually render speech right now.
  VoiceEngine get activeEngine =>
      kokoroEngine.isAvailable ? kokoroEngine : deviceEngine;

  String get activeEngineLabel => activeEngine.isAvailable &&
          activeEngine.engineId == 'kokoro'
      ? 'Kokoro voice'
      : 'Device voice (Kokoro engine not in this build — see Settings)';

  Future<List<VoiceInfo>> listVoices() async {
    final all = <VoiceInfo>[];
    all.addAll(await kokoroEngine.listVoices());
    all.addAll(await deviceEngine.listVoices());
    return all;
  }

  /// Speaks [markedText] (emotion markup allowed — it is parsed OUT of
  /// anything displayed by the caller via [EmotionParser]).
  Future<SpeakResult> speak(
    String markedText, {
    required EmotionLevel level,
    VoiceInfo? voice,
    SpeechContext context = SpeechContext.normal,
  }) async {
    final parsed = EmotionParser.parse(markedText);
    final effectiveContext =
        context == SpeechContext.urgent ? context : parsed.context;
    if (parsed.segments.isEmpty) {
      return SpeakResult(
        spoken: false,
        renderedBy: _lastRenderedBy,
        message: 'There is nothing to say out loud.',
      );
    }
    final engine = activeEngine;
    final selectedVoice = (voice != null && voice.engineId == engine.engineId)
        ? voice
        : null;
    await stop(); // new utterance interrupts the old one — controller rule
    final serial = ++_utteranceSerial;
    _isSpeaking = true;
    try {
      for (var i = 0; i < parsed.segments.length; i++) {
        if (serial != _utteranceSerial) break; // interrupted
        final segment = parsed.segments[i];
        final prosody = _mapper.map(
          emotion: segment.emotion,
          level: level,
          context: effectiveContext,
          seed: variationSeedFor(text: segment.text, segmentIndex: i),
          segmentText: segment.text,
        );
        await engine.speakSegment(
          segment.text,
          prosody: prosody,
          voice: selectedVoice,
        );
      }
      _lastRenderedBy = selectedVoice == null
          ? '${engine.displayName} (device default voice)'
          : '${engine.displayName} • ${selectedVoice.name}';
      return SpeakResult(spoken: true, renderedBy: _lastRenderedBy);
    } catch (e) {
      debugPrint('VoiceService speak error: $e');
      return SpeakResult(
        spoken: false,
        renderedBy: _lastRenderedBy,
        message: 'The voice could not speak just now. The words are on '
            'the screen instead.',
      );
    } finally {
      if (serial == _utteranceSerial) _isSpeaking = false;
    }
  }

  Future<void> stop() async {
    _utteranceSerial++;
    _isSpeaking = false;
    await deviceEngine.stop();
  }
}
