import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/entry.dart';
import '../theme.dart';

/// The claim label chip — ALWAYS visible wherever entry content is shown
/// (SPEC §3: claims are always labeled; the chat layer must preserve the
/// label). "Official fact" reads as company-stated; "Distributor claim"
/// is visibly different so it can never be mistaken for a fact.
class ClaimChip extends StatelessWidget {
  final KnowledgeEntry entry;
  const ClaimChip({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final isOfficial = entry.claimLabel == 'official fact';
    return Chip(
      avatar: Icon(
        isOfficial ? Icons.verified_outlined : Icons.people_outline,
        size: 16,
        color: isOfficial ? LwColors.primary : LwColors.deepNavy,
      ),
      label: Text(
        entry.claimChipText,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      backgroundColor:
          isOfficial ? LwColors.tint : const Color(0xFFFFF3E0),
      side: BorderSide(
        color: isOfficial ? LwColors.accent : const Color(0xFFE0A83E),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// The official LifeWave logo (bundled SVG, used as-is). Falls back to a
/// clean text wordmark if the logo asset is unavailable — the only
/// fallback SPEC §7.12 allows (never a redrawn/fake logo).
class LogoImage extends StatelessWidget {
  final String? assetPath;
  final double height;
  const LogoImage({super.key, required this.assetPath, this.height = 36});

  @override
  Widget build(BuildContext context) {
    final path = assetPath;
    if (path == null) {
      return Text(
        'LifeWave',
        style: TextStyle(
          fontSize: height * 0.6,
          fontWeight: FontWeight.w700,
          color: LwColors.primary,
          letterSpacing: 0.5,
        ),
      );
    }
    return SvgPicture.asset(
      path,
      height: height,
      semanticsLabel: 'LifeWave logo',
    );
  }
}

/// A product picture from the bundled brand assets, or the branded
/// placeholder panel when the entry has no official picture
/// (prod-nirvana-legacy maps to null in assets.json — NO fake image).
class ProductImage extends StatelessWidget {
  final String? assetPath;
  final String productName;
  final double height;
  const ProductImage({
    super.key,
    required this.assetPath,
    required this.productName,
    this.height = 120,
  });

  @override
  Widget build(BuildContext context) {
    final path = assetPath;
    if (path == null) {
      return Container(
        height: height,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [LwColors.primary, LwColors.accent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.waves, color: Colors.white, size: 28),
            const SizedBox(height: 6),
            Text(
              productName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Text(
              'No official picture available',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      );
    }
    return Image.asset(
      path,
      height: height,
      width: double.infinity,
      fit: BoxFit.contain,
      semanticLabel: productName,
      errorBuilder: (context, error, stack) => Container(
        height: height,
        color: LwColors.tint,
        alignment: Alignment.center,
        child: const Text('Picture could not be loaded'),
      ),
    );
  }
}

/// Extracts the first http(s) URL from a string, or null. Pointer entries
/// carry the group link in both body and source_ref.
String? firstUrl(String? text) {
  if (text == null) return null;
  final match = RegExp(r'https?://[^\s)]+').firstMatch(text);
  return match?.group(0);
}

/// Friendly display names for topic ids.
String topicLabel(String topic) {
  switch (topic) {
    case 'products':
      return 'Products';
    case 'faq':
      return 'Questions & answers';
    case 'playbook':
      return 'Curiosity posts';
    case 'usage':
      return 'How to use';
    case 'business':
      return 'Business basics';
    case 'group-pointers':
      return 'Group guides (pointers)';
    case 'company':
      return 'About the company';
    case 'phototherapy':
      return 'How phototherapy works';
    case 'testimonials':
      return 'Testimonials';
    default:
      return topic;
  }
}

String formatUsd(double? value) =>
    value == null ? 'not listed' : '\$${value.toStringAsFixed(2)}';
