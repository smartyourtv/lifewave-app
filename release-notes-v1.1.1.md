# Lifewave AI v1.1.1

An independent Brand Partner tool — not an official LifeWave, Inc. app.

## What's new: problem reports + self-repair

Shawn's standing rule for every app we build: if the app hits a
problem, it should say so, write it down, and — when the problem is in
its own saved information — try to fix it safely. v1.1.1 adds both
halves.

### Crash & error reports

- If the app stops or hits a problem, a plain-language report is
  saved on the device: what happened, when, the app version, the
  device system, and the technical details.
- A copy of each report also lands in the device's **Downloads**
  folder (`Lifewave-crash-<date>-<time>.txt`), so it can be found and
  shared without opening the app.
- In the app: **Diagnostics → Crash & error reports** lists every
  saved report — tap to read it, share it, or delete it.
- Reports are **never sent anywhere** by the app. They stay on the
  device until you share one yourself.
- Problems caught along the way (the voice file failing to load, an
  update check that could not run, the database failing to open) are
  recorded in the same place, even when the app keeps going.

### Self-repair

When the problem is in the app's own saved information, the app now
tries a careful fix — and writes the outcome (fixed / could not fix,
with the evidence) into the same reports list:

- **Damaged settings:** settings load one by one. A damaged entry is
  reset to its safe default; every healthy setting is kept. (Before,
  one damaged entry discarded all settings.)
- **Bad voice download:** a Kokoro voice file that is incomplete or
  fails its safety check is never switched on. A file that fails the
  check is removed, and the device voice keeps speaking.
- **Damaged saved lists:** a damaged posts/replies/prospects file
  still starts the app with empty lists (never a crash), and the
  damaged file is kept aside — now logged as a repair as well.
- **Database that won't open:** the app retries once from its bundled
  copy; if that fails, you still get the plain-language error screen.

Code problems are not "repaired" — they are reported, and fixed by an
update like this one.

## Also fixed

- The app's internal build number now matches the shipped version
  (it lagged one release behind, which could make the updater offer
  an "update" to the version already installed).

## Honest notes

- Reports capture problems in the app's own (Dart) layer. A failure
  deep in native code (for example inside the voice engine's native
  library) can end the app before any report is written — that is a
  platform limit, not something this update hides.
- On Android 9 and older the Downloads copy is best-effort (older
  Android restricts direct Downloads writes); the in-app copy is
  always kept.
- If the Downloads copy can't be written, the in-app report is still
  saved — the mirror never loses the original.
- On-device behavior of the new reporting is untested on a physical
  phone/PC as of this release; the logic is covered by automated
  tests (156 passing).
