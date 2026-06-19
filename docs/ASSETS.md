# ASSETS.md — 캐릭터 에셋 제작·교체 기록

라이선스는 저장소 루트의 `ASSETS-LICENSE` 참조 (코드 MIT와 분리).

## 1. 현행 에셋: 절차적 SVG 스프라이트 (v1)

- **생성 방법**: 외부 API 없이 캐릭터별로 손수 설계한 SVG를
  `scripts/gen-placeholders.mjs` 가 sharp(librsvg)로 래스터라이즈.
- **생성일**: 2026-06-12 (1~12종) · 2026-06-18 (13~24종 확장)
- **출력**: `assets/characters/{id}.png` — 512×512, 투명 배경, 24장.
  (`_contactsheet.png` 는 6×4 육안 중복 점검용 보조 산출물 — 게임에서 미사용.)
- **재생성**: `node scripts/gen-placeholders.mjs` (일부만: `... moka doto`),
  육안 점검 시트는 `node scripts/gen-placeholders.mjs --sheet`.
  생성 후 Godot headless `--import` 로 .import 메타 갱신.
- **검증(스크립트 내장)**: (a) id·모티프를 IP/작가명 금지어 셋과 대조 →
  매칭 시 `process.exit(1)`, (b) 512² / ≥1KB / 네 모서리 알파=0,
  (c) `--sheet` 컨택트시트로 실루엣 중복 육안 확인.
- **디자인 언어** (docs/GAME_DESIGN.md §4 아트 바이블): 점 눈 2 + 작은 입 +
  분홍 볼터치 + 2~2.5등신 + 파스텔 단색 몸 + 어두운 외곽선 + 식별 소품 1개.
  확장 12종은 한 "가문" 응집을 위해 몸색을 `hsl(hue, S0.11, L0.86)` 파스텔
  대역에서 산출하고(외곽선 = 동계열 L−0.40), 몸 세로 그라데이션 + 하단 셀
  음영(opacity 0.12) + 볼 글로우 림 + 눈 하이라이트 2점을 공통 적용한다.
  희귀도 연출은 런타임 오버레이 담당이라 에셋에 넣지 않음 — 예외로
  금붕·별똥(legendary)만 그라데이션 + 미세 광택/빛꼬리를 허용.

| id | 이름 | 희귀도 | 식별 소품 / 형태 특징 |
|---|---|---|---|
| moka | 모카 | common | 머리 위 새싹, 크림색 몸 + 큰 두더지 앞발 |
| somsom | 솜솜 | common | 구름형 뭉게 윤곽 양털 + 베이지 얼굴 패치 |
| kongkong | 콩콩 | common | 물결 밑단 꼬투리 후드 모자 + 꼭지 덩굴 |
| ppiyak | 삐약 | common | 지그재그 단 알껍질 바지 + 다이아 부리 |
| doto | 도토 | common | 도토리 깍정이 베레모 + 큰 말림 꼬리 |
| dorong | 도롱 | common | 머리 위 외측 깃아가미 3쌍 + 분홍 타원 몸 |
| gosum | 고슴 | common | 등의 둥근 가시 능선 + 뾰족 주둥이 + 코점 |
| gaegul | 개굴 | common | 머리 위 돌출 눈 2개 + 넓은 타원 + 벌린 뒷다리 |
| ddalbang | 딸방 | common | 방울형 몸 + 딸기 꼭다리 별잎 + 점박이 씨 |
| sikppang | 식빵 | common | 둥근 사각 식빵 실루엣 + 크러스트 테두리 + ω입 |
| pudding | 푸딩 | rare | 푸딩 실루엣 + 카라멜 드립 층 |
| jiji | 지지 | rare | 분홍-하늘 투톤 둥근 사각 몸 + 경계 심 |
| mongdang | 몽당 | rare | 깎인 나무 원뿔 + 연필심 고깔 머리 |
| latte | 라떼 | rare | 배의 크림 패치에 라떼아트 로제타+하트, 수염 |
| mongsong | 몽송 | rare | 긴 타원 몸 + 짧은 옆 지느러미 + 수염 + 꼬리지느러미 |
| dalbo | 달보 | rare | 머리 위 방사형 홀씨 갓 + 떠다니는 솜털 |
| beoseot | 버섯 | rare | 둥근 점박이 갓(머리) + 크림 기둥 몸 |
| jogyak | 조약 | rare | 둥근 사각 자갈 몸 + 머리 위 이끼 한 줌 + 물결 점 |
| byeolgaru | 별가루 | epic | 둥근 8뿔 별사탕 몸 + 떠다니는 반짝이 |
| haedal | 해달 | epic | S곡선 해마 몸 + 말린 꼬리 + 등지느러미 |
| buong | 부엉 | epic | 바깥쪽으로 비스듬한 짧은 귀깃 + 졸린 점눈 |
| gureum | 구름 | epic | cloudBlob 구름 몸 + 머리 위 미니 무지개 |
| geumbung | 금붕 | legendary | 물고기형 빵 + 와플 격자 결 + 갈래 꼬리 (금 그라데이션 허용) |
| byeolttong | 별똥 | legendary | 둥근 5뿔 별 몸 + 뒤로 흐르는 빛꼬리 + 반짝 |

## 1B. 배경 소품 (decor) — 절차적 SVG

- **생성**: `scripts/gen-decor.mjs` (캐릭터와 동일 sharp/librsvg 파이프라인, 외부 API·IP 없음).
- **출력**: `assets/decor/*.png` — 투명 배경. 목장 5레이어(docs/DESIGN_SPEC §C)의
  언덕·소품 레이어와 가챠 빈 무대를 채운다. 캐릭터와 같은 파스텔로 통일.
- **목록**: `hill_far`·`hill_near`(대기원근 언덕), `tree`·`fence`·`pond`·`rock`·
  `stump`·`grasstuft`, `flower_pink/purple/blue`, `gacha_machine`(가챠 캡슐머신),
  `toggle_on/off`(CheckButton 코지 pill 스위치).
- **재생성**: `node scripts/gen-decor.mjs` (일부만: `... hill_far hill_near`) → Godot `--import`.

## 1C. 효과음 (sfx) — 절차적 WAV

- **생성**: `scripts/gen-sfx.mjs` — 외부 샘플 없이 사인/감쇠 합성으로 생성(저작권 무관).
- **출력**: `assets/sfx/*.wav` — 9종: click·ding·boop·coin·pop·chime·whoosh·swish·fanfare.
- **재생**: autoload `Sfx`(scripts/autoload/sfx.gd). 설정 '조용 모드' 시 음소거.
- **재생성**: `node scripts/gen-sfx.mjs` → Godot `--import`.

## 1D. UI 아이콘 — Lucide (ISC)

- **출처**: [Lucide](https://lucide.dev) 아이콘 SVG (ISC 라이선스, 상업적 사용·재배포 허용).
- **저장**: `assets/icons/*.svg` (원본 SVG 그대로). 코드에서 `scripts/ui/icons.gd`
  `Icons.make(semantic, color, size)` 가 의미명→파일명 매핑 후 색을 입혀 TextureRect로 사용.
- **이모지 대체**: UI 전반의 이모지를 본 아이콘 세트로 교체(저시인성·플랫폼별 렌더 편차 제거).
- **라이선스 고지**: `ASSETS-LICENSE` 의 Lucide(ISC) 절 참조.

## 2. 향후 AI 아트 교체 절차 (빌드타임 전용)

런타임 게임 코드에서 이미지 생성을 호출하지 않는다 (docs/RISKS.md security).

1. `.env` 에 `OPENROUTER_API_KEY` 준비 (커밋 금지 — .gitignore 선행 확인).
2. `node scripts/gen-characters-openrouter.mjs` 수동 실행
   (모델 google/gemini-2.5-flash-image, 캐릭터별 고정 seed,
   마젠타 #FF00FF 크로마키 후처리 — 흰배경 flood-fill은 파스텔 몸을
   깨뜨리므로 금지, docs/RISKS.md feasibility).
3. 아래 검수 체크리스트를 **전부** 통과한 이미지만
   `assets/characters/{id}.png` 로 교체 후 Godot `--import` 재실행.
4. 본 문서에 교체 캐릭터·생성일·모델·seed를 기록하고,
   `ASSETS-LICENSE` 의 AI 생성 에셋 고지 절을 활성화한다.

### 검수 체크리스트 (이미지당, 사람이 직접)

- [ ] **IP 유사성 육안 대조**: 주요 카와이 IP의 대표 캐릭터들과 나란히 놓고
      "동일 캐릭터로 오인될 수 있는가"를 확인. 실루엣·배색·무늬·종(種)
      조합이 1:1로 겹치면 폐기 후 재생성 (흰 둥근 몸+세모 귀 콤보 등 금지).
- [ ] 아트 바이블 준수: 점 눈 2 / 작은 입 / 볼터치 / 2~2.5등신 / 파스텔 /
      어두운 외곽선 / 해당 캐릭터의 식별 소품이 정확히 1개 존재.
- [ ] 모티프 형태가 읽히는가 (양=구름, 푸딩=카라멜 층, 붕어빵=격자 결 …).
- [ ] 배경 완전 투명: 크로마키 후 마젠타 잔여 픽셀·프린지 없음.
- [ ] 512×512, 캐릭터가 중앙에 적절한 여백으로 배치.
- [ ] 텍스트·워터마크·서명 형태의 아티팩트 없음.
- [ ] 프롬프트·생성일·모델·seed가 본 문서에 기록됨 (독자 창작 과정 입증용).

## 3. 변경 이력

- 2026-06-12: v1 — 절차적 SVG 12종 최초 생성 (`scripts/gen-placeholders.mjs`).
- 2026-06-18: v2 — 로스터 12 → 24종 확장. 신규 12종(dorong/gosum/gaegul/
  ddalbang/sikppang/mongsong/dalbo/beoseot/jogyak/haedal/gureum/byeolttong)에
  `hsl`/`outlineOf`/`bodyGrad`/`cellShade`/`blushGlow`/`eye2` 헬퍼 적용.
  생성기에 금지어 게이트 + `--sheet` 컨택트시트 모드 추가. 기존 12종 렌더
  무변경(바이트 동일). 분포 common 10 / rare 8 / epic 4 / legendary 2.
- 2026-06-18: 디자인 오버홀 — 배경 소품(§1B, gen-decor.mjs)·효과음(§1C,
  gen-sfx.mjs)·Lucide 아이콘(§1D) 3개 에셋 카테고리 신설. 성인 타깃에 맞춰
  캐릭터 팔레트를 mute()(채도×0.6·명도−6%)로 더스티 파스텔화. 언덕 명암 대비 상향.

### 신규 12종 이름 상표 사전검색 게이트 (출시 전 수기 확인)

영문 소문자 id + 한글명에 대해 알려진 카와이 IP 캐릭터명과의 1:1 충돌 여부를
육안/검색으로 점검. 모티프는 모두 일반 동물·사물 stock이며, 세모 귀 콤보를
쓰지 않고 아가미/가시/돌출눈/홀씨 갓 등으로 실루엣을 차별화함.

- [ ] dorong(도롱) · gosum(고슴) · gaegul(개굴) · ddalbang(딸방)
- [ ] sikppang(식빵) · mongsong(몽송) · dalbo(달보) · beoseot(버섯)
- [ ] jogyak(조약) · haedal(해달) · gureum(구름) · byeolttong(별똥)
