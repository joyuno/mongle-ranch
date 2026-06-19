# 몽글목장 — Godot 4

학습 퀴즈 × 비전투 수집 가챠 × 관찰형 목장.
"퀴즈를 풀면 몽글몽글한 친구들이 목장에 찾아온다 — 공부가 곧 먹이이고, 친구들은 절대 떠나지 않는다."

[study_game_godot](../study_game_godot)의 퀴즈 시스템을 계승하고, [GitAnimals](https://github.com/devxb/gitanimals)의
"활동 → 펫 성장" 메커니즘에서 영감을 받아(에셋·코드 미사용, 메커니즘 독자 구현) 싱글플레이어로 번안했습니다.

## 게임 루프

1. **퀴즈 사다리** — 세션당 5문제, 상금 200 → 400 → 800 → 1,600 → 3,200코인 (정답마다 2배).
   정답 직후 "받고 멈추기" 가능, 오답이면 **그 세션 상금만** 0 (더블 오어 나씽).
2. 정답 1개 = 보유 캐릭터 중 **랜덤 1마리 레벨 +1** · 누적 정답 30개 = **무료 가챠 티켓 1장** — 사다리에 실패해도 이건 항상 지급.
3. **가챠** (1,000코인 / 티켓) — 12종 캐릭터, 천장 3단(10연 에픽 보장 / 40연 레전더리 하드천장 / 100연 스파크 지명).
4. 수집한 친구들이 **목장 화면을 랜덤하게 배회** — 성격별로 잠자고, 점프하고, 따라다니고, 구석을 좋아한다.
5. **NPC 시장** — 매일 시세(×0.85~1.15)가 바뀌고 주 1회 인기일(×1.3~1.6). 매물 구매·내 친구 판매(일 3마리).
6. **GitHub 간식 배달** (선택) — username만 입력하면 공개 커밋 1개 = 간식 1개(일 10개). 간식으로 친구에게 레벨 +1.
   토큰·로그인 없음. 실패해도 게임은 퀴즈만으로 완결.

**무처벌 원칙**: 미접속해도 친구가 굶거나 떠나지 않는다. 스트릭이 끊기면 2,000코인으로 복구.

## 빠른 시작

```powershell
$GODOT = "C:\Users\admin\Downloads\all_project\godot\Godot_v4.6.2-stable_win64.exe"
& $GODOT --path . # 실행
& $GODOT --headless --import                              # 자산 import
& $GODOT --headless --script res://tests/test_runner.gd   # 도메인 테스트
```

## 디렉토리 구조

```
study_game_v2/
├── project.godot              autoload: ProgressStore · PackStore · GithubSync · ThemeSetup
├── scenes/                    .tscn 골조 (Control + script attach만)
│   ├── Ranch.tscn             목장(메인) — 캐릭터 배회 + HUD + 네비
│   ├── CharacterSprite.tscn   캐릭터 1마리 컴포넌트 (상태머신·트윈·이모트)
│   ├── Quiz.tscn              팩 선택 + 사다리 세션
│   ├── Gacha.tscn             뽑기 + 천장/스파크 + 확률 공시
│   ├── Collection.tscn        도감 + 합성 + 목장 멤버 관리
│   ├── Market.tscn            NPC 시장 (일일 시세·인기일)
│   ├── WrongNote.tscn         오답노트 (SRS 복습)
│   └── Settings.tscn          GitHub username · 스트릭 복구 · 설정
├── scripts/
│   ├── autoload/
│   │   ├── progress_store.gd  지갑·컬렉션·천장·시장·스트릭 — user://progress.json atomic save
│   │   ├── pack_store.gd      퀴즈 사다리 세션 + 오답 SRS
│   │   ├── github_sync.gd     무인증 공개 API + ETag 캐시 + 백오프 (비차단)
│   │   └── theme_setup.gd     Pretendard 글로벌 Theme
│   ├── domain/                순수 함수 — 헤드리스 테스트 100%
│   │   ├── characters.gd      로스터 12종 (희귀도·weight·성격)
│   │   ├── gacha.gd           천분율 추첨 + 3단 천장 + 스파크
│   │   ├── market.gd          가격 공식 · 일일 랜덤워크 · 인기일
│   │   ├── ladder.gd          사다리 상금 · 티켓 마일스톤 · 일일 캡
│   │   ├── github_snacks.gd   이벤트 → 커밋 증분 → 간식 변환
│   │   └── srs.gd · leveling.gd · pack_parser.gd · yaml_pack_parser.gd  (계승)
│   ├── ui/                    코드-우선 화면 스크립트
│   ├── gen-placeholders.mjs   절차적 SVG → PNG 12종 (외부 API 없음)
│   └── gen-characters-openrouter.mjs  AI 아트 교체용 (빌드타임 전용, 실행 전 검수 필수)
├── assets/characters/         캐릭터 PNG 12종
├── data/quizzes/              JSON 퀴즈팩 (study_game_godot과 동일 포맷)
├── docs/
│   ├── GAME_DESIGN.md         확정 컨셉 (팀리더 종합)
│   ├── RESEARCH.md            자료조사 결과 (트렌드·GitAnimals·디자인·경제·기술)
│   ├── RISKS.md               보안·저작권·실현성 리스크 17건 + 완화책
│   └── ASSETS.md              에셋 생성 기록
└── tests/test_runner.gd       단일 파일 헤드리스 테스트
```

## 캐릭터 12종

| 희귀도 | 친구들 |
|---|---|
| 일반 (weight 0.7~1.0) | 모카(새싹 두더지) · 솜솜(구름 양) · 콩콩(완두콩) · 삐약(병아리) · 도토(다람쥐) |
| 레어 (0.2~0.3) | 푸딩 · 지지(지우개) · 몽당(연필) · 라떼(수달) |
| 에픽 (0.04~0.05) | 별가루(별사탕 요정) · 부엉(아기 부엉이) |
| 레전더리 (0.005) | 금붕(황금 붕어빵) |

## 퀴즈 팩 포맷

study_game_godot과 1:1 동일한 JSON 스키마 (`mcq` / `ox`, 선택 필드 `passage`/`time`/`explanation`).
[workbook 플러그인](https://github.com/joyuno/workbook)으로 자료를 변환해 `data/quizzes/`에 넣으면 자동 인식.

## 라이선스

- 코드: MIT ([LICENSE](LICENSE))
- 에셋: 별도 ([ASSETS-LICENSE](ASSETS-LICENSE)) — 생성 기록은 [docs/ASSETS.md](docs/ASSETS.md)
