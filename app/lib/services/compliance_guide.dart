import '../models/entry.dart';
import 'compliance.dart';

/// Plain-language explanations for compliance hits (SPEC §7.9 rider).
///
/// The scanner (M2) finds the phrases; this guide explains WHY each
/// category is a problem and which compliant direction to take instead.
/// The directions come from the playbook's own do/don't entries
/// (play-compliance-do / play-compliance-dont) — quoted at guidance
/// level, never as a silent rewrite: the checker NEVER edits the
/// user's text for them.
class ComplianceExplanation {
  final ComplianceHit hit;
  final String why;
  final String suggestion;
  const ComplianceExplanation({
    required this.hit,
    required this.why,
    required this.suggestion,
  });
}

class ComplianceGuide {
  final KnowledgeEntry? doEntry;
  final KnowledgeEntry? dontEntry;
  const ComplianceGuide({this.doEntry, this.dontEntry});

  factory ComplianceGuide.fromDb(List<KnowledgeEntry> entries) {
    KnowledgeEntry? find(String id) {
      for (final e in entries) {
        if (e.id == id) return e;
      }
      return null;
    }

    return ComplianceGuide(
      doEntry: find('play-compliance-do'),
      dontEntry: find('play-compliance-dont'),
    );
  }

  String _why(ComplianceCategory c) {
    switch (c) {
      case ComplianceCategory.medicalClaim:
        return 'This reads as claiming a product cures, treats, prevents, '
            'heals or diagnoses a health condition. Public medical claims '
            'are not allowed — the groups and the company both prohibit '
            'them.';
      case ComplianceCategory.restrictedTerm:
        return 'This wording is on the restricted list: it names a '
            'condition or promises a treatment effect, which turns an '
            'everyday post into a medical claim.';
      case ComplianceCategory.promise:
        return 'This promises a result or a timeline. Nobody can promise '
            'what another person will feel or when — the company makes '
            'no such promise, so a post must not either.';
      case ComplianceCategory.incomeClaim:
        return 'This makes an income or lifestyle claim. Income talk is '
            'only allowed alongside the official Earnings Disclosure '
            'Statement, using its typical figures — never as a promise.';
    }
  }

  String _suggestion(ComplianceCategory c) {
    switch (c) {
      case ComplianceCategory.medicalClaim:
      case ComplianceCategory.restrictedTerm:
        return 'Try the compliant direction from the playbook: stick to '
            'the company\'s official "supports…" language, or turn the '
            'sentence into an everyday-experience question about '
            'routines, energy or sleep — no conditions named.';
      case ComplianceCategory.promise:
        return 'Try asking instead of promising: "what helps your '
            'energy?" invites answers without guaranteeing anyone a '
            'result.';
      case ComplianceCategory.incomeClaim:
        return 'Keep opportunity posts curious about the work, never '
            'about the money — and cover any real figures only with the '
            'Earnings Disclosure Statement alongside.';
    }
  }

  List<ComplianceExplanation> explain(ComplianceReport report) => report.hits
      .map((h) => ComplianceExplanation(
            hit: h,
            why: _why(h.category),
            suggestion: _suggestion(h.category),
          ))
      .toList(growable: false);

  /// Hits grouped by category, in a stable display order, for the
  /// standalone checker screen.
  Map<ComplianceCategory, List<ComplianceHit>> groupByCategory(
      ComplianceReport report) {
    final out = <ComplianceCategory, List<ComplianceHit>>{};
    for (final c in ComplianceCategory.values) {
      final hits = report.hits.where((h) => h.category == c).toList();
      if (hits.isNotEmpty) out[c] = hits;
    }
    return out;
  }
}
