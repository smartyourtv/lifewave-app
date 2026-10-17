import 'package:flutter/foundation.dart';

import '../models/journey.dart';
import '../models/social.dart';
import 'compliance.dart';
import 'cross_post.dart';
import 'journey.dart' as journey_logic;
import 'local_store.dart';

/// Reminder scheduling seam — the real implementation talks to
/// flutter_local_notifications (INEXACT alarms only, PRE-BUILD-AUDIT
/// §3); tests use a fake. Scheduling is best-effort: the queue in this
/// store is the source of truth, notifications are copies of it.
abstract class ReminderScheduler {
  /// True when OS notifications can actually be scheduled here.
  bool get available;

  /// Plain-language state for the UI/diagnostics.
  String get stateLabel;

  Future<void> initialize({void Function(String postId)? onTapPost});

  /// Schedules an INEXACT reminder. Returns false when unavailable —
  /// the caller keeps the queue entry and says so honestly.
  Future<bool> schedule({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    required String payloadPostId,
  });

  Future<void> cancel(int id);
}

/// The M3 store: post queue, reply drafts, prospects, quick templates.
///
/// Owns the state machine rules so no screen can invent an illegal
/// transition:
///  - a post can be APPROVED from draft;
///  - a post can be QUEUED only from approved, and only when its text
///    passes the compliance scanner OR the user has explicitly
///    overridden with the flags acknowledged (recorded on the draft);
///  - NOTHING auto-sends, ever; handoff states record what actually
///    happened (share sheet opened / copied).
class SocialStore extends ChangeNotifier {
  final JsonDocumentStore _doc;
  final ReminderScheduler reminders;
  final ComplianceScanner _scanner;
  int _idCounter = 0;

  final List<PostDraft> posts = [];
  final List<ReplyDraft> replies = [];
  final List<Prospect> prospects = [];
  final List<QuickReplyTemplate> quickTemplates = [];

  /// M4: 30-day journey customers (with their private journals),
  /// stored in the SAME on-device document as the other lists.
  final List<Customer> customers = [];
  bool loaded = false;

  SocialStore({
    JsonDocumentStore? doc,
    required this.reminders,
    ComplianceScanner scanner = const ComplianceScanner(),
  })  : _doc = doc ?? JsonDocumentStore(io: AppDocsFileIo()),
        _scanner = scanner;

  /// Store warning for Diagnostics (corrupt file / failed save).
  String? get storeWarning => _doc.lastWarning;

  String newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  Future<void> load() async {
    await _doc.load();
    posts
      ..clear()
      ..addAll(_doc.listFor('posts').map(PostDraft.tryDecode).whereType<PostDraft>());
    replies
      ..clear()
      ..addAll(
          _doc.listFor('replies').map(ReplyDraft.tryDecode).whereType<ReplyDraft>());
    prospects
      ..clear()
      ..addAll(_doc
          .listFor('prospects')
          .map(Prospect.tryDecode)
          .whereType<Prospect>());
    quickTemplates
      ..clear()
      ..addAll(_doc
          .listFor('quickTemplates')
          .map(QuickReplyTemplate.tryDecode)
          .whereType<QuickReplyTemplate>());
    customers
      ..clear()
      ..addAll(_doc
          .listFor('customers')
          .map(Customer.tryDecode)
          .whereType<Customer>());
    loaded = true;
    notifyListeners();
  }

  Future<void> _savePosts() =>
      _doc.saveList('posts', posts.map((p) => p.toJson()).toList());
  Future<void> _saveReplies() =>
      _doc.saveList('replies', replies.map((r) => r.toJson()).toList());
  Future<void> _saveProspects() =>
      _doc.saveList('prospects', prospects.map((p) => p.toJson()).toList());
  Future<void> _saveTemplates() => _doc.saveList(
      'quickTemplates', quickTemplates.map((t) => t.toJson()).toList());
  Future<void> _saveCustomers() => _doc.saveList(
      'customers', customers.map((c) => c.toJson()).toList());

  PostDraft? postById(String id) {
    for (final p in posts) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Posts: lifecycle
  // ---------------------------------------------------------------------

  Future<PostDraft> addPost(PostDraft draft) async {
    posts.insert(0, draft);
    await _savePosts();
    notifyListeners();
    return draft;
  }

  Future<void> updatePostText(PostDraft post, String text) async {
    post.text = text;
    post.updatedAt = DateTime.now();
    // Editing a flagged-and-overridden draft clears the override: the
    // new text has not been acknowledged by anyone yet.
    if (post.complianceOverride) {
      post.complianceOverride = false;
      post.overrideAcknowledgedFlags = [];
    }
    await _savePosts();
    notifyListeners();
  }

  ComplianceReport scanPost(PostDraft post) => _scanner.scan(post.text);

  /// Draft -> Approved. Compliance is enforced at QUEUE time (the last
  /// gate before a reminder exists), so approval itself always works —
  /// but a flagged draft carries its flags visibly from here on.
  Future<bool> approvePost(PostDraft post) async {
    if (post.status != PostStatus.draft) return false;
    post.status = PostStatus.approved;
    post.updatedAt = DateTime.now();
    await _savePosts();
    notifyListeners();
    return true;
  }

  /// Records an explicit compliance override: the user saw these exact
  /// flagged phrases and chose to go ahead anyway. Default path is to
  /// fix the text — this is the deliberate exception, and it is stored
  /// on the draft.
  Future<void> recordPostOverride(PostDraft post, ComplianceReport report) async {
    post.complianceOverride = true;
    post.overrideAcknowledgedFlags =
        report.hits.map((h) => '${h.categoryLabel}: "${h.term}"').toList();
    post.updatedAt = DateTime.now();
    await _savePosts();
    notifyListeners();
  }

  /// Whether [post] may be queued right now: approved + (clean scan OR
  /// recorded override covering the CURRENT flags).
  bool canQueue(PostDraft post) {
    if (post.status != PostStatus.approved) return false;
    final report = scanPost(post);
    return report.isClean || post.complianceOverride;
  }

  /// Approved -> Queued: sets the reminder time + destination and asks
  /// the OS for an INEXACT notification. Returns the scan report when
  /// compliance blocks queueing (caller shows the flags), or null on
  /// success. When the OS reminder cannot be scheduled (permission /
  /// platform), the post still queues and [reminderScheduled] on the
  /// result is false — the Today card remains the source of truth.
  Future<({ComplianceReport? blockedBy, bool reminderScheduled})> queuePost(
    PostDraft post, {
    required DateTime when,
    required PostDestination destination,
  }) async {
    if (post.status != PostStatus.approved) {
      return (blockedBy: null, reminderScheduled: false);
    }
    final report = scanPost(post);
    if (report.hasHits && !post.complianceOverride) {
      return (blockedBy: report, reminderScheduled: false);
    }
    post.scheduledFor = when;
    post.destination = destination;
    post.status = PostStatus.queued;
    post.updatedAt = DateTime.now();
    final scheduled = await reminders.schedule(
      id: post.reminderId,
      when: when,
      title: 'Time to share your post',
      body: 'Your curiosity post is ready. Open the app and tap '
          '"Post now" to share it yourself.',
      payloadPostId: post.id,
    );
    await _savePosts();
    notifyListeners();
    return (blockedBy: null, reminderScheduled: scheduled);
  }

  /// Queued (or handed-off/copied) -> Queued at a new time.
  Future<bool> reschedulePost(PostDraft post, DateTime when) async {
    if (post.status != PostStatus.queued &&
        post.status != PostStatus.handedOff &&
        post.status != PostStatus.copied) {
      return false;
    }
    await reminders.cancel(post.reminderId);
    post.scheduledFor = when;
    post.status = PostStatus.queued;
    post.updatedAt = DateTime.now();
    await reminders.schedule(
      id: post.reminderId,
      when: when,
      title: 'Time to share your post',
      body: 'Your curiosity post is ready. Open the app and tap '
          '"Post now" to share it yourself.',
      payloadPostId: post.id,
    );
    await _savePosts();
    notifyListeners();
    return true;
  }

  Future<void> cancelPost(PostDraft post) async {
    await reminders.cancel(post.reminderId);
    post.status = PostStatus.cancelled;
    post.updatedAt = DateTime.now();
    await _savePosts();
    notifyListeners();
  }

  /// Records what ACTUALLY happened at handoff time: the share sheet
  /// was opened, or the text was copied. Never a "posted" state.
  Future<void> markHandedOff(PostDraft post, {required bool copied}) async {
    post.status = copied ? PostStatus.copied : PostStatus.handedOff;
    post.updatedAt = DateTime.now();
    await _savePosts();
    notifyListeners();
  }

  Future<void> deletePost(PostDraft post) async {
    await reminders.cancel(post.reminderId);
    posts.remove(post);
    await _savePosts();
    notifyListeners();
  }

  /// Queued posts whose reminder time has arrived and that have not
  /// been handed off yet — the Today card's "ready to post" list.
  List<PostDraft> duePosts(DateTime now) => posts
      .where((p) =>
          p.status == PostStatus.queued &&
          p.scheduledFor != null &&
          !p.scheduledFor!.isAfter(now))
      .toList();

  // ---------------------------------------------------------------------
  // Replies
  // ---------------------------------------------------------------------

  Future<ReplyDraft> addReply(ReplyDraft draft) async {
    replies.insert(0, draft);
    await _saveReplies();
    notifyListeners();
    return draft;
  }

  Future<void> updateReplyText(ReplyDraft draft, String text) async {
    draft.draftText = text;
    if (draft.complianceOverride) {
      draft.complianceOverride = false;
      draft.overrideAcknowledgedFlags = [];
    }
    await _saveReplies();
    notifyListeners();
  }

  Future<void> recordReplyOverride(
      ReplyDraft draft, ComplianceReport report) async {
    draft.complianceOverride = true;
    draft.overrideAcknowledgedFlags =
        report.hits.map((h) => '${h.categoryLabel}: "${h.term}"').toList();
    await _saveReplies();
    notifyListeners();
  }

  Future<void> setReplyStatus(ReplyDraft draft, ReplyStatus status) async {
    draft.status = status;
    await _saveReplies();
    notifyListeners();
  }

  Future<void> deleteReply(ReplyDraft draft) async {
    replies.remove(draft);
    await _saveReplies();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Prospects
  // ---------------------------------------------------------------------

  Future<Prospect> addProspect({
    required String name,
    String note = '',
    DateTime? followUpDate,
  }) async {
    final p = Prospect(
      id: newId('prospect'),
      name: name,
      note: note,
      followUpDate: followUpDate,
    );
    prospects.add(p);
    await _saveProspects();
    notifyListeners();
    return p;
  }

  Future<void> setProspectStage(Prospect p, ProspectStage stage) async {
    p.stage = stage;
    await _saveProspects();
    notifyListeners();
  }

  /// Advances one step along Commented -> Invited -> Joined -> Customer.
  /// Returns false at the final stage (no step beyond Customer).
  Future<bool> advanceProspect(Prospect p) async {
    final next = p.stage.next;
    if (next == null) return false;
    await setProspectStage(p, next);
    return true;
  }

  Future<void> setFollowUp(Prospect p, DateTime? when) async {
    p.followUpDate = when;
    await _saveProspects();
    notifyListeners();
  }

  /// Follow-up done: clears the date (the prospect stays in the list).
  Future<void> markFollowUpDone(Prospect p) => setFollowUp(p, null);

  /// Pushes the follow-up [days] into the future from its current date
  /// (or from today when none was set).
  Future<void> snoozeFollowUp(Prospect p, {int days = 3}) async {
    final base = p.followUpDate ?? DateTime.now();
    await setFollowUp(p, base.add(Duration(days: days)));
  }

  Future<void> deleteProspect(Prospect p) async {
    prospects.remove(p);
    await _saveProspects();
    notifyListeners();
  }

  /// Prospects sorted for the list: due follow-ups first (earliest
  /// first), then dated follow-ups, then undated by name.
  List<Prospect> sortedProspects(DateTime now) {
    final list = [...prospects];
    list.sort((a, b) {
      final aDue = a.isDueOn(now) ? 0 : 1;
      final bDue = b.isDueOn(now) ? 0 : 1;
      if (aDue != bDue) return aDue.compareTo(bDue);
      final af = a.followUpDate;
      final bf = b.followUpDate;
      if (af != null && bf != null) return af.compareTo(bf);
      if (af != null) return -1;
      if (bf != null) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  // ---------------------------------------------------------------------
  // Quick-reply templates (user pre-approved in Settings)
  // ---------------------------------------------------------------------

  Future<QuickReplyTemplate> addTemplate({
    required String title,
    required String text,
  }) async {
    final t = QuickReplyTemplate(id: newId('tpl'), title: title, text: text);
    quickTemplates.add(t);
    await _saveTemplates();
    notifyListeners();
    return t;
  }

  Future<void> setTemplateApproved(QuickReplyTemplate t, bool approved) async {
    t.approved = approved;
    await _saveTemplates();
    notifyListeners();
  }

  Future<void> deleteTemplate(QuickReplyTemplate t) async {
    quickTemplates.remove(t);
    await _saveTemplates();
    notifyListeners();
  }

  List<QuickReplyTemplate> get approvedTemplates =>
      quickTemplates.where((t) => t.approved).toList();

  // ---------------------------------------------------------------------
  // Cross-posting handoffs (M4, SPEC §7.8 item 8)
  // ---------------------------------------------------------------------

  /// Records that a share sheet was opened for [platform]'s formatted
  /// variant of [post]. The label says exactly that — never "posted".
  Future<void> markPlatformHandoff(PostDraft post, SharePlatform platform,
      {DateTime? when}) async {
    post.platformHandoffs[platform.name] =
        platformHandoffLabel(platform, when ?? DateTime.now());
    post.updatedAt = DateTime.now();
    await _savePosts();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Customers — 30-day journey (M4, SPEC §7.8 item 5)
  // ---------------------------------------------------------------------

  Customer? customerById(String id) {
    for (final c in customers) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<Customer> addCustomer({
    required String name,
    String? productId,
    String productTitle = '',
    required DateTime startDate,
  }) async {
    final c = Customer(
      id: newId('customer'),
      name: name,
      productId: productId,
      productTitle: productTitle,
      startDate: startDate,
    );
    customers.add(c);
    await _saveCustomers();
    notifyListeners();
    return c;
  }

  Future<void> deleteCustomer(Customer c) async {
    customers.remove(c);
    await _saveCustomers();
    notifyListeners();
  }

  /// Records a check-in draft handoff for milestone [day] (share sheet
  /// opened / copied) — honest wording, never "sent".
  Future<void> markCheckInHandedOff(Customer c, int day) async {
    c.checkInsHandedOff.add(day);
    await _saveCustomers();
    notifyListeners();
  }

  Future<void> markCheckInDone(Customer c, int day) async {
    c.checkInsDone.add(day);
    await _saveCustomers();
    notifyListeners();
  }

  /// Marks the customer reordered: the day-25 nudge clears.
  Future<void> markReordered(Customer c) async {
    c.reordered = true;
    c.reorderedAt = DateTime.now();
    await _saveCustomers();
    notifyListeners();
  }

  Future<void> unmarkReordered(Customer c) async {
    c.reordered = false;
    c.reorderedAt = null;
    await _saveCustomers();
    notifyListeners();
  }

  /// Adds a private journal note for [day]. Journal entries live ONLY
  /// inside this customer's record in the on-device document.
  Future<JournalEntry> addJournalEntry(
      Customer c, int day, String text) async {
    final entry = JournalEntry(
      id: newId('journal'),
      customerId: c.id,
      day: day,
      text: text,
    );
    c.journal.add(entry);
    await _saveCustomers();
    notifyListeners();
    return entry;
  }

  Future<void> deleteJournalEntry(Customer c, JournalEntry entry) async {
    c.journal.remove(entry);
    await _saveCustomers();
    notifyListeners();
  }

  /// Journal entries for one customer only — isolation is structural:
  /// entries live inside the customer's own record.
  List<JournalEntry> journalFor(Customer c) {
    final list = [...c.journal]..sort((a, b) {
        final byDay = a.day.compareTo(b.day);
        return byDay != 0 ? byDay : a.createdAt.compareTo(b.createdAt);
      });
    return list;
  }

  /// Customers sorted for the Journey screen: most action needed
  /// first (reorder due, then check-in due), then by day descending.
  List<Customer> sortedCustomers(DateTime now) {
    final list = [...customers];
    int urgency(Customer c) {
      if (journey_logic.reorderDue(c, now)) return 0;
      if (journey_logic.dueCheckIns(c, now).isNotEmpty) return 1;
      return 2;
    }

    list.sort((a, b) {
      final u = urgency(a).compareTo(urgency(b));
      if (u != 0) return u;
      return journey_logic
          .journeyDay(b, now)
          .compareTo(journey_logic.journeyDay(a, now));
    });
    return list;
  }

  /// How many customers have a check-in due right now (Journey badge).
  int get checkInsDueCount {
    final now = DateTime.now();
    return customers
        .where((c) => journey_logic.dueCheckIns(c, now).isNotEmpty)
        .length;
  }

  // ---------------------------------------------------------------------
  // Today counts — REAL numbers from these stores (SPEC §7.8 item 7)
  // ---------------------------------------------------------------------

  TodayCounts todayCounts(DateTime now) {
    return TodayCounts(
      repliesWaiting:
          replies.where((r) => r.status == ReplyStatus.waiting).length,
      // Queued posts with a reminder still in the future.
      postsScheduled: posts
          .where((p) =>
              p.status == PostStatus.queued &&
              p.scheduledFor != null &&
              p.scheduledFor!.isAfter(now))
          .length,
      followUpsDue: prospects.where((p) => p.isDueOn(now)).length,
      // REAL since M4: journey customers at day >= 25 not reordered.
      reordersDue: customers
          .where((c) => journey_logic.reorderDue(c, now))
          .length,
    );
  }
}
