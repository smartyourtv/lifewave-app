import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Share-sheet handoff seam (share_plus PINNED 10.1.4 — the
/// PRE-BUILD-AUDIT §6 resolution for the pinned Flutter 3.24.5).
///
/// Honesty rule (SPEC §7.11 + audit §3): a completed share call means
/// "handed to the target app", NEVER "posted". Callers label states
/// accordingly (Handed off / Copied).
abstract class ShareGateway {
  /// Opens the system share sheet with [text]. Returns true when the
  /// sheet was opened (the handoff happened) — not that anything was
  /// posted anywhere.
  Future<bool> shareText(String text);

  /// Opens the share sheet for a file (fact-card PNG). Same honesty
  /// contract as [shareText]; the sheet is also how a user saves the
  /// file (Files / Drive / Photos targets appear there).
  Future<bool> shareFile(String filePath, {String? text});

  /// Writes bytes to a shareable temp file and returns its path.
  Future<String> writeTempFile(String fileName, List<int> bytes);
}

class SharePlusGateway implements ShareGateway {
  @override
  Future<bool> shareText(String text) async {
    try {
      final result = await Share.share(text);
      // dismissed still means the sheet opened and the user chose —
      // the handoff happened; unavailable means it never opened.
      return result.status != ShareResultStatus.unavailable;
    } catch (e) {
      debugPrint('Share text failed: $e');
      return false;
    }
  }

  @override
  Future<bool> shareFile(String filePath, {String? text}) async {
    try {
      final result = await Share.shareXFiles(
        [XFile(filePath)],
        text: text,
      );
      return result.status != ShareResultStatus.unavailable;
    } catch (e) {
      debugPrint('Share file failed: $e');
      return false;
    }
  }

  @override
  Future<String> writeTempFile(String fileName, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$fileName');
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }
}

/// Test gateway: records what would have been handed off.
class FakeShareGateway implements ShareGateway {
  final List<String> sharedTexts = [];
  final List<String> sharedFiles = [];
  final Map<String, List<int>> tempFiles = {};
  bool succeed = true;

  @override
  Future<bool> shareText(String text) async {
    if (succeed) sharedTexts.add(text);
    return succeed;
  }

  @override
  Future<bool> shareFile(String filePath, {String? text}) async {
    if (succeed) sharedFiles.add(filePath);
    return succeed;
  }

  @override
  Future<String> writeTempFile(String fileName, List<int> bytes) async {
    tempFiles[fileName] = bytes;
    return '/fake-tmp/$fileName';
  }
}
