#!/usr/bin/env bash
# 차량 앱 대신 Firebase /vehicle 에 1초마다 가짜 신호를 흘린다 (비 + 고속도로, 부드러운 운전).
# 쓰는 법: ALLO_DB_URL=... scripts/fake_vehicle_feed.sh <sessionId> [초=300] [tags=rain,highway]
set -eu
: "${ALLO_DB_URL:?ALLO_DB_URL 을 설정하세요}"
SID=${1:?sessionId}
SECS=${2:-300}
TAGS=${3:-rain,highway}
TAGS_JSON=$(printf '%s' "$TAGS" | awk -F, '{for(i=1;i<=NF;i++){printf "%s\"%s\"", (i>1?",":""), $i}}')
WIPER=$([[ ",$TAGS," == *",rain,"* ]] && echo 2 || echo 0)
LIGHT=$([[ ",$TAGS," == *",tunnel,"* || ",$TAGS," == *",night,"* ]] && echo true || echo false)
DIST=0
for ((i=0; i<SECS; i++)); do
  NOW=$(date +%s000); DIST=$((DIST + 25))   # 90kph ≈ 25 m/s
  curl -s -X PUT "${ALLO_DB_URL%/}/sessions/$SID/vehicle.json" -d @- >/dev/null <<JSON
{"ts":$NOW,"gear":"D","speedKph":90,"distanceM":$DIST,"harshBrake":0,"harshSteer":0,
 "wiperLevel":$WIPER,"headlightOn":$LIGHT,"seatRow2":true,"etaSec":null,
 "envTags":[$TAGS_JSON],"capabilities":["wiper","light","seat","odometer","speed","gear"]}
JSON
  sleep 1
done
