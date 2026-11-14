# Cabin Pairing and Direct Conversation Plan

> Use subagent-driven-development. Tests first for changed behavior; preserve data and approved village baseline.

Goal: Empty unpaired cabin -> explicit pairing/QR -> one egg, independent summoned buddy, click-to-converse backend chat.
Spec: docs/superpowers/specs/2026-11-14-cabin-pairing-direct-conversation-design.md
Base: 4d1374b already includes prior named branch and approved village UI (Unity202passed).

## Shared contracts
- New app view `pairing`; action `scanPairingQr`; optional controller callback `Future<PairingCredentials?> Function()? pairingScanner` supplied by host.
- Pair success automatically navigates cabin; cancel/failure stays pairing with no egg grant.
- No unconditional fake ensureTripEgg at initialize. Existing real restore/grant ledger unchanged.
- `CompanionLearningController.openConversation(requestId)` sends backend /turn action greet; child followups use chat. mode only closed/chat for new UI. Retain legacy public methods if tests/old clients need them, not exposed in new UI.
- Server greet + chat own narrative/persona; app metadata-only manifest unchanged. No authored long-story substitute for absent model key.

## Task1 phone cabin routing
Own UnityAppController and its routing/learning/story/demo/fixture tests. New pairing view/action/callback; empty cast unless connected and explicitly selected/newhatch buddy, no automatic collected friends. Remove fake auto pairing; pair/scan success invokes existing GameController pair grant and returns cabin. Keep exactowned summon, egg independent. Coordinate direct-chat API with task3 and QR callback with task4.

## Task2 Unity flow
Own Unity app UI/DTO/StoryOverlay adapter and editmode tests. Empty disconnected cabin only connect button; pairing form with QR/direct fields. Hide experimental story UI in this app flow, retain village. Connected cabin renders egg care independent of buddy; direct chat head bubble+composer, no menu/story/next controls. QR invokes scanPairingQr. Tests head/control/modal ownership and independent egg display before export.

## Task3 backend/direct dialog
Own server/affinity and phone/lib/learning + corresponding learning tests. Implement greet and free chat using server persona/fixed background+curated knowledge and transient six-pair context. No scripted chapter advancement new UI; backend authored actions retained compatible. Preserve parent-frequency server counter, identity/cancellation and no persistent transcripts. Click-to-open and close/reopen same-session context with tests; source/mode correlation validated.

## Task4 QR host
Own UnityAppScreen, explore/unity_channel.dart and new QR handoff tests. Use existing QrPairingScreen on main Flutter engine after closeUnityExplore, then reopen Unity via native open. Register callback only when host owns it; respect injection/dispose. Test success/cancel/lifecycle/unavailable; no new QR dependency or secondary engine.

## Parent
Integrate and independently review. Update docs/launcher/evidence, full Flutter/core/Unity/server + relevant static checks, export/build and emulator flow. Physical optical QR and real-model quality stay separately reported. Keep requests/generation guarded through QR/STT/profile changes. No remote deploy/merge unless separately requested.

## Task5 on-demand actions (Unity)
Latest user requested single iPhone-like action control, not permanent bars. Reuse existing action routes inside grouped sheet, no phone/backend domain change. Tests one content action control, sheet lifecycle/target grouping, no self-disabling gate, outside dismiss, native input and existing egg-terminal cleanup. Re-export/build after source green; prior Flutter499/server53 remain applicable while Unity-only presentation changes are verified separately.

## Completed verification
All five tasks integrated. Flutter500/core93/server53/Unity220 passed; village PlayMode2 and QR handoff9 passed. Export and debug APK build succeeded. API36 emulator verified camera handoff/cancel, manual synthetic pairing, direct character chat error UI without a provider key, and independent egg/buddy care. Final pill/sheet capture checked after antialiasing update. See docs/verification/2026-11-14-cabin-pairing-direct-conversation.md. Real provider dialogue and physical vehicle QR remain unverified.
