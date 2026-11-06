#!/usr/bin/env bash
# 시연 시나리오 1: 비 + 고속도로 + 부드러운 운전 환경 재현 (결과는 앱에서 확인)
# 쓰는 법: scripts/scenario_rainy_highway.sh [주행 초=120]
# 흐름: 뒷좌석 탑승 → D → 60→90kph 가속 → 90kph 유지(highway 태그는 60초 뒤) → 감속 → P
set -eu
cd "$(dirname "$0")" && source ./vc.sh
SECS=${1-120}
if [ "$#" -gt 1 ] || [[ ! "$SECS" =~ ^[1-9][0-9]{0,5}$ ]]; then
  echo "주행 초는 1~999999의 정수 하나여야 합니다." >&2
  exit 2
fi
vc_setup
# 이전 시나리오의 환경과 차량 제어 상태를 명시적으로 지운다.
gear Park
drive 0 0 0 0
wiper 0
light off
seat rear_left false
seat rear_right false
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
echo "[rainy_highway] 신호 시퀀스 전송 완료. 부화·속성·등급은 확인하지 않았습니다."
echo "[rainy_highway] 기본 120초 × 90km/h는 약 3km; small 거리 부화 기준 5km에 부족합니다."
