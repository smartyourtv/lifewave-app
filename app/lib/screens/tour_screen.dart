import 'package:flutter/material.dart';

import '../services/brand_assets.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// First-run guided tour (SPEC §7.6): 5–6 swipeable plain-language
/// cards, shown ONCE on first launch (replacing the M1 welcome-card
/// flow). Skip or Done marks it seen; "Show the tour again" lives in
/// the Guide. The tour carries the §7.12 independent-tool line.
class TourCardData {
  final IconData icon;
  final String title;
  final String body;
  const TourCardData(this.icon, this.title, this.body);
}

const List<TourCardData> kTourCards = [
  TourCardData(
    Icons.waves,
    'Welcome to LifeWave AI',
    'Your helper for product questions, posts, replies and practice — '
        'built on a database of official LifeWave information, and it '
        'works offline.\n\n'
        'An independent Brand Partner tool — not an official LifeWave, '
        'Inc. app.',
  ),
  TourCardData(
    Icons.chat_bubble_outline,
    'Ask anything',
    'Tap Chat and ask a question in plain words — or say it out loud. '
        'Every answer shows where it came from: "official fact" or '
        '"distributor claim", so you always know which is which.',
  ),
  TourCardData(
    Icons.mic_none,
    'Talk, and hear it back',
    'Tap the microphone to talk instead of typing. Answers can be '
        'spoken out loud too — in a warm voice with real feeling. Pick '
        'your voice in Settings.',
  ),
  TourCardData(
    Icons.translate,
    'Any language',
    'Translate messages, talk face to face with someone in another '
        'language, and read answers in your language. Language packs '
        'download once, then work offline.',
  ),
  TourCardData(
    Icons.auto_awesome_outlined,
    'Posts that start conversations',
    'The app writes curiosity posts and reply drafts in the playbook '
        'style, checks them for compliance, and queues them with a '
        'reminder. You approve everything — and you send everything '
        'yourself.',
  ),
  TourCardData(
    Icons.menu_book_outlined,
    'Help is always one tap away',
    'Every screen has a ? button that explains it, and the full Guide '
        '(in More) covers everything in plain words — you can even ask '
        'it questions out loud. That is the tour — welcome aboard!',
  ),
];

class TourScreen extends StatefulWidget {
  final BrandAssets? brand;

  /// Called when the user finishes or skips the tour. The caller
  /// persists "tour seen" — the tour never shows itself again.
  final VoidCallback onDone;

  const TourScreen({super.key, this.brand, required this.onDone});

  @override
  State<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends State<TourScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _page == kTourCards.length - 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LwColors.tint,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: LwColors.primary,
        actions: [
          TextButton(
            onPressed: widget.onDone,
            child: const Text('Skip'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Center(
              child: LogoImage(
                  assetPath: widget.brand?.logoAssetPath, height: 44),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: kTourCards.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final card = kTourCards[i];
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(card.icon,
                                size: 56, color: LwColors.primary),
                            const SizedBox(height: 16),
                            Text(
                              card.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              card.body,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 16, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < kTourCards.length; i++)
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _page
                          ? LwColors.primary
                          : LwColors.accent.withOpacity(0.4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: FilledButton(
                onPressed: _isLast
                    ? widget.onDone
                    : () => _controller.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(_isLast ? 'Done — start using the app' : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
