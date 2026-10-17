# Lifewave AI App — Spec & Knowledge Database Foundation

*Phase 1 foundation, 2026-10-17. Builds on `research.md` (2026-09-23 briefing) — this spec does not duplicate it; it turns that research into a buildable app + database plan.*
*Phase 2 revision, 2026-10-17: `FEATURE-REQUESTS.md` is folded in full as §7. This file is now the single authoritative Phase 2 build spec; `FEATURE-REQUESTS.md` is retained as the historical log of how each decision was made, but where the two differ, this spec wins.*

> **Design note — 2026-10-17 (Shawn): OWNER-NEUTRAL, SINGLE EDITION.**
> Shawn: *"I don't want either version personalized to me, it should be usable by anyone."*
> This **supersedes the two-tier (shawn/team) model** drafted earlier the same day. There is now
> **ONE generic app and ONE database, usable by anyone** — no user's name, data, or personalization
> baked in (same owner-neutrality rule as the Tiara kit). Consequences, applied throughout this spec:
> (1) the entry schema has no tier field — every entry is `audience: "public"`;
> (2) the database is the anyone-safe database: official sources + own-words summaries of *general*
> knowledge only; group-internal material (protocols, group training internals) is **never content** —
> it appears only as pointer entries (§4); (3) a release build check fails if any user's name
> (e.g. "Shawn") appears in shipped content (§8).

## 1. Product decisions (locked by Shawn, 2026-10-17)

- **Form:** native easy-install apps for phone + PC — Android APK (download + tap to install, GitHub Releases, same pattern as Scout) and Windows `Setup.exe` (per Shawn's 2026-10-17 standing Windows rule). **One shared codebase: Flutter — LOCKED (no longer "proposed").** Both apps stay in sync and read the same database. Windows packaging follows the standing Windows easy-install rule: one `*-Setup.exe` (per-user install, no admin to install, Start Menu + Desktop shortcut, uninstaller in Settings, no runtime prerequisite for the user), built on a Windows runner — Flutter does not cross-compile to Windows from Linux, and no Windows exe is ever faked. The unsigned SmartScreen step ("More info → Run anyway") is documented in the README.
- **No browser dependency.** The PWA idea was scrapped by Shawn explicitly because voice "works best in Chrome/Edge" was not acceptable.
- **Fully standalone — NOTHING connects to laptop Scout.** The app never connects to the ThinkPad, Tailscale, the van LAN, or any van-Scout tier in any cascade. Its AI tiers are **on-device + generic cloud only**. Reuse from Scout is code/design patterns only, never a live connection (see §7.7). Anyone can use this app — nobody else has the laptop, and the van system stays private.
- **AI chat + AI voice required.** Tap-to-talk questions; **no wake word in v1.** Speech *input* uses the device's native speech recognition (STT). Spoken *output* uses **Scout's voice system — the Kokoro engine + Scout voice mods + emotion rendering** (§7.3) — this supersedes the earlier "device's native speech recognition + TTS" wording for output; the device's native TTS remains only as the fallback when the Kokoro model has not been downloaded or cannot run. Spoken answers are short and spoken-friendly (Scout voice lesson).
- **Audience: anyone.** Shawn and his team will use it, and so could any customer or distributor who installs it. One edition — see the design note above.
- **First-run personalization:** the app *may* ask each user for their own name/preferences, stored on their own device only. That is the user's data — never the builder's, never shipped.
- **Installer size target: ~20–30 MB.** Heavy assets (Kokoro voice model, on-device translation packs) are **download-after-install** only (Scout slimming pattern) — never bundled into the installer.
- **Branding: clearly LifeWave (Shawn, 2026-10-17 — full requirement in `BRANDING.md`).** Both apps carry a strong LifeWave visual identity: LifeWave logo on splash screen, app icon, and home/Today header; the LifeWave color palette as the app theme; official product pictures for every product entry. Full rules in §7.12 — including the guardrails (official assets as-is, never a fabricated logo; provenance logged in `ASSETS.md`; bundled brand imagery ≤ ~5 MB) and the independent-tool line carried in About / first-run tour / user guide: *"An independent Brand Partner tool — not an official LifeWave, Inc. app."*
- **iPhone:** Apple allows no APK-style install; iOS needs App Store / TestFlight. Later phase, not v1 (inferred from platform rules).

## 2. Sources

1. **Official LifeWave websites** — lifewave.com store + product pages (facts, prices, official benefit language), official pricing PDF (secure.lifewave.com). The primary anchor for database content.
2. **Facebook groups (read via facebook-cli; content rules in §3):**
   - LW Team Learning — 68k members — https://facebook.com/groups/1088773684574273/
   - LW Distributor Learning — 6k members — https://facebook.com/groups/328205680871899/
   Used to learn what topics matter, what general knowledge is commonly taught, and where group-internal material lives (for pointer entries) — **not** as a content source beyond own-words general knowledge.
3. **`research.md`** (2026-09-23) — existing briefing; background/company/funnel context already captured there.

## 3. HARD RULES (non-negotiable, from the groups' own rules + Shawn's standing boundaries)

- LW Team Learning's own rule: **do not copy group content outside the group.** Therefore:
  - Database entries are **summaries / extracted facts in our own words — never verbatim group posts, never copied protocols, never screenshots/transcripts.**
  - **Group protocols and group-internal training material are never database content.** They are represented only by pointer entries (§4).
  - Group discussion may inform *general* product/business knowledge entries (e.g. "distributors commonly pair X39 with X49"), written in our own words, with no protocol detail.
- **No public medical claims.** Health/product claims are always labeled: `official fact` (the company states it / it's verifiable) vs `distributor claim` (what distributors/groups say, not verified). The chat layer must preserve the label in answers and refuse to phrase distributor claims as facts.
- Testimonials: never presented as evidence of efficacy. Only *company-approved* testimonials from official pages may be quoted, labeled as testimonials. Group testimonials are not content (pointer only).

## 4. Single-edition, owner-neutral content model

- **One database, `audience: "public"` on every entry.** No personal editions, no hidden tiers.
- **Pointer entries** are the only trace of group-internal material. A pointer entry contains exactly: the topic, a one-line note that it is covered in the named group's guides/units, and the group link. Nothing else — no summaries of the material itself.
  Schema-wise a pointer is a normal entry with `topic: "group-pointers"`, `source_type: "group-official"` (it describes the groups' own published guide structure), and a body limited to the pointer text.
- **Owner-neutrality:** shipped content (db, app strings, examples) contains no user's name or personal data. Enforced by an automated release check (§8).

## 5. Database design

**Format choice: JSON — one JSON file per topic under `db/`, plus `db/manifest.json` as the index.**
Why JSON over Markdown-per-topic: the app (Flutter) parses JSON natively with no markdown dependency; field-based filtering (audience, claim label) is a comparison, not text parsing; entries stay diff-friendly in git (one entry = one object); and a manifest gives the app a cheap "what topics exist / how many entries / when updated" check for the updater. Markdown stays for human docs (this spec, HARVEST-LOG.md).

**Entry schema (every entry, no exceptions):**

```json
{
  "id": "prod-x39",
  "topic": "products",
  "title": "LifeWave X39® Patches",
  "body": "Own-words summary. Prices written as: US retail $X / Subscribe & Save $Y (USD, checked YYYY-MM-DD).",
  "audience": "public",
  "source_type": "official-site | group-official | group-summary",
  "source_ref": "URL or group name + link",
  "claim_label": "official fact | distributor claim",
  "updated": "YYYY-MM-DD"
}
```

- `source_type` values: `official-site` (lifewave.com / official PDFs), `group-official` (pointer entries and the groups' own public-facing structure), `group-summary` (own-words summary of *general* knowledge commonly taught in the groups — never protocols, never verbatim; use sparingly).
- Optional product fields (used in `db/products/products.json`): `item_code`, `price_retail_usd`, `price_subscribe_usd`, `category` (`patch | bundle | nutrition | skincare | device | legacy`).
- Prices are US store prices at check date — flagged volatile; re-verify at each harvest pass.

## 6. Harvest plan (topic-by-topic, in build order)

*Statuses updated 2026-10-17 to match HARVEST-LOG.md reality (Pass 1 + Pass 2 complete; Pass 3 in progress). Manifest at `db_version` 2, 44 entries, after Pass 2.*

| # | Topic (db file) | Content | Status |
|---|---|---|---|
| 1 | `products` | Full current lineup from the official store: name, company-stated purpose, US prices, item codes | **Done — Pass 1, 2026-10-17** (25 current US items + 1 legacy = 26 entries; 10 entries deepened in Pass 2) |
| 2 | `group-pointers` | Pointer entries for group-internal material (protocols, condition-specific patching, testimonials, training systems) | **Done — Pass 1, 2026-10-17** (5 pointers) |
| 3 | `phototherapy` | How the company says phototherapy/patches work (official explanation), company history/founder facts | **Done — Pass 2, 2026-10-17** (3 entries) |
| 4 | `usage` | Official general usage only: placement generalities from official pages, wear time (up to 12 hrs), hydration note, official warnings (external use, not for children, AcuLife horses-only) | **Pass 3 in progress, 2026-10-17** |
| 5 | `faq` | FAQs & objection handling at general-knowledge level: price, "is it a drug?", how to buy through a referrer, guarantees (90-day retail/preferred, 30-day Brand Partner per official pages), patch counts per sleeve | **Pass 3 in progress, 2026-10-17** |
| 6 | `business` | Business basics from **official sources only**: Brand Partner model, retail vs Subscribe & Save pricing, BV concept, enrollment kits from official opportunity docs | **Done at officially-published level — Pass 2, 2026-10-17** (5 entries). Deeper comp-plan detail is **not public** — no current complete plan document is posted on lifewave.com; current terms live in the Brand Partner Back Office, so no current percentages/bonus figures are entered (see HARVEST-LOG Pass 2) |
| 7 | `playbook` | Curiosity-post playbook at style level: question-led posts, comment → invite-into-group funnel, compliance do/don't list (no medical claims, no forbidden cure words), original template patterns written by us | **Pass 3 in progress, 2026-10-17** |
| 8 | `testimonials` | Company-approved testimonials from official product pages only, labeled as testimonials | **Done — Pass 2, 2026-10-17** (2 entries, from the company's approved-testimonials program on official replicated sites; store product pages themselves carried none in text fetch) |
| 9 | `company` | Company background (research.md + official "Our Story"): founded 2004, David Schmidt, Draper UT HQ, global footprint | **Done — Pass 2, 2026-10-17** (3 entries; Draper UT HQ not yet in an entry — it appears in company press releases but was not on the official pages fetched in Pass 2, so it was not entered) |

Harvest method per topic: (a) official site first (facts anchor), (b) facebook-cli `groups posts --query` passes on both groups to learn topic coverage and general knowledge, (c) write own-words entries or pointer entries, (d) log queries/counts/gaps in HARVEST-LOG.md. Group search returns relevance-ranked recent results with paging cursors — coverage is topic-level across passes, never a full scrape (bulk scraping is also prohibited by the connector rules).

## 7. Phase 2 feature spec

*Everything in this section is folded in from `FEATURE-REQUESTS.md` (logged 2026-10-17). Disposition of every item in that file is accounted for in §7.10 — nothing is dropped silently.*

### 7.1 Requested #1 — Curiosity-post posting + scheduling

- The app generates curiosity posts from the database in the groups' question-led style, **compliance-checked before queueing** (see the compliance checker, §7.9).
- **Scheduling mechanics (platform reality, stated plainly in the app):**
  - Full native scheduling works on a Facebook **Page** — 10 minutes to 29 days ahead, reschedule/cancel supported.
  - Personal **profile** posts **cannot** be scheduled by apps. For profiles the app queues the post and **reminds the user at the chosen time for a one-tap post**.
- **Every post gets human approval before it is queued/sent.** No exceptions, no auto-posting.
- Live posting is subject to the honesty rule in §7.11: a standalone app can only post live through **each user's own account connection**; v1 ships the draft/queue/approval UX plus documented integration points and never fakes a send.

### 7.2 Requested #2 — AI-assisted replies (never silent-send)

- Scope: comments on the user's posts and Messenger messages. The AI drafts replies in the established style — answer briefly, invite into LW Team Learning, no medical claims, coded language for restricted terms.
- Mode: **draft + one-tap approve / edit / send. Each send is individually approved — no silent auto-sending, ever.**
- Pre-approved template answers for common FAQs are the fastest path *within* that rule — a template still goes out only on the user's tap.
- Same honesty rule as §7.1: reading a user's comments/messages and sending on their behalf requires that user's own account connection; v1 ships drafts/approval UX + documented integration points.

### 7.3 Requested #3 — Voice, like Scout, with emotions

- **Input:** dictate a post idea or a question by voice (native STT, §1). This also covers the old "voice-note capture" suggestion — dictate an idea → AI turns it into a post draft.
- **Output:** spoken answers use Scout's voice system, **not** the device's plain robot TTS:
  - **Kokoro engine + Scout's voice mods** (prosody: pitch / breath / pacing / pauses) — the shared voice stack, under the universal improvement rule (voice improvements push to all builds).
  - **Full emotion range like Scout:** chuckle, full laugh, sighs, surprise, empathy. The AI marks the emotion; the renderer produces it **in the selected voice** — the laugh follows voice changes, never a stock clip of a different person.
  - The user picks **their own voice on their own device** (owner-neutral). Edge voices transfer in as extra selectable voices (§7.7).
  - **Emotion-level setting** per user (Nuri's dropdown pattern — plain-word levels: Calm / Gentle / Warm / Expressive / Full-hearted), **default Warm**.
  - An **emotion self-test button ships in the app** (diagnostics rule, §7.7) so the user can hear each emotion in their selected voice on demand.
- **Persona distinction:** same voice *engine* as Scout, but the assistant's character is Lifewave-appropriate — **warm, professional, business-safe** — not Scout's sarcastic persona. Users may rename their assistant (on-device, per user; §7.7).
- **Cost control:** the Kokoro voice model is a **download-after-install** asset (Scout slimming pattern) so the installer stays in the ~20–30 MB target. Until/unless it is downloaded, spoken output falls back to device TTS and the app says so plainly.

### 7.4 Requested #4 — Translation, any language

- Applies to: chat Q&A (ask and be answered in your language), curiosity-post drafts, and incoming comments/Messenger replies.
- Design: **on-device translation packs (~59 languages, offline after download) + cloud fallback for the long tail (100+ languages, needs internet).** "Any language" means the full list these engines cover — no engine covers every language on Earth, and the app must not claim otherwise.
- **The compliance check runs on the final-language text**, not just the English draft — translation must not soften claim labels or introduce medical claims.
- **Dialects: NOT imperative for this app** (Shawn, 2026-10-17). Standard single-voice support per language is acceptable; dialect-specific engines are a nice-to-have, never a build blocker. Named tradeoff: a Southern Vietnamese speaker gets a standard/Northern-leaning voice and STT tuned to standard Vietnamese — understandable, less natural. **Scope: this downgrade is Lifewave-only** — the hard Southern-Vietnamese requirement on the van translator flagship + standalone translator stays in full force and is unaffected.

### 7.5 Requested #5 — 2-way conversation translator

- Face-to-face interpreter mode for talking with prospects/customers in person: you speak your language, the app speaks theirs aloud; they reply, the app speaks yours.
- Reuses the Scout interpreter design already built (2026-10-16): **turn-based; auto language detection per turn or manual toggle; split-screen transcript (original + translation per turn); timeout cascade so a turn never hangs — on-device first, cloud second.** There is **no van-Scout tier** in this app's cascade (§1, §7.7).
- Audio routing (Scout fallbacks): phone speaker for their side by default (like Google Translate conversation mode); a Bluetooth headset gives private listening; a clipped speaker is the loud option.
- **Honest limits, stated in the app:** spoken languages are a **subset** of text languages — speech recognition and TTS must support the language on the device. Where speech isn't supported, the same mode works as a **text conversation** (type / show the screen). Dialects not imperative (see §7.4) — standard voices are fine.
- PC version: the same turn-based mode with mic + speakers — also usable across a video call.

### 7.6 Requested #6 — Easy-to-understand in-app user guide

- Same pattern as Scout/Outpost's in-app universal guide (the "dummy-proof" rule): **plain language, no jargon, written for nontechnical users, searchable, covering EVERY feature** — chat, voice/emotions, translator + 2-way mode, posts + scheduling, AI replies, roleplay, demo/presentation, fact cards, customer journey, QR kit, Today card, cross-posting, settings, updates, and troubleshooting in "what to do when…" form (not just error codes).
- **Ask-the-guide by voice:** "How do I schedule a post?" gets a spoken, step-by-step answer from the guide content.
- **First-run guided tour** in plain steps; a **help button on every screen** explains that screen (UX rule: every control explains itself).
- The guide **translates with the app (any language)** and **works offline** like the database. A **one-page quick-start prints** from the app.

### 7.7 Scout reuse rule (Shawn, 2026-10-17)

*"Use anything from Scout that will make this app better"* — same rule as Nuri's, under the universal improvement rule (no-negative-effects guard). Reuse is **shared patterns/code, not a fork**.

**Transfers in:**
- Voice stack: Kokoro + voice mods + emotions (§7.3), Edge voices as extra selectable voices, spoken-friendly answer style.
- Interpreter engine + language ID + timeout cascade (§7.5); Bluetooth routing lessons (use the existing system connection; headset/speaker routing for conversation mode).
- "Ask the Cloud" escalation: light/on-device answers first, cloud AI for hard questions — **grounded in the database, claim labels preserved**. (Generic cloud only — never van Scout, see the connection rule below.)
- Diagnostics card + one-tap self-tests (standing rule): mic, voice/emotion test, translation packs, database version — plus a plain-language health/status view, so "it's not working" becomes a screenshot instead of a guessing game.
- Updater (standing rule): GitHub check, one subtle notification per version, an update button the user taps to apply — never forced, never silent auto-install.
- Settings UX: plain-word dropdowns (how well it hears you, how quickly it jumps in, personality/emotion strength), rename-your-assistant (on-device, per user); **every control explains itself, confirms consequential changes, and gives feedback** (standing UX rule).
- Per-user on-device memory ("remember that…" pattern): the app remembers each user's own preferences/notes **on their device only**.
- Android home-screen mic widget; offline-first bundled database; download-after-install slimming; build/signing/release chain + `Setup.exe` packaging template.

**Connection rule (Shawn, 2026-10-17): NOTHING connects to laptop Scout.** The app is fully standalone — no ThinkPad, no Tailscale, no van LAN, no van-Scout tier in any cascade. Its AI tiers are on-device + generic cloud only. Reuse from Scout is code/design patterns, never a live connection to the van system.

**Intentionally NOT transferred (would not make this app better):**
- All van hardware features: Shield/Outpost control, DVR, ALDL, deterrence, theft decoy, mirroring/casting, van-router features.
- Scout's name, branding, and sarcastic persona — this app keeps its own warm, business-safe character (voice *engine* only, see §7.3).
- Wake word: the tech is available, but v1 stays tap-to-talk as decided.

### 7.8 Over-the-top set — APPROVED 2026-10-17 (Shawn: "Add all of them")

All 8 are IN:

1. **Roleplay practice mode** — the AI plays a skeptical prospect (voice + emotions, any language); the user practices out loud; it coaches with compliant phrasing from the database. Uses every system built: voice, emotions, translator, DB, compliance.
2. **60-second demo mode** — "Show me what you can do": voice Q&A with emotion, a live 2-way translation, a curiosity post drafted, a fact card made. The recruiting closer for team members (Tiara demo-mode lesson).
3. **Presentation mode** — voice-controlled product slideshow for coffee meetings / home parties / a TV on the PC version; **official facts only**; live translated captions.
4. **Fact cards** — one-tap shareable image cards (product fact + curiosity question), compliance-checked, any language, sized for posts and stories.
5. **30-day customer journey** — patch-day counter, placement-pointer reminders (pointers only — §3/§4 still apply; the app points to where placement guidance lives, it does not ship protocol content), private on-device feel-journal (never medical claims), sponsor check-in drafts on days 3/7/30 (see also §7.9 check-ins), reorder nudge at day 25.
6. **My QR kit** — each user enters **their own** referral link at setup; the app makes their QR code + a printable one-pager for events. (The referral link is the user's own data, entered by them, stored on their device — owner-neutrality is preserved because nothing is baked in.)
7. **Today card** — one-glance business dashboard (diagnostics-card pattern): replies waiting with drafts ready, posts scheduled, follow-ups due, reorders due — every row one tap.
8. **Cross-posting** — **one approval** posts a curiosity post to the Facebook Page + Instagram + Threads, formatted per platform. Subject to the §7.11 honesty rule: each platform send goes through the user's own account connection; v1 ships the approval/formatting UX + documented integration points and never fakes a send.

### 7.9 Approved riders

Named with the over-the-top approval and IN:

- **Prospect pipeline** — comment → invited → joined group → customer, with follow-up reminders so nobody falls through. Pipeline data is the user's own, on-device.
- **Compliance checker** — scan any draft (post / reply / message / fact card / translated final text) for medical claims and restricted terms **before** it goes out. This is the enforcement point for §3 inside every content-producing feature (§7.1, §7.4, §7.8).
- **Content calendar** — best-time suggestions from past post engagement, alongside the §7.1 queue/schedule.
- **Customer check-ins** — day 3 / 7 / 30 draft messages for new customers, plus reorder (Subscribe & Save) reminders. **Dual-homed by design:** check-ins also live inside the 30-day customer journey (§7.8 item 5, which carries the day 3/7/30 drafts and the day-25 reorder nudge). One implementation, surfaced in both places — not two separate check-in systems. Check-in messages are drafts: the §7.2 rule applies — sent only on the user's tap.

### 7.10 Disposition of the original "Scout-suggested" list — nothing dropped silently

| Suggested item (FEATURE-REQUESTS.md) | Disposition |
|---|---|
| Prospect pipeline | **Approved** — rider, §7.9 |
| Compliance checker | **Approved** — rider, §7.9 |
| Content calendar | **Approved** — rider, §7.9 |
| Customer care check-ins | **Approved** — rider, §7.9; also inside the journey, §7.8 item 5 |
| Team duplication | **Covered** by the owner-neutral anyone design (§1, §4): every team member installs the same app and uses it with their own accounts/data — no separate duplication feature is built |
| Voice-note capture (dictate idea → post draft) | **Covered** by Requested #3 (§7.3 voice input) |
| ~~Vietnamese translation for posts/replies~~ | **Superseded** 2026-10-17 by Requested #4 — translation in ANY language (§7.4) |

**Conflicts noted, not deleted:**
- *Live posting vs §8 security posture (no Facebook credentials in the app).* §7.1/§7.2/§7.8 ask for posting, replies, and cross-posting, while the database-phase rule was "the app never logs into Facebook." Resolution (§7.11 honesty rule): v1 ships draft/queue/approval UX + documented integration points; any future live send uses **each user's own account connection** (their own OAuth/app connection on their own device) — the app ships with no one's credentials baked in, stores no Facebook password, and never simulates a send.
- *Scheduling expectation vs platform reality.* "Scheduling" cannot mean native scheduled profile posts — Meta does not allow apps to schedule personal-profile posts. The spec keeps the honest mechanic (§7.1): Page = true scheduling; profile = queue + timed reminder + one-tap post.
- *FEATURE-REQUESTS.md internal tension.* Its closing line says the core helpers were "still awaiting a pick," while its own header records Shawn's "Add all of them" approval of the 8 + riders. This spec follows the approval (confirmed again in the Phase 2 go-ahead, 2026-10-17): all riders are IN (§7.9).

### 7.11 Build order — Phase 2 milestones

*Phases 1–2 of the original plan (spec + db foundation; harvest) are complete except the Pass 3 topics (§6). The app build proceeds in milestones:*

- **M1 — Skeleton + data + chat:** Flutter project skeleton (Android + Windows targets); **LifeWave branding foundation (§7.12): palette theme, splash screen, app icon, header logo, brand-asset bundle + `ASSETS.md`**; database loading from the bundled JSON + manifest/`db_version` handling; offline search/retrieval over entries; product catalog cards showing the official product picture per entry (§7.12); chat Q&A (on-device retrieval first, answers grounded in retrieved entries with claim labels preserved; cloud-escalation *interface* defined and stubbed behind it); diagnostics card (standing rule: DB version, mic status, self-tests); Today card shell (§7.8 item 7, rows wired as data arrives in later milestones) with the branded header.
- **M2 — Voice + translator:** native STT input; Kokoro voice path with emotion rendering + emotion-level setting + emotion self-test (device TTS fallback until the model is downloaded); translation (on-device packs + cloud fallback, compliance check on final-language text); 2-way conversation translator (§7.5) with timeout cascade and text-conversation fallback.
- **M3 — Social:** curiosity-post generator + draft/queue/approval + Page-schedule vs profile-reminder mechanics; AI reply drafts (approve/edit/send UX); compliance checker; fact cards (branded template + the product's official picture, §7.12); content calendar; prospect pipeline.
- **M4 — Extras + guide:** roleplay practice, 60-second demo (branded, product pictures), presentation mode (branded slides with official product pictures + logo), 30-day customer journey + check-ins, My QR kit, cross-posting UX; the in-app user guide (§7.6, branded cover page) + first-run guided tour (carries the §7.12 independent-tool line) + per-screen help.
- **M5 — Updater + packaging:** updater per the standing rule (GitHub check against the `smartyourtv/lifewave-app` repo, one-time notification per version, tap-to-apply); Android signed release APK via the local toolchain (same signing/release pattern as Scout); Windows Flutter build + Inno Setup `Setup.exe` packaging per the windows-health packaging template — **the Windows build compiles on a Windows runner only**; GitHub Release + `version.json` update; §8 release checks must pass before publishing.

**Finalization — laptop-Scout export (Shawn, 2026-10-17; after M5, gated on database completion):** once the database is COMPLETE — Back Office gap-fill material (current comp plan, Policies & Procedures, Earnings Disclosure, brand assets) integrated, manifest/`db_version` bumped, and the owner-neutral + compliance audits passing — produce `~/workspace/lifewave/laptop-scout-export/` containing (a) the full DB JSON set as shipped in the app and (b) `lifewave-knowledge-base.md`, a readable rendering of every entry formatted for the ThinkPad knowledge pipeline (same pattern as the van knowledge base + first-aid library: header block naming its laptop home `~/scout/knowledge/lifewave-knowledge-base.md`, purpose, source basis; behavior rules preserving claim labels and the no-medical-claims rule; entries grouped by topic). It rides the existing usb-prep knowledge payload to the laptop. **This is a one-way data copy into the builder's personal van Scout — it does NOT connect the Lifewave app to laptop Scout (§1/§7.7 connection rule stands unchanged): the app stays standalone for every user; only the finished database is also copied, as data, into one personal knowledge library.**

**Honesty rule (applies to every milestone):** live Facebook/Instagram/Threads posting from a standalone app needs **each user's own account connection** (and, for real distribution, Meta app review). v1 therefore ships the draft/queue/approval UX + documented integration points — **no faked sends, no simulated "posted" states.** Any UI state must say what actually happened (drafted / queued / reminder set / handed to the platform share sheet / sent through the user's connection).

**Size rule:** installer target ~20–30 MB; heavy assets (Kokoro model, language packs, Edge-voice extras) are download-after-install only (§1).

**Later (unchanged):** iOS via TestFlight/App Store if wanted.

### 7.12 Branding & visual identity (Shawn, 2026-10-17 — source: `BRANDING.md`)

Both apps (Android + Windows) are **clearly LifeWave-branded, with pictures and logos**:

- **Logo & identity:** the LifeWave logo appears on the splash screen, the app icon, and the home/Today header. The LifeWave color palette is the app theme throughout. Branding surfaces: splash, app icon, home/Today header, product catalog, demo mode, presentation mode, fact cards, and the user guide cover page.
- **Product pictures:** every product entry (the 26 in `db/products/`, incl. legacy) has an official product picture, used on its catalog card, its fact cards, and its presentation/demo slides. Pictures come from **official LifeWave public pages only**.
- **Provenance:** every brand asset (logo, palette source, each product image) is recorded in **`ASSETS.md`** with its source URL + retrieval date. No asset ships without a provenance row.
- **Size discipline:** bundled brand imagery is compressed (WebP thumbnails) and totals **≤ ~5 MB added** — the ~20–30 MB installer target (§1) is not negotiable for pictures. Any larger imagery follows the download-after-install pattern instead.
- **Guardrails (hard):**
  - Official assets are used **as-is** — never redraw, trace, or fabricate a fake "official" logo. If a clean official logo file cannot be sourced, ship the LifeWave name in clean wordmark text styling and log the gap in `BUILD-STATUS.md` — do not invent one.
  - Product images illustrate **official product entries only** — no group photos, no copied group content, no testimonial imagery implying results (§3 applies to pictures too).
  - **Independent-tool line:** the About screen, the first-run tour, and the user guide each carry, clearly readable: *"An independent Brand Partner tool — not an official LifeWave, Inc. app."* Main branding stays clean — the line lives in About/guide/store listing, not splashed across the UI. It protects the builder and the groups from any implication of company endorsement.

## 8. Audits (standing rules, applied before building)

The two standing audits for this app are written in full as separate files and are part of this spec by reference:

- **`CHANGE-IMPACT-AUDIT.md`** (same directory) — the 9-item change-impact audit for building Phase 2: blast radius, regression risk, cross-build effects, data & compatibility, permissions & security, behavior changes, performance, rollback, test plan.
- **`PRE-BUILD-AUDIT.md`** (same directory) — the 6-item pre-build audit: permissions↔API matching, null-safety/error handling, API misuse, protocol contracts, security, dependency/version check. Run/refresh it at each milestone gate (M1–M5), not once.

**Release checks (seeded here; enforced at M5 — a failure blocks packaging):**
- **Owner-neutrality check (automated, fails the build):** grep shipped db + app strings for the builder's name and personal data ("Shawn", personal emails/IDs) — any hit fails packaging. Same check pattern as windows-health's validate_packaging.py.
- **Content check (automated):** every entry has `audience: "public"`, a `claim_label`, and a `source_ref`; no entry body matches harvested group text (spot-diff against harvest samples); pointer entries contain a group link and nothing beyond topic + pointer line.
- **Branding checks (§7.12, enforced at M5):** every shipped brand asset has a provenance row in `ASSETS.md` (source URL + retrieval date); bundled brand imagery totals ≤ ~5 MB; every product entry has an official picture or a logged gap; the independent-tool line — *"An independent Brand Partner tool — not an official LifeWave, Inc. app."* — is present in the About screen, first-run tour, and user guide; no fabricated/redrawn logo ships (wordmark-text fallback + logged gap is the only alternative).
- **Biggest-risk note (carried from the Phase 1 audit):** the largest risk in this product is *content*, not code — a protocol or verbatim group text slipping into the database or a generated post would break the groups' own rule and expose any distributor who ships the app. Mitigations: pointer-only rule (§3–4), claim/audience fields required by schema, compliance checker on every outbound draft (§7.9), per-batch HARVEST-LOG review, and the release checks above.
