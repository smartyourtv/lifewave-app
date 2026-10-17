# Lifewave App — Change-Impact Audit (Phase 2 build)

*Standing rule (AGENTS.md, 2026-10-15): run before implementing any change to an existing build. This audit covers the Phase 2 change: turning the Phase 1 spec + database foundation (`SPEC.md` §§1–6, `db/` at `db_version` 2, 44 entries) into the full Flutter app specified in `SPEC.md` §7. Written 2026-10-17. Companion file: `PRE-BUILD-AUDIT.md`.*

## 1. Blast radius

- **New standalone app.** Phase 2 creates a new codebase (`app/`, Flutter) plus packaging/release plumbing. No existing production app is modified to make it work.
- **Files/areas touched:** new Flutter project; the bundled copy of `db/` (read-only at runtime — the harvest source of truth stays in `~/workspace/lifewave/db/`); `db/manifest.json` contract (consumed, not redefined — see §4); GitHub repo `smartyourtv/lifewave-app` (new); `version.json` in that repo (new, updater contract — see PRE-BUILD-AUDIT §4).
- **Shared items (reuse only, read-only borrowing):**
  - The windows-health packaging template (`~/workspace/windows-health/packaging/` — `setup.iss`, `build-installer.ps1`, `validate_packaging.py`, `app-config.json` pattern) — copied/adapted for the Inno Setup `Setup.exe`, never edited in place.
  - The GitHub Releases distribution pattern used by Scout (stable `-latest.apk` filename, versioned release tags, `version.json` read by the in-app updater).
  - Scout voice-stack *patterns* (Kokoro + voice mods + emotion rendering design, slimming/download-after-install pattern, diagnostics-card pattern) — reimplemented/shared as patterns in Flutter, not a live dependency on any Scout codebase or service.
- **Explicitly untouched:** Scout (phone app, laptop/ThinkPad, Outpost/Shield), Nuri, Tiara — no code, no servers, no shared runtime state. The Lifewave app has **no connection** to any of them (SPEC §1, §7.7 connection rule).
- **Content blast radius is the real one:** the app *generates* outbound text (posts, replies, fact cards, translations). A bad generation reaches the user's public Facebook presence and, if it contains a medical claim or group-internal material, breaks SPEC §3 hard rules in public, under the user's name. This is why the compliance checker (SPEC §7.9) gates every outbound draft and why approval is always human (§5, §6).

## 2. Regression risk

- **No prior Lifewave app exists to regress** — there is no shipped v1 behavior, settings store, or user data from a previous Lifewave build. Regression risk here means *reopening known-fixed problems from sibling builds* and *breaking Phase 1 guarantees*:
  - **Phase 1 guarantees that must not regress:** owner-neutrality (release grep check, SPEC §8), claim labels preserved end-to-end (retrieval → chat answer → post draft → translation), pointer-only handling of group-internal material, `audience: "public"` on every entry. The app must never "helpfully" summarize a pointer entry into content — pointers render as pointers.
  - **Known-fixed Scout lessons that must not be reintroduced:** (a) a control that appears to do nothing — every button explains + confirms + gives feedback (the voice-prompt-button lesson); (b) voice output cutting off mid-sentence — TTS/Kokoro playback needs completion/error surfacing in the diagnostics card, tested on-device in M2; (c) Bluetooth routing surprises in conversation mode — use the existing system connection and Scout's documented fallbacks (speaker default, headset private, clipped speaker loud) rather than inventing a new routing path; (d) silent failures — every cascade tier (retrieval, translation, cloud escalation) logs to the diagnostics view and degrades visibly, never hangs (interpreter timeout-cascade lesson).
  - **Database regression risk:** app-side DB handling must not mutate or "upgrade" bundled entries in ways that diverge from the harvested source; any app-side cache is disposable and rebuilt from the bundle.

## 3. Cross-build effects

- **Universal improvement rule applies, with the no-negative-effects guard:** voice/emotion and interpreter improvements made *for* Lifewave that would help Scout/Nuri are candidates to push back to those builds — but only as separate, separately-audited changes to those builds, never as a side effect of this build. This build does not edit Scout/Nuri/Tiara code.
- **Nuri integrity guard:** nothing in Lifewave touches Nuri. The emotion-level dropdown pattern is borrowed *from* Nuri's design; borrowing a pattern changes nothing in Nuri.
- **Shared-pattern drift risk:** packaging template and release pattern are copied, not linked. If the windows-health template later fixes a packaging bug, Lifewave does not inherit it automatically — accepted, and preferable to a shared build dependency between unrelated products. Noted so a future template fix is manually ported.
- **Reputation coupling (non-code):** Lifewave ships under the same GitHub account (`smartyourtv`) as Scout. A broken or non-compliant Lifewave release reflects on the same release channel — another reason the §8 release checks gate M5.

## 4. Data & compatibility

- **`db_version` handling:** `db/manifest.json` carries `db_version` (currently 2). Rules for the app:
  - The app bundles a known-good DB and records the bundled `db_version` at build time.
  - On a DB update (delivered with an app release or as a downloaded bundle), the app accepts a bundle only if its manifest parses, `db_version` is **newer** than the installed one, and every entry passes the schema/claim-label/audience check. A failed or older bundle is rejected whole — no partial application — and the previous DB keeps serving.
  - The app must **tolerate older `db_version`s** (a user who skips releases): retrieval code keys off the manifest's topic/file list, never hard-coded topic names, so missing topics (e.g. `usage`/`faq`/`playbook` before Pass 3 lands) render as "not in this database version yet," not as errors.
  - Entry-level tolerance: entries missing optional fields (price, item code) render "not listed" — never crash, never invent (see PRE-BUILD-AUDIT §2).
- **Per-user on-device data (all new in Phase 2, all on the user's own device only):** first-run name/preferences; assistant rename; voice + emotion-level choice; "remember that…" notes; prospect pipeline entries; customer-journey state (day counter, journal, check-in status); post/reply drafts and queue; content calendar; referral link for My QR kit; downloaded assets (Kokoro model, language packs).
  - None of this is shipped, synced, or backed up by us. Uninstall removes it (platform behavior) — the user guide must say so plainly, including for the journey journal ("deleting the app deletes your journal").
  - **Migration:** Phase 2 is the first version, so there is no legacy user data to migrate. From the first release onward, every per-user store gets its own version key; a store whose version the app doesn't recognize is preserved-but-ignored with a diagnostics entry, never silently wiped — the journal and pipeline are the user's business records.
  - **Format rule:** per-user stores are local files/DB in app-private storage (see PRE-BUILD-AUDIT §5 for encryption); no per-user data is ever written into the bundled knowledge DB or mixed with it.
- **Compatibility:** Android + Windows from one Flutter codebase read the same DB bundle and the same `version.json` contract; a DB or content fix therefore ships to both by rebuilding both — there is no platform-specific content fork. iOS is out of scope (§7.11 later phase) and no Phase 2 decision may assume iOS APIs.

## 5. Permissions & security

- **Permissions the app plans to request (least set, each matched to a feature — full matching table in PRE-BUILD-AUDIT §1):** microphone (voice input, interpreter, ask-the-guide); internet (cloud escalation, translation-pack/Kokoro downloads, updater check, optional user-connected social accounts); notifications (post-time reminders for profile queue, follow-up/reorder reminders, one-time update notice); storage/file access only through the platform share/picker flows (fact-card sharing, printing the quick-start/QR one-pager) — no broad storage permission.
  - **Not requested:** contacts, location, camera (QR is *generated*, not scanned, in v1), background location, SMS/phone. Anything on this list appearing in a manifest diff is a red flag that stops the build.
- **No Facebook credentials in the app.** The app ships with no one's Meta credentials, stores no Facebook password, and never logs into Facebook as the builder or the user. Live social actions, when they come, use **each user's own account connection** on their own device (SPEC §7.10/§7.11 honesty rule); v1 ships draft/queue/approval + documented integration points only. Tokens from any future user connection are user data: stored only in platform secure storage, never in the knowledge DB, logs, or diagnostics output.
- **No telemetry.** No analytics SDK, no crash-reporting beacons, no usage tracking in v1. Diagnostics are **on-device** (the diagnostics card) and leave the device only if the user chooses to share a screenshot/report themselves.
- **Secrets handling:** the app ships with **no embedded API keys or secrets**. If generic-cloud escalation requires configuration, it takes one of two forms: (a) a provider endpoint that needs no per-app secret, or (b) a **user-supplied** cloud API key entered by the user in Settings, stored only in platform secure storage, used only for that user's requests, redacted from all logs/diagnostics, and removable with one tap ("disconnect"). A design that needs a builder-owned secret embedded in the binary is a **stop**: redesign the escalation tier instead (see PRE-BUILD-AUDIT §§4–5).
- **Content security = compliance security:** the compliance checker is a security control, not a nicety — it is the last automated gate before user-approved text reaches a public platform (§1).

## 6. Behavior changes

- **For the user (all new — there is no prior Lifewave behavior):**
  - A new app on phone + PC with tap-to-talk chat, spoken answers in a selectable emotional voice (default emotion level **Warm**), translation + conversation mode, and business tools (Today card, pipeline, journey).
  - **Approval is the interaction model:** posts, replies, check-ins, and cross-posts are drafted by the AI and sent **only** on the user's tap. Users coming from auto-posting tools must see this as a feature, stated plainly in the first-run tour — not discover it as a limitation.
  - **Honest state labels:** the UI says what actually happened — drafted / queued / reminder set / shared via share sheet — never "posted" when nothing was sent (SPEC §7.11).
  - Voice sounds like a warm, professional assistant, **not** Scout's persona (§7.3); on Windows before the Kokoro model downloads, voice is device TTS and the app says so.
- **For other builds' users:** none. Scout/Nuri/Tiara behavior, voices, and interfaces do not change as part of this build.
- **For the database workflow:** harvesting continues unchanged (Pass 3: `usage`/`faq`/`playbook`); the app consumes whatever `db_version` is bundled at build time, so harvest timing no longer blocks app milestones — M1 works against `db_version` 2.

## 7. Performance

- **Installer budget: ~20–30 MB total** (Android APK and Windows `Setup.exe` alike). Enforcement: the bundled knowledge DB is small (44 entries ≈ tens of KB of JSON — negligible); the budget is spent on the Flutter runtime + app code + assets. **Kokoro model, Edge-voice extras, and per-language translation packs are download-after-install, per-language/per-asset, with sizes shown before download** — bundling any of them into the installer breaks this audit and M5 packaging.
- **Downloaded-asset storage:** assets live in app-private storage with a visible size readout and a delete option in Settings/diagnostics; a user on a small phone must be able to reclaim the space.
- **Runtime:** on-device retrieval over ≤ a few hundred JSON entries is trivially in-memory; no vector DB or heavy index in v1. Chat latency is dominated by the cloud-escalation tier when used — the UI must stream/acknowledge rather than block (timeout cascade pattern). Voice: Kokoro inference on low-end phones is the known perf risk — M2 includes a low-end-device check; device-TTS fallback is the pressure valve, surfaced honestly, never a silent quality drop.
- **Battery/background:** no always-listening (no wake word in v1), no background polling. Reminders use scheduled local notifications (OS-scheduled), not a resident service. The updater checks on launch/app-open cadence per the standing rule, not on a timer loop.
- **Windows:** the `Setup.exe` is per-user (no admin); first run must not require downloading the Flutter runtime or Python — everything the app needs is inside the installer or an explicitly-offered in-app download.

## 8. Rollback

- **App rollback:** GitHub Releases keeps every prior release; the updater only moves *forward* on user tap and never force-installs, so a bad release is rolled back by (a) publishing a fixed release, or (b) pointing `version.json` back / shipping a patch release whose versionCode supersedes the bad one (Android will not install a lower versionCode over a higher one — rollback on Android therefore means a *new build with a higher versionCode containing the reverted code*, and the release notes must say so). Windows: a new `Setup.exe` with the reverted code installs over the bad one per-user.
- **Pre-build snapshot:** before M1 scaffolding, the current `~/workspace/lifewave/` tree (spec, db at `db_version` 2, logs) is the Phase 1 baseline; it lives in git/workspace history and is not modified by app work except for additive harvest passes. DB changes are append/edit-in-place per entry with HARVEST-LOG entries, so any pass can be reverted per-topic.
- **User-data fate on rollback/reinstall:** per-user stores are version-keyed (§4); rolling the *binary* back does not roll back the user's data, and an older binary meeting a newer store preserves-but-ignores it (never wipes). The one destructive path is uninstall — documented in the guide (§6).
- **Feature-level rollback:** each §7 feature is independently shippable/removable behind the milestone structure (M1–M5). If, e.g., cross-posting integration stalls on platform review, M3/M4 ship with its draft/approval UX and the integration point documented — no other feature is held hostage.

## 9. Test plan

- **Runnable on this Linux VM (no device needed) — required at every milestone gate:**
  - Dart unit tests: DB loader (manifest parse, `db_version` accept/reject, missing-topic tolerance), entry schema validation (required fields, claim-label/audience enums), retrieval ranking determinism, compliance checker (seeded violating drafts must be flagged; seeded clean drafts must pass), claim-label preservation through chat-answer assembly and translation-check flow, pipeline/journey state transitions, updater `version.json` parse + compare logic.
  - Flutter widget tests: Today card rows render from fixture data; draft → approval → queue flow states are labeled honestly; DB-entry rendering with missing optional fields shows "not listed"; guide search returns results offline; settings dropdowns persist per-user values.
  - Static gates: `flutter analyze` clean; the SPEC §8 release checks (owner-neutrality grep, content check) run against the bundle in CI/local before any packaging.
  - Golden/fixture rule: tests run against a **fixture DB** (synthetic entries incl. a pointer entry, a distributor-claim entry, entries with missing optional fields) — never against harvested group text.
- **Needs a real device (cannot be proven on the VM — do not claim otherwise):**
  - Android: mic permission flow + STT accuracy/noise behavior; Kokoro playback quality, emotion rendering, and the mid-sentence cut-off check on a low-end phone; Bluetooth headset/speaker routing in conversation mode; local-notification delivery for queue/follow-up reminders under Android battery management (incl. exact-alarm limits — see PRE-BUILD-AUDIT §3); share-sheet fact-card handoff; APK install-over-install upgrade with real per-user data present.
  - Windows: `Setup.exe` install/uninstall on a clean Windows machine (per-user, no admin), SmartScreen wording in the README verified against reality, Flutter Windows STT/TTS behavior (platform support differs from Android — see PRE-BUILD-AUDIT §3), printing of the quick-start/QR one-pager.
  - Human acceptance: a Southern-Vietnamese conversation-mode sanity check is **not** an acceptance gate for this app (dialects not imperative, SPEC §7.4) — standard-Vietnamese intelligibility is the bar here; the dialect acceptance test belongs to the van/standalone translator.
- **Compliance acceptance (human, before M5):** a reviewer reads a sample of generated posts/replies/fact cards in English *and* one translated language, checking claim labels, coded language, and pointer discipline — automated checks alone do not pass this gate.

## Red flags found by this audit

1. **Embedded-secret trap:** generic-cloud escalation tempts an embedded builder API key. Forbidden by §5 — the escalation tier must be keyless-by-design or user-keyed, or it does not ship.
2. **"Posted" dishonesty trap:** queue/reminder/share-sheet flows are easy to mislabel as sends. The honest-state-label rule (§6, SPEC §7.11) is a release check, not a style preference.
3. **Asset-creep trap:** Kokoro + 59 language packs would blow the 20–30 MB installer by an order of magnitude if bundled "for convenience." Download-after-install is audited at M5 by measuring the actual installer.
