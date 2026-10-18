import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/social.dart';
import '../services/emotion.dart';
import '../services/m2_services.dart';
import '../services/qr_kit.dart';
import '../services/social_store.dart';
import '../services/translation_service.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/social_widgets.dart' show kDestinationExplainer;
import 'guide_screen.dart';

/// Shared preference keys. Per-user data, stored on this device only —
/// never shipped, never baked into the app (SPEC §1/§4).
abstract class PrefKeys {
  static const String displayName = 'display_name';
  static const String welcomeDismissed = 'welcome_dismissed';
  // M2 — voice & language (per-user, on-device).
  static const String emotionLevel = 'emotion_level';
  static const String voiceKey = 'voice_key'; // 'engine|id|name'
  static const String chatLanguage = 'chat_language'; // code, e.g. 'es'
  // M3 — the user's usual post destination (per-post picks can differ).
  static const String defaultDestination = 'default_destination';
  // M4 — first-run tour state + the user's own referral link (QR kit).
  static const String tourSeen = 'tour_seen';
  static const String referralLink = 'referral_link';

  static VoiceInfo? decodeVoice(String? raw) {
    if (raw == null) return null;
    final parts = raw.split('|');
    if (parts.length != 3) return null;
    return VoiceInfo(engineId: parts[0], id: parts[1], name: parts[2]);
  }

  static String encodeVoice(VoiceInfo v) => '${v.engineId}|${v.id}|${v.name}';
}

/// Settings: display name (M1) + voice & emotions, languages (M2).
/// Every control explains itself, saves with feedback (standing UX rule).
class SettingsScreen extends StatefulWidget {
  final String? initialName;
  final ValueChanged<String?> onNameChanged;
  final M2Services? services;
  final EmotionLevel initialEmotionLevel;
  final ValueChanged<EmotionLevel>? onEmotionLevelChanged;
  final VoiceInfo? initialVoice;
  final ValueChanged<VoiceInfo?>? onVoiceChanged;
  final AppLanguage initialChatLanguage;
  final ValueChanged<AppLanguage>? onChatLanguageChanged;
  final SocialStore? socialStore;
  final String? initialReferralLink;
  final ValueChanged<String?>? onReferralLinkChanged;

  /// M5 updater row: honest last-check label + actions (built by main
  /// from the UpdateService). Null label = section hidden.
  final String? updateStatusLabel;
  final String? updateAvailableVersionName;
  final VoidCallback? onCheckForUpdate;
  final VoidCallback? onOpenUpdate;
  final VoidCallback? onDismissUpdate;
  const SettingsScreen({
    super.key,
    required this.initialName,
    required this.onNameChanged,
    this.services,
    this.initialEmotionLevel = EmotionLevel.warm,
    this.onEmotionLevelChanged,
    this.initialVoice,
    this.onVoiceChanged,
    this.initialChatLanguage = const AppLanguage('es', 'Spanish'),
    this.onChatLanguageChanged,
    this.socialStore,
    this.initialReferralLink,
    this.onReferralLinkChanged,
    this.updateStatusLabel,
    this.updateAvailableVersionName,
    this.onCheckForUpdate,
    this.onOpenUpdate,
    this.onDismissUpdate,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.initialName ?? '');
  late final TextEditingController _linkController =
      TextEditingController(text: widget.initialReferralLink ?? '');
  late EmotionLevel _level = widget.initialEmotionLevel;
  late VoiceInfo? _voice = widget.initialVoice;
  late AppLanguage _chatLanguage = widget.initialChatLanguage;
  List<VoiceInfo> _voices = const [];
  List<LanguagePack> _packs = const [];
  bool _packsBusy = false;
  PostDestination _destination = PostDestination.personalProfile;

  @override
  void initState() {
    super.initState();
    _loadVoicesAndPacks();
    _loadDestination();
  }

  Future<void> _loadDestination() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(PrefKeys.defaultDestination);
      if (mounted && raw != null) {
        setState(() => _destination = PostDestination.fromName(raw));
      }
    } catch (_) {
      // Default applies.
    }
  }

  Future<void> _setDestination(PostDestination d) async {
    setState(() => _destination = d);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.defaultDestination, d.name);
    _feedback('New posts will start out headed to your ${d.label}. '
        'You can still change it for each post.');
  }

  Future<void> _loadVoicesAndPacks() async {
    final services = widget.services;
    if (services == null) return;
    await services.voice.kokoroEngine.modelManager.refresh();
    final voices = await services.voice.listVoices();
    final packs = await services.translation.listPacks();
    if (!mounted) return;
    setState(() {
      _voices = voices;
      _packs = packs;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  /// Saves the referral link after validation (M4 QR kit). An empty
  /// field clears the link. An invalid link is NOT saved — the user
  /// hears exactly what is wrong with it.
  Future<void> _saveReferralLink() async {
    final raw = _linkController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    if (raw.isEmpty) {
      await prefs.remove(PrefKeys.referralLink);
      widget.onReferralLinkChanged?.call(null);
      _feedback('Referral link cleared. Your QR kit will ask for a '
          'link again.');
      return;
    }
    final problem = referralLinkProblem(raw);
    if (problem != null) {
      _feedback(problem);
      return;
    }
    await prefs.setString(PrefKeys.referralLink, raw);
    widget.onReferralLinkChanged?.call(raw);
    _feedback('Referral link saved on this device. Your QR code is '
        'ready in "My QR kit" (in More).');
  }

  void _feedback(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    if (name.isEmpty) {
      await prefs.remove(PrefKeys.displayName);
    } else {
      await prefs.setString(PrefKeys.displayName, name);
    }
    widget.onNameChanged(name.isEmpty ? null : name);
    _feedback('Settings saved on this device.');
  }

  Future<void> _setLevel(EmotionLevel level) async {
    setState(() => _level = level);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.emotionLevel, level.name);
    widget.onEmotionLevelChanged?.call(level);
    _feedback('Feeling set to ${level.label}. Try the emotion self-test '
        'in Diagnostics to hear it.');
  }

  Future<void> _setVoice(VoiceInfo? voice) async {
    setState(() => _voice = voice);
    final prefs = await SharedPreferences.getInstance();
    if (voice == null) {
      await prefs.remove(PrefKeys.voiceKey);
    } else {
      await prefs.setString(PrefKeys.voiceKey, PrefKeys.encodeVoice(voice));
    }
    widget.onVoiceChanged?.call(voice);
    _feedback(voice == null
        ? 'Voice set to the device default.'
        : 'Voice set to ${voice.name}.');
  }

  /// The list instance matching the stored selection (VoiceInfo has no
  /// value equality, so match on the persisted key form).
  VoiceInfo? _matchingVoice() {
    final current = _voice;
    if (current == null) return null;
    final key = PrefKeys.encodeVoice(current);
    for (final v in _voices) {
      if (PrefKeys.encodeVoice(v) == key) return v;
    }
    return null;
  }

  Future<void> _setChatLanguage(AppLanguage lang) async {
    setState(() => _chatLanguage = lang);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.chatLanguage, lang.code);
    widget.onChatLanguageChanged?.call(lang);
    _feedback('Chat answers will translate into ${lang.name}.');
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), actions: [HelpButton(screenKey: 'settings', brand: null, services: widget.services, db: null, share: null, emotionLevel: widget.initialEmotionLevel)],),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Your name',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'The name the app greets you with. It is stored only on this '
            'device — it is never sent anywhere and never built into the '
            'app for anyone else.',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Your display name',
              hintText: 'For example: Alex',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save settings'),
          ),
          const SizedBox(height: 28),
          Text('Your referral link (QR kit)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Your own LifeWave store link. The app turns it into your '
            'QR code and printable one-pager (More → My QR kit). It is '
            'stored only on this device — the app ships with nobody\'s '
            'link built in.',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _linkController,
            decoration: const InputDecoration(
              labelText: 'Your referral link',
              hintText: 'https://lifewave.com/yourstore',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _saveReferralLink,
            icon: const Icon(Icons.qr_code_outlined, size: 18),
            label: const Text('Save link & build my QR kit'),
          ),
          if (widget.updateStatusLabel != null) ...[
            const SizedBox(height: 28),
            Text('App updates',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'The app checks the app\'s GitHub page for a newer '
              'version at most once a day. Updates are never forced '
              'and never install themselves — you tap Update and '
              'install it yourself.',
            ),
            const SizedBox(height: 8),
            Text('Last check: ${widget.updateStatusLabel}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (widget.onCheckForUpdate != null)
                  OutlinedButton.icon(
                    onPressed: widget.onCheckForUpdate,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Check now'),
                  ),
                if (widget.updateAvailableVersionName != null &&
                    widget.onOpenUpdate != null)
                  FilledButton.icon(
                    onPressed: widget.onOpenUpdate,
                    icon: const Icon(Icons.system_update_outlined,
                        size: 18),
                    label: Text(
                        'Update to version ${widget.updateAvailableVersionName}'),
                  ),
                if (widget.updateAvailableVersionName != null &&
                    widget.onDismissUpdate != null)
                  TextButton(
                    onPressed: widget.onDismissUpdate,
                    child: const Text('Dismiss this version'),
                  ),
              ],
            ),
          ],
          if (widget.socialStore != null) ...[
            const SizedBox(height: 28),
            Text('Posts and replies',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'Where your posts usually go, and the quick replies you '
              'have written and approved for yourself. Everything here '
              'is stored only on this device.',
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<PostDestination>(
              value: _destination,
              decoration: const InputDecoration(
                labelText: 'Usual post destination',
                border: OutlineInputBorder(),
              ),
              items: PostDestination.values
                  .map((d) =>
                      DropdownMenuItem(value: d, child: Text(d.label)))
                  .toList(),
              onChanged: (v) {
                if (v != null) _setDestination(v);
              },
            ),
            const SizedBox(height: 4),
            const Text(kDestinationExplainer,
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 16),
            _QuickTemplatesSection(
              store: widget.socialStore!,
              onFeedback: _feedback,
            ),
          ],
          if (services != null) ...[
            const SizedBox(height: 28),
            Text('Voice and feelings',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'How spoken answers sound. Feelings are made fresh in the '
              'voice you pick, every time — never a recording of someone '
              'else.',
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<EmotionLevel>(
              value: _level,
              decoration: const InputDecoration(
                labelText: 'How much feeling',
                border: OutlineInputBorder(),
              ),
              items: EmotionLevel.values
                  .map((l) =>
                      DropdownMenuItem(value: l, child: Text(l.label)))
                  .toList(),
              onChanged: (v) {
                if (v != null) _setLevel(v);
              },
            ),
            const SizedBox(height: 4),
            const Text(
              'Calm is the quietest; Full-hearted is the most expressive. '
              'Warm is the standard setting.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<VoiceInfo?>(
              value: _matchingVoice(),
              decoration: const InputDecoration(
                labelText: 'Voice',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<VoiceInfo?>(
                  value: null,
                  child: Text('Device default voice'),
                ),
                ..._voices.map((v) => DropdownMenuItem<VoiceInfo?>(
                      value: v,
                      child: Text(
                        '${v.name}${v.engineId == 'kokoro' ? ' (Kokoro)' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
              ],
              onChanged: _setVoice,
            ),
            const SizedBox(height: 4),
            Text(
              'Engine in use: ${services.voice.activeEngineLabel}.',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            _KokoroModelCard(services: services, onChanged: _loadVoicesAndPacks),
            const SizedBox(height: 28),
            Text('Languages',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'The language the Translate button in Chat uses, and the '
              'on-device language packs. Packs are downloaded once and '
              'then work offline. Pack sizes are managed by the device '
              'system, so the app shows which packs you have rather '
              'than a size it cannot measure.',
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<AppLanguage>(
              value: _chatLanguage,
              decoration: const InputDecoration(
                labelText: 'Translate chat answers into',
                border: OutlineInputBorder(),
              ),
              items: kAppLanguages
                  .map((l) =>
                      DropdownMenuItem(value: l, child: Text(l.name)))
                  .toList(),
              onChanged: (v) {
                if (v != null) _setChatLanguage(v);
              },
            ),
            const SizedBox(height: 12),
            if (_packs.isEmpty)
              const Text('Language pack list is loading…')
            else
              for (final pack in _packs)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    pack.downloaded
                        ? Icons.check_circle_outline
                        : Icons.cloud_download_outlined,
                    color: LwColors.primary,
                  ),
                  title: Text(pack.language.name),
                  subtitle: Text(pack.downloaded
                      ? 'Downloaded — works offline'
                      : 'Not downloaded'),
                  trailing: pack.downloaded
                      ? TextButton(
                          onPressed: _packsBusy
                              ? null
                              : () async {
                                  setState(() => _packsBusy = true);
                                  await services.translation
                                      .deletePack(pack.language.code);
                                  await _loadVoicesAndPacks();
                                  if (mounted) {
                                    setState(() => _packsBusy = false);
                                  }
                                  _feedback(
                                      'The ${pack.language.name} pack was removed.');
                                },
                          child: const Text('Delete'),
                        )
                      : TextButton(
                          onPressed: _packsBusy
                              ? null
                              : () async {
                                  setState(() => _packsBusy = true);
                                  final ok = await services.translation
                                      .downloadPack(pack.language.code);
                                  await _loadVoicesAndPacks();
                                  if (mounted) {
                                    setState(() => _packsBusy = false);
                                  }
                                  _feedback(ok
                                      ? 'The ${pack.language.name} pack is downloaded.'
                                      : 'That pack could not be downloaded. Check your internet and try again.');
                                },
                          child: const Text('Download'),
                        ),
                ),
          ],
        ],
      ),
    );
  }
}

/// Pre-approved quick-reply templates (SPEC §7.2): the user writes
/// their own templates here and approves the ones they trust; approved
/// templates appear as one-tap inserts on the Replies screen. A
/// template still only ever goes out on the user's own tap.
class _QuickTemplatesSection extends StatelessWidget {
  final SocialStore store;
  final void Function(String) onFeedback;
  const _QuickTemplatesSection(
      {required this.store, required this.onFeedback});

  Future<void> _add(BuildContext context) async {
    final titleController = TextEditingController();
    final textController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New quick reply'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Short name',
                  hintText: 'For example: Price question',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                decoration: const InputDecoration(
                  labelText: 'The reply text',
                  hintText: 'The exact words, in your own voice…',
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
              ),
              const SizedBox(height: 8),
              const Text(
                'New templates start un-approved. Review the words, '
                'then switch on "Approved" when you are happy for this '
                'to be a one-tap reply.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save template'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final title = titleController.text.trim();
    final text = textController.text.trim();
    if (title.isEmpty || text.isEmpty) {
      onFeedback('A name and the reply text are both needed — nothing '
          'was saved.');
      return;
    }
    await store.addTemplate(title: title, text: text);
    onFeedback('Template "$title" saved. Approve it below to use it '
        'from the Replies screen.');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your quick replies',
                style: Theme.of(context).textTheme.titleSmall),
            const Text(
              'Your own pre-written answers to common questions. Only '
              'approved ones appear on the Replies screen.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            if (store.quickTemplates.isEmpty)
              const Text('No quick replies yet — add your first one below.')
            else
              for (final t in store.quickTemplates)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text(t.title),
                    subtitle: Text(t.text,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: t.approved,
                              onChanged: (v) async {
                                await store.setTemplateApproved(t, v);
                                onFeedback(v
                                    ? '"${t.title}" is approved for '
                                        'one-tap use.'
                                    : '"${t.title}" is no longer '
                                        'approved.');
                              },
                            ),
                            const Text('Approved',
                                style: TextStyle(fontSize: 10)),
                          ],
                        ),
                        IconButton(
                          tooltip: 'Delete this template',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await store.deleteTemplate(t);
                            onFeedback('Template "${t.title}" deleted.');
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () => _add(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add a quick reply'),
            ),
          ],
        );
      },
    );
  }
}

class _KokoroModelCard extends StatefulWidget {
  final M2Services services;
  final VoidCallback onChanged;
  const _KokoroModelCard({required this.services, required this.onChanged});

  @override
  State<_KokoroModelCard> createState() => _KokoroModelCardState();
}

class _KokoroModelCardState extends State<_KokoroModelCard> {
  bool _busy = false;

  VoiceModelManager get _manager =>
      widget.services.voice.kokoroEngine.modelManager;

  @override
  Widget build(BuildContext context) {
    final manager = _manager;
    return Card(
      color: LwColors.tint,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kokoro voice file (the Scout voice)',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(KokoroEngine.aboutText),
            if (!widget.services.voice.kokoroEngine.isAvailable) ...[
              const SizedBox(height: 6),
              Text(widget.services.voice.kokoroEngine.unavailableReason),
            ],
            const SizedBox(height: 8),
            Text('Voice file: ${manager.stateLabel}'
                '${manager.downloadedBytes > 0 ? ' (${(manager.downloadedBytes / 1048576).toStringAsFixed(0)} MB)' : ''}'),
            if (manager.state == VoiceModelState.downloading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(value: manager.progress),
              ),
            if (manager.state == VoiceModelState.error)
              Text(manager.errorMessage,
                  style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (manager.state != VoiceModelState.ready)
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            await manager.download();
                            if (mounted) setState(() => _busy = false);
                            widget.onChanged();
                          },
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Download voice file (~132 MB)'),
                  ),
                if (manager.state == VoiceModelState.ready ||
                    manager.state == VoiceModelState.error)
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            await manager.deleteModel();
                            if (mounted) setState(() => _busy = false);
                            widget.onChanged();
                          },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete voice file'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// About: logo, versions, and the SPEC §7.12 independent-tool line.
class AboutScreen extends StatelessWidget {
  final String? logoAssetPath;
  final int dbVersion;
  final int entryCount;
  const AboutScreen({
    super.key,
    required this.logoAssetPath,
    required this.dbVersion,
    required this.entryCount,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About'), actions: const [HelpButton(screenKey: 'about')]),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(child: LogoImage(assetPath: logoAssetPath, height: 48)),
          const SizedBox(height: 16),
          Center(
            child: Text(AppInfo.appName,
                style: Theme.of(context).textTheme.headlineSmall),
          ),
          const SizedBox(height: 8),
          const Center(child: Text(AppInfo.versionLabel)),
          Center(child: Text('Database version $dbVersion — $entryCount entries')),
          const SizedBox(height: 24),
          const Card(
            color: LwColors.tint,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                AppInfo.independentToolLine,
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'This app answers from its built-in database of official '
            'LifeWave information, summarized in plain words. Group '
            'training material is never copied into the app — entries '
            'point you to the groups where it lives.',
          ),
        ],
      ),
    );
  }
}

/// The "More" tab: Diagnostics, Settings, About, translators — each
/// with a plain subtitle explaining what it does (UX rule: every
/// control explains itself; no dead buttons).
class MoreScreen extends StatelessWidget {
  final VoidCallback onOpenDiagnostics;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAbout;
  final VoidCallback? onOpenTranslator;
  final VoidCallback? onOpenConversation;
  final VoidCallback? onOpenPosts;
  final VoidCallback? onOpenReplies;
  final VoidCallback? onOpenCompliance;
  final VoidCallback? onOpenFactCards;
  final VoidCallback? onOpenCalendar;
  final VoidCallback? onOpenProspects;
  final VoidCallback? onOpenGuide;
  final VoidCallback? onOpenRoleplay;
  final VoidCallback? onOpenDemo;
  final VoidCallback? onOpenPresentation;
  final VoidCallback? onOpenJourney;
  final VoidCallback? onOpenQrKit;
  const MoreScreen({
    super.key,
    required this.onOpenDiagnostics,
    required this.onOpenSettings,
    required this.onOpenAbout,
    this.onOpenTranslator,
    this.onOpenConversation,
    this.onOpenPosts,
    this.onOpenReplies,
    this.onOpenCompliance,
    this.onOpenFactCards,
    this.onOpenCalendar,
    this.onOpenProspects,
    this.onOpenGuide,
    this.onOpenRoleplay,
    this.onOpenDemo,
    this.onOpenPresentation,
    this.onOpenJourney,
    this.onOpenQrKit,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (onOpenPosts != null)
            _MoreTile(
              icon: Icons.auto_awesome_outlined,
              title: 'Posts',
              subtitle:
                  'Write curiosity posts, check them, and queue reminders — you share them yourself',
              onTap: onOpenPosts!,
            ),
          if (onOpenReplies != null)
            _MoreTile(
              icon: Icons.reply_outlined,
              title: 'Replies',
              subtitle:
                  'Draft replies to comments with a group invite — you send them yourself',
              onTap: onOpenReplies!,
            ),
          if (onOpenCompliance != null)
            _MoreTile(
              icon: Icons.fact_check_outlined,
              title: 'Compliance checker',
              subtitle:
                  'Check any text for medical claims and restricted wording before it goes out',
              onTap: onOpenCompliance!,
            ),
          if (onOpenFactCards != null)
            _MoreTile(
              icon: Icons.image_outlined,
              title: 'Fact cards',
              subtitle:
                  'Shareable picture cards: one official fact + one curiosity question',
              onTap: onOpenFactCards!,
            ),
          if (onOpenCalendar != null)
            _MoreTile(
              icon: Icons.calendar_month_outlined,
              title: 'Content calendar',
              subtitle:
                  'Your week of queued posts, with playbook rhythm suggestions',
              onTap: onOpenCalendar!,
            ),
          if (onOpenProspects != null)
            _MoreTile(
              icon: Icons.people_outline,
              title: 'Prospects',
              subtitle:
                  'Commented → invited → joined → customer, with follow-ups — private on this device',
              onTap: onOpenProspects!,
            ),
          if (onOpenJourney != null)
            _MoreTile(
              icon: Icons.route_outlined,
              title: 'Customer journey',
              subtitle:
                  '30-day check-ins, private journal and reorder nudges for each customer',
              onTap: onOpenJourney!,
            ),
          if (onOpenRoleplay != null)
            _MoreTile(
              icon: Icons.school_outlined,
              title: 'Practice conversations',
              subtitle:
                  'Rehearse with a skeptical practice prospect — the coach reviews your answers',
              onTap: onOpenRoleplay!,
            ),
          if (onOpenDemo != null)
            _MoreTile(
              icon: Icons.play_circle_outline,
              title: 'Demo — show me what you can do',
              subtitle:
                  'A 60-second guided tour where the real features run with sample questions',
              onTap: onOpenDemo!,
            ),
          if (onOpenPresentation != null)
            _MoreTile(
              icon: Icons.slideshow_outlined,
              title: 'Presentation mode',
              subtitle:
                  'Full-screen product slideshow with official facts — for meetings or a TV',
              onTap: onOpenPresentation!,
            ),
          if (onOpenQrKit != null)
            _MoreTile(
              icon: Icons.qr_code_outlined,
              title: 'My QR kit',
              subtitle:
                  'Your referral link as a QR code plus a printable one-pager',
              onTap: onOpenQrKit!,
            ),
          if (onOpenGuide != null)
            _MoreTile(
              icon: Icons.menu_book_outlined,
              title: 'Guide',
              subtitle:
                  'Every feature explained in plain words — search it or ask it out loud',
              onTap: onOpenGuide!,
            ),
          if (onOpenTranslator != null)
            _MoreTile(
              icon: Icons.translate,
              title: 'Translator',
              subtitle: 'Translate words and messages into another language',
              onTap: onOpenTranslator!,
            ),
          if (onOpenConversation != null)
            _MoreTile(
              icon: Icons.people_outline,
              title: 'Talk together (2-way translator)',
              subtitle:
                  'Talk face to face in two languages — the app interprets out loud',
              onTap: onOpenConversation!,
            ),
          _MoreTile(
            icon: Icons.health_and_safety_outlined,
            title: 'Diagnostics',
            subtitle:
                'Check the app is working: versions, database, self-tests',
            onTap: onOpenDiagnostics,
          ),
          _MoreTile(
            icon: Icons.settings_outlined,
            title: 'Settings',
            subtitle: 'Your name, voice, feelings and languages, on this device',
            onTap: onOpenSettings,
          ),
          _MoreTile(
            icon: Icons.info_outline,
            title: 'About',
            subtitle: 'What this app is, its version, and who made it',
            onTap: onOpenAbout,
          ),
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: LwColors.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
