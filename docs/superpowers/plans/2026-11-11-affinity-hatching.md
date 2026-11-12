# Affinity Hatching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan. User authorized parallel independent tasks and implementation without waiting for team pre-approval.

**Goal:** C-owned affinity hatching, photo gate and demo API with saved state and current controller integration.
**Architecture:** Pure Dart round → existing Flutter controller/store → authenticated Python demo service. Original app flow remains opt-in legacy compatible until UI input providers are wired. No backend deployment or real-device success claim without evidence.
**Tech Stack:** Dart/Flutter existing SDK, Python3 stdlib HTTP+SQLite with Pillow for safe image re-encoding, OpenAI Responses REST.
**Spec:** docs/affinity-hatching.md (user-selected rules; supersedes old draft).

## Global Constraints
- score0..100; speech +12/60s, -12 immediately, neutral0; speech180s, pet+3/10s, placement+7/15s; wrong/cooldown vibrate.
- 4 zone IDs, successful placement chooses a different preferred zone; no re-roll on failure.
- Mandatory photo gate at50, authenticated remote receipt +15 once, immediate hatch at100 after quest.
- Existing ETA/deferred/distance arithmetic; next egg30min from actual success; active-time pause preserved.
- No raw speech/text persistence/logging; OpenAI key server-only; authenticated cross-device demo photo retrieval; no RTDB image/raw text.
- Separate file ownership. Core agent owns only affinity_round.dart/test and allo_core export. Server agent owns only server/affinity. Client agent owns only phone/lib/affinity/egg_demo_api.dart and its test. Root owns controller/models/store/docs.

## Review Focus
- Deadline ties, delayed passive credit, no reward across photo gate.
- Stale asynchronous completion after session/egg/lifecycle changes.
- Crash between pending result and dex insert; stable ID idempotency.
- Photo spoofing/type/size/auth and exact request/egg correlation.
- Existing time-based controller tests and newest Unity lifecycle preserved.

### Task 1: Pure affinity round
Files: core src/affinity_round.dart, test/affinity_round_test.dart, allo_core.dart export.
Public API: AffinityRound.start/fromJson, advanceTo, speak, pet, place, confirmPhoto, discard and toJson. Tests use literal values at boundaries, save/restore, photo gate and random target.
- [x] RED semantic failing tests, then minimal state machine implementation.
- [x] Focused dart test; full core suite; report red/green evidence.

### Task 2: Demo API service
Files: server/affinity/app.py, tests/test_app.py, requirements.txt, README.md, .gitignore.
- [x] Tests first: actual local HTTP auth/oversize/bad JSON/photo encode+GET+idempotency; provider DI only at external API.
- [x] Implement fixed REST contract; structured schema and sanitized failures; no content logs.
- [x] Run unittest entire server suite; live provider only if authorized key configured.

### Task 3: Phone API client
Files: phone/lib/affinity/egg_demo_api.dart; phone/test/egg_demo_api_test.dart.
- [x] Local HTTP server tests fail first for body/correlation/auth/timeouts/bytes.
- [x] dart:io client, strict response parsing, no provider key, no raw errors/content logging.
- [x] Run focused Flutter test and report.

### Task 4: Controller/storage integration
Files: GameController, core models, DexStore, new affinity integration tests; docs/schema.md.
- [x] Add opt-in useAffinity to startIncubating, state restoration and tick/interaction APIs.
- [x] Score/photo/time gating and stable sourceEggId before reward publication, late response guards.
- [x] Tests RED→GREEN for early hatch/30min repeat, deadline failure, gate, restore and storage retry.
- [x] Full core+phone+server suites; analyze; independent branch review.
Publication follows the reviewed implementation: push a feature PR and update #61/#54 with selected rules/evidence. No merge or issue close without completion review.

## Verification result

Core 70 tests, phone 242 tests, server 24 tests passed. Cross-language HTTP smoke passed with synthetic evaluation. Independent review findings fixed and re-reviewed. Provider key absent; live classification quality, deployment and native UI/device verification remain excluded. `dart analyze` reports no errors/warnings and two existing library infos; Flutter analysis wrapper hit an analysis-server JSON error.
