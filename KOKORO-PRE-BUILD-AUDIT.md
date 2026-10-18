# Lifewave App — Pre-Build Audit: Kokoro voice integration (v1.1.0)

*Written before implementation, 2026-10-17. Companion to
KOKORO-CHANGE-IMPACT-AUDIT.md.*

## 1. Permissions — every sensitive API call matched to its permission
- sherpa-onnx OfflineTts synthesis: pure on-device compute + file reads
  from the app's private documents dir. No permission.
- AudioTrack playback via the PCM MethodChannel: no permission (media
  playback, not recording). RECORD_AUDIO is NOT requested or used.
- Model download/extraction: existing INTERNET permission + existing
  http downloader; extraction writes only inside the app-private
  voice-model dir. No storage permission (app-specific storage needs
  none on any supported API level).
- Conclusion: the AndroidManifest gains NO new permissions in v1.1.0.

## 2. Null-safety / error handling
- Every failure mode of the new path lands in an honest state, never a
  crash and never fake speech:
  - download error / HTTP non-200 → manager error state + plain message
    (existing v1 behavior, unchanged).
  - SHA-256 mismatch → error state, archive deleted, message says the
    file did not check out and to retry on a good connection.
  - extraction failure / archive-slip entry → error state, no marker;
    partial extraction dir is removed.
  - model files missing at engine init → engine stays unavailable,
    reason updated; VoiceService falls back to device voice.
  - sherpa-onnx native load failure (e.g. Windows runner without the
    native lib) → caught at the synthesizer seam; same fallback.
  - PCM channel errors (no AudioTrack, interrupted) → speakSegment
    completes with the controller's existing error result; text remains
    on screen (existing SpeakResult message path).
- `speakSegment` on the Kokoro engine no longer throws StateError in
  normal operation; it may still throw on programmer error (never
  initialized), which VoiceService catches like any speak error.
- Nullable discipline: speaker id parsing (picked VoiceInfo id → sid)
  falls back to sid 0 (af_heart) for unknown/absent ids rather than
  throwing; the fallback is the catalogue's first voice, matching the
  app's "device default" honesty pattern.

## 3. API misuse risks
- Threading: OfflineTts.generate is CPU-heavy — it must NOT run on the
  platform/main thread. The synthesizer seam runs generation on a
  background isolate/thread owned by the engine (Dart: a long-lived
  worker isolate is overkill for sentence segments; generation is
  invoked from the already-async speak path — but the FFI call blocks
  its isolate, so it runs in a spawned isolate per initialization,
  kept alive for the engine's lifetime). Decision recorded here: use a
  dedicated persistent isolate for synthesis so UI jank is impossible.
  PCM playback itself is async via the channel (Kotlin writes on its
  own executor thread; the channel result completes when playback
  finishes — the same completion semantics flutter_tts provides via
  awaitSpeakCompletion).
- Lifecycle: the OfflineTts native object is created once and reused;
  it is released only when the engine is disposed (app teardown). No
  per-utterance create/free (native leak class).
- AudioTrack: created per play call in STREAM mode, stopped +
  released in a finally path on the Kotlin side; a completion timeout
  (utterance length + margin, capped) guarantees the Dart future
  completes even if the device misreports head position.
- The single-controller invariant stays: nothing outside VoiceService
  calls either engine; the self-test and translator keep going through
  VoiceService.speak (verified by grep before/after).

## 4. Protocol contracts
- VoiceEngine interface: unchanged signatures. KokoroEngine now honors
  the contract instead of throwing.
- VoiceService contract with callers (chat, translator, diagnostics
  self-test, demo): unchanged. `SpeakResult.renderedBy` values change
  only in that Kokoro renders are now possible ("Kokoro voice • …").
- Updater contract: version.json shape unchanged; android entry
  1.1.0 / versionCode 2 / releaseTag v1.1.0 / asset Lifewave-latest.apk.
- Stored data: PrefKeys.voiceKey encoding unchanged; Kokoro catalogue
  order unchanged (existing user picks keep meaning).
- MethodChannel 'lifewave/pcm_player': new, app-internal only.
  Methods: play {pcm: Uint8List (int16 LE), sampleRate: int,
  playbackRate: int} → null on completion; stop {} → null. Versioned
  by the app itself; no external consumers.

## 5. Security
- Model supply chain: single official source URL (sherpa-onnx GitHub
  release, already in v1 code) + pinned SHA-256 + license verified
  Apache-2.0 in v1 (redistribution-by-download clean). No third-party
  mirrors, no new network endpoints.
- Archive-slip guard on extraction (parent-path check per entry).
- No secrets, keys, or user data in the new code; synthesis is fully
  offline once the model is present; nothing spoken is logged or sent
  anywhere (debugPrint of errors only, matching existing style — and
  error logs never include utterance text).

## 6. Dependency / version check
Pinned exactly (no ranges), resolved against Flutter 3.24.5 / Dart
3.5.4 (verified on pub.dev 2026-10-17):
- `sherpa_onnx: 1.13.8` — sdk '>=3.2.0 <4.0.0', flutter '>=3.10.0' ✓.
  Its pubspec pins ALL platform packages at exactly 1.13.8, which
  structurally fixes the M2 skew (1.10.30 meta → android 1.12.36).
- `archive: 3.6.1` — sdk '^3.0.0' ✓ (tar + bzip2 decode for the model
  archive; pulls crypto ^3.0.3, path ^1.8.0).
- `crypto: 3.0.7` — sdk '^3.4.0' ✓ (SHA-256 streaming verification).
No other dependency changes. Build remains on the pinned toolchain
(TOOLCHAIN.md env block verbatim; one Gradle build at a time — 7.7 GB).

## Red flags found by this audit
- **sherpa_onnx on the Windows CI runner**: the plugin ships a Windows
  package; the Windows build currently fails earlier (VS generator,
  the other job's repair). My pubspec change must not be the thing that
  breaks a future Windows run — the engine's native-load failure is a
  caught, labeled unavailable state by design (see §2).
- **Isolate + FFI**: the sherpa-onnx native library is loaded per
  isolate; bindings init must happen inside the synthesis isolate, not
  assumed from the main isolate. The synthesizer implementation owns
  this explicitly (initBindings + OfflineTts construction inside the
  worker), and the fake used in tests bypasses FFI entirely.
- **132 MB on a phone's mobile data**: unchanged from v1 design — the
  download is user-tapped with the size on the button; no auto-download
  is introduced.
