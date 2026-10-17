import '../models/entry.dart';
import 'compliance.dart';

/// Presentation mode model (SPEC §7.8 item 3): a full-screen product
/// slideshow built from OFFICIAL facts only.
///
/// Slide facts are extracted from the product entry body exactly the
/// fact-card way (see services/fact_card.dart): substantive sentences,
/// scanner-clean only, disclaimer sentences skipped. A slide NEVER
/// carries a flagged sentence — if an entry had too few clean
/// sentences, the slide shows fewer lines rather than a risky one.
class PresentationSlide {
  final String productId;
  final String productTitle;
  final String? imageAssetPath;

  /// 2–3 official-fact lines (fewer only when the entry has fewer
  /// clean ones — honesty over padding).
  final List<String> factLines;
  final String claimLabel;

  const PresentationSlide({
    required this.productId,
    required this.productTitle,
    required this.imageAssetPath,
    required this.factLines,
    required this.claimLabel,
  });

  /// All on-slide text, for translation + scanning.
  String get captionText => '$productTitle\n${factLines.join('\n')}';
}

/// Extracts up to [maxLines] scanner-clean fact sentences from an
/// entry body, preferring the company's own positioning language
/// ("supports…", "the company says…") in body order.
List<String> cleanFactLines(
  KnowledgeEntry entry, {
  int maxLines = 3,
  ComplianceScanner scanner = const ComplianceScanner(),
}) {
  final flat = entry.body.replaceAll(RegExp(r'\s+'), ' ').trim();
  final sentences = flat
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((s) => s.trim())
      .where((s) => s.length >= 40)
      .where((s) => !s.toLowerCase().contains('not intended'))
      .where((s) => !s.toLowerCase().contains('fda'))
      .where((s) => scanner.scan(s).isClean)
      .toList();
  return sentences.take(maxLines).toList(growable: false);
}

/// Builds slides for [products] (the screen passes the flagship set
/// by default, or the user's picks).
List<PresentationSlide> buildSlides(
  List<KnowledgeEntry> products, {
  required String? Function(String productId) imageFor,
  ComplianceScanner scanner = const ComplianceScanner(),
}) {
  return products
      .map((p) => PresentationSlide(
            productId: p.id,
            productTitle: p.title,
            imageAssetPath: imageFor(p.id),
            factLines: cleanFactLines(p, scanner: scanner),
            claimLabel: p.claimLabel,
          ))
      .toList(growable: false);
}

/// The flagship default set: the well-known patch lines, in catalog
/// order, capped so a presentation stays watchable. Falls back to the
/// first products when ids ever change.
List<KnowledgeEntry> flagshipProducts(List<KnowledgeEntry> products) {
  const flagshipIds = [
    'prod-x39',
    'prod-x49',
    'prod-silent-nights',
    'prod-energy-enhancer',
    'prod-icewave',
    'prod-alavida-patches',
  ];
  final picked = <KnowledgeEntry>[];
  for (final id in flagshipIds) {
    for (final p in products) {
      if (p.id == id) picked.add(p);
    }
  }
  if (picked.length >= 3) return picked;
  return products.take(6).toList();
}

/// Cache key for a translated slide caption: slide + language. One
/// translation per (slide, language) — re-showing a slide in the same
/// language never re-runs the engine.
String captionCacheKey(String productId, String languageCode) =>
    '$productId|$languageCode';

/// A tiny caption cache for the presentation screen.
class CaptionCache {
  final Map<String, String> _cache = {};
  String? get(String productId, String languageCode) =>
      _cache[captionCacheKey(productId, languageCode)];
  void put(String productId, String languageCode, String text) =>
      _cache[captionCacheKey(productId, languageCode)] = text;
  int get size => _cache.length;
  void clear() => _cache.clear();
}
