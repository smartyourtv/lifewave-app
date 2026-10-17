import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../services/brand_assets.dart';
import '../services/emotion.dart';
import '../services/guide_content.dart';
import '../services/knowledge_db.dart';
import '../services/m2_services.dart';
import '../services/share_service.dart';
import '../services/translation_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// The in-app user guide (SPEC §7.6): section list + search +
/// "Ask the guide" + per-section Listen (spoken step by step) and
/// Translate + quick-start one-pager export. Fully offline — the
/// content is bundled data (services/guide_content.dart).
///
/// A help (?) button on every major screen opens this guide at that
/// screen's section (see [HelpButton] + [kScreenHelpSections]).
class GuideScreen extends StatefulWidget {
  final BrandAssets? brand;
  final M2Services? services;
  final KnowledgeDb? db;
  final ShareGateway? share;
  final String? initialSectionKey;
  final VoidCallback? onShowTour;
  final EmotionLevel emotionLevel;

  const GuideScreen({
    super.key,
    this.brand,
    this.services,
    this.db,
    this.share,
    this.initialSectionKey,
    this.onShowTour,
    this.emotionLevel = EmotionLevel.warm,
  });

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  final _searchController = TextEditingController();
  final _captureKey = GlobalKey();
  GuideSection? _open;
  String _query = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final key = widget.initialSectionKey;
    if (key != null) _open = guideSectionByKey(key);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _feedback(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// "Ask the guide": type or dictate a how-do-I question -> open the
  /// best-matching section.
  void _askGuide(String question) {
    final q = question.trim();
    if (q.isEmpty) return;
    final hits = searchGuide(q, limit: 1);
    if (hits.isEmpty) {
      _feedback('No guide section matches that yet. Try different '
          'words, or browse the list below.');
      return;
    }
    setState(() => _open = hits.first);
  }

  Future<void> _dictateQuestion() async {
    final services = widget.services;
    if (services == null) return;
    final result = await services.speechInput.listenOnce();
    if (!mounted) return;
    if (result.ok) {
      _searchController.text = result.text;
      _askGuide(result.text);
    } else {
      _feedback(result.message);
    }
  }

  Future<void> _exportQuickStart() async {
    final share = widget.share;
    if (share == null) {
      _feedback('Sharing is not available from here.');
      return;
    }
    setState(() => _busy = true);
    try {
      final boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        _feedback('The quick-start card is not ready yet. Try again.');
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        _feedback('The picture could not be made. Try again.');
        return;
      }
      final path = await share.writeTempFile(
          'lifewave-quick-start.png', bytes.buffer.asUint8List());
      final opened =
          await share.shareFile(path, text: 'LifeWave AI — quick start');
      if (!mounted) return;
      _feedback(opened
          ? 'Share sheet opened. Pick a printer app, Files, or share '
              'it with your team.'
          : 'The share sheet could not open.');
    } catch (_) {
      _feedback('Export ran into a problem. The card was not shared.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    if (open != null) {
      return _SectionView(
        section: open,
        services: widget.services,
        emotionLevel: widget.emotionLevel,
        onBack: () => setState(() => _open = null),
      );
    }
    final results =
        _query.isEmpty ? kGuideSections : searchGuide(_query, limit: 30);
    return Scaffold(
      appBar: AppBar(title: const Text('Guide')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: LogoImage(
                assetPath: widget.brand?.logoAssetPath, height: 36),
          ),
          const SizedBox(height: 8),
          const Text(
            'Plain words, short steps, for every part of the app. '
            'Search, ask out loud, or pick a topic. The whole guide '
            'works offline.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Ask the guide — "How do I…?"',
              hintText: 'For example: how do I schedule a post',
              border: const OutlineInputBorder(),
              suffixIcon: widget.services == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.mic_outlined),
                      tooltip: 'Ask by voice',
                      onPressed: _dictateQuestion,
                    ),
            ),
            onChanged: (v) => setState(() => _query = v),
            onSubmitted: _askGuide,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _askGuide(_searchController.text),
                icon: const Icon(Icons.help_outline, size: 18),
                label: const Text('Ask the guide'),
              ),
              if (widget.onShowTour != null)
                OutlinedButton.icon(
                  onPressed: widget.onShowTour,
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: const Text('Show the tour again'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_query.isNotEmpty && results.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.search_off_outlined),
                title: Text('Nothing matches that yet'),
                subtitle: Text('Try different words — like "post", '
                    '"translate", or "voice".'),
              ),
            ),
          for (final s in results)
            Card(
              child: ListTile(
                leading: const Icon(Icons.menu_book_outlined,
                    color: LwColors.primary),
                title: Text(s.title),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => setState(() => _open = s),
              ),
            ),
          const SizedBox(height: 16),
          Text('Quick start — your first 6 steps',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Center(
            child: RepaintBoundary(
              key: _captureKey,
              child: const QuickStartCard(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _exportQuickStart,
            icon: const Icon(Icons.share_outlined),
            label: Text(_busy ? 'Making picture…' : 'Share quick start…'),
          ),
          const Text(
            'The quick-start card as a picture: share it, save it, or '
            'print it from the share sheet.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// One guide section: rendered steps, Listen (spoken step by step),
/// and Translate (M2 service; the translated text replaces the body
/// view, labeled as translated).
class _SectionView extends StatefulWidget {
  final GuideSection section;
  final M2Services? services;
  final EmotionLevel emotionLevel;
  final VoidCallback onBack;
  const _SectionView({
    required this.section,
    required this.services,
    required this.emotionLevel,
    required this.onBack,
  });

  @override
  State<_SectionView> createState() => _SectionViewState();
}

class _SectionViewState extends State<_SectionView> {
  AppLanguage _language = languageByCode('es');
  String? _translatedBody;
  bool _busy = false;
  bool _speaking = false;

  void _feedback(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Speaks the section step by step through the single voice
  /// controller — one call per step, in order.
  Future<void> _listen() async {
    final services = widget.services;
    if (services == null) return;
    if (_speaking) {
      await services.voice.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }
    setState(() => _speaking = true);
    final steps = widget.section.spokenSteps;
    for (var i = 0; i < steps.length; i++) {
      if (!mounted || !_speaking) break;
      await services.voice.speak(
        i == 0
            ? '[warm] ${widget.section.title}. ${steps[i]}'
            : '[warm] ${steps[i]}',
        level: widget.emotionLevel,
      );
    }
    if (mounted) setState(() => _speaking = false);
  }

  Future<void> _translate() async {
    final services = widget.services;
    if (services == null) return;
    setState(() => _busy = true);
    final result = await services.translation.translateWithCascade(
      widget.section.body,
      fromCode: 'en',
      toCode: _language.code,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.usedOriginal) {
      _feedback(result.message);
    } else {
      setState(() => _translatedBody = result.text);
      _feedback('Shown in ${_language.name}. Tap "Show in English" to '
          'go back.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _translatedBody ?? widget.section.body;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.section.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final line in body.split('\n'))
            if (line.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  line.trim(),
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    fontWeight: RegExp(r'^\d+\.\s').hasMatch(line.trim())
                        ? FontWeight.w500
                        : null,
                  ),
                ),
              ),
          if (_translatedBody != null)
            TextButton(
              onPressed: () => setState(() => _translatedBody = null),
              child: const Text('Show in English'),
            ),
          const SizedBox(height: 8),
          if (widget.services != null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _listen,
                  icon: Icon(_speaking ? Icons.stop : Icons.volume_up_outlined,
                      size: 18),
                  label: Text(_speaking ? 'Stop' : 'Listen — hear the steps'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<AppLanguage>(
                    value: _language,
                    decoration: const InputDecoration(
                      labelText: 'Read this section in…',
                      border: OutlineInputBorder(),
                    ),
                    items: kAppLanguages
                        .map((l) =>
                            DropdownMenuItem(value: l, child: Text(l.name)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _language = v);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _translate,
                  icon: const Icon(Icons.translate, size: 18),
                  label: Text(_busy ? 'Working…' : 'Translate'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The branded quick-start card (also the PNG export source).
class QuickStartCard extends StatelessWidget {
  const QuickStartCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: LwColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LwColors.accent, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: LwColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: const Row(
              children: [
                Icon(Icons.waves, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'LifeWave AI — Quick start',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < kQuickStartSteps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${i + 1}. ${kQuickStartSteps[i]}',
                      style: const TextStyle(fontSize: 14, height: 1.35),
                    ),
                  ),
                const Text(
                  AppInfo.independentToolLine,
                  style: TextStyle(fontSize: 10, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The per-screen help (?) button (SPEC §7.6): opens the guide at the
/// section registered for [screenKey] in [kScreenHelpSections].
class HelpButton extends StatelessWidget {
  final String screenKey;
  final BrandAssets? brand;
  final M2Services? services;
  final KnowledgeDb? db;
  final ShareGateway? share;
  final VoidCallback? onShowTour;
  final EmotionLevel emotionLevel;

  const HelpButton({
    super.key,
    required this.screenKey,
    this.brand,
    this.services,
    this.db,
    this.share,
    this.onShowTour,
    this.emotionLevel = EmotionLevel.warm,
  });

  @override
  Widget build(BuildContext context) {
    final sectionKey = kScreenHelpSections[screenKey];
    return IconButton(
      icon: const Icon(Icons.help_outline),
      tooltip: 'Help — about this screen',
      onPressed: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => GuideScreen(
            brand: brand,
            services: services,
            db: db,
            share: share,
            initialSectionKey: sectionKey,
            onShowTour: onShowTour,
            emotionLevel: emotionLevel,
          ),
        ));
      },
    );
  }
}
