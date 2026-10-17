/// One knowledge-database entry (SPEC §5 schema).
///
/// Decoding is CHECKED (PRE-BUILD-AUDIT §2): required fields missing or
/// mistyped => the entry is malformed and must be skipped + counted by the
/// caller, never partially rendered. Optional product fields missing =>
/// null, and the UI renders "not listed" — never an invented value.
class KnowledgeEntry {
  final String id;
  final String topic;
  final String title;
  final String body;
  final String audience;
  final String sourceType;
  final String sourceRef;

  /// Exactly "official fact" or "distributor claim" in shipped data.
  /// Kept as the raw string so the label always travels with the entry.
  final String claimLabel;
  final String updated;

  // Optional product fields (products topic only).
  final String? itemCode;
  final double? priceRetailUsd;
  final double? priceSubscribeUsd;
  final String? category;

  const KnowledgeEntry({
    required this.id,
    required this.topic,
    required this.title,
    required this.body,
    required this.audience,
    required this.sourceType,
    required this.sourceRef,
    required this.claimLabel,
    required this.updated,
    this.itemCode,
    this.priceRetailUsd,
    this.priceSubscribeUsd,
    this.category,
  });

  bool get isPointer => topic == 'group-pointers';

  /// Short chip text for the claim label. The full label stays visible;
  /// this only capitalizes for display ("Official fact" / "Distributor claim").
  String get claimChipText {
    if (claimLabel.isEmpty) return claimLabel;
    return claimLabel[0].toUpperCase() + claimLabel.substring(1);
  }

  static String? _reqString(Map<String, dynamic> json, String key) {
    final v = json[key];
    if (v is String && v.trim().isNotEmpty) return v;
    return null;
  }

  static double? _optPrice(Map<String, dynamic> json, String key) {
    final v = json[key];
    if (v is num) return v.toDouble();
    return null; // missing or mistyped optional price => "not listed"
  }

  static String? _optString(Map<String, dynamic> json, String key) {
    final v = json[key];
    if (v is String && v.trim().isNotEmpty) return v;
    return null;
  }

  /// Returns null when the entry is malformed (any required field missing
  /// or mistyped). The caller counts nulls as skipped-malformed.
  static KnowledgeEntry? tryDecode(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = _reqString(raw, 'id');
    final topic = _reqString(raw, 'topic');
    final title = _reqString(raw, 'title');
    final body = _reqString(raw, 'body');
    final audience = _reqString(raw, 'audience');
    final sourceType = _reqString(raw, 'source_type');
    final sourceRef = _reqString(raw, 'source_ref');
    final claimLabel = _reqString(raw, 'claim_label');
    final updated = _reqString(raw, 'updated');
    if (id == null ||
        topic == null ||
        title == null ||
        body == null ||
        audience == null ||
        sourceType == null ||
        sourceRef == null ||
        claimLabel == null ||
        updated == null) {
      return null;
    }
    return KnowledgeEntry(
      id: id,
      topic: topic,
      title: title,
      body: body,
      audience: audience,
      sourceType: sourceType,
      sourceRef: sourceRef,
      claimLabel: claimLabel,
      updated: updated,
      itemCode: _optString(raw, 'item_code'),
      priceRetailUsd: _optPrice(raw, 'price_retail_usd'),
      priceSubscribeUsd: _optPrice(raw, 'price_subscribe_usd'),
      category: _optString(raw, 'category'),
    );
  }
}
