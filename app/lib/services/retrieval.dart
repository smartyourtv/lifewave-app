import '../models/entry.dart';

/// Deterministic, fully offline keyword retrieval over the bundled
/// database. Tokenized search over title / body / topic with simple
/// scoring — title hits weigh more than body hits. No randomness, no
/// network, same query always gives the same order.
class ScoredEntry {
  final KnowledgeEntry entry;
  final int score;
  const ScoredEntry(this.entry, this.score);
}

class Retrieval {
  final List<KnowledgeEntry> _entries;
  const Retrieval(this._entries);

  static const Set<String> _stopwords = {
    'a', 'an', 'the', 'is', 'it', 'of', 'to', 'in', 'on', 'for', 'and',
    'or', 'what', 'how', 'do', 'does', 'i', 'me', 'my', 'can', 'you',
    'your', 'are', 'was', 'were', 'be', 'with', 'about', 'tell', 'please',
  };

  static List<String> tokenize(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.isNotEmpty && !_stopwords.contains(t))
        .toList(growable: false);
  }

  static int _countOccurrences(List<String> tokens, String token) {
    var n = 0;
    for (final t in tokens) {
      if (t == token) n++;
    }
    return n;
  }

  int _score(KnowledgeEntry e, List<String> queryTokens) {
    final titleTokens = tokenize(e.title);
    final bodyTokens = tokenize(e.body);
    final topicTokens = tokenize(e.topic);
    final idText = e.id.toLowerCase();
    var score = 0;
    for (final q in queryTokens) {
      // Title word hit weighs most.
      if (titleTokens.contains(q)) score += 10;
      // Product/topic ids (e.g. "prod-x39") carry the product code.
      if (idText.split('-').contains(q)) score += 8;
      // Topic hit.
      if (topicTokens.contains(q)) score += 5;
      // Body hits, capped so long bodies can't dominate.
      final bodyHits = _countOccurrences(bodyTokens, q);
      score += (bodyHits > 3 ? 3 : bodyHits) * 2;
    }
    return score;
  }

  /// Top matches for [query], best first. Empty when nothing matches —
  /// the caller must answer honestly, never fabricate (SPEC §7.11).
  List<ScoredEntry> search(String query, {int limit = 5}) {
    final queryTokens = tokenize(query).toSet().toList(growable: false);
    if (queryTokens.isEmpty) return const [];
    final results = <ScoredEntry>[];
    for (final e in _entries) {
      final s = _score(e, queryTokens);
      if (s > 0) results.add(ScoredEntry(e, s));
    }
    results.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byTitle = a.entry.title.compareTo(b.entry.title);
      if (byTitle != 0) return byTitle;
      return a.entry.id.compareTo(b.entry.id);
    });
    return results.take(limit).toList(growable: false);
  }
}

/// One fragment of a composed chat answer: an entry plus the excerpt shown
/// for it. The claim label lives on the entry and is rendered by the UI
/// from the entry itself, so a fragment can never lose its label
/// (PRE-BUILD-AUDIT §2 — label travels with the entry through assembly).
class AnswerFragment {
  final KnowledgeEntry entry;
  final String text;
  const AnswerFragment(this.entry, this.text);
}

/// A composed chat answer: either grounded fragments, or the honest
/// no-match answer.
class ComposedAnswer {
  final String question;
  final List<AnswerFragment> fragments;
  const ComposedAnswer(this.question, this.fragments);

  bool get hasMatches => fragments.isNotEmpty;
}

/// Composes an answer from retrieval results: quotes/summarizes entry
/// bodies, one fragment per entry, labels attached.
ComposedAnswer composeAnswer(String question, List<ScoredEntry> results) {
  final fragments = results
      .map((r) => AnswerFragment(r.entry, r.entry.body))
      .toList(growable: false);
  return ComposedAnswer(question, fragments);
}

/// The honest no-match text. Shown when retrieval finds nothing.
const String noMatchAnswerText =
    "I don't have that in the database yet, so I can't answer it from "
    'checked information. You could try different words, browse the '
    'product catalog, or check the guide topics in the catalog.';
