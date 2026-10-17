import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../services/brand_assets.dart';
import '../services/emotion.dart';
import '../services/guide_content.dart';
import '../services/knowledge_db.dart';
import '../services/m2_services.dart';
import '../services/retrieval.dart';
import '../services/social_store.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'guide_screen.dart';

class _TestState {
  final String name;
  final String description;
  bool? passed; // null = not run yet
  String detail = '';
  _TestState(this.name, this.description);
}

/// Diagnostics — the standing-rule health card. One screen, plain words,
/// screenshot-friendly: versions, counts, and one-tap self-tests that
/// actually run. This is how "it's not working" becomes a screenshot.
class DiagnosticsScreen extends StatefulWidget {
  final KnowledgeDb db;
  final BrandAssets brand;
  final M2Services? services;
  final EmotionLevel emotionLevel;
  final VoiceInfo? selectedVoice;
  final SocialStore? socialStore;

  /// M4 states: first-run tour seen, QR referral link set.
  final bool? tourSeen;
  final bool? referralLinkSet;

  /// M5: honest last update-check result label (from UpdateService).
  final String? updateStatusLabel;
  const DiagnosticsScreen({
    super.key,
    required this.db,
    required this.brand,
    this.services,
    this.emotionLevel = EmotionLevel.warm,
    this.selectedVoice,
    this.socialStore,
    this.tourSeen,
    this.referralLinkSet,
    this.updateStatusLabel,
  });

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

/// One emotion self-test: a fixed sample line spoken with that emotion
/// in the selected voice (SPEC §7.3 diagnostics rule).
class _EmotionSample {
  final String label;
  final String markedLine;
  const _EmotionSample(this.label, this.markedLine);
}

const List<_EmotionSample> _emotionSamples = [
  _EmotionSample('Warm',
      '[warm] Hello! It is lovely to meet you. Let me help you find what you need.'),
  _EmotionSample('Chuckle', '[chuckle] That is a fun way to look at it.'),
  _EmotionSample('Laugh', '[laugh] That really is funny — thank you for sharing it.'),
  _EmotionSample('Sigh', '[sigh] Some days are harder than others, and that is okay.'),
  _EmotionSample('Surprise', '[surprise] Oh — that is wonderful news!'),
  _EmotionSample('Empathy',
      '[empathy] I hear you. Let us take this one step at a time, together.'),
];

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  int? _brandBytes;
  bool _running = false;
  String? _micPermission;
  String _renderedBy = '';
  late final List<_TestState> _tests = [
    _TestState('Database load test',
        'Loads the built-in database again and counts its entries.'),
    _TestState('Search smoke test',
        'Searches for "X39" — the X39 product must come back first.'),
    _TestState('Picture load test',
        'Opens the LifeWave logo and one product picture to check they load.'),
  ];

  @override
  void initState() {
    super.initState();
    widget.brand.totalBytes().then((b) {
      if (mounted) setState(() => _brandBytes = b);
    });
    final services = widget.services;
    if (services != null) {
      services.voice.kokoroEngine.modelManager.refresh().then((_) {
        if (mounted) setState(() {});
      });
      services.translation.loadBookkeeping().then((_) {
        if (mounted) setState(() {});
      });
      services.speechInput.micPermissionLabel().then((label) {
        if (mounted) setState(() => _micPermission = label);
      });
    }
  }

  Future<void> _speakSample(_EmotionSample sample) async {
    final services = widget.services;
    if (services == null) return;
    final result = await services.voice.speak(
      sample.markedLine,
      level: widget.emotionLevel,
      voice: widget.selectedVoice,
    );
    if (!mounted) return;
    setState(() => _renderedBy = result.spoken
        ? '${sample.label} — spoken by ${result.renderedBy} '
            'with feeling set to ${widget.emotionLevel.label}.'
        : '${sample.label} — ${result.message}');
  }

  Future<void> _runTests() async {
    setState(() {
      _running = true;
      for (final t in _tests) {
        t.passed = null;
        t.detail = '';
      }
    });

    // (a) Database load test — a fresh full load from the bundled assets.
    try {
      final fresh = await KnowledgeDb.load();
      _tests[0].passed = fresh.entryCount > 0 &&
          fresh.dbVersion == widget.db.dbVersion;
      _tests[0].detail =
          'Loaded ${fresh.entryCount} entries, database version ${fresh.dbVersion}.';
    } catch (e) {
      _tests[0].passed = false;
      _tests[0].detail = 'Could not load the database: $e';
    }

    // (b) Search smoke test — fixed query "X39" must return prod-x39 first.
    try {
      final results = Retrieval(widget.db.entries).search('X39');
      final firstId = results.isEmpty ? '(no results)' : results.first.entry.id;
      _tests[1].passed = results.isNotEmpty && firstId == 'prod-x39';
      _tests[1].detail = results.isEmpty
          ? 'No results came back for "X39".'
          : 'First result: ${results.first.entry.title} ($firstId).';
    } catch (e) {
      _tests[1].passed = false;
      _tests[1].detail = 'Search failed: $e';
    }

    // (c) Asset load test — logo bytes + one product image must decode.
    try {
      final logoPath = widget.brand.logoAssetPath;
      if (logoPath == null) {
        throw Exception('logo is missing from the brand map');
      }
      final logoBytes = await rootBundle.load(logoPath);
      final logoText = String.fromCharCodes(
          logoBytes.buffer.asUint8List(0, 200.clamp(0, logoBytes.lengthInBytes)));
      if (!logoText.contains('<svg')) {
        throw Exception('logo file did not look like the logo artwork');
      }
      final imgPath = widget.brand.productImageFor('prod-x39');
      if (imgPath == null) {
        throw Exception('the X39 product picture is missing');
      }
      final imgBytes = await rootBundle.load(imgPath);
      final codec = await ui.instantiateImageCodec(
          imgBytes.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      final ok = w > 0 && h > 0;
      frame.image.dispose();
      _tests[2].passed = ok;
      _tests[2].detail =
          'Logo loaded (${logoBytes.lengthInBytes} bytes) and the X39 picture opened ($w×$h).';
    } catch (e) {
      _tests[2].passed = false;
      _tests[2].detail = 'A picture could not be loaded: $e';
    }

    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics'), actions: [HelpButton(screenKey: 'diagnostics', brand: widget.brand, services: widget.services, db: widget.db, share: null, emotionLevel: widget.emotionLevel)],),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: LogoImage(assetPath: widget.brand.logoAssetPath, height: 32)),
          const SizedBox(height: 8),
          const Text(
            'If something is not working, take a screenshot of this screen '
            'and send it to whoever helps you with the app.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('App health',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Divider(),
                  const _InfoRow('App version', AppInfo.versionLabel),
                  _InfoRow('Update check',
                      widget.updateStatusLabel ?? 'Not checked yet'),
                  _InfoRow('Database version', '${widget.db.dbVersion}'),
                  _InfoRow('Entries loaded', '${widget.db.entryCount}'),
                  _InfoRow('Entries skipped (damaged)',
                      '${widget.db.skippedMalformed}'),
                  _InfoRow('Brand pictures bundled',
                      '${widget.brand.assetCount}'),
                  _InfoRow(
                    'Brand pictures size',
                    _brandBytes == null
                        ? 'counting…'
                        : '${(_brandBytes! / 1024).toStringAsFixed(0)} KB',
                  ),
                  _InfoRow('Platform', defaultTargetPlatform.name),
                  const _InfoRow('Cloud help', 'Not set up yet (on-device only)'),
                  if (widget.socialStore != null) ...[
                    const Divider(),
                    _InfoRow(
                      'Saved on this device',
                      '${widget.socialStore!.posts.length} post(s), '
                          '${widget.socialStore!.replies.length} reply '
                          'draft(s), '
                          '${widget.socialStore!.prospects.length} '
                          'prospect(s)',
                    ),
                    _InfoRow('Post reminders',
                        widget.socialStore!.reminders.stateLabel),
                    _InfoRow(
                      'Saved-lists health',
                      widget.socialStore!.storeWarning ??
                          'OK — lists loaded normally',
                    ),
                    _InfoRow(
                      'Customers on a journey',
                      '${widget.socialStore!.customers.length}',
                    ),
                  ],
                  const Divider(),
                  _InfoRow('Guide sections', '${kGuideSections.length}'),
                  _InfoRow(
                    'First-run tour',
                    widget.tourSeen == null
                        ? 'Not checked'
                        : widget.tourSeen!
                            ? 'Seen'
                            : 'Not seen yet',
                  ),
                  _InfoRow(
                    'QR kit (referral link)',
                    widget.referralLinkSet == null
                        ? 'Not checked'
                        : widget.referralLinkSet!
                            ? 'Link set — QR ready'
                            : 'No link set yet',
                  ),
                ],
              ),
            ),
          ),
          if (widget.services != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Voice, speech and translation',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Divider(),
                    _InfoRow('Voice engine',
                        widget.services!.voice.activeEngineLabel),
                    _InfoRow(
                      'Kokoro voice file',
                      widget.services!.voice.kokoroEngine.modelManager
                          .stateLabel,
                    ),
                    _InfoRow(
                      'Voice picked',
                      widget.selectedVoice?.name ?? 'Device default voice',
                    ),
                    _InfoRow('Feeling level', widget.emotionLevel.label),
                    _InfoRow('Speech listening (mic)',
                        widget.services!.speechInput.availabilityLabel),
                    _InfoRow('Microphone permission',
                        _micPermission ?? 'checking…'),
                    _InfoRow(
                      'Language packs downloaded',
                      '${widget.services!.translation.downloadedCount}',
                    ),
                    const _InfoRow(
                      'Language packs size',
                      'Managed by the device system (not reported to the app)',
                    ),
                    _InfoRow('Last spoken by',
                        widget.services!.voice.lastRenderedBy),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hear the feelings',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    const Text(
                      'Tap a feeling to hear it in your picked voice, at '
                      'your feeling level. Every tap sounds a little '
                      'different — the feelings are made fresh each time.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final sample in _emotionSamples)
                          OutlinedButton.icon(
                            onPressed: () => _speakSample(sample),
                            icon: const Icon(Icons.play_arrow, size: 16),
                            label: Text(sample.label),
                          ),
                        OutlinedButton.icon(
                          onPressed: () => widget.services!.voice.stop(),
                          icon: const Icon(Icons.stop, size: 16),
                          label: const Text('Stop'),
                        ),
                      ],
                    ),
                    if (_renderedBy.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(_renderedBy,
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _running ? null : _runTests,
            icon: const Icon(Icons.play_circle_outline),
            label: Text(_running ? 'Running tests…' : 'Run self-tests'),
          ),
          const Text(
            'These tests really run: they reload the database, run a '
            'search, and open the pictures.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          for (final t in _tests)
            Card(
              child: ListTile(
                leading: Icon(
                  t.passed == null
                      ? Icons.circle_outlined
                      : t.passed!
                          ? Icons.check_circle
                          : Icons.error,
                  color: t.passed == null
                      ? Colors.grey
                      : t.passed!
                          ? Colors.green
                          : Colors.red,
                ),
                title: Text(t.name),
                subtitle: Text(
                  t.passed == null
                      ? t.description
                      : '${t.passed! ? 'Passed' : 'FAILED'} — ${t.detail}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
