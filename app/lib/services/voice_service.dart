import 'dart:async';
import 'dart:io' show Directory, File;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

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
///  - [KokoroEngine] — the preferred Scout voice path (v1.1.0): real
///    sherpa-onnx Kokoro synthesis → PCM playback, once the voice file
///    has been downloaded, hash-verified and unpacked by
///    [VoiceModelManager] (download-after-install). Until then — or if
///    the engine cannot start on the device — the device voice speaks
///    and every surface says so.

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
///  - Exact size: 132,303,094 bytes and SHA-256 below — both measured
///    from the official release asset itself on 2026-10-17 (v1.1.0).
///    No checksum is published upstream, so the app pins the hash of
///    the asset it was built against: if upstream ever re-packs the
///    asset, the check fails honestly (error state, retry advice)
///    until an app update pins the new hash — never a silent accept.
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
  static const int expectedBytes = 132303094;

  /// SHA-256 of the official archive, pinned at build time (see above).
  static const String expectedSha256 =
      '4c3052abaa60943a341f193888cf6abd68787dae6ab8ae5c925a706caa247e4e';

  /// First-pass sanity tolerance around [expectedBytes] (a truncated
  /// download fails here before the hash is even computed).
  static const double sizeTolerance = 0.10;
  static const String archiveName = 'kokoro-model.tar.bz2';
  static const String markerName = 'kokoro-model.ready';

  /// Layout of the unpacked archive (verified against the asset):
  /// `<model dir>/kokoro-int8-multi-lang-v1_0/{model.int8.onnx,
  /// voices.bin, tokens.txt, lexicon-*.txt, espeak-ng-data/}`.
  static const String extractedDirName = 'kokoro-int8-multi-lang-v1_0';
  static const String modelFileName = 'model.int8.onnx';
  static const String voicesFileName = 'voices.bin';
  static const String tokensFileName = 'tokens.txt';
  static const List<String> lexiconFileNames = [
    'lexicon-us-en.txt',
    'lexicon-gb-en.txt',
  ];
  static const String dataDirName = 'espeak-ng-data';
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

/// Verifies a downloaded archive's integrity. Injectable for tests.
/// The real check is the pinned SHA-256 (see [KokoroModelSource]).
typedef ModelVerifier = Future<bool> Function(String archivePath);

/// Unpacks the verified archive into [destDir]. Injectable for tests.
typedef ModelExtractor = Future<void> Function(
  String archivePath,
  String destDir,
);

Future<bool> _sha256Verifier(String archivePath) async {
  final file = File(archivePath);
  if (!await file.exists()) return false;
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString() == KokoroModelSource.expectedSha256;
}

Future<void> _archiveExtractor(String archivePath, String destDir) async {
  // bzip2 + tar over ~132 MB must not block the UI isolate.
  await Isolate.run(() => extractFileToDisk(archivePath, destDir));
}

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
///
/// "Ready" (v1.1.0) means the FULL path has completed: archive
/// downloaded → size sane → SHA-256 verified → unpacked → model files
/// present on disk. (In v1.0 the manager stopped at "archive present"
/// because no engine consumed the files; the marker alone no longer
/// counts as ready.)
class VoiceModelManager {
  final ModelDownloader _downloader;
  final ModelDirProvider _dirProvider;
  final ModelVerifier _verifier;
  final ModelExtractor _extractor;
  final String downloadUrl;

  VoiceModelState _state = VoiceModelState.notDownloaded;
  double _progress = 0;
  String _errorMessage = '';
  int _downloadedBytes = 0;
  bool _extracting = false;

  VoiceModelManager({
    ModelDownloader? downloader,
    ModelDirProvider? dirProvider,
    ModelVerifier? verifier,
    ModelExtractor? extractor,
    this.downloadUrl = KokoroModelSource.downloadUrl,
  })  : _downloader = downloader ?? _httpDownloader,
        _dirProvider = dirProvider ?? _appDocsModelDir,
        _verifier = verifier ?? _sha256Verifier,
        _extractor = extractor ?? _archiveExtractor;

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
        return _extracting
            ? 'Preparing the voice…'
            : 'Downloading… ${(_progress * 100).round()}%';
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

  /// The directory the model unpacks into (whether or not it exists).
  Future<String> extractedDir() async =>
      '${await _dirProvider()}/${KokoroModelSource.extractedDirName}';

  Future<bool> _modelTreeOk() async {
    final dir = await extractedDir();
    for (final name in [
      KokoroModelSource.modelFileName,
      KokoroModelSource.voicesFileName,
      KokoroModelSource.tokensFileName,
    ]) {
      if (!await File('$dir/$name').exists()) return false;
    }
    return true;
  }

  /// Refreshes [state] from what is actually on disk. Ready requires the
  /// marker AND the unpacked model file — a v1.0 install (marker +
  /// archive, never unpacked) reads as not-downloaded here, and
  /// [download] then unpacks the archive it already has instead of
  /// fetching it again.
  Future<void> refresh() async {
    if (_state == VoiceModelState.downloading) return;
    try {
      final marker = File(await _markerPath());
      final archive = File(await _archivePath());
      if (await archive.exists()) {
        _downloadedBytes = await archive.length();
      }
      if (await marker.exists() && await _modelTreeOk()) {
        _state = VoiceModelState.ready;
      } else {
        _state = VoiceModelState.notDownloaded;
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
    _extracting = false;
    try {
      final archivePath = await _archivePath();
      final archiveFile = File(archivePath);
      // Reuse a hash-valid archive already on disk (v1.0 download, or a
      // retry after an unpack problem) — no pointless 132 MB re-fetch.
      // An invalid leftover is deleted and fetched fresh.
      var haveArchive = false;
      if (await archiveFile.exists()) {
        final existing = await archiveFile.length();
        haveArchive = _sizeOk(existing) && await _verifier(archivePath);
        if (!haveArchive) await archiveFile.delete();
      }
      if (!haveArchive) {
        await _downloader(downloadUrl, archivePath, (p) => _progress = p);
        final bytes = await archiveFile.length();
        if (!_sizeOk(bytes)) {
          _state = VoiceModelState.error;
          _errorMessage =
              'The downloaded voice file looks incomplete ($bytes bytes). '
              'Delete it and try again on a good connection.';
          return false;
        }
        if (!await _verifier(archivePath)) {
          await archiveFile.delete();
          _state = VoiceModelState.error;
          _errorMessage = 'The downloaded voice file did not pass its '
              'safety check, so it was removed. Try again on a good '
              'connection.';
          return false;
        }
        _downloadedBytes = bytes;
      } else {
        _downloadedBytes = await archiveFile.length();
        _progress = 1;
      }
      // Unpack, then demand the real model files before calling it ready.
      _extracting = true;
      final extractDir = Directory(await extractedDir());
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
      await _extractor(archivePath, await _dirProvider());
      if (!await _modelTreeOk()) {
        if (await extractDir.exists()) {
          await extractDir.delete(recursive: true);
        }
        _state = VoiceModelState.error;
        _errorMessage = 'The voice file could not be unpacked. Delete '
            'it and try again.';
        return false;
      }
      await File(await _markerPath()).writeAsString(
          'kokoro-multi-lang-v1_0 sha256:${KokoroModelSource.expectedSha256}');
      _state = VoiceModelState.ready;
      _progress = 1;
      return true;
    } catch (e) {
      _state = VoiceModelState.error;
      _errorMessage = 'The voice download did not finish. Check your '
          'internet connection and try again.';
      debugPrint('VoiceModelManager download error: $e');
      return false;
    } finally {
      _extracting = false;
    }
  }

  Future<void> deleteModel() async {
    try {
      final a = File(await _archivePath());
      if (await a.exists()) await a.delete();
      final m = File(await _markerPath());
      if (await m.exists()) await m.delete();
      final x = Directory(await extractedDir());
      if (await x.exists()) await x.delete(recursive: true);
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
// Kokoro synthesis + PCM playback seams (real in v1.1.0)
// ---------------------------------------------------------------------------

/// One synthesized utterance: raw float samples + their sample rate.
class KokoroAudio {
  final Float32List samples;
  final int sampleRate;
  const KokoroAudio(this.samples, this.sampleRate);
}

/// Synthesis backend seam. The real implementation runs sherpa-onnx in
/// a dedicated isolate (FFI generation blocks its isolate; the UI must
/// never pay that cost). Tests substitute a fake.
abstract class KokoroSynthesizer {
  bool get isInitialized;
  Future<void> initialize(String modelDir);
  Future<KokoroAudio> synthesize(
    String text, {
    required int speakerId,
    required double speed,
  });
  Future<void> dispose();
}

/// Worker-isolate entry point: owns the native OfflineTts object.
/// Bindings are initialised INSIDE this isolate (sherpa-onnx rule:
/// every isolate that touches the native library initialises its own).
void _kokoroSynthWorker(SendPort mainPort) {
  final port = ReceivePort();
  mainPort.send(port.sendPort);
  sherpa.OfflineTts? tts;
  port.listen((dynamic msg) {
    final m = msg as Map;
    final reply = m['reply'] as SendPort;
    try {
      switch (m['cmd']) {
        case 'init':
          sherpa.initBindings();
          final dir = m['dir'] as String;
          final kokoro = sherpa.OfflineTtsKokoroModelConfig(
            model: '$dir/${KokoroModelSource.modelFileName}',
            voices: '$dir/${KokoroModelSource.voicesFileName}',
            tokens: '$dir/${KokoroModelSource.tokensFileName}',
            lexicon: KokoroModelSource.lexiconFileNames
                .map((f) => '$dir/$f')
                .join(','),
            dataDir: '$dir/${KokoroModelSource.dataDirName}',
          );
          tts = sherpa.OfflineTts(
            sherpa.OfflineTtsConfig(
              model: sherpa.OfflineTtsModelConfig(
                kokoro: kokoro,
                numThreads: 2,
                debug: false,
              ),
            ),
          );
          reply.send({'ok': true});
          break;
        case 'synth':
          final engine = tts;
          if (engine == null) {
            reply.send({'ok': false, 'error': 'synthesiser not started'});
            break;
          }
          final audio = engine.generate(
            text: m['text'] as String,
            sid: m['sid'] as int,
            speed: (m['speed'] as num).toDouble(),
          );
          reply.send({
            'ok': true,
            'samples': audio.samples,
            'sampleRate': audio.sampleRate,
          });
          break;
        case 'dispose':
          tts?.free();
          tts = null;
          reply.send({'ok': true});
          break;
        default:
          reply.send({'ok': false, 'error': 'unknown command'});
      }
    } catch (e) {
      reply.send({'ok': false, 'error': '$e'});
    }
  });
}

/// sherpa-onnx Kokoro synthesis, driven through [_kokoroSynthWorker].
class SherpaKokoroSynthesizer implements KokoroSynthesizer {
  Isolate? _isolate;
  SendPort? _workerPort;
  bool _initialized = false;

  @override
  bool get isInitialized => _initialized;

  Future<Map> _call(Map<String, dynamic> msg) async {
    final worker = _workerPort;
    if (worker == null) throw StateError('synthesis worker not running');
    final rp = ReceivePort();
    worker.send({...msg, 'reply': rp.sendPort});
    final response = await rp.first as Map;
    if (response['ok'] != true) {
      throw StateError('${response['error'] ?? 'synthesis failed'}');
    }
    return response;
  }

  @override
  Future<void> initialize(String modelDir) async {
    if (_initialized) return;
    if (_isolate == null) {
      final rp = ReceivePort();
      _isolate = await Isolate.spawn(_kokoroSynthWorker, rp.sendPort);
      _workerPort = await rp.first as SendPort;
    }
    await _call({'cmd': 'init', 'dir': modelDir});
    _initialized = true;
  }

  @override
  Future<KokoroAudio> synthesize(
    String text, {
    required int speakerId,
    required double speed,
  }) async {
    final r = await _call({
      'cmd': 'synth',
      'text': text,
      'sid': speakerId,
      'speed': speed,
    });
    return KokoroAudio(
      r['samples'] as Float32List,
      (r['sampleRate'] as num).toInt(),
    );
  }

  @override
  Future<void> dispose() async {
    try {
      if (_workerPort != null) await _call({'cmd': 'dispose'});
    } catch (_) {
      // Worker already gone — disposal is best-effort.
    }
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerPort = null;
    _initialized = false;
  }
}

/// PCM sink seam. The real implementation is the app's AudioTrack
/// platform channel; tests substitute a fake.
abstract class PcmPlayer {
  /// Plays [samples] to completion (or until [stop]).
  /// [pitch] is applied as playback-rate scaling at the sink;
  /// [volume] scales the samples before conversion.
  Future<void> play(
    Float32List samples, {
    required int sampleRate,
    required double volume,
    required double pitch,
  });
  Future<void> stop();
}

/// Converts float samples in [-1, 1] to little-endian int16 PCM,
/// scaled by [volume] and clamped. Pure — unit-tested directly.
Uint8List pcm16LeFromFloat(Float32List samples, double volume) {
  final out = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    var v = samples[i] * volume;
    if (v > 1.0) v = 1.0;
    if (v < -1.0) v = -1.0;
    out.setInt16(i * 2, (v * 32767).round(), Endian.little);
  }
  return out.buffer.asUint8List();
}

class MethodChannelPcmPlayer implements PcmPlayer {
  static const MethodChannel _channel = MethodChannel('lifewave/pcm_player');

  @override
  Future<void> play(
    Float32List samples, {
    required int sampleRate,
    required double volume,
    required double pitch,
  }) async {
    final rate = (sampleRate * pitch).round();
    await _channel.invokeMethod<void>('play', {
      'pcm': pcm16LeFromFloat(samples, volume),
      'sampleRate': rate,
    });
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {
      // No player running — stopping must never throw into the UI.
    }
  }
}

// ---------------------------------------------------------------------------
// Kokoro engine — real synthesis (v1.1.0)
// ---------------------------------------------------------------------------

/// Kokoro via sherpa-onnx: synthesis produces PCM float samples, played
/// through the [PcmPlayer] sink. Available only when the voice file is
/// downloaded + verified + unpacked ([VoiceModelManager.isReady]) and
/// the native engine starts on this device; [ensureReady] performs the
/// one-time start and latches any failure into [unavailableReason] so
/// VoiceService can fall back to the device voice — speech never just
/// fails because Kokoro couldn't start.
///
/// Prosody on this engine: synthesis SPEED from the mapper's rate
/// (flutter_tts scale 0.5 == normal → sherpa speed = rate × 2), the
/// voiced marker synthesized in the picked Kokoro voice as part of the
/// segment text (exactly like the device engine speaks it), pauses
/// honored as silence, volume applied to the samples. PITCH: sherpa
/// Kokoro exposes no pitch parameter, so pitch is applied at the sink
/// as playback-rate scaling and the synthesis speed is divided by the
/// same factor, keeping duration natural. Pitch is clamped to a subtle
/// band (0.85–1.25) — rate-scaling beyond that sounds artificial.
class KokoroEngine implements VoiceEngine {
  final VoiceModelManager modelManager;
  final KokoroSynthesizer _synthesizer;
  final PcmPlayer _player;

  bool _startFailed = false;

  KokoroEngine(
    this.modelManager, {
    KokoroSynthesizer? synthesizer,
    PcmPlayer? player,
  })  : _synthesizer = synthesizer ?? SherpaKokoroSynthesizer(),
        _player = player ?? MethodChannelPcmPlayer();

  /// Plain description of the Kokoro voice, shown in Settings.
  static const String aboutText =
      'Kokoro is the warm Scout voice. It runs fully on this device — '
      'no internet is needed once the voice file is downloaded. Until '
      'the file is here, the device voice speaks instead, and the app '
      'says so.';

  @override
  String get engineId => 'kokoro';
  @override
  String get displayName => 'Kokoro voice (Scout voice)';
  @override
  bool get isAvailable => modelManager.isReady && !_startFailed;
  @override
  String get unavailableReason {
    if (_startFailed) {
      return 'The Kokoro voice could not start on this device, so the '
          'device voice is being used instead.';
    }
    if (!modelManager.isReady) {
      return 'The Kokoro voice file has not been downloaded yet, so '
          'the device voice is being used instead. Download it below '
          'to switch to Kokoro.';
    }
    return '';
  }

  /// One-time engine start (native model load). Returns false — and
  /// latches the failure — when Kokoro cannot run on this device.
  Future<bool> ensureReady() async {
    if (_startFailed) return false;
    if (_synthesizer.isInitialized) return true;
    if (!modelManager.isReady) return false;
    try {
      await _synthesizer.initialize(await modelManager.extractedDir());
      return true;
    } catch (e) {
      _startFailed = true;
      debugPrint('KokoroEngine start failed: $e');
      return false;
    }
  }

  /// The standard Kokoro multi-lang v1.0 speaker ids (speaker order in
  /// the sherpa-onnx package = the sid used for synthesis). Selection
  /// is stored per-user.
  static const List<String> kokoroVoiceIds = [
    'af_heart', 'af_bella', 'af_sarah', 'af_nicole', 'af_sky',
    'am_michael', 'am_adam', 'am_eric', 'am_liam', 'am_puck',
    'bf_emma', 'bf_alice', 'bf_lily', 'bm_george', 'bm_daniel', 'bm_lewis',
    'jf_alpha', 'jm_kumo', 'zf_xiaoxiao', 'zf_xiaoyi', 'zm_yunyang',
    'zm_yunjian', 'ff_siwis', 'if_sara', 'im_nicola',
  ];

  int speakerIdFor(VoiceInfo? voice) {
    if (voice == null || voice.engineId != engineId) return 0;
    final idx = kokoroVoiceIds.indexOf(voice.id);
    return idx >= 0 ? idx : 0;
  }

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
    if (!await ensureReady()) {
      throw StateError('Kokoro is not available: $unavailableReason');
    }
    if (prosody.pauseBeforeMs > 0) {
      await Future<void>.delayed(
          Duration(milliseconds: prosody.pauseBeforeMs));
    }
    // The marker is spoken IN the picked Kokoro voice as part of the
    // segment (same approach as the device engine); breaths on this
    // path are the varied pauses the mapper folded into the pause
    // values — no fake breath noise is synthesized.
    final spokenText =
        prosody.marker.isEmpty ? text : '${prosody.marker}$text';
    final pitch = prosody.pitch.clamp(0.85, 1.25).toDouble();
    final speed = ((prosody.rate * 2.0) / pitch).clamp(0.5, 2.0).toDouble();
    final audio = await _synthesizer.synthesize(
      spokenText,
      speakerId: speakerIdFor(voice),
      speed: speed,
    );
    if (audio.samples.isEmpty || audio.sampleRate <= 0) {
      throw StateError('Kokoro produced no audio for this segment.');
    }
    await _player.play(
      audio.samples,
      sampleRate: audio.sampleRate,
      volume: prosody.volume,
      pitch: pitch,
    );
    if (prosody.pauseAfterMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: prosody.pauseAfterMs));
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
  }
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

  /// Honest one-liner for Settings/Diagnostics: which voice will speak.
  /// (Kokoro init failure latches in the engine, so after a failed
  /// first start this correctly reads "Device voice".)
  String get activeEngineLabel =>
      activeEngine.engineId == 'kokoro' ? 'Kokoro voice' : 'Device voice';

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
    var engine = activeEngine;
    if (engine.engineId == kokoroEngine.engineId) {
      // First Kokoro utterance pays the one-time model load. If the
      // engine cannot start on this device, THIS utterance falls back
      // to the device voice instead of failing — and the engine's
      // latched state makes later calls skip straight to the device.
      if (!await kokoroEngine.ensureReady()) {
        engine = deviceEngine;
      }
    }
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
    await kokoroEngine.stop();
  }
}
