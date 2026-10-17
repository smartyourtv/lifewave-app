import 'dart:math' as math;

/// Emotion markup + prosody mapping (SPEC §7.3) with the voice-realism
/// rules (2026-10-17, shared voice mods — now explicit for this app):
///
/// 1. NO TWO ALIKE: every render takes a variation seed; breath and
///    emotion-sound parameters are jittered per occurrence from that seed,
///    so the same tag never produces byte-identical parameters twice.
///    On the device-TTS path the variation is pause/prosody parameters
///    (device TTS cannot synthesize a literal breath); on a future Kokoro
///    path the same varied parameters drive the render.
/// 2. BREATHS FIT THE SITUATION: breath character follows the emotion —
///    light/quick when upbeat, soft/slow for empathy/serious, breathy
///    after laughter, deeper reset breath before long explanations.
///    Breath depth scales with surrounding speech length.
/// 3. URGENT/ALERT SUPPRESSES DECORATION: in [SpeechContext.urgent] there
///    are NO decorative breaths and NO playful emotion sounds at all.
/// 4. Emotion sounds (chuckle/laugh/sigh/surprise/empathy) are generated
///    fresh in the SELECTED voice every time — as prosody + brief voiced
///    markers spoken by that voice — never a canned clip of another
///    person. Where an engine cannot render a laugh, the mapping degrades
///    to warm prosody (marker dropped) — see [ProsodyParams.canRenderMarker].

/// Emotions the answer layer may mark. Markup form: `[warm]`, `[chuckle]`,
/// `[laugh]`, `[sigh]`, `[surprise]`, `[empathy]`, plus the context tag
/// `[urgent]` (handled as a speech context, not an emotion).
enum Emotion { warm, chuckle, laugh, sigh, surprise, empathy, neutral }

/// Plain-word emotion-level setting (SPEC §7.3, Nuri dropdown pattern).
/// Scales how strongly emotions are rendered. Default: Warm.
enum EmotionLevel {
  calm('Calm', 0.3),
  gentle('Gentle', 0.6),
  warm('Warm', 1.0),
  expressive('Expressive', 1.35),
  fullHearted('Full-hearted', 1.7);

  final String label;

  /// Multiplier applied to every emotion's prosody deltas + intensity.
  final double scale;
  const EmotionLevel(this.label, this.scale);

  static EmotionLevel fromName(String? name) {
    for (final l in EmotionLevel.values) {
      if (l.name == name || l.label == name) return l;
    }
    return EmotionLevel.warm; // SPEC default
  }
}

/// Speech context. [urgent] = warnings / alerts / serious readouts:
/// decorative breaths and playful emotions are suppressed entirely.
enum SpeechContext { normal, urgent }

Emotion? emotionFromTag(String tag) {
  switch (tag.toLowerCase()) {
    case 'warm':
      return Emotion.warm;
    case 'chuckle':
      return Emotion.chuckle;
    case 'laugh':
      return Emotion.laugh;
    case 'sigh':
      return Emotion.sigh;
    case 'surprise':
      return Emotion.surprise;
    case 'empathy':
      return Emotion.empathy;
    default:
      return null;
  }
}

bool isKnownTag(String tag) =>
    emotionFromTag(tag) != null || tag.toLowerCase() == 'urgent';

/// Deterministic per-render variation source. Same seed => same variation
/// (unit-testable); different seeds => different parameters (the
/// no-two-alike rule). Seeds are derived by the voice service from the
/// utterance text + position + wall-clock, so real renders always differ.
class VariationRng {
  int _state;
  VariationRng(int seed) : _state = (seed == 0 ? 0x9E3779B9 : seed) & 0x7fffffff;

  /// Next value in [0, 1).
  double next() {
    // xorshift32 — small, deterministic, no platform randomness needed.
    var x = _state;
    x ^= (x << 13) & 0xffffffff;
    x ^= x >> 17;
    x ^= (x << 5) & 0xffffffff;
    _state = x & 0x7fffffff;
    if (_state == 0) _state = 0x2545F491;
    return _state / 2147483648.0;
  }

  /// Jitter in [-amount, +amount].
  double jitter(double amount) => (next() * 2 - 1) * amount;

  int intIn(int minIncl, int maxIncl) =>
      minIncl + (next() * (maxIncl - minIncl + 1)).floor();
}

/// A breath to render around a segment. [present] is false when the
/// situation forbids one (urgent context, or a segment too short to earn
/// a breath at low intensity).
class BreathSpec {
  final bool present;

  /// 'lightQuick' | 'softSlow' | 'breathyAfterLaugh' | 'deepReset' | 'none'
  final String character;
  final int durationMs;

  /// 0..1 — scales with surrounding speech length.
  final double depth;
  const BreathSpec({
    required this.present,
    required this.character,
    required this.durationMs,
    required this.depth,
  });
  static const BreathSpec none =
      BreathSpec(present: false, character: 'none', durationMs: 0, depth: 0);

  @override
  bool operator ==(Object other) =>
      other is BreathSpec &&
      other.present == present &&
      other.character == character &&
      other.durationMs == durationMs &&
      other.depth == depth;
  @override
  int get hashCode => Object.hash(present, character, durationMs, depth);
}

/// Fully-resolved prosody for one segment: what an engine is asked to do.
class ProsodyParams {
  final double rate; // flutter_tts speech rate (~0..1 device scale mapped by engine)
  final double pitch; // ~0.5..2.0, 1.0 = voice default
  final double volume; // 0..1
  final int pauseBeforeMs;
  final int pauseAfterMs;

  /// Brief voiced marker spoken IN THE SELECTED VOICE before the text
  /// (e.g. a chuckle's syllables). Empty when the emotion has no marker
  /// or the context/level suppresses it. Never an audio clip.
  final String marker;

  /// Whether the active engine can render [marker] at all. Device TTS
  /// can (it speaks the syllables in the chosen voice); an engine that
  /// cannot render a laugh degrades to warm prosody with marker == ''.
  final bool canRenderMarker;
  final BreathSpec breathBefore;
  final BreathSpec breathAfter;

  /// Effective emotion after context rules (urgent flattens playful
  /// emotions to neutral/warm).
  final Emotion effectiveEmotion;

  const ProsodyParams({
    required this.rate,
    required this.pitch,
    required this.volume,
    required this.pauseBeforeMs,
    required this.pauseAfterMs,
    required this.marker,
    required this.canRenderMarker,
    required this.breathBefore,
    required this.breathAfter,
    required this.effectiveEmotion,
  });

  @override
  bool operator ==(Object other) =>
      other is ProsodyParams &&
      other.rate == rate &&
      other.pitch == pitch &&
      other.volume == volume &&
      other.pauseBeforeMs == pauseBeforeMs &&
      other.pauseAfterMs == pauseAfterMs &&
      other.marker == marker &&
      other.breathBefore == breathBefore &&
      other.breathAfter == breathAfter &&
      other.effectiveEmotion == effectiveEmotion;
  @override
  int get hashCode => Object.hash(rate, pitch, volume, pauseBeforeMs,
      pauseAfterMs, marker, breathBefore, breathAfter, effectiveEmotion);
}

/// One parsed segment: clean display text + its governing emotion.
class SpeechSegment {
  final String text; // markup-free, safe to display AND to speak
  final Emotion emotion;
  const SpeechSegment(this.text, this.emotion);
}

/// Result of parsing marked-up answer text.
class ParsedSpeech {
  /// Text with ALL tags removed — the only text the UI may display.
  final String displayText;
  final List<SpeechSegment> segments;
  final SpeechContext context;
  const ParsedSpeech({
    required this.displayText,
    required this.segments,
    required this.context,
  });
}

/// Parses `[tag]` markup out of answer text. Known emotion tags switch
/// the emotion for the following text; `[urgent]` switches the whole
/// utterance to the urgent context; UNKNOWN tags are stripped from the
/// display text and otherwise ignored (never shown, never spoken).
class EmotionParser {
  static final RegExp _tagRe = RegExp(r'\[([A-Za-z]+)\]');

  static ParsedSpeech parse(String input) {
    var context = SpeechContext.normal;
    if (RegExp(r'\[urgent\]', caseSensitive: false).hasMatch(input)) {
      context = SpeechContext.urgent;
    }
    final segments = <SpeechSegment>[];
    var current = Emotion.neutral;
    var last = 0;
    final display = StringBuffer();
    void flush(String raw, Emotion emotion) {
      final clean = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (clean.isEmpty) return;
      // Merge with the previous segment when the emotion is unchanged
      // (e.g. text split only by an unknown tag) — one idea, one segment.
      if (segments.isNotEmpty && segments.last.emotion == emotion) {
        final prev = segments.removeLast();
        segments.add(SpeechSegment('${prev.text} $clean', emotion));
      } else {
        segments.add(SpeechSegment(clean, emotion));
      }
      if (display.isNotEmpty) display.write(' ');
      display.write(clean);
    }

    for (final m in _tagRe.allMatches(input)) {
      flush(input.substring(last, m.start), current);
      final tag = m.group(1)!;
      final e = emotionFromTag(tag);
      if (e != null) current = e;
      // Unknown tags: stripped (not added to display), emotion unchanged.
      last = m.end;
    }
    flush(input.substring(last), current);
    return ParsedSpeech(
      displayText: display.toString(),
      segments: List.unmodifiable(segments),
      context: context,
    );
  }
}

/// Maps (emotion, level, context, seed, text) -> prosody. Pure and
/// deterministic for a given seed — this is the unit-tested core of the
/// voice-realism rules.
class ProsodyMapper {
  const ProsodyMapper();

  ProsodyParams map({
    required Emotion emotion,
    required EmotionLevel level,
    required SpeechContext context,
    required int seed,
    required String segmentText,
    bool engineCanRenderMarker = true,
  }) {
    final rng = VariationRng(seed);
    final urgent = context == SpeechContext.urgent;
    final scale = level.scale;

    // Urgent/alert: playful emotions are flattened entirely (rule 3).
    var effective = emotion;
    if (urgent &&
        (emotion == Emotion.chuckle ||
            emotion == Emotion.laugh ||
            emotion == Emotion.surprise)) {
      effective = Emotion.neutral;
    }

    // Base deltas per emotion (before level scaling).
    double rateD = 0, pitchD = 0, volD = 0;
    var pauseBefore = 120, pauseAfter = 160;
    switch (effective) {
      case Emotion.warm:
        pitchD = 0.04;
        volD = 0.02;
        break;
      case Emotion.chuckle:
        rateD = 0.05;
        pitchD = 0.10;
        pauseAfter = 220;
        break;
      case Emotion.laugh:
        rateD = 0.07;
        pitchD = 0.14;
        pauseAfter = 300;
        break;
      case Emotion.sigh:
        rateD = -0.08;
        pitchD = -0.08;
        pauseBefore = 320;
        break;
      case Emotion.surprise:
        rateD = 0.09;
        pitchD = 0.16;
        pauseBefore = 60;
        break;
      case Emotion.empathy:
        rateD = -0.06;
        pitchD = -0.04;
        volD = -0.03;
        pauseBefore = 240;
        break;
      case Emotion.neutral:
        break;
    }

    // Voiced marker, generated fresh per render: syllable count varies
    // with the seed AND with intensity (level scale) — a small chuckle
    // for mild moments, a fuller laugh only at higher intensity.
    var marker = '';
    if (!urgent && engineCanRenderMarker) {
      final intensity = scale; // 0.3 .. 1.7
      switch (effective) {
        case Emotion.chuckle:
          final n = intensity < 0.8 ? 1 : rng.intIn(2, 2);
          marker = '${List.filled(n, 'heh').join(' ')}, ';
          break;
        case Emotion.laugh:
          // Full laugh only when intensity is genuinely high.
          final n = intensity < 0.8
              ? 2
              : intensity < 1.3
                  ? rng.intIn(2, 3)
                  : rng.intIn(3, 4);
          marker = '${List.filled(n, 'ha').join(' ')}! ';
          break;
        default:
          marker = '';
      }
    }
    final canRender = marker.isNotEmpty;

    // Breaths (rules 1+2): character follows the emotion; depth scales
    // with surrounding speech length; parameters jittered per seed.
    final len = segmentText.length;
    final depth = math.min(1.0, 0.3 + len / 400.0);
    BreathSpec breathFor({required bool before}) {
      if (urgent) return BreathSpec.none; // no decorative breaths in alerts
      // Per-render depth variation (continuous, from the seed) — texture
      // must never repeat exactly, per the no-two-alike rule.
      double variedDepth(double base) =>
          (base * (0.9 + rng.next() * 0.2)).clamp(0.1, 1.0);
      if (effective == Emotion.sigh && before) {
        // A sigh IS a shaped exhale: long, soft, varied per render.
        return BreathSpec(
          present: true,
          character: 'softSlow',
          durationMs: 380 + rng.jitter(90).round(),
          depth: variedDepth(depth * scale),
        );
      }
      if (effective == Emotion.empathy && before) {
        return BreathSpec(
          present: true,
          character: 'softSlow',
          durationMs: 300 + rng.jitter(70).round(),
          depth: variedDepth(depth * 0.8 * scale),
        );
      }
      if ((effective == Emotion.chuckle || effective == Emotion.laugh) &&
          !before) {
        return BreathSpec(
          present: true,
          character: 'breathyAfterLaugh',
          durationMs: 220 + rng.jitter(60).round(),
          depth: variedDepth(depth * 0.7),
        );
      }
      if (before && len >= 120) {
        // Deeper reset breath before a long explanation.
        return BreathSpec(
          present: true,
          character: 'deepReset',
          durationMs: 320 + rng.jitter(80).round(),
          depth: variedDepth(depth),
        );
      }
      if (before &&
          (effective == Emotion.warm || effective == Emotion.surprise)) {
        return BreathSpec(
          present: true,
          character: 'lightQuick',
          durationMs: 160 + rng.jitter(40).round(),
          depth: variedDepth(depth * 0.5),
        );
      }
      return BreathSpec.none;
    }

    final breathBefore = breathFor(before: true);
    final breathAfter = breathFor(before: false);

    // On the device-TTS path a "breath" is rendered as a varied pause —
    // the pause length absorbs the breath duration so no two renders
    // time identically. Urgent speech keeps pauses minimal and fixed-ish.
    final breathPauseBefore =
        breathBefore.present ? (breathBefore.durationMs * 0.6).round() : 0;
    final jitterAmt = urgent ? 0.0 : 1.0;

    return ProsodyParams(
      rate: (0.5 + (rateD * scale) + rng.jitter(0.012) * jitterAmt)
          .clamp(0.2, 1.0),
      pitch: (1.0 + (pitchD * scale) + rng.jitter(0.03) * jitterAmt)
          .clamp(0.5, 2.0),
      volume: (0.95 + (volD * scale)).clamp(0.5, 1.0),
      pauseBeforeMs: urgent
          ? math.min(pauseBefore, 80)
          : math.max(
              0, pauseBefore + breathPauseBefore + rng.jitter(25).round()),
      pauseAfterMs:
          urgent ? math.min(pauseAfter, 100) : math.max(0, pauseAfter + rng.jitter(30).round()),
      marker: marker,
      canRenderMarker: canRender,
      breathBefore: breathBefore,
      breathAfter: breathAfter,
      effectiveEmotion: effective,
    );
  }
}

/// Derives a variation seed for one render. Real calls mix in the wall
/// clock so repeated identical tags never render identically; tests pass
/// explicit seeds to [ProsodyMapper] instead.
int variationSeedFor({
  required String text,
  required int segmentIndex,
  int? nowMillis,
}) {
  var h = 0;
  for (final c in text.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  final t = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
  return (h ^ (t & 0x3fffffff) ^ (segmentIndex * 7919)) & 0x7fffffff;
}
