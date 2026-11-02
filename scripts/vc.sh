#!/usr/bin/env bash
# Pleos Connect Emulator Virtual Console (HTTP 8088) 헬퍼. 다른 스크립트가 source 한다.
# 확인된 엔드포인트 (선례 핸들온·SoftRide):
#   PUT /vehicle/gear?gear=Drive|Park|Reverse|Neutral
#   PUT /vehicle/controls?speed=<kph int>&accelerator=<0-100>&brake=<0-100>&steering=<deg>
#   PUT /vehicle/seat?area=rear_left|rear_right&kind=occupied&value=true|false
#   PUT /vehicle/turn-signal?mode=BlinkLeft|BlinkRight|Off
#   PUT /vehicle/hvac?power=1 ...
#   POST /browser/session?client=<id>   ← 하트비트. 없으면 콘솔이 emulator_inactive 로 차를 안 움직인다
# TODO(A): 와이퍼·전조등 엔드포인트는 브라우저 http://127.0.0.1:8088 에서 조작하며 Network 탭으로 확인해 아래 wiper()/light() 에 채운다.
set -u
VC=${VC:-http://127.0.0.1:8088}
CLIENT=${CLIENT:-allo-scripts}

vc_setup() {
  if [ -z "${ANDROID_SERIAL:-}" ]; then
    for s in $(adb devices | awk '/^emulator-[0-9]+\tdevice$/{print $1}'); do
      name=$(adb -s "$s" emu avd name 2>/dev/null | head -1 | tr -d '\r')
      case "$name" in Pleos*|pleos*) export ANDROID_SERIAL=$s ;; esac
    done
  fi
  adb forward tcp:8088 tcp:8088 >/dev/null
}
beat()  { curl -s -o /dev/null -X POST "$VC/browser/session?client=$CLIENT"; }
put()   { beat; curl -s -o /dev/null -X PUT "$VC/$1"; }
gear()  { put "vehicle/gear?gear=$1"; }
drive() { put "vehicle/controls?speed=${1:-0}&accelerator=${2:-0}&brake=${3:-0}&steering=${4:-0}"; }
seat()  { put "vehicle/seat?area=${1:-rear_right}&kind=occupied&value=${2:-true}"; }
wiper() { echo "TODO wiper level=$1 (엔드포인트 미확인)"; }
light() { echo "TODO headlight on=$1 (엔드포인트 미확인)"; }
vc_close() { curl -s -o /dev/null -X POST "$VC/browser/session?client=$CLIENT&closing=1"; }
