import 'compliance.dart';

/// Cross-posting formatter (SPEC §7.8 item 8).
///
/// One approved curiosity post, formatted per platform. The formatting
/// is REAL — the text actually differs per platform:
///  - Facebook: the post as composed.
///  - Instagram: captions cannot rely on bare links, so any link in
///    the text is pulled out and replaced by a "link in bio" line;
///    hashtags are grouped together at the end.
///  - Threads: tighter length guidance — the variant carries a
///    character count and a plain note when it runs long.
///
/// Every variant is compliance-scanned on its OWN final text (SPEC
/// §7.4/§7.9), and every handoff label is honest: "opened share sheet",
/// never "posted to …" (SPEC §7.11).
enum SharePlatform {
  facebook('Facebook'),
  instagram('Instagram'),
  threads('Threads');

  final String label;
  const SharePlatform(this.label);

  static SharePlatform fromName(String? name) => SharePlatform.values
      .firstWhere((p) => p.name == name, orElse: () => SharePlatform.facebook);
}

/// Threads' comfortable post length used for the guidance note.
const int kThreadsGuidanceChars = 500;

class PlatformVariant {
  final SharePlatform platform;
  final String text;

  /// Compliance scan of THIS variant's final text.
  final ComplianceReport report;

  /// Character count (shown for Threads guidance; useful everywhere).
  final int charCount;

  /// Plain guidance note ('' when none) — e.g. Threads length advice.
  final String guidance;

  const PlatformVariant({
    required this.platform,
    required this.text,
    required this.report,
    required this.charCount,
    required this.guidance,
  });
}

final RegExp _urlRe = RegExp(r'https?://[^\s)]+');
final RegExp _hashtagRe = RegExp(r'#\w+');

class CrossPostFormatter {
  final ComplianceScanner _scanner;
  const CrossPostFormatter({ComplianceScanner scanner = const ComplianceScanner()})
      : _scanner = scanner;

  PlatformVariant format(SharePlatform platform, String sourceText) {
    switch (platform) {
      case SharePlatform.facebook:
        return _variant(platform, sourceText.trim(), '');
      case SharePlatform.instagram:
        return _variant(platform, _instagram(sourceText), '');
      case SharePlatform.threads:
        final text = sourceText.trim();
        final guidance = text.length > kThreadsGuidanceChars
            ? 'This is ${text.length} characters — Threads works best '
                'at $kThreadsGuidanceChars or fewer. Consider trimming '
                'before you share it.'
            : 'Length looks good for Threads '
                '(${text.length} of $kThreadsGuidanceChars characters).';
        return _variant(platform, text, guidance);
    }
  }

  List<PlatformVariant> formatAll(String sourceText) =>
      SharePlatform.values.map((p) => format(p, sourceText)).toList();

  PlatformVariant _variant(
      SharePlatform platform, String text, String guidance) {
    return PlatformVariant(
      platform: platform,
      text: text,
      report: _scanner.scan(text),
      charCount: text.length,
      guidance: guidance,
    );
  }

  /// Instagram variant: links move to a "link in bio" line (captions
  /// are not link-driven), hashtags group at the end.
  String _instagram(String source) {
    var text = source.trim();
    final hadLink = _urlRe.hasMatch(text);
    text = text.replaceAll(_urlRe, '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final tags = _hashtagRe.allMatches(text).map((m) => m.group(0)!).toList();
    if (tags.isNotEmpty) {
      text = text.replaceAll(_hashtagRe, '').replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    final parts = <String>[text];
    if (hadLink) {
      parts.add('🔗 Link in bio — that is where my link lives.');
    }
    if (tags.isNotEmpty) {
      parts.add(tags.join(' '));
    }
    return parts.where((p) => p.isNotEmpty).join('\n\n');
  }
}

/// The honest handoff label recorded on a draft, e.g.
/// "Opened share sheet for Instagram at Oct 17, 2026 at 2:05 PM".
/// It NEVER says "posted" (SPEC §7.11).
String platformHandoffLabel(SharePlatform platform, DateTime when) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hour12 = when.hour == 0
      ? 12
      : when.hour > 12
          ? when.hour - 12
          : when.hour;
  final ampm = when.hour < 12 ? 'AM' : 'PM';
  final minute = when.minute.toString().padLeft(2, '0');
  return 'Opened share sheet for ${platform.label} at '
      '${months[when.month - 1]} ${when.day}, ${when.year} at '
      '$hour12:$minute $ampm';
}
