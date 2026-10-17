import 'package:flutter_test/flutter_test.dart';
import 'package:lifewave_app/models/entry.dart';
import 'package:lifewave_app/services/retrieval.dart';

KnowledgeEntry makeEntry({
  required String id,
  required String title,
  required String body,
  String topic = 'products',
  String claimLabel = 'official fact',
}) {
  return KnowledgeEntry(
    id: id,
    topic: topic,
    title: title,
    body: body,
    audience: 'public',
    sourceType: 'official-site',
    sourceRef: 'https://example.com/$id',
    claimLabel: claimLabel,
    updated: '2026-10-17',
  );
}

void main() {
  final entries = [
    makeEntry(
      id: 'prod-x39',
      title: 'LifeWave X39® Patches',
      body: 'The flagship patch. Supports exercise performance.',
    ),
    makeEntry(
      id: 'prod-performance-bundle',
      title: 'X39® & X49® Performance Bundle',
      body: 'A bundle of X39 and X49 sleeves.',
    ),
    makeEntry(
      id: 'prod-x49',
      title: 'LifeWave X49™ Patches',
      body: 'A patch for performance and stamina.',
    ),
    makeEntry(
      id: 'play-question-led-pattern',
      title: 'Curiosity posts: the question-led pattern',
      body: 'Ask a genuine question instead of pitching the product.',
      topic: 'playbook',
      claimLabel: 'distributor claim',
    ),
  ];

  test('"X39" query returns prod-x39 first', () {
    final results = Retrieval(entries).search('X39');
    expect(results, isNotEmpty);
    expect(results.first.entry.id, 'prod-x39');
  });

  test('nonsense query returns empty (honest no-match path)', () {
    final results = Retrieval(entries).search('zzqqx blorp snizzle');
    expect(results, isEmpty);
  });

  test('empty / stopword-only query returns empty', () {
    expect(Retrieval(entries).search(''), isEmpty);
    expect(Retrieval(entries).search('what is the'), isEmpty);
  });

  test('claim labels survive retrieval + answer composition', () {
    final results = Retrieval(entries).search('curiosity question');
    expect(results, isNotEmpty);
    final answer = composeAnswer('curiosity question', results);
    expect(answer.hasMatches, isTrue);
    for (final fragment in answer.fragments) {
      // Every fragment carries its entry — and therefore its label.
      expect(fragment.entry.claimLabel, isNotEmpty);
      expect(
        fragment.entry.claimLabel,
        anyOf('official fact', 'distributor claim'),
      );
    }
    final playbookFragment = answer.fragments
        .firstWhere((f) => f.entry.id == 'play-question-led-pattern');
    expect(playbookFragment.entry.claimChipText, 'Distributor claim');
  });

  test('search is deterministic: same query, same order, twice', () {
    final a = Retrieval(entries).search('patch').map((r) => r.entry.id).toList();
    final b = Retrieval(entries).search('patch').map((r) => r.entry.id).toList();
    expect(a, b);
    expect(a, isNotEmpty);
  });
}
