import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:path_provider/path_provider.dart';

import '../theme.dart';

/// Crash & error reporting (standing rule, Shawn 2026-10-17 — retroactive
/// + all future builds): every app captures its errors/crashes and
/// surfaces them TWO ways —
///
///  1. an in-app reports view (Diagnostics → "Crash & error reports":
///     list, read, share, delete), fed by the app's own stored copies in
///     the app-documents `crash_reports/` folder;
///  2. a report FILE in the device's Downloads folder
///     (`Lifewave-crash-<YYYYMMDD-HHMMSS>.txt`), written at crash time.
///
/// Reports are NEVER auto-uploaded anywhere. They stay on the device
/// until the user shares one.
///
/// Survival design: the handlers are installed before `runApp` (see
/// main.dart — a Zone guard, FlutterError.onError and
/// PlatformDispatcher.onError). At record time the report is written
/// FIRST, synchronously, to the persistent crash log + the report store
/// in app documents — so the evidence survives even if the process dies
/// immediately after. The Downloads mirror is best-effort on top of that:
/// a Downloads failure (permission, platform) never loses the report.
///
/// Honest platform limits:
///  - Dart-layer capture cannot see a purely native crash (e.g. a segfault
///    inside a native library) — no report is written for those. On
///    Android the sherpa-onnx native side is the main such surface.
///  - Android Downloads: written through MediaStore (API 29+, no
///    permission needed). On API 21–28 the native side attempts the
///    public Downloads folder directly; devices that refuse it keep the
///    report in the in-app view only, and the mirror result says so.
///  - On non-Android/Windows targets the mirror is skipped silently (the
///    in-app store still works wherever path_provider works).

/// One captured error/crash, ready to format as the report file text.
class CrashReportData {
  final DateTime when;

  /// True when the error was fatal (app stopped / would stop).
  final bool fatal;

  /// Short human label of where the error was caught, e.g.
  /// "Kokoro voice start" or "Update check". Null for unhandled errors.
  final String? context;

  final String errorType;
  final String message;
  final String stackTrace;
  final String appVersionLabel;
  final String platformLabel;

  /// Self-repair mark (standing self-repair rule, v1.1.1): when this
  /// record is a repair log entry rather than an error, this is
  /// `'repaired'` or `'repair-failed'`; null for ordinary errors. The
  /// [message] then states the problem found and [stackTrace] carries
  /// the evidence (what was observed / done / re-checked).
  final String? repairMark;

  const CrashReportData({
    required this.when,
    required this.fatal,
    required this.context,
    required this.errorType,
    required this.message,
    required this.stackTrace,
    required this.appVersionLabel,
    required this.platformLabel,
    this.repairMark,
  });

  bool get isRepair => repairMark != null;
  bool get repairOk => repairMark == 'repaired';

  /// Plain-language opening line — always the first line of the file.
  String get summaryLine {
    if (repairMark == 'repaired') {
      return 'LifeWave AI found a problem in its own saved information '
          'and fixed it.';
    }
    if (repairMark == 'repair-failed') {
      return 'LifeWave AI found a problem in its own saved information '
          'and could not fix it.';
    }
    return fatal
        ? 'LifeWave AI stopped working because of a problem.'
        : 'LifeWave AI hit a problem, but kept going.';
  }

  /// The full report file text.
  String format() {
    final b = StringBuffer();
    b.writeln(summaryLine);
    b.writeln();
    b.writeln('When: ${formatTimestamp(when)}');
    b.writeln('App: LifeWave AI, $appVersionLabel');
    b.writeln('Device system: $platformLabel');
    b.writeln('Serious: ${fatal ? 'Yes — the app stopped.' : 'No — the app kept running.'}');
    if (repairMark != null) {
      b.writeln('Self-repair: ${repairOk ? 'REPAIRED' : 'REPAIR FAILED'}');
    }
    if (context != null) b.writeln('Where it happened: $context');
    b.writeln();
    b.writeln('What happened:');
    b.writeln('$errorType: $message');
    b.writeln();
    b.writeln(isRepair
        ? 'Evidence (what was found, done, and re-checked):'
        : 'Technical details (stack trace):');
    b.writeln(stackTrace.isEmpty ? '(no stack trace was provided)' : stackTrace);
    b.writeln();
    b.writeln('This report was saved by the app on this device only. '
        'It is never sent anywhere unless you share it.');
    return b.toString();
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// `2026-10-17 19:45:12` — local time, human readable.
  static String formatTimestamp(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)} '
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  /// `20261017-194512` — the timestamp embedded in the file name.
  static String fileTimestamp(DateTime t) =>
      '${t.year}${_two(t.month)}${_two(t.day)}-'
      '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';
}

/// Header facts the reports list shows without opening the file.
class CrashReportHeader {
  final String fileName;
  final String summaryLine;
  final String whenLabel;
  final bool fatal;

  /// Self-repair mark parsed from the report: 'repaired',
  /// 'repair-failed', or null for ordinary error reports.
  final String? repairMark;

  const CrashReportHeader({
    required this.fileName,
    required this.summaryLine,
    required this.whenLabel,
    required this.fatal,
    this.repairMark,
  });

  bool get isRepair => repairMark != null;

  /// Short label for the reports list.
  String get kindLabel {
    if (repairMark == 'repaired') return 'Self-repair — fixed';
    if (repairMark == 'repair-failed') return 'Self-repair — could not fix';
    return fatal ? 'The app stopped' : 'The app kept going';
  }

  /// Parses the header out of a stored report's text. Tolerant: a
  /// damaged file still lists, with what could be read.
  factory CrashReportHeader.parse(String fileName, String text) {
    final lines = text.split('\n');
    var summary = lines.isNotEmpty ? lines.first.trim() : '';
    if (summary.isEmpty) summary = 'A saved problem report.';
    var when = '';
    var serious = false;
    String? repair;
    for (final line in lines.take(10)) {
      final t = line.trim();
      if (t.startsWith('When: ')) when = t.substring(6);
      if (t.startsWith('Serious: Yes')) serious = true;
      if (t == 'Self-repair: REPAIRED') repair = 'repaired';
      if (t == 'Self-repair: REPAIR FAILED') repair = 'repair-failed';
    }
    return CrashReportHeader(
      fileName: fileName,
      summaryLine: summary,
      whenLabel: when,
      fatal: serious,
      repairMark: repair,
    );
  }
}

/// Picks the report file name for [when], adding `-2`, `-3`… when a
/// report from the same second already exists.
String crashReportFileName(DateTime when, bool Function(String) exists) {
  final base = 'Lifewave-crash-${CrashReportData.fileTimestamp(when)}';
  var name = '$base.txt';
  var n = 2;
  while (exists(name)) {
    name = '$base-$n.txt';
    n++;
  }
  return name;
}

// ---------------------------------------------------------------------------
// File IO seam — the app's own stored copies (app-documents folder).
// ---------------------------------------------------------------------------

/// Storage seam for the report store + persistent crash log. Unit tests
/// use [MemoryCrashFileIo]; the app uses [AppDocsCrashFileIo].
abstract class CrashFileIo {
  /// Names of stored report files, sorted (oldest name first).
  Future<List<String>> listReportNames();

  Future<String?> readReport(String name);

  /// Synchronous write — used at crash time, must not await.
  void writeReportSync(String name, String contents);

  /// Synchronous append to the persistent crash log — crash-time safe.
  void appendToLogSync(String entry);

  Future<void> deleteReport(String name);

  /// Full path of a stored report (for the share sheet); null when the
  /// IO has no real file system path (tests).
  Future<String?> reportPath(String name);
}

/// Real IO: app-documents `crash_reports/` folder + `crash_log.txt`
/// alongside it. The directory path is resolved once by
/// [CrashReporter.install] (before runApp) so crash-time writes are
/// purely synchronous `dart:io` calls.
class AppDocsCrashFileIo implements CrashFileIo {
  final String docsPath;
  AppDocsCrashFileIo(this.docsPath);

  String get _reportsDirPath => '$docsPath/crash_reports';
  String get _logPath => '$docsPath/crash_log.txt';

  Directory get _reportsDir => Directory(_reportsDirPath);

  @override
  Future<List<String>> listReportNames() async {
    final dir = _reportsDir;
    if (!await dir.exists()) return const [];
    final names = <String>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.txt')) {
        names.add(e.uri.pathSegments.last);
      }
    }
    names.sort();
    return names;
  }

  @override
  Future<String?> readReport(String name) async {
    final f = File('$_reportsDirPath/$name');
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  @override
  void writeReportSync(String name, String contents) {
    _reportsDir.createSync(recursive: true);
    File('$_reportsDirPath/$name').writeAsStringSync(contents, flush: true);
  }

  @override
  void appendToLogSync(String entry) {
    final f = File(_logPath);
    f.writeAsStringSync(entry, mode: FileMode.append, flush: true);
  }

  @override
  Future<void> deleteReport(String name) async {
    final f = File('$_reportsDirPath/$name');
    if (await f.exists()) await f.delete();
  }

  @override
  Future<String?> reportPath(String name) async => '$_reportsDirPath/$name';
}

/// In-memory IO for tests.
class MemoryCrashFileIo implements CrashFileIo {
  final Map<String, String> reports = {};
  String log = '';

  @override
  Future<List<String>> listReportNames() async {
    final names = reports.keys.toList()..sort();
    return names;
  }

  @override
  Future<String?> readReport(String name) async => reports[name];

  @override
  void writeReportSync(String name, String contents) {
    reports[name] = contents;
  }

  @override
  void appendToLogSync(String entry) {
    log += entry;
  }

  @override
  Future<void> deleteReport(String name) async {
    reports.remove(name);
  }

  @override
  Future<String?> reportPath(String name) async =>
      reports.containsKey(name) ? '/memory/$name' : null;
}

// ---------------------------------------------------------------------------
// Downloads mirror seam.
// ---------------------------------------------------------------------------

/// Writes a copy of a report into the device's Downloads folder.
/// Returns true when the copy landed. Best-effort by contract: the
/// caller never depends on this succeeding.
abstract class DownloadsMirror {
  Future<bool> writeToDownloads(String fileName, String contents);
}

/// Production mirror:
///  - Windows / desktop: the user's Downloads folder via path_provider.
///  - Android: the `lifewave/downloads` MethodChannel (MediaStore — see
///    MainActivity.kt). path_provider's Android downloads directory is
///    app-private, NOT the public Downloads folder, so it is not used.
class PlatformDownloadsMirror implements DownloadsMirror {
  static const MethodChannel _channel = MethodChannel('lifewave/downloads');

  /// Platform check seam (tests override).
  final bool Function() _isAndroid;
  final bool Function() _isWindows;

  PlatformDownloadsMirror({
    bool Function()? isAndroid,
    bool Function()? isWindows,
  })  : _isAndroid = isAndroid ?? (() => Platform.isAndroid),
        _isWindows = isWindows ?? (() => Platform.isWindows);

  @override
  Future<bool> writeToDownloads(String fileName, String contents) async {
    try {
      if (_isAndroid()) {
        final ok = await _channel.invokeMethod<bool>(
          'writeTextFile',
          {'name': fileName, 'contents': contents},
        );
        return ok ?? false;
      }
      if (_isWindows()) {
        final dir = await getDownloadsDirectory();
        if (dir == null) return false;
        await File('${dir.path}${Platform.pathSeparator}$fileName')
            .writeAsString(contents, flush: true);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

/// Test mirror: records what would have been written.
class MemoryDownloadsMirror implements DownloadsMirror {
  final Map<String, String> written = {};
  bool succeed = true;

  @override
  Future<bool> writeToDownloads(String fileName, String contents) async {
    if (succeed) written[fileName] = contents;
    return succeed;
  }
}

// ---------------------------------------------------------------------------
// The reporter.
// ---------------------------------------------------------------------------

class CrashReporter {
  final CrashFileIo io;
  final DownloadsMirror mirror;
  final String appVersionLabel;
  final String platformLabel;
  final DateTime Function() _now;

  /// Set when the Downloads mirror succeeded for the latest report —
  /// Diagnostics-view honesty (a report that only exists in-app is
  /// still listed there; nothing pretends otherwise).
  bool? lastMirrorOk;

  CrashReporter({
    required this.io,
    required this.mirror,
    required this.appVersionLabel,
    required this.platformLabel,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static CrashReporter? _active;

  /// The installed reporter, or null before [install] / in tests that
  /// never installed one (recording is then a no-op by design).
  static CrashReporter? get active => _active;

  /// Records a caught error from a risky path (non-fatal unless
  /// [fatal]). Safe to call from anywhere: never throws.
  static void recordCaught(
    Object error,
    StackTrace? stack, {
    String? context,
    bool fatal = false,
  }) {
    _active?.record(error, stack, context: context, fatal: fatal);
  }

  /// Installs the global handlers and returns the active reporter.
  /// Called once in main(), before runApp, inside the Zone guard.
  /// Never throws: if the directories cannot be resolved, the reporter
  /// stays inactive and the app still starts (debugPrint only).
  static Future<CrashReporter?> install() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final reporter = CrashReporter(
        io: AppDocsCrashFileIo(docs.path),
        mirror: PlatformDownloadsMirror(),
        appVersionLabel: AppInfo.versionLabel,
        platformLabel:
            '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      );
      _active = reporter;
      reporter._installHandlers();
      return reporter;
    } catch (e) {
      debugPrint('CrashReporter install failed: $e');
      return null;
    }
  }

  void _installHandlers() {
    final previousFlutterOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      record(
        details.exception,
        details.stack,
        context: details.context?.toString(),
        fatal: true,
      );
      // Keep the framework's own reporting (console dump in debug,
      // red screen handling stays with the framework's ErrorWidget).
      if (previousFlutterOnError != null) {
        previousFlutterOnError(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack, fatal: true);
      return true; // handled — recorded; do not re-crash the engine
    };
  }

  /// Entry point for the Zone guard in main().
  static void recordZoneError(Object error, StackTrace stack) {
    _active?.record(error, stack, fatal: true);
  }

  /// Records one error. Synchronous store + log write FIRST (survives
  /// a fatal crash), Downloads mirror second (best-effort, unawaited).
  /// Returns the stored file name, or null when nothing could be
  /// written. Never throws.
  String? record(
    Object error,
    StackTrace? stack, {
    String? context,
    bool fatal = false,
  }) {
    return _write(CrashReportData(
      when: _now(),
      fatal: fatal,
      context: context,
      errorType: error.runtimeType.toString(),
      message: error.toString(),
      stackTrace: stack?.toString() ?? '',
      appVersionLabel: appVersionLabel,
      platformLabel: platformLabel,
    ));
  }

  /// Records a self-repair outcome (standing self-repair rule): every
  /// repair — and every failed repair, with evidence — lands in the
  /// same report store, marked repaired / repair-failed. Never throws.
  String? recordRepair({
    required bool success,
    required String problem,
    required String evidence,
    String? context,
  }) {
    return _write(CrashReportData(
      when: _now(),
      fatal: false,
      context: context,
      errorType: 'SelfRepair',
      message: problem,
      stackTrace: evidence,
      appVersionLabel: appVersionLabel,
      platformLabel: platformLabel,
      repairMark: success ? 'repaired' : 'repair-failed',
    ));
  }

  /// Static facade for repair logging from anywhere in the app.
  static void recordRepairOutcome({
    required bool success,
    required String problem,
    required String evidence,
    String? context,
  }) {
    _active?.recordRepair(
      success: success,
      problem: problem,
      evidence: evidence,
      context: context,
    );
  }

  /// Test hook: installs [reporter] as the active one (or clears it).
  @visibleForTesting
  static void setActiveForTest(CrashReporter? reporter) {
    _active = reporter;
  }

  String? _write(CrashReportData data) {
    try {
      final text = data.format();
      // Existence check must be synchronous (crash-time path): names
      // written this session are tracked in memory; for the real IO a
      // sync file probe covers reports from earlier sessions.
      final name = crashReportFileName(
        data.when,
        (candidate) =>
            _writtenNames.contains(candidate) ||
            (io is AppDocsCrashFileIo &&
                File('${(io as AppDocsCrashFileIo).docsPath}'
                        '/crash_reports/$candidate')
                    .existsSync()),
      );
      io.writeReportSync(name, text);
      _writtenNames.add(name);
      io.appendToLogSync('$text\n${'=' * 60}\n');
      // Mirror to Downloads — unawaited, failure-tolerant.
      unawaited(_mirrorToDownloads(name, text));
      return name;
    } catch (e) {
      debugPrint('CrashReporter record failed: $e');
      return null;
    }
  }

  Future<void> _mirrorToDownloads(String name, String text) async {
    try {
      lastMirrorOk = await mirror.writeToDownloads(name, text);
    } catch (_) {
      lastMirrorOk = false;
    }
  }

  final Set<String> _writtenNames = {};

  // --- Store API for the in-app reports view ---

  /// Stored reports, newest first.
  Future<List<CrashReportHeader>> listReports() async {
    final names = await io.listReportNames();
    final headers = <CrashReportHeader>[];
    for (final name in names) {
      final text = await io.readReport(name) ?? '';
      headers.add(CrashReportHeader.parse(name, text));
    }
    headers.sort((a, b) => b.fileName.compareTo(a.fileName));
    return headers;
  }

  Future<int> reportCount() async => (await io.listReportNames()).length;

  Future<String?> readReport(String name) => io.readReport(name);

  Future<String?> reportPath(String name) => io.reportPath(name);

  Future<void> deleteReport(String name) => io.deleteReport(name);
}
