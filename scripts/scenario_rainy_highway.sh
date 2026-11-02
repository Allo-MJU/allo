#!/usr/bin/env bash
# 시연 시나리오 1: 비 + 고속도로 + 부드러운 운전 → water tier 3 (Tide Keeper) 기대
# 쓰는 법: scripts/scenario_rainy_highway.sh [주행 초=120]
# 흐름: 뒷좌석 탑승 → D → 60→90kph 가속 → 90kph 유지(highway 태그는 60초 뒤) → 감속 → P
set -u
cd "$(dirname "$0")" && source ./vc.sh
SECS=${1:-120}
vc_setup
echo "[rainy_highway] 뒷좌석 탑승"
seat rear_right true; sleep 2
wiper 2
gear Drive
for s in 20 40 60 75 90; do drive $s 30 0 0; beat; sleep 1; done
echo "[rainy_highway] 90kph 유지 ${SECS}s"
for ((i=0; i<SECS; i++)); do drive 90 25 0 0; sleep 1; done
echo "[rainy_highway] 부드럽게 감속 → P"
for s in 80 70 60 50 40 30 20 10 0; do drive $s 0 15 0; sleep 1; done
gear Park; drive 0 0 0 0
vc_close
echo "[rainy_highway] 끝"
