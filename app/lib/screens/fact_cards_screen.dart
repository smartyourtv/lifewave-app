import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/emotion.dart';
import 'package:flutter/rendering.dart';

import '../models/entry.dart';
import '../services/compliance.dart';
import '../services/compliance_guide.dart';
import '../services/fact_card.dart';
import '../services/post_generator.dart' show focusForProduct;
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/social_widgets.dart';
import 'guide_screen.dart';

/// Fact cards (SPEC §7.8 item 4): pick a product -> a branded card
/// with the product's official picture, ONE official fact from its
/// database entry, and ONE curiosity question -> live preview ->
/// compliance scan (must pass) -> export as PNG via the share sheet.
///
/// A product with no official picture (Nirvana) gets the branded
/// placeholder — never a fake image (SPEC §7.12 guardrails).
class FactCardsScreen extends StatefulWidget {
  final SocialDeps deps;
  const FactCardsScreen({super.key, required this.deps});

  @override
  State<FactCardsScreen> createState() => _FactCardsScreenState();
}

class _FactCardsScreenState extends State<FactCardsScreen> {
  final GlobalKey _captureKey = GlobalKey();
  KnowledgeEntry? _product;
  bool _busy = false;

  List<KnowledgeEntry> get _products => widget.deps.db.byTopic('products');

  @override
  void initState() {
    super.initState();
    if (_products.isNotEmpty) _product = _products.first;
  }

  FactCardData? get _card {
    final p = _product;
    if (p == null) return null;
    return composeFactCard(
      p,
      imageAssetPath: widget.deps.brand.productImageFor(p.id),
      focus: focusForProduct(p),
    );
  }

  ComplianceReport? get _report {
    final card = _card;
    return card == null
        ? null
        : const ComplianceScanner().scan(card.allText);
  }

  void _feedback(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Captures the preview as a PNG and hands it to the share sheet.
  /// Sharing is also the save path: the sheet offers Files / Drive /
  /// Photos targets ("save to device" via the sheet, per the audit —
  /// no storage permission is ever requested).
  Future<void> _export() async {
    final card = _card;
    final report = _report;
    if (card == null || report == null) return;
    if (report.hasHits) {
      _feedback('This card\'s text has compliance flags, so it cannot '
          'be exported. The fact comes straight from the database — '
          'pick another product, and please report this one.');
      return;
    }
    setState(() => _busy = true);
    try {
      final boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        _feedback('The card preview is not ready yet. Try again.');
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        _feedback('The card picture could not be made. Try again.');
        return;
      }
      final path = await widget.deps.share.writeTempFile(
        'fact-card-${card.productId}.png',
        bytes.buffer.asUint8List(),
      );
      final opened = await widget.deps.share.shareFile(path,
          text: 'LifeWave fact card — ${card.productTitle}');
      if (!mounted) return;
      _feedback(opened
          ? 'Share sheet opened. Pick Facebook to share it, or Files / '
              'Drive / Photos to save the picture to this device.'
          : 'The share sheet could not open, so the picture was not '
              'handed off.');
    } catch (e) {
      _feedback('Export ran into a problem. The card was not shared.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Fact cards'), actions: [HelpButton(screenKey: 'fact-cards', brand: widget.deps.brand, services: widget.deps.m2, db: widget.deps.db, share: widget.deps.share, emotionLevel: EmotionLevel.warm)],),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'A shareable picture card made only from the database: the '
            'product\'s official picture, one official fact from its '
            'entry, and one curiosity question. The text is checked for '
            'compliance before the card can be exported — no invented '
            'claims, ever.',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<KnowledgeEntry>(
            value: _product,
            decoration: const InputDecoration(
              labelText: 'Product',
              border: OutlineInputBorder(),
            ),
            items: _products
                .map((p) => DropdownMenuItem(
                      value: p,
                      child: Text(p.title, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _product = v),
          ),
          const SizedBox(height: 16),
          if (card != null) ...[
            Center(
              child: RepaintBoundary(
                key: _captureKey,
                child: FactCardView(card: card),
              ),
            ),
            const SizedBox(height: 16),
            if (report != null)
              ComplianceResultsView(
                report: report,
                guide: ComplianceGuide.fromDb(widget.deps.db.entries),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || (report?.hasHits ?? true) ? null : _export,
              icon: const Icon(Icons.share_outlined),
              label: Text(_busy ? 'Making picture…' : 'Export picture…'),
            ),
            const Text(
              'Export opens the share sheet with a PNG picture of the '
              'card. From there you can share it to Facebook or save it '
              'to this device (Files / Drive / Photos).',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

/// The branded card itself (also what gets captured to PNG). Fixed
/// width so the exported picture has a post-friendly shape.
class FactCardView extends StatelessWidget {
  final FactCardData card;
  const FactCardView({super.key, required this.card});

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
            child: Row(
              children: [
                const Icon(Icons.waves, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'LifeWave',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  card.claimLabel == 'official fact'
                      ? 'Official fact'
                      : 'Distributor claim',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          ProductImage(
            assetPath: card.imageAssetPath,
            productName: card.productTitle,
            height: 170,
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.productTitle,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: LwColors.deepNavy,
                  ),
                ),
                const SizedBox(height: 8),
                Text(card.fact, style: const TextStyle(fontSize: 15, height: 1.35)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: LwColors.tint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    card.question,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: LwColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'An independent Brand Partner tool — not an official '
                  'LifeWave, Inc. app.',
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
