import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifewave_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // M3 startup touches three plugin channels that have no test-host
    // implementation. Mock them the way a real device behaves, so the
    // boot flow (store load + reminder setup) runs end to end.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      (call) async => 'America/Los_Angeles',
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async => true,
    );
  });

  testWidgets('app boots splash -> first-run tour -> home; Today card '
      'renders; catalog shows a product card with its picture',
      (WidgetTester tester) async {
    await tester.pumpWidget(const LifewaveApp());

    // Splash is the first route.
    expect(find.text('Loading your database…'), findsOneWidget);

    // Let loading finish. M3 startup also reads a real file (the local
    // store) via dart:io, whose completions arrive on the real event
    // loop — so give the app real time inside runAsync, then settle.
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // M4: the FIRST-RUN TOUR replaces the M1 welcome card. Its first
    // card carries the independent-tool line.
    expect(find.text('Welcome to LifeWave AI'), findsOneWidget);
    expect(find.textContaining('independent Brand Partner tool'),
        findsOneWidget);

    // Skip the tour -> the shell (tour shows once; the "seen" state
    // is covered by the tour tests + the persisted pref).
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Home: branded header + Today card. The rows read the real
    // (empty, first-run) stores — honest zeros, Reorders included
    // (real since M4).
    expect(find.text('Welcome to your LifeWave helper'), findsOneWidget);
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Replies waiting'), findsOneWidget);
    expect(find.text('Posts scheduled'), findsOneWidget);
    expect(find.text('Follow-ups due'), findsOneWidget);
    expect(find.text('Reorders due'), findsOneWidget);
    expect(find.text('0 — Nothing waiting'), findsOneWidget);
    expect(find.text('0 — Nothing scheduled'), findsOneWidget);
    // Follow-ups and Reorders both read "0 — Nothing due" when empty.
    expect(find.text('0 — Nothing due'), findsNWidgets(2));
    expect(
      find.textContaining('From your Customer Journey'),
      findsOneWidget,
    );
    // The demo is launched from Home (below the fold — scroll to it).
    await tester.scrollUntilVisible(
        find.text('Show me what you can do'), 200);
    await tester.pumpAndSettle();
    expect(find.text('Show me what you can do'), findsOneWidget);

    // Bottom navigation is present.
    expect(find.text('Catalog'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);

    // Catalog: the X39 product card renders with its official picture.
    await tester.tap(find.text('Catalog'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('LifeWave X39® Patches'), findsWidgets);
    expect(find.byType(Image), findsWidgets);
    expect(find.text('Official fact'), findsWidgets);
  });
}
