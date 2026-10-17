import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/entry.dart';

/// Loads a text asset by path. Injectable so unit tests can serve fixtures
/// instead of the real bundled assets.
typedef AssetTextLoader = Future<String> Function(String path);

Future<String> _rootBundleLoader(String path) => rootBundle.loadString(path);

/// Raised when the database cannot be loaded at all. The app fails CLOSED
/// with a plain-language error screen (PRE-BUILD-AUDIT §2) — never a crash,
/// never a half-loaded database, never invented content.
class DbLoadException implements Exception {
  final String message;
  const DbLoadException(this.message);
  @override
  String toString() => message;
}

/// The bundled knowledge database: manifest + every topic file it lists.
class KnowledgeDb {
  static const String manifestAssetPath = 'assets/db/manifest.json';
  static const String dbAssetPrefix = 'assets/db/';

  /// Oldest db_version this build accepts (PRE-BUILD-AUDIT §4: tolerate
  /// older db_versions; accept >= 1 and record the actual version).
  static const int minSupportedDbVersion = 1;

  final int dbVersion;
  final List<KnowledgeEntry> entries;

  /// Entries skipped because a required field was missing/mistyped.
  final int skippedMalformed;

  /// Topic names in manifest order.
  final List<String> topics;

  const KnowledgeDb({
    required this.dbVersion,
    required this.entries,
    required this.skippedMalformed,
    required this.topics,
  });

  int get entryCount => entries.length;

  List<KnowledgeEntry> byTopic(String topic) =>
      entries.where((e) => e.topic == topic).toList(growable: false);

  KnowledgeEntry? byId(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Full load: manifest first, then every topic file the manifest lists.
  /// Any structural problem (missing/corrupt manifest, missing db_version,
  /// a listed topic file that cannot be read/parsed) fails the whole load.
  static Future<KnowledgeDb> load({AssetTextLoader? loader}) async {
    final loadText = loader ?? _rootBundleLoader;

    // 1. Manifest first — fail closed if it is missing or corrupt.
    final Object? manifestRaw;
    try {
      manifestRaw = jsonDecode(await loadText(manifestAssetPath));
    } catch (_) {
      throw const DbLoadException(
        'The knowledge database could not be loaded: its index file '
        '(manifest) is missing or damaged. Try restarting the app. If it '
        'keeps happening, reinstall the app to restore the database.',
      );
    }
    if (manifestRaw is! Map<String, dynamic>) {
      throw const DbLoadException(
        'The knowledge database could not be loaded: its index file '
        '(manifest) is not in the expected format. Try reinstalling the app.',
      );
    }

    final versionRaw = manifestRaw['db_version'];
    if (versionRaw is! int) {
      throw const DbLoadException(
        'The knowledge database could not be loaded: it does not say which '
        'version it is. Try reinstalling the app to restore the database.',
      );
    }
    if (versionRaw < minSupportedDbVersion) {
      throw DbLoadException(
        'This database version ($versionRaw) is older than this app can '
        'read. Please update the app.',
      );
    }

    final filesRaw = manifestRaw['files'];
    if (filesRaw is! List) {
      throw const DbLoadException(
        'The knowledge database could not be loaded: its index does not '
        'list any topic files. Try reinstalling the app.',
      );
    }

    // 2. Load every topic file listed in the manifest.
    final all = <KnowledgeEntry>[];
    final topics = <String>[];
    var skipped = 0;
    for (final fileRaw in filesRaw) {
      if (fileRaw is! Map<String, dynamic>) {
        throw const DbLoadException(
          'The knowledge database could not be loaded: its index lists a '
          'topic in an unexpected format. Try reinstalling the app.',
        );
      }
      final topic = fileRaw['topic'];
      final path = fileRaw['path'];
      if (topic is! String || path is! String) {
        throw const DbLoadException(
          'The knowledge database could not be loaded: its index is '
          'incomplete. Try reinstalling the app.',
        );
      }
      topics.add(topic);
      final Object? topicRaw;
      try {
        topicRaw = jsonDecode(await loadText('$dbAssetPrefix$path'));
      } catch (_) {
        throw DbLoadException(
          'The knowledge database could not be loaded: the "$topic" topic '
          'file is missing or damaged. Try reinstalling the app.',
        );
      }
      if (topicRaw is! Map<String, dynamic> || topicRaw['entries'] is! List) {
        throw DbLoadException(
          'The knowledge database could not be loaded: the "$topic" topic '
          'file is not in the expected format. Try reinstalling the app.',
        );
      }
      for (final rawEntry in topicRaw['entries'] as List) {
        final entry = KnowledgeEntry.tryDecode(rawEntry);
        if (entry == null) {
          skipped++; // malformed entry: skipped + counted, never fatal
        } else {
          all.add(entry);
        }
      }
    }

    return KnowledgeDb(
      dbVersion: versionRaw,
      entries: List.unmodifiable(all),
      skippedMalformed: skipped,
      topics: List.unmodifiable(topics),
    );
  }
}
