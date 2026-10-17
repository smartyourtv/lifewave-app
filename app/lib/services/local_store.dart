import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

/// Tiny persistent JSON store backing the M3 local lists (post queue,
/// reply drafts, prospects, quick templates).
///
/// Rules (task + PRE-BUILD-AUDIT §2):
///  - The file lives in the app-private documents directory — no storage
///    permission, the user's own data, on-device only.
///  - Writes are atomic-ish: write a temp file, then rename over the
///    target, so a killed app never leaves a half-written file.
///  - A corrupt/unreadable file NEVER crashes the app: reads degrade to
///    an empty document and the problem is surfaced as [lastWarning],
///    which Diagnostics displays. The corrupt file is preserved (renamed
///    aside) rather than silently wiped.

/// File IO seam — unit tests use [MemoryFileIo], the app uses
/// [AppDocsFileIo].
abstract class TextFileIo {
  Future<String?> readText(String name);

  /// Atomic-ish write of [contents] to the file called [name].
  Future<void> writeTextAtomic(String name, String contents);

  /// Moves a corrupt file aside (best effort) so it is preserved.
  Future<void> preserveAside(String name);
}

class AppDocsFileIo implements TextFileIo {
  Directory? _dir;

  Future<Directory> _docs() async =>
      _dir ??= await getApplicationDocumentsDirectory();

  @override
  Future<String?> readText(String name) async {
    final f = File('${(await _docs()).path}/$name');
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  @override
  Future<void> writeTextAtomic(String name, String contents) async {
    final dir = await _docs();
    final tmp = File('${dir.path}/$name.tmp');
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename('${dir.path}/$name');
  }

  @override
  Future<void> preserveAside(String name) async {
    try {
      final dir = await _docs();
      final f = File('${dir.path}/$name');
      if (await f.exists()) {
        await f.rename(
            '${dir.path}/$name.corrupt-${DateTime.now().millisecondsSinceEpoch}');
      }
    } catch (_) {
      // Preserving is best-effort; degradation must never crash.
    }
  }
}

/// In-memory IO for tests and previews.
class MemoryFileIo implements TextFileIo {
  final Map<String, String> files = {};
  final List<String> preserved = [];

  @override
  Future<String?> readText(String name) async => files[name];

  @override
  Future<void> writeTextAtomic(String name, String contents) async {
    files[name] = contents;
  }

  @override
  Future<void> preserveAside(String name) async {
    final v = files.remove(name);
    if (v != null) preserved.add(name);
  }
}

/// One JSON document on disk: a versioned map of named lists.
class JsonDocumentStore {
  final TextFileIo io;
  final String fileName;
  static const int docVersion = 1;

  /// Plain-language description of the last load problem, or null.
  /// Shown on the Diagnostics card — a degraded store is visible,
  /// never silent (and never a crash).
  String? lastWarning;

  Map<String, dynamic> _doc = {'version': docVersion};

  JsonDocumentStore({required this.io, this.fileName = 'social_store.json'});

  /// Loads the document. Missing file = first run (empty, no warning).
  /// Corrupt file = empty + [lastWarning] + file preserved aside.
  Future<void> load() async {
    lastWarning = null;
    String? raw;
    try {
      raw = await io.readText(fileName);
    } catch (e) {
      debugPrint('JsonDocumentStore read error: $e');
      lastWarning = 'Your saved posts, replies and prospects could not be '
          'read on this device. The app started with empty lists instead '
          'of crashing.';
      _doc = {'version': docVersion};
      return;
    }
    if (raw == null) {
      _doc = {'version': docVersion};
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('document is not a JSON object');
      }
      _doc = decoded;
    } catch (e) {
      debugPrint('JsonDocumentStore corrupt file: $e');
      lastWarning = 'A saved file for posts, replies and prospects was '
          'damaged, so the app started with empty lists and kept the '
          'damaged file aside instead of deleting it.';
      await io.preserveAside(fileName);
      _doc = {'version': docVersion};
    }
  }

  /// The raw list stored under [key] (empty when absent/mistyped).
  List<dynamic> listFor(String key) {
    final v = _doc[key];
    return v is List ? v : const [];
  }

  /// Replaces the list under [key] and persists the whole document.
  Future<void> saveList(String key, List<Map<String, dynamic>> items) async {
    _doc[key] = items;
    _doc['version'] = docVersion;
    try {
      await io.writeTextAtomic(fileName, jsonEncode(_doc));
    } catch (e) {
      // A failed save must not crash the feature; surface it instead.
      debugPrint('JsonDocumentStore write error: $e');
      lastWarning = 'A change to your posts, replies or prospects could '
          'not be saved on this device. It is still shown for now, but '
          'may not be there next time the app opens.';
    }
  }
}
