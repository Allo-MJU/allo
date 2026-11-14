# Trip Egg and Character Invitation Implementation Plan

> Workers: use subagent-driven-development, meaningful failing tests before code, preserve existing data and unrelated edits.

Goal: One automatic egg per trip with carryover; Friends summons and head-anchored click dialogue.
Spec: docs/superpowers/specs/2026-11-14-trip-egg-character-invitation-design.md
Architecture: GameController owns trip/egg lifecycle, UnityAppController owns exact selected learning target and request lifetime, Unity owns hit detection and anchored presentation. Server owns personal dialogue via /turn; client renders server-approved responses and stores only approved references.

## Constraints / Review focus
- Reconnect/restart/terminal/tier bypass must not grant twice.
- A→B carryover consumes B opportunity; preserve egg ID/progress and retry unsaved hatch before changing target.
- Preserve ETA hatch duration and distance fallback, remove all repeating grants.
- No automatic selection narration/idle invitation bypassing tap.
- Head controls target exact owned instance; no input/TTS overlap with experiments/notebook.

## Task1 core and storage (trip_rules agent)
Own GameController, DexStore, allo_core incubation schedule and related lifecycle/core tests, legacy Flutter pairing screen calls. Add tests covering above trip cases, run red, add persistent profile/session ledger and automatic pair grant/resume with serialized writes, remove repeating logic, run relevant/full tests. Public API `ensureTripEgg({EggTier tier=EggTier.small, bool useAffinity=true}) -> Future<bool>`; pair/restore invokes internally when ready. Manual start cannot bypass policy. Demo lifecycle also has identity. Coordinate fake initialization with task2. Do not edit UnityAppController.

## Task2 phone interaction routing (invitation_phone agent)
Own UnityAppController, CompanionLearningController and related phone routing/controller tests. Consume ensureTripEgg; initialize/resume fake trip without cabin selector. Friends selectCarCompanion success also selects same learning creature silently. New actions companionTapped(creatureId/speciesId), listenStory, talkToCompanion, closeCompanionInvitation; old storyNext/repeat/chat internals retained behind target/lifetime gate. Snapshot learning adds invitationOpen, conversationMode (closed/menu/story/chat), invitationText; existing text now transient bubble content. Disable select auto narration and idle invites by explicit policy. No changes to GameController or Unity. Tests first: silent summons, wrong/stale targets, click-gated options, modal/foreground cancellation, removed startEgg intent.

## Task3 Unity presentation (invitation_unity agent)
Own Unity App UI, CritterDirector/TapInput head event, bubble presentation and editmode tests. Remove cabin selectors/start panels and permanent learning sheet. Friends button sends selectCarCompanion and goes cabin on success. Head bubble follows actual companion and offers two choices. New Flutter bridge event companionTapped includes speciesId, App UI forwards valid exact selected creature action; no pose/reward side effects for invitation tap. New actions/snapshot from task2 coordinate immediately. Compact story/chat bubbles and existing mic/text/next/repeat functionality remain usable. Preserve common care and experiment overlay. Tests first for gates/anchors/input exclusivity, Unity compile/full suite and screenshots.

## Task4 integration / verification (parent)
Update current schema/affinity/schedule docs to new product policy. Run complete Flutter/core/Unity suites and scoped analyze. Independent review/fix, export/build, emulator UI verification preserving data if available. Record limits and commit. No provider API key required for these source changes; no remote deployment.

User already authorized functionality and answered carryover policy; proceed without another execution-method approval. Reuse clean managed feature worktree on new branch from latest dev.

## Task5 backend conversation authority (learning_server + invitation_phone)
User additionally required backend-owned dialogue/personas. Server owns authenticated /turn invite/listen/next/repeat/chat, persona/catalog lookup and resulting scene/text/canNext. Phone sends intents and renders only; replace rich bundle with ID-only manifest and preserve returned reference locally, no local story fallback. Keep /chat backward-compatible. Test server no-key authored turns, request correlation/invalid actions, ID-only manifest and client no local advance/offline fabrication. Then redo affected full Flutter/server suites. Root updates local launcher with keyless authored mode and verifies actual backend+emulator.

## Completed verification

2026-11-14: Flutter479/core93/Unity189/server48/launcher2/vehiclefixture2 passed. App/server HTTP checked12 stories×4 authored turns. APK built, installed preserving data and actual head-menu/story/next observed; APK manifest checked ID-only. Evidence and limits: `docs/verification/2026-11-14-trip-egg-companion-invitation.md`. Generated asset churn and concurrent separate village-detail changes excluded from this feature commit.
