import 'package:flutter_test/flutter_test.dart';
import 'package:lifewave_app/services/crash_reporter.dart';
import 'package:lifewave_app/services/share_service.dart';
import 'package:lifewave_app/screens/crash_reports_screen.dart';
import 'package:flutter/material.dart';

/// v1.1.1 — crash & error reporting (standing rule): capture format,
/// the store, the Downloads mirror contract, and the in-app view.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixedNow = DateTime(2026, 10, 17, 19, 45, 12);

  CrashReporter makeReporter(
    MemoryCrashFileIo io,
    MemoryDownloadsMirror mirror,
  ) =>
      CrashReporter(
        io: io,
        mirror: mirror,
        appVersionLabel: 'Version 1.1.1 (build 3)',
        platformLabel: 'android 14 (test)',
        now: () => fixedNow,
      );

  group('report format', () {
    test('fatal report: plain-language first line + all required fields',
        () {
      final data = CrashReportData(
        when: fixedNow,
        fatal: true,
        context: null,
        errorType: 'StateError',
        message: 'Bad state: no element',
        stackTrace: '#0 main (main.dart:1)',
        appVersionLabel: 'Version 1.1.1 (build 3)',
        platformLabel: 'android 14 (test)',
      );
      final text = data.format();
      final lines = text.split('\n');
      expect(lines.first, 'LifeWave AI stopped working because of a problem.');
      expect(text, contains('When: 2026-10-17 19:45:12'));
      expect(text, contains('App: LifeWave AI, Version 1.1.1 (build 3)'));
      expect(text, contains('Device system: android 14 (test)'));
      expect(text, contains('StateError: Bad state: no element'));
      expect(text, contains('#0 main (main.dart:1)'));
      expect(text, contains('never sent anywhere unless you share it'));
    });

    test('non-fatal report says the app kept going', () {
      final data = CrashReportData(
        when: fixedNow,
        fatal: false,
        context: 'Update check',
        errorType: 'Exception',
        message: 'no connection',
        stackTrace: '',
        appVersionLabel: 'Version 1.1.1 (build 3)',
        platformLabel: 'windows 11 (test)',
      );
      final text = data.format();
      expect(text.split('\n').first,
          'LifeWave AI hit a problem, but kept going.');
      expect(text, contains('Where it happened: Update check'));
      expect(text, contains('(no stack trace was provided)'));
    });

    test('file name format + same-second collision suffixes', () {
      final taken = <String>{};
      String pick() {
        final n = crashReportFileName(fixedNow, taken.contains);
        taken.add(n);
        return n;
      }

      expect(pick(), 'Lifewave-crash-20261017-194512.txt');
      expect(pick(), 'Lifewave-crash-20261017-194512-2.txt');
      expect(pick(), 'Lifewave-crash-20261017-194512-3.txt');
    });
  });

  group('reporter store + mirror', () {
    test('record writes store + log FIRST and mirrors to Downloads',
        () async {
      final io = MemoryCrashFileIo();
      final mirror = MemoryDownloadsMirror();
      final reporter = makeReporter(io, mirror);

      final name = reporter.record(
        StateError('boom'),
        StackTrace.fromString('#0 somewhere'),
        fatal: true,
      );
      expect(name, 'Lifewave-crash-20261017-194512.txt');
      // Store + persistent log written synchronously.
      expect(io.reports.keys, contains(name));
      expect(io.log, contains('boom'));
      expect(io.log, contains('=' * 10));
      // Mirror is async best-effort; let it land.
      await Future<void>.delayed(Duration.zero);
      expect(mirror.written.keys, contains(name));
      expect(reporter.lastMirrorOk, isTrue);

      final headers = await reporter.listReports();
      expect(headers, hasLength(1));
      expect(headers.single.fatal, isTrue);
      expect(headers.single.kindLabel, 'The app stopped');
      expect(headers.single.whenLabel, '2026-10-17 19:45:12');
      expect(await reporter.reportCount(), 1);
      expect(await reporter.readReport(name!), contains('StateError'));
    });

    test('a failed Downloads mirror never loses the report', () async {
      final io = MemoryCrashFileIo();
      final mirror = MemoryDownloadsMirror()..succeed = false;
      final reporter = makeReporter(io, mirror);
      final name = reporter.record(Exception('x'), null);
      expect(name, isNotNull);
      await Future<void>.delayed(Duration.zero);
      expect(reporter.lastMirrorOk, isFalse);
      expect(await reporter.reportCount(), 1);
    });

    test('delete removes the stored copy', () async {
      final io = MemoryCrashFileIo();
      final reporter = makeReporter(io, MemoryDownloadsMirror());
      final name = reporter.record(Exception('gone soon'), null)!;
      expect(await reporter.reportCount(), 1);
      await reporter.deleteReport(name);
      expect(await reporter.reportCount(), 0);
      expect(await reporter.readReport(name), isNull);
    });

    test('recordCaught is a safe no-op without an installed reporter',
        () {
      CrashReporter.setActiveForTest(null);
      // Must not throw.
      CrashReporter.recordCaught(Exception('nobody listening'), null);
    });
  });

  group('repair records', () {
    test('recordRepair marks the record repaired / repair-failed',
        () async {
      final io = MemoryCrashFileIo();
      final reporter = makeReporter(io, MemoryDownloadsMirror());
      reporter.recordRepair(
        success: true,
        problem: 'A setting was damaged.',
        evidence: 'Removed and re-checked.',
        context: 'Self-repair — Saved settings',
      );
      reporter.recordRepair(
        success: false,
        problem: 'The database could not be opened.',
        evidence: 'Restore attempt failed too.',
        context: 'Self-repair — Knowledge database',
      );
      final headers = await reporter.listReports();
      expect(headers, hasLength(2));
      final marks = headers.map((h) => h.repairMark).toSet();
      expect(marks, {'repaired', 'repair-failed'});
      final ok = headers.firstWhere((h) => h.repairMark == 'repaired');
      expect(ok.isRepair, isTrue);
      expect(ok.kindLabel, 'Self-repair — fixed');
      expect(ok.summaryLine, contains('fixed it'));
      final bad = headers.firstWhere((h) => h.repairMark == 'repair-failed');
      expect(bad.kindLabel, 'Self-repair — could not fix');
      final text = await reporter.readReport(bad.fileName);
      expect(text, contains('Self-repair: REPAIR FAILED'));
      expect(text, contains('Evidence (what was found, done, and re-checked):'));
    });
  });

  group('reports screen (widget)', () {
    testWidgets('lists reports, opens one, deletes it', (tester) async {
      final io = MemoryCrashFileIo();
      final reporter = makeReporter(io, MemoryDownloadsMirror());
      reporter.record(StateError('screen boom'),
          StackTrace.fromString('#0 widget'), fatal: true);
      final share = FakeShareGateway();

      await tester.pumpWidget(MaterialApp(
        home: CrashReportsScreen(reporter: reporter, share: share),
      ));
      await tester.pumpAndSettle();
      expect(find.text('LifeWave AI stopped working because of a problem.'),
          findsOneWidget);
      expect(find.textContaining('The app stopped'), findsOneWidget);

      await tester.tap(find.text('LifeWave AI stopped working because of a problem.'));
      await tester.pumpAndSettle();
      expect(find.text('Problem report'), findsOneWidget);
      expect(find.textContaining('screen boom'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(await reporter.reportCount(), 0);
      expect(find.textContaining('No problem reports saved'), findsOneWidget);
    });

    testWidgets('empty state explains where reports would appear',
        (tester) async {
      final reporter =
          makeReporter(MemoryCrashFileIo(), MemoryDownloadsMirror());
      await tester.pumpWidget(MaterialApp(
        home: CrashReportsScreen(
            reporter: reporter, share: FakeShareGateway()),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('No problem reports saved'), findsOneWidget);
      expect(find.textContaining('sent anywhere'), findsOneWidget);
    });
  });
}
