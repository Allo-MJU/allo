#!/usr/bin/env bash
# 시연 시나리오 2: 터널 + 거친 운전 → dark tier 1 기대 (급제동·급조향이 등급을 깎는 것을 보여준다)
# 쓰는 법: scripts/scenario_tunnel_rough.sh [반복 횟수=6]
set -u
cd "$(dirname "$0")" && source ./vc.sh
REPS=${1:-6}
vc_setup
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
echo "[tunnel_rough] 끝"
