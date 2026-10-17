import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifewave_app/screens/guide_screen.dart';
import 'package:lifewave_app/screens/tour_screen.dart';
import 'package:lifewave_app/services/guide_content.dart';
import 'package:lifewave_app/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('First-run tour', () {
    test('there are 5-6 cards and the first carries the '
        'independent-tool line', () {
      expect(kTourCards.length, inInclusiveRange(5, 6));
      expect(
        kTourCards.first.body,
        contains(
            'An independent Brand Partner tool — not an official LifeWave, Inc. app.'),
      );
    });

    testWidgets('tour shows; Skip finishes it', (tester) async {
      var done = false;
      await tester.pumpWidget(MaterialApp(
        theme: buildLifewaveTheme(),
        home: TourScreen(onDone: () => done = true),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to LifeWave AI'), findsOneWidget);
      expect(find.textContaining('independent Brand Partner tool'),
          findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(done, isTrue);
    });

    testWidgets('tour swipes through to Done on the last card',
        (tester) async {
      var done = false;
      await tester.pumpWidget(MaterialApp(
        theme: buildLifewaveTheme(),
        home: TourScreen(onDone: () => done = true),
      ));
      await tester.pumpAndSettle();
      for (var i = 0; i < kTourCards.length - 1; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Done — start using the app'), findsOneWidget);
      await tester.tap(find.text('Done — start using the app'));
      await tester.pumpAndSettle();
      expect(done, isTrue);
    });
  });

  group('Guide screen', () {
    testWidgets('section list renders every section; asking the guide '
        'a scheduling question opens the scheduling section',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildLifewaveTheme(),
        home: const GuideScreen(),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Guide'), findsOneWidget);
      expect(find.text('Getting started'), findsWidgets);
      // Ask the guide.
      await tester.enterText(
          find.byType(TextField), 'how do I schedule a post');
      await tester.tap(find.text('Ask the guide'));
      await tester.pumpAndSettle();
      // The scheduling section opened (its title + body steps show).
      expect(find.text('Schedule a post'), findsWidgets);
      expect(find.textContaining('the app queues your post'),
          findsOneWidget);
    });

    testWidgets('opening at a section renders its steps and the '
        'troubleshooting content', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildLifewaveTheme(),
        home: const GuideScreen(initialSectionKey: 'troubleshooting'),
      ));
      await tester.pumpAndSettle();
      expect(
          find.text('What to do when… (troubleshooting)'), findsOneWidget);
      expect(find.textContaining('microphone does not hear me'),
          findsOneWidget);
    });

    test('guide search finds the troubleshooting section for a mic '
        'question', () {
      final hits = searchGuide('microphone does not hear me');
      expect(hits, isNotEmpty);
      expect(hits.map((s) => s.key), contains('troubleshooting'));
    });
  });
}
