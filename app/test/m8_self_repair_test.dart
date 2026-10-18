import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifewave_app/services/crash_reporter.dart';
import 'package:lifewave_app/services/self_repair.dart';
import 'package:lifewave_app/services/voice_service.dart';

/// v1.1.1 — self-repair (standing rule): conservative, verified, and
/// logged. Covers the formal runner, the settings loader (safe-default
/// restore preserving salvageable data), and one wired repair site
/// (Kokoro corrupt download → removed, never enabled, outcome logged).

/// Map-backed PrefsAccess with sabotage switches.
class FakePrefsAccess implements PrefsAccess {
  final Map<String, Object?> values;
  bool throwOnRead = false;
  bool throwOnRemove = false;
  FakePrefsAccess(this.values);

  @override
  Object? rawValue(String key) {
    if (throwOnRead) throw StateError('store unreadable');
    return values[key];
  }

  @override
  Future<void> remove(String key) async {
    if (throwOnRemove) throw StateError('cannot remove');
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SelfRepair.attempt — the formal runner', () {
    late MemoryCrashFileIo io;
    late CrashReporter reporter;

    setUp(() {
      io = MemoryCrashFileIo();
      reporter = CrashReporter(
        io: io,
        mirror: MemoryDownloadsMirror(),
        appVersionLabel: 'Version 1.1.1 (build 3)',
        platformLabel: 'test',
        now: () => DateTime(2026, 10, 17, 20, 0, 0),
      );
      CrashReporter.setActiveForTest(reporter);
    });

    tearDown(() => CrashReporter.setActiveForTest(null));

    test('success only when the post-repair check passes + logged repaired',
        () async {
      var state = 'broken';
      final ok = await SelfRepair.attempt(
        area: 'Test area',
        problem: 'State was broken.',
        evidence: 'Observed broken state.',
        repair: () async => state = 'fixed',
        verify: () async => state == 'fixed',
      );
      expect(ok, isTrue);
      final headers = await reporter.listReports();
      expect(headers, hasLength(1));
      expect(headers.single.repairMark, 'repaired');
    });

    test('verify failure -> repair-failed, never claimed as success',
        () async {
      final ok = await SelfRepair.attempt(
        area: 'Test area',
        problem: 'State was broken.',
        evidence: 'Observed broken state.',
        repair: () async {},
        verify: () async => false,
      );
      expect(ok, isFalse);
      final headers = await reporter.listReports();
      expect(headers.single.repairMark, 'repair-failed');
      final text = await reporter.readReport(headers.single.fileName);
      expect(text, contains('follow-up check still shows the problem'));
    });

    test('a throwing repair -> repair-failed with the error as evidence',
        () async {
      final ok = await SelfRepair.attempt(
        area: 'Test area',
        problem: 'State was broken.',
        evidence: 'Observed broken state.',
        repair: () async => throw StateError('cannot fix'),
        verify: () async => true,
      );
      expect(ok, isFalse);
      final headers = await reporter.listReports();
      expect(headers.single.repairMark, 'repair-failed');
      final text = await reporter.readReport(headers.single.fileName);
      expect(text, contains('The repair itself failed'));
      expect(text, contains('cannot fix'));
    });
  });

  group('SafePrefsLoader — settings repair', () {
    test('healthy settings are preserved untouched, no repairs', () async {
      final access = FakePrefsAccess({
        'display_name': 'Jamie',
        'welcome_dismissed': true,
        'emotion_level': 'expressive',
        'voice_key': 'kokoro|af_heart|Heart',
        'chat_language': 'vi',
        'tour_seen': true,
        'referral_link': 'https://example.com/ref',
      });
      final loaded = await SafePrefsLoader(
        access,
        voiceValidator: (raw) => raw.split('|').length == 3,
      ).load();
      expect(loaded.displayName, 'Jamie');
      expect(loaded.welcomeDismissed, isTrue);
      expect(loaded.emotionLevelName, 'expressive');
      expect(loaded.voiceRaw, 'kokoro|af_heart|Heart');
      expect(loaded.chatLanguageCode, 'vi');
      expect(loaded.tourSeen, isTrue);
      expect(loaded.referralLink, 'https://example.com/ref');
      expect(loaded.repairs, isEmpty);
      expect(access.values.length, 7); // nothing was removed
    });

    test('one damaged entry is reset; the rest survive (salvage)',
        () async {
      final access = FakePrefsAccess({
        'display_name': 42, // wrong type — the corruption shape
        'welcome_dismissed': true,
        'chat_language': 'fr',
        'tour_seen': 'yes', // wrong type too
      });
      final loaded = await SafePrefsLoader(access).load();
      expect(loaded.displayName, isNull); // safe default
      expect(loaded.tourSeen, isFalse); // safe default
      expect(loaded.welcomeDismissed, isTrue); // preserved
      expect(loaded.chatLanguageCode, 'fr'); // preserved
      expect(access.values.containsKey('display_name'), isFalse);
      expect(access.values.containsKey('tour_seen'), isFalse);
      expect(loaded.repairs, hasLength(2));
      expect(loaded.repairs.every((r) => r.success), isTrue);
      expect(loaded.repairs.map((r) => r.subject),
          containsAll(['display_name', 'tour_seen']));
    });

    test('an undecodable saved voice is reset to the default voice',
        () async {
      final access = FakePrefsAccess({'voice_key': 'garbage-value'});
      final loaded = await SafePrefsLoader(
        access,
        voiceValidator: (raw) => raw.split('|').length == 3,
      ).load();
      expect(loaded.voiceRaw, isNull);
      expect(access.values.containsKey('voice_key'), isFalse);
      expect(loaded.repairs.single.subject, 'voice_key');
      expect(loaded.repairs.single.success, isTrue);
    });

    test('a removal that fails is logged repair-failed, defaults still used',
        () async {
      final access = FakePrefsAccess({'display_name': 42})
        ..throwOnRemove = true;
      final loaded = await SafePrefsLoader(access).load();
      expect(loaded.displayName, isNull);
      expect(loaded.repairs.single.success, isFalse);
      expect(loaded.repairs.single.evidence, contains('failed'));
    });

    test('an unreadable store degrades to defaults, repair attempted',
        () async {
      final access = FakePrefsAccess({'display_name': 'Jamie'})
        ..throwOnRead = true;
      final loaded = await SafePrefsLoader(access).load();
      expect(loaded.displayName, isNull);
      expect(loaded.repairs, isNotEmpty);
      expect(loaded.repairs.every((r) => !r.success), isTrue);
    });
  });

  group('Kokoro download repair wiring', () {
    late Directory tmp;
    late MemoryCrashFileIo io;
    late CrashReporter reporter;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('lw_m8_');
      io = MemoryCrashFileIo();
      reporter = CrashReporter(
        io: io,
        mirror: MemoryDownloadsMirror(),
        appVersionLabel: 'Version 1.1.1 (build 3)',
        platformLabel: 'test',
        now: () => DateTime(2026, 10, 17, 20, 5, 0),
      );
      CrashReporter.setActiveForTest(reporter);
    });

    tearDown(() async {
      CrashReporter.setActiveForTest(null);
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    Future<void> writeSizedFile(String dest, int bytes) async {
      final f = File(dest);
      await f.create(recursive: true);
      final raf = await f.open(mode: FileMode.write);
      await raf.setPosition(bytes - 1);
      await raf.writeByte(0);
      await raf.close();
    }

    test('hash failure: file removed, never ready, repair logged repaired',
        () async {
      final manager = VoiceModelManager(
        dirProvider: () async => tmp.path,
        downloader: (url, dest, onProgress) async {
          await writeSizedFile(dest, KokoroModelSource.expectedBytes);
        },
        verifier: (_) async => false, // hash mismatch
        extractor: (archive, destDir) async {},
      );
      final ok = await manager.download();
      expect(ok, isFalse);
      expect(manager.state, VoiceModelState.error);
      expect(manager.isReady, isFalse);
      final archive = File('${tmp.path}/${KokoroModelSource.archiveName}');
      expect(await archive.exists(), isFalse); // removed, never usable

      final headers = await reporter.listReports();
      final repair =
          headers.where((h) => h.repairMark == 'repaired').toList();
      expect(repair, hasLength(1));
      final text = await reporter.readReport(repair.single.fileName);
      expect(text, contains('SHA-256'));
      expect(text, contains('Self-repair — Kokoro voice download'));
    });

    test('incomplete download: not enabled, quarantine logged', () async {
      final manager = VoiceModelManager(
        dirProvider: () async => tmp.path,
        downloader: (url, dest, onProgress) async {
          await writeSizedFile(dest, 1024); // far too small
        },
        verifier: (_) async => true,
        extractor: (archive, destDir) async {},
      );
      final ok = await manager.download();
      expect(ok, isFalse);
      expect(manager.isReady, isFalse);
      final headers = await reporter.listReports();
      final repair =
          headers.where((h) => h.repairMark == 'repaired').toList();
      expect(repair, hasLength(1));
      final text = await reporter.readReport(repair.single.fileName);
      expect(text, contains('incomplete'));
    });
  });
}
