import 'package:flutter/material.dart';

import '../services/emotion.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/entry.dart';
import '../services/brand_assets.dart';
import '../services/knowledge_db.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'guide_screen.dart';

/// Catalog: browse entries by topic (chips), entry cards with the
/// official product picture where one exists.
class CatalogScreen extends StatefulWidget {
  final KnowledgeDb db;
  final BrandAssets brand;
  const CatalogScreen({super.key, required this.db, required this.brand});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  String? _selectedTopic; // null = All

  @override
  Widget build(BuildContext context) {
    final entries = _selectedTopic == null
        ? widget.db.entries
        : widget.db.byTopic(_selectedTopic!);
    return Scaffold(
      appBar: AppBar(title: const Text('Catalog'), actions: [HelpButton(screenKey: 'catalog', brand: widget.brand, services: null, db: widget.db, share: null, emotionLevel: EmotionLevel.warm)],),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Browse everything in the database. Pick a topic, or scroll '
              'all entries. Tap any card for the full entry.',
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All topics'),
                  selected: _selectedTopic == null,
                  onSelected: (_) => setState(() => _selectedTopic = null),
                ),
                for (final topic in widget.db.topics)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(topicLabel(topic)),
                      selected: _selectedTopic == topic,
                      onSelected: (_) =>
                          setState(() => _selectedTopic = topic),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              itemCount: entries.length,
              itemBuilder: (context, i) => EntryCard(
                entry: entries[i],
                brand: widget.brand,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        EntryDetailScreen(entry: entries[i], brand: widget.brand),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One catalog / search-result card.
class EntryCard extends StatelessWidget {
  final KnowledgeEntry entry;
  final BrandAssets brand;
  final VoidCallback? onTap;
  const EntryCard(
      {super.key, required this.entry, required this.brand, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isProduct = entry.topic == 'products';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isProduct)
              ProductImage(
                assetPath: brand.productImageFor(entry.id),
                productName: entry.title,
                height: 140,
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          entry.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      ClaimChip(entry: entry),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Topic: ${topicLabel(entry.topic)}',
                    style: const TextStyle(
                        fontSize: 12, color: LwColors.deepNavy),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    entry.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (isProduct) ...[
                    const SizedBox(height: 6),
                    Text(
                      'US retail ${formatUsd(entry.priceRetailUsd)} / '
                      'Subscribe & Save ${formatUsd(entry.priceSubscribeUsd)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full entry detail: whole body, claim chip, structured price fields when
/// present ("not listed" when absent), and the source link.
class EntryDetailScreen extends StatelessWidget {
  final KnowledgeEntry entry;
  final BrandAssets brand;
  const EntryDetailScreen(
      {super.key, required this.entry, required this.brand});

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final sourceUrl = firstUrl(entry.sourceRef) ?? firstUrl(entry.body);
    return Scaffold(
      appBar: AppBar(title: Text(topicLabel(entry.topic))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (entry.topic == 'products')
            Card(
              clipBehavior: Clip.antiAlias,
              child: ProductImage(
                assetPath: brand.productImageFor(entry.id),
                productName: entry.title,
                height: 200,
              ),
            ),
          const SizedBox(height: 8),
          Text(entry.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              ClaimChip(entry: entry),
              const SizedBox(width: 8),
              Text('Topic: ${topicLabel(entry.topic)}'),
            ],
          ),
          const SizedBox(height: 12),
          Text(entry.body, style: const TextStyle(fontSize: 16, height: 1.4)),
          const SizedBox(height: 16),
          if (entry.topic == 'products') ...[
            const Divider(),
            _DetailRow('Item code', entry.itemCode ?? 'not listed'),
            _DetailRow('US retail price', formatUsd(entry.priceRetailUsd)),
            _DetailRow(
                'Subscribe & Save price', formatUsd(entry.priceSubscribeUsd)),
            _DetailRow('Category', entry.category ?? 'not listed'),
          ],
          _DetailRow('Last updated', entry.updated),
          const Divider(),
          const Text('Source',
              style: TextStyle(fontWeight: FontWeight.w600)),
          Text(entry.sourceRef),
          if (sourceUrl != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _open(sourceUrl),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(entry.isPointer
                    ? 'Open the group'
                    : 'Open the source page'),
              ),
            ),
          if (entry.isPointer)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'This is a pointer: the full material lives in the group '
                'and is not copied into this app.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
