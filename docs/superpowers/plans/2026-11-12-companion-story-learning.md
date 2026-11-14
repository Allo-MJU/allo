# Companion Story Learning Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development. Steps use checkbox tracking.

**Goal:** Provide common pre/post-hatch care and fixed-story persona-based learning for age 10.
**Architecture:** Existing Dart controllers retain authority. Separate learning controller owns selected creature/story progress; server owns authored content and AI prompts; Unity displays intentions/results, Android supplies speech.
**Tech Stack:** Dart/Flutter, Unity C#, Python stdlib service, Android native speech.
**Spec:** docs/superpowers/specs/2026-11-12-companion-story-learning-design.md

## Global Constraints
- Eggs never speak; seven common care actions work before/after hatching.
- Fixed story only; explicit next action advances; no AI authority over progress or rewards.
- Age10, optional occasional parent prompts, short Korean explanations and occasional English.
- No persistent transcripts/audio; preserve existing affinity/photo and camp inventory rules.
- Existing dirty work is preserved; only this feature's paths are changed. No deployment or merge.

## Review Focus
- Late responses after target/view/lifecycle changes must be dropped.
- Same species different ownership IDs and demo/real profiles keep separate progress.
- Existing affinity scoring must not duplicate or bypass photo lock.
- Unconfigured provider/offline remains honest with authored fallback and no progress loss.
- Invalid content IDs and oversized inputs are rejected at API boundary.

### Task 1: Authored content and education API
Files: data/companion_learning/story.json; phone/assets/data/companion_learning.json; server/affinity/learning.py; server/affinity/app.py; server/affinity/tests/test_learning.py.
Interfaces: POST /v1/companion/chat body {requestId,creatureId,speciesId,storyId,version,sceneId,text,history,allowParentPrompt}; response echoes IDs/version and {text}. GET catalog unnecessary; same authored bundle packaged locally/server.
- [x] Write failing HTTP/content/provider tests, run red.
- [x] Implement one representative fixed story and server validation/persona prompting; injected transport for tests; no SDK dependency.
- [x] Verify existing server and new tests.

### Task 2: Phone learning state and routing
Files: phone/lib/learning/*; phone/test/companion_learning_test.dart; phone/lib/unity_app/unity_app_controller.dart; phone/pubspec.yaml.
Interfaces: snapshot.learning {creatureId,speciesId,name,storyId,sceneId,title,text,busy,available,canNext,muted}; actions selectCompanion(creatureId), storyNext, storyRepeat, companionChat(text), companionSpeech, learningMute, commonCare(actionId in snack/water/ball/pet/plush/cushion/blanket). Native channel allo/companion-voice supports speak {text}, stop. Reuse configured EggDemoApi base URL/token via narrow compatible method or exposed factory.
- [x] Red tests for ownership/profiles/next/storage/failure/stale responses/egg silence.
- [x] Implement catalog/controller/local progress, bounded session history, explicit next, native input, API and common action routing without changing camp recipe inventory.
- [x] Verify focused Flutter tests and analyze.

### Task 3: Unity common care and learning presentation
Files: unity/allo_explore/Assets/Scripts/App/{AppState.cs,AppUiViews.cs,CabinEgg.cs}; new AppUiLearning.cs; relevant CritterDirector common action bridge; Unity tests.
Consumes snapshot/actions from Task2. CommonCare action is represented by actionId, selected target in learning.creatureId; egg default until selection. Common play response must be visual before and after hatch. Chat and explicit next only for selected hatched owned creature.
- [x] Red edit-mode tests for egg/non-egg gates.
- [x] Add compact care controls, companion selector, story dialogue/input/next/repeat/mute. Preserve old affinity UI and no egg TTS.
- [x] Verify Unity edit-mode tests/compile when available.

### Task 4: Native voice and whole feature validation
Files: phone/android/.../CompanionVoiceBridge.kt and MainActivity integration; docs verification report.
- [x] Implement Android TextToSpeech speak/stop with lifecycle cleanup and Korean/English handling.
- [x] Integrate agent output; run server/Flutter/core/Unity checks; fix regressions.
- [x] Independent final review then record verified limits (provider/device/deployment).

Ruling: User explicitly approved implementation and supplied subagent rules, so proceed without a second execution-method approval. Reuse existing linked feature worktree; do not reset other work.

Completed source implementation and automated verification 2026-11-14. Evidence and device/provider limits: `docs/verification/2026-11-14-companion-story-learning.md`. No deployment/merge performed.
