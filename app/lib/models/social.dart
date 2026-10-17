// M3 social data models (SPEC §7.1, §7.2, §7.9).
//
// All of this data is the USER's own, created on their device, stored
// on-device only, and never synced anywhere (owner-neutral design,
// SPEC §1/§4). Nothing here represents a send: the honesty rule
// (SPEC §7.11) forbids any state that claims a post was "posted" —
// v1 has NO account connection, so the most that can ever happen is a
// reminder firing and a handoff to the system share sheet / clipboard.

/// Where a post is headed. The distinction is preserved in the data
/// model + UI copy on purpose: a future release can add each user's
/// OWN account connection and implement TRUE scheduled publishing for
/// Facebook Pages (the only destination Meta allows apps to schedule)
/// without reworking the queue. Personal profiles can never be
/// scheduled by an app — they always resolve to reminder + handoff.
enum PostDestination {
  facebookPage('Facebook Page'),
  personalProfile('Personal profile');

  final String label;
  const PostDestination(this.label);

  static PostDestination fromName(String? name) =>
      PostDestination.values.firstWhere(
        (d) => d.name == name,
        orElse: () => PostDestination.personalProfile,
      );
}

/// Post lifecycle: Draft -> Approved -> Queued (reminder set) ->
/// Handed off / Copied. Cancelled is reachable from any live state.
/// There is deliberately NO "posted" state (SPEC §7.11 honesty rule).
enum PostStatus {
  draft,
  approved,
  queued,
  handedOff,
  copied,
  cancelled;

  /// The exact words the UI shows for this state. These must say what
  /// ACTUALLY happened — never "Posted".
  String label({DateTime? scheduledFor}) {
    switch (this) {
      case PostStatus.draft:
        return 'Draft';
      case PostStatus.approved:
        return 'Approved';
      case PostStatus.queued:
        return scheduledFor == null
            ? 'Queued'
            : 'Reminder set for ${formatWhen(scheduledFor)}';
      case PostStatus.handedOff:
        return 'Handed off (share sheet opened)';
      case PostStatus.copied:
        return 'Copied';
      case PostStatus.cancelled:
        return 'Cancelled';
    }
  }

  static PostStatus fromName(String? name) => PostStatus.values.firstWhere(
        (s) => s.name == name,
        orElse: () => PostStatus.draft,
      );
}

/// "Oct 20, 2026 at 9:00 AM" — plain, unambiguous, no weekday guessing.
String formatWhen(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hour12 = dt.hour == 0
      ? 12
      : dt.hour > 12
          ? dt.hour - 12
          : dt.hour;
  final ampm = dt.hour < 12 ? 'AM' : 'PM';
  final minute = dt.minute.toString().padLeft(2, '0');
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $hour12:$minute $ampm';
}

String _iso(DateTime? dt) => dt?.toIso8601String() ?? '';
DateTime? _parseIso(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

/// One curiosity-post draft and its queue state.
class PostDraft {
  final String id;
  String text;

  /// The product the user picked to steer the topic (playbook rule: the
  /// product itself is NOT pitched in the post — see PostGenerator).
  final String? productId;
  final String? productTitle;

  /// The playbook template entry id this draft was composed from.
  final String? templateId;

  PostDestination destination;
  PostStatus status;
  DateTime? scheduledFor;

  /// Compliance override record: true only when the user saw the flags
  /// and explicitly acknowledged them. The flagged phrases at override
  /// time are kept here so the acknowledgment is auditable on-device.
  bool complianceOverride;
  List<String> overrideAcknowledgedFlags;

  /// Cross-posting handoffs (M4, SPEC §7.8 item 8): platform name ->
  /// honest handoff label ("Opened share sheet for Instagram at …").
  /// A record exists only after a share sheet was actually opened for
  /// that platform's formatted variant. Never a "posted" record.
  Map<String, String> platformHandoffs;

  final DateTime createdAt;
  DateTime updatedAt;

  PostDraft({
    required this.id,
    required this.text,
    this.productId,
    this.productTitle,
    this.templateId,
    this.destination = PostDestination.personalProfile,
    this.status = PostStatus.draft,
    this.scheduledFor,
    this.complianceOverride = false,
    List<String>? overrideAcknowledgedFlags,
    Map<String, String>? platformHandoffs,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : overrideAcknowledgedFlags = overrideAcknowledgedFlags ?? [],
        platformHandoffs = platformHandoffs ?? {},
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Stable positive int used as the OS notification id.
  int get reminderId => id.hashCode.abs() % 900000 + 1000;

  bool get isLive =>
      status != PostStatus.cancelled && status != PostStatus.draft;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'productId': productId,
        'productTitle': productTitle,
        'templateId': templateId,
        'destination': destination.name,
        'status': status.name,
        'scheduledFor': _iso(scheduledFor),
        'complianceOverride': complianceOverride,
        'overrideAcknowledgedFlags': overrideAcknowledgedFlags,
        'platformHandoffs': platformHandoffs,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static PostDraft? tryDecode(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['id'];
    final text = raw['text'];
    if (id is! String || id.isEmpty || text is! String) return null;
    return PostDraft(
      id: id,
      text: text,
      productId: raw['productId'] is String ? raw['productId'] as String : null,
      productTitle:
          raw['productTitle'] is String ? raw['productTitle'] as String : null,
      templateId:
          raw['templateId'] is String ? raw['templateId'] as String : null,
      destination: PostDestination.fromName(raw['destination'] as String?),
      status: PostStatus.fromName(raw['status'] as String?),
      scheduledFor: _parseIso(raw['scheduledFor']),
      complianceOverride: raw['complianceOverride'] == true,
      overrideAcknowledgedFlags: (raw['overrideAcknowledgedFlags'] is List)
          ? (raw['overrideAcknowledgedFlags'] as List)
              .whereType<String>()
              .toList()
          : [],
      platformHandoffs: (raw['platformHandoffs'] is Map)
          ? (raw['platformHandoffs'] as Map).map(
              (k, v) => MapEntry('$k', v is String ? v : '$v'))
          : {},
      createdAt: _parseIso(raw['createdAt']) ?? DateTime.now(),
      updatedAt: _parseIso(raw['updatedAt']) ?? DateTime.now(),
    );
  }
}

enum ReplyStatus { waiting, handled, dismissed }

/// One AI-assisted reply draft (SPEC §7.2). The user sends it from their
/// own Facebook — the app only drafts, copies, or hands off.
class ReplyDraft {
  final String id;
  final String incomingText;
  String draftText;

  /// Language code the FINAL draft text is in (compliance is scanned on
  /// the final-language text, SPEC §7.4).
  String languageCode;
  ReplyStatus status;
  bool complianceOverride;
  List<String> overrideAcknowledgedFlags;
  final DateTime createdAt;

  ReplyDraft({
    required this.id,
    required this.incomingText,
    required this.draftText,
    this.languageCode = 'en',
    this.status = ReplyStatus.waiting,
    this.complianceOverride = false,
    List<String>? overrideAcknowledgedFlags,
    DateTime? createdAt,
  })  : overrideAcknowledgedFlags = overrideAcknowledgedFlags ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'incomingText': incomingText,
        'draftText': draftText,
        'languageCode': languageCode,
        'status': status.name,
        'complianceOverride': complianceOverride,
        'overrideAcknowledgedFlags': overrideAcknowledgedFlags,
        'createdAt': createdAt.toIso8601String(),
      };

  static ReplyDraft? tryDecode(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['id'];
    final incoming = raw['incomingText'];
    final draft = raw['draftText'];
    if (id is! String || id.isEmpty || incoming is! String || draft is! String) {
      return null;
    }
    return ReplyDraft(
      id: id,
      incomingText: incoming,
      draftText: draft,
      languageCode:
          raw['languageCode'] is String ? raw['languageCode'] as String : 'en',
      status: ReplyStatus.values.firstWhere(
        (s) => s.name == raw['status'],
        orElse: () => ReplyStatus.waiting,
      ),
      complianceOverride: raw['complianceOverride'] == true,
      overrideAcknowledgedFlags: (raw['overrideAcknowledgedFlags'] is List)
          ? (raw['overrideAcknowledgedFlags'] as List)
              .whereType<String>()
              .toList()
          : [],
      createdAt: _parseIso(raw['createdAt']) ?? DateTime.now(),
    );
  }
}

/// Pipeline stages (SPEC §7.9): comment -> invited -> joined -> customer.
enum ProspectStage {
  commented('Commented'),
  invited('Invited'),
  joinedGroup('Joined group'),
  customer('Customer');

  final String label;
  const ProspectStage(this.label);

  ProspectStage? get next =>
      index + 1 < ProspectStage.values.length
          ? ProspectStage.values[index + 1]
          : null;

  static ProspectStage fromName(String? name) =>
      ProspectStage.values.firstWhere(
        (s) => s.name == name,
        orElse: () => ProspectStage.commented,
      );
}

class Prospect {
  final String id;
  String name;
  String note;
  ProspectStage stage;
  DateTime? followUpDate;
  final DateTime createdAt;

  Prospect({
    required this.id,
    required this.name,
    this.note = '',
    this.stage = ProspectStage.commented,
    this.followUpDate,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Due = a follow-up date set for today or earlier (date-level).
  bool isDueOn(DateTime day) {
    final f = followUpDate;
    if (f == null) return false;
    final fDay = DateTime(f.year, f.month, f.day);
    final dDay = DateTime(day.year, day.month, day.day);
    return !fDay.isAfter(dDay);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'note': note,
        'stage': stage.name,
        'followUpDate': _iso(followUpDate),
        'createdAt': createdAt.toIso8601String(),
      };

  static Prospect? tryDecode(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      return null;
    }
    return Prospect(
      id: id,
      name: name,
      note: raw['note'] is String ? raw['note'] as String : '',
      stage: ProspectStage.fromName(raw['stage'] as String?),
      followUpDate: _parseIso(raw['followUpDate']),
      createdAt: _parseIso(raw['createdAt']) ?? DateTime.now(),
    );
  }
}

/// A user pre-approved quick-reply template (SPEC §7.2 fastest path —
/// still only ever sent by the user's own tap).
class QuickReplyTemplate {
  final String id;
  String title;
  String text;
  bool approved;
  QuickReplyTemplate({
    required this.id,
    required this.title,
    required this.text,
    this.approved = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'text': text,
        'approved': approved,
      };

  static QuickReplyTemplate? tryDecode(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['id'];
    final title = raw['title'];
    final text = raw['text'];
    if (id is! String || id.isEmpty || title is! String || text is! String) {
      return null;
    }
    return QuickReplyTemplate(
      id: id,
      title: title,
      text: text,
      approved: raw['approved'] == true,
    );
  }
}

/// The real Today-card counts (SPEC §7.8 item 7). Since M4 the
/// reorders count is REAL too: customers on day >= 25 of their journey
/// who have not been marked reordered (services/journey.dart).
class TodayCounts {
  final int repliesWaiting;
  final int postsScheduled;
  final int followUpsDue;
  final int reordersDue;
  const TodayCounts({
    required this.repliesWaiting,
    required this.postsScheduled,
    required this.followUpsDue,
    this.reordersDue = 0,
  });
  static const zero = TodayCounts(
      repliesWaiting: 0, postsScheduled: 0, followUpsDue: 0, reordersDue: 0);
}
