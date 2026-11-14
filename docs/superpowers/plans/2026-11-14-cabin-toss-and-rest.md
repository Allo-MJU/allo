# Cabin Toss and Rest Implementation Plan

> Use subagents for disjoint UI and gameplay files. Preserve the current uncommitted approved baseline. No commit/push requested for this revision.

**Goal:** Top QR button, four circular item choices, directional swipe throws (up/left/right/diagonal), direct rubbing and double-tap free relocation with fixed-rest interactions.

**Architecture:** Existing Unity AppUi presents controls; new CabinInteraction coordinates local gestures and transient visuals. Existing Dart commonCare approval and server conversation remain authoritative.

**Spec:** docs/superpowers/specs/2026-11-14-cabin-toss-and-rest-design.md

## Constraints and review focus

- No new API, package, borrowed game art, or reward rules.
- Keep egg photo/speech/zone access when removing the old sheet.
- Distinguish tap/rub/relocation; never open dialogue after a drag.
- Never grant care on selection or cancelled input.
- Cancel on ownership/session/view/modal changes, not ordinary ticks.
- Do not let legacy TapInput or CabinEgg consume the same pointer.

## Task 1 — UI

Owner: cabin_radial_ui. Files AppUi*, AppSession installation, UI tests. Test title-position QR navigation and four circles/no action sheet, enabled/selected states and preserved egg operations. Then replace action menu and install CabinInteraction. Contract: static SelectedItem and SelectItem(string), IDs snack/water/ball/plush.

## Task 2 — gestures and gameplay

Owner: cabin_gesture_gameplay. New CabinInteraction, CritterDirector.CommonCare, TapInput only as needed, new tests. Test swipe recognition, tap/rub/drag distinctions, identity cancellation and accepted-action targeting. Implement held 3D item, throw arc and landing reaction; fixed cushion/blanket and dragging buddy. Keep egg input isolated.

Latest steering replaces stationary hold with double tap to enter relocation. Single dialogue tap waits briefly for a second tap, rubbing stays direct, any valid walk surface accepts the drop without a new reward. Fixed rest targets use the existing commonCare action.

## Task 3 — integration and verification

Parent reviews both changes and tests, runs full Unity tests then export/APK build. Install without clearing data and inspect API36 captures: title QR, circle selection, toss, rub and rest zones. Record exact verified and unverified behavior. Restore generated prefab/scene/iOS noise, update evidence. No additional server/model claims.

## Completion evidence

Final EditMode236/236 and rendered raycast PlayMode1/1 passed. Final APK built106.8s and installed without clearing data. Forward/left/right ball flight, stable camera and landed care submission verified; shared emulator traces also showed single-tap deferral, double-tap arming and free placement without reward. See docs/verification/2026-11-14-cabin-toss-and-rest.md for exact scope/limits. Generated export noise restored. No commit/push.
