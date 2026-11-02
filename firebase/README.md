# Firebase

Realtime Database 하나만 씁니다. 스키마는 `docs/schema.md` 3장이 기준입니다.

## 셋업 (C, Day 1)

1. Firebase 콘솔에서 프로젝트 생성 → Realtime Database 생성 (asia-southeast1 권장)
2. 규칙 탭에 `database.rules.json` 붙여넣기
3. Android 앱 등록 두 개
   - 차량 앱: 패키지 `ai.allo.car` → `google-services.json`을 `car/app/`에
   - 폰 앱: `flutterfire configure` 로 `phone/lib/firebase_options.dart` 생성
4. 두 파일 모두 **git에 올리지 않습니다** (`.gitignore` 처리됨). 팀 내 별도 채널로 공유
5. DB URL을 팀에 공유 → `scripts/`의 `ALLO_DB_URL`로 사용

## 규칙 요약

- 세션은 생성 후 24시간만 읽기·쓰기 가능
- `vehicle`에 `lat`/`lng`/`latitude`/`longitude` 키는 규칙 단에서 거부
- `vehicle`은 `ts`, `gear` 필수. `game`은 `ts`, `stage` 필수

## 만료 데이터 정리

규칙이 접근만 막고 데이터를 지우진 않습니다. 접수 전까지 둘 중 하나를 택해 README에 명시합니다.

- Cloud Functions 스케줄로 `createdAt < now - 24h` 세션 삭제
- 수동 삭제 정책 (공모전 기간엔 이걸로 충분)
