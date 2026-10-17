# Lifewave AI

An independent Brand Partner tool — not an official LifeWave, Inc. app.

A phone + PC helper for LifeWave Brand Partners and customers: an
offline product knowledge base, a pictured catalog, chat Q&A grounded
in that database, voice with feelings, a translator (including a
2-way conversation mode), and plain-language business helpers —
curiosity-post drafts, reply drafts, a compliance checker, fact
cards, a prospect pipeline, and a 30-day customer journey.

The app works offline from its bundled database (95 entries, built
from official LifeWave sources, with every health/product claim
labeled as an *official fact* or a *distributor claim*). Group
training material is never copied into the app — entries point to
the groups where it lives.

## Features

- **Chat Q&A** — answers retrieved from the bundled database, claim
  labels preserved; the assistant says so when something is not in
  the database instead of guessing.
- **Catalog** — every current product with its official picture,
  US prices, and item codes.
- **Voice** — tap-to-talk input (device speech recognition) and
  spoken answers with a Scout-style emotion/prosody layer (chuckle,
  laugh, sigh, surprise, empathy; five feeling levels, default Warm)
  rendered by the device voice. **Honest note:** the Kokoro voice
  engine is stubbed in v1 — its native runtime alone is ~97 MB and
  would break the installer-size target. The app ships a complete
  download-manager for the voice file and says plainly in Settings
  and Diagnostics that the Kokoro timbre is not active yet; spoken
  answers use the device voice with the full emotion system.
- **Translator + 2-way conversation translator** — on-device language
  packs with a cloud fallback, auto/manual language per turn, and a
  text-conversation fallback where speech is not supported.
- **Social helpers** — curiosity-post generator (playbook style),
  draft/queue with reminders, reply drafts, compliance checker,
  fact cards, content calendar, prospect pipeline. **Honest note:**
  v1 has no account connection — nothing is posted for you. Every
  send is your own tap through the share sheet / the platform app,
  and queue states never claim a post was "posted".
- **Extras** — roleplay practice with coaching, a 60-second demo,
  presentation mode, the 30-day customer journey with check-in
  drafts, and a personal QR kit (your own referral link, entered by
  you, stored only on your device).
- **Guide + first-run tour** — every feature explained in plain
  words, searchable, with a help button on every screen.
- **Diagnostics** — versions, database state, and one-tap self-tests,
  so "it's not working" becomes a screenshot.
- **Updater** — checks this repo's `version.json` at most once a day
  on app start; one subtle notice per version; you tap to update.
  Never forced, never silent.

## Install

### Android

1. On the phone, open this repo's **Releases** page and download
   **Lifewave-latest.apk** (or use the direct link:
   `https://github.com/smartyourtv/lifewave-app/releases/latest/download/Lifewave-latest.apk`).
2. Tap the downloaded file to install. Android will ask you to allow
   installs from your browser ("unknown apps") for this one install —
   allow it, then tap Install.
3. Open **Lifewave AI**. The first-run tour explains everything.

The APK is signed with a consistent release key, so future versions
install over this one without uninstalling.

### Windows

1. Download **Lifewave-Setup.exe** from Releases (available once the
   Windows build has run — see "Building" below; if it is not in the
   release yet, only the Android APK is available).
2. Run it. It installs per-user (no admin needed) with Start Menu and
   Desktop shortcuts, and uninstalls from Settings → Apps.
3. The installer is unsigned, so Windows SmartScreen will warn the
   first time: click **More info → Run anyway**.

## Data & privacy

- Works offline. Your data (name, preferences, drafts, pipeline,
  journal, referral link) stays **on your device only**.
- No accounts, no telemetry, no trackers, no ads.
- The only network traffic is: the update check (this repo), optional
  downloads (voice file / language packs), and anything you choose to
  share through the system share sheet.

## Database

95 entries across products, usage, FAQ, business (including the
current US Compensation Plan 2.0 and Policies & Procedures summaries
from official documents, and the **2024** Earnings Disclosure —
labeled by year), phototherapy, company, testimonials, the
curiosity-post playbook, and group pointers. Sources and provenance
are logged in `ASSETS.md` (brand assets) and `HARVEST-LOG.md`
(database). Entries are own-words summaries of official sources —
never verbatim group posts or protocols.

## Building

- Android: Flutter 3.24.5 (pinned) — `cd app && flutter build apk --release`.
  Release signing reads `app/android/key.properties` when present
  (local only, git-ignored); without it the build falls back to debug
  signing.
- Windows: the Flutter Windows build only compiles on Windows.
  `packaging/build-windows.ps1` runs it and compiles
  `Lifewave-Setup.exe` with Inno Setup 6 from
  `packaging/app-config.json`. Validate the packaging anywhere with
  `python packaging/validate_packaging.py`. The CI workflow that
  automates this lives at `.github/workflows/build-windows.yml` in
  the project folder (added to the repo via the GitHub website — the
  API credential cannot push workflow files).

## License / status

An independent tool built by a Brand Partner for Brand Partners.
LifeWave®, X39® and the other product names are trademarks of
LifeWave, Inc.; this project is not affiliated with or endorsed by
LifeWave, Inc.
