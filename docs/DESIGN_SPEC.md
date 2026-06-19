Confirmed: no sfx.gd, no juice.gd, no gen-decor.mjs, no assets/decor or assets/bg dirs yet. ASSETS-LICENSE exists (47 lines). Everything is verified. I'll now write the implementation spec grounded in the actual codebase.

# 몽글목장 — 시니어 디렉터 완성 스펙 (실행안)

검증 완료: 현재 `theme_setup.gd`는 **다크 Tailwind 팔레트**(코지 아님 — 이게 핵심 갭). `_stylebox()`에 그림자 없음. `ranch.gd` 마당은 단색 `#9fd08c` Panel 1장. HUD/네비는 이모지 텍스트. `character_sprite.gd`는 이미 숨쉬기/squash&stretch/joy_jump/레벨업 elastic 보유. `gen-placeholders.mjs`는 `eye/sleepyEye/mouth/blush/stub/sparkle/cloudBlob/smoothStar` 헬퍼·`INK=#3B3129`·blush opacity 0.42·외곽선8 보유. `assets/decor`·`sfx.gd`·`juice.gd`는 **아직 없음**(신설 대상). 모든 경로/상수 실재 확인함.

---

## A. 캐릭터 로스터 확장 (12 → 24종)

목표 **24종**. 동물의숲·코지 수집게임 표준 로스터(20~30종)에 맞춘 최소 완성 규모. 현 희귀도 분포(common 5 / rare 4 / epic 2 / legendary 1)를 2배로 — common 10 / rare 8 / epic 4 / legendary 2.

추가 12종 (모두 IP-무관 일반 모티프, 식별 소품 1개, 도형 가문 명시):

| id | 이름 | 모티프 | 희귀도 | weight | 몸 도형 가문 | 식별 소품(실루엣 브레이크) |
|---|---|---|---|---|---|---|
| dorong | 도롱 | 분홍 아홀로틀 | common | 0.7 | 타원 | 머리 위 외측 깃아가미 3쌍 |
| gosum | 고슴 | 베이지 고슴도치 | common | 0.6 | 타원 | 등의 둥근 가시 능선 |
| gaegul | 개굴 | 민트 개구리 | common | 0.6 | 넓은 타원 | 머리 위 돌출 눈 2개 |
| ddalbang | 딸방 | 딸기우유 방울 | common | 0.5 | 방울형 | 꼭지 딸기 꼭다리 + 점박이 씨 |
| sikppang | 식빵 | 식빵 고양이 한 조각 | common | 0.5 | 둥근 사각 | 사각 빵 실루엣 + 가장자리 크러스트 |
| mongsong | 몽송 | 회색 물범 | rare | 0.25 | 긴 타원 | 짧은 지느러미 + 수염 |
| dalbo | 달보 | 민들레 홀씨 요정 | rare | 0.22 | 원 | 머리 위 홀씨 갓 + 떠다니는 솜털 |
| beoseot | 버섯 | 빨강물방울 버섯 | rare | 0.2 | 기둥형 | 둥근 점박이 갓(머리) |
| jog약 | 조약 | 강가 조약돌 정령 | rare | 0.18 | 둥근 사각 | 이끼 한 줌 + 물결 점 |
| haedal | 해달 | 자수정 해마 | epic | 0.045 | S곡선 | 말린 꼬리 + 등지느러미 |
| gu름 | 구름 | 솜사탕 구름 정령 | epic | 0.035 | cloudBlob | 머리 위 미니 무지개 |
| byeolttong | 별똥 | 유성 꼬리 별 | legendary | 0.004 | smoothStar | 뒤로 흐르는 빛꼬리 + 반짝 |

오리지널 보장 규칙(생성 스크립트에 하드코딩):
1. **금지어 검증** — 생성 전 모티프 문자열을 금지어 셋(IP명·작가명, RISKS §8.1)과 대조, 매칭 시 `process.exit(1)`. `gen-placeholders.mjs main()`에 추가.
2. **3-조합 충돌 회피** — '흰 둥근 몸+세모 귀', '팔자무늬 고양이', '노란 토끼+세모귀' 조합 금지(RISKS §8.2). 신규 12종은 세모 귀를 쓰지 않음(아가미/가시/돌출눈/갓으로 대체).
3. **실루엣 테스트 자동화** — `gen-placeholders.mjs main()`의 검증 루프에 추가: PNG를 검정 단색 채움 후 48×48 축소, 알파>50% 픽셀 비율이 인접 캐릭터와 IoU 0.92 미만이어야 통과(너무 닮으면 실패). 소품이 외곽으로 돌출하므로 자연히 분리됨.
4. **이름 상표 사전검색** — 출시 전 12개 신규 한글명 수기 게이트(`docs/ASSETS.md` 체크리스트 행 추가).

완료 기준: 24종 PNG가 `--headless --import` 통과 + `Characters.ROSTER` 24엔트리 + `test_runner.gd` 가챠 풀 합계 weight 검증 통과 + 24종 1장 컨택트시트에서 육안 중복 0.

---

## B. 캐릭터 아트바이블 정교화 (절차적 SVG 구현형)

현 코드가 이미 6요소(점눈/입/볼/2.5등신/파스텔단색/외곽선)를 충족 — 방향은 정확. **"더 귀엽게"의 구체 규칙**을 헬퍼 추가로 강제한다. 모든 값은 `gen-placeholders.mjs` 상수로 고정해 24종 일관성 확보.

**B1. 색 시스템 — 즉흥 hex → OKLCH 계산 생성**
- 현재 몸색이 하드코딩(`#F4E5C8` 등). 신규 12종은 `hsl()` 헬퍼로 산출: **L 0.86, C 0.11**(파스텔 카와이 대역) 고정, **hue만 색상환 12등분**. 명도/채도 고정 → 24종이 자동으로 "한 가문".
- 외곽선색 = 몸색 hue 동계열 + L −0.40 (현 moka `#8A6F52` 패턴 일반화). 헬퍼 `outlineOf(bodyHsl)`.
- 잉크 `INK=#3B3129` 전 캐릭터 공통 유지(응집 핵심).

**B2. 등신·눈·볼 (더 큐트하게)**
- 등신: 머리:몸 = 1:0.8 유지. 신규 중 3종(haedal/mongsong/gaegul)은 다리노출 3등신형으로 체형 다양성.
- **눈 키우기 + 하이라이트 2점**: `eye()`에 둘째 하이라이트(작은 하단점) 추가 — 카와이 큐티의 결정타. `r` 기본 12→13, 간격은 얼굴폭의 0.62.
- **볼터치**: opacity 0.42 유지, 신규 헬퍼 `blushGlow()` = 볼 원 + radial 그라데이션 림(0.42→0)으로 "디지털 글로우" 부여.
- 입: 작은 곡선 유지. 표정 라이브러리화(B5).

**B3. 외곽선 — 굵기 변조(anti-AI)**
- 현 일괄 stroke 8 → 외곽선 8, 내부선 5~6 위계 유지(이미 적용). **추가**: 외곽선 path에 `stroke-linejoin:round`(이미 svgDoc에 적용됨) + 하단부만 +1px(접지 무게감). 헬퍼 단순화 위해 선택적.

**B4. 그림자·볼륨 (말랑 3D)**
- **몸 세로 그라데이션**: 단색 → 상단 +6% 밝기 linearGradient(`bodyGrad(body)` defs 헬퍼). "퍼피/부풀린 3D" 효과. legendary geumbung이 이미 쓰는 `goldGrad` 패턴 일반화.
- **셀 음영 2톤**: 몸 하단 1/3에 어두운 동계열 반투명 호(opacity 0.12) 1겹 — `cellShade()` 헬퍼. 매끈함 제거 = anti-AI.
- 발밑 접지 그림자는 런타임(`character_sprite._draw`)이 이미 처리 — PNG엔 넣지 않음(중복 방지).

**B5. 표정 라이브러리 (모듈 직교 조합)**
- 현 `eye`/`sleepyEye` 2종 → **4 가문**: `happy`(기본 점눈+곡선입), `sleepy`(sleepyEye), `curious`(눈 한쪽 ^ + 작은 o입), `joy`(>< 감은 눈 + 큰 미소). 캐논 PNG는 `happy` 고정. 나머지는 가챠 등장/간식/레벨업 연출용으로 향후 파생 PNG 생성 가능(파이프라인 동일).

완료 기준: `bodyGrad`/`cellShade`/`blushGlow`/`outlineOf`/`hsl` 헬퍼가 신규 12종에 적용 + 24종 컨택트시트에서 색온도·명도 이탈자 0 + 기존 12종 회귀 렌더 동일(diff 없음, 신규 헬퍼는 신규 캐릭터에만).

---

## C. 목장 배경 리디자인

단색 `#9fd08c` Panel(`ranch.gd` L95-100) → **5레이어 스택**. Kitfox 코지 3기둥의 Softness 미달을 해소. 전부 Control + GradientTexture2D + 빌드타임 SVG→PNG(런타임 생성 0).

**C1. 레이어 구성** (`_yard` 자식, anchor full-rect, 뒤→앞)
1. **하늘** — `TextureRect.texture = GradientTexture2D`(세로 선형, 3스톱). 상단 베이비블루 → 중단 크림 → 하단 투명. RISKS 무관(리소스 보간).
2. **원경 언덕** — 빌드타임 SVG 둥근 언덕 실루엣 2겹 PNG(`assets/decor/hill_far.png`, `hill_near.png`). 대기원근: 먼 언덕 밝고 저채도.
3. **잔디 바닥** — 커스텀 Control `_draw()`(잔디 줄무늬 + 점박이 꽃, 정적 0코스트) 또는 2색 GradientTexture(상단 밝게). `_yard` Panel을 이걸로 교체.
4. **소품** — `assets/decor/*.png` TextureRect 산포(C3).
5. **전경 풀** — 하단 가장자리 풀잎 띠 PNG + 부드러운 비네트(반투명 어두운 테두리, "안전한 방" 신호).

**C2. 팔레트 hex** (theme 상수로 단일 출처)
- 하늘: `#AEC6CF`(베이비블루) → `#FAF0DC`(크림)
- 원경 언덕: `#C8E6B0`(밝은 연두) / 근경 언덕 `#A8D88E`
- 잔디 베이스: `#9FD08C`(상단) → `#86C06F`(하단)
- 꽃 점박이: `#F6BCCB`/`#FBE7A2`/`#DCC8F2`(파스텔 3색, 캐릭터 팔레트와 동일)
- 비네트: `#3B3129` @ alpha 0.10 (INK 재사용)

**C3. 배치 소품 목록** (`scripts/gen-decor.mjs` 신설 — gen-placeholders 파이프라인 복제)
- fence(울타리 가로바+기둥), tree(둥근 캐노피+줄기), pond(타원+밝은 림+물결 하이라이트), flower(5장 꽃잎 점), rock(둥근 자갈), cloud(`cloudBlob` 재사용), mushroom_decor, stump(그루터기 — 향후 꾸미기 상품)
- 각 SVG 함수 → `assets/decor/{name}.png`, 512² 투명. `docs/ASSETS.md` + `ASSETS-LICENSE` 갱신 의무.

**C4. 낮밤/시간대 연출**
- Ranch 씬 루트에 `CanvasModulate` 추가. `OS.get_datetime_dict_from_system()["hour"]`로 `Gradient.sample(hour/24.0)`.
- 톤: 밤(22~6시) 디새추레이트 블루 `#8090C0`, 노을(18~20) 핑크오렌지 `#F5C0A0`, 낮 흰색 통과 `#FFFFFF`. 캐릭터 PNG도 같이 톤 입혀져 통일.
- **무처벌 원칙 준수**: 실시간 시계 기반(접속 시각 톤)일 뿐 미접속 페널티 0. 구름 미세 드리프트 Tween만(정적 코지).

**C5. 구현 방법**: `_build_layout()`의 `_yard` 생성부를 레이어 스택 함수로 교체. CPUParticles2D(amount 12, 느린 상승 꽃잎/반짝, 기존 `sparkles.svg` 재활용) 1레이어 추가 — `clip_contents=true` 이미 ON.

완료 기준: 마당이 5레이어로 보이고 깊이감 있음 + 시간대별 톤 3종 육안 확인 + `--headless` 테스트 통과(GradientTexture/CanvasModulate는 헤드리스 안전) + decor PNG `--import` 통과 + ASSETS-LICENSE/ASSETS.md 갱신.

---

## D. UI/테마 오버홀 (다크 → 코지 라이트)

**핵심 진단**: 현 `theme_setup.gd`는 다크 Tailwind. 코지 게임에 부적합. 라이트 파스텔로 전환이 가장 큰 임팩트.

**D1. 색 팔레트 hex** (`theme_setup.gd` 상수 교체)
```
C_BG        #FAF4E8  (크림 배경, 순백 금지)
C_PANEL     #FFFDF7  (카드 표면)
C_PANEL_2   #F3E9D6  (raised)
C_BORDER    #E4D5BC
C_TEXT      #4A3F35  (어두운 갈색 — 순흑 금지, 저대비 따뜻)
C_MUTED     #9A8A76
C_ACCENT    #F2A0A8  (소프트 코랄 — 긍정/CTA)
C_ACCENT_2  #A8D8C0  (민트 — 보조)
C_OK        #8FCB8F  C_WARN #F5C97A  C_DANGER #E89090 (경고도 부드럽게)
```
- 60-30-10: 크림 지배 / 파스텔 카드 / 코랄 강조. 외곽선·텍스트는 어둡게(가독성 역설).

**D2. 카드/패널 (라운드+섀도)** — `_stylebox()`에 그림자 추가(ROI 1위, 단일 함수)
```gdscript
sb.shadow_size = 8
sb.shadow_offset = Vector2(0, 4)
sb.shadow_color = Color(0.29, 0.25, 0.21, 0.18)  # INK 계열 18%
sb.corner_detail = 12
sb.anti_aliasing_size = 1.0
```
- corner radius 6 → **16**(패널/카드), 버튼 12. `set_corner_radius_all`.
- StyleBoxFlat 그라데이션 미지원이므로 강조 패널만 GradientTexture2D + StyleBoxTexture 9-slice(빌드타임 리소스, RISKS 무관) 선택 적용.

**D3. 타이포 스케일** (`theme_setup.gd` 상수 + 클래스 등록, 인라인 override 제거)
```
FS_BODY 15 / FS_SUB 18 / FS_TITLE 24 / FS_DISPLAY 32
```
- `ranch.gd`의 산재한 14/18/22 override를 클래스 토큰으로 수렴.

**D4. 아이콘 전략 (이모지 → Lucide)**
- `icons.gd MAP`에 추가: `home`(목장), `book-open`(퀴즈/도감), `dices`(뽑기), `library`(도감), `store`(시장), `notebook-pen`(오답노트), `settings`(설정), `cookie`(간식), `timer`(공부동행). SVG는 lucide.dev에서 받아 `assets/icons/` 커밋(런타임 다운로드 금지 — 직접 커밋). ISC라 표기 부담 0.
- `ranch.gd NAV_ITEMS`를 이모지 텍스트 → `HBox(Icons.make(아이콘, C_TEXT, 22) + Label)` 구조로 변경.
- HUD `🪙/🎟️/🍪/🔥`을 `Icons.make("gold"/"ticket"/"cookie"/"flame")` + 숫자 라벨로. game-icons.net(CC0 기여분)에서 가챠 천장/희귀도 별만 보충(나머지 Lucide).

**D5. HUD/버튼/탭 개선**
- HUD를 PanelContainer 카드(라운드+섀도)로 감싸 단순 라벨 나열 탈피.
- 네비 버튼: 아이콘+라벨 세로 정렬, hover scale 1.05(E 참조).
- 화면 전환에 0.15~0.2s ColorRect alpha 페이드(저비용 폴리시).

완료 기준: 전 화면이 크림 라이트 테마로 통일 + 모든 카드에 부드러운 섀도 + 이모지 0개(전부 Lucide/CC0 아이콘) + `add_theme_font_size_override` 산재 제거 + `--headless` 통과. side-by-side로 ranch/quiz/gacha/collection/market 패널 corner radius·섀도 동일.

---

## E. 게임필 / Juice (전부 GDScript Tween, C# 금지 준수)

**신설 `scripts/ui/juice.gd`** (순수 함수, domain 아님). 코지 톤 = **절제**(스크린셰이크·강탄성 금지).

| 함수 | 동작 | 적용처 |
|---|---|---|
| `pop_in(node)` | scale 0.9→1.0 + alpha fade, TRANS_BACK/EASE_OUT 0.25s | 카드·팝업 등장 |
| `punch_scale(node)` | 1.0→0.96→1.0, 0.12s | 버튼 pressed |
| `hover(node, on)` | scale 1.0↔1.05, 0.2s SINE | 모든 버튼 mouse_entered/exited |
| `float_label(parent, "+N", color)` | 중력 포물선 라벨, velocity y −300 + 좌우 randf | 코인/티켓 증가(ProgressStore signal) |
| `pop_sparkle(node)` | `sparkles.svg` 1~2개 짧게 페이드 | 수집·간식 확정 |
| `hitstop(0.08)` | Engine.time_scale 0.07→1.0 | 가챠 레전더리 등장만 |
| `play_reward(node)` | punch + sparkle + sfx 묶음 | 가챠/레벨업 프리셋 |

**신설 `scripts/autoload/sfx.gd`** (AudioStreamPlayer 풀 4~6, `play(name, pitch=randf(0.95,1.05))`). ProgressStore signal에 연결(도메인 비침습).

사운드 큐 목록:
- 버튼 click: plop / 가챠 스핀: 상승 whoosh / 가챠 결과: 희귀도별 jingle(레전더리=가장 풍성) / 정답: 밝은 ding / 오답: 부드러운 boop(처벌 톤 금지) / 간식 주기: pop / 판매: 코인 cha-ching / 레벨업: chime / 화면 전환: 미세 swish.
- 에셋: Kenney "51 UI sounds" + "50 RPG sounds" + "85 jingles" (전부 CC0). 피치 랜덤화로 반복 단조로움 제거.

기존 보유 juice(유지·확장): `character_sprite`의 breathing/squash/joy_jump/레벨업 elastic은 그대로. 가챠 등장에 TRANS_ELASTIC + sparkle 추가.

완료 기준: 모든 버튼이 hover/press 반응 + 코인 증가 시 `+N` 포물선 + 가챠 레전더리에 hitstop + 9종 사운드 큐 연결 + 음소거 토글(설정) 동작 + `--headless`에서 sfx.gd가 오디오 디바이스 없이 크래시 안 함(헤드리스 가드).

---

## F. 오픈소스 / CC0 리소스

| 리소스 | 라이선스 | URL | 용도 | 절차적 대안 |
|---|---|---|---|---|
| Lucide Icons | ISC (표기 불필요) | github.com/lucide-icons/lucide / lucide.dev | 네비·HUD·UI 아이콘. SVG 직접 커밋 | 이미 보유 11종 확장 |
| game-icons.net | CC0(기여분)/CC-BY 3.0 | game-icons.net | 가챠 천장·희귀도 별·시세 화살표 | CC0분만 선별 → 표기 0 |
| Kenney UI Pack Adventure | CC0 | kenney.nl/assets/ui-pack | 강조 패널 9-slice(선택) | StyleBoxFlat 섀도로 자체 재현 우선 |
| Kenney 51 UI + 50 RPG + 85 jingles | CC0 | opengameart.org/content/all-cc0-uploader-kenney | SFX 큐 전부 | — |
| Pretendard / Noto Sans JP | OFL | (이미 보유) | 폰트 | — |

**절차적 우선 원칙**: 배경·소품·카드룩은 외부 에셋보다 자체 구현이 코드-우선 규율에 정합 —
- 카드/패널 = StyleBoxFlat(섀도+라운드), 외부 9-slice 불필요.
- 배경 하늘 = GradientTexture2D(에셋 0).
- 소품 = `gen-decor.mjs` 빌드타임 SVG→PNG(기존 sharp 파이프라인).
- 캐릭터 = `gen-placeholders.mjs` 확장(CC0 동물팩은 아트바이블 불일치 → 배경 장식·도감 실루엣 폴백으로만).
- 외부 CC0는 **아이콘(Lucide)·사운드(Kenney)**에 한정 — 이 둘만 자작이 비효율적이라 채용.

모든 CC0/CC-BY 채용 시 `ASSETS-LICENSE` 3절 + `docs/ASSETS.md`에 출처·생성일 기록(의무).

---

## G. 우선순위 구현 작업 목록 (임팩트 順)

**P0 — 테마 전환 (최대 임팩트, 최소 변경)**
1. `theme_setup.gd` 다크→크림 라이트 팔레트 교체 + `_stylebox()`에 shadow 3속성·corner_detail 12·AA 1.0·radius 16 추가. *완료기준: 전 화면이 코지 라이트로 통일, 모든 카드에 섀도, 헤드리스 통과.*
2. `ranch.gd` 단색 `_yard` → 하늘 GradientTexture2D + 잔디 그라데이션 + 비네트(최소 3레이어). *완료기준: 마당에 하늘/잔디 깊이감, Softness 기둥 충족.*

**P1 — 아이콘·타이포 정리**
3. `icons.gd MAP` 9개 추가 + Lucide SVG 커밋 + `ranch.gd` NAV/HUD 이모지 → 아이콘+라벨. *완료기준: 이모지 0개, 라벨 없이 식별 가능, 고대비.*
4. 타이포 토큰(15/18/24/32) 클래스 등록 + 인라인 override 제거. *완료기준: 화면 간 폰트 위계 일관.*

**P2 — Juice·사운드**
5. `scripts/ui/juice.gd` 신설 + 버튼 hover/press·화면 전환 페이드 전 화면 적용. *완료기준: 모든 버튼 반응, 전환 페이드.*
6. `scripts/autoload/sfx.gd` 신설 + Kenney CC0 사운드 + ProgressStore signal 연결 + 음소거 토글. *완료기준: 9큐 동작, 헤드리스 무크래시, 음소거.*
7. 가챠 레전더리 hitstop + sparkle, 코인 증가 `+N` 포물선. *완료기준: 레전더리 등장 임팩트, 재화 피드백.*

**P3 — 배경 소품·낮밤**
8. `scripts/gen-decor.mjs` 신설 → fence/tree/pond/flower/rock/cloud PNG + 마당 배치(5레이어 완성). *완료기준: 살아있는 목장, decor `--import` 통과, ASSETS-LICENSE 갱신.*
9. Ranch 루트 CanvasModulate + 시각 기반 Gradient.sample 낮밤. *완료기준: 시간대 3톤, 무처벌 준수.*

**P4 — 캐릭터 확장 (가장 큰 작업)**
10. `gen-placeholders.mjs`에 B 헬퍼(`hsl`/`bodyGrad`/`cellShade`/`blushGlow`/`outlineOf`) + 표정 라이브러리 추가. *완료기준: 헬퍼가 신규에 적용, 기존 12종 회귀 동일.*
11. 신규 12종 SVG 함수 + `Characters.ROSTER` 12엔트리 + 금지어/실루엣 검증 로직 + 컨택트시트 모드. *완료기준: 24종 생성·`--import` 통과, 컨택트시트 중복 0, 가챠 weight 합계 테스트 통과.*
12. 출시 게이트: 24종 육안 IP 유사성 대조 + 이름 상표 검색 + `test_runner.gd` 갱신. *완료기준: 헤드리스 전체 통과, 게이트 체크리스트 완료.*

**전체 완료 기준(senior OK)**: Kitfox 3기둥(Safety 기존 충족 / Abundance·Softness 신규 충족) + 전 화면 시각 일관(공용 theme) + 이모지 0 + 모든 인터랙션 juice+사운드 + 24종 응집 로스터 + `godot --headless --script res://tests/test_runner.gd` 전부 통과 + `--import` 클린 + RISKS 11항 전부 무위반(런타임 생성 0, IP명 0, 무처벌, 토큰 UI 없음).

---

**제약 준수 요약**: 전 작업 Control-우선(Node2D/TileMap 미사용) · 캐릭터/배경/소품은 빌드타임 SVG→PNG(런타임 생성 0) · IP명 0(금지어 검증 하드코딩) · 1캐릭터=1PNG(연출은 Tween) · 무처벌(낮밤은 톤만, 페널티 0) · 코드-우선(StyleBoxFlat·GradientTexture로 에셋 최소화).

**참조 파일(절대경로)**: `C:\Users\admin\Downloads\all_project\study_game_v2\scripts\autoload\theme_setup.gd`(P0-1) · `scripts\ui\ranch.gd`(P0-2,P1-3) · `scripts\ui\icons.gd`(P1-3) · `scripts\gen-placeholders.mjs`(P4-10,11) · `scripts\domain\characters.gd`(P4-11) · `scripts\ui\character_sprite.gd`(기존 juice 확장) · 신설: `scripts\ui\juice.gd`·`scripts\autoload\sfx.gd`·`scripts\gen-decor.mjs` · 갱신 의무: `ASSETS-LICENSE`·`docs\ASSETS.md`·`docs\GAME_DESIGN.md`(§4 아트바이블 토큰표)·`tests\test_runner.gd`.