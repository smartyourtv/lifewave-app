import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'screens/calendar_screen.dart';
import 'screens/catalog_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/compliance_screen.dart';
import 'screens/demo_screen.dart';
import 'screens/diagnostics_screen.dart';
import 'screens/fact_cards_screen.dart';
import 'screens/guide_screen.dart';
import 'screens/home_screen.dart';
import 'screens/journey_screen.dart';
import 'screens/posts_screen.dart';
import 'screens/presentation_screen.dart';
import 'screens/prospects_screen.dart';
import 'screens/qr_kit_screen.dart';
import 'screens/replies_screen.dart';
import 'screens/roleplay_screen.dart';
import 'screens/settings_about.dart';
import 'screens/tour_screen.dart';
import 'screens/translator_screens.dart';
import 'services/brand_assets.dart';
import 'services/cloud_escalation.dart';
import 'services/crash_reporter.dart';
import 'services/emotion.dart';
import 'services/knowledge_db.dart';
import 'services/local_store.dart';
import 'services/m2_services.dart';
import 'services/reminder_service.dart';
import 'services/self_repair.dart';
import 'services/share_service.dart';
import 'services/social_store.dart';
import 'services/translation_service.dart';
import 'services/update_service.dart';
import 'services/voice_service.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/update_banner.dart';
import 'widgets/social_widgets.dart';

void main() {
  // Standing crash-report rule (v1.1.1): the whole app runs inside a
  // Zone guard and the crash handlers are installed BEFORE runApp, so
  // even a crash during startup leaves its report — first in the app's
  // own storage, with a copy mirrored to the Downloads folder. Reports
  // are never uploaded anywhere (see services/crash_reporter.dart).
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await CrashReporter.install();
    runApp(const LifewaveApp());
  }, (error, stack) {
    CrashReporter.recordZoneError(error, stack);
  });
}

/// App root. First route is the branded splash while the database, brand
/// assets and on-device preferences load; then the main shell. If the
/// database fails to load, the app fails CLOSED to a plain-language error
/// screen (never a crash, never a half-loaded database).
class LifewaveApp extends StatefulWidget {
  const LifewaveApp({super.key});

  @override
  State<LifewaveApp> createState() => _LifewaveAppState();
}

class _LoadedData {
  final KnowledgeDb db;
  final BrandAssets brand;
  final String? displayName;
  final bool welcomeDismissed;
  final EmotionLevel emotionLevel;
  final VoiceInfo? voice;
  final AppLanguage chatLanguage;
  final SocialStore socialStore;

  /// M4: first-run tour state + the user's own referral link.
  final bool tourSeen;
  final String? referralLink;

  /// M5: the updater (GitHub version.json check, standing rule).
  final UpdateService updateService;
  const _LoadedData({
    required this.db,
    required this.brand,
    required this.displayName,
    required this.welcomeDismissed,
    required this.emotionLevel,
    required this.voice,
    required this.chatLanguage,
    required this.socialStore,
    required this.tourSeen,
    required this.referralLink,
    required this.updateService,
  });
}

class _LifewaveAppState extends State<LifewaveApp> {
  late Future<_LoadedData> _loadFuture;
  int _loadAttempt = 0;

  /// Lets a tapped post reminder open the queue from anywhere.
  final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();

  /// Set once the shell has built its M3 dependency bundle; the
  /// reminder-tap handler uses it (taps can only arrive after that).
  SocialDeps? _socialDeps;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  Future<_LoadedData> _load() async {
    // Keep the splash visible briefly so it reads as a splash, not a flash.
    final splashMin = Future<void>.delayed(const Duration(milliseconds: 700));
    KnowledgeDb? loadedDb;
    try {
      loadedDb = await KnowledgeDb.load();
    } catch (e) {
      // Self-repair (standing rule): the database is bundled read-only
      // assets, so the restore path is a fresh load from the bundle —
      // one automatic attempt, verified by a real entry count, and the
      // outcome is logged either way. If the bundle itself is damaged
      // there is no state repair to make: startup still fails CLOSED
      // to the plain-language error screen below.
      final repaired = await SelfRepair.attempt(
        area: 'Knowledge database',
        problem: 'The knowledge database could not be opened.',
        evidence: 'The first open failed: $e',
        repair: () async {
          loadedDb = await KnowledgeDb.load();
        },
        verify: () async => (loadedDb?.entryCount ?? 0) > 0,
      );
      if (!repaired) rethrow;
    }
    final db = loadedDb!;
    final brand = await BrandAssets.load();
    // M3 local stores: the user's own posts/replies/prospects, loaded
    // from the app-private documents file. A corrupt file degrades to
    // empty lists + a Diagnostics-visible warning — never a crash, so
    // this load sits OUTSIDE the fail-closed database path on purpose.
    final reminders = LocalNotificationsReminderScheduler();
    final socialStore = SocialStore(
      doc: JsonDocumentStore(io: AppDocsFileIo()),
      reminders: reminders,
    );
    await socialStore.load();
    // Self-repair performed inside the store (a damaged saved-lists
    // file degrades to empty lists and is preserved aside, never a
    // crash): log the outcome into the report store (standing rule).
    final storeWarning = socialStore.storeWarning;
    if (storeWarning != null) {
      SelfRepair.logOutcome(
        success: true,
        area: 'Saved posts, replies and prospects',
        problem: 'A saved file for posts, replies and prospects was '
            'damaged, so the app started with empty lists instead of '
            'crashing, and kept the damaged file aside.',
        evidence: storeWarning,
      );
    }
    try {
      // Bounded: a platform channel that never answers (unsupported
      // platform, test host) must never hang app startup — reminders
      // degrade to in-app only and Diagnostics shows their state.
      await reminders
          .initialize(onTapPost: (_) {
            final deps = _socialDeps;
            final nav = _navigatorKey.currentState;
            if (deps != null && nav != null) {
              nav.push(MaterialPageRoute(
                builder: (_) =>
                    PostsScreen(deps: deps, openQueueFirst: true),
              ));
            }
          })
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Reminder setup failed/timed out: the queue + Today card remain
      // the source of truth (PRE-BUILD-AUDIT §3).
    }
    String? displayName;
    var welcomeDismissed = false;
    var emotionLevel = EmotionLevel.warm;
    VoiceInfo? voice;
    var chatLanguage = languageByCode('es');
    var tourSeen = false;
    String? referralLink;
    SharedPreferences? prefsInstance;
    try {
      final prefs = await SharedPreferences.getInstance();
      prefsInstance = prefs;
      // Self-repair (standing rule): settings load key-by-key — a
      // damaged entry is reset to its safe default and the repair is
      // logged, while every healthy entry is preserved exactly as
      // stored. (Before v1.1.1 one blanket catch discarded ALL
      // settings when any single one was damaged.)
      final loadedPrefs = await SafePrefsLoader(
        SharedPreferencesAccess(prefs),
        voiceValidator: (raw) => PrefKeys.decodeVoice(raw) != null,
      ).load();
      displayName = loadedPrefs.displayName;
      welcomeDismissed = loadedPrefs.welcomeDismissed;
      emotionLevel = EmotionLevel.fromName(loadedPrefs.emotionLevelName);
      voice = PrefKeys.decodeVoice(loadedPrefs.voiceRaw);
      final langCode = loadedPrefs.chatLanguageCode;
      if (langCode != null) chatLanguage = languageByCode(langCode);
      tourSeen = loadedPrefs.tourSeen;
      referralLink = loadedPrefs.referralLink;
      for (final r in loadedPrefs.repairs) {
        SelfRepair.logOutcome(
          success: r.success,
          area: 'Saved settings',
          problem: r.problem,
          evidence: 'Setting "${r.subject}": ${r.evidence}',
        );
      }
    } catch (e) {
      // The settings store itself could not be opened: no selective
      // repair is possible from here — defaults apply (the app still
      // works) and the failed repair goes on record.
      SelfRepair.logOutcome(
        success: false,
        area: 'Saved settings',
        problem: 'The settings store could not be opened at all, so '
            'the app started with its safe default settings.',
        evidence: 'Opening the settings store failed: $e',
      );
    }
    // M5 updater: real HTTP fetcher in the app; tests use fakes.
    // If preferences were unavailable, the updater still works with
    // in-memory prefs (checks happen, dismissals just don't persist).
    final updateService = UpdateService(
      fetcher: UpdateService.httpFetcher(),
      prefs: prefsInstance != null
          ? SharedPreferencesUpdatePrefs(prefsInstance)
          : MemoryUpdatePrefs(),
    );
    await splashMin;
    return _LoadedData(
      db: db,
      brand: brand,
      displayName: displayName,
      welcomeDismissed: welcomeDismissed,
      emotionLevel: emotionLevel,
      voice: voice,
      chatLanguage: chatLanguage,
      socialStore: socialStore,
      tourSeen: tourSeen,
      referralLink: referralLink,
      updateService: updateService,
    );
  }

  void _retry() {
    setState(() {
      _loadAttempt++;
      _loadFuture = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.appName,
      theme: buildLifewaveTheme(),
      navigatorKey: _navigatorKey,
      home: FutureBuilder<_LoadedData>(
        key: ValueKey(_loadAttempt),
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final err = snapshot.error;
            final message = err is DbLoadException
                ? err.message
                : 'Something went wrong while starting the app. Try '
                    'restarting it; if it keeps happening, reinstall it.';
            return _ErrorScreen(message: message, onRetry: _retry);
          }
          final data = snapshot.data;
          if (data == null) {
            return const _SplashScreen();
          }
          return _MainShell(
            data: data,
            onDepsReady: (deps) => _socialDeps = deps,
          );
        },
      ),
    );
  }
}

/// Branded splash: official logo on the palette tint background.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LwColors.tint,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LogoImage(
              assetPath: 'assets/brand/lifewave-logo.svg',
              height: 56,
            ),
            const SizedBox(height: 16),
            Text(
              AppInfo.appName,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: LwColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: LwColors.primary),
            const SizedBox(height: 12),
            const Text('Loading your database…'),
          ],
        ),
      ),
    );
  }
}

/// Fail-closed error screen: plain words, what to try, and a retry button.
class _ErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorScreen({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LwColors.tint,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  size: 56, color: LwColors.deepNavy),
              const SizedBox(height: 16),
              Text(
                'The app could not start',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Main shell: bottom navigation — Today / Catalog / Chat / More.
class _MainShell extends StatefulWidget {
  final _LoadedData data;
  final void Function(SocialDeps) onDepsReady;
  const _MainShell({required this.data, required this.onDepsReady});

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  AppTab _tab = AppTab.today;
  late String? _displayName = widget.data.displayName;
  late bool _welcomeDismissed = widget.data.welcomeDismissed;
  late EmotionLevel _emotionLevel = widget.data.emotionLevel;
  late VoiceInfo? _voice = widget.data.voice;
  late AppLanguage _chatLanguage = widget.data.chatLanguage;
  late bool _tourSeen = widget.data.tourSeen;
  late String? _referralLink = widget.data.referralLink;

  /// M2 services — created once for the whole app (audit rules:
  /// STT initialize-once, single speech controller).
  late final M2Services _services = M2Services();

  /// M3 dependency bundle — created once, shared by every social
  /// screen, Home's Today card, Settings and Diagnostics.
  late final SocialDeps _socialDeps = SocialDeps(
    db: widget.data.db,
    brand: widget.data.brand,
    m2: _services,
    store: widget.data.socialStore,
    share: SharePlusGateway(),
  );

  @override
  void initState() {
    super.initState();
    widget.onDepsReady(_socialDeps);
    // M5: check for updates on app start — throttled to at most once
    // per 24h inside the service, silent on failure/offline.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final result = await widget.data.updateService.check();
      _recordUpdateCheckFailure(result);
      if (mounted) setState(() {});
    });
  }

  UpdateService get _updater => widget.data.updateService;

  /// Risky-path logging (crash-report rule): a failed update check is
  /// recorded as a non-fatal problem report. Bounded by the service's
  /// own 24h throttle for automatic checks.
  void _recordUpdateCheckFailure(UpdateCheckResult result) {
    if (result.status == UpdateCheckStatus.couldNotCheck) {
      CrashReporter.recordCaught(
        Exception('The update check could not finish '
            '(no connection, or the answer could not be read).'),
        null,
        context: 'Update check',
      );
    }
  }

  Future<void> _checkUpdateNow() async {
    final result = await _updater.check(force: true);
    _recordUpdateCheckFailure(result);
    if (mounted) setState(() {});
  }

  Future<void> _dismissUpdate() async {
    await _updater.dismissCurrent();
    if (mounted) setState(() {});
  }

  Future<void> _openUpdate() async {
    await launchUrl(UpdateService.downloadUri,
        mode: LaunchMode.externalApplication);
  }

  Future<void> _dismissWelcome() async {
    setState(() => _welcomeDismissed = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(PrefKeys.welcomeDismissed, true);
    } catch (_) {
      // Non-fatal: the card just reappears next launch.
    }
  }

  /// M4 first-run tour: shown once, before the shell. Done/Skip both
  /// mark it seen (persisted) — "Show the tour again" lives in Guide.
  Future<void> _markTourSeen() async {
    setState(() => _tourSeen = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(PrefKeys.tourSeen, true);
      await prefs.setBool(PrefKeys.welcomeDismissed, true);
    } catch (_) {
      // Non-fatal: the tour simply shows again next launch.
    }
  }

  void _openTourAgain() {
    _push(TourScreen(
      brand: widget.data.brand,
      onDone: () => Navigator.of(context).pop(),
    ));
  }

  void _openGuide({String? sectionKey}) {
    _push(GuideScreen(
      brand: widget.data.brand,
      services: _services,
      db: widget.data.db,
      share: SharePlusGateway(),
      initialSectionKey: sectionKey,
      onShowTour: _openTourAgain,
      emotionLevel: _emotionLevel,
    ));
  }

  void _goTab(AppTab tab) => setState(() => _tab = tab);

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  // M3 social screens — one construction site each.
  void _openPosts({DateTime? prefillWhen, bool openQueueFirst = false}) =>
      _push(PostsScreen(
        deps: _socialDeps,
        prefillWhen: prefillWhen,
        openQueueFirst: openQueueFirst,
      ));
  void _openReplies() => _push(RepliesScreen(deps: _socialDeps));
  void _openProspects() => _push(ProspectsScreen(deps: _socialDeps));
  void _openCompliance() =>
      _push(ComplianceCheckerScreen(deps: _socialDeps));
  void _openFactCards() => _push(FactCardsScreen(deps: _socialDeps));
  void _openCalendar() => _push(CalendarScreen(
        deps: _socialDeps,
        onOpenPost: (_) => _openPosts(openQueueFirst: true),
        onDraftForSlot: (when) => _openPosts(prefillWhen: when),
      ));

  // M4 screens — one construction site each.
  void _openJourney() => _push(JourneyScreen(deps: _socialDeps));
  void _openRoleplay() => _push(RoleplayScreen(
        deps: _socialDeps,
        emotionLevel: _emotionLevel,
        selectedVoice: _voice,
      ));
  void _openDemo() => _push(DemoScreen(
        deps: _socialDeps,
        emotionLevel: _emotionLevel,
        selectedVoice: _voice,
      ));
  void _openPresentation() => _push(PresentationScreen(
        deps: _socialDeps,
        referralLink: _referralLink,
        displayName: _displayName,
      ));
  void _openQrKit() => _push(QrKitScreen(
        deps: _socialDeps,
        referralLink: _referralLink,
        displayName: _displayName,
        onOpenSettings: () {
          Navigator.of(context).pop();
          _push(SettingsScreen(
            initialName: _displayName,
            onNameChanged: (name) => setState(() => _displayName = name),
            services: _services,
            initialEmotionLevel: _emotionLevel,
            onEmotionLevelChanged: (level) =>
                setState(() => _emotionLevel = level),
            initialVoice: _voice,
            onVoiceChanged: (voice) => setState(() => _voice = voice),
            initialChatLanguage: _chatLanguage,
            onChatLanguageChanged: (lang) =>
                setState(() => _chatLanguage = lang),
            socialStore: widget.data.socialStore,
            initialReferralLink: _referralLink,
            onReferralLinkChanged: (link) =>
                setState(() => _referralLink = link),
            updateStatusLabel: _updater.lastResult.diagnosticsLabel,
            updateAvailableVersionName:
                _updater.lastResult.status == UpdateCheckStatus.updateAvailable
                    ? _updater.lastResult.remote?.versionName
                    : null,
            onCheckForUpdate: _checkUpdateNow,
            onOpenUpdate: _openUpdate,
            onDismissUpdate: _dismissUpdate,
          ));
        },
      ));

  @override
  Widget build(BuildContext context) {
    // M4: the first-run tour replaces the M1 welcome-card flow. It is
    // shown once, before the shell, until Done/Skip marks it seen.
    if (!_tourSeen) {
      return TourScreen(brand: widget.data.brand, onDone: _markTourSeen);
    }
    final db = widget.data.db;
    final brand = widget.data.brand;
    final store = widget.data.socialStore;
    final screens = <AppTab, Widget>{
      AppTab.today: AnimatedBuilder(
        animation: store,
        builder: (context, _) => HomeScreen(
          brand: brand,
          displayName: _displayName,
          // The tour replaced the welcome card (M4, SPEC §7.6): by
          // the time the shell builds, the tour has been seen, so
          // this is always false in practice.
          showWelcomeCard: !_tourSeen && !_welcomeDismissed,
          onDismissWelcome: _dismissWelcome,
          onGoTab: _goTab,
          counts: store.todayCounts(DateTime.now()),
          onOpenReplies: _openReplies,
          onOpenPosts: () => _openPosts(),
          onOpenProspects: _openProspects,
          onOpenJourney: _openJourney,
          onOpenDemo: _openDemo,
          updateBanner: _updater.shouldNotify
              ? UpdateBanner(
                  versionName:
                      _updater.lastResult.remote?.versionName ?? '',
                  onUpdate: _openUpdate,
                  onDismiss: _dismissUpdate,
                )
              : null,
          helpAction: HelpButton(
            screenKey: 'home',
            brand: brand,
            services: _services,
            db: db,
            share: SharePlusGateway(),
            onShowTour: _openTourAgain,
            emotionLevel: _emotionLevel,
          ),
        ),
      ),
      AppTab.catalog: CatalogScreen(db: db, brand: brand),
      AppTab.chat: ChatScreen(
        db: db,
        brand: brand,
        cloud: const NotConfiguredCloudEscalation(), // M1 stub — see service
        services: _services,
        emotionLevel: _emotionLevel,
        selectedVoice: _voice,
        chatLanguage: _chatLanguage,
      ),
      AppTab.more: MoreScreen(
        onOpenTranslator: () => _push(TranslatorScreen(
          services: _services,
          emotionLevel: _emotionLevel,
          selectedVoice: _voice,
        )),
        onOpenConversation: () => _push(ConversationScreen(
          services: _services,
          emotionLevel: _emotionLevel,
        )),
        onOpenPosts: () => _openPosts(),
        onOpenReplies: _openReplies,
        onOpenCompliance: _openCompliance,
        onOpenFactCards: _openFactCards,
        onOpenCalendar: _openCalendar,
        onOpenProspects: _openProspects,
        onOpenDiagnostics: () => _push(DiagnosticsScreen(
          db: db,
          brand: brand,
          services: _services,
          emotionLevel: _emotionLevel,
          selectedVoice: _voice,
          socialStore: store,
          tourSeen: _tourSeen,
          referralLinkSet:
              _referralLink != null && _referralLink!.trim().isNotEmpty,
          updateStatusLabel: _updater.lastResult.diagnosticsLabel,
          crashReporter: CrashReporter.active,
          shareGateway: _socialDeps.share,
        )),
        onOpenSettings: () => _push(SettingsScreen(
          initialName: _displayName,
          onNameChanged: (name) => setState(() => _displayName = name),
          services: _services,
          initialEmotionLevel: _emotionLevel,
          onEmotionLevelChanged: (level) =>
              setState(() => _emotionLevel = level),
          initialVoice: _voice,
          onVoiceChanged: (voice) => setState(() => _voice = voice),
          initialChatLanguage: _chatLanguage,
          onChatLanguageChanged: (lang) =>
              setState(() => _chatLanguage = lang),
          socialStore: store,
          initialReferralLink: _referralLink,
          onReferralLinkChanged: (link) =>
              setState(() => _referralLink = link),
          updateStatusLabel: _updater.lastResult.diagnosticsLabel,
          updateAvailableVersionName:
              _updater.lastResult.status == UpdateCheckStatus.updateAvailable
                  ? _updater.lastResult.remote?.versionName
                  : null,
          onCheckForUpdate: _checkUpdateNow,
          onOpenUpdate: _openUpdate,
          onDismissUpdate: _dismissUpdate,
        )),
        onOpenGuide: () => _openGuide(),
        onOpenRoleplay: _openRoleplay,
        onOpenDemo: _openDemo,
        onOpenPresentation: _openPresentation,
        onOpenJourney: _openJourney,
        onOpenQrKit: _openQrKit,
        onOpenAbout: () => _push(AboutScreen(
          logoAssetPath: brand.logoAssetPath,
          dbVersion: db.dbVersion,
          entryCount: db.entryCount,
        )),
      ),
    };
    return Scaffold(
      body: IndexedStack(
        index: _tab.index,
        children: AppTab.values.map((t) => screens[t]!).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.index,
        onDestinationSelected: (i) => _goTab(AppTab.values[i]),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Catalog',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz),
            selectedIcon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
