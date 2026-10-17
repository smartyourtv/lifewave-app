import '../models/entry.dart';
import 'compliance.dart';
import 'knowledge_db.dart';
import 'post_generator.dart' show ReplyComposer;

/// Roleplay practice (SPEC §7.8 item 1): the app plays a skeptical
/// prospect so the user can practice out loud, then a COACH reviews
/// each answer.
///
/// This is a built-in, on-device scenario engine — NOT a real person
/// and NOT a cloud AI. The screen labels it honestly: "Practice
/// partner — built-in practice, not a real person."
///
/// CLOUD-ESCALATION HOOK (§7.8 item 1): if a cloud tier is ever
/// configured, richer free-form roleplay plugs in behind the existing
/// [CloudEscalation] interface (services/cloud_escalation.dart) — the
/// session would ask it for the next prospect line instead of the
/// scripted bank below. Interface note only: no network in this build,
/// and the scripted engine stays as the offline fallback either way.
///
/// Everything the coach checks comes from the database: the objection
/// bank is the faq topic, the key compliant points are the points the
/// faq entry itself makes, and the suggested stronger phrasing is
/// composed from that entry's own words.

/// One key compliant point for an objection, with the words that show
/// the user covered it.
class KeyPoint {
  final String label;
  final List<String> keywords; // any one match (lowercase substring)
  const KeyPoint(this.label, this.keywords);

  bool coveredBy(String answer) {
    final lower = answer.toLowerCase();
    return keywords.any((k) => lower.contains(k));
  }
}

/// One scripted prospect reaction: when the user's answer contains
/// any of [keywords], the prospect says [line] next.
class ProspectReaction {
  final List<String> keywords;
  final String line;

  /// Emotion markup tag for the voice (e.g. 'warm', 'sigh').
  final String emotion;
  const ProspectReaction({
    required this.keywords,
    required this.line,
    this.emotion = 'neutral',
  });
}

/// A prospect persona, bound to one faq objection entry.
class ProspectPersona {
  final String id;
  final String name;
  final String description;
  final String faqEntryId;
  final String openingLine;
  final String openingEmotion;
  final List<KeyPoint> keyPoints;
  final List<ProspectReaction> reactions;

  /// Pushback lines used when an answer matches no reaction (rotated).
  final List<String> pushbacks;
  const ProspectPersona({
    required this.id,
    required this.name,
    required this.description,
    required this.faqEntryId,
    required this.openingLine,
    this.openingEmotion = 'sigh',
    required this.keyPoints,
    required this.reactions,
    required this.pushbacks,
  });
}

/// The four built-in personas. Their key points are the compliant
/// points the linked faq entry makes — checked against the DB in
/// tests via [RoleplayEngine].
const List<ProspectPersona> kProspectPersonas = [
  ProspectPersona(
    id: 'price-skeptic',
    name: 'Pat — the price skeptic',
    description: 'Thinks it costs too much and wants to know why.',
    faqEntryId: 'faq-price-objection',
    openingLine: 'Okay, be honest with me — how much does this cost? '
        'Because it sounds like a lot of money for some patches.',
    openingEmotion: 'sigh',
    keyPoints: [
      KeyPoint('Mentioned the two prices (retail and Subscribe & Save)',
          ['subscribe', 'two prices', 'retail', 'lower price', 'monthly']),
      KeyPoint('No pressure — left the choice with them',
          ['no pressure', 'up to you', 'your choice', 'when you are ready', 'take your time']),
      KeyPoint('Mentioned the money-back guarantee',
          ['guarantee', 'money-back', 'money back', 'refund']),
    ],
    reactions: [
      ProspectReaction(
        keywords: ['subscribe'],
        line: 'Hmm, a subscription? I do not love subscriptions. '
            'What if I want to stop?',
        emotion: 'neutral',
      ),
      ProspectReaction(
        keywords: ['guarantee', 'refund'],
        line: 'A guarantee does help, I will give you that. So if it '
            'is not for me, I am not stuck with it?',
        emotion: 'warm',
      ),
    ],
    pushbacks: [
      'That still sounds like a lot. Why is it priced like that?',
      'I do not know… my cousin said these things are all the same.',
    ],
  ),
  ProspectPersona(
    id: 'drug-questioner',
    name: 'Robin — "is it a drug?"',
    description: 'Worried about drugs or chemicals going into the body.',
    faqEntryId: 'faq-drug-or-chemical',
    openingLine: 'Wait. Is this a drug? Does something soak into my '
        'body from that patch? I am not comfortable with that.',
    openingEmotion: 'surprise',
    keyPoints: [
      KeyPoint('Said it is non-transdermal / nothing enters the body',
          ['non-transdermal', 'nothing enters', 'no drugs', 'no chemicals', 'nothing goes in', 'does not enter']),
      KeyPoint('Explained it works with the body\'s own infrared energy / heat',
          ['infrared', 'body heat', 'own energy', 'reflects']),
      KeyPoint('Attributed it to the company ("the company says…")',
          ['company says', 'the company', 'official']),
    ],
    reactions: [
      ProspectReaction(
        keywords: ['infrared', 'heat', 'reflect'],
        line: 'So it uses my own body heat? That is… actually kind of '
            'interesting. But does it do anything, then?',
        emotion: 'warm',
      ),
      ProspectReaction(
        keywords: ['nothing enters', 'non-transdermal', 'no drugs'],
        line: 'Nothing goes in at all? Then how is it different from '
            'just a sticker?',
        emotion: 'neutral',
      ),
    ],
    pushbacks: [
      'I am still not sure I get it. A patch that puts nothing in?',
      'What does the company actually say it does, then?',
    ],
  ),
  ProspectPersona(
    id: 'works-skeptic',
    name: 'Sam — "does it really work?"',
    description: 'Wants proof and quick results, and pushes for a promise.',
    faqEntryId: 'faq-how-soon-results',
    openingLine: 'Come on — does this thing actually work? How soon '
        'would I feel something? A week? A day?',
    openingEmotion: 'chuckle',
    keyPoints: [
      KeyPoint('Made NO promise about results or timing',
          ['no promise', 'cannot promise', "can't promise", 'never promise', 'no guarantee of results', 'makes no promise']),
      KeyPoint('Said everyone\'s experience is their own',
          ['everyone', 'your own experience', 'each person', 'individual', 'different for']),
      KeyPoint('Pointed to the 90-day money-back guarantee',
          ['90-day', '90 day', 'guarantee', 'money-back', 'money back']),
    ],
    reactions: [
      ProspectReaction(
        keywords: ['guarantee', '90'],
        line: 'Ninety days to try it is fair, I suppose. So I would '
            'not be risking much?',
        emotion: 'warm',
      ),
      ProspectReaction(
        keywords: ['promise', 'everyone'],
        line: 'Huh — most people just promise me the moon. Okay, '
            'what do people usually use it for?',
        emotion: 'neutral',
      ),
    ],
    pushbacks: [
      'But surely SOME people feel it fast? You can tell me.',
      'If it does nothing, why do people keep buying it?',
    ],
  ),
  ProspectPersona(
    id: 'busy-no-time',
    name: 'Jo — busy, no time for routines',
    description: 'Interested, but their days are packed and chaotic.',
    faqEntryId: 'faq-how-long-wear',
    openingLine: 'Honestly? I have zero time for another complicated '
        'routine. How much fuss is this every day?',
    openingEmotion: 'sigh',
    keyPoints: [
      KeyPoint('Said up to 12 hours, then discard',
          ['12 hours', 'twelve hours', 'up to 12']),
      KeyPoint('Kept it simple: morning or evening, one patch',
          ['morning', 'evening', 'one patch', 'once a day', 'simple']),
      KeyPoint('Mentioned patches are single-use',
          ['single-use', 'single use', 'throw it away', 'discard', 'new one each']),
    ],
    reactions: [
      ProspectReaction(
        keywords: ['12 hours', 'twelve'],
        line: 'Twelve hours and then I just throw it away? That part '
            'sounds easy enough, actually.',
        emotion: 'warm',
      ),
      ProspectReaction(
        keywords: ['morning', 'evening'],
        line: 'Morning or night — okay. And what if I forget a day?',
        emotion: 'neutral',
      ),
    ],
    pushbacks: [
      'My mornings are chaos. Be real with me — how long does it take?',
      'And I have to remember to take it off too?',
    ],
  ),
];

/// The coach's review of one user answer.
class CoachReview {
  /// Compliance scan of the user's own answer (flags explained by the
  /// UI through the shared compliance guide).
  final ComplianceReport report;

  /// Key points from the faq entry the answer covered / missed.
  final List<String> coveredPoints;
  final List<String> missedPoints;

  /// A stronger phrasing composed from the faq entry's own words.
  final String suggestedPhrasing;

  const CoachReview({
    required this.report,
    required this.coveredPoints,
    required this.missedPoints,
    required this.suggestedPhrasing,
  });

  bool get allPointsCovered => missedPoints.isEmpty;
}

/// Builds a suggested stronger phrasing from the faq [entry]: the
/// first substantive, scanner-clean sentence that carries one of the
/// [keyPoints]' keywords — falling back to the first substantive clean
/// sentence, then to a brief excerpt of the body. The result is always
/// derived from the entry (tests assert provenance).
String suggestedPhrasingFor(KnowledgeEntry entry, List<KeyPoint> keyPoints) {
  const scanner = ComplianceScanner();
  final flat = entry.body.replaceAll(RegExp(r'\s+'), ' ').trim();
  final sentences = flat
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((s) => s.trim())
      .where((s) => s.length >= 30)
      .where((s) => scanner.scan(s).isClean)
      .toList();
  for (final s in sentences) {
    final lower = s.toLowerCase();
    final carries = keyPoints.any((kp) =>
        kp.keywords.any((k) => lower.contains(k)));
    if (carries) return s;
  }
  if (sentences.isNotEmpty) return sentences.first;
  return ReplyComposer.briefExcerpt(entry.body);
}

/// One practice conversation. Advance it with [answer]; it ends after
/// the prospect has spoken [maxProspectLines] lines in total (the
/// opening counts), which keeps a practice round short and finishable.
class RoleplaySession {
  final ProspectPersona persona;
  final KnowledgeEntry faqEntry;
  final ComplianceScanner _scanner;
  static const int maxProspectLines = 3;

  int _linesSpoken = 1; // the opening line
  int _pushbackIndex = 0;
  bool _done = false;

  RoleplaySession({
    required this.persona,
    required this.faqEntry,
    ComplianceScanner scanner = const ComplianceScanner(),
  }) : _scanner = scanner;

  bool get isDone => _done;
  int get linesSpoken => _linesSpoken;

  /// The line the prospect opens with, with its emotion markup ready
  /// for the voice service.
  String get openingMarked => '[${persona.openingEmotion}] ${persona.openingLine}';

  /// Reviews the user's [answer] and returns the coach review plus the
  /// prospect's next line (null when the practice round is complete).
  ({CoachReview review, String? nextMarkedLine}) answer(String answer) {
    final review = CoachReview(
      report: _scanner.scan(answer),
      coveredPoints: persona.keyPoints
          .where((kp) => kp.coveredBy(answer))
          .map((kp) => kp.label)
          .toList(),
      missedPoints: persona.keyPoints
          .where((kp) => !kp.coveredBy(answer))
          .map((kp) => kp.label)
          .toList(),
      suggestedPhrasing: suggestedPhrasingFor(faqEntry, persona.keyPoints),
    );
    if (_linesSpoken >= maxProspectLines) {
      _done = true;
      return (review: review, nextMarkedLine: null);
    }
    final lower = answer.toLowerCase();
    String line;
    String emotion;
    ProspectReaction? matched;
    for (final r in persona.reactions) {
      if (r.keywords.any((k) => lower.contains(k))) {
        matched = r;
        break;
      }
    }
    if (matched != null) {
      line = matched.line;
      emotion = matched.emotion;
    } else {
      line = persona.pushbacks[_pushbackIndex % persona.pushbacks.length];
      _pushbackIndex++;
      emotion = 'neutral';
    }
    _linesSpoken++;
    return (review: review, nextMarkedLine: '[$emotion] $line');
  }

  /// Closing line when the round completes — warm, and it thanks the
  /// user like a real conversation would wind down.
  String get closingMarked =>
      '[warm] Okay — thank you for explaining all that. I will think '
      'it over. You did well — check the coach notes and try again '
      'any time.';
}

/// Engine facade over the persona bank + the database.
class RoleplayEngine {
  final KnowledgeDb db;
  const RoleplayEngine(this.db);

  List<ProspectPersona> get personas => kProspectPersonas;

  ProspectPersona personaById(String id) => kProspectPersonas.firstWhere(
        (p) => p.id == id,
        orElse: () => kProspectPersonas.first,
      );

  /// Starts a session for [persona]. Returns null when the persona's
  /// faq entry is missing from the database (never in shipped data).
  RoleplaySession? start(ProspectPersona persona) {
    final entry = db.byId(persona.faqEntryId);
    if (entry == null) return null;
    return RoleplaySession(persona: persona, faqEntry: entry);
  }
}
