# Lifewave App — Change-Impact Audit: Kokoro voice integration (v1.1.0)

*Written before implementation, 2026-10-17. Decision being implemented:
Shawn, 2026-10-17 — "Yes Kokoro." Scope: wire real sherpa-onnx Kokoro
synthesis → PCM playback into the existing voice path, replacing the
labeled engine stub shipped in v1.0.0.*

## 1. Blast radius
- `app/lib/services/voice_service.dart` — the core change: `KokoroEngine`
  stub → real engine; `VoiceModelManager` gains SHA-256 verification +
  archive extraction (the v1 manager downloads the .tar.bz2 but never
  extracts it, so "ready" in v1 meant "archive present", which no engine
  could consume); `VoiceService` gains an async engine-resolution step so
  a Kokoro init failure falls back to the device voice for that utterance
  instead of failing speech outright.
- `app/android/app/src/main/kotlin/.../MainActivity.kt` — gains a small
  PCM-player MethodChannel (AudioTrack). Only Android platform code
  touched; the Windows build path is untouched (sherpa_onnx ships a
  Windows plugin; the Kokoro *engine* degrades to unavailable there via
  the synthesizer seam if the native lib fails to load — honest label).
- `app/lib/screens/settings_about.dart` — the Kokoro card currently
  prints `KokoroEngine.stubReason` (stub copy) verbatim; replaced with
  live status copy. `app/lib/theme.dart` — version label 1.1.0 (build 2).
- `app/pubspec.yaml` / `pubspec.lock` — three pinned additions
  (sherpa_onnx, archive, crypto). Nothing else in the dependency graph
  is intentionally changed.
- NOT touched: `packaging/`, `.github/` (a separate job is repairing the
  Windows installer there), the database, SPEC/FEATURE-REQUESTS, any
  screen outside the Kokoro settings card copy.

## 2. Regression risk
- The single-controller rule (PRE-BUILD-AUDIT §3) is the main risk area:
  Kokoro playback must honor the same completion/interruption contract as
  flutter_tts (awaitSpeakCompletion). The PCM channel therefore reports
  completion only when AudioTrack has actually played the frames, and
  `stop()` must cut playback mid-segment. A hang here freezes ALL app
  speech — mitigated by a Kotlin-side completion timeout and the
  controller's serial-token interruption, and covered by fake-player
  tests of the Dart side.
- Existing v1 behavior when no model is downloaded must be IDENTICAL:
  device voice, same labels except the stub wording. The m2 fake-service
  tests assert this path and are updated only where the stub copy /
  stub semantics were the assertion.
- Voice picking: stored per-user selections are `engine|id|name`
  strings. A user who picked a Kokoro voice in v1 (listVoices exposed
  the catalogue when the archive was "ready") must resolve to the same
  speaker id in v1.1 — the catalogue order is unchanged.

## 3. Cross-build effects
- Phone Scout / laptop Scout / Nuri: none. Shared-code rule applies to
  patterns, and this integration follows the Scout pattern (download-
  after-install + integrity check + honest labels) without code coupling.
- Windows installer job (parallel): no shared files. This job does not
  touch `packaging/` or `.github/`; repo head is re-fetched immediately
  before pushing, and any conflicting head movement = stop and report.

## 4. Data & compatibility
- In-place upgrade: same keystore (Scout-pattern, cert 051c7687…),
  versionCode 1 → 2, versionName 1.0.0 → 1.1.0. Updater contract
  (version.json android.versionCode integer compare) unchanged in shape;
  version.json android entry moves to 1.1.0 / code 2 / tag v1.1.0.
- On-device data: v1 installs may already hold a downloaded archive +
  `.ready` marker written by the v1 manager. v1.1 `refresh()` must NOT
  trust a v1 marker alone (v1 never extracted): readiness requires the
  extracted model file; if a v1 archive is present without extraction,
  the manager extracts it in place (no re-download) the first time the
  engine/card is used. This is handled by making `refresh()` check the
  extracted tree and `download()` short-circuit to extract-only when a
  hash-valid archive already exists.
- Model files on disk: extraction adds ~150-250 MB next to the 132 MB
  archive in the app's documents dir; the archive is kept (it is the
  hash-verified source the delete action removes; deleting it post-
  extract would make "repair" a re-download). Stated in BUILD-STATUS.

## 5. Permissions & security
- No new Android permissions: synthesis and AudioTrack playback need
  none; the model download already rides the existing INTERNET
  permission and the existing http downloader.
- Integrity: SHA-256 of the downloaded archive is pinned in code
  (`KokoroModelSource.expectedSha256`, computed from the official
  sherpa-onnx release asset on 2026-10-17) and verified BEFORE the
  archive is extracted or the marker written. A re-packed official
  asset would fail the hash and need an app update — accepted trade-off
  of pinning, stated in BUILD-STATUS (the v1 size-only check remains as
  a first-pass sanity check).
- Extraction safety: tar entries are extracted ONLY under the model
  dir; entries with `..` or absolute paths are rejected (archive-slip).
  Extraction happens on the app's private storage only.

## 6. Behavior changes
- After the voice file is downloaded (now: downloaded + verified +
  extracted), the app's voice BECOMES Kokoro automatically
  (`VoiceService.activeEngine` already prefers an available Kokoro), and
  Settings/Diagnostics say "Kokoro voice" — before that they say the
  device voice is in use and why. No fake Kokoro state anywhere.
- The emotion/prosody system applies to Kokoro output: synthesis speed
  from the prosody rate, voiced markers synthesized in the picked
  Kokoro voice, pauses honored; pitch is applied at the PCM sink
  (playback-rate scaling, synthesis speed compensated) because
  sherpa-onnx Kokoro exposes no pitch parameter.
- First Kokoro utterance pays a one-time model-load cost (int8 model
  init); subsequent utterances reuse the loaded engine.
- Settings card copy changes from the stub explanation to: what Kokoro
  is, that the file is ~132 MB to download, and the live state.

## 7. Performance
- APK size: adding sherpa_onnx bundles its native runtime. All four
  Android ABI packages resolve, but the app's existing abiFilters
  (arm64-v8a + armeabi-v7a) limit what is packaged: expected +~41 MB
  (arm64 ~24 MB + v7a ~17 MB) over v1.0.0's 32.3 MB. The 97 MB figure
  was all-ABI; x86/x86_64 are NOT packaged. Measured number is reported
  in BUILD-STATUS, not estimated. The 132 MB MODEL stays
  download-after-install — it is not in the APK.
- Runtime: OfflineTts init loads ~90 MB of int8 weights; generation is
  CPU (2 threads) and faster than real time for sentence-length
  segments on arm64. PCM playback streams via AudioTrack; no audio is
  written to disk.

## 8. Rollback
- Code rollback = revert the voice_service/MainActivity/pubspec
  changes; v1.0.0 release stays published and untouched until v1.1.0
  verifies by read-back.
- User-level: deleting the voice file in Settings returns the app to
  the device voice exactly as in v1. A failed Kokoro init at runtime
  never blocks speech (device fallback per utterance).

## 9. Test plan
- Baseline: 120/120 (v1.0.0). All suites must pass after updates.
- Updated: VoiceModelManager tests (fake downloader + injected fake
  verifier/extractor seams, mirroring the existing injectable style);
  the VoiceService stub assertions.
- New coverage: hash-mismatch → error state, no marker; extraction
  failure → error state; v1-archive-present → extract-without-download;
  KokoroEngine with fake synthesizer + fake PCM player: unavailable
  until model ready, speaker-id resolution from the picked voice,
  prosody application (speed/pitch/volume/marker synthesis order),
  stop() cuts the player; VoiceService falls back to device voice when
  Kokoro init fails; activeEngineLabel honesty in each state.
- On-device items that CANNOT be proven on this VM (stated, not
  claimed): real sherpa-onnx synthesis, AudioTrack playback quality,
  Kokoro timbre/emotion realism by ear (Shawn's acceptance), model-load
  time on a real phone.

## Red flags found by this audit
- **The v1 manager's "ready" is a lie an engine could trip on** (archive
  present, never extracted). Fixed by the readiness redefinition above;
  any other reader of `isReady` (Settings card, Diagnostics row,
  listVoices) inherits the stricter meaning — checked, all are display
  or catalogue paths that behave correctly with it.
- **`activeEngineLabel` hardcodes the stub sentence** ("Kokoro engine
  not in this build") — replaced with state-driven labels.
- **Plugin version skew (the M2 stub's blocker (a))**: sherpa_onnx
  1.10.30's loose platform constraints resolved mismatched platform
  packages (android 1.12.36). Pinning sherpa_onnx **1.13.8** — whose own
  pubspec pins every platform package at exactly 1.13.8 — removes the
  skew by construction. Verified from pub.dev before implementation.
