#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APK="$ROOT/phone/build/app/outputs/flutter-apk/app-debug.apk"
AVD=ALLO_API_36

usage() {
  cat <<'EOF'
Usage: scripts/demo_sea_learning.sh [--build]

Install and launch the sea learning pilot on an online Android emulator.
  --build  Export Unity and build a fresh Flutter debug APK first.
  --help   Show this help.

Set ALLO_SEA_DEVICE to select a specific online emulator serial.
EOF
}

build=0
while (($#)); do
  case "$1" in
    --build) build=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

command -v adb >/dev/null || { echo "adb is required (Android SDK platform-tools)." >&2; exit 1; }
adb reconnect offline >/dev/null 2>&1 || true

if ((build)); then
  UNITY=/Applications/Unity/Hub/Editor/6000.0.85f2/Unity.app/Contents/MacOS/Unity \
    "$ROOT/scripts/export_unity.sh"
  (
    cd "$ROOT/phone"
    flutter build apk --debug \
      --dart-define=EXPLORE_UNITY=true \
      --dart-define=UNITY_APP=true \
      --dart-define=FEED=fake \
      --dart-define=FAKE_TIME_SCALE=1 \
      --dart-define=SCENARIO=clear \
      --dart-define=UNITY_DEMO_CREATURES=true
  )
fi

[[ -f "$APK" ]] || { echo "Debug APK not found: $APK (run with --build)." >&2; exit 1; }

device="${ALLO_SEA_DEVICE:-}"
if [[ -n "$device" ]]; then
  state="$(adb devices | awk -v serial="$device" '$1 == serial { print $2; exit }')"
  [[ "$state" == device ]] || {
    echo "Selected device '$device' is not online (state: ${state:-missing})." >&2
    exit 1
  }
else
  device="$(adb devices | awk '$1 ~ /^emulator-/ && $2 == "device" { print $1; exit }')"
  if [[ -z "$device" ]]; then
    emulator_bin="$(command -v emulator || true)"
    if [[ -z "$emulator_bin" ]]; then
      sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
      emulator_bin="$sdk_root/emulator/emulator"
    fi
    [[ -x "$emulator_bin" ]] || { echo "No online emulator and emulator command is unavailable." >&2; exit 1; }
    echo "Starting visible $AVD emulator..."
    nohup "$emulator_bin" -avd "$AVD" -gpu host >/tmp/allo-sea-learning-emulator.log 2>&1 </dev/null &
    for ((attempt = 0; attempt < 180; attempt++)); do
      device="$(adb devices | awk '$1 ~ /^emulator-/ && $2 == "device" { print $1; exit }')"
      [[ -n "$device" ]] && break
      sleep 1
    done
    [[ -n "$device" ]] || {
      echo "Emulator did not become available; see /tmp/allo-sea-learning-emulator.log." >&2
      exit 1
    }
  fi
fi

booted=0
for ((attempt = 0; attempt < 60; attempt++)); do
  if [[ "$(adb -s "$device" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then
    booted=1
    break
  fi
  sleep 1
done
[[ "$booted" == 1 ]] || { echo "Emulator $device did not finish booting within 60 seconds." >&2; exit 1; }

echo "Using $device; installing without clearing app data."
adb -s "$device" install -r "$APK"
adb -s "$device" shell am start -n ai.allo.allo_phone/.MainActivity
