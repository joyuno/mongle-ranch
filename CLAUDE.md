# CLAUDE.md — 몽글목장 (study_game_v2) 작업 규율

전역 `~/.claude/CLAUDE.md` 위에 덧붙이는 프로젝트별 지침. study_game_godot의 규율을 계승한다.

## 0. 세션 시작 시
1. 이 파일 + `MEMORY.md`를 읽는다.
2. 게임 규칙 변경 전 `docs/GAME_DESIGN.md`(확정 컨셉)와 `docs/RISKS.md`(금지 목록)를 확인한다.
3. 도메인 변경 시 `tests/test_runner.gd` 케이스도 같이 갱신한다.

## 1. 절대 금지 (docs/RISKS.md high 항목 — 변경하려면 사용자 승인 필수)
- 프롬프트·코드·주석·문서·커밋 어디에도 특정 카와이 IP의 캐릭터명·작가명, 타 IP 캐릭터명 금지.
- GitHub **토큰 입력 UI 금지** — username-only 무인증 공개 API만.
- **런타임 이미지 생성 API 호출 금지** — 생성은 scripts/*.mjs 빌드타임 전용, 결과는 사람 검수 후 커밋.
- **무처벌 원칙** — 미접속 시 캐릭터 굶김·이탈·퇴화 메커니즘 일체 금지.
- GitAnimals 에셋·펫 이름·UI 복제 금지 (메커니즘·수치만 독자 구현).
- 파스텔 스프라이트에 흰배경 flood-fill 금지 — 마젠타 크로마키 또는 네이티브 알파.

## 2. 언어·엔진 결정 (변경 금지)
- Godot 4.6.2 stable (GDScript). C# 도입 금지.
- JSON 퀴즈팩 (study_game_godot과 동일 스키마). RichTextLabel은 항상 `bbcode_enabled=false`.
- 상태 관리: autoload(ProgressStore·PackStore·GithubSync) + signal. 직접 노드 참조 결합 금지.
- UI: 코드-우선. .tscn은 3줄 골조만, 레이아웃은 스크립트 `_ready()`에서.

## 3. 디렉토리 컨벤션
- `scripts/domain/`: 순수 함수만. Node/Scene 참조 금지. RNG는 인자로 주입(테스트 시드 고정).
- `scripts/autoload/`: 글로벌 상태. 저장은 atomic write(tmp→rename) + 로드 시 값 클램프.
- `scripts/ui/`: .tscn에 attach. 캐릭터 연출은 Tween — 스프라이트시트 도입 금지(1캐릭터=1PNG).
- `assets/characters/{id}.png`: 512×512 투명배경. 추가 시 `docs/ASSETS.md` + `ASSETS-LICENSE` 갱신 의무.

## 4. 경제 수치 변경 시
- `docs/GAME_DESIGN.md` §2·§5의 수치 테이블이 단일 출처. 코드 상수와 어긋나면 문서를 따라 코드를 고친다.
- 가챠 확률·천장 변경 시 확률 공시 UI(gacha.gd)도 같이 갱신.
- 변경 전 tests/test_runner.gd 의 Gacha/Market/Ladder 케이스 갱신 → 헤드리스 통과 확인.

## 5. 테스트·빌드
- `godot --headless --script res://tests/test_runner.gd` — 전부 통과가 기준선. 떨어지면 푸시 금지.
- 자산 추가 후 `--headless --import` 1회.
