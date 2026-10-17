import 'package:flutter_test/flutter_test.dart';
import 'package:lifewave_app/models/journey.dart';
import 'package:lifewave_app/models/social.dart';
import 'package:lifewave_app/services/brand_assets.dart';
import 'package:lifewave_app/services/compliance.dart';
import 'package:lifewave_app/services/cross_post.dart';
import 'package:lifewave_app/models/entry.dart';
import 'package:lifewave_app/services/demo.dart';
import 'package:lifewave_app/services/fact_card.dart';
import 'package:lifewave_app/services/guide_content.dart';
import 'package:lifewave_app/services/journey.dart';
import 'package:lifewave_app/services/knowledge_db.dart';
import 'package:lifewave_app/services/local_store.dart';
import 'package:lifewave_app/services/presentation.dart';
import 'package:lifewave_app/services/qr_kit.dart';
import 'package:lifewave_app/services/reminder_service.dart';
import 'package:lifewave_app/services/roleplay.dart';
import 'package:lifewave_app/services/social_store.dart';
import 'package:lifewave_app/services/translation_service.dart';
import 'package:lifewave_app/theme.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class FakeDemoEngines implements DemoEngines {
  final List<String> calls = [];
  bool sttAvailable = true;
  bool speakOk = true;
  bool throwOnPost = false;

  @override
  Future<bool> speechInputAvailable() async {
    calls.add('stt');
    return sttAvailable;
  }

  @override
  Future<({String display, String speakable})> answerQuestion(
      String question) async {
    calls.add('answer');
    return (
      display: 'X39 is the flagship patch.',
      speakable: '[warm] X39 is the flagship patch.'
    );
  }

  @override
  Future<bool> speak(String markedText) async {
    calls.add('speak');
    return speakOk;
  }

  @override
  Future<({String text, String adapted})> translateSample(
      String text, String toCode) async {
    calls.add('translate');
    return (text: '¡Hola!', adapted: '');
  }

  @override
  Future<String> generateSamplePost(KnowledgeEntry product) async {
    calls.add('post');
    if (throwOnPost) throw StateError('engine blew up');
    return 'Quick question — what helps your energy?';
  }

  @override
  FactCardData sampleFactCard(KnowledgeEntry product) {
    calls.add('factcard');
    return const FactCardData(
      productId: 'prod-x39',
      productTitle: 'LifeWave X39® Patches',
      imageAssetPath: null,
      fact: 'A fact.',
      question: 'A question?',
      claimLabel: 'official fact',
    );
  }
}

Future<SocialStore> loadedStore(MemoryFileIo io) async {
  final store = SocialStore(
    doc: JsonDocumentStore(io: io),
    reminders: FakeReminderScheduler(),
  );
  await store.load();
  return store;
}

// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Roleplay practice', () {
    late KnowledgeDb db;
    late RoleplayEngine engine;
    setUpAll(() async {
      db = await KnowledgeDb.load();
      engine = RoleplayEngine(db);
    });

    test('every persona is bound to a real faq entry', () {
      expect(engine.personas.length, 4);
      for (final p in engine.personas) {
        expect(db.byId(p.faqEntryId), isNotNull, reason: p.id);
        expect(engine.start(p), isNotNull, reason: p.id);
      }
    });

    test('scenario advances: prospect reacts and the round completes '
        'after the scripted lines', () {
      final session = engine.start(engine.personaById('price-skeptic'))!;
      expect(session.isDone, isFalse);
      expect(session.openingMarked, contains('how much does this cost'));
      final r1 = session.answer('It depends on the option you pick.');
      expect(r1.nextMarkedLine, isNotNull);
      expect(session.isDone, isFalse);
      final r2 = session.answer('Let me explain the options.');
      // Third prospect line reached -> the round completes on the
      // NEXT answer (maxProspectLines counts spoken lines).
      expect(session.linesSpoken, RoleplaySession.maxProspectLines);
      final r3 = session.answer('And there is a guarantee.');
      expect(r3.nextMarkedLine, isNull);
      expect(session.isDone, isTrue);
      expect(r2.review, isNotNull);
    });

    test('prospect reacts to answer keywords (guarantee reaction)',
        () {
      final session = engine.start(engine.personaById('price-skeptic'))!;
      final r = session.answer(
          'There is a money-back guarantee, so you are not stuck.');
      expect(r.nextMarkedLine, contains('guarantee'));
    });

    test('coach flags a non-compliant practice answer (cure claim)',
        () {
      final session = engine.start(engine.personaById('works-skeptic'))!;
      final r = session.answer(
          'Oh yes, this cures your pain and you will feel it in a week!');
      expect(r.review.report.hasHits, isTrue);
      final cats = r.review.report.hits.map((h) => h.category).toSet();
      expect(cats, contains(ComplianceCategory.medicalClaim));
      expect(cats, contains(ComplianceCategory.promise));
    });

    test('coach marks key points covered from a good answer', () {
      final session = engine.start(engine.personaById('price-skeptic'))!;
      final r = session.answer(
          'There are two prices — the retail price and the lower '
          'Subscribe & Save monthly price. No pressure at all, and '
          'there is a 90-day money-back guarantee.');
      expect(r.review.missedPoints, isEmpty,
          reason: 'covered: ${r.review.coveredPoints}');
      expect(r.review.coveredPoints.length, 3);
      expect(r.review.report.isClean, isTrue);
    });

    test('suggested phrasing derives from the faq entry', () {
      for (final p in engine.personas) {
        final entry = db.byId(p.faqEntryId)!;
        final suggestion = suggestedPhrasingFor(entry, p.keyPoints);
        expect(suggestion, isNotEmpty, reason: p.id);
        final flatBody =
            entry.body.replaceAll(RegExp(r'\s+'), ' ').trim();
        expect(flatBody, contains(suggestion),
            reason: '${p.id}: suggestion must come from the entry');
        expect(const ComplianceScanner().scan(suggestion).isClean,
            isTrue,
            reason: '${p.id}: suggestion must be compliant');
      }
    });
  });

  group('60-second demo', () {
    late KnowledgeDb db;
    setUpAll(() async {
      db = await KnowledgeDb.load();
    });

    test('step sequence runs in the specced order and completes',
        () async {
      final engines = FakeDemoEngines();
      final runner = DemoRunner(
        engines: engines,
        db: db,
        targetLanguage: languageByCode('es'),
      );
      final steps = <DemoStep>[];
      while (!runner.isFinished) {
        final r = await runner.next();
        steps.add(r.step);
      }
      expect(steps, kDemoStepOrder);
      expect(runner.results.length, 6);
      // The real features were driven, in order.
      expect(engines.calls,
          ['stt', 'answer', 'speak', 'translate', 'speak', 'post', 'factcard']);
    });

    test('offline-safe: no STT + no speech adapts in-step and the demo '
        'still completes', () async {
      final engines = FakeDemoEngines()
        ..sttAvailable = false
        ..speakOk = false;
      final runner = DemoRunner(
        engines: engines,
        db: db,
        targetLanguage: languageByCode('es'),
      );
      final results = <DemoStepResult>[];
      while (!runner.isFinished) {
        results.add(await runner.next());
      }
      expect(results.length, 6);
      final qa = results.firstWhere((r) => r.step == DemoStep.voiceQa);
      expect(qa.note, contains('typed instead'));
      final closing =
          results.firstWhere((r) => r.step == DemoStep.closing);
      expect(closing.bodyText, contains('That was the short tour'));
    });

    test('a hard engine failure becomes an adaptation, not a crash',
        () async {
      final engines = FakeDemoEngines()..throwOnPost = true;
      final runner = DemoRunner(
        engines: engines,
        db: db,
        targetLanguage: languageByCode('es'),
      );
      final results = <DemoStepResult>[];
      while (!runner.isFinished) {
        results.add(await runner.next());
      }
      final post = results.firstWhere((r) => r.step == DemoStep.post);
      expect(post.bodyText, contains('could not run'));
      expect(results.last.step, DemoStep.closing);
    });
  });

  group('Presentation mode', () {
    late KnowledgeDb db;
    late BrandAssets brand;
    setUpAll(() async {
      db = await KnowledgeDb.load();
      brand = await BrandAssets.load();
    });

    test('every slide fact line is scanner-clean and verbatim from '
        'its entry', () {
      const scanner = ComplianceScanner();
      final slides = buildSlides(
        db.byTopic('products'),
        imageFor: brand.productImageFor,
      );
      expect(slides.length, db.byTopic('products').length);
      for (final slide in slides) {
        final entry = db.byId(slide.productId)!;
        expect(slide.factLines, isNotEmpty, reason: slide.productId);
        expect(slide.factLines.length, lessThanOrEqualTo(3));
        for (final line in slide.factLines) {
          expect(scanner.scan(line).isClean, isTrue,
              reason: '${slide.productId}: $line');
          expect(
            entry.body.replaceAll(RegExp(r'\s+'), ' '),
            contains(line),
            reason: '${slide.productId}: line must come from the entry',
          );
        }
      }
    });

    test('flagship default set resolves to real products', () {
      final picked = flagshipProducts(db.byTopic('products'));
      expect(picked.length, greaterThanOrEqualTo(4));
      expect(picked.map((p) => p.id), contains('prod-x39'));
    });

    test('caption cache keys by slide + language', () {
      final cache = CaptionCache();
      cache.put('prod-x39', 'es', 'Hola');
      cache.put('prod-x39', 'fr', 'Bonjour');
      cache.put('prod-x49', 'es', 'Hola X49');
      expect(cache.get('prod-x39', 'es'), 'Hola');
      expect(cache.get('prod-x39', 'fr'), 'Bonjour');
      expect(cache.get('prod-x49', 'es'), 'Hola X49');
      expect(cache.get('prod-x49', 'fr'), isNull);
      expect(cache.size, 3);
      expect(captionCacheKey('prod-x39', 'es'), 'prod-x39|es');
    });
  });

  group('Customer journey', () {
    Customer customerStarting(DateTime start) => Customer(
          id: 'c1',
          name: 'Jamie Lee',
          productTitle: 'LifeWave X39® Patches',
          startDate: start,
        );

    test('day math: day 1 is the start date', () {
      final start = DateTime(2026, 10, 17, 15, 30);
      expect(journeyDay(customerStarting(start), DateTime(2026, 10, 17, 9)), 1);
      expect(journeyDay(customerStarting(start), DateTime(2026, 10, 18)), 2);
      expect(journeyDay(customerStarting(start), DateTime(2026, 11, 15)), 30);
      expect(journeyDay(customerStarting(start), DateTime(2026, 10, 16)), 0);
    });

    test('check-ins are due at days 3, 7 and 30 only', () {
      final c = customerStarting(DateTime(2026, 10, 1));
      expect(dueCheckIns(c, DateTime(2026, 10, 2)), isEmpty); // day 2
      expect(dueCheckIns(c, DateTime(2026, 10, 3)), [3]); // day 3
      expect(dueCheckIns(c, DateTime(2026, 10, 7)), [3, 7]); // day 7
      expect(dueCheckIns(c, DateTime(2026, 10, 30)), [3, 7, 30]);
      // Handed off / done milestones stop being due.
      c.checkInsHandedOff.add(3);
      c.checkInsDone.add(7);
      expect(dueCheckIns(c, DateTime(2026, 10, 30)), [30]);
    });

    test('reorder is due at day >= 25 until marked reordered', () {
      final c = customerStarting(DateTime(2026, 9, 22));
      expect(reorderDue(c, DateTime(2026, 10, 16)), isTrue); // day 25
      expect(reorderDue(c, DateTime(2026, 10, 15)), isFalse); // day 24
      c.reordered = true;
      expect(reorderDue(c, DateTime(2026, 10, 16)), isFalse);
    });

    test('check-in and reorder drafts scan clean and carry the '
        'product + group invite', () async {
      final db = await KnowledgeDb.load();
      final c = customerStarting(DateTime(2026, 10, 15));
      const scanner = ComplianceScanner();
      for (final day in kCheckInDays) {
        final draft = composeCheckInDraft(customer: c, day: day, db: db);
        expect(scanner.scan(draft).isClean, isTrue, reason: 'day $day');
        expect(draft, contains('Jamie'), reason: 'day $day');
        expect(draft, contains('LW Team Learning'), reason: 'day $day');
      }
      final reorder = composeReorderDraft(customer: c, db: db);
      expect(scanner.scan(reorder).isClean, isTrue);
      expect(reorder, contains('Subscribe & Save'));
    });

    test('placement pointers surface official usage entries + the '
        'pointer line only', () async {
      final db = await KnowledgeDb.load();
      final pointers = PlacementPointers.fromDb(db);
      expect(pointers.usageEntries, isNotEmpty);
      expect(pointers.usageEntries.every((e) => e.topic == 'usage'),
          isTrue);
      expect(PlacementPointers.pointerLine, contains('LW Team Learning'));
      expect(PlacementPointers.pointerLine, contains('lives in'));
    });

    test('journal isolation: notes live per customer and survive a '
        'store round-trip', () async {
      final io = MemoryFileIo();
      final store = await loadedStore(io);
      final a = await store.addCustomer(
          name: 'Ann', startDate: DateTime(2026, 10, 1));
      final b = await store.addCustomer(
          name: 'Bob', startDate: DateTime(2026, 10, 5));
      await store.addJournalEntry(a, 3, 'Said mornings feel easier');
      await store.addJournalEntry(a, 7, 'Routine is set');
      await store.addJournalEntry(b, 2, 'Asked about the group');
      expect(store.journalFor(a).length, 2);
      expect(store.journalFor(b).length, 1);
      expect(store.journalFor(b).single.text, 'Asked about the group');

      final store2 = await loadedStore(io);
      expect(store2.customers.length, 2);
      final a2 = store2.customerById(a.id)!;
      expect(store2.journalFor(a2).length, 2);
      expect(store2.journalFor(store2.customerById(b.id)!).length, 1);
    });

    test('Today reorders count is REAL: day >= 25 and not reordered',
        () async {
      final io = MemoryFileIo();
      final store = await loadedStore(io);
      final now = DateTime(2026, 10, 17, 10);
      await store.addCustomer(
          name: 'Due', startDate: DateTime(2026, 9, 20)); // day 28
      await store.addCustomer(
          name: 'Early', startDate: DateTime(2026, 10, 10)); // day 8
      final done = await store.addCustomer(
          name: 'Done', startDate: DateTime(2026, 9, 1)); // day 47
      await store.markReordered(done);
      expect(store.todayCounts(now).reordersDue, 1);
      final due = store.customers.firstWhere((c) => c.name == 'Due');
      await store.markReordered(due);
      expect(store.todayCounts(now).reordersDue, 0);
    });
  });

  group('My QR kit', () {
    test('URL validation rejects non-URLs and accepts http/https', () {
      expect(isValidReferralLink('https://lifewave.com/mystore'), isTrue);
      expect(isValidReferralLink('http://example.com/x'), isTrue);
      expect(isValidReferralLink(''), isFalse);
      expect(isValidReferralLink('not a url'), isFalse);
      expect(isValidReferralLink('lifewave.com/mystore'), isFalse);
      expect(isValidReferralLink('ftp://example.com'), isFalse);
      expect(isValidReferralLink('https://'), isFalse);
      expect(referralLinkProblem('notaurl'), isNotNull);
    });

    test('one-pager model contains the link + the disclaimer line',
        () async {
      final db = await KnowledgeDb.load();
      final blurb = companyBlurbFrom(db.byId('comp-story'));
      expect(blurb, contains('founded in 2004'));
      final pager = QrOnePager(
        displayName: 'Alex Partner',
        referralLink: 'https://lifewave.com/alex',
        logoAssetPath: 'assets/brand/lifewave-logo.svg',
        companyBlurb: blurb,
      );
      expect(pager.allText, contains('https://lifewave.com/alex'));
      expect(pager.allText, contains(AppInfo.independentToolLine));
      expect(QrOnePager.disclaimerLine,
          'An independent Brand Partner tool — not an official LifeWave, Inc. app.');
    });
  });

  group('Cross-posting', () {
    const source =
        'Quick question — what helps your energy lately? More here: '
        'https://lifewave.com/example #wellness #energy';
    const formatter = CrossPostFormatter();

    test('the three variants differ as specced', () {
      final fb = formatter.format(SharePlatform.facebook, source);
      final ig = formatter.format(SharePlatform.instagram, source);
      final th = formatter.format(SharePlatform.threads, source);
      expect(fb.text, source.trim());
      expect(ig.text, isNot(fb.text));
      expect(th.text, fb.text); // Threads keeps the text; guidance differs
      expect(th.guidance, contains('Length looks good'));
    });

    test('Instagram moves the link to a bio line and groups hashtags '
        'at the end', () {
      final ig = formatter.format(SharePlatform.instagram, source);
      expect(ig.text, isNot(contains('https://')));
      expect(ig.text, contains('Link in bio'));
      expect(ig.text.trimRight().endsWith('#wellness #energy'), isTrue,
          reason: ig.text);
      // The body itself keeps neither the bare link nor stray hashtags.
      final body = ig.text.split('\n\n').first;
      expect(body, isNot(contains('#')));
      expect(body, contains('what helps your energy'));
    });

    test('Threads guidance flags over-length posts with a count', () {
      final long = 'a' * 600;
      final th = formatter.format(SharePlatform.threads, long);
      expect(th.charCount, 600);
      expect(th.guidance, contains('600 characters'));
      expect(th.guidance, contains('$kThreadsGuidanceChars'));
    });

    test('the compliance scan re-runs per variant', () {
      const bad = 'This cures everything, trust me';
      for (final p in SharePlatform.values) {
        final v = formatter.format(p, bad);
        expect(v.report.hasHits, isTrue, reason: p.name);
      }
      final clean = formatter.formatAll(source);
      for (final v in clean) {
        expect(v.report.isClean, isTrue, reason: v.platform.name);
      }
    });

    test('handoff labels are honest — never "posted"', () async {
      final label = platformHandoffLabel(
          SharePlatform.instagram, DateTime(2026, 10, 17, 14, 5));
      expect(label, startsWith('Opened share sheet for Instagram at'));
      expect(label.toLowerCase(), isNot(contains('posted')));

      // Store-level: marking a handoff records the label on the draft.
      final io = MemoryFileIo();
      final store = await loadedStore(io);
      final post = PostDraft(id: store.newId('post'), text: source);
      await store.addPost(post);
      await store.markPlatformHandoff(post, SharePlatform.threads,
          when: DateTime(2026, 10, 17, 9, 0));
      expect(post.platformHandoffs['threads'],
          contains('Opened share sheet for Threads'));
      final store2 = await loadedStore(io);
      expect(store2.posts.single.platformHandoffs['threads'],
          post.platformHandoffs['threads']);
    });
  });

  group('User guide', () {
    test('coverage: EVERY feature key has a guide section', () {
      for (final feature in kGuideFeatureKeys) {
        expect(guideSectionForFeature(feature), isNotNull,
            reason: 'missing guide section for feature: $feature');
      }
      expect(kGuideSections.length,
          greaterThanOrEqualTo(kGuideFeatureKeys.length));
      // Keys are unique (list/search/help all key off them).
      expect(kGuideSections.map((s) => s.key).toSet().length,
          kGuideSections.length);
    });

    test('search: "how do I schedule a post" finds the scheduling '
        'section first', () {
      final hits = searchGuide('how do I schedule a post');
      expect(hits, isNotEmpty);
      expect(hits.first.key, 'schedule-post');
    });

    test('troubleshooting section exists and covers the specced cases',
        () {
      final t = guideSectionByKey('troubleshooting');
      expect(t, isNotNull);
      final body = t!.body.toLowerCase();
      expect(body, contains('microphone'));
      expect(body, contains('voice sounds'));
      expect(body, contains('download'));
      expect(body, contains('queue'));
      expect(body, contains("cloud isn't set up"));
    });

    test('the About section carries the EXACT independent-tool line',
        () {
      final about = guideSectionByKey('about');
      expect(about, isNotNull);
      expect(
        about!.body,
        contains(
            'An independent Brand Partner tool — not an official LifeWave, Inc. app.'),
      );
    });

    test('every per-screen help target resolves to a real section', () {
      for (final entry in kScreenHelpSections.entries) {
        expect(guideSectionByKey(entry.value), isNotNull,
            reason: 'screen ${entry.key} -> ${entry.value}');
      }
    });

    test('quick-start has the 6 first steps', () {
      expect(kQuickStartSteps.length, 6);
    });
  });
}
