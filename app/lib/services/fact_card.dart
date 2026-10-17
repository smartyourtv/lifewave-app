import '../models/entry.dart';
import 'compliance.dart';

/// Fact-card data model (SPEC §7.8 item 4).
///
/// A card is TEMPLATE-COMPOSED from database content only: one official
/// fact taken from the product's own entry body, and one curiosity
/// question built from the playbook question pattern. No invented
/// claims — and the composed text must pass the compliance scanner
/// before the card can be exported (the screen enforces that gate;
/// [composeFactCard] already prefers scanner-clean sentences).
class FactCardData {
  final String productId;
  final String productTitle;

  /// Bundled brand-asset path for the official picture, or null — the
  /// branded placeholder renders instead (the Nirvana case).
  final String? imageAssetPath;

  /// One official fact, verbatim from the entry body.
  final String fact;

  /// One curiosity question in the playbook's question-led style.
  final String question;

  /// The entry's claim label — printed on the card so the fact can
  /// never travel without its label (SPEC §3).
  final String claimLabel;

  const FactCardData({
    required this.productId,
    required this.productTitle,
    required this.imageAssetPath,
    required this.fact,
    required this.question,
    required this.claimLabel,
  });

  bool get hasOfficialPicture => imageAssetPath != null;

  /// All text that will appear on the card — scanned as one before
  /// export.
  String get allText => '$productTitle $fact $question';
}

/// The curiosity question for a card, by focus topic — everyday-
/// experience language only, in the playbook's question-led pattern.
String factCardQuestion(String focus) {
  switch (focus) {
    case 'sleep':
      return 'Quick question: what is the ONE thing that actually helps '
          'your sleep?';
    case 'recovery':
      return 'Quick question: what helps you recover after a workout?';
    case 'performance':
      return 'Quick question: what do you do to stay strong and active?';
    case 'skin':
      return 'Quick question: what is your favorite part of your '
          'skincare routine?';
    case 'energy':
      return 'Quick question: what do you do when your energy runs out '
          'by mid-afternoon?';
    default:
      return 'Quick question: what is the ONE thing you do that '
          'actually helps you feel your best?';
  }
}

/// Picks the card's fact sentence from the entry body: the first
/// sentence that is substantive, scanner-clean, and preferably carries
/// the company's own positioning ("the company says…" / "supports…").
/// Sentences with FDA-disclaimer wording are skipped — a disclaimer is
/// not a fact to feature, and its claim verbs would (correctly) trip
/// the scanner.
String pickFactSentence(
  KnowledgeEntry entry, {
  ComplianceScanner scanner = const ComplianceScanner(),
}) {
  final flat = entry.body.replaceAll(RegExp(r'\s+'), ' ').trim();
  final sentences = flat
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((s) => s.trim())
      .where((s) => s.length >= 40)
      .where((s) => !s.toLowerCase().contains('not intended'))
      .where((s) => !s.toLowerCase().contains('fda'))
      .toList();
  String? firstClean;
  for (final s in sentences) {
    if (!scanner.scan(s).isClean) continue;
    firstClean ??= s;
    final lower = s.toLowerCase();
    if (lower.contains('supports') || lower.contains('company says')) {
      return s;
    }
  }
  if (firstClean != null) return firstClean;
  // Last resort: the first substantive sentence as-is. The export gate
  // will scan the composed card and block it if this ever trips.
  return sentences.isNotEmpty ? sentences.first : flat;
}

/// Composes the fact card for [product]. [imageAssetPath] comes from
/// the brand-asset map (null = branded placeholder, e.g. Nirvana).
FactCardData composeFactCard(
  KnowledgeEntry product, {
  required String? imageAssetPath,
  required String focus,
  ComplianceScanner scanner = const ComplianceScanner(),
}) {
  return FactCardData(
    productId: product.id,
    productTitle: product.title,
    imageAssetPath: imageAssetPath,
    fact: pickFactSentence(product, scanner: scanner),
    question: factCardQuestion(focus),
    claimLabel: product.claimLabel,
  );
}
