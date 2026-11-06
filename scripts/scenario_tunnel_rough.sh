#!/usr/bin/env bash
# 시연 시나리오 2: 터널 + 거친 운전 환경 재현 (결과는 앱에서 확인)
# 쓰는 법: scripts/scenario_tunnel_rough.sh [반복 횟수=6]
set -eu
cd "$(dirname "$0")" && source ./vc.sh
REPS=${1-6}
if [ "$#" -gt 1 ] || [[ ! "$REPS" =~ ^[1-9][0-9]{0,5}$ ]]; then
  echo "반복 횟수는 1~999999의 정수 하나여야 합니다." >&2
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
seat rear_right true; sleep 2
light on          # 주간 + 전조등 = tunnel
gear Drive
drive 60 30 0 0; sleep 3
for ((i=0; i<REPS; i++)); do
  echo "[tunnel_rough] 급제동 #$((i+1))"
  drive 60 30 0 0; sleep 2
  drive 30 0 80 0; sleep 1          # 1초에 30kph 감속
  echo "[tunnel_rough] 급조향"
  drive 50 20 0 120; sleep 1
  drive 50 20 0 -120; sleep 1
  drive 50 20 0 0; sleep 2
done
for s in 40 30 20 10 0; do drive $s 0 20 0; sleep 1; done
gear Park; drive 0 0 0 0
vc_close
echo "[tunnel_rough] 신호 시퀀스 전송 완료. 부화·속성·등급은 확인하지 않았습니다."
