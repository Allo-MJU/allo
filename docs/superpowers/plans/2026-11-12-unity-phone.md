# Unity phone application Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build the full landscape Unity phone UI over existing affinity/camp Dart controllers.
**Architecture:** Invisible Flutter host dispatches validated Unity intents to saved Dart controllers. A versioned snapshot drives a Unity home/camp world and reused cabin; platform services supply real camera/speech inputs.
**Tech Stack:** Unity6000.0.85f2, UGUI, Flutter/Dart, Android Kotlin; existing dependencies only.
**Spec:** docs/superpowers/specs/2026-11-12-unity-phone-design.md

## Global Constraints
- Egg appears only in cabin; #93/#100 rules and canonical species IDs remain authoritative.
- All visible app screens in Unity; latest camp art direction is Palworld-like survival materials, with Ninja Voltage composition. #97 is reference only.
- No fake balances or Pleos reward contract; preserve current source worktrees and persistent user data.
- Exact app/AppAction DTO names and fields are in the spec. No raw speech/photo/token in snapshots/logs.
- Agents own disjoint files. Main agent alone runs shared Unity Editor commands and integrates scene builder/shared bridge.

## Review Focus
- Old/duplicate egg input must never affect a newer egg or spend twice (Task1 tests).
- Save errors show unchanged authoritative inventory and retry (Task1 tests).
- Unknown species/missing assets and zero-owned characters remain usable (Tasks2/3 visual and component checks).
- Leaving cabin removes all egg visuals; touch UI cannot trigger hidden gestures (Task4 tests).
- Permission denial/unavailable camera/STT do not award quest/affinity (Task5 + Task1 tests).

### Task 1: Dart state/command bridge and invisible host
Files: phone/lib/unity_app/**, phone/lib/app.dart, phone/test/unity_app*_test.dart only.
Consumes exact snapshot/actions from spec and existing controllers; produces UnityAppController snapshot + handleMessage and UnityAppScreen using existing UnityViewBuilder.
- [x] Write and run failing behavioral boundary tests (stale egg, duplicate mutation, malformed/version, outside-cabin egg input).
- [x] Implement normalized snapshots, validated serialized dispatch, actual affinity/camp APIs, lifecycle/dispose, default Android Unity route and injection for native input.
- [x] Focused tests then phone full suite, report evidence and commit only owned paths.

### Task 2: Unity application UI
Files: unity/allo_explore/Assets/Scripts/App/AppUi.cs, AppUiWidgets.cs, AppUiViews.cs and corresponding meta only.
Consumes AppSession, AppState and AppAction; produces real UGUI screens for all six views with navigation, pairing, egg state/commands, three facility workflows, selection/detail, food/action use, inventory and settings. Buttons use AppSession.Request; never mutate game rules. Preserve focused text fields across snapshot ticks, show pending/empty/errors and disabled reasons. UI changes are verified visually; main runs shared Unity tests/build.
- [x] Build reusable accessible UGUI style matching approved reference, valid Korean text and safe area.
- [x] Implement all six functional views and selection/confirmation/detail flows with real state.
- [x] Self-check contract/cost displays, report and commit owned files.

### Task 3: Unity home/camp world
Files: unity/allo_explore/Assets/Scripts/App/AppWorld.cs plus meta only.
Consumes AppState and exact SetView/Apply signatures; produces a distinct 3D camp diorama with three named facilities, canonical friend representations, home/camp camera, cabin restoration, visible level/work states. Existing cabin/world assets remain intact. No logic/reward generation or UI overlays.
- [x] Implement three-dimensional camp and state visuals, hide cabin outside cabin view and disable its input/camera rig appropriately.
- [x] Preserve original cabin transform/settings when switching back; tolerate no creatures and missing assets.
- [x] Report visual verification needs and commit owned files.

### Task 4: Cabin egg model and gestures
Files: unity/allo_explore/Assets/Scripts/App/CabinEgg.cs; Assets/Tests/EditMode/CabinEggTests.cs and meta only.
Consumes AppSession/AppState, produces Apply/SetView; egg primitive mesh must look like an egg, with four actual cabin locations, touch/drag placement, rubbing pet, preferred-zone affordance, feedback and saved hatch/failure animation confined to cabin. UI touch cannot pet/move or drag camera simultaneously. Never score locally; send intent with egg ID.
- [x] Add regression tests for cabin-only visibility and exactly four zones/current-ID intent context; tell main when ready for RED run before implementing.
- [x] Implement gestures/model and honest server-confirmed feedback.
- [x] Main runs Unity suite/build; report and commit owned files.

### Task 5: Android real speech/photo input
Files: phone/android/app/src/main/kotlin/ai/allo/allo_phone/EggInputBridge.kt, EggInputActivity.kt, MainActivity.kt; AndroidManifest.xml, res/xml/egg_camera_paths.xml only.
Consumes method channel allo/egg-input; produces speech String/photo JPEG bytes/null cancellation. Use proxy Activity over currently foreground Unity Activity, system speech/camera intents and FileProvider, limit image to <=1280px and composite egg with Canvas, remove metadata, clear own temp images, prevent overlapping requests. Missing service/permissions produce errors, no private logging. Dart callback handles scoring.
- [x] Verify failure/denial/cancellation paths in native code, no runtime install/new libraries.
- [x] Implement registered proxy Activity and MethodChannel attachment/cleanup without changing ExploreBridge.
- [x] Build validation is main agent's responsibility; report and commit owned paths.

### Task 6: Shared schema, integration and verification (main)
Files: AppState.cs, AppSession.cs, Bridge/MessageParser.cs, Bridge/FlutterBridge.cs, Bridge/Messages.cs, Common/Hud.cs, Editor/AlloBuild.cs, new app-state EditMode tests, docs.
- [x] Define shared DTO/session once; retain legacy explore protocol. appMode disables old HUD.
- [x] Integrate components in scene generation, embed existing Do Hyeon font from #97, run base/new Unity tests and full Dart suite.
- [x] Stage source into existing runtime build cache, export Android, build/install with data-preserving update.
- [x] Inspect screenshots across six views and test real supported interaction paths; fix discovered defects, independent whole-branch review, record verified limitations and deliver runnable app.


## Final steering and verification limits
Ninja Voltage is the basic 2D village screen; Palworld is the survival theme only. The temporary 3D preview and its tests were removed after the user's explicit correction. Final implementation uses the persistent full-screen two-axis UGUI map, clean original 2D terrain/station sprites, fixed HUD/right action rail and existing game rules. Latest evidence is in docs/work-results/unity-phone/README.md.

Implementation completion does not imply physical-device camera/STT, predictive Back, real vehicle or Pleos remote rewards have been end-to-end verified. Pleos reward schema remains pending. Manual emulator pan input was previously inconclusive; the real EventSystem PlayMode test covers both axes and fixed HUD.
