# Vehicle UI capture harness

Opt-in Android app using the vehicle app's actual Compose screens and explicit test data.
It does not exercise Pleos, AAOS restrictions, Firebase, or live phone mirroring.
The screenshot includes a visible test-data label.

```sh
# from car/, JDK 17 and ANDROID_HOME required
sh ./gradlew -PincludePreview=true :preview:assembleDebug
adb install -r preview/build/outputs/apk/debug/preview-debug.apk
adb shell am start -n ai.allo.preview/ai.allo.preview.PreviewActivity --es mode driving
adb exec-out screencap -p > ../tasks/screenshots/drive.png
adb shell am force-stop ai.allo.preview
adb shell am start -n ai.allo.preview/ai.allo.preview.PreviewActivity --es mode parked
adb exec-out screencap -p > ../tasks/screenshots/parked.png
```

The default fixture is `road_sprout` (normal, tier 1). Use `--es species tide_keeper`
to select another catalog species with its matching attribute and tier.
Wait for the app to finish drawing before capturing. `--ez disconnected true` displays
the disconnected-state fixture. The parked capture is the actual sharing-entry UI,
not a claim that phone video has been received. Normal vehicle builds do not include
this module unless `-PincludePreview=true` is supplied.

Driving in this harness explicitly enables the running-motion concept. Its banner
marks it as a preview, not an approved in-vehicle behavior. The vehicle app never
opts into `previewRunning` and continues to display a static driving pose.
Parked sleep uses breathing/floating Z; fishing loops through lifting, catching,
escaping and splashing. These are decorative states, not game rewards.
