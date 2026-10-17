import '../models/entry.dart';
import '../models/social.dart';
import 'knowledge_db.dart';
import 'retrieval.dart';

/// Curiosity-post generator (SPEC §7.1) + AI reply composer (§7.2).
///
/// Composition is TEMPLATE-BASED from the playbook topic: the four
/// original template entries (play-template-*) carry fill-in patterns
/// written for this app; the generator fills their [bracketed] slots.
/// Nothing is copied from any real post, and group material is never
/// used — only the app's own playbook entries.
///
/// Playbook rule honored in code: the post itself never pitches a
/// product (play-question-led-pattern). When the user picks a product,
/// the product's OFFICIAL positioning steers which everyday topic the
/// question asks about (sleep / energy / recovery / …), and the pick is
/// recorded on the draft — the conversation, not the post, is where a
/// product is ever shared (play-funnel-steps).

/// Everyday question topics the generator can steer toward.
const List<String> kFocusTopics = [
  'sleep',
  'energy',
  'recovery',
  'performance',
  'skin',
  'wellness',
];

/// Derives a focus topic from a product's official entry text.
/// Order matters: nearly every patch entry mentions "skin" (patches
/// are worn on skin), so skin is decided by the product's NAME/line
/// first, and the everyday-life topics (sleep, recovery, performance,
/// energy) outrank a passing body mention of skin.
String focusForProduct(KnowledgeEntry product) {
  final title = product.title.toLowerCase();
  final text = '${product.title} ${product.body}'.toLowerCase();
  if (title.contains('alavida') ||
      title.contains('facial') ||
      title.contains('eye cream') ||
      title.contains('nightly restore')) {
    return 'skin';
  }
  if (text.contains('sleep') || text.contains('silent nights')) return 'sleep';
  if (text.contains('recovery')) return 'recovery';
  if (text.contains('performance') || text.contains('stamina')) {
    return 'performance';
  }
  if (text.contains('energy')) return 'energy';
  if (text.contains('skin')) return 'skin';
  return 'wellness';
}

class PostGenerator {
  final KnowledgeDb db;
  const PostGenerator(this.db);

  /// The four original templates, in playbook order.
  List<KnowledgeEntry> get templates => db
      .byTopic('playbook')
      .where((e) => e.id.startsWith('play-template-'))
      .toList();

  /// Extracts the quoted fill-in pattern from a template entry's body.
  /// Falls back to a pattern skeleton if an entry's shape ever changes
  /// (generation degrades, never crashes).
  String extractPattern(KnowledgeEntry template) {
    final start = template.body.indexOf("'");
    final end = start < 0 ? -1 : template.body.indexOf("'", start + 1);
    if (start >= 0 && end > start + 10) {
      return template.body.substring(start + 1, end).trim();
    }
    return 'Quick question — what is the ONE thing that actually helps '
        'your [sleep / energy / recovery after workouts]? I have been '
        'trying something new in my routine and I am curious what works '
        'for everyone else.';
  }

  /// Fills one [a / b / c] slot: the option matching [focus] when one
  /// matches, otherwise options rotate by [variant] so "another
  /// version" really is another version. Slots without options
  /// (e.g. [12]) are used as-is.
  String _fillSlot(String slot, String focus, int variant, int slotIndex) {
    final options = slot.split('/').map((s) => s.trim()).toList();
    if (options.length == 1) return options.single;
    for (final o in options) {
      if (o.toLowerCase().contains(focus)) return o;
    }
    return options[(variant + slotIndex) % options.length];
  }

  /// Composes an original draft from [template]. [variant] rotates the
  /// slot choices. The result is plain post text — the caller runs the
  /// compliance scanner over it before it can be queued.
  String compose({
    required KnowledgeEntry template,
    KnowledgeEntry? product,
    String? focus,
    int variant = 0,
  }) {
    final effectiveFocus =
        focus ?? (product != null ? focusForProduct(product) : 'energy');
    final pattern = extractPattern(template);
    final buffer = StringBuffer();
    var slotIndex = 0;
    var i = 0;
    while (i < pattern.length) {
      final open = pattern.indexOf('[', i);
      if (open < 0) {
        buffer.write(pattern.substring(i));
        break;
      }
      final close = pattern.indexOf(']', open);
      if (close < 0) {
        buffer.write(pattern.substring(i));
        break;
      }
      buffer.write(pattern.substring(i, open));
      buffer.write(_fillSlot(pattern.substring(open + 1, close),
          effectiveFocus, variant, slotIndex++));
      i = close + 1;
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Builds a ready-to-edit [PostDraft] (status: Draft).
  PostDraft composeDraft({
    required String id,
    required KnowledgeEntry template,
    KnowledgeEntry? product,
    String? focus,
    int variant = 0,
    PostDestination destination = PostDestination.personalProfile,
  }) {
    return PostDraft(
      id: id,
      text: compose(
          template: template, product: product, focus: focus, variant: variant),
      productId: product?.id,
      productTitle: product?.title,
      templateId: template.id,
      destination: destination,
    );
  }
}

/// AI reply composer (SPEC §7.2): brief answer from the database ->
/// invite into LW Team Learning. Draft only — the user sends it from
/// their own Facebook, on their own tap. Never a silent send.
class ReplyComposer {
  final KnowledgeDb db;
  const ReplyComposer(this.db);

  /// The LW Team Learning group link, taken from the pointer entries
  /// (the only place group links live as data — never hard-coded, so a
  /// database update moves the link with it).
  String? get teamLearningGroupLink {
    for (final e in db.byTopic('group-pointers')) {
      if (e.body.contains('LW Team Learning')) {
        final m = RegExp(r'https?://[^\s)]+').firstMatch(e.body);
        if (m != null) return m.group(0);
      }
    }
    return null;
  }

  /// The invite half of every reply, per the funnel (play-funnel-steps)
  /// and reply style (play-cadence-and-replies): brief, warm, points to
  /// the group where the teaching lives.
  String inviteText() {
    final link = teamLearningGroupLink;
    const base = 'I share what I use in our learning group, LW Team '
        'Learning — that is where the full explanations live. Want me '
        'to add you?';
    return link == null ? base : '$base You can find it here: $link';
  }

  /// First 1–2 sentences of an entry body, trimmed to a brief reply
  /// length. Long bodies never go out whole in a reply.
  static String briefExcerpt(String body, {int maxChars = 260}) {
    final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final sentences = flat.split(RegExp(r'(?<=[.!?])\s+'));
    var out = '';
    for (final s in sentences) {
      if (out.isEmpty) {
        out = s;
      } else if ('$out $s'.length <= maxChars) {
        out = '$out $s';
      } else {
        break;
      }
      if (out.length >= 120) break;
    }
    if (out.length > maxChars) out = '${out.substring(0, maxChars - 1)}…';
    return out;
  }

  /// Drafts a reply to [incomingText]: retrieval over faq first (the
  /// common-question path), then the whole database; the draft is the
  /// brief answer + the group invite. With no grounded match, the draft
  /// is an honest "let me check" + invite — never an invented answer.
  String composeReply(String incomingText) {
    final retrieval = Retrieval(db.entries);
    KnowledgeEntry? best;
    // Prefer FAQ entries: they are written as answers already.
    final faqHits = Retrieval(db.byTopic('faq'))
        .search(incomingText, limit: 1);
    if (faqHits.isNotEmpty) {
      best = faqHits.first.entry;
    } else {
      final hits = retrieval.search(incomingText, limit: 1);
      if (hits.isNotEmpty && !hits.first.entry.isPointer) {
        best = hits.first.entry;
      }
    }
    final invite = inviteText();
    if (best == null) {
      return 'Thanks so much for asking! I want to give you the right '
          'information, so let me check on that for you. $invite';
    }
    return '${briefExcerpt(best.body)} $invite';
  }
}
