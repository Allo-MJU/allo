# Unity phone implementation

The Android phone app now boots the Unity application interface over the existing Dart affinity, collection and camp controllers. Views cover home, cabin, facilities, friends, inventory and settings. Egg models and gestures exist only inside the vehicle cabin. Saved materials, role assignments, build/cook/train costs, offline jobs and hatching rules remain owned by the original controllers.

## Latest camp direction
The user clarified that Ninja Voltage is the baseline 2D village screen; Palworld supplies ONLY the wilderness survival theme. The temporary 3D camp was removed. The final map uses original cel-shaded 2D woodland terrain and three transparent sprites: workbench/canvas shelter, outdoor cauldron/prep table, and training dummy/target. No reference-game IP assets were copied. Native color/alpha are preserved and assets/prompts are recorded in docs/village-art-provenance.md.

Background, facility sprites, hit areas, labels, jobs and owned-friend marker pan together on both axes inside bounds. The thin HUD and right circular rail stay fixed. The original 3D cabin remains intact, and only that view shows the egg.

## Verification
- Final 2D source: Unity EditMode 95/95 passed (/tmp/allo-demo-friends-editmode.xml); PlayMode 1/1 passed (/tmp/allo-demo-friends-playmode.xml), both run after the final owned-character markers.
- Real EventSystem PlayMode coverage verifies raycast drag movement on both axes with fixed HUD.
- Phone suite: 302/302 passed after isolated demo ownership was added (/tmp/unity_app_demo_full.log); scoped analysis reported no issues.

Final 2D Android export and debug APK build succeeded (/tmp/allo-camp2d-export.log and /tmp/allo-camp2d-apk.log, 40.4s APK build). Installed with adb install -r to Android 16/API 36 emulator-5554, preserving saved data. Actual Unity view showed the new 2D forest terrain, three correctly aligned survival station sprites, full-screen background and clear right rail.

## Pre-collected character examples
The user explicitly requested examples assuming the characters were collected. Build with UNITY_DEMO_CREATURES=true alongside FEED=fake and UNITY_APP=true to enable the isolated unity-demo-examples profile. It contains road_sprout (길싹이), puddle_pip (웅덩이삐약), lamp_moth (등불나방) and highway_comet (고속혜성), using existing canonical sprites. Ownership is saved idempotently through DexStore and can be assigned to existing camp roles. The default and original demo profiles, materials and incubation progress remain separate. No materials or remote reward receipts are seeded.

The 2D camp displays up to four authoritative owned-character markers, preserving them across state ticks. Their name badges update, removed characters are cleaned up, and tapping a marker selects its exact creature/species in the friends view. Missing art is explicitly labeled.

## Remaining integration limits
Pleos fishing/logging rewards await the upstream contract; no remote reward schema, fake receipt or production balance was invented. Real vehicle sync and physical-device camera/microphone remain unverified. Manual emulator system Back/pan automation was inconclusive; no manual success is claimed for those checks. Character species without approved sprites use an explicit neutral placeholder without substituting another species.

The runtime demonstration uses the opt-in isolated fake-feed example profile and preserves the prior profiles on installation. No credentials or runtime configuration values are stored here.

Final character-preview verification: Unity EditMode 95/95, PlayMode 1/1, phone suite 302/302 and scoped analysis passed. After removing the redundant permanent sample banner, focused demo boundaries passed 5/5 again (/tmp/allo-demo-friends-no-banner-tests.log). Actual Android rendering showed all four canonical characters with their names over the 2D camp; no Unity/AndroidRuntime/Flutter errors were logged during the launch check.

Final no-banner APK succeeded in 13.2s (/tmp/allo-demo-friends-final-apk.log), updated with data-preserving install and cold-launched. Actual final screenshot 01-home.png confirms all four characters, 2D survival facilities and the compact demo chip without the large notice banner.
