import '../theme.dart';
import 'retrieval.dart';

/// The in-app user guide (SPEC §7.6 — a headline requirement).
///
/// The guide content is DATA, not hard-coded screen text: sections are
/// plain records the guide screen lists, searches (with the same
/// tokenizer the database retrieval uses), translates, and speaks
/// step by step. Plain language, no jargon, short steps, covering
/// EVERY feature — the coverage test in test/m4_extras_test.dart fails
/// if a feature in [kGuideFeatureKeys] ever loses its section.
///
/// The guide works fully offline: this content ships in the app.
class GuideSection {
  /// Stable key, e.g. 'schedule-post'. Also the help-registry target.
  final String key;

  /// The feature this section covers (see [kGuideFeatureKeys]).
  final String featureKey;

  final String title;

  /// Plain-language body. Lines starting with a number + '. ' render
  /// as steps; other lines render as paragraphs.
  final String body;

  /// Extra words search should find this section by.
  final String keywords;

  const GuideSection({
    required this.key,
    required this.featureKey,
    required this.title,
    required this.body,
    this.keywords = '',
  });

  String get searchableText => '$title $keywords $body';

  /// The body as speakable steps: one string per paragraph/step, for
  /// the Listen button (spoken one at a time via VoiceService).
  List<String> get spokenSteps => body
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .map((l) => l.replaceFirst(RegExp(r'^\d+\.\s+'), ''))
      .toList(growable: false);
}

/// Every feature that MUST have a guide section. The coverage test
/// enumerates this list — add a feature here and the test demands its
/// section.
const List<String> kGuideFeatureKeys = [
  'getting-started',
  'chat',
  'voice',
  'translator',
  'conversation',
  'write-post',
  'schedule-post',
  'replies',
  'compliance',
  'fact-cards',
  'calendar',
  'pipeline',
  'journey',
  'qr-kit',
  'roleplay',
  'demo',
  'presentation',
  'settings',
  'updating',
  'troubleshooting',
  'about',
];

const List<GuideSection> kGuideSections = [
  GuideSection(
    key: 'getting-started',
    featureKey: 'getting-started',
    title: 'Getting started',
    keywords: 'first time start begin home today welcome tour',
    body: 'Welcome! This app helps you answer product questions, write '
        'posts, and keep track of people — using a built-in database '
        'of official LifeWave information. It works even with no '
        'internet.\n'
        '1. Look at the Today card on the first screen — it shows '
        'what needs your attention.\n'
        '2. Tap "Ask a question" to ask anything about the products.\n'
        '3. Tap "More" (bottom right) to find everything else: posts, '
        'replies, the translator, practice, and this guide.\n'
        '4. Your name, voice and languages live in Settings — they '
        'are stored only on this device.\n'
        'Nothing in this app sends anything by itself. You always '
        'approve, and you always share things yourself.',
  ),
  GuideSection(
    key: 'ask-question',
    featureKey: 'chat',
    title: 'Ask a question (chat)',
    keywords: 'chat ask question answer database search product price',
    body: 'The Chat screen answers questions from the built-in '
        'database — never from guesses.\n'
        '1. Tap Chat at the bottom of the screen.\n'
        '2. Type your question, or tap the microphone and say it.\n'
        '3. Tap Ask.\n'
        'Every answer shows where it came from and a label: "Official '
        'fact" means the company states it; "Distributor claim" means '
        'partners say it but it is not a checked fact.\n'
        'Tap "Listen" to hear an answer out loud, and "Translate" to '
        'read it in another language.\n'
        'If the app says it does not have the answer, it means the '
        'database does not cover it yet — it will never make one up.',
  ),
  GuideSection(
    key: 'talk-listen',
    featureKey: 'voice',
    title: 'Talk & listen (voice and feelings)',
    keywords: 'voice speak listen microphone feelings emotion hear talk',
    body: 'You can talk to the app, and it can talk back — with '
        'feeling, like a person: warm, a chuckle, a sigh.\n'
        '1. Tap the microphone button next to any typing box.\n'
        '2. Say your words out loud. They appear as text.\n'
        '3. To hear an answer, tap Listen.\n'
        'In Settings you can pick your voice and choose how much '
        'feeling it uses: Calm, Gentle, Warm, Expressive, or '
        'Full-hearted.\n'
        'In Diagnostics, the "Hear the feelings" buttons let you hear '
        'each feeling in your picked voice, any time.\n'
        'If talking does not work on your device, typing always does '
        '— everything works the same typed.',
  ),
  GuideSection(
    key: 'translator',
    featureKey: 'translator',
    title: 'Translator',
    keywords: 'translate language spanish words message pack download',
    body: 'The Translator turns words and messages into another '
        'language, on this device.\n'
        '1. Open More, then Translator.\n'
        '2. Pick the language you are starting from, and the one you '
        'want.\n'
        '3. Type or speak the words, then tap Translate.\n'
        '4. Tap "Hear it" to hear the translation out loud.\n'
        'Some languages need a one-time download (a "language pack") '
        'before they work without internet. If a pack is missing, the '
        'screen says so and offers a Download button.\n'
        'Translated words are checked by the compliance checker too, '
        'in the final language — translation never gets a free pass.',
  ),
  GuideSection(
    key: 'talk-together',
    featureKey: 'conversation',
    title: 'Talk together (2-way translator)',
    keywords: 'conversation two way face to face interpret person speak both',
    body: 'Talk together is for talking face to face with someone who '
        'speaks another language. You take turns; the app interprets '
        'out loud.\n'
        '1. Open More, then "Talk together".\n'
        '2. Pick the two languages at the top.\n'
        '3. The first person taps their big button and talks. The app '
        'says it in the other language.\n'
        '4. The other person taps their button and replies.\n'
        'Typing works on both sides too, when speaking is not '
        'possible.\n'
        'Speaking works only for languages your device supports — the '
        'screen says so honestly when one is not supported.',
  ),
  GuideSection(
    key: 'write-post',
    featureKey: 'write-post',
    title: 'Write a post',
    keywords: 'post curiosity write draft generate facebook share',
    body: 'The post writer makes curiosity posts in the playbook '
        'style: a genuine question about everyday life that starts '
        'conversations. The product is never pitched in the post.\n'
        '1. Open More, then Posts.\n'
        '2. Pick a style, and (if you like) a product to steer the '
        'topic.\n'
        '3. Read the draft. Tap "Another version" for a different one, '
        'or edit the words yourself.\n'
        '4. The compliance check runs automatically — fix anything it '
        'flags.\n'
        '5. Tap Approve when you are happy with it.\n'
        'A post is never sent by the app. Approving just saves it to '
        'your queue.',
  ),
  GuideSection(
    key: 'schedule-post',
    featureKey: 'schedule-post',
    title: 'Schedule a post',
    keywords: 'schedule queue reminder time later calendar post when',
    body: 'Scheduling works like this: the app queues your post and '
        'reminds you at the time you pick. Then you share it yourself '
        'in one tap. (No app can post to a personal profile by '
        'itself — the reminder is the honest way it works.)\n'
        '1. Write and approve a post (see "Write a post").\n'
        '2. Tap "Approve & set reminder…" and pick a day and time.\n'
        '3. Pick where it will go: Facebook Page or Personal profile.\n'
        '4. At the time you picked, open the Queue tab and tap '
        '"Post now". The share sheet opens — you pick Facebook and '
        'post it yourself.\n'
        'You can reschedule or cancel any queued post in the Queue '
        'tab, and the Calendar shows your week of posts.',
  ),
  GuideSection(
    key: 'replies',
    featureKey: 'replies',
    title: 'Replies helper',
    keywords: 'reply comment message answer draft invite group send',
    body: 'When someone comments on your post or messages you, the '
        'Replies helper drafts an answer for you: a short answer from '
        'the database, plus an invite into the learning group.\n'
        '1. Copy their comment from Facebook.\n'
        '2. Open More, then Replies, and paste it in.\n'
        '3. Tap "Draft a reply", read it, and edit it if you like.\n'
        '4. Check the compliance results under the draft.\n'
        '5. Tap Copy or Share — then paste it and send it yourself '
        'from your own Facebook.\n'
        'The app has no Facebook connection, so it can never send a '
        'reply for you — and it never will without you tapping send.',
  ),
  GuideSection(
    key: 'compliance',
    featureKey: 'compliance',
    title: 'Check my words (compliance)',
    keywords: 'compliance check words claims safe rules medical scan flag',
    body: 'The compliance checker reads any words before they go out '
        'and flags wording that breaks the rules: medical claims '
        '(like "cures" or "treats"), promised results, and income '
        'claims.\n'
        '1. Open More, then "Compliance checker".\n'
        '2. Paste or dictate the words.\n'
        '3. Read the results: each flag explains why it is a problem '
        'and suggests a safer direction.\n'
        'The checker never changes your words for you — you fix them '
        'yourself, so nothing gets quietly rewritten.\n'
        'The same check runs automatically on posts, replies, fact '
        'cards, journey messages, and translated text.',
  ),
  GuideSection(
    key: 'fact-cards',
    featureKey: 'fact-cards',
    title: 'Fact cards',
    keywords: 'fact card picture share image product story post',
    body: 'A fact card is a shareable picture: the product\'s official '
        'photo, one official fact from its database entry, and one '
        'curiosity question.\n'
        '1. Open More, then "Fact cards".\n'
        '2. Pick a product.\n'
        '3. Look at the card and the compliance result under it.\n'
        '4. Tap "Export picture…" — the share sheet opens with the '
        'picture. Share it, or save it to this device from the sheet.\n'
        'Every fact on a card comes straight from the database entry, '
        'with its claim label printed on the card.',
  ),
  GuideSection(
    key: 'calendar',
    featureKey: 'calendar',
    title: 'Calendar',
    keywords: 'calendar week plan schedule posts rhythm best time',
    body: 'The Calendar shows your week: which days have a queued '
        'post, and suggested days for the next one.\n'
        '1. Open More, then "Content calendar".\n'
        '2. Tap a day with a post to open the queue.\n'
        '3. Tap a suggested empty day to draft a post for it.\n'
        'Suggestions come from the playbook\'s rhythm — a few '
        'question posts a week, mixed with ordinary life posts. They '
        'are labeled suggestions, not measured "best times".',
  ),
  GuideSection(
    key: 'pipeline',
    featureKey: 'pipeline',
    title: 'People I\'m following up (prospects)',
    keywords: 'prospects pipeline people follow up stages customer invited joined',
    body: 'Prospects is your private list of people you are talking '
        'with, and where each one is: Commented, Invited, Joined '
        'group, or Customer.\n'
        '1. Open More, then Prospects, and tap "Add a person".\n'
        '2. Tap a stage chip to move them along as things happen.\n'
        '3. Set a follow-up date so nobody is forgotten — due '
        'follow-ups show on the Today card.\n'
        '4. Use Done to clear a follow-up, or Snooze to move it 3 '
        'days.\n'
        'This list lives only on this device. It is never uploaded or '
        'shared anywhere.',
  ),
  GuideSection(
    key: 'journey',
    featureKey: 'journey',
    title: 'Customer journey (30 days)',
    keywords: 'customer journey 30 days check-in reorder journal day counter new customer',
    body: 'When someone becomes a customer, the Journey keeps their '
        'first 30 days on track: a day counter, check-ins on days 3, '
        '7 and 30, and a reorder nudge on day 25.\n'
        '1. Open More, then "Customer journey", and add the customer '
        'with their product and start date. Day 1 is the start date.\n'
        '2. When a check-in is due, tap "Draft check-in" — a warm '
        'message is written for you, checked for compliance. Copy or '
        'share it, and send it yourself.\n'
        '3. The journey shows the official general usage basics and '
        'points to LW Team Learning for detailed placement guidance '
        '— the app never carries placement protocols itself.\n'
        '4. Keep a private journal: one note per day, for your eyes '
        'only. Journal notes are stored only on this device — never '
        'synced, never shared.\n'
        '5. On day 25 the Today card counts the customer under '
        '"Reorders due" until you mark them reordered.',
  ),
  GuideSection(
    key: 'qr-kit',
    featureKey: 'qr-kit',
    title: 'My QR kit',
    keywords: 'qr code link referral kit events print one-pager share store link',
    body: 'Your QR kit turns your own referral link into a QR code '
        'people can scan, plus a printable one-page sheet for events.\n'
        '1. Open Settings and paste your own referral link (it must '
        'start with http:// or https://). It is stored only on this '
        'device.\n'
        '2. Open More, then "My QR kit" to see your code, your name, '
        'and your link in words.\n'
        '3. Tap "Share the one-pager…" to send the sheet — logo, QR '
        'code, your link, and a short fact about the company — to a '
        'printer app, Files, or anywhere the share sheet offers.\n'
        'The link is yours: the app ships with nobody\'s link built '
        'in.',
  ),
  GuideSection(
    key: 'roleplay',
    featureKey: 'roleplay',
    title: 'Practice conversations (roleplay)',
    keywords: 'practice roleplay prospect skeptical coach rehearse conversation objection',
    body: 'Practice mode lets you rehearse talking with a skeptical '
        'prospect before the real thing. The app plays the prospect — '
        'it is a built-in practice partner, not a real person.\n'
        '1. Open More, then "Practice conversations", and pick a '
        'person to practice with.\n'
        '2. The prospect speaks their worry out loud. Answer by '
        'talking (tap the microphone) or typing.\n'
        '3. After each answer, the coach checks your words: anything '
        'the compliance checker flags, which key points you covered, '
        'and a stronger way to say it — taken from the database '
        'answers.\n'
        '4. Pick a language to practice in another language: the '
        'prospect speaks it, and you answer in it.\n'
        'There are no scores that leave this device. It is just '
        'practice.',
  ),
  GuideSection(
    key: 'demo',
    featureKey: 'demo',
    title: 'Demo mode ("Show me what you can do")',
    keywords: 'demo show me tour showcase 60 second try sample',
    body: 'The demo is a one-minute guided tour where the app shows '
        'its real features with sample questions.\n'
        '1. On the first screen (Today), tap "Show me what you can '
        'do".\n'
        '2. Follow along: a spoken answer, a translation, a written '
        'post, and a fact card — each one really happening, not a '
        'recording.\n'
        '3. Tap Next to move on, or Exit to stop at any time.\n'
        'It works fully offline. If something cannot run on your '
        'device (like voice typing), the step says so and the demo '
        'carries on.\n'
        'It is a good way to show a friend what the app does.',
  ),
  GuideSection(
    key: 'presentation',
    featureKey: 'presentation',
    title: 'Presentation mode',
    keywords: 'presentation slideshow products meeting tv big screen slides captions',
    body: 'Presentation mode is a full-screen slideshow of products '
        'for a coffee meeting, a home party, or a TV.\n'
        '1. Open More, then "Presentation mode" and pick products '
        '(the best-known ones are picked for you).\n'
        '2. Tap Start. Each slide shows the official picture, the '
        'product name, and a few official facts in big, clear type.\n'
        '3. Tap the right side for the next slide, the left side to '
        'go back — or say "next" / "back" out loud if voice control '
        'works on your device.\n'
        '4. Use the language button to show the slide\'s words in '
        'another language.\n'
        'The last slide shows your QR code if you have set up your QR '
        'kit — a natural way to end.',
  ),
  GuideSection(
    key: 'settings',
    featureKey: 'settings',
    title: 'Settings in plain words',
    keywords: 'settings name voice feeling language pack destination quick replies referral',
    body: 'Settings holds your personal choices. Everything is stored '
        'only on this device.\n'
        'Your name: the name the app greets you with.\n'
        'Usual post destination: where your posts usually go '
        '(Facebook Page or Personal profile). You can still change it '
        'for each post.\n'
        'Your quick replies: short answers you write and approve '
        'yourself, for one-tap use in Replies.\n'
        'How much feeling: how expressive the voice sounds.\n'
        'Voice: which voice speaks. The Kokoro voice file is a '
        'download — until it is downloaded, the device voice speaks, '
        'and the app says so.\n'
        'Languages: the language chat answers translate into, and the '
        'language packs on this device.\n'
        'Your referral link: the link your QR kit is built from.',
  ),
  GuideSection(
    key: 'updating',
    featureKey: 'updating',
    title: 'Updating the app',
    keywords: 'update new version install upgrade notification',
    body: 'When a new version of the app is ready, the app tells you '
        'once — quietly, never with pop-ups every day.\n'
        '1. Tap the update note (or the Update button) when you see '
        'it.\n'
        '2. Follow the download and install steps.\n'
        '3. Your posts, people, customers and settings stay on your '
        'device — updating does not erase them.\n'
        'Updates are never forced and never install by themselves. '
        'You always tap to apply one.',
  ),
  GuideSection(
    key: 'troubleshooting',
    featureKey: 'troubleshooting',
    title: 'What to do when… (troubleshooting)',
    keywords: 'trouble problem broken help mic voice translation download queue cloud fix',
    body: 'The microphone does not hear me: check that the app has '
        'microphone permission in your device settings (Diagnostics '
        'shows the current state). Typing always works instead.\n'
        'The voice sounds wrong, or there is no voice: the app uses '
        'the device voice until the Kokoro voice file is downloaded '
        'in Settings. Try the "Hear the feelings" test in '
        'Diagnostics to hear how it sounds right now.\n'
        'A translation needs a download: some languages need their '
        'language pack first. Connect to the internet, open '
        'Translator or Settings, and tap Download for that language. '
        'After that it works offline.\n'
        'A post will not queue: read the compliance flags on the '
        'post. Fix the flagged words, or — if you have read them and '
        'choose to go ahead — use the override button. A post also '
        'needs approving before it can queue.\n'
        'The app says cloud isn\'t set up: that is normal. Cloud help '
        'is an extra that is not part of this version. Everything '
        'else works from the built-in database, offline.\n'
        'Something else looks wrong: open Diagnostics, tap "Run '
        'self-tests", and take a screenshot of that screen to show '
        'whoever helps you.',
  ),
  GuideSection(
    key: 'about',
    featureKey: 'about',
    title: 'About this app',
    keywords: 'about who made independent official version',
    body: 'LifeWave AI helps Brand Partners answer questions, write '
        'posts, and look after people, using a built-in database of '
        'official LifeWave information in plain words.\n'
        '${AppInfo.independentToolLine}\n'
        'Group training material is never copied into this app. '
        'Where deeper teaching lives in the learning groups, the app '
        'points you there instead.\n'
        'Your own data — your name, posts, people, customers and '
        'journal — lives only on your device.',
  ),
];

/// The section for a key, or null.
GuideSection? guideSectionByKey(String key) {
  for (final s in kGuideSections) {
    if (s.key == key) return s;
  }
  return null;
}

/// Feature key -> section (the coverage invariant the tests enforce).
GuideSection? guideSectionForFeature(String featureKey) {
  for (final s in kGuideSections) {
    if (s.featureKey == featureKey) return s;
  }
  return null;
}

/// Searches the guide with the same tokenization as database
/// retrieval. Returns sections best-first (title hits weigh most).
List<GuideSection> searchGuide(String query, {int limit = 5}) {
  final tokens = Retrieval.tokenize(query).toSet().toList();
  if (tokens.isEmpty) return const [];
  final scored = <(GuideSection, int)>[];
  for (final s in kGuideSections) {
    final titleTokens = Retrieval.tokenize(s.title);
    final bodyTokens = Retrieval.tokenize(s.searchableText);
    var score = 0;
    for (final t in tokens) {
      if (titleTokens.contains(t)) score += 10;
      var hits = 0;
      for (final b in bodyTokens) {
        if (b == t) hits++;
      }
      score += (hits > 3 ? 3 : hits) * 2;
    }
    if (score > 0) scored.add((s, score));
  }
  scored.sort((a, b) {
    final byScore = b.$2.compareTo(a.$2);
    if (byScore != 0) return byScore;
    return a.$1.title.compareTo(b.$1.title);
  });
  return scored.take(limit).map((e) => e.$1).toList(growable: false);
}

/// The 6 most important first steps, for the quick-start one-pager.
const List<String> kQuickStartSteps = [
  'Ask a question: tap Chat, type or say your question, and read the answer with its source label.',
  'Hear it out loud: tap Listen on any answer. Pick your voice and feeling level in Settings.',
  'Write a post: open More → Posts, pick a style, approve the draft, and set a reminder.',
  'Answer a comment: open More → Replies, paste their words, draft a reply, copy it, and send it yourself.',
  'Add your link: put your referral link in Settings, then open More → My QR kit for your QR code.',
  'Get help any time: tap the ? button on any screen, or open the Guide in More.',
];

/// Per-screen help registry (SPEC §7.6): screen key -> guide section
/// key. Every major screen's app bar carries a help (?) button that
/// opens its section. Audited in tests: every key here must resolve
/// to a real section.
const Map<String, String> kScreenHelpSections = {
  'home': 'getting-started',
  'catalog': 'ask-question',
  'chat': 'ask-question',
  'posts': 'write-post',
  'replies': 'replies',
  'compliance': 'compliance',
  'fact-cards': 'fact-cards',
  'calendar': 'schedule-post',
  'prospects': 'pipeline',
  'translator': 'translator',
  'conversation': 'talk-together',
  'settings': 'settings',
  'diagnostics': 'troubleshooting',
  'about': 'about',
  'roleplay': 'roleplay',
  'demo': 'demo',
  'presentation': 'presentation',
  'journey': 'journey',
  'qr-kit': 'qr-kit',
  'guide': 'getting-started',
};
