# Unity phone implementation

The Android phone app now boots the Unity application interface over the existing Dart affinity, collection and camp controllers. Views cover home, cabin, facilities, friends, inventory and settings. Egg models and gestures exist only inside the vehicle cabin. Saved materials, role assignments, build/cook/train costs, offline jobs and hatching rules remain owned by the original controllers.

## Latest camp direction
The user clarified that Ninja Voltage is the baseline 2D village screen; Palworld supplies ONLY the wilderness survival theme. The temporary 3D camp was removed. The final map uses original cel-shaded 2D woodland terrain and three transparent sprites: workbench/canvas shelter, outdoor cauldron/prep table, and training dummy/target. No reference-game IP assets were copied. Native color/alpha are preserved and assets/prompts are recorded in docs/village-art-provenance.md.

Background, facility sprites, hit areas, labels, jobs and owned-friend marker pan together on both axes inside bounds. The thin HUD and right circular rail stay fixed. The original 3D cabin remains intact, and only that view shows the egg.

## Verification
- Final 2D source: Unity EditMode 94/94 passed (/tmp/allo-camp2d-editmode.xml); PlayMode 1/1 passed (/tmp/allo-camp2d-playmode.xml), both run after the 3D removal and new assets.
- Real EventSystem PlayMode coverage verifies raycast drag movement on both axes with fixed HUD.
- Phone suite: 297/297 passed before the presentation-only camp revision; no Dart gameplay changes in this revision.

Final 2D Android export and debug APK build succeeded (/tmp/allo-camp2d-export.log and /tmp/allo-camp2d-apk.log, 40.4s APK build). Installed with adb install -r to Android 16/API 36 emulator-5554, preserving saved data. Actual Unity view showed the new 2D forest terrain, three correctly aligned survival station sprites, full-screen background and clear right rail.

## Remaining integration limits
Pleos fishing/logging rewards await the upstream contract; no remote reward schema, fake receipt or production balance was invented. Real vehicle sync and physical-device camera/microphone remain unverified. Manual emulator system Back/pan automation was inconclusive; no manual success is claimed for those checks. Character species without approved sprites use an explicit neutral placeholder without substituting another species.

The runtime demonstration uses the existing separate fake-feed profile and preserves its saved data on installation. No credentials or runtime configuration values are stored here.
