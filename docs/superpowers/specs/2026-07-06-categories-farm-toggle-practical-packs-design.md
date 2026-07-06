# 설계 스펙 — 카테고리·검색 UI + 목장 온오프 + 실무 레퍼런스 팩(파일럿)

작성: 2026-07-06 · 상태: 설계 확정(사용자 승인 대기)

세 개의 독립적이지만 연관된 작업을 하나의 스펙으로 묶는다. 카테고리 taxonomy가
Part A(UI)와 Part C(신규 팩)에 공통이므로 함께 확정한다.

- **Part A** — 퀴즈 팩 목록에 카테고리 탭 + 검색 + 필터 (몽글목장 + studyandgame-godot 양쪽)
- **Part B** — 목장(농장) UI 온오프 토글, default OFF (몽글목장 전용)
- **Part C** — 실무 레퍼런스 신규 팩 파일럿: 분야당 1팩 (AI 엔지니어 · 데이터 엔지니어 · 백엔드 · logpresso-SQL · logpresso-설치)

대상 저장소: `joyuno/mongle-ranch`(study_game_v2), `joyuno/studyandgame-godot`(study_game_godot).

---

## 0. 카테고리 Taxonomy (Part A·C 공통)

`meta`에 **`category` 문자열 필드**를 신규 추가한다. `PackParser._validate_pack()`은
`title`만 검증하고 미지의 meta 키를 무시하므로 non-breaking (근거: pack_parser.gd:63-88).

확정 카테고리(사용자 결정 반영 — clickhouse 단독 유지):

| category 키 | 표시명 | 현재 팩 수 |
|---|---|---|
| `japanese` | 일본어 (JLPT N2) | 30 |
| `semiconductor` | 반도체 | 31 |
| `observability` | 관측성 (OTel·APM·RUM) | 6 |
| `clickhouse` | ClickHouse | 1 |
| `data-eng` | 데이터 엔지니어 | 0 (신규) |
| `ai-eng` | AI 엔지니어 | 0 (신규) |
| `backend` | 백엔드 | 0 (신규) |
| `logpresso` | Logpresso | 0 (신규, 로컬 전용) |

- **표시 순서**: 위 표 순서를 고정 배열로 관리(코드 상수). 미지의 category는 "기타"로.
- **마이그레이션**: 빌드타임 스크립트(node)가 기존 68개 `res://data/quizzes/*.json`의
  `meta.category`를 파일명/기존 `tags`로 자동 부여. 규칙:
  - `tags`에 `jlpt` → `japanese`
  - `tags`에 `semiconductor` 또는 파일명 `semiconductor-*|memory-*|physical-electronics-*|reliability-fa-*|semiconductor-*|spc-yield-*` → `semiconductor`
  - `tags`에 `observability`(apm/otel/rum) → `observability`
  - `tags`에 `clickhouse` → `clickhouse`
  - 결과를 사람이 diff 검토 후 커밋(자명한 매핑이므로 explanation 보강 때처럼 구조 무변 확인).
- **폴백**: `category` 없는 팩(유저 임포트 등)은 런타임에 기존 `_subject_icon()`
  키워드 버킷(quiz.gd:330-344)과 동일 로직으로 임시 분류. 즉 category 필드는
  authoritative, 없으면 degrade.

---

## Part A — 카테고리 + 검색 + 필터 UI

### A.1 목표 / 성공 기준
- 팩이 많아져도(수백 개) 스크롤 대신 카테고리 클릭으로 관련 팩만 본다.
- 제목/태그 부분일치 검색이 카테고리와 함께 동작한다.
- 몽글목장(quiz.gd 피커)과 studyandgame-godot(home.gd 피커) 양쪽에 적용.

### A.2 UI (칩 바 + 검색창)
피커 상단(리스트 위)에 필터 바 삽입:
```
🔍 [ 검색: 제목·태그…                    ]
[전체 N] [일본어 30] [반도체 31] [관측성 6] [ClickHouse 1] [데이터 …] [AI …] [백엔드 …] [Logpresso …]
```
- 칩은 가로 스크롤(HBox in ScrollContainer, 카테고리 많아도 대응).
- 각 칩에 해당 카테고리 팩 수 표시. "전체"가 default 활성.
- 칩 클릭 → 그 카테고리만. 검색어 입력 → 부분일치. 둘은 AND 결합.
- 빈 카테고리(팩 0개)는 칩을 숨긴다(신규 카테고리가 아직 팩 없을 때 노이즈 방지).

### A.3 몽글목장 구현 (scripts/ui/quiz.gd)
- 삽입 위치: `hint` 라벨(quiz.gd:161)과 `ScrollContainer`(quiz.gd:169) 사이에 필터 바.
- **파싱 캐시**: 현재 `_populate_pack_list()`(quiz.gd:185-212)는 리빌드마다 68파일을
  재파싱 → 검색 키입력마다 느림(Explore 지적). `_pack_cache: Array`(파싱된
  `{path, file, meta, count, is_user_pack}`)를 세션 진입 시 1회 구축하고, 필터는
  캐시에서 수행. 파일 목록 변화(유저 임포트) 시에만 캐시 무효화.
- 상태: `_active_category: String = ""`(빈=전체), `_search_query: String = ""` 멤버 변수.
- 순수 헬퍼 분리(격리·테스트 가능):
  `PackFilter.matches(meta: Dictionary, category: String, query: String) -> bool`
  (scripts/domain/ 신규, Node 참조 없음). 카테고리 일치 + (query 비었거나 title/tags에
  부분일치). 태그·제목 소문자 비교.
- `_make_chip_bar()` / `_apply_filter()` 추가. 필터 변경 시 `pack_list_box`만 재구성
  (캐시에서). `_make_pack_card()`는 그대로 재사용.

### A.4 studyandgame-godot 구현 (scripts/ui/home.gd)
- 동일 패턴. 피커 스캔 함수(home.gd:213-235, `.yml`이 `.json` 이김 규칙 유지)에
  category 필터 게이트 추가. `PackFilter` 헬퍼는 각 레포에 동일 사본(도메인 순수함수).
- `.yml`/`.json` 양쪽 meta에서 `category` 읽기(YAMLPackParser·PackParser 모두 미지 키 무시).

### A.5 데이터 마이그레이션
- 기존 팩에 `category` 부여: 몽글목장 `.json` 68개 + studyandgame-godot `.json`+`.yml`.
- 신규 Part C 팩은 처음부터 `category` 포함.

### A.6 테스트
- `PackFilter.matches` 단위 케이스를 각 게임 `tests/test_runner.gd`에 추가(카테고리
  일치/불일치, 빈 쿼리, 부분일치, 대소문자, category 없는 팩 폴백).
- 헤드리스: 전 팩 PackParser 통과 + category 필드 파싱 확인.

---

## Part B — 목장 온오프 토글 (몽글목장 전용, default OFF)

### B.1 목표
회사에서 쓰기 위해 유치한 목장 뷰를 끌 수 있게. **default OFF** — 신규/리셋 사용자는
차분한 화면을 본다. 켜면 기존 목장(펫·목초지) 복원.

### B.2 영속화 (scripts/autoload/progress_store.gd) — `quietMode` 패턴 미러
1. `signal farm_visible_changed(enabled: bool)` 추가 (progress_store.gd:20 근처).
2. getter `is_farm_visible() -> bool: return bool(progress.get("showFarm", false))` (:134 근처).
3. setter `set_farm_visible(enabled)`: `progress["showFarm"]=enabled; _persist(); farm_visible_changed.emit(enabled)` (Settings 리전 :621-643).
4. `_default_progress()`에 `"showFarm": false` (:773-798).
5. bool이라 `_sanitize()` 변경 불필요.

### B.3 설정 UI (scripts/ui/settings.gd)
- "퀴즈 환경" 섹션(:100-136)의 quiet-mode CheckButton(:132-136) 복제해 "목장 표시"
  CheckButton 추가. `set_pressed_no_signal(ProgressStore.is_farm_visible())` +
  `.toggled.connect(func(on): ProgressStore.set_farm_visible(on))`.

### B.4 목장 화면 (scripts/ui/ranch.gd) — OFF 상태 동작 (사용자 결정: "퀴즈 시작 하나")
- `_yard` Panel(:101-109, 목초지·펫·장식·파티클 전부)을 `is_farm_visible()` false면 숨김.
- **OFF 화면**: 단색 테마 배경(ThemeSetup 색) + 기존 HUD(코인/스트릭 chip 바) +
  가운데에 **큰 "퀴즈 시작" 버튼 하나** + 하단 내비(퀴즈/도감/설정) 유지.
  → 회사에서 바로 퀴즈 진입. 새 대시보드 구축 아님(YAGNI), 최소 CTA만.
- `_build_layout()`(:69-135)에서 `is_farm_visible()`로 `_yard` vs "퀴즈 시작" CTA 분기.
- `_ready()` deferred 블록(:58-63), `_on_collection_changed`(:478), `_apply_daylight`(:339)를
  `if is_farm_visible()`로 가드(off면 펫/장식/데이라이트 연산 스킵).
- `farm_visible_changed` 구독 → 리로드 없이 즉시 show/hide 전환.

### B.5 테스트
- 헤드리스: `showFarm` 기본 false, setter 후 persist·load 왕복, getter 클램프(garbage→false).
- 부팅: off/on 양쪽에서 ranch.gd 파싱·구성 에러 0.

---

## Part C — 실무 레퍼런스 팩 파일럿

### C.1 범위 (사용자 결정: 먼저 각 1팩 → 확장)
파일럿 5팩, 각 ~30문항. 이후 품질 게이트 통과 시 분야당 다수 팩으로 확장.

| 팩 | category | 공개 | 출처 |
|---|---|---|---|
| AI 엔지니어 (실무 기초) | `ai-eng` | public OK | 웹 리서치(exa/deep-research) |
| 데이터 엔지니어 (실무 기초) | `data-eng` | public OK | 웹 리서치 |
| 백엔드 (실무 기초) | `backend` | public OK | 웹 리서치 |
| Logpresso SQL | `logpresso` | **로컬 전용** | 공식 문서 리서치 |
| Logpresso 설치·운영 | `logpresso` | **로컬 전용** | 제공된 설치 PDF(새니타이즈) |

### C.2 난이도·형식 (사용자 결정: 실무 중급~고급 + 도움말·해설 카드 필수)
- 난이도: 실무 중급~고급, **실무 레퍼런스** 지향(현업 함정·베스트프랙티스 중심).
- **모든 문항 필수**: `glossary`(전문용어 도움말 카드, `용어｜읽기·원어｜뜻`) +
  `explanation`(정답 근거 + **각 오답이 왜 틀렸는지/무엇을 써야 하는지**, JLPT 보강과 동일 기준).
- 스키마: 기존 팩과 동일(`type: mcq|ox`, `q`, `choices`, `answer`, `glossary`,
  `explanation`, `tags`, `category`). 보기는 번호 대신 「」 인용(기존 규칙).
- meta: `title`, `version`, `default_time`, `tags`, `category`.

### C.3 팀 워크플로우 (분야별 병렬 — Workflow 툴, 사용자 허가)
분야당 파이프라인:
```
Researcher   → exa 검색 + 공식문서 fetch로 실무 레퍼런스 소스 수집
Synthesizer  → 핵심개념·함정·베스트프랙티스 개요(사실 출처 명시)
Author       → 30문항 mcq/ox + glossary + 오답서술 해설 작성(category 포함)
Verifier     → 사실성 적대검증(공식문서 대조) + PackParser 헤드리스 통과
```
- exa MCP 툴(`web_search_exa`, `web_fetch_exa`)을 워크플로우 에이전트가 ToolSearch로 사용.
- 정확도 최우선(실무 레퍼런스). Verifier가 근거 없는 주장 제거.

### C.4 Logpresso 기밀 처리 (사용자 결정: 로컬 전용 + 전부 새니타이즈)
- **로컬 전용**: logpresso 팩은 공개 저장소에 커밋 금지. **양쪽 게임**
  (몽글목장·studyandgame-godot)의 `data/quizzes/logpresso-*.json`로 배치하고 각 레포
  `.gitignore`에 `data/quizzes/logpresso-*.json` 등록 → 로컬 실행/로컬 exe(export 필터는
  gitignore와 무관하게 `*.json` 포함)에는 들어가지만 git push엔 절대 안 실림.
  (studyandgame-godot는 `.yml`이 `.json`을 가리므로 logpresso는 `.json`만 두면 표시됨 —
  `.yml` 미생성으로 중복 없음.)
- **전부 새니타이즈**(설치 팩): 제공 PDF에서 아래를 문제집에 **절대 포함하지 않는다**:
  - 고객사/프로젝트명(예: 특정 공사명), 작성자명, 회사명, ㊙️ 성격
  - 리터럴 비밀번호/자격증명(설치 절차의 "루트 PW 설정" 개념은 가르치되 실제 문자열 X)
  - 실제 내부 IP(필요 시 RFC1918 일반 예시로 대체)
- **유지(교육 가치)**: 분석/수집/전달 AS 3-tier 아키텍처, 포트 역할(7140 RPC / 7141 Node
  RPC)과 왜 7141도 열어야 하는지, VIP/Active/Standby HA 개념, MariaDB Galera Cluster
  구성 개념, SELinux/sysctl 튜닝, sonar/araqne 명령 흐름, SNR/ENT 계정명 규칙,
  사설 인증서 우회 개념 등 재사용 가능한 절차·원리.
- 원본 PDF는 이미 `.gitignore`(`*.pdf`)로 커밋 차단됨. 추출 텍스트는 세션 스크래치패드
  (레포 밖)에만 존재.

### C.5 품질 게이트 (확장 전)
- 5팩 완성 → PackParser 헤드리스 통과 + 제출자(나) 사실성·형식 스팟체크
- logpresso 설치 팩: 새니타이즈 누락(고객명/비번/IP/작성자) 0 자동 스캔
- 사용자 검수 OK → 그때 분야당 다수 팩으로 확장(별도 사이클)

---

## 순서 / 커밋 분리

1. **Part B** (목장 토글) — 작고 독립. 몽글목장 커밋 1개.
2. **Part A** (카테고리 UI) — (a) category 마이그레이션 커밋(각 게임), (b) 필터 UI 커밋(각 게임).
3. **Part C** (파일럿 팩) — public 3팩(ai/data/backend)은 커밋; logpresso 2팩은 로컬 전용
   (gitignore, 커밋 안 함). 별도 품질 게이트.
4. exe 재빌드(몽글목장 + studyandgame-godot)는 마지막. push는 사용자 승인 후.

각 게임 파리티 유지. 커밋마다 CLAUDE.md §5 트레일러.

## 비목표 (YAGNI)
- 반도체 서브카테고리(2단 taxonomy) — 필요해지면 별도.
- OFF 상태 전용 대시보드 — "퀴즈 시작" CTA만.
- logpresso 팩 공개/private repo 푸시 — 로컬 전용으로 확정.
- 파일럿 단계에서 분야당 다수 팩 — 게이트 통과 후.

## 검증 기준선
- 각 게임 `godot --headless --script tests/test_runner.gd` 전부 통과.
- 전 팩 PackParser 헤드리스 파싱 0 실패(신규 category 필드 포함).
- `PackFilter.matches` 단위 케이스 통과.
- logpresso 팩 새니타이즈 스캔(고객명/비번/IP/작성자) 0 매치.
- 부팅: 목장 on/off 양쪽 에러 0.
