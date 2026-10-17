import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/entry.dart';
import '../services/presentation.dart';
import '../services/translation_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/social_widgets.dart';
import 'guide_screen.dart';

/// Presentation mode (SPEC §7.8 item 3): full-screen slideshow —
/// title slide with the logo, one slide per product (official picture
/// large, name, 2–3 official-fact lines), and an end slide with the
/// user's QR (QR kit set up) or the group-invite pointer.
///
/// Controls: big tap zones (left = back, right = next) + optional
/// voice control ("next" / "back" via SpeechInput when available,
/// with the honest fallback note). Translated captions are cached
/// per slide + language. High-contrast large type — readable on a TV
/// across the room.
class PresentationScreen extends StatefulWidget {
  final SocialDeps deps;
  final String? referralLink;
  final String? displayName;
  const PresentationScreen({
    super.key,
    required this.deps,
    this.referralLink,
    this.displayName,
  });

  @override
  State<PresentationScreen> createState() => _PresentationScreenState();
}

class _PresentationScreenState extends State<PresentationScreen> {
  final Set<String> _picked = {};
  bool _running = false;
  List<PresentationSlide> _slides = const [];
  int _index = 0; // 0 = title, 1..n = products, n+1 = end
  final CaptionCache _captions = CaptionCache();
  AppLanguage? _captionLanguage;
  String? _captionText;
  bool _captionBusy = false;

  List<KnowledgeEntry> get _products => widget.deps.db.byTopic('products');

  @override
  void initState() {
    super.initState();
    for (final p in flagshipProducts(_products)) {
      _picked.add(p.id);
    }
  }

  int get _totalSlides => _slides.length + 2; // title + products + end
  bool get _onTitle => _index == 0;
  bool get _onEnd => _index == _totalSlides - 1;
  PresentationSlide? get _slide =>
      (_onTitle || _onEnd) ? null : _slides[_index - 1];

  void _start() {
    final chosen =
        _products.where((p) => _picked.contains(p.id)).toList();
    if (chosen.isEmpty) return;
    setState(() {
      _slides = buildSlides(
        chosen,
        imageFor: widget.deps.brand.productImageFor,
      );
      _index = 0;
      _running = true;
      _captionLanguage = null;
      _captionText = null;
    });
  }

  void _next() {
    if (_index < _totalSlides - 1) {
      setState(() {
        _index++;
        _captionText = _cachedCaption();
      });
    }
  }

  void _back() {
    if (_index > 0) {
      setState(() {
        _index--;
        _captionText = _cachedCaption();
      });
    }
  }

  String? _cachedCaption() {
    final slide = _slide;
    final lang = _captionLanguage;
    if (slide == null || lang == null || lang.code == 'en') return null;
    return _captions.get(slide.productId, lang.code);
  }

  /// Voice control: one listen session; "next"/"forward" advances,
  /// "back" goes back. Honest fallback: when speech input is not
  /// available the service says so, and the tap zones remain.
  Future<void> _voiceControl() async {
    final result = await widget.deps.m2.speechInput.listenOnce();
    if (!mounted) return;
    if (!result.ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
      return;
    }
    final words = result.text.toLowerCase();
    if (words.contains('next') || words.contains('forward')) {
      _next();
    } else if (words.contains('back')) {
      _back();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Heard "${result.text}" — say "next" or "back".'),
      ));
    }
  }

  Future<void> _toggleCaptions(AppLanguage? lang) async {
    final slide = _slide;
    setState(() => _captionLanguage = lang);
    if (lang == null || lang.code == 'en' || slide == null) {
      setState(() => _captionText = null);
      return;
    }
    final cached = _captions.get(slide.productId, lang.code);
    if (cached != null) {
      setState(() => _captionText = cached);
      return;
    }
    setState(() => _captionBusy = true);
    final result = await widget.deps.m2.translation.translateWithCascade(
      slide.captionText,
      fromCode: 'en',
      toCode: lang.code,
    );
    if (!mounted) return;
    setState(() => _captionBusy = false);
    if (result.usedOriginal) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
      setState(() => _captionText = null);
    } else {
      _captions.put(slide.productId, lang.code, result.text);
      setState(() => _captionText = result.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_running) return _buildSetup(context);
    return _buildShow(context);
  }

  Widget _buildSetup(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Presentation mode'),
        actions: [
          HelpButton(
            screenKey: 'presentation',
            brand: widget.deps.brand,
            services: widget.deps.m2,
            db: widget.deps.db,
            share: widget.deps.share,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'A full-screen slideshow for a coffee meeting or a TV. '
            'Pick the products to show — the best-known ones are '
            'already picked. Every slide uses the official picture '
            'and official facts only.',
          ),
          const SizedBox(height: 12),
          for (final p in _products)
            CheckboxListTile(
              value: _picked.contains(p.id),
              title: Text(p.title),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _picked.add(p.id);
                } else {
                  _picked.remove(p.id);
                }
              }),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _picked.isEmpty ? null : _start,
            icon: const Icon(Icons.slideshow_outlined),
            label: const Text('Start presentation'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShow(BuildContext context) {
    final slide = _slide;
    return Scaffold(
      backgroundColor: LwColors.deepNavy,
      body: SafeArea(
        child: Stack(
          children: [
            // Big tap zones: left third = back, right two-thirds = next.
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _back,
                    child: const SizedBox.expand(),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _next,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
            IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: _onTitle
                    ? _titleSlide(context)
                    : _onEnd
                        ? _endSlide(context)
                        : _productSlide(context, slide!),
              ),
            ),
            // Controls row (above the tap zones).
            Positioned(
              left: 12,
              right: 12,
              bottom: 8,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: 'Exit presentation',
                    onPressed: () => setState(() => _running = false),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    tooltip: 'Previous slide',
                    onPressed: _back,
                  ),
                  IconButton(
                    icon: const Icon(Icons.mic_none, color: Colors.white),
                    tooltip: 'Voice control — say "next" or "back" '
                        '(typing taps always work)',
                    onPressed: _voiceControl,
                  ),
                  Expanded(
                    child: Text(
                      'Slide ${_index + 1} of $_totalSlides',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  if (slide != null)
                    DropdownButton<AppLanguage?>(
                      value: _captionLanguage,
                      dropdownColor: LwColors.deepNavy,
                      hint: const Text('Captions: English',
                          style: TextStyle(color: Colors.white)),
                      style: const TextStyle(color: Colors.white),
                      underline: const SizedBox.shrink(),
                      items: [
                        const DropdownMenuItem<AppLanguage?>(
                          value: null,
                          child: Text('Captions: English'),
                        ),
                        for (final l in kAppLanguages.where(
                            (l) => l.code != 'en'))
                          DropdownMenuItem<AppLanguage?>(
                            value: l,
                            child: Text('Captions: ${l.name}'),
                          ),
                      ],
                      onChanged: _toggleCaptions,
                    ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward,
                        color: Colors.white),
                    tooltip: 'Next slide',
                    onPressed: _next,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _titleSlide(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(20),
          child: LogoImage(
              assetPath: widget.deps.brand.logoAssetPath, height: 64),
        ),
        const SizedBox(height: 24),
        const Text(
          'LifeWave',
          style: TextStyle(
            color: Colors.white,
            fontSize: 44,
            fontWeight: FontWeight.w800,
          ),
          textAlign: TextAlign.center,
        ),
        const Text(
          'Phototherapy patches — the official story',
          style: TextStyle(color: Colors.white70, fontSize: 22),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        const Text(
          'Tap the right side of the screen to begin.',
          style: TextStyle(color: Colors.white54, fontSize: 16),
        ),
      ],
    );
  }

  Widget _productSlide(BuildContext context, PresentationSlide slide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            color: Colors.white,
            child: ProductImage(
              assetPath: slide.imageAssetPath,
              productName: slide.productTitle,
              height: 300,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          slide.productTitle,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 36,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 12),
        if (_captionText != null)
          Text(
            _captionText!,
            style: const TextStyle(
              color: Color(0xFFFFF59D),
              fontSize: 24,
              height: 1.35,
            ),
          )
        else
          for (final fact in slide.factLines)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '• $fact',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  height: 1.35,
                ),
              ),
            ),
        if (_captionBusy)
          const Text('Translating captions…',
              style: TextStyle(color: Colors.white54)),
        Text(
          slide.claimLabel == 'official fact'
              ? 'Official facts — LifeWave'
              : 'Distributor claim — LifeWave',
          style: const TextStyle(color: Colors.white54, fontSize: 15),
        ),
      ],
    );
  }

  Widget _endSlide(BuildContext context) {
    final link = widget.referralLink;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Thank you!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        if (link != null && link.isNotEmpty) ...[
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: QrImageView(
              data: link,
              version: QrVersions.auto,
              size: 220,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.displayName == null
                ? 'Scan to visit my LifeWave store'
                : 'Scan to visit ${widget.displayName}\'s LifeWave store',
            style: const TextStyle(color: Colors.white, fontSize: 20),
            textAlign: TextAlign.center,
          ),
          Text(
            link,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ] else ...[
          const Icon(Icons.groups_outlined, color: Colors.white, size: 56),
          const SizedBox(height: 12),
          const Text(
            'Want to learn more? Join us in LW Team Learning — '
            'that is where the full teaching lives. Ask me and I '
            'will add you.',
            style: TextStyle(color: Colors.white, fontSize: 22, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            '(Set up My QR kit in Settings to end with your own QR '
            'code here instead.)',
            style: TextStyle(color: Colors.white54, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
