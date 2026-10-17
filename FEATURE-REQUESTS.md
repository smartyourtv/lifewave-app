# Lifewave App — Feature Requests (for Phase 2 spec)

Logged 2026-10-17 from Shawn, after Phase 1. To be folded into SPEC.md
when Phase 2 (the apps) is specced.

## Requested by Shawn
1. **Curiosity-post posting + scheduling**
   - App generates curiosity posts from the database in the groups'
     question-led style, compliance-checked before queueing.
   - Scheduling: full native scheduling works on a Facebook **Page**
     (10 min – 29 days ahead, reschedule/cancel supported). Personal
     profile posts cannot be scheduled by apps — the app queues them
     and reminds at the chosen time for a one-tap post.
   - Every post still gets a human approval before it is queued/sent.
2. **AI-assisted replies (option)**
   - Comments on his posts and Messenger messages: AI drafts replies
     in the established style (answer briefly, invite into LW Team
     Learning, no medical claims, coded language for restricted terms).
   - Mode: draft + one-tap approve/edit/send. Each send is approved —
     no silent auto-sending. Pre-approved template answers for common
     FAQs are the fastest path within that rule.
3. **Voice — like Scout, with emotions** (Shawn, 2026-10-17)
   - Dictate a post idea or question by voice (already in spec), AND
     spoken answers use Scout's voice system, not the device's plain
     robot TTS:
     - Kokoro engine + Scout's voice mods (prosody: pitch/breath/
       pacing/pauses) — the shared voice stack, per the universal
       improvement rule (voice improvements push to all builds).
     - Full emotion range like Scout: chuckle, full laugh, sighs,
       surprise, empathy — the AI marks the emotion, the renderer
       produces it IN THE SELECTED VOICE (laugh follows voice changes;
       never a stock clip of a different person).
     - User picks their own voice on their own device (owner-neutral);
       emotion self-test button ships in the app (diagnostics rule).
   - Persona distinction: same voice ENGINE as Scout, but the
     assistant's character is Lifewave-appropriate (warm, professional,
     business-safe) — not Scout's sarcastic persona. Each user may get
     an emotion-level setting (Nuri's dropdown pattern) — default Warm.
   - Cost: the Kokoro voice model is a download-after-install (Scout
     slimming pattern), so the installer stays small.
4. **Translation — any language** (Shawn, 2026-10-17 — supersedes the
   Vietnamese-only suggestion below)
   - Applies to: chat Q&A (ask and be answered in your language),
     curiosity-post drafts, and incoming comments/Messenger replies.
   - Design: on-device translation packs (~59 languages, offline after
     download) + cloud fallback for the long tail (100+ languages,
     needs internet). "Any language" = the full list these engines
     cover — no engine covers every language on Earth.
   - Compliance check runs on the final-language text, not just the
     English draft — translation must not soften claim labels or
     introduce medical claims.
   - Dialects: NOT imperative (Shawn, 2026-10-17). Standard
     single-voice support per language is acceptable for this app —
     dialect-specific engines are a nice-to-have, never a build
     blocker. (Scope confirmed 2026-10-17: Lifewave-only — the hard
     Southern-Vietnamese rule on the van/standalone translator STAYS.)
5. **2-way conversation translator** (Shawn, 2026-10-17: "How about
   2 way conversation translator")
   - Face-to-face interpreter mode: you speak your language, the app
     speaks theirs aloud; they reply, the app speaks yours. For
     talking with prospects/customers in person — the Lifewave use.
   - Reuses the Scout interpreter design already built (2026-10-16):
     turn-based, auto language detection per turn or manual toggle,
     split-screen transcript (original + translation per turn),
     cascade with timeouts so a turn never hangs — on-device first,
     cloud second (no van-Scout tier in this app).
   - Audio: phone speaker for their side by default (like Google
     Translate conversation mode); Bluetooth headset gives private
     listening, clipped speaker is the loud option — same fallbacks
     as Scout.
   - Honest limits: spoken languages are a SUBSET of text languages —
     speech recognition/TTS must support the language on the device.
     Where speech isn't supported, the same mode works as text
     conversation (type / show the screen). Dialects not imperative
     (see #4) — standard voices are fine.
   - PC version: same turn-based mode with mic + speakers — also
     usable across a video call.

6. **Easy-to-understand user guide, in the app** (Shawn, 2026-10-17)
   - Same pattern as Scout/Outpost's in-app universal guide (his
     "dummy proof" rule): plain language, no jargon, written for
     nontechnical users, searchable, covering EVERY feature — chat,
     voice/emotions, translator + 2-way mode, posts + scheduling,
     AI replies, roleplay, demo/presentation, fact cards, customer
     journey, QR kit, Today card, cross-posting, settings, updates,
     troubleshooting ("what to do when…", not just error codes).
   - Ask-the-guide by voice: "How do I schedule a post?" gets a
     spoken, step-by-step answer from the guide content.
   - First-run guided tour in plain steps; a help button on every
     screen explains that screen (UX rule: every control explains
     itself).
   - Guide translates with the app (any language) and works offline
     like the database. A one-page quick-start prints from the app.

## Scout-suggested additions (not yet approved by Shawn)
- Prospect pipeline: comment → invited → joined group → customer,
  with follow-up reminders so nobody falls through.
- Compliance checker: scan any draft (post/reply/message) for medical
  claims / restricted terms before it goes out.
- Content calendar: best-time suggestions from past post engagement.
- Customer care check-ins: day 3 / 7 / 30 draft messages for new
  customers, reorder (Subscribe & Save) reminders.
- Team duplication: team members get the same post generator + reply
  drafts with their own accounts (owner-neutral, per-user sign-in).
- Voice-note capture: dictate an idea → AI turns it into a post draft.
- ~~Vietnamese translation for posts/replies~~ — superseded 2026-10-17:
  Shawn asked for translation in ANY language (see Requested #4).

## Scout reuse rule for this app (Shawn, 2026-10-17)
"In fact use anything from scout that will make this app better" —
same rule as Nuri's, under the universal improvement rule (no-negative-
effects guard). Reuse as shared patterns/code, not a fork.

**Transfers in:**
- Voice stack: Kokoro + voice mods + emotions (Requested #3), Edge
  voices as extra selectable voices, spoken-friendly answer style.
- Interpreter engine + language-ID + timeout cascade (Requested #5),
  Bluetooth routing lessons (use the existing system connection;
  headset/speaker routing for conversation mode).
- "Ask the Cloud" escalation: light/on-device answers first, cloud AI
  for hard questions — grounded in the database, claim labels kept.
- Diagnostics card + one-tap self-test (standing rule): mic, voice/
  emotion test, translation packs, database version.
- Updater (standing rule): GitHub check, one subtle notification per
  version, update button — never forced.
- Settings UX: plain-word dropdowns (how well it hears you, how
  quickly it jumps in, personality strength), rename-your-assistant
  (on-device, per user), every control explains + confirms + gives
  feedback.
- Per-user on-device memory ("remember that…" pattern): the app
  remembers each user's own preferences/notes on their device only.
- Android home-screen mic widget; offline-first bundled database;
  download-after-install slimming; build/signing/release chain +
  Setup.exe packaging template.

**Connection rule (Shawn, 2026-10-17): NOTHING connects to laptop
Scout.** The app is fully standalone — no ThinkPad, no Tailscale, no
van LAN, no van-Scout tier in any cascade. Its AI tiers are on-device
+ generic cloud only. Reuse from Scout is code/design patterns, never
a live connection to his van system. (Anyone can use this app — nobody
else has his laptop, and his van stays private.)

**Intentionally NOT transferred (would not make this app better):**
- Van hardware: Shield/Outpost control, DVR, ALDL, deterrence, theft
  decoy, mirroring/casting, van-router features.
- Scout's name, branding, and sarcastic persona — this app keeps its
  own warm, business-safe character (voice engine only, see #3).
- Wake word: available tech, but v1 stays tap-to-talk as decided.

## Scout's "over the top" recommendations — APPROVED 2026-10-17 (Shawn: "Add all of them")
All 8 below are IN, plus the riders named with the offer: prospect
pipeline, compliance checker, content calendar (from the first
suggested list). Team duplication is covered by the owner-neutral
anyone design; voice-note-to-post is covered by Requested #3.
1. **Roleplay practice mode** — the AI plays a skeptical prospect
   (voice + emotions, any language); the user practices out loud; it
   coaches with compliant phrasing from the database. Uses every
   system we built: voice, emotions, translator, DB, compliance.
2. **60-second demo mode** — "Show me what you can do": voice Q&A with
   emotion, a live 2-way translation, a curiosity post drafted, a fact
   card made. The recruiting closer for team members (Tiara demo-mode
   lesson).
3. **Presentation mode** — voice-controlled product slideshow for
   coffee meetings / home parties / a TV on the PC version, official
   facts only, live translated captions.
4. **Fact cards** — one-tap shareable image cards (product fact +
   curiosity question), compliance-checked, any language, sized for
   posts and stories.
5. **30-day customer journey** — patch-day counter, placement-pointer
   reminders, private on-device feel-journal (never medical claims),
   sponsor check-in drafts on days 3/7/30, reorder nudge at day 25.
6. **My QR kit** — each user enters their own referral link at setup;
   the app makes their QR code + a printable one-pager for events.
7. **Today card** — one-glance business dashboard (diagnostics-card
   pattern): replies waiting with drafts ready, posts scheduled,
   follow-ups due, reorders due — every row one tap.
8. **Cross-posting** — one approval posts a curiosity post to the
   Facebook Page + Instagram + Threads, formatted per platform.
Plus the already-suggested core helpers from the first list (prospect
pipeline, compliance checker, content calendar, customer check-ins)
still awaiting a pick.
