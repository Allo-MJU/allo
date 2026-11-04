#!/usr/bin/env bash
# PT 시연: "바다 여행" — 판교(도심) 출발 → 고속도로 → 바다 도착 → P → 세션 종료(sessionEnd)
# 쓰는 법: scripts/demo_sea_trip.sh [고속도로 초=90] [--wait]
#   기본은 도착 후 세션을 바로 끝낸다 (debug 명령). --wait 를 주면 실제 기준(P 3분)을 기다린다.
# 전제: 디버그 빌드 설치, 차 화면에서 페어링 완료(폰 또는 콘솔에서 meta.paired=true)
# 지역은 DebugDemoReceiver 로 덮어쓴다 (에뮬레이터 내비 위치가 판교로 고정이라). 좌표는 쓰지 않는다.
set -u
cd "$(dirname "$0")" && source ./vc.sh
HWY=${1:-90}
WAIT=0; for a in "$@"; do [ "$a" = "--wait" ] && WAIT=1; done
demo() { adb shell am broadcast -a ai.allo.car.debug.DEMO -n ai.allo.car/.debug.DebugDemoReceiver "$@" >/dev/null; }
step() { echo "[sea_trip] $*"; }

vc_setup
trap 'demo --es region off; vc_close' EXIT

step "출발 준비: 뒷좌석 탑승, 지역 = 도심(판교)"
demo --es region city
seat rear_right true; wiper 0; light off; gear Park; drive 0 0 0 0; sleep 2

step "D → 시내 50kph 20초"
gear Drive
for s in 10 20 30 40 50; do drive $s 30 0 0; sleep 1; done
for ((i=0; i<20; i++)); do drive 50 20 0 0; sleep 1; done

step "고속도로 95kph ${HWY}초 (highway 태그는 60초 뒤)"
demo --es region off
for s in 60 70 80 90 95; do drive $s 30 0 0; sleep 1; done
for ((i=0; i<HWY; i++)); do drive 95 25 0 0; sleep 1; done

step "바다 도착: 지역 = coast, 30kph 해안도로 20초"
for s in 80 60 40 30; do drive $s 0 15 0; sleep 1; done
demo --es region coast
for ((i=0; i<20; i++)); do drive 30 10 0 0; sleep 1; done

step "정차 → P"
for s in 20 10 0; do drive $s 0 20 0; sleep 1; done
gear Park; drive 0 0 0 0

if [ $WAIT = 1 ]; then
  step "P 3분 대기 (실제 종료 기준)"
  for ((i=0; i<190; i++)); do beat; sleep 1; done
else
  sleep 3
  step "세션 종료 (debug)"
  demo --es end now
fi
step "끝. 확인: adb logcat -d -s SessionManager | grep 'session end'"
