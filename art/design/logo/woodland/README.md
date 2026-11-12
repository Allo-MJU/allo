# 새 차량 화면 로고

사용자가 2026-11-12 첨부한 `KakaoTalk_Photo_2026-11-12-16-15-29.jpeg`를 `original.jpeg`에 보존한다. `allo-logo.png`는 해당 이미지의 흰 JPEG 배경을 코드로 투명화하고 여백만 잘랐다. AI 재생성·글자/캐릭터 재그리기는 하지 않았다.

재현: Pillow 환경에서 `python scripts/art/prepare_woodland_logo.py art/design/logo/woodland/original.jpeg art/design/logo/woodland/allo-logo.png`.

최저 RGB 값이 215 이하인 불투명 색상은 원본 RGB 그대로 유지한다. 215–245의 흰 가장자리는 white matte를 제거하고 alpha로 표현하며 245 이상의 흰색은 투명하다. 내부 흰 여백도 투명하게 처리한다. JPEG 특성상 테두리에는 미세한 압축 흔적이 남을 수 있다.

차량 `drawable-nodpi/allo_logo.png`에 적용하며 라이트·다크에서 같은 컬러 로고를 사용한다. 앱 런처 아이콘은 앞서 확정한 알 모양 A 전용 아이콘을 유지한다.
