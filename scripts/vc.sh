#!/usr/bin/env bash
# Pleos Connect Emulator Virtual Console (HTTP 8088) 헬퍼. 다른 스크립트가 source 한다.
# 확인된 엔드포인트 (선례 핸들온·SoftRide):
#   PUT /vehicle/gear?gear=Drive|Park|Reverse|Neutral
#   PUT /vehicle/controls?speed=<kph int>&accelerator=<0-100>&brake=<0-100>&steering=<deg>
#   PUT /vehicle/seat?area=rear_left|rear_right&kind=occupied&value=true|false
#   PUT /vehicle/turn-signal?mode=BlinkLeft|BlinkRight|Off
#   PUT /vehicle/hvac?power=1 ...
#   POST /browser/session?client=<id>   ← 하트비트. 없으면 콘솔이 emulator_inactive 로 차를 안 움직인다
#   PUT /vehicle/body?front_wiper=Off|Auto|Low|High
#   PUT /vehicle/lights?feature=headlamp_mode&value=Off|Auto|Position|LowBeam
#   PUT /vehicle/odometer?traveled_distance_km=<km 소수>
#   (docs/verification.md #1 · #2 · #4 실측. 전체 목록은 GET /vehicle/catalog)
set -u
VC=${VC:-http://127.0.0.1:8088}
CLIENT=${CLIENT:-allo-scripts}

vc_setup() {
  if [ -z "${ANDROID_SERIAL:-}" ]; then
    local devices s name found=""
    devices=$(adb devices) || return 1
    for s in $(printf '%s\n' "$devices" | awk '/^emulator-[0-9]+[[:space:]]+device$/{print $1}'); do
      name=$(adb -s "$s" emu avd name 2>/dev/null) || return 1
      name=$(printf '%s\n' "$name" | head -1 | tr -d '\r')
      case "$name" in
        Pleos*|pleos*)
          if [ -n "$found" ]; then echo "vc_setup: 여러 Pleos 에뮬레이터가 있습니다. ANDROID_SERIAL을 지정하세요." >&2; return 1; fi
          found=$s ;;
      esac
    done
    [ -n "$found" ] || { echo "vc_setup: Pleos 에뮬레이터가 없습니다. ANDROID_SERIAL을 확인하세요." >&2; return 1; }
    export ANDROID_SERIAL=$found
  fi
  adb forward tcp:8088 tcp:8088 >/dev/null
}
beat()  { curl --fail --silent --show-error --connect-timeout 5 --max-time 10 -o /dev/null -X POST "$VC/browser/session?client=$CLIENT"; }
put()   { beat && curl --fail --silent --show-error --connect-timeout 5 --max-time 10 -o /dev/null -X PUT "$VC/$1"; }
gear()  { put "vehicle/gear?gear=$1"; }
drive() { put "vehicle/controls?speed=${1:-0}&accelerator=${2:-0}&brake=${3:-0}&steering=${4:-0}"; }
seat()  { put "vehicle/seat?area=${1:-rear_right}&kind=occupied&value=${2:-true}"; }
# wiper <0-3> : wiperLevel 기준. VC 에는 간헐(1)이 없어 1·2 → Low(CONTINUOUS_LEVEL_1), 3 → High(CONTINUOUS_LEVEL_3)
wiper() {
  case "${1:-0}" in
    0) v=Off ;; 1|2) v=Low ;; 3) v=High ;; auto) v=Auto ;;
    *) echo "wiper: 0-3 | auto" >&2; return 1 ;;
  esac
  put "vehicle/body?front_wiper=$v"
}
# light on|off : 하향등. 에뮬레이터는 Auto 에서 켜지지 않으므로 LowBeam 으로 직접 켠다
light() {
  case "${1:-off}" in on) v=LowBeam ;; off) v=Off ;; *) echo "light: on | off" >&2; return 1 ;; esac
  put "vehicle/lights?feature=headlamp_mode&value=$v"
}
# odo <km> : 에뮬레이터는 주행으로 Odometer 를 올리지 않는다. 거리 시나리오는 이걸로 직접 올린다
odo() { put "vehicle/odometer?traveled_distance_km=${1:?km}"; }
vc_close() { curl --fail --silent --show-error --connect-timeout 5 --max-time 10 -o /dev/null -X POST "$VC/browser/session?client=$CLIENT&closing=1"; }
