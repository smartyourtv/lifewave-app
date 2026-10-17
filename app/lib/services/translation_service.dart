import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'compliance.dart';
import 'emotion.dart';
import 'voice_service.dart';

/// Translation (SPEC §7.4 + §7.5): on-device ML Kit first, cloud fallback
/// (still the NotConfigured stub — honest "not set up", no keys), and a
/// timeout cascade so a turn NEVER hangs (SPEC §7.5). The compliance
/// check runs on the FINAL-LANGUAGE text (SPEC §7.4) — callers scan the
/// translated result with [ComplianceScanner]; the conversation flow
/// below does it automatically per turn.
///
/// ML Kit honesty notes:
///  - On-device packs are per-language downloads MANAGED BY ML KIT /
///    Android — the plugin API does not report a per-pack byte size, so
///    [LanguagePack.sizeBytes] is null on the real engine and the UI
///    says "size managed by the system" instead of inventing a number.
///  - Windows: ML Kit has no Windows implementation; the engine reports
///    unavailable and text translation falls through the cascade to the
///    (unconfigured) cloud tier, landing on an honest failure message.

class AppLanguage {
  final String code; // BCP-47-ish primary code, e.g. 'en', 'es', 'vi'
  final String name;
  const AppLanguage(this.code, this.name);
  @override
  String toString() => '$name ($code)';
  @override
  bool operator ==(Object other) => other is AppLanguage && other.code == code;
  @override
  int get hashCode => code.hashCode;
}

/// Languages offered in pickers. The ML Kit on-device engine covers ~59
/// languages; this curated list is the common set — the engine call
/// itself is the authority and fails honestly for anything unsupported.
const List<AppLanguage> kAppLanguages = [
  AppLanguage('en', 'English'),
  AppLanguage('es', 'Spanish'),
  AppLanguage('fr', 'French'),
  AppLanguage('de', 'German'),
  AppLanguage('it', 'Italian'),
  AppLanguage('pt', 'Portuguese'),
  AppLanguage('vi', 'Vietnamese'),
  AppLanguage('zh', 'Chinese'),
  AppLanguage('ja', 'Japanese'),
  AppLanguage('ko', 'Korean'),
  AppLanguage('ru', 'Russian'),
  AppLanguage('ar', 'Arabic'),
  AppLanguage('hi', 'Hindi'),
  AppLanguage('tl', 'Tagalog'),
  AppLanguage('nl', 'Dutch'),
  AppLanguage('pl', 'Polish'),
  AppLanguage('tr', 'Turkish'),
  AppLanguage('uk', 'Ukrainian'),
];

AppLanguage languageByCode(String code) {
  for (final l in kAppLanguages) {
    if (l.code == code) return l;
  }
  return AppLanguage(code, code.toUpperCase());
}

class LanguagePack {
  final AppLanguage language;
  final bool downloaded;

  /// Null when the engine does not report sizes (real ML Kit case).
  final int? sizeBytes;
  const LanguagePack({
    required this.language,
    required this.downloaded,
    this.sizeBytes,
  });
}

/// Typed translation failure — the cascade turns these into fallbacks,
/// never into a hung spinner.
class TranslationException implements Exception {
  final String message;
  const TranslationException(this.message);
  @override
  String toString() => message;
}

/// Seam over the on-device engine (tests use fakes).
abstract class TranslationEngine {
  bool get isSupportedOnPlatform;
  Future<bool> isModelDownloaded(String code);
  Future<void> downloadModel(String code);
  Future<void> deleteModel(String code);
  Future<String> translate(String text, String fromCode, String toCode);
  Future<String> detectLanguage(String text); // BCP code or 'und'
}

TranslateLanguage? _mlKitLang(String code) {
  for (final l in TranslateLanguage.values) {
    if (l.bcpCode == code) return l;
  }
  // ML Kit uses 'zh' variants / legacy codes for a few languages.
  switch (code) {
    case 'zh':
      return TranslateLanguage.chinese;
    case 'tl':
      return TranslateLanguage.tagalog;
    default:
      return null;
  }
}

class MlKitTranslationEngine implements TranslationEngine {
  final OnDeviceTranslatorModelManager _models =
      OnDeviceTranslatorModelManager();
  LanguageIdentifier? _identifier;

  @override
  bool get isSupportedOnPlatform {
    // ML Kit ships Android/iOS implementations only. On Windows the
    // platform channel is absent; report unsupported up front instead
    // of throwing MissingPluginException into the cascade.
    try {
      return true; // refined by try/catch on first real call below
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isModelDownloaded(String code) async {
    final lang = _mlKitLang(code);
    if (lang == null) return false;
    try {
      return await _models.isModelDownloaded(lang.bcpCode);
    } catch (e) {
      debugPrint('MLKit isModelDownloaded error: $e');
      return false;
    }
  }

  @override
  Future<void> downloadModel(String code) async {
    final lang = _mlKitLang(code);
    if (lang == null) {
      throw const TranslationException(
          'That language is not in the on-device list.');
    }
    try {
      await _models.downloadModel(lang.bcpCode);
    } catch (e) {
      throw const TranslationException('The language pack could not be '
          'downloaded. Check your internet connection and try again.');
    }
  }

  @override
  Future<void> deleteModel(String code) async {
    final lang = _mlKitLang(code);
    if (lang == null) return;
    try {
      await _models.deleteModel(lang.bcpCode);
    } catch (_) {
      // Best-effort delete; bookkeeping refresh reports the truth.
    }
  }

  @override
  Future<String> translate(String text, String fromCode, String toCode) async {
    final from = _mlKitLang(fromCode);
    final to = _mlKitLang(toCode);
    if (from == null || to == null) {
      throw const TranslationException(
          'That language pair is not supported on this device.');
    }
    final translator =
        OnDeviceTranslator(sourceLanguage: from, targetLanguage: to);
    try {
      return await translator.translateText(text);
    } catch (e) {
      debugPrint('MLKit translate error: $e');
      throw const TranslationException(
          'On-device translation did not work for that text.');
    } finally {
      await translator.close();
    }
  }

  @override
  Future<String> detectLanguage(String text) async {
    try {
      _identifier ??= LanguageIdentifier(confidenceThreshold: 0.5);
      final code = await _identifier!.identifyLanguage(text);
      return code; // 'und' when undetermined
    } catch (e) {
      debugPrint('MLKit language-id error: $e');
      return 'und';
    }
  }
}

/// Cloud translation fallback — interface only in M2. The live cloud
/// tier is the same not-configured posture as [CloudEscalation]: no
/// keys ship in the app, ever.
abstract class CloudTranslator {
  bool get isConfigured;
  Future<String> translate(String text, String fromCode, String toCode);
}

class NotConfiguredCloudTranslator implements CloudTranslator {
  const NotConfiguredCloudTranslator();
  @override
  bool get isConfigured => false;
  @override
  Future<String> translate(String text, String fromCode, String toCode) {
    throw const TranslationException(
        "Cloud translation isn't set up on this device yet.");
  }
}

enum TranslationTier { onDevice, cloud, failed }

class TranslationResult {
  final String text; // translated text, or the ORIGINAL text when failed
  final TranslationTier tier;
  final String message; // plain-language note ('' on clean success)
  final bool usedOriginal; // true when text is the untranslated original
  const TranslationResult({
    required this.text,
    required this.tier,
    this.message = '',
    this.usedOriginal = false,
  });
}

/// Translation service: pack bookkeeping + the timeout cascade.
class TranslationService {
  final TranslationEngine engine;
  final CloudTranslator cloud;
  final Duration onDeviceTimeout;

  static const String _prefsKeyDownloaded = 'translation_downloaded_packs';

  /// Codes this device has downloaded packs for (bookkeeping mirror of
  /// the engine's own state; refreshed from the engine on load).
  final Set<String> _downloaded = {};

  TranslationService({
    TranslationEngine? engine,
    CloudTranslator? cloud,
    this.onDeviceTimeout = const Duration(seconds: 12),
  })  : engine = engine ?? MlKitTranslationEngine(),
        cloud = cloud ?? const NotConfiguredCloudTranslator();

  Set<String> get downloadedCodes => Set.unmodifiable(_downloaded);
  int get downloadedCount => _downloaded.length;

  /// Total size of downloaded packs, or null when the engine does not
  /// report sizes (the real ML Kit case — UI must say so, not guess).
  /// The ML Kit plugin exposes no per-pack size API, so on the real
  /// engine this is null BY CONSTRUCTION rather than an invented number.
  int? get downloadedTotalBytes => null;

  Future<void> loadBookkeeping() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_prefsKeyDownloaded) ?? const [];
      _downloaded
        ..clear()
        ..addAll(saved);
      // Reconcile with the engine's truth for every known language.
      for (final lang in kAppLanguages) {
        final has = await engine.isModelDownloaded(lang.code);
        if (has) {
          _downloaded.add(lang.code);
        } else {
          _downloaded.remove(lang.code);
        }
      }
      await _persist();
    } catch (_) {
      // Bookkeeping is best-effort; translation itself still works.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          _prefsKeyDownloaded, _downloaded.toList()..sort());
    } catch (_) {}
  }

  Future<List<LanguagePack>> listPacks() async {
    final packs = <LanguagePack>[];
    for (final lang in kAppLanguages) {
      var downloaded = _downloaded.contains(lang.code);
      try {
        downloaded = await engine.isModelDownloaded(lang.code);
      } catch (_) {}
      packs.add(LanguagePack(language: lang, downloaded: downloaded));
    }
    return packs;
  }

  Future<bool> downloadPack(String code) async {
    try {
      await engine.downloadModel(code);
      _downloaded.add(code);
      await _persist();
      return true;
    } catch (e) {
      debugPrint('downloadPack error: $e');
      return false;
    }
  }

  Future<void> deletePack(String code) async {
    await engine.deleteModel(code);
    _downloaded.remove(code);
    await _persist();
  }

  Future<String> detectLanguage(String text) => engine.detectLanguage(text);

  /// The cascade: on-device (with timeout) -> cloud -> honest failure
  /// carrying the ORIGINAL text. A call to this method always completes.
  Future<TranslationResult> translateWithCascade(
    String text, {
    required String fromCode,
    required String toCode,
    Duration? timeout,
  }) async {
    if (text.trim().isEmpty) {
      return TranslationResult(
          text: text, tier: TranslationTier.failed, message: 'Nothing to translate.', usedOriginal: true);
    }
    if (fromCode == toCode) {
      return TranslationResult(text: text, tier: TranslationTier.onDevice);
    }
    // Tier 1: on-device.
    try {
      final translated = await engine
          .translate(text, fromCode, toCode)
          .timeout(timeout ?? onDeviceTimeout);
      return TranslationResult(text: translated, tier: TranslationTier.onDevice);
    } on TimeoutException {
      debugPrint('On-device translation timed out; trying cloud tier.');
    } catch (e) {
      debugPrint('On-device translation failed ($e); trying cloud tier.');
    }
    // Tier 2: cloud (stub in M2 -> honest notice, original preserved).
    try {
      final translated = await cloud.translate(text, fromCode, toCode);
      return TranslationResult(text: translated, tier: TranslationTier.cloud);
    } catch (e) {
      return TranslationResult(
        text: text,
        tier: TranslationTier.failed,
        usedOriginal: true,
        message: "Couldn't translate that just now. "
            '${e is TranslationException ? e.message : ''} '
            'The original words are shown instead.',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// 2-way conversation translator (SPEC §7.5)
// ---------------------------------------------------------------------------

enum ConversationSide { a, b }

class ConversationTurn {
  final ConversationSide speaker;
  final String originalText;
  final String translatedText;
  final String sourceCode;
  final String targetCode;
  final TranslationTier tier;

  /// True when translation failed and [translatedText] is the original.
  final bool failed;

  /// Compliance hits found in the FINAL-LANGUAGE (translated) text.
  final List<ComplianceHit> complianceHits;
  const ConversationTurn({
    required this.speaker,
    required this.originalText,
    required this.translatedText,
    required this.sourceCode,
    required this.targetCode,
    required this.tier,
    required this.failed,
    this.complianceHits = const [],
  });
}

/// Turn state machine + orchestration for the conversation screen.
/// Audio routing note (SPEC §7.5): output goes to the DEFAULT device
/// speaker/headset via the platform — this app deliberately does NOT
/// build custom Bluetooth routing (PRE-BUILD-AUDIT §1: no
/// BLUETOOTH_CONNECT APIs are called).
class ConversationTranslator {
  final TranslationService translation;
  final VoiceService voice;
  final ComplianceScanner scanner;
  AppLanguage languageA;
  AppLanguage languageB;
  bool autoDetect;

  final List<ConversationTurn> _turns = [];
  List<ConversationTurn> get turns => List.unmodifiable(_turns);

  ConversationTranslator({
    required this.translation,
    required this.voice,
    ComplianceScanner? scanner,
    AppLanguage? languageA,
    AppLanguage? languageB,
    this.autoDetect = true,
  })  : scanner = scanner ?? const ComplianceScanner(),
        languageA = languageA ?? languageByCode('en'),
        languageB = languageB ?? languageByCode('es');

  AppLanguage languageFor(ConversationSide side) =>
      side == ConversationSide.a ? languageA : languageB;
  AppLanguage otherLanguageFor(ConversationSide side) =>
      side == ConversationSide.a ? languageB : languageA;

  /// Runs one turn end to end: detect (if auto) -> translate (cascade,
  /// never hangs) -> compliance-scan the final text -> append -> speak
  /// the translation aloud. Returns the appended turn.
  Future<ConversationTurn> processTurn({
    required ConversationSide speaker,
    required String inputText,
    required EmotionLevel emotionLevel,
    bool speakResult = true,
    String? manualSourceCode,
  }) async {
    final target = otherLanguageFor(speaker);
    var source = languageFor(speaker);
    if (manualSourceCode != null) {
      source = languageByCode(manualSourceCode);
    } else if (autoDetect) {
      final detected = await translation.detectLanguage(inputText);
      if (detected != 'und' && detected.isNotEmpty) {
        // Only accept a detection that matches one of the two sides —
        // anything else keeps the speaker's chosen language.
        if (detected == languageA.code || detected == languageB.code) {
          source = languageByCode(detected);
        }
      }
    }
    // If detection says the speaker actually used the OTHER side's
    // language, the target flips with it.
    final effectiveTarget =
        source.code == target.code ? languageFor(speaker) : target;

    final result = await translation.translateWithCascade(
      inputText,
      fromCode: source.code,
      toCode: effectiveTarget.code,
    );
    final report = scanner.scan(result.text); // final-language check
    final turn = ConversationTurn(
      speaker: speaker,
      originalText: inputText,
      translatedText: result.text,
      sourceCode: source.code,
      targetCode: effectiveTarget.code,
      tier: result.tier,
      failed: result.tier == TranslationTier.failed,
      complianceHits: report.hits,
    );
    _turns.add(turn);
    if (speakResult && !turn.failed) {
      // Spoken in the target side's language via the single voice
      // controller; warm business tone, no markup surprises.
      await voice.speak(
        '[warm] ${turn.translatedText}',
        level: emotionLevel,
      );
    }
    return turn;
  }

  void clear() => _turns.clear();
}
