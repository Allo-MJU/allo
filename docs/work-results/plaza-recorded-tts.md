# Pleos 광장 제공 TTS 연결

2026-11-14 · 원본: Downloads/allo_tts_plaza

- 현재 표시12종24문장과 manifest 문구가 전부 정확히 일치한다. 불일치/누락0개.
- 캐릭터 탭과 말풍선 다시 듣기는 제공 WAV를 재생한다. 기존 광장 문구·교대 순서는 유지한다.
- 새 캐릭터 선택 시 이전 준비/재생을 해제한다. 늦게 도착한 이전 파일의 준비·완료·실패 콜백은 무시한다.
- 반복 탭·페이지/친구 목록/연결 상태 변경·앱 pause·광장 화면 종료 시 기존 stop/release 경로를 유지한다.
- 이야기 탭과 운전자 음성은 기존 합성 음성 경로를 유지한다. 이 변경은 광장 전용이다.

| 캐릭터 ID | 파일 | 화면 및 manifest 대사 | SHA256 |
|---|---|---|---|
| road_sprout | `road_sprout/plaza_1.wav` | 풀잎이 반짝인다! 정말 신기해. | `883ee05cdc5a7ef8e3c0a65c0afb799e2590932651a400bd6c1ccb538906bba5` |
| road_sprout | `road_sprout/plaza_2.wav` | 새로운 친구를 만나고 싶어! | `80b87d1b78aabab8b2aa8a207f177c60c700976d332e35248fc4b784b574904d` |
| puddle_pip | `puddle_pip/plaza_1.wav` | 첨벙첨벙, 물놀이가 제일 좋아! | `5d4b286fa3014cbcd46cfe2a93c6f7897fefc6b76a9811bb6b6900eb817532ea` |
| puddle_pip | `puddle_pip/plaza_2.wav` | 촉촉한 풀밭에서 놀고 싶어. 삐약! | `1702b40bf8593d233c1c085a13b35e18a96fa9f2307f0a9c6df99298e273a5a4` |
| storm_lantern | `storm_lantern/plaza_1.wav` | 광장에 씩씩한 등불 등장! 번쩍! | `35444f94e64362bca7962d24a895e48c9f9c3c2dd68c2b79a6d6c599580cab92` |
| storm_lantern | `storm_lantern/plaza_2.wav` | 내 작은 불빛으로 환하게 비출게. | `60b165bd0c384db40c0684ee50c62cd2a193be479a2b491466760165c7c3a807` |
| sea_mist | `sea_mist/plaza_1.wav` | 살며시 다가왔어. 몽글몽글. | `213fc4c974e2a4b5c4d0571b81481e3c62a83c40ed3b51e59cdbfe219f90f7d8` |
| sea_mist | `sea_mist/plaza_2.wav` | 조용히 쉬는 시간이 참 좋아. | `46d10e3b052cd92d7b06903a786b8146d4f9767ae5125b3097e7875ad797ad29` |
| lamp_moth | `lamp_moth/plaza_1.wav` | 작은 불빛만 봐도 신나. 반짝! | `7eb979f841d81c14fcdb54523f3cdb29722cda7d00b3e39df2b9d3f5e4bdd2c7` |
| lamp_moth | `lamp_moth/plaza_2.wav` | 환한 빛을 따라 산책하고 싶어. | `500e6a0d9911791fe2f6c08774cf6947655acbd9adc90ec1e12e662391b63337` |
| highway_comet | `highway_comet/plaza_1.wav` | 광장 한 바퀴, 신나게 달려! 슝! | `40c23c5486c4e55ece452c218b6f24103301b15da901d81b72b3ffb88b3529e6` |
| highway_comet | `highway_comet/plaza_2.wav` | 쌩쌩 달리고 잠깐 쉬는 거야. | `3a922759f69303049b14340204198bfed8438a8039c2ca97f516122e5d2ae93b` |
| breeze_wyrm | `breeze_wyrm/plaza_1.wav` | 바람 따라 산책할래. 산들산들. | `09c8a2507013b52b4812d6f04e74ae725e4f40f8b6a97c0933af63e58c4213e1` |
| breeze_wyrm | `breeze_wyrm/plaza_2.wav` | 나뭇잎 춤을 보고 싶어. 살랑. | `524c08162d991335041583001fc84ee6f72a5c9928b2d5b2078f8fe25b1884fe` |
| cloud_strider | `cloud_strider/plaza_1.wav` | 서두르지 않아도 좋아. 사뿐. | `ca32b2ac763325bc85268b527ea5d7441c692f76f24293b7fed1e95be9550170` |
| cloud_strider | `cloud_strider/plaza_2.wav` | 느긋한 산책이 내 취향이야. | `d3cac0e592e48d1d89df555b85739e163de28d00ad9fe6f2f47c701f314d2b69` |
| dewcap | `dewcap/plaza_1.wav` | 작은 이슬을 구경하고 싶어. | `76e319689b672ff370b9da7309f8902c205f8410d24c2049ae8bdcdc076ed9a7` |
| dewcap | `dewcap/plaza_2.wav` | 쉬는 동안 마음도 촉촉해져. | `4a18d595ed506264789301fd42b2d0776286b2001b82609331c3158762e9046d` |
| dune_roller | `dune_roller/plaza_1.wav` | 차근차근 걷는 게 좋아. | `12fbb16916b029a1e2faa8a7faec3ddf14a52dc86fa13172cd3050da6911878d` |
| dune_roller | `dune_roller/plaza_2.wav` | 둥근 돌을 떠올렸어. 또르르. | `90e0a64f76da7134fe4b5bb944949c5ca2a573b025773d4e25f6476b1428222b` |
| ember_crab | `ember_crab/plaza_1.wav` | 살짝 인사하러 왔어. 반가워. | `d7bf136eb67eb9add2e39851d8370a47b8de2eda06e8015dcf2d8b412e03677a` |
| ember_crab | `ember_crab/plaza_2.wav` | 포근하게 쉬고 싶은 날이야. | `8e6fedb7b5489b2e3c56f89cd26599e4966f353f024c54309a784376d2e73e1c` |
| pebble_orbit | `pebble_orbit/plaza_1.wav` | 동그란 모양이 참 재미있어. | `f496a10d9d582db2e761bd4dcc671de3309356129a20817b52d7cddbc4f27674` |
| pebble_orbit | `pebble_orbit/plaza_2.wav` | 천천히 둘러보고 싶어. 빙글. | `8c7db0d6d4160f91e2465a0a2a4d41c4054d9398654485bcd8ce15830aacd85b` |

## 검증 범위

manifest 대조와 WAV 구조·파일 바이트를 확인했다. 실제 발화 전사·청취 검수는 별도다. 빌드 및 자동 테스트 결과는 아래에 기록한다.

## 검증 결과

- 차량 전체330테스트 통과 (실패/오류/스킵0). 캐릭터 전환 시 이전 prepare/완료/오류 콜백 무시, 반복 탭 중단, 해제 후 지연 콜백, 재생 오류 복구 회귀 포함.
- app/preview debug APK 및 app release Kotlin 컴파일 성공.
- 두 APK의24 WAV가 원본과 byte동일, MediaPlayer openFd에 필요한 무압축 저장 확인.
- 실제 Pleos 기기 출력·청취·오디오 포커스 간섭 검증은 미실시.
