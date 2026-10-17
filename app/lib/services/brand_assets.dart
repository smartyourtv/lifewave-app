import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'knowledge_db.dart' show AssetTextLoader;

/// The brand-asset map (assets/assets.json): the official logo plus the
/// official product picture per product entry id. `prod-nirvana-legacy`
/// maps to null in the shipped map — there is no official picture for it,
/// and the UI renders a branded placeholder instead of any fake image
/// (ASSETS.md gap note).
class BrandAssets {
  static const String mapAssetPath = 'assets/assets.json';
  static const String assetPrefix = 'assets/';

  /// Asset path of the official logo SVG, e.g. assets/brand/lifewave-logo.svg
  final String? logoAssetPath;

  /// product entry id -> asset path, or null when no picture exists.
  final Map<String, String?> productImages;

  const BrandAssets({required this.logoAssetPath, required this.productImages});

  /// Number of shipped brand files (logo + product pictures that exist).
  int get assetCount =>
      (logoAssetPath != null ? 1 : 0) +
      productImages.values.where((v) => v != null).length;

  String? productImageFor(String entryId) => productImages[entryId];

  /// Loads the map. A missing/corrupt map is NOT fatal (unlike the
  /// database): branding degrades to the text wordmark fallback and the
  /// product placeholder panels, per SPEC §7.12 guardrails.
  static Future<BrandAssets> load({AssetTextLoader? loader}) async {
    final loadText = loader ?? ((p) => rootBundle.loadString(p));
    try {
      final raw = jsonDecode(await loadText(mapAssetPath));
      if (raw is! Map<String, dynamic>) {
        return const BrandAssets(logoAssetPath: null, productImages: {});
      }
      final logoRaw = raw['logo'];
      final logo = logoRaw is String ? '$assetPrefix$logoRaw' : null;
      final products = <String, String?>{};
      final productsRaw = raw['products'];
      if (productsRaw is Map<String, dynamic>) {
        productsRaw.forEach((id, v) {
          products[id] = v is String ? '$assetPrefix$v' : null;
        });
      }
      return BrandAssets(logoAssetPath: logo, productImages: products);
    } catch (_) {
      return const BrandAssets(logoAssetPath: null, productImages: {});
    }
  }

  /// Total byte size of all shipped brand files (for diagnostics).
  Future<int> totalBytes() async {
    var total = 0;
    final paths = <String>[
      if (logoAssetPath != null) logoAssetPath!,
      ...productImages.values.whereType<String>(),
    ];
    for (final p in paths) {
      try {
        final data = await rootBundle.load(p);
        total += data.lengthInBytes;
      } catch (_) {
        // Missing file contributes 0; the asset-load self-test reports it.
      }
    }
    return total;
  }
}
