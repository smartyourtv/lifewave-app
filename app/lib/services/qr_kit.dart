import '../models/entry.dart';
import '../theme.dart';

/// My QR kit (SPEC §7.8 item 6): the user's OWN referral link -> a QR
/// code + a printable one-pager.
///
/// Owner-neutrality: the link is the user's own data, entered by them
/// in Settings and stored on their device only — nothing is baked
/// into the app (SPEC §7.12 / §4).

/// Validates a referral link: must be a well-formed http/https URL
/// with a host. Returns a plain-language problem, or null when valid.
String? referralLinkProblem(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return 'Paste your referral link first.';
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme) {
    return 'That does not look like a web link. It should start with '
        'https:// — copy it exactly from your LifeWave store page.';
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return 'The link must start with http:// or https://.';
  }
  if (uri.host.isEmpty || !uri.host.contains('.')) {
    return 'That link is missing the website name — copy the full '
        'link from your LifeWave store page.';
  }
  return null;
}

bool isValidReferralLink(String raw) => referralLinkProblem(raw) == null;

/// The one-pager model: everything the printable sheet shows. The
/// screen renders exactly this — tests assert the link and the
/// independent-tool line are in it.
class QrOnePager {
  final String displayName; // '' when the user has not set a name
  final String referralLink;
  final String? logoAssetPath;

  /// A short official-fact blurb from the company topic.
  final String companyBlurb;

  /// The independent-tool line, printed small at the bottom.
  static const String disclaimerLine = AppInfo.independentToolLine;

  const QrOnePager({
    required this.displayName,
    required this.referralLink,
    required this.logoAssetPath,
    required this.companyBlurb,
  });

  /// All text on the sheet (for tests and the share caption).
  String get allText => [
        if (displayName.isNotEmpty) displayName,
        referralLink,
        companyBlurb,
        disclaimerLine,
      ].join('\n');
}

/// A short official-fact blurb for the one-pager: the first
/// substantive sentence of the company-story entry, verbatim from the
/// database (never invented copy).
String companyBlurbFrom(KnowledgeEntry? storyEntry) {
  if (storyEntry == null) {
    return 'LifeWave is a health and wellness company founded in 2004.';
  }
  final flat = storyEntry.body.replaceAll(RegExp(r'\s+'), ' ').trim();
  final first = flat.split(RegExp(r'(?<=[.!?])\s+')).first;
  return first;
}
