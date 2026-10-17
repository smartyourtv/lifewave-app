import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/qr_kit.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/social_widgets.dart';
import 'guide_screen.dart';

/// My QR kit (SPEC §7.8 item 6): the user's own referral link (set in
/// Settings) as a QR code with their name + logo branding, plus a
/// printable one-pager exported as PNG through the share sheet
/// (share / print / save all flow through the sheet — no storage
/// permission, no printing dependency).
class QrKitScreen extends StatefulWidget {
  final SocialDeps deps;
  final String? referralLink;
  final String? displayName;

  /// Opens Settings so the user can add/fix their link.
  final VoidCallback? onOpenSettings;
  const QrKitScreen({
    super.key,
    required this.deps,
    required this.referralLink,
    required this.displayName,
    this.onOpenSettings,
  });

  @override
  State<QrKitScreen> createState() => _QrKitScreenState();
}

class _QrKitScreenState extends State<QrKitScreen> {
  final GlobalKey _captureKey = GlobalKey();
  bool _busy = false;

  void _feedback(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  QrOnePager? get _pager {
    final link = widget.referralLink;
    if (link == null || !isValidReferralLink(link)) return null;
    return QrOnePager(
      displayName: widget.displayName ?? '',
      referralLink: link.trim(),
      logoAssetPath: widget.deps.brand.logoAssetPath,
      companyBlurb:
          companyBlurbFrom(widget.deps.db.byId('comp-story')),
    );
  }

  Future<void> _shareOnePager() async {
    final pager = _pager;
    if (pager == null) return;
    setState(() => _busy = true);
    try {
      final boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        _feedback('The one-pager is not ready yet. Try again.');
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        _feedback('The picture could not be made. Try again.');
        return;
      }
      final path = await widget.deps.share
          .writeTempFile('lifewave-qr-one-pager.png', bytes.buffer.asUint8List());
      final opened = await widget.deps.share.shareFile(path,
          text: 'My LifeWave QR card — ${pager.referralLink}');
      if (!mounted) return;
      _feedback(opened
          ? 'Share sheet opened. From there you can print it (via a '
              'printer app), save it, or send it.'
          : 'The share sheet could not open.');
    } catch (_) {
      _feedback('Export ran into a problem. The one-pager was not shared.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pager = _pager;
    final rawLink = widget.referralLink;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My QR kit'),
        actions: [
          HelpButton(
            screenKey: 'qr-kit',
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
            'Your own referral link as a QR code — for events, cards '
            'and conversations. The link is yours, entered by you in '
            'Settings and stored only on this device.',
          ),
          const SizedBox(height: 16),
          if (pager == null) ...[
            Card(
              color: LwColors.tint,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rawLink == null || rawLink.trim().isEmpty
                          ? 'No referral link yet'
                          : 'That link does not look right',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      rawLink == null || rawLink.trim().isEmpty
                          ? 'Add your LifeWave referral link in '
                              'Settings and your QR code will appear '
                              'here.'
                          : referralLinkProblem(rawLink) ??
                              'Add a valid link in Settings.',
                    ),
                    const SizedBox(height: 8),
                    if (widget.onOpenSettings != null)
                      FilledButton.icon(
                        onPressed: widget.onOpenSettings,
                        icon: const Icon(Icons.settings_outlined, size: 18),
                        label: const Text('Open Settings'),
                      ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LogoImage(
                          assetPath: pager.logoAssetPath, height: 36),
                      const SizedBox(height: 12),
                      QrImageView(
                        data: pager.referralLink,
                        version: QrVersions.auto,
                        size: 240,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: LwColors.deepNavy,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: LwColors.deepNavy,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (pager.displayName.isNotEmpty)
                        Text(
                          pager.displayName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      Text(
                        pager.referralLink,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: LwColors.primary,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Printable one-pager',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Center(
              child: RepaintBoundary(
                key: _captureKey,
                child: QrOnePagerView(pager: pager),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _shareOnePager,
              icon: const Icon(Icons.share_outlined),
              label: Text(_busy ? 'Making picture…' : 'Share the one-pager…'),
            ),
            const Text(
              'Sharing is also how you print or save it: the sheet '
              'offers printer apps, Files, Drive and Photos.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

/// The branded one-pager (also the PNG export source): logo, QR, the
/// link in text, a short official-fact blurb, and the independent-tool
/// line small at the bottom.
class QrOnePagerView extends StatelessWidget {
  final QrOnePager pager;
  const QrOnePagerView({super.key, required this.pager});

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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                if (pager.displayName.isNotEmpty)
                  Text(
                    pager.displayName,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text(
                  'Scan to visit my LifeWave store',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: LwColors.deepNavy,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                QrImageView(
                  data: pager.referralLink,
                  version: QrVersions.auto,
                  size: 200,
                ),
                const SizedBox(height: 12),
                Text(
                  pager.referralLink,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: LwColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  pager.companyBlurb,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 14),
                const Text(
                  QrOnePager.disclaimerLine,
                  textAlign: TextAlign.center,
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
