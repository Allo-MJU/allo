# Drive-aware cabin view implementation plan

**Goal:** Connect steering-derived corner visuals to the existing vehicle-to-Unity path and replace accumulated touch-assisted gyro look with a calibrated relative-pose view.

**User decisions:** Explain changes before implementation. On 2026-11-15 the user chose to keep the existing approximate city/mountain/coast/highway classification and implement steering and gyro first. APK work remains deferred; do not export Android libraries, build APKs, install or deploy these feature changes.

## Existing behavior and limits

- RegionTagger uses representative coordinate/radius areas; highway is sustained-speed inference. The installed NaviHelper lacks current-road class and terrain layers. These classifiers remain unchanged.
- The real phone controller already publishes scene and route messages. Unity draws thematic scenery, planned navigation turns and limited heading corrections; raw steering is not transmitted.
- The camera currently adds 0.3× gyro angular velocity to accumulated touch look. This has no stable neutral-pose reference.

## Tasks and ownership

- [x] Vehicle: keep steering angles local; validate SDK input, invalidate failed/stale values and publish optional display-only cornering. Preserve existing harsh-steering counters and pairing fixes.
- [x] Phone: parse the optional block defensively, preserve it through VehicleState copies, and forward it through both Unity route publishers. Missing/invalid legacy data remains absent.
- [x] Unity world: smooth signed steering into outside-world turn presentation, keep the cabin fixed and avoid duplicating committed navigation turns. Use navigation fallback when steering is unavailable; duplicate timestamps never prolong validity.
- [x] Unity camera: use the first valid pose as neutral, relative attitude for yaw/pitch, level horizon and ±35° pitch. Preserve touch fallback, reduced-motion preference, cabin gestures and authored hatch camera sequences. Recenter on relevant lifecycle/orientation changes.
- [x] Settings: add the existing-style “정면 다시 맞추기” control calling CameraRig.Recenter().
- [x] Verification: targeted regression tests followed by full Dart/Flutter and Unity suites, independent review and actual-camera PlayMode tests. Physical-device sensor verification remains deferred with APK work.

## Display-only wire addition

`vehicle.cornering` and the Unity `route.cornering` message optionally contain:

```json
{"version":1,"bend":-0.5,"receivedAtMs":1794700000000}
```

- `bend`: finite normalized value in [-1, 1], negative left / positive right, zero straight. It is a visual proxy, not physical curvature or steering-wheel angle.
- `receivedAtMs`: epoch milliseconds when the SDK delivered the reading, not a guaranteed hardware observation timestamp.
- Car emission requires steering support, fresh SDK receipt (≤2500ms), valid fresh forward motion and gear D. No coordinates or raw steering angle are added to the wire.
- The current SDK/Virtual Console sign observation determines the default mapping; real-vehicle sign, sampling cadence and visual gain still need hardware calibration.
- Consumers ignore unknown versions, malformed values, stale/out-of-order receipts and unsupported data. Existing messages and old clients remain compatible.

## Verification record

- Gyro focused EditMode: 11/11; focused actual-camera PlayMode: 1/1. Synthetic poses verify neutral/return, landscape, pitch limits and invalid samples. A simultaneous glance/rail regression was reproduced and fixed within the camera scope.
- Vehicle focused cornering regressions: 6; debug and release suites: 354/354 each. These are source tests, not real-car sensor verification.
- Independent review found and regressions reproduced four issues: callback-time snapshot race, delayed-getter starvation, egg interaction resetting gyro neutral, and duplicate UI route messages moving the fallback navigation reference. All four were fixed and their covering tests passed. Reduced-motion settings also disable the new cornering cue.
- Final vehicle debug and release suites: 357/357 each. Shared Dart core: 99/99. Flutter: 534/534. Unity EditMode: 302/302. Unity PlayMode: 5/5. `git diff --check` passed.
- No APK build, Unity Android export, device installation or cloud deployment was performed for this feature. Physical sensor axes, real-car steering sign and perceived sensitivity remain unverified.
