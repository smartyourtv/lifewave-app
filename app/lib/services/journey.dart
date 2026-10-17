import '../models/entry.dart';
import '../models/journey.dart';
import 'compliance.dart';
import 'knowledge_db.dart';
import 'post_generator.dart' show ReplyComposer;

/// 30-day customer journey logic (SPEC §7.8 item 5 + §7.9 check-ins).
///
/// Day math is DATE-LEVEL: day 1 is the start date itself, day N is
/// start + (N-1) calendar days. Check-in milestones are days 3, 7 and
/// 30; the reorder nudge starts at day 25 and clears only when the
/// customer is marked reordered.
///
/// Check-in drafts are warm messages composed from playbook/faq content
/// in the app's own words — they are DRAFTS (§7.2 rule): the user hands
/// them off and sends them from their own account, on their own tap.
/// Placement reminders are POINTERS ONLY (§3/§4): they surface the
/// official general usage entries and point to LW Team Learning for
/// detailed guidance — no protocol content is ever composed here.

/// Check-in milestone days.
const List<int> kCheckInDays = [3, 7, 30];

/// The day the reorder nudge begins.
const int kReorderDay = 25;

/// Length of the journey window shown by the day counter.
const int kJourneyDays = 30;

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// The journey day [customer] is on at [now]: day 1 = the start date.
/// Returns 0 when the start date is still in the future.
int journeyDay(Customer customer, DateTime now) {
  final start = _dateOnly(customer.startDate);
  final today = _dateOnly(now);
  final diff = today.difference(start).inDays;
  return diff < 0 ? 0 : diff + 1;
}

/// True when [day] is a check-in milestone that has been reached and
/// has not been handed off or marked done yet.
bool checkInDue(Customer customer, int day, DateTime now) {
  if (!kCheckInDays.contains(day)) return false;
  if (customer.checkInsDone.contains(day)) return false;
  if (customer.checkInsHandedOff.contains(day)) return false;
  return journeyDay(customer, now) >= day;
}

/// All check-in milestones currently due for [customer].
List<int> dueCheckIns(Customer customer, DateTime now) =>
    kCheckInDays.where((d) => checkInDue(customer, d, now)).toList();

/// Reorder due = on/after day [kReorderDay] and not yet marked
/// reordered. This is the REAL count behind the Today card's
/// "Reorders due" row (SPEC §7.8 item 7).
bool reorderDue(Customer customer, DateTime now) =>
    !customer.reordered && journeyDay(customer, now) >= kReorderDay;

/// One row of the journey timeline.
class JourneyMilestone {
  final int day;
  final String label;
  final String detail;

  /// 'checkin' | 'reorder' | 'start'
  final String kind;
  const JourneyMilestone({
    required this.day,
    required this.label,
    required this.detail,
    required this.kind,
  });
}

/// The full timeline for a customer, in day order.
List<JourneyMilestone> journeyTimeline() => const [
      JourneyMilestone(
        day: 1,
        label: 'Day 1 — they start',
        detail: 'Welcome them, and point them to the official usage '
            'basics and the learning group.',
        kind: 'start',
      ),
      JourneyMilestone(
        day: 3,
        label: 'Day 3 — first check-in',
        detail: 'A short, warm check-in draft is ready below.',
        kind: 'checkin',
      ),
      JourneyMilestone(
        day: 7,
        label: 'Day 7 — one-week check-in',
        detail: 'Ask how their routine is going; invite questions.',
        kind: 'checkin',
      ),
      JourneyMilestone(
        day: kReorderDay,
        label: 'Day 25 — reorder nudge',
        detail: 'A gentle reminder that a sleeve lasts about a month, '
            'so a reorder (or Subscribe & Save) keeps them from '
            'running out.',
        kind: 'reorder',
      ),
      JourneyMilestone(
        day: 30,
        label: 'Day 30 — one-month check-in',
        detail: 'Celebrate a month of routine and ask what they '
            'noticed — their words, never a claim from us.',
        kind: 'checkin',
      ),
    ];

/// Composes the check-in draft for milestone [day]. Warm, brief, in
/// the reply style (§7.2): no medical claims, no promised results, and
/// the group invite from the pointer entries rides along. The caller
/// compliance-scans the result before any handoff.
String composeCheckInDraft({
  required Customer customer,
  required int day,
  required KnowledgeDb db,
}) {
  final firstName = customer.name.trim().split(RegExp(r'\s+')).first;
  final product =
      customer.productTitle.isNotEmpty ? ' with ${customer.productTitle}' : '';
  final String body;
  switch (day) {
    case 3:
      body = 'Hi $firstName! Just checking in — you are a few days into '
          'your first month$product. How is the routine feeling so far? '
          'If any questions come up about wearing it or the basics, I '
          'am right here.';
      break;
    case 7:
      body = 'Hi $firstName, one week in$product! How has the routine '
          'settled into your days? Remember the basics: up to 12 hours '
          'on clean, dry skin, and keep the water bottle handy. Any '
          'questions, just ask.';
      break;
    case 30:
      body = 'Hi $firstName — a whole month$product! Thank you for '
          'giving it a real try. I would love to hear how the routine '
          'fit your life, in your own words. And if you would like to '
          'keep going, I can help you set up the next order so you '
          'never run out.';
      break;
    default:
      body = 'Hi $firstName! Just checking in on your journey$product — '
          'how is everything going? Any questions at all, I am here.';
  }
  final invite = ReplyComposer(db).inviteText();
  return '$body $invite';
}

/// Composes the day-25 reorder nudge draft (Subscribe & Save framing
/// from the official pricing structure — see faq-price-objection).
String composeReorderDraft({required Customer customer, required KnowledgeDb db}) {
  final firstName = customer.name.trim().split(RegExp(r'\s+')).first;
  final product =
      customer.productTitle.isNotEmpty ? customer.productTitle : 'your patches';
  return 'Hi $firstName! A quick heads-up: a sleeve of $product lasts '
      'about a month on the usual routine, so yours is getting close '
      'to running out. If you would like to keep going without a gap, '
      'I can help you reorder — or set up Subscribe & Save, which is '
      'the lower monthly price. Just say the word!';
}

/// The placement-pointer block (SPEC §7.8 item 5): the OFFICIAL general
/// usage entries, plus the pointer framing. Detailed placement
/// guidance lives in the group — the app points, it never ships
/// protocol content.
class PlacementPointers {
  /// Official general usage entries from the bundled database.
  final List<KnowledgeEntry> usageEntries;

  /// The pointer line, shown verbatim in the UI.
  static const String pointerLine =
      'Detailed placement guidance lives in LW Team Learning — this '
      'app only carries the official general basics and points you '
      'there for the rest.';

  const PlacementPointers(this.usageEntries);

  factory PlacementPointers.fromDb(KnowledgeDb db) =>
      PlacementPointers(db.byTopic('usage'));
}

/// Scans a composed journey draft — the same gate every other draft
/// passes before handoff (SPEC §7.9).
ComplianceReport scanJourneyDraft(String text) =>
    const ComplianceScanner().scan(text);
