import '../models/entry.dart';

/// Cloud escalation — INTERFACE / STUB ONLY (M1).
///
/// Per SPEC §7.7 + PRE-BUILD-AUDIT §4, the cloud tier (when it lands in a
/// later milestone) answers grounded in retrieved entries, preserves claim
/// labels, and sends only the question + public DB entries. M1 defines the
/// interface so chat code never grows a second, ad-hoc network path.
///
/// STUB: [NotConfiguredCloudEscalation] makes NO network calls and there
/// are NO embedded API keys anywhere in this app (audit red flag if that
/// ever changes). It simply reports that cloud help is not set up.
abstract class CloudEscalation {
  Future<CloudEscalationResult> escalate({
    required String question,
    required List<KnowledgeEntry> retrievedEntries,
  });

  bool get isConfigured;
}

class CloudEscalationResult {
  /// True when a real cloud tier produced [answerText].
  final bool answered;

  /// The answer text, or a plain-language explanation of why there is none.
  final String message;
  const CloudEscalationResult({required this.answered, required this.message});
}

/// M1 implementation: cloud help is not set up on this device yet.
class NotConfiguredCloudEscalation implements CloudEscalation {
  const NotConfiguredCloudEscalation();

  @override
  bool get isConfigured => false;

  @override
  Future<CloudEscalationResult> escalate({
    required String question,
    required List<KnowledgeEntry> retrievedEntries,
  }) async {
    // STUB — no network call is made here, by design.
    return const CloudEscalationResult(
      answered: false,
      message: "Cloud help isn't set up on this device yet. For now, "
          'answers come only from the built-in database.',
    );
  }
}
