import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Speech INPUT (STT) — SPEC §7.3 input side + PRE-BUILD-AUDIT §§1/3:
///  - initialize ONCE and reuse the instance;
///  - listen() only after a successful initialize();
///  - mic permission requested AT FIRST USE, in context;
///  - denial / unavailability => typing fallback with an honest message,
///    never a dead mic button;
///  - Windows: desktop speech recognition is weak/absent in the
///    speech_to_text plugin (no Windows implementation ships), so the
///    service reports "not available on this device" honestly and the
///    UI falls back to typing. NO Windows voice-parity promise.

enum SpeechInputState {
  unknown,
  ready,
  listening,
  unavailable,
  permissionDenied,
}

class SpeechInputResult {
  final bool ok;
  final String text; // recognized words ('' when !ok)
  final String message; // plain-language outcome, always set when !ok
  const SpeechInputResult({required this.ok, this.text = '', this.message = ''});
}

/// Seam over the platform STT + permission plugins (tests use fakes).
abstract class SttPlatform {
  Future<bool> initialize();
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  bool get isListening;
  Future<void> listen({
    required void Function(String words, bool isFinal) onResult,
    String? localeId,
  });
  Future<void> stop();
}

class SpeechToTextPlatform implements SttPlatform {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _initialized = false;

  @override
  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onStatus: (s) => debugPrint('STT status: $s'),
      onError: (e) => debugPrint('STT error: ${e.errorMsg} (permanent: ${e.permanent})'),
    );
    return _initialized;
  }

  @override
  Future<bool> hasPermission() async {
    try {
      return await _speech.hasPermission;
    } catch (_) {
      final status = await Permission.microphone.status;
      return status.isGranted;
    }
  }

  @override
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<void> listen({
    required void Function(String words, bool isFinal) onResult,
    String? localeId,
  }) async {
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) =>
          onResult(r.recognizedWords, r.finalResult),
      localeId: localeId,
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
      ),
    );
  }

  @override
  Future<void> stop() async => _speech.stop();
}

/// The app's single speech-input service.
class SpeechInputService {
  final SttPlatform _platform;
  final bool _isWindows;

  SpeechInputState _state = SpeechInputState.unknown;
  bool _initAttempted = false;
  bool _initOk = false;
  String _lastMessage = '';

  SpeechInputService({SttPlatform? platform, bool? isWindows})
      : _platform = platform ?? SpeechToTextPlatform(),
        _isWindows = isWindows ?? Platform.isWindows;

  SpeechInputState get state => _state;
  String get lastMessage => _lastMessage;

  /// Honest availability: Windows reports unavailable by design (audit
  /// §3) — the plugin has no Windows speech implementation to call.
  bool get platformSupported => !_isWindows;

  String get availabilityLabel {
    if (!platformSupported) {
      return 'Not available on Windows — type instead';
    }
    switch (_state) {
      case SpeechInputState.ready:
        return 'Ready';
      case SpeechInputState.listening:
        return 'Listening…';
      case SpeechInputState.permissionDenied:
        return 'Microphone permission not given — type instead';
      case SpeechInputState.unavailable:
        return 'Not available on this device — type instead';
      case SpeechInputState.unknown:
        return 'Not checked yet — tap the mic to try';
    }
  }

  /// Ensures permission + one-time initialization. Returns true when a
  /// listen() may follow. Safe to call repeatedly.
  Future<bool> ensureReady() async {
    if (!platformSupported) {
      _state = SpeechInputState.unavailable;
      _lastMessage = 'Voice typing is not available on Windows in this '
          'app. Please type instead — everything else works the same.';
      return false;
    }
    try {
      var granted = await _platform.hasPermission();
      if (!granted) {
        granted = await _platform.requestPermission();
      }
      if (!granted) {
        _state = SpeechInputState.permissionDenied;
        _lastMessage = 'The microphone is off for this app, so voice '
            'typing cannot run. You can type instead, or turn the '
            'microphone on for LifeWave AI in your device settings.';
        return false;
      }
      if (!_initAttempted) {
        _initAttempted = true;
        _initOk = await _platform.initialize(); // ONCE — audit rule
      }
      if (!_initOk) {
        _state = SpeechInputState.unavailable;
        _lastMessage = 'This device could not start speech listening. '
            'Typing works just as well.';
        return false;
      }
      _state = SpeechInputState.ready;
      return true;
    } catch (e) {
      // MissingPluginException and friends degrade to typing (audit §2).
      debugPrint('SpeechInput ensureReady error: $e');
      _state = SpeechInputState.unavailable;
      _lastMessage = 'Voice typing is not available on this device. '
          'You can type instead.';
      return false;
    }
  }

  /// One tap-to-talk session: listens until a final result, silence, or
  /// [timeout]. Never hangs and never throws into the UI.
  Future<SpeechInputResult> listenOnce({
    String? localeId,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!await ensureReady()) {
      return SpeechInputResult(ok: false, message: _lastMessage);
    }
    _state = SpeechInputState.listening;
    try {
      var words = '';
      final completer = Completer<String>();
      await _platform.listen(
        localeId: localeId,
        onResult: (w, isFinal) {
          words = w;
          if (isFinal && !completer.isCompleted) {
            completer.complete(words);
          }
        },
      );
      final result = await completer.future
          .timeout(timeout, onTimeout: () => words);
      await stop();
      if (result.trim().isEmpty) {
        return const SpeechInputResult(
          ok: false,
          message: 'Nothing was heard. Try again, or type instead.',
        );
      }
      return SpeechInputResult(ok: true, text: result.trim());
    } catch (e) {
      debugPrint('SpeechInput listen error: $e');
      _state = SpeechInputState.unavailable;
      return const SpeechInputResult(
        ok: false,
        message: 'Listening stopped with a problem. You can type instead.',
      );
    } finally {
      if (_state == SpeechInputState.listening) {
        _state = SpeechInputState.ready;
      }
    }
  }

  Future<void> stop() async {
    try {
      await _platform.stop();
    } catch (_) {
      // Stopping a dead session is fine.
    }
    if (_state == SpeechInputState.listening) {
      _state = SpeechInputState.ready;
    }
  }

  /// Current mic permission without prompting (for Diagnostics).
  Future<String> micPermissionLabel() async {
    if (!platformSupported) return 'Not applicable on Windows';
    try {
      final status = await Permission.microphone.status;
      if (status.isGranted) return 'Given';
      if (status.isPermanentlyDenied) return 'Turned off in device settings';
      return 'Not given yet';
    } catch (_) {
      return 'Could not be checked';
    }
  }
}
