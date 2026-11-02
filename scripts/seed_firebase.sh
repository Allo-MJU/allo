#!/usr/bin/env bash
# 차량 앱 없이 Firebase 에 세션 1건을 만든다. B/C 가 Day 1 에 폰 앱·로직을 붙여보기 위한 것.
# 쓰는 법: ALLO_DB_URL=https://<project>-default-rtdb.<region>.firebasedatabase.app scripts/seed_firebase.sh [sessionId]
set -eu
: "${ALLO_DB_URL:?ALLO_DB_URL 을 설정하세요}"
SID=${1:-$(uuidgen | tr 'A-Z' 'a-z')}
NOW=$(date +%s000)
BASE="${ALLO_DB_URL%/}/sessions/$SID"

curl -sf -X PUT "$BASE/meta.json" -d "{\"createdAt\":$NOW,\"pairCode\":\"483920\",\"paired\":false,\"carAppVersion\":\"seed\"}" >/dev/null
curl -sf -X PUT "$BASE/vehicle.json" -d @- >/dev/null <<JSON
{"ts":$NOW,"gear":"D","speedKph":82.4,"distanceM":14300,"harshBrake":2,"harshSteer":1,
 "wiperLevel":2,"headlightOn":false,"seatRow2":true,"etaSec":2280,
 "envTags":["rain","highway"],"capabilities":["wiper","light","seat","odometer","eta","speed","gear"]}
JSON
curl -sf -X PUT "$BASE/game.json" -d "{\"ts\":$NOW,\"eggTier\":\"mid\",\"stage\":\"incubating\",\"progress\":0.0,\"speciesId\":null,\"attribute\":null,\"tier\":null,\"careCount\":0,\"lookOutCount\":0,\"hatchAtM\":25000,\"hatchAtSec\":null}" >/dev/null

echo "$SID"
echo "pairCode 483920 · 폰 앱에서 수동 입력으로 붙을 수 있습니다"
