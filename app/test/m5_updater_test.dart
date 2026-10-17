import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifewave_app/services/update_service.dart';

/// M5 updater tests — fakes only, NO real network.
String bodyFor(int code, {String name = '9.9.9'}) => jsonEncode({
      'android': {
        'versionCode': code,
        'versionName': name,
        'releaseTag': 'v$name',
        'asset': 'Lifewave-latest.apk',
      },
      'windows': {
        'version': name,
        'releaseTag': 'v$name',
        'asset': 'Lifewave-Setup.exe',
      },
    });

void main() {
  group('UpdateService', () {
    late MemoryUpdatePrefs prefs;
    late DateTime now;
    UpdateService make(Future<String> Function(Uri) fetcher,
            {int current = 1}) =>
        UpdateService(
          fetcher: fetcher,
          prefs: prefs,
          currentVersionCode: current,
          now: () => now,
        );

    setUp(() {
      prefs = MemoryUpdatePrefs();
      now = DateTime(2026, 10, 17, 12);
    });

    test('newer remote version is detected', () async {
      final svc = make((_) async => bodyFor(2, name: '1.1.0'));
      final r = await svc.check();
      expect(r.status, UpdateCheckStatus.updateAvailable);
      expect(r.remote?.versionCode, 2);
      expect(r.remote?.versionName, '1.1.0');
      expect(svc.shouldNotify, isTrue);
      expect(r.diagnosticsLabel, contains('Update available'));
    });

    test('same version does not notify', () async {
      final svc = make((_) async => bodyFor(1));
      final r = await svc.check();
      expect(r.status, UpdateCheckStatus.upToDate);
      expect(svc.shouldNotify, isFalse);
    });

    test('older remote version does not notify', () async {
      final svc = make((_) async => bodyFor(1), current: 5);
      final r = await svc.check();
      expect(r.status, UpdateCheckStatus.upToDate);
      expect(svc.shouldNotify, isFalse);
    });

    test('dismiss records the version and it never nags again; '
        'the next version may notify once', () async {
      var remoteCode = 2;
      final svc = make((_) async => bodyFor(remoteCode));
      await svc.check();
      expect(svc.shouldNotify, isTrue);
      await svc.dismissCurrent();
      expect(prefs.dismissedVersionCode, 2);
      expect(svc.shouldNotify, isFalse);
      // A fresh service over the same prefs still does not nag for v2.
      final svc2 = make((_) async => bodyFor(2));
      await svc2.check(force: true);
      expect(svc2.shouldNotify, isFalse);
      // But v3 may notify once.
      remoteCode = 3;
      final svc3 = make((_) async => bodyFor(remoteCode));
      await svc3.check(force: true);
      expect(svc3.shouldNotify, isTrue);
    });

    test('offline failure is silent (no throw) with honest diagnostics',
        () async {
      final svc = make((_) async => throw Exception('no network'));
      final r = await svc.check();
      expect(r.status, UpdateCheckStatus.couldNotCheck);
      expect(r.diagnosticsLabel, contains("Couldn't check"));
      expect(svc.shouldNotify, isFalse);
    });

    test('malformed version.json is couldNotCheck, not a crash', () async {
      final svc = make((_) async => '{"nope": true}');
      final r = await svc.check();
      expect(r.status, UpdateCheckStatus.couldNotCheck);
    });

    test('throttle: a second check within 24h does not fetch again',
        () async {
      var calls = 0;
      final svc = make((_) async {
        calls++;
        return bodyFor(1);
      });
      await svc.check();
      expect(calls, 1);
      now = now.add(const Duration(hours: 1));
      await svc.check();
      expect(calls, 1, reason: 'throttled inside 24h');
      now = now.add(const Duration(hours: 24));
      await svc.check();
      expect(calls, 2, reason: 'due again after the interval');
    });

    test('force bypasses the throttle (manual check)', () async {
      var calls = 0;
      final svc = make((_) async {
        calls++;
        return bodyFor(1);
      });
      await svc.check();
      await svc.check(force: true);
      expect(calls, 2);
    });

    test('contract URLs use the stable asset names', () {
      expect(UpdateService.versionJsonUri.toString(),
          'https://raw.githubusercontent.com/smartyourtv/lifewave-app/main/version.json');
      expect(UpdateService.downloadUri.toString(),
          'https://github.com/smartyourtv/lifewave-app/releases/latest/download/Lifewave-latest.apk');
      expect(UpdateService.windowsAssetName, 'Lifewave-Setup.exe');
    });
  });
}
