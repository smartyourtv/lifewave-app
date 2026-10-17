import 'package:flutter_test/flutter_test.dart';
import 'package:lifewave_app/models/social.dart';
import 'package:lifewave_app/services/brand_assets.dart';
import 'package:lifewave_app/services/calendar_logic.dart';
import 'package:lifewave_app/services/compliance.dart';
import 'package:lifewave_app/services/compliance_guide.dart';
import 'package:lifewave_app/services/fact_card.dart';
import 'package:lifewave_app/services/knowledge_db.dart';
import 'package:lifewave_app/services/local_store.dart';
import 'package:lifewave_app/services/post_generator.dart';
import 'package:lifewave_app/services/reminder_service.dart';
import 'package:lifewave_app/services/social_store.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

SocialStore makeStore(MemoryFileIo io, FakeReminderScheduler reminders) {
  return SocialStore(
    doc: JsonDocumentStore(io: io),
    reminders: reminders,
  );
}

Future<(SocialStore, FakeReminderScheduler, MemoryFileIo)> loadedStore() async {
  final io = MemoryFileIo();
  final reminders = FakeReminderScheduler();
  final store = makeStore(io, reminders);
  await store.load();
  return (store, reminders, io);
}

PostDraft draftPost(SocialStore store, String text) => PostDraft(
      id: store.newId('post'),
      text: text,
    );

// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Store persistence (JSON file in app documents)', () {
    test('round-trip: posts, replies, prospects, templates survive a '
        'reload through the same file', () async {
      final (store, reminders, io) = await loadedStore();
      final post = draftPost(store, 'A perfectly fine question post?');
      await store.addPost(post);
      await store.approvePost(post);
      final when = DateTime.now().add(const Duration(days: 1));
      final result = await store.queuePost(post,
          when: when, destination: PostDestination.facebookPage);
      expect(result.blockedBy, isNull);
      expect(result.reminderScheduled, isTrue);

      await store.addReply(ReplyDraft(
        id: store.newId('reply'),
        incomingText: 'How much does it cost?',
        draftText: 'Here is the short answer.',
      ));
      final prospect = await store.addProspect(
          name: 'Jamie', note: 'Asked about sleep', followUpDate: when);
      await store.advanceProspect(prospect);
      final tpl = await store.addTemplate(
          title: 'Price', text: 'It depends on the option you pick.');
      await store.setTemplateApproved(tpl, true);

      // A brand-new store over the same "file" sees everything.
      final store2 = makeStore(io, reminders);
      await store2.load();
      expect(store2.posts.length, 1);
      final p2 = store2.posts.single;
      expect(p2.text, 'A perfectly fine question post?');
      expect(p2.status, PostStatus.queued);
      expect(p2.destination, PostDestination.facebookPage);
      expect(p2.scheduledFor, when);
      expect(store2.replies.single.incomingText, 'How much does it cost?');
      expect(store2.prospects.single.name, 'Jamie');
      expect(store2.prospects.single.stage, ProspectStage.invited);
      expect(store2.quickTemplates.single.approved, isTrue);
      expect(store2.storeWarning, isNull);
    });

    test('corrupt file degrades to empty lists + a visible warning, '
        'never a crash, and the file is preserved aside', () async {
      final io = MemoryFileIo();
      io.files['social_store.json'] = 'this is {not] json at all';
      final store = makeStore(io, FakeReminderScheduler());
      await store.load();
      expect(store.posts, isEmpty);
      expect(store.replies, isEmpty);
      expect(store.prospects, isEmpty);
      expect(store.storeWarning, isNotNull);
      expect(store.storeWarning, contains('damaged'));
      expect(io.preserved, contains('social_store.json'));
      // And the store still works afterwards.
      await store.addProspect(name: 'Sam');
      expect(store.prospects.single.name, 'Sam');
    });

    test('missing file is a normal first run (empty, no warning)',
        () async {
      final (store, _, _) = await loadedStore();
      expect(store.posts, isEmpty);
      expect(store.storeWarning, isNull);
    });
  });

  group('Post queue state machine', () {
    test('a draft cannot be queued before approval', () async {
      final (store, reminders, _) = await loadedStore();
      final post = draftPost(store, 'What helps your energy?');
      await store.addPost(post);
      final result = await store.queuePost(post,
          when: DateTime.now().add(const Duration(hours: 2)),
          destination: PostDestination.personalProfile);
      expect(result.reminderScheduled, isFalse);
      expect(post.status, PostStatus.draft);
      expect(reminders.scheduled, isEmpty);
    });

    test('clean post: approve -> queue sets an inexact reminder and the '
        'honest "Reminder set for" label', () async {
      final (store, reminders, _) = await loadedStore();
      final post = draftPost(store, 'What helps your energy these days?');
      await store.addPost(post);
      expect(await store.approvePost(post), isTrue);
      expect(store.canQueue(post), isTrue);
      final when = DateTime.now().add(const Duration(days: 2));
      final result = await store.queuePost(post,
          when: when, destination: PostDestination.personalProfile);
      expect(result.blockedBy, isNull);
      expect(result.reminderScheduled, isTrue);
      expect(post.status, PostStatus.queued);
      expect(reminders.scheduled[post.reminderId], when);
      expect(post.status.label(scheduledFor: post.scheduledFor),
          startsWith('Reminder set for'));
    });

    test('flagged post is BLOCKED from queueing until fixed or '
        'explicitly overridden; the override is recorded', () async {
      final (store, _, _) = await loadedStore();
      final post = draftPost(store, 'This patch cures back pain fast!');
      await store.addPost(post);
      await store.approvePost(post);
      expect(store.canQueue(post), isFalse);
      final blocked = await store.queuePost(post,
          when: DateTime.now().add(const Duration(days: 1)),
          destination: PostDestination.personalProfile);
      expect(blocked.blockedBy, isNotNull);
      expect(blocked.blockedBy!.hits, isNotEmpty);
      expect(post.status, PostStatus.approved); // still not queued

      // Fixing the text (the default path) clears the block.
      await store.updatePostText(post, 'What helps your back feel '
          'ready for the day?');
      expect(store.canQueue(post), isTrue);

      // Flag it again and take the override path instead.
      await store.updatePostText(post, 'This patch cures back pain fast!');
      final report = store.scanPost(post);
      await store.recordPostOverride(post, report);
      expect(post.complianceOverride, isTrue);
      expect(post.overrideAcknowledgedFlags, isNotEmpty);
      expect(post.overrideAcknowledgedFlags.join(' '), contains('cures'));
      expect(store.canQueue(post), isTrue);
      final ok = await store.queuePost(post,
          when: DateTime.now().add(const Duration(days: 1)),
          destination: PostDestination.personalProfile);
      expect(ok.blockedBy, isNull);
      expect(post.status, PostStatus.queued);

      // Editing after an override clears it — new text, new decision.
      await store.updatePostText(post, 'This patch cures back pain fast!');
      expect(post.complianceOverride, isFalse);
    });

    test('reschedule moves the reminder; cancel kills it; handoff '
        'states record what actually happened', () async {
      final (store, reminders, _) = await loadedStore();
      final post = draftPost(store, 'What helps your sleep?');
      await store.addPost(post);
      await store.approvePost(post);
      final first = DateTime.now().add(const Duration(days: 1));
      await store.queuePost(post,
          when: first, destination: PostDestination.facebookPage);

      final second = DateTime.now().add(const Duration(days: 3));
      expect(await store.reschedulePost(post, second), isTrue);
      expect(post.status, PostStatus.queued);
      expect(post.scheduledFor, second);
      expect(reminders.cancelled, contains(post.reminderId));
      expect(reminders.scheduled[post.reminderId], second);

      await store.markHandedOff(post, copied: true);
      expect(post.status, PostStatus.copied);
      expect(post.status.label(), 'Copied');
      await store.markHandedOff(post, copied: false);
      expect(post.status, PostStatus.handedOff);
      expect(post.status.label(), contains('Handed off'));

      await store.cancelPost(post);
      expect(post.status, PostStatus.cancelled);
      expect(reminders.scheduled.containsKey(post.reminderId), isFalse);
    });

    test('NO path reaches a "posted" state — the word does not exist '
        'in any status label', () {
      for (final s in PostStatus.values) {
        final label =
            s.label(scheduledFor: DateTime(2026, 10, 20, 9)).toLowerCase();
        expect(label, isNot(contains('posted')),
            reason: 'status $s must never claim a post happened');
        expect(s.name.toLowerCase(), isNot(contains('posted')));
      }
    });
  });

  group('Curiosity-post generator (real bundled DB)', () {
    late KnowledgeDb db;
    setUpAll(() async {
      db = await KnowledgeDb.load();
    });

    test('the four original playbook templates are available', () {
      final gen = PostGenerator(db);
      expect(gen.templates.length, 4);
      expect(
        gen.templates.map((t) => t.id),
        containsAll([
          'play-template-open-question',
          'play-template-routine-note',
          'play-template-poll',
          'play-template-photo-prompt',
        ]),
      );
    });

    test('draft composes from template + product: slots filled, '
        'question present, product recorded, scan clean', () {
      final gen = PostGenerator(db);
      final template = gen.templates
          .firstWhere((t) => t.id == 'play-template-open-question');
      final x39 = db.byId('prod-x39')!;
      final draft = gen.composeDraft(
        id: 'post-test',
        template: template,
        product: x39,
      );
      expect(draft.text, contains('?'));
      expect(draft.text, isNot(contains('[')));
      expect(draft.text, isNot(contains(']')));
      expect(draft.productId, 'prod-x39');
      expect(draft.templateId, 'play-template-open-question');
      expect(draft.status, PostStatus.draft);
      expect(const ComplianceScanner().scan(draft.text).isClean, isTrue);
    });

    test('every template x variant composes scanner-clean text', () {
      final gen = PostGenerator(db);
      const scanner = ComplianceScanner();
      for (final template in gen.templates) {
        for (var variant = 0; variant < 3; variant++) {
          final text = gen.compose(template: template, variant: variant);
          expect(scanner.scan(text).isClean, isTrue,
              reason: '${template.id} variant $variant flagged: $text');
          expect(text, isNot(contains('[')));
        }
      }
    });

    test('a product steers the focus topic from its official text', () {
      expect(focusForProduct(db.byId('prod-silent-nights')!), 'sleep');
      expect(focusForProduct(db.byId('prod-x39')!),
          anyOf('energy', 'recovery', 'performance'));
    });
  });

  group('AI reply composer (real bundled DB)', () {
    late KnowledgeDb db;
    setUpAll(() async {
      db = await KnowledgeDb.load();
    });

    test('draft contains a brief grounded answer + the group invite '
        'with the group link from the pointer entries', () {
      final composer = ReplyComposer(db);
      final reply =
          composer.composeReply('How many patches come in a sleeve?');
      expect(reply, contains('LW Team Learning'));
      expect(reply, contains('Want me to add you?'));
      expect(reply,
          contains('https://facebook.com/groups/1088773684574273/'));
      expect(reply.length, lessThan(600)); // brief, per the reply style
    });

    test('composed replies pass the compliance scanner', () {
      final composer = ReplyComposer(db);
      const scanner = ComplianceScanner();
      for (final q in [
        'How many patches come in a sleeve?',
        'Why does it cost that much?',
        'Is it a drug?',
        'How soon will I notice anything?',
      ]) {
        final reply = composer.composeReply(q);
        expect(scanner.scan(reply).isClean, isTrue, reason: q);
        expect(reply, contains('LW Team Learning'));
      }
    });

    test('an unknown question still gets an honest draft + invite, '
        'never an invented answer', () {
      final composer = ReplyComposer(db);
      final reply = composer.composeReply(
          'What is the airspeed of a laden swallow?');
      expect(reply, contains('let me check'));
      expect(reply, contains('LW Team Learning'));
    });
  });

  group('Fact cards (real bundled DB)', () {
    late KnowledgeDb db;
    late BrandAssets brand;
    setUpAll(() async {
      db = await KnowledgeDb.load();
      brand = await BrandAssets.load();
    });

    test('for EVERY product: the fact is verbatim from its entry and '
        'the composed card text scans clean', () {
      const scanner = ComplianceScanner();
      for (final product in db.byTopic('products')) {
        final card = composeFactCard(
          product,
          imageAssetPath: brand.productImageFor(product.id),
          focus: focusForProduct(product),
        );
        expect(product.body, contains(card.fact),
            reason: '${product.id}: fact must come from the entry');
        expect(scanner.scan(card.allText).isClean, isTrue,
            reason: '${product.id}: card text flagged: ${card.allText}');
        expect(card.question, contains('?'));
        expect(card.claimLabel, product.claimLabel);
      }
    });

    test('Nirvana (no official picture) uses the placeholder path', () {
      final nirvana = db.byId('prod-nirvana-legacy')!;
      expect(brand.productImageFor(nirvana.id), isNull);
      final card = composeFactCard(
        nirvana,
        imageAssetPath: brand.productImageFor(nirvana.id),
        focus: focusForProduct(nirvana),
      );
      expect(card.hasOfficialPicture, isFalse);
      expect(card.imageAssetPath, isNull);
      expect(card.fact, isNotEmpty);
    });
  });

  group('Content calendar slot logic', () {
    PostDraft queuedOn(DateTime when) => PostDraft(
          id: 'post-${when.day}',
          text: 'Queued post?',
          status: PostStatus.queued,
          scheduledFor: when,
        );

    test('queued posts land on their day; cadence weekdays without a '
        'post get a labeled suggestion; past slots get none', () {
      // Mon Oct 19, 2026, 08:00 — suggestions at 9:00 are still future.
      final now = DateTime(2026, 10, 19, 8);
      final wed = DateTime(2026, 10, 21, 18, 30);
      final days = buildWeek(
        posts: [queuedOn(wed)],
        anchor: now,
        now: now,
      );
      expect(days.length, 7);
      final monday = days[0];
      expect(monday.date.weekday, DateTime.monday);
      expect(monday.posts, isEmpty);
      expect(monday.hasSuggestion, isTrue);
      expect(monday.suggestion!.hour, kSuggestionHour);
      final wednesday = days[2];
      expect(wednesday.posts.length, 1);
      expect(wednesday.hasSuggestion, isFalse);
      final friday = days[4];
      expect(friday.hasSuggestion, isTrue);
      final sunday = days[6];
      expect(sunday.hasSuggestion, isFalse); // not a cadence weekday

      // A week fully in the past suggests nothing.
      final past = buildWeek(
        posts: const [],
        anchor: DateTime(2026, 10, 5),
        now: now,
      );
      expect(past.every((d) => !d.hasSuggestion), isTrue);
    });

    test('cadence guidance quotes the playbook entry, labeled as such',
        () async {
      final db = await KnowledgeDb.load();
      final guidance =
          cadenceGuidance(db.byId('play-cadence-and-replies'));
      expect(guidance, startsWith('Playbook guidance:'));
      expect(guidance.toLowerCase(), contains('consistency'));
    });
  });

  group('Prospect pipeline', () {
    test('stage stepper advances Commented -> Invited -> Joined -> '
        'Customer and stops there', () async {
      final (store, _, _) = await loadedStore();
      final p = await store.addProspect(name: 'Alex');
      expect(p.stage, ProspectStage.commented);
      expect(await store.advanceProspect(p), isTrue);
      expect(p.stage, ProspectStage.invited);
      expect(await store.advanceProspect(p), isTrue);
      expect(p.stage, ProspectStage.joinedGroup);
      expect(await store.advanceProspect(p), isTrue);
      expect(p.stage, ProspectStage.customer);
      expect(await store.advanceProspect(p), isFalse);
      expect(p.stage, ProspectStage.customer);
    });

    test('follow-up due computation, snooze and mark-done', () async {
      final (store, _, _) = await loadedStore();
      final today = DateTime(2026, 10, 17, 10);
      final due = await store.addProspect(
          name: 'Due Dana', followUpDate: DateTime(2026, 10, 17, 9));
      final future = await store.addProspect(
          name: 'Future Fred', followUpDate: DateTime(2026, 10, 25));
      final undated = await store.addProspect(name: 'No-date Nora');
      expect(due.isDueOn(today), isTrue);
      expect(future.isDueOn(today), isFalse);
      expect(undated.isDueOn(today), isFalse);

      await store.snoozeFollowUp(due, days: 3);
      expect(due.followUpDate, DateTime(2026, 10, 20, 9));
      expect(due.isDueOn(today), isFalse);
      await store.markFollowUpDone(due);
      expect(due.followUpDate, isNull);
    });

    test('list sorts due follow-ups first', () async {
      final (store, _, _) = await loadedStore();
      final today = DateTime(2026, 10, 17, 10);
      await store.addProspect(
          name: 'Later', followUpDate: DateTime(2026, 12, 1));
      await store.addProspect(
          name: 'Due', followUpDate: DateTime(2026, 10, 16));
      await store.addProspect(name: 'Undated');
      final sorted = store.sortedProspects(today);
      expect(sorted.first.name, 'Due');
      expect(sorted.last.name, 'Undated');
    });
  });

  group('Today counts come from the real stores', () {
    test('replies waiting / posts scheduled / follow-ups due', () async {
      final (store, _, _) = await loadedStore();
      final now = DateTime(2026, 10, 17, 10);
      // Replies: one waiting, one handled.
      final r1 = ReplyDraft(
          id: store.newId('reply'),
          incomingText: 'Price?',
          draftText: 'Answer.');
      await store.addReply(r1);
      final r2 = ReplyDraft(
          id: store.newId('reply'),
          incomingText: 'Drug?',
          draftText: 'Answer 2.');
      await store.addReply(r2);
      await store.setReplyStatus(r2, ReplyStatus.handled);
      // Posts: one queued in the future, one already due, one draft.
      final future = draftPost(store, 'Future post?');
      await store.addPost(future);
      await store.approvePost(future);
      await store.queuePost(future,
          when: DateTime(2026, 10, 20, 9),
          destination: PostDestination.personalProfile);
      final pastDue = draftPost(store, 'Past-due post?');
      await store.addPost(pastDue);
      await store.approvePost(pastDue);
      await store.queuePost(pastDue,
          when: DateTime(2026, 10, 17, 9),
          destination: PostDestination.personalProfile);
      await store.addPost(draftPost(store, 'Just a draft?'));
      // Prospects: one due, one not.
      await store.addProspect(
          name: 'Due', followUpDate: DateTime(2026, 10, 17, 8));
      await store.addProspect(
          name: 'Later', followUpDate: DateTime(2026, 11, 1));

      final counts = store.todayCounts(now);
      expect(counts.repliesWaiting, 1);
      expect(counts.postsScheduled, 1,
          reason: 'only the future-reminder queued post counts');
      expect(counts.followUpsDue, 1);
      // The past-due queued post is surfaced as ready-to-post instead.
      expect(store.duePosts(now).length, 1);
    });
  });

  group('Compliance guide', () {
    test('explanations group hits by category with why + suggestion',
        () async {
      final db = await KnowledgeDb.load();
      final guide = ComplianceGuide.fromDb(db.entries);
      const scanner = ComplianceScanner();
      final report =
          scanner.scan('This cures pain. Get rich from home!');
      expect(report.hasHits, isTrue);
      final grouped = guide.groupByCategory(report);
      expect(grouped.keys,
          containsAll([ComplianceCategory.medicalClaim, ComplianceCategory.incomeClaim]));
      final explanations = guide.explain(report);
      expect(explanations.length, report.hits.length);
      for (final e in explanations) {
        expect(e.why, isNotEmpty);
        expect(e.suggestion, isNotEmpty);
      }
      expect(guide.doEntry?.id, 'play-compliance-do');
      expect(guide.dontEntry?.id, 'play-compliance-dont');
    });
  });
}
