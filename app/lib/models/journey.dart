// M4 customer-journey models (SPEC §7.8 item 5 + §7.9 check-ins).
//
// All of this is the USER's own data, created on their device, stored
// on-device only, never synced or shared (owner-neutral design,
// SPEC §1/§4). The private journal is exactly that: private notes the
// user writes for themselves. Nothing here is a medical claim or a
// protocol — placement guidance is a POINTER to the learning groups
// (§3/§4), never content.

String _iso(DateTime? dt) => dt?.toIso8601String() ?? '';
DateTime? _parseIso(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

/// One private journal note for one customer on one day. Stored ONLY
/// on-device (the Journey screen says so in plain words).
class JournalEntry {
  final String id;
  final String customerId;

  /// The journey day this note belongs to (1-based: day 1 = start date).
  final int day;
  String text;
  final DateTime createdAt;

  JournalEntry({
    required this.id,
    required this.customerId,
    required this.day,
    required this.text,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'customerId': customerId,
        'day': day,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
      };

  static JournalEntry? tryDecode(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['id'];
    final customerId = raw['customerId'];
    final day = raw['day'];
    final text = raw['text'];
    if (id is! String ||
        id.isEmpty ||
        customerId is! String ||
        customerId.isEmpty ||
        day is! int ||
        text is! String) {
      return null;
    }
    return JournalEntry(
      id: id,
      customerId: customerId,
      day: day,
      text: text,
      createdAt: _parseIso(raw['createdAt']) ?? DateTime.now(),
    );
  }
}

/// One customer on the 30-day journey.
class Customer {
  final String id;
  String name;

  /// Product entry id + title the customer started with (display only —
  /// the journey never prescribes anything).
  final String? productId;
  String productTitle;

  /// The day they started. Day 1 = this date (date-level math).
  DateTime startDate;

  /// Milestone days whose check-in draft was handed off (share sheet /
  /// copy) — recorded honestly as "handed off", never "sent".
  final Set<int> checkInsHandedOff;

  /// Milestone days the user marked done.
  final Set<int> checkInsDone;

  /// True once the user marks that this customer reordered — the
  /// day-25 reorder nudge clears.
  bool reordered;
  DateTime? reorderedAt;

  final List<JournalEntry> journal;
  final DateTime createdAt;

  Customer({
    required this.id,
    required this.name,
    this.productId,
    this.productTitle = '',
    required this.startDate,
    Set<int>? checkInsHandedOff,
    Set<int>? checkInsDone,
    this.reordered = false,
    this.reorderedAt,
    List<JournalEntry>? journal,
    DateTime? createdAt,
  })  : checkInsHandedOff = checkInsHandedOff ?? <int>{},
        checkInsDone = checkInsDone ?? <int>{},
        journal = journal ?? <JournalEntry>[],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'productId': productId,
        'productTitle': productTitle,
        'startDate': startDate.toIso8601String(),
        'checkInsHandedOff': checkInsHandedOff.toList()..sort(),
        'checkInsDone': checkInsDone.toList()..sort(),
        'reordered': reordered,
        'reorderedAt': _iso(reorderedAt),
        'journal': journal.map((j) => j.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  static Customer? tryDecode(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['id'];
    final name = raw['name'];
    final start = _parseIso(raw['startDate']);
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      return null;
    }
    if (start == null) return null;
    Set<int> intSet(Object? v) =>
        v is List ? v.whereType<int>().toSet() : <int>{};
    return Customer(
      id: id,
      name: name,
      productId: raw['productId'] is String ? raw['productId'] as String : null,
      productTitle:
          raw['productTitle'] is String ? raw['productTitle'] as String : '',
      startDate: start,
      checkInsHandedOff: intSet(raw['checkInsHandedOff']),
      checkInsDone: intSet(raw['checkInsDone']),
      reordered: raw['reordered'] == true,
      reorderedAt: _parseIso(raw['reorderedAt']),
      journal: (raw['journal'] is List)
          ? (raw['journal'] as List)
              .map(JournalEntry.tryDecode)
              .whereType<JournalEntry>()
              .toList()
          : [],
      createdAt: _parseIso(raw['createdAt']) ?? DateTime.now(),
    );
  }
}
