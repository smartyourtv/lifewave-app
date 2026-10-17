import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifewave_app/models/entry.dart';
import 'package:lifewave_app/services/knowledge_db.dart';

Map<String, dynamic> goodEntry(String id) => {
      'id': id,
      'topic': 'products',
      'title': 'Entry $id',
      'body': 'Body of $id',
      'audience': 'public',
      'source_type': 'official-site',
      'source_ref': 'https://example.com/$id',
      'claim_label': 'official fact',
      'updated': '2026-10-17',
    };

AssetTextLoader fixtureLoader({
  required Object? manifest,
  Map<String, Object?> topicFiles = const {},
}) {
  return (path) async {
    if (path == KnowledgeDb.manifestAssetPath) {
      if (manifest == null) throw Exception('missing manifest');
      return jsonEncode(manifest);
    }
    final v = topicFiles[path];
    if (v == null) throw Exception('missing file $path');
    return jsonEncode(v);
  };
}

void main() {
  group('KnowledgeEntry.tryDecode', () {
    test('decodes a full product entry with optional fields', () {
      final raw = goodEntry('prod-x39')
        ..['item_code'] = '39000.022.009'
        ..['price_retail_usd'] = 149.95
        ..['price_subscribe_usd'] = 99.95
        ..['category'] = 'patch';
      final e = KnowledgeEntry.tryDecode(raw);
      expect(e, isNotNull);
      expect(e!.itemCode, '39000.022.009');
      expect(e.priceRetailUsd, 149.95);
      expect(e.priceSubscribeUsd, 99.95);
      expect(e.category, 'patch');
      expect(e.claimChipText, 'Official fact');
    });

    test('missing optional fields decode as null (rendered "not listed")', () {
      final e = KnowledgeEntry.tryDecode(goodEntry('prod-nirvana-legacy'));
      expect(e, isNotNull);
      expect(e!.itemCode, isNull);
      expect(e.priceRetailUsd, isNull);
      expect(e.priceSubscribeUsd, isNull);
    });

    test('malformed entries return null: missing required, mistyped, non-map',
        () {
      final missingBody = goodEntry('bad-1')..remove('body');
      expect(KnowledgeEntry.tryDecode(missingBody), isNull);
      final mistyped = goodEntry('bad-2')..['title'] = 42;
      expect(KnowledgeEntry.tryDecode(mistyped), isNull);
      final emptyId = goodEntry('bad-3')..['id'] = '  ';
      expect(KnowledgeEntry.tryDecode(emptyId), isNull);
      expect(KnowledgeEntry.tryDecode('not a map'), isNull);
      expect(KnowledgeEntry.tryDecode(null), isNull);
    });

    test('mistyped optional price is tolerated as null, not fatal', () {
      final raw = goodEntry('prod-x')..['price_retail_usd'] = 'soon';
      final e = KnowledgeEntry.tryDecode(raw);
      expect(e, isNotNull);
      expect(e!.priceRetailUsd, isNull);
    });
  });

  group('KnowledgeDb.load', () {
    test('loads manifest + topics; malformed entries skipped and counted',
        () async {
      final db = await KnowledgeDb.load(
        loader: fixtureLoader(
          manifest: {
            'db_version': 3,
            'files': [
              {'topic': 'products', 'path': 'products/products.json', 'entries': 3},
            ],
          },
          topicFiles: {
            'assets/db/products/products.json': {
              'topic': 'products',
              'entries': [
                goodEntry('prod-a'),
                goodEntry('prod-b')..remove('claim_label'), // malformed
                goodEntry('prod-c'),
              ],
            },
          },
        ),
      );
      expect(db.dbVersion, 3);
      expect(db.entryCount, 2);
      expect(db.skippedMalformed, 1);
      expect(db.topics, ['products']);
      expect(db.byId('prod-a'), isNotNull);
      expect(db.byId('prod-b'), isNull);
    });

    test('older db_version >= 1 is accepted and recorded', () async {
      final db = await KnowledgeDb.load(
        loader: fixtureLoader(
          manifest: {
            'db_version': 1,
            'files': [
              {'topic': 'faq', 'path': 'faq/faq.json', 'entries': 0},
            ],
          },
          topicFiles: {
            'assets/db/faq/faq.json': {'topic': 'faq', 'entries': []},
          },
        ),
      );
      expect(db.dbVersion, 1);
    });

    test('missing manifest fails closed with DbLoadException', () async {
      expect(
        () => KnowledgeDb.load(loader: fixtureLoader(manifest: null)),
        throwsA(isA<DbLoadException>()),
      );
    });

    test('manifest without db_version fails closed', () async {
      expect(
        () => KnowledgeDb.load(
          loader: fixtureLoader(manifest: {'files': []}),
        ),
        throwsA(isA<DbLoadException>()),
      );
    });

    test('manifest listing a missing topic file fails closed', () async {
      expect(
        () => KnowledgeDb.load(
          loader: fixtureLoader(
            manifest: {
              'db_version': 2,
              'files': [
                {'topic': 'faq', 'path': 'faq/faq.json', 'entries': 1},
              ],
            },
          ),
        ),
        throwsA(isA<DbLoadException>()),
      );
    });
  });

  group('Bundled database (real assets)', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('bundled DB loads with the shipped entry counts', () async {
      final db = await KnowledgeDb.load();
      expect(db.dbVersion, 5);
      // manifest.json re-synced at M3: db_version 5, 95 entries total.
      expect(db.entryCount, 95);
      expect(db.skippedMalformed, 0);
      expect(db.byId('prod-x39'), isNotNull);
      expect(db.byId('prod-nirvana-legacy')!.priceRetailUsd, isNull);
    });
  });
}
