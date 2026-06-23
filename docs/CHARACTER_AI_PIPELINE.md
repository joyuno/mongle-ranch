# CHARACTER_AI_PIPELINE.md — 빌드타임 AI 캐릭터 아트 파이프라인 (runbook)

> **상태: 미실행 스캐폴드.** 현재 출하 에셋은 `scripts/gen-placeholders.mjs` 의
> 절차적 SVG 24종이며 **이 문서가 지시하는 AI 생성은 아직 한 장도 수행되지 않았다.**
> 이 문서는 향후 GPU/사람 검수 패스를 위한 운영 매뉴얼(runbook)이다.
>
> **불변 규칙 (docs/RISKS.md, CLAUDE.md §1):**
> - 런타임 이미지 생성 API 호출 **금지** — 생성은 `scripts/*.mjs` 빌드타임 전용,
>   결과는 **사람 검수 후 커밋**.
> - 성인 대상 **더스티 파스텔 · 코지** 톤 (유아톤 금지 — MEMORY/design-direction).
> - **오리지널 IP만** — 타 IP 캐릭터·이름·작가명 일체 금지 (프롬프트 포함).
> - 배경 제거는 **마젠타 크로마키(#FF00FF) 또는 네이티브 알파** — 흰배경
>   flood-fill 금지 (파스텔 몸 내부 밝은 픽셀을 같이 날림).
> - 모든 교체분은 `docs/ASSETS.md` + `ASSETS-LICENSE` 갱신 의무.

---

## 0. Goal

24종 캐릭터(`docs/ASSETS.md §1` 로스터)를 **한 "가문"으로 보이는 응집된 AI 아트**로
교체하되, 다음을 동시에 만족한다:

1. **일관성** — 24종이 같은 화풍·팔레트·등신·선화 두께를 공유 (현 SVG의
   `hsl(hue, 0.11, 0.86)` 파스텔 대역 + 어두운 외곽선 응집을 계승).
2. **IP 분쟁 회피** — *우리 자체 레퍼런스로 스타일 LoRA를 학습*해 업스트림
   학습데이터(타 카와이 IP) 오염을 우회한다. 프롬프트·LoRA 어디에도 외부 IP명 없음.
3. **권리 확보** — 순수 AI 출력은 미국(USCO 2025 / *Thaler*) 등에서 저작권이
   없으므로, **사람의 창작적 기여**(스케치·큐레이션·인페인트·배열)를 기록해 권리를 주장.
4. **런타임 무의존** — 생성은 1회성 빌드 패스. 게임 바이너리에 생성 엔드포인트/키 없음.
5. **출하 산출물** — `assets/characters/{id}.png`, 512×512, 깨끗한 알파, 24장.

성공 기준: 24종 family matrix 사이드바이사이드가 한 가문으로 읽히고, IP 유사성
검수를 전원 통과하며, `docs/ASSETS.md` 검수 체크리스트 7항목 + 본 문서 §5 게이트를
전부 통과한 이미지만 커밋된다.

---

## 1. Pipeline steps (개요)

```
[0] 레퍼런스 수집 (현 24 SVG 렌더 + 무드보드)
        │
        ▼
[1] STYLE LoRA 학습  ──────────────► 우리 화풍 1개 (가문 응집 + IP 오염 회피)
        │
        ▼
[2] 캐릭터별 character sheet  ─────► 턴어라운드 + 표정 (per-id, 정체성 앵커)
        │
        ▼
[3] 생성 (ComfyUI + Flux)  ───────► style LoRA + IP-Adapter 멀티레퍼런스(w≈0.55)
        │                            (+ 선택: per-character LoRA)
        ▼
[4] 클린업 / 크로마·매팅  ─────────► BiRefNet/Bria 알파 매팅 → 마젠타 키 제거 → Aseprite 터치업
        │
        ▼
[5] 사람 검수 게이트  ─────────────► family matrix · IP 유사성 · 손/눈 아티팩트 · 512²+알파
        │
        ▼
[6] 커밋 / 기록  ──────────────────► assets/characters/ + docs/ASSETS.md + ASSETS-LICENSE
```

각 단계는 독립 산출물을 남기므로, 마음에 안 드는 캐릭터만 [2]~[5]를 재실행한다.

### 작업 디렉토리 레이아웃 (빌드타임 전용 — 게임에 번들 금지)

```
pipeline/                         # ← .gitignore 대상 (대용량 중간물), workflow JSON만 커밋
  refs/
    svg/                          # scripts/gen-placeholders.mjs 24 렌더 복사본 (스타일 학습 입력)
    moodboard/                    # 사람이 선별한 톤 레퍼런스 (더스티 파스텔/코지 — 외부 IP 캐릭터 제외)
  lora/
    mongle-style.safetensors      # [1] 산출물 (대용량 — 커밋하지 않음, 체크섬만 ASSETS.md 기록)
    char/{id}.safetensors         # [2] 선택적 per-character LoRA
  sheets/{id}/                    # [2] 턴어라운드 + 표정 시트
  raw/{id}/seed-*.png             # [3] 생성 원본 (마젠타 배경 포함)
  cut/{id}/seed-*.png             # [4] 알파 매팅 + 크로마키 후
  review/_family_matrix.png       # [5] 검수용 24종 대조 시트
scripts/
  gen-characters-openrouter.mjs   # 기존 SaaS 폴백 경로 (단발 생성, §7)
  comfy/                          # ← 신규: ComfyUI workflow JSON (커밋 대상, §3)
    mongle-style-train.json
    mongle-char-gen.json
    mongle-cleanup-matte.json
```

> **커밋되는 것:** ComfyUI workflow JSON, 시드 표, 프롬프트, 검수 시트(선택),
> 최종 PNG. **커밋 안 하는 것:** LoRA `.safetensors`(대용량), `pipeline/raw`·`cut`
> 중간물, 무드보드 원본(레퍼런스 출처 라이선스 미정 시). `.gitignore` 에 `pipeline/`
> 추가하고 workflow는 `scripts/comfy/` 에 별도 보관.

---

## 2. Step 1 — STYLE LoRA (가문 응집 + IP 오염 회피)

**왜 자체 레퍼런스인가:** Flux 베이스 모델로 바로 txt2img하면 (a) 24종 일관성이
시드마다 흔들리고, (b) "kawaii mascot" 프롬프트가 모델이 학습한 타 IP로 끌려가
의거성(依拠性) 리스크가 생긴다(docs/RISKS.md copyright [HIGH]). **우리가 직접 만든
24 SVG + 무드보드만으로 style LoRA를 학습**하면 화풍이 우리 자산에 고정되어 두 문제를
동시에 푼다.

| 항목 | 값 |
|---|---|
| 학습 입력 | `pipeline/refs/svg/` 24장 (현행 SVG 렌더) + `pipeline/refs/moodboard/` 사람 선별 톤 컷 |
| 베이스 | Flux.1 (dev 또는 schnell — 라이선스는 §6 참조) |
| 타입 | **Style** LoRA (캐릭터 정체성이 아니라 화풍·팔레트·선화·등신만 학습) |
| 캡션 | 트리거 토큰 `mngl_style` + 일반 기술어("flat pastel, thick dark outline, two heads tall"). **외부 IP명·작가명 절대 금지.** |
| 랭크/스텝 | dim 16~32, 1500~3000 step 권장(레퍼런스 24장 소량이므로 과적합 주의 — 낮은 LR + 정규화 이미지) |
| 산출물 | `pipeline/lora/mongle-style.safetensors` (커밋 X, sha256만 `docs/ASSETS.md` 기록) |

**무드보드 규칙:** 톤·구도·라이팅 레퍼런스만 모은다. 식별 가능한 타 IP 캐릭터
이미지는 무드보드에 **넣지 않는다**(학습 오염 + 증거 잔존 리스크). 색·질감·"코지함"
같은 추상 속성만 참조한다.

---

## 3. Step 2 — 캐릭터별 character sheet (정체성 앵커)

style LoRA로 화풍은 고정됐으니, 각 캐릭터의 **정체성(식별 소품 + 실루엣)** 을 시드마다
일관되게 묶기 위해 캐릭터 시트를 먼저 만든다. 이것이 [3]의 IP-Adapter 멀티레퍼런스
입력이 된다.

캐릭터 시트 = **턴어라운드**(정면·3/4·측면) + **표정 4종**(기본 / 기쁨 / 졸림 / 놀람).
표정은 게임 내 Tween 연출(bobbing·squash&stretch)과 별개로, 단일 캐노니컬 PNG를
고르기 위한 후보 풀이다(1캐릭터=1PNG 원칙은 유지 — docs/RISKS.md feasibility).

- 입력: style LoRA + 해당 id의 SVG 렌더 1장(IP-Adapter 레퍼런스) + 표정/뷰 프롬프트.
- 산출: `pipeline/sheets/{id}/turnaround.png`, `expr_*.png`.
- **선택적 per-character LoRA:** 시트가 좋으면 그 시트로 캐릭터 LoRA를 학습해
  복잡한 소품(예: 라떼아트 로제타, 와플 격자)의 시드 안정성을 높인다. 단순 캐릭터는
  생략하고 IP-Adapter만으로 충분.

---

## 4. Step 3 — 생성 (ComfyUI + Flux)

**도구: ComfyUI + Flux 로컬.** workflow는 JSON으로 `scripts/comfy/` 에 커밋(재현 가능,
리뷰 가능). SaaS(Scenario.gg / Layer.ai)는 GPU가 없을 때의 대안(§7).

`mongle-char-gen.json` 워크플로 노드 체인(개념):

```
Load Flux base
  → Apply LoRA (mongle-style.safetensors, strength ~0.8)
  → [선택] Apply LoRA (char/{id}.safetensors)
  → IP-Adapter (reference = sheets/{id}/turnaround.png, weight ≈ 0.55)
  → Positive: "{desc}, mngl_style, {STYLE 공통 블록}, solid #FF00FF magenta background"
  → Negative: "white background, gradient background, text, watermark, signature,
               extra limbs, deformed hands, six fingers, copyrighted character,
               pink/magenta on the body"
  → KSampler (per-character seed 고정 — §아래 시드 표)
  → SaveImage → pipeline/raw/{id}/seed-{n}.png
```

- **IP-Adapter weight ≈ 0.55**: 시트의 정체성은 따라오되 화풍이 시트에 과고착되지
  않는 균형값. 소품이 흐려지면 0.6~0.65로, 화풍이 흔들리면 0.5로 미세조정.
- **마젠타 배경 강제**: 프롬프트에 `solid #FF00FF magenta background` 고정(현
  `gen-characters-openrouter.mjs` `STYLE` 상수와 동일 전략). Flux도 "투명 배경"
  요구를 무시하고 단색을 깔기 때문에, 팔레트에 없는 채도 최대 마젠타를 깔아 [4]에서
  정확히 그 색만 벗긴다.
- **시드 결정성**: 캐릭터별 고정 seed 표를 유지(현 스크립트 `CHARACTERS[].seed`
  101~112 패턴을 24종으로 확장). 마음에 안 드는 것만 seed offset(+1000 등)으로 재롤.
- **프레이밍 룰**(legendary 폭주 방지, docs/RISKS.md [MEDIUM]): 프롬프트에
  "character fills 60-70% of canvas, accessories small, no giant aura, no encircling
  halo" 처음부터 포함. 희귀도 연출은 생성이 아니라 **Godot 런타임 오버레이** 담당.

---

## 5. Step 4 — 클린업 / 크로마·매팅

순서가 중요하다: **먼저 머리카락급 알파 매팅 → 그다음 마젠타 키 제거 → Aseprite 터치업.**

1. **알파 매팅 (BiRefNet 또는 Bria RMBG):** 마젠타 배경 위 캐릭터의 부드러운
   외곽(털·홀씨·반짝이)을 머리카락급 정밀도로 따낸다. 단순 임계값 크로마키만으로는
   파스텔 외곽 AA 프린지에서 할로가 생긴다(docs/RISKS.md feasibility 합성 테스트
   입증). `mongle-cleanup-matte.json` 워크플로에 BiRefNet 노드를 둔다.
2. **마젠타 키 제거:** 매팅 후 남은 마젠타 프린지를 `gen-characters-openrouter.mjs`
   `chromaKeyMagenta()` 의 r−g 점수 램프 로직으로 제거(분홍 볼터치는 r−g가 작아
   생존). 이 함수는 이미 검증됐으니 재사용한다.
3. **Aseprite 터치업:** 손/눈 아티팩트 수정, 식별 소품 또렷하게, 외곽선 두께
   통일, 팔레트를 더스티 파스텔로 정렬(`mute()` = 채도×0.6·명도−6% 방향, ASSETS.md
   §3 2026-06-18 항목과 일치). **이 수작업이 §6 권리 주장의 "인간 창작적 기여"
   기록 대상이다 — 무엇을 고쳤는지 남긴다.**
4. 최종 리사이즈 512×512, `pipeline/cut/{id}/seed-*.png` 저장.

> **네이티브 알파 경로(대안):** 모델이 진짜 투명 PNG를 내면(일부 SaaS/Gemini 경로)
> 1~2를 건너뛰고 바로 3으로 간다. 흰배경 flood-fill은 **어느 경로에서도 금지**.

---

## 6. Step 5 — 사람 검수 게이트 (커밋 전, 사람이 직접)

`docs/ASSETS.md` §"검수 체크리스트(이미지당)" 7항목을 그대로 적용하고, 추가로 가문
단위 게이트를 둔다. **하나라도 실패하면 폐기 후 [2]~[5] 재실행 — 통과분만 커밋.**

- [ ] **Family matrix 사이드바이사이드:** `pipeline/review/_family_matrix.png`(24종
      대조 시트, 현 `--sheet` 컨택트시트와 동일 역할)에서 24종이 **한 가문**으로
      읽히는가. 한 캐릭터만 채도·등신·선화가 튀면 재롤.
- [ ] **IP 유사성 대조:** 알려진 카와이 IP 대표 캐릭터들과 나란히 놓고 "동일
      캐릭터로 오인되는가" 확인. 실루엣·배색·무늬·종(種) 조합이 1:1로 겹치면 폐기.
      (흰 둥근 몸+세모 귀 콤보 등 금지 — docs/RISKS.md copyright.)
- [ ] **손/눈 아티팩트:** 손가락 개수·눈 비대칭·녹은 소품 등 생성 아티팩트 없음.
- [ ] **512×512 + 깨끗한 알파:** 네 모서리 알파=0, 마젠타 잔여·프린지 없음,
      캐릭터 중앙 배치 + 적절한 여백.
- [ ] **아트 바이블 준수**(docs/GAME_DESIGN.md §4): 점 눈 2 / 작은 입 / 볼터치 /
      2~2.5등신 / 더스티 파스텔 단색 몸 / 어두운 외곽선 / **식별 소품 정확히 1개**.
- [ ] **모티프 가독성:** 해당 캐릭터의 식별 소품이 읽히는가(양=구름 윤곽,
      금붕=와플 격자, 푸딩=카라멜 드립 …).
- [ ] **텍스트·워터마크·서명 없음.**
- [ ] **기록 완비:** 프롬프트·생성일·모델·seed·**사람 수정 내역**이 §7 기록 절차로
      `docs/ASSETS.md` 에 남는가(독자 창작 + 권리 주장 입증용).

---

## 7. Step 6 — 커밋 / 기록 + 기존 스캐폴드 연결

### 7.1 커밋 절차

1. 통과한 `pipeline/cut/{id}/seed-N.png` 를 `assets/characters/{id}.png` 로 교체.
2. Godot headless 임포트: `godot --headless --import` (1회, .import 메타 갱신).
3. 테스트 기준선: `godot --headless --script res://tests/test_runner.gd` 전부 통과.
4. `docs/ASSETS.md` 갱신:
   - §2 "향후 AI 아트 교체 절차"를 실행 기록으로 전환, §3 변경 이력에 한 줄 추가.
   - 교체 캐릭터 id·**생성 모델·생성일·seed·IP-Adapter weight·style LoRA sha256·
     사람 수정 내역**을 표로 기록.
5. `ASSETS-LICENSE` §2 "AI 생성 에셋 고지" 템플릿을 **활성화** — "대상 파일: (없음)"
   을 실제 교체 파일 목록으로 채운다. SVG 잔존분은 §1(CC-BY) 그대로 유지.

### 7.2 기존 `scripts/gen-characters-openrouter.mjs` 와의 관계

이 스캐폴드는 **이미 다음을 제공**하므로 파이프라인의 일부로 직접 재사용한다:

- **공통 `STYLE` 상수** (L44~53) — ComfyUI positive 프롬프트의 공통 블록 출처.
  외부 IP명 없는 일반 기술어 + 마젠타 배경 강제가 이미 검증돼 있다.
- **`CHARACTERS[]` 모티프·seed 표** (L56~69) — character sheet/생성의 `{desc}` 와
  per-character seed 출처. ⚠ **현재 12종까지만 정의됨** — 로스터는 24종이므로
  나머지 12종(dorong·gosum·gaegul·ddalbang·sikppang·mongsong·dalbo·beoseot·jogyak·
  haedal·gureum·byeolttong)의 `desc`/`seed`를 `docs/ASSETS.md §1` 표에서 채워 넣어야
  한다(이 확장이 §3 실행의 선행 작업).
- **`chromaKeyMagenta()`** (L94~114) — §5 단계2 마젠타 키 제거에 그대로 사용.
- **빌드타임 전용 가드 주석** (L1~26) — 런타임 호출 금지 원칙을 명문화. ComfyUI
  경로도 동일하게 빌드타임 전용.

**두 경로의 역할 분담:**

| 경로 | 용도 | 일관성 메커니즘 |
|---|---|---|
| ComfyUI + Flux (본 문서 §2~5) | 기본. GPU 보유 시 24종 가문 응집 | style LoRA + IP-Adapter + 시트 |
| `gen-characters-openrouter.mjs` (SaaS) | GPU 부재 시 폴백 / 빠른 단발 재생성 | 공통 `STYLE` 앵커 프롬프트 + 고정 seed |

SaaS 경로는 LoRA를 못 쓰므로 가문 응집이 약하다 → **family matrix 게이트(§6)에서
더 엄격히 본다.** 둘 중 무엇으로 만들었든 §5·§6 게이트와 §7.1 기록은 동일 적용.

---

## 8. Tools table

| 단계 | 도구 | 라이선스/주의 | 비고 |
|---|---|---|---|
| 워크플로 | **ComfyUI** | GPL-3.0 (툴) — 출력물엔 영향 없음 | workflow JSON을 `scripts/comfy/` 에 커밋 |
| 베이스 모델 | **Flux.1 schnell** | Apache-2.0 (상업 자유) | 상업 배포 시 **schnell 권장** |
| 〃 | Flux.1 dev | 비상업 — 상업 시 유료 라이선스 | dev로 만들면 상업 배포 전 라이선스 확인 |
| 스타일 학습 | LoRA 트레이너(kohya/ComfyUI 노드) | — | 입력은 **우리 레퍼런스만** |
| 정체성 | IP-Adapter | — | weight ≈ 0.55 |
| 알파 매팅 | **BiRefNet** 또는 **Bria RMBG** | 모델별 상이 — 상업 가부 확인 | 머리카락급 외곽 |
| 크로마 | `chromaKeyMagenta()` (sharp) | 프로젝트 자체 코드 | 매팅 후 잔여 마젠타 |
| 터치업 | **Aseprite** | 유료 1회 구매 | **인간 창작 기여 기록 대상** |
| SaaS 폴백 | Scenario.gg / Layer.ai | 구독 — 약관·권리귀속 확인 | GPU 부재 시 |
| 비용 | 로컬 GPU 상각 시 **~$1–5/char** / SaaS 구독별 상이 | — | 24종 1패스 기준 |

---

## 9. Legal & Steam checklist

- [ ] **권리 주장 근거 기록:** 각 캐릭터의 **인간 창작적 기여**(스케치/큐레이션/
      인페인트/팔레트 재정렬/배열)를 `docs/ASSETS.md` 에 남긴다. 순수 프롬프트
      출력은 미국(USCO 2025 Copyrightability Report / *Thaler v. Perlmutter*)·한국·
      일본 모두 저작권 부존재 → **사람 기여가 유일한 권리 근거.**
- [ ] **오염 회피 입증:** style LoRA는 **우리 자체 24 SVG + 무드보드로만** 학습.
      외부 IP 이미지를 학습/무드보드에 넣지 않았음을 기록(레퍼런스 출처 목록 유지).
- [ ] **프롬프트 청결:** 프롬프트·캡션·LoRA 트리거·커밋·문서 어디에도 외부
      IP명·작가명·캐릭터명 없음(grep 게이트 — `gen-placeholders.mjs` 금지어 셋 재사용).
- [ ] **라이선스 분리:** 코드 MIT, 아트는 `ASSETS-LICENSE`. AI 교체분은 §2 고지
      활성화(권리 불확실·퍼블릭 도메인 준함 명시), SVG 잔존분은 §1 CC-BY 유지.
- [ ] **Steam 고지 (2026 정책):** 사전 생성 AI 아트는 **Steamworks 콘텐츠 설문**의
      AI 사용 항목에서 **반드시 공시**한다(pre-generated 카테고리). 게임 내 런타임
      생성은 없으므로 "live-generated AI" 항목은 해당 없음.
- [ ] **모바일:** 별도 AI 공시 의무 없음(2026 기준) — 그래도 §2 고지는 동봉.
- [ ] **제3자 침해 미보증:** ASSETS-LICENSE §2 문구대로, 검수는 했으나 법적 보증은
      하지 않음을 명시.

---

## 10. 실행 전 선행 작업 요약 (현재 미완)

1. `scripts/comfy/` 워크플로 JSON 3종 작성(train / gen / cleanup-matte).
2. `gen-characters-openrouter.mjs` `CHARACTERS[]` 를 12 → 24종으로 확장
   (나머지 12종 `desc`/`seed`).
3. `pipeline/` 를 `.gitignore` 에 추가, `pipeline/refs/svg/` 에 현 24 SVG 렌더 복사.
4. style LoRA 학습용 무드보드 선별(외부 IP 캐릭터 제외).
5. GPU 가용성 확인 → 로컬(ComfyUI) vs SaaS 폴백 결정.

---

## 부록 A — Per-character 프롬프트 TEMPLATE (fill-in)

각 로스터 캐릭터의 **모티프 + 식별 소품 1개**를 채워 쓴다. `{공통_STYLE}` 은
`gen-characters-openrouter.mjs` 의 `STYLE` 상수(외부 IP명 없는 일반 기술어 + 마젠타
배경)를 그대로 인용한다.

```
Positive:
  {모티프 한 줄: 종/색}, {식별 소품 1개를 또렷이},
  mngl_style, {공통_STYLE},
  character fills 60-70% of canvas, accessory small and readable,
  dusty pastel muted palette, cozy, gentle slightly wistful expression,
  solid #FF00FF magenta background.

Negative:
  white background, gradient background, text, watermark, signature,
  extra limbs, deformed hands, six fingers, melted accessory,
  giant aura, encircling halo, copyrighted character,
  pink or magenta tones on the body itself.

IP-Adapter reference: pipeline/sheets/{id}/turnaround.png   (weight ≈ 0.55)
Seed: {CHARACTERS[id].seed 고정값}
```

### 워크된 예시 1 — `moka` (모카 = 새싹 두더지, common)

> 모티프/식별 소품: 머리 위 새싹 + 크림색 몸 + 큰 두더지 앞발 (docs/ASSETS.md §1).

```
Positive:
  a cream-colored mole with a tiny green sprout growing from the top of its head,
  big soft digging paws, light oval muzzle with a small pink nose,
  mngl_style, kawaii minimal mascot, round chibi body, two dot eyes, tiny mouth,
  pink blush, dusty pastel muted flat colors, thick clean dark outline,
  full body centered, two heads tall, short stubby limbs,
  character fills 60-70% of canvas, the green sprout small and readable,
  gentle slightly wistful expression, cozy,
  solid #FF00FF magenta background.

Negative:
  white background, gradient background, text, watermark, signature,
  extra limbs, deformed hands, six fingers, melted sprout,
  copyrighted character, pink or magenta tones on the body.

IP-Adapter reference: pipeline/sheets/moka/turnaround.png   (weight ≈ 0.55)
Seed: 101
```

### 워크된 예시 2 — `geumbung` (금붕 = 붕어빵, legendary)

> 모티프/식별 소품: 물고기형 빵 + 와플 격자 결 + 갈래 꼬리. legendary라 §1 예외로
> **금 그라데이션/미세 광택 허용**(에셋에 한정 — 희귀도 오버레이는 런타임 담당).

```
Positive:
  a golden fish-shaped pastry, plump fish silhouette bread with a crisp waffle
  grid texture, forked tail fin and a small rounded dorsal fin,
  subtle warm golden sheen highlight,
  mngl_style, kawaii minimal mascot, two dot eyes, tiny mouth, pink blush,
  dusty pastel muted palette with a soft golden gradient on the body,
  thick clean dark outline, full body centered, two heads tall,
  character fills 60-70% of canvas, waffle grid clearly readable,
  no giant aura, no encircling halo, cozy,
  solid #FF00FF magenta background.

Negative:
  white background, gradient background (on the canvas, not the body),
  text, watermark, signature, extra fins, deformed shape,
  giant aura, encircling halo, copyrighted character,
  magenta tones on the body.

IP-Adapter reference: pipeline/sheets/geumbung/turnaround.png   (weight ≈ 0.55)
Seed: 112
```

> 두 예시의 `desc`/`seed` 는 `gen-characters-openrouter.mjs` `CHARACTERS[]` 에 이미
> 존재한다(L57, L68). 나머지 22종도 같은 방식으로 §1 로스터 표를 채워 쓴다.
