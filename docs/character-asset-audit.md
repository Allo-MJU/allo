# 캐릭터 원본 및 게임 목록 불일치 조사 (2026-11-12)

## 사용자 결정

- 바탕화면 `/Users/leejiho/Desktop/assets`의 캐릭터 12종을 정식 표시 기준으로 사용한다.
- 임의 생성한 신규 디자인과 동작 시트 대신 제공된 캐릭터 원본을 사용한다.
- 로고는 수정하지 않는다.
- 새 6종의 한글 이름·속성·등급·획득 조건을 결정하기 전에 GitHub 기록을 먼저 확인한다.

## 실제 대조

공통 6종: road_sprout, puddle_pip, lamp_moth, storm_lantern, highway_comet, sea_mist.
이 6종의 Desktop/assets idle/move/sleep PNG 18장은 기존 phone/assets/poses 원본과 byte가 동일하다.

게임에만 있던 6종: bridge_hopper, mountain_sprite, river_glider, tide_keeper, tunnel_moth, star_owl.
제공된 원본에만 있는 6종: ember_crab, dewcap, cloud_strider, pebble_orbit, breeze_wyrm, dune_roller.

게임의 구 6종은 최초 저장소 세팅 커밋 `637303e`(2026-11-02)의 data/species.json에 이미 정의되어 있었다. 이번 작업에서 새로 명명한 것은 아니지만, 이 오래된 목록에 맞춰 신규 이미지를 생성한 판단은 제공된 아트와의 불일치를 확대했다.

## GitHub 확인 결과

- 디자인 시스템 3.2: 디자인 전용 6종의 species.json 항목은 없음. 한글 이름·등급·출현 조건은 C가 정한다고 명시.
  https://github.com/Allo-MJU/allo/blob/docs/design-refine/docs/design-system.md
- 기능 개편 명세 13.2: 공통/코드 전용/디자인 전용을 각각 6종씩 명시하고, 일대일 대응·게임 속성·획득 조건·한글 이름이 정해져 있지 않다고 기록.
  https://github.com/Allo-MJU/allo/blob/docs/feature-rework-spec/docs/feature-rework-spec.md
- PR #53의 11/12 후속 댓글: 기존 코드 ID/획득 조건/저장/역할 유지, 공통 6종부터 연결하며 다른 외형을 임의 교체하지 않음.
  https://github.com/Allo-MJU/allo/pull/53#issuecomment-6817883999
- 이슈 #54의 11/12 후속 댓글도 동일한 방침. 새 6종의 확정 게임 메타데이터 표는 없음.
  https://github.com/Allo-MJU/allo/issues/54#issuecomment-6817888570
- PR #48, #76, #86, #90, #97 본문/댓글도 읽음. PR #97에 디자인 원본 12종이 있으나 게임 규칙 확정 기록은 찾지 못함.
- PR #113은 추가 생성 6종을 광장 전용 경로에 포함한다고 기록한다. 제공된 Desktop/assets 원본과 같다고 해석하면 안 된다.
  https://github.com/Allo-MJU/allo/pull/113

## 조사 범위와 적용 상태

GitHub CLI로 이슈/PR 이름 검색 및 #53/#54/#86 전체 댓글·#53 리뷰, #48/#76/#90/#97/#113 본문·댓글을 읽고 원격 문서 브랜치를 대조했다. 읽기 전용이며 GitHub에 댓글/수정/머지는 하지 않았다.

Desktop/assets 원본 해시 목록: tasks/desktop-character-assets-audit.json.
원본 12종 파일과 별도 표시 목록을 /tmp/allo-provided-assets에 준비했으나, 이 조사 턴에서는 실제 앱이나 게임 저장 데이터·획득 규칙을 교체하지 않았다. 새 6종에 구 6종의 ID나 조건을 임의 배정하지 않았다. 제공된 로고와 기존 앱 로고도 변경하지 않았다.

## 후속 적용 완료

사용자가 게임 규칙 유지·표시만 제공12종으로 변경을 확정한 뒤 적용했다. data/characters.json이 Pleos 표시 정본이며, data/species.json은 변경하지 않았다. 생성 동작 시트는 APK에서 제외하고 원본120파일의 bytes를 검증했다. 로고를 포함한 앱 리소스는 해시가 동일하다. 실제 앱 내부 SuppliedCharactersActivity에서12종을 확인했다. 세부 결과는 tasks/pleos-supplied-art-verification.json 및 tasks/todo.md에 기록했다.
