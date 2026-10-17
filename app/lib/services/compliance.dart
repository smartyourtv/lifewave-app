/// Compliance scanner (SPEC §3 + §7.9) — reusable service, built in M2
/// and reused by M3's standalone checker UI.
///
/// Term/pattern lists are drawn from the bundled database playbook
/// compliance entries:
///  - play-compliance-dont (db/playbook/playbook.json): never claim or
///    imply a product "cures, treats, prevents, heals or diagnoses" any
///    disease or condition; never name a condition and say a patch helped
///    it; never present a testimonial as proof; never promise results or
///    timelines; no income/lifestyle claims without the Earnings
///    Disclosure Statement.
///  - play-compliance-do: stick to official "supports…" language; the test
///    question is "does this sentence promise a health outcome?"
///
/// The scanner FLAGS hits visibly. It NEVER silently rewrites text —
/// distributor claims must not be laundered into facts by an edit loop
/// (PRE-BUILD-AUDIT §2). It runs on FINAL-LANGUAGE text (SPEC §7.4), so
/// the lists include common non-English equivalents.
enum ComplianceCategory { medicalClaim, restrictedTerm, incomeClaim, promise }

class ComplianceHit {
  final String term; // the matched text, as it appeared
  final ComplianceCategory category;
  final int start; // offset in the scanned text
  const ComplianceHit({
    required this.term,
    required this.category,
    required this.start,
  });

  String get categoryLabel {
    switch (category) {
      case ComplianceCategory.medicalClaim:
        return 'Medical claim';
      case ComplianceCategory.restrictedTerm:
        return 'Restricted term';
      case ComplianceCategory.incomeClaim:
        return 'Income claim';
      case ComplianceCategory.promise:
        return 'Promised result';
    }
  }

  @override
  String toString() => '$categoryLabel: "$term"';
}

class ComplianceReport {
  final List<ComplianceHit> hits;
  const ComplianceReport(this.hits);
  bool get isClean => hits.isEmpty;
  bool get hasHits => hits.isNotEmpty;
}

class ComplianceScanner {
  const ComplianceScanner();

  /// Forbidden claim verbs (play-compliance-dont: "cures, treats,
  /// prevents, heals or diagnoses … those words and their synonyms are
  /// forbidden territory") + close synonyms.
  static const List<String> _medicalClaimWords = [
    'cure', 'cures', 'cured', 'curing',
    'treat', 'treats', 'treated', 'treating',
    'diagnose', 'diagnoses', 'diagnosed', 'diagnosing',
    'prevent', 'prevents', 'prevented', 'preventing',
    'heal', 'heals', 'healed', 'healing',
    // Non-English equivalents (final-language scanning, SPEC §7.4):
    'cura', 'curar', 'curado', // Spanish/Portuguese "cure"
    'guérir', 'guérit', // French "heal/cure"
    'chữa', 'điều trị', // Vietnamese "cure / treat"
  ];

  /// Broader treatment nouns that read as medical claims in product copy.
  static const List<String> _restrictedTerms = [
    'treatment for',
    'remedy for',
    'fixes my',
    'fixed my',
    'miracle',
    'clinically proven',
    'disease',
    'cancer',
    'diabetes',
    'arthritis',
  ];

  static const List<String> _promisePhrases = [
    'you will feel',
    "you'll feel",
    'guaranteed results',
    'guarantee results',
    'works for everyone',
    'feel it in a week',
    'results in days',
  ];

  static const List<String> _incomePhrases = [
    'get rich',
    'financial freedom guaranteed',
    'quit your job',
    'six figures',
    '6 figures',
    'passive income guaranteed',
    'make money fast',
  ];

  ComplianceReport scan(String text) {
    if (text.trim().isEmpty) return const ComplianceReport([]);
    final lower = text.toLowerCase();
    final hits = <ComplianceHit>[];

    void scanList(List<String> terms, ComplianceCategory cat,
        {bool wordBoundary = false}) {
      for (final term in terms) {
        var from = 0;
        while (true) {
          final i = lower.indexOf(term, from);
          if (i < 0) break;
          var ok = true;
          if (wordBoundary) {
            final beforeOk = i == 0 ||
                !RegExp(r'[a-zà-ỹ]').hasMatch(lower[i - 1]);
            final end = i + term.length;
            final afterOk = end >= lower.length ||
                !RegExp(r'[a-zà-ỹ]').hasMatch(lower[end]);
            ok = beforeOk && afterOk;
          }
          if (ok) {
            hits.add(ComplianceHit(
              term: text.substring(i, i + term.length),
              category: cat,
              start: i,
            ));
          }
          from = i + term.length;
        }
      }
    }

    // Claim verbs use word boundaries so "secure"/"accurate" never trip
    // on the substring "cure"/"cur…".
    scanList(_medicalClaimWords, ComplianceCategory.medicalClaim,
        wordBoundary: true);
    scanList(_restrictedTerms, ComplianceCategory.restrictedTerm);
    // Promise phrases, with one precision rule (M3): "works for
    // everyone ELSE" is the playbook's own template question — asking
    // readers what works for them — not a promise. "Works for
    // everyone" standing alone (a universality claim) still flags.
    for (final term in _promisePhrases) {
      var from = 0;
      while (true) {
        final i = lower.indexOf(term, from);
        if (i < 0) break;
        final end = i + term.length;
        final after = lower.substring(end).trimLeft();
        final negated =
            term == 'works for everyone' && after.startsWith('else');
        if (!negated) {
          hits.add(ComplianceHit(
            term: text.substring(i, end),
            category: ComplianceCategory.promise,
            start: i,
          ));
        }
        from = end;
      }
    }
    scanList(_incomePhrases, ComplianceCategory.incomeClaim);

    hits.sort((a, b) => a.start.compareTo(b.start));
    return ComplianceReport(List.unmodifiable(hits));
  }
}
