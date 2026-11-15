# Sea learning pilot demo

Run `scripts/demo_sea_learning.sh` to install the existing debug APK and open the Android phone app. Run `scripts/demo_sea_learning.sh --build` to export the current Unity project and build the APK first. The helper reuses an online emulator, or starts a visible `ALLO_API_36` emulator if none is online. Set `ALLO_SEA_DEVICE` to choose a particular online emulator serial.

The demo uses a local fake vehicle feed. No API key, Firebase setup, or backend is needed. The install updates `ai.allo.allo_phone` in place and preserves its app data; the helper does not clear or uninstall the app.

In the phone app, follow this route:

1. **차 안** → **차량 QR 연결하기** → **테스트 연결** (fake feed only)
2. **탐험 노트** → **바다**
3. Choose an expectation, start the experiment, compare the two results, read the explanation, then save the discovery card.

This pilot runs in the Android phone app. It does not run in the Pleos car app.
