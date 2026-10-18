import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import 'crash_reporter.dart';

/// Self-repair (standing rule, Shawn 2026-10-17 — all apps): the app
/// detects and repairs recoverable problems in its own STATE under
/// three conditions on EVERY repair:
///
///  1. **Conservative** — only verifiable, reversible repairs (reset a
///     corrupt setting to its safe default, remove a corrupt download
///     before it can be used, reload the bundled database). Code bugs
///     are NOT self-repairable: they are reported and fixed by update.
///  2. **Verified** — after repairing, the state is re-checked; success
///     is claimed only when the check passes.
///  3. **Logged** — every repair and every failed repair, with the
///     evidence, is written into the crash/error report store, marked
///     repaired / repair-failed (see [CrashReporter.recordRepair]).
///
/// This file holds the formal runner ([SelfRepair.attempt]) plus the
/// settings-repair loader ([SafePrefsLoader]). Repairs that already
/// existed elsewhere (saved-lists corruption degradation in
/// local_store.dart, Kokoro download quarantine in voice_service.dart)
/// log their outcomes through [SelfRepair.logOutcome].

/// One repair outcome, ready to log.
class RepairEvent {
  /// Short label of the thing that was wrong (e.g. a preference key).
  final String subject;

  /// What was wrong, in plain words.
  final String problem;

  /// Evidence: what was observed, what was done, what the re-check saw.
  final String evidence;

  final bool success;
  const RepairEvent({
    required this.subject,
    required this.problem,
    required this.evidence,
    required this.success,
  });
}

abstract class SelfRepair {
  /// The formal repair runner: run [repair], then [verify]; log the
  /// outcome with [evidence] either way. Returns true ONLY when the
  /// post-repair check passes. Never throws.
  static Future<bool> attempt({
    required String area,
    required String problem,
    required String evidence,
    required Future<void> Function() repair,
    required Future<bool> Function() verify,
  }) async {
    var ok = false;
    var detail = evidence;
    try {
      await repair();
      ok = await verify();
      if (!ok) {
        detail = '$evidence The repair was done, but the follow-up '
            'check still shows the problem.';
      }
    } catch (e) {
      ok = false;
      detail = '$evidence The repair itself failed: $e';
    }
    logOutcome(
      success: ok,
      area: area,
      problem: problem,
      evidence: detail,
    );
    return ok;
  }

  /// Logs an already-performed repair (or failed repair) into the
  /// crash/error report store. Never throws.
  static void logOutcome({
    required bool success,
    required String area,
    required String problem,
    required String evidence,
  }) {
    try {
      CrashReporter.recordRepairOutcome(
        success: success,
        problem: problem,
        evidence: evidence,
        context: 'Self-repair — $area',
      );
    } catch (e) {
      debugPrint('SelfRepair log failed: $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Settings (SharedPreferences) repair — safe-default restore that
// preserves everything salvageable.
// ---------------------------------------------------------------------------

/// Minimal read/remove seam over the preferences store, so the repair
/// logic is unit-testable without the platform channel.
abstract class PrefsAccess {
  /// The raw stored value for [key] (no type coercion), or null.
  Object? rawValue(String key);

  Future<void> remove(String key);
}

class SharedPreferencesAccess implements PrefsAccess {
  final SharedPreferences _prefs;
  SharedPreferencesAccess(this._prefs);

  @override
  Object? rawValue(String key) => _prefs.get(key);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

/// The settings values main() needs at startup, after repair.
class LoadedPrefs {
  final String? displayName;
  final bool welcomeDismissed;
  final String? emotionLevelName;
  final String? voiceRaw;
  final String? chatLanguageCode;
  final bool tourSeen;
  final String? referralLink;

  /// Repairs performed (or attempted) while loading, for logging.
  final List<RepairEvent> repairs;

  const LoadedPrefs({
    required this.displayName,
    required this.welcomeDismissed,
    required this.emotionLevelName,
    required this.voiceRaw,
    required this.chatLanguageCode,
    required this.tourSeen,
    required this.referralLink,
    required this.repairs,
  });
}

/// Loads the startup settings key-by-key (the keys mirror PrefKeys in
/// settings_about.dart — kept as literals here so this service does not
/// depend on a screen file). A key holding a value of the WRONG TYPE —
/// the on-device shape of a corrupt settings file — is reset to its
/// safe default (removed), verified gone, and reported as a
/// [RepairEvent]; every healthy key is preserved exactly as stored.
/// Before v1.1.1 a single blanket try/catch discarded ALL settings
/// when any one of them was damaged.
class SafePrefsLoader {
  static const String _kDisplayName = 'display_name';
  static const String _kWelcomeDismissed = 'welcome_dismissed';
  static const String _kEmotionLevel = 'emotion_level';
  static const String _kVoice = 'voice_key';
  static const String _kChatLanguage = 'chat_language';
  static const String _kTourSeen = 'tour_seen';
  static const String _kReferralLink = 'referral_link';

  final PrefsAccess _access;

  /// Validates the stored voice string ('engine|id|name'); an
  /// undecodable non-null value counts as corrupt. Injected so this
  /// service stays free of screen/voice imports (main passes
  /// PrefKeys.decodeVoice).
  final bool Function(String raw)? voiceValidator;

  SafePrefsLoader(this._access, {this.voiceValidator});

  Future<LoadedPrefs> load() async {
    final repairs = <RepairEvent>[];
    final displayName =
        await _string(_kDisplayName, repairs);
    final welcomeDismissed =
        await _bool(_kWelcomeDismissed, false, repairs);
    final emotionLevelName = await _string(_kEmotionLevel, repairs);
    var voiceRaw = await _string(_kVoice, repairs);
    if (voiceRaw != null &&
        voiceValidator != null &&
        !voiceValidator!(voiceRaw)) {
      // Present but not in 'engine|id|name' shape: corrupt entry.
      final ok = await _resetKey(
        _kVoice,
        'The saved voice choice was damaged (it was not in the '
            'expected shape), so it was reset to the default voice.',
        'Stored value: $voiceRaw',
        repairs,
      );
      if (ok) voiceRaw = null;
    }
    final chatLanguageCode = await _string(_kChatLanguage, repairs);
    final tourSeen = await _bool(_kTourSeen, false, repairs);
    final referralLink = await _string(_kReferralLink, repairs);
    return LoadedPrefs(
      displayName: displayName,
      welcomeDismissed: welcomeDismissed,
      emotionLevelName: emotionLevelName,
      voiceRaw: voiceRaw,
      chatLanguageCode: chatLanguageCode,
      tourSeen: tourSeen,
      referralLink: referralLink,
      repairs: repairs,
    );
  }

  /// Reads one entry; a wrong-type or unreadable value triggers the
  /// reset repair. Returns the raw stored value (null when absent or
  /// repaired away).
  Future<Object?> _read(String key, List<RepairEvent> repairs) async {
    Object? raw;
    try {
      raw = _access.rawValue(key);
    } catch (e) {
      await _resetKey(
        key,
        'A saved setting could not be read at all, so it was reset '
            'to its safe default.',
        'Reading "$key" failed: $e',
        repairs,
      );
      return null;
    }
    return raw;
  }

  Future<String?> _string(String key, List<RepairEvent> repairs) async {
    final raw = await _read(key, repairs);
    if (raw == null || raw is String) return raw as String?;
    await _resetKey(
      key,
      'A saved setting held the wrong kind of value, so it was reset '
          'to its safe default.',
      'Key "$key" held a ${raw.runtimeType} where text was expected.',
      repairs,
    );
    return null;
  }

  Future<bool> _bool(
      String key, bool fallback, List<RepairEvent> repairs) async {
    final raw = await _read(key, repairs);
    if (raw == null) return fallback;
    if (raw is bool) return raw;
    await _resetKey(
      key,
      'A saved setting held the wrong kind of value, so it was reset '
          'to its safe default.',
      'Key "$key" held a ${raw.runtimeType} where a yes/no value was '
          'expected.',
      repairs,
    );
    return fallback;
  }

  /// The repair itself: remove the damaged entry, then VERIFY it is
  /// gone. Records the outcome either way. Returns true when the entry
  /// is verifiably gone (the safe default now applies).
  Future<bool> _resetKey(
    String key,
    String problem,
    String evidence,
    List<RepairEvent> repairs,
  ) async {
    var ok = false;
    var detail = evidence;
    try {
      await _access.remove(key);
      ok = _access.rawValue(key) == null;
      if (!ok) {
        detail = '$evidence The damaged entry was removed, but the '
            'follow-up check still finds a value for "$key".';
      }
    } catch (e) {
      detail = '$evidence Removing the damaged entry failed: $e';
    }
    repairs.add(RepairEvent(
      subject: key,
      problem: problem,
      evidence: detail,
      success: ok,
    ));
    return ok;
  }
}
