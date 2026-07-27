# Local Coding Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve the current quiz and creature game while adding one locally hosted, server-authoritative Python coding problem that Godot can load, submit to private Judge0, and reward exactly once after all hidden tests pass.

**Architecture:** Godot talks only to a versioned FastAPI game API. The API owns guest identity, problem metadata, submissions, wallet state, and reward idempotency in PostgreSQL; a replaceable `JudgeClient` is the only component that can reach Judge0. The first slice stays synchronous and local for observability, but its API, ownership, and ledger boundaries remain suitable for later hosted workers, account linking, rankings, and P2P trading.

**Tech Stack:** Godot 4.6.2 stable with GDScript; Python 3.12; FastAPI; Pydantic 2; SQLAlchemy 2; Alembic; psycopg 3; PostgreSQL 16; HTTPX; pytest; Docker Compose; Judge0 CE 1.13.1.

## Global Constraints

- Godot 4.6.2 stable, GDScript only. No C#.
- Existing objective quiz JSON schema, wrong-note flow, and SRS behavior remain compatible.
- Godot UI remains code-first; each new `.tscn` is only a root `Control` plus attached script.
- `RichTextLabel.bbcode_enabled = false` always; prefer `Label` for untrusted server text.
- State integration uses autoloads and signals; UI scenes do not call each other directly.
- `scripts/domain/` remains pure and has no Node or Scene references.
- No GitHub token input UI, no runtime image generation, and no punitive absence mechanics.
- No specific kawaii IP names, character names, author names, or copied third-party game assets.
- Judge0 binds only to the private Docker network. Godot never receives its address, credentials, reference solutions, or hidden tests.
- The local development guest endpoint is unavailable when `APP_ENV` is not `local` or `test`.
- Every wallet mutation has an immutable ledger row and an idempotency key.
- Only the first Accepted result for a user and problem version grants a reward.
- User source is limited to 32 KiB; stdout is limited by Judge0; execution uses CPU, wall-time, process, and memory limits.
- Pin external images and Python dependencies. Commit the generated dependency lock.
- The backend lives in the sibling Git repository `C:\Users\admin\Downloads\all_project\study_game_server`, outside Godot's `res://` root.
- Hidden tests and reference solutions exist only in the server repository or its private authoring source; they are never copied into `study_game_v2`.
- Do not read or delete the unknown local file `terasys@192.168.10.6`; ignore only that exact repository-root name.
- Each task is authored and reviewed in separate passes. Do not push or deploy without explicit user approval.

**Primary Godot test command:**

```powershell
C:\Users\admin\Downloads\all_project\godot\Godot_v4.6.2-stable_win64.exe --headless --path . --script res://tests/test_runner.gd
```

**Main-scene smoke command:**

```powershell
C:\Users\admin\Downloads\all_project\godot\Godot_v4.6.2-stable_win64.exe --headless --path . --quit-after 30
```

**Server test command:**

```powershell
docker compose -f ../study_game_server/compose.yml run --rm api pytest -q
```

---

## Scope Boundaries

This plan implements only the first vertical slice. Later plans cover:

1. Hosted authentication, cloud saves, and account linking.
2. Asynchronous judge workers, rankings, mastery adaptation, and the 36-48 problem pilot.
3. Server-authoritative gacha, fusion, breeding, NPC market migration, and P2P escrow trading.
4. Figma design system, alien research-vessel UI migration, and the reviewed 24-creature art roster.
5. Steam packaging, mobile layouts, store compliance, telemetry, and production operations.

The first slice is complete only when an actual Godot screen submits Python through the game API, Judge0 evaluates server-only tests, PostgreSQL records the result, and a duplicate Accepted submission does not grant a second reward.

---

## File Structure

### Existing Godot files

- Modify `scripts/ui/ranch.gd` — guard farm-disabled sprite sorting and add navigation to coding challenges.
- Modify `project.godot` — register `GameApi` autoload.
- Modify `tests/test_runner.gd` — add pure response-parser coverage.
- Modify `.gitignore` — ignore the exact unknown local filename and local server secrets.
- Create `scripts/domain/api_response.gd` — pure validation and normalization of API payloads.
- Create `scripts/autoload/game_api.gd` — HTTP boundary, guest token, problem list, submission signals.
- Create `scenes/CodingChallenge.tscn` — three-line scene skeleton.
- Create `scripts/ui/coding_challenge.gd` — problem, editor, run/submit, result, and reward UI.
- Create `tests/ranch_off_smoke.gd` — scene-level regression for the null-yard failure.
- Create `tests/quiz_regression.gd` — executable objective-quiz, wrong-note, review, ladder, and streak regression.
- Create `tests/game_api_contract.gd` — local fake-server contract runner.

### New game server

All paths in this section are in the separate sibling repository `../study_game_server`. Task 2 creates that repository on branch `codex/local-coding-vertical-slice`; server commits are made there, never through the Godot repository.

- Create `../study_game_server/pyproject.toml` and `../study_game_server/uv.lock` — pinned Python environment.
- Create `../study_game_server/Dockerfile` — non-root API image.
- Create `../study_game_server/app/config.py` — environment validation.
- Create `../study_game_server/app/db.py` — SQLAlchemy engine/session dependency.
- Create `../study_game_server/app/models.py` — first-slice database models and uniqueness constraints.
- Create `../study_game_server/app/schemas.py` — public request/response contracts.
- Create `../study_game_server/app/auth.py` — bearer-token hashing and current-user dependency.
- Create `../study_game_server/app/main.py` — app factory and router registration.
- Create `../study_game_server/app/routers/health.py` — liveness/readiness.
- Create `../study_game_server/app/routers/dev_sessions.py` — local-only guest bootstrap.
- Create `../study_game_server/app/routers/problems.py` — public problem catalog and detail.
- Create `../study_game_server/app/routers/submissions.py` — code submission endpoint.
- Create `../study_game_server/app/services/judge.py` — Judge0 protocol, HTTP adapter, and verdict normalization.
- Create `../study_game_server/app/services/submissions.py` — submission orchestration.
- Create `../study_game_server/app/services/rewards.py` — first-Accepted reward transaction.
- Create `../study_game_server/alembic.ini`, `../study_game_server/alembic/env.py`, and `../study_game_server/alembic/versions/0001_vertical_slice.py` — schema migration.
- Create `../study_game_server/data/demo_frequency_kits.json` — server-only demo statement, tests, limits, and reward.
- Create `../study_game_server/scripts/seed_demo.py` — idempotent demo problem import.
- Create `../study_game_server/tests/` — API, judge, submission, and reward tests.

### Local infrastructure and documentation

- Create `../study_game_server/compose.yml` — app DB, API, Judge0 DB, Redis, Judge0 server, and worker.
- Create `../study_game_server/judge0.conf.example` — non-secret Judge0 settings.
- Create `../study_game_server/.env.example` — documented local variables without credentials.
- Create `docs/LOCAL_CODING_SETUP.md` — setup, health checks, test commands, and recovery.
- Modify `README.md` — link the local coding setup without advertising unfinished online features.

---

### Task 1: Stabilize Farm-Off Boot and Repository Hygiene

**Files:**
- Modify: `.gitignore`
- Modify: `scripts/ui/ranch.gd:585`
- Create: `tests/ranch_off_smoke.gd`

**Interfaces:**
- Consumes: `ProgressStore.is_farm_visible() -> bool`
- Produces: `_sort_sprites() -> void` that is safe when `_yard == null`

- [ ] **Step 1: Add an exact local-file ignore**

Append these entries:

```gitignore
# Exact local artifact; contents are intentionally not inspected.
/terasys@192.168.10.6
```

- [ ] **Step 2: Write the scene regression**

Create `tests/ranch_off_smoke.gd`:

```gdscript
extends SceneTree

func _initialize() -> void:
	var original := ProgressStore.is_farm_visible()
	ProgressStore.set_farm_visible(false)
	var scene := load("res://scenes/Ranch.tscn").instantiate()
	root.add_child(scene)
	for frame in 20:
		await process_frame
	assert(scene != null)
	scene.queue_free()
	ProgressStore.set_farm_visible(original)
	await process_frame
	quit(0)
```

- [ ] **Step 3: Run the regression and capture the current failure**

Run:

```powershell
C:\Users\admin\Downloads\all_project\godot\Godot_v4.6.2-stable_win64.exe --headless --path . --script res://tests/ranch_off_smoke.gd
```

Expected before the fix: non-zero exit or an error containing `Invalid access to property or key 'size' on a base object of type 'Nil'`.

- [ ] **Step 4: Add the minimal null guard**

Change the beginning of `_sort_sprites()`:

```gdscript
func _sort_sprites() -> void:
	if _yard == null:
		return
	var yh := maxf(_yard.size.y, 1.0)
```

- [ ] **Step 5: Run focused and baseline tests**

Run the ranch smoke command, the primary Godot test command, and the main-scene smoke command. Expected: all exit `0`; primary tests report `129 passed, 0 failed`; main scene has no null-yard error.

- [ ] **Step 6: Add an executable learning-path regression**

Create `tests/quiz_regression.gd`. Snapshot `ProgressStore.progress.duplicate(true)` before the test and restore `ProgressStore.progress`, call `_persist()`, and delete the temporary pack before every exit. Write this two-question pack to `user://quiz_regression.json`, then enter through `PackStore.load_pack_from_path(ProjectSettings.globalize_path("user://quiz_regression.json"))`:

```gdscript
var pack := {
	"meta": {"title": "Regression", "version": "1", "default_time": 30},
	"questions": [
		{"type": "mcq", "q": "2+2", "choices": ["4", "5"], "answer_index": 0, "explanation": ""},
		{"type": "mcq", "q": "3+3", "choices": ["5", "6"], "answer_index": 1, "explanation": ""},
	],
}
```

Exercise these behaviors through public `PackStore` entry points:

```text
correct answer -> correct_count increments and ladder advances
wrong answer -> wrong-note count increments and ladder resets
review session -> load_review_session returns true and uses SRS without changing quiz streak
coding API remains unused -> no GameApi signal is required for objective-quiz actions
```

Run:

```powershell
C:\Users\admin\Downloads\all_project\godot\Godot_v4.6.2-stable_win64.exe --headless --path . --script res://tests/quiz_regression.gd
```

- [ ] **Step 7: Confirm the existing learning files remain untouched**

Run:

```powershell
git diff --exit-code -- scripts/autoload/pack_store.gd scripts/domain/srs.gd scripts/ui/quiz.gd scripts/ui/wrong_note.gd
```

Expected: no diff. Coding Accepted must not call `PackStore.submit_answer()`, add an objective-quiz wrong-note entry, modify SRS review levels, advance the quiz ladder, or touch the quiz streak.

- [ ] **Step 8: Commit**

```powershell
git add .gitignore scripts/ui/ranch.gd tests/ranch_off_smoke.gd tests/quiz_regression.gd
git commit -m "fix: keep farm-off main scene stable" -m "Constraint: farm is default-off`nConfidence: high`nScope-risk: narrow"
```

---

### Task 2: Create the Minimal FastAPI Service and Health Contract

**Files:**
- Create: `../study_game_server/pyproject.toml`
- Create: `../study_game_server/uv.lock`
- Create: `../study_game_server/Dockerfile`
- Create: `../study_game_server/app/__init__.py`
- Create: `../study_game_server/app/config.py`
- Create: `../study_game_server/app/main.py`
- Create: `../study_game_server/app/routers/__init__.py`
- Create: `../study_game_server/app/routers/health.py`
- Create: `../study_game_server/tests/test_health.py`

**Interfaces:**
- Produces: `create_app() -> FastAPI`
- Produces: `GET /health/live -> {"status":"ok"}`
- Produces: `GET /health/ready -> {"status":"ready"}` after DB readiness is added in Task 3

- [ ] **Step 1: Create the separate server repository**

Run from `study_game_v2`:

```powershell
New-Item -ItemType Directory -Path ..\study_game_server
git -C ..\study_game_server init -b main
git -C ..\study_game_server switch -c codex/local-coding-vertical-slice
```

Add a server-root `.gitignore` containing `.env.local`, `judge0.conf`, `.venv/`, `__pycache__/`, `.pytest_cache/`, and coverage artifacts. Do not configure a remote or push in this phase.

- [ ] **Step 2: Define the Python project**

Use Python `>=3.12,<3.14` and these dependency ranges:

```toml
[project]
name = "alien-research-game-api"
version = "0.1.0"
requires-python = ">=3.12,<3.14"
dependencies = [
  "alembic>=1.14,<2",
  "fastapi>=0.115,<1",
  "httpx>=0.28,<1",
  "psycopg[binary]>=3.2,<4",
  "pydantic-settings>=2.7,<3",
  "sqlalchemy>=2.0,<3",
  "uvicorn[standard]>=0.34,<1",
]

[dependency-groups]
dev = [
  "pytest>=8.3,<9",
  "pytest-cov>=6,<7",
]

[tool.pytest.ini_options]
testpaths = ["tests"]
```

Generate and commit `uv.lock` with `uv lock`.

- [ ] **Step 3: Write the failing health test**

```python
from fastapi.testclient import TestClient

from app.main import create_app


def test_liveness() -> None:
    with TestClient(create_app()) as client:
        response = client.get("/health/live")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
```

- [ ] **Step 4: Run the focused test**

Run `cd ..\study_game_server; uv run pytest tests/test_health.py -q`.

Expected: FAIL because `app.main` does not exist.

- [ ] **Step 5: Implement settings, router, and app factory**

`Settings` must include:

```python
class Settings(BaseSettings):
    app_env: Literal["local", "test", "production"] = "local"
    database_url: str = "postgresql+psycopg://game:game@localhost:5433/game"
    judge0_url: str = "http://judge0-server:2358"
    judge0_python_language_id: int = 71
    source_code_max_bytes: int = 32768
    rate_limit_hmac_key: SecretStr
```

`rate_limit_hmac_key` has no default. Tests inject a fixed value; local Compose reads it from ignored `.env.local`; production startup fails when it is missing.

`create_app()` registers a router whose liveness handler returns exactly `{"status": "ok"}`.

- [ ] **Step 6: Build the non-root container**

The image must install from `uv.lock`, run as a non-root user, expose `8000`, and execute:

```dockerfile
CMD ["uv", "run", "uvicorn", "app.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000"]
```

- [ ] **Step 7: Verify and commit**

Run `uv run pytest tests/test_health.py -q` and `docker build -t alien-game-api:test ..\study_game_server`.

```powershell
git -C ..\study_game_server add .
git -C ..\study_game_server commit -m "feat(server): add versioned game API skeleton" -m "Constraint: Python 3.12 and non-root container`nConfidence: high`nScope-risk: narrow"
```

---

### Task 3: Add PostgreSQL Identity, Wallet, and Problem Schema

**Files:**
- Create: `../study_game_server/app/db.py`
- Create: `../study_game_server/app/models.py`
- Create: `../study_game_server/alembic.ini`
- Create: `../study_game_server/alembic/env.py`
- Create: `../study_game_server/alembic/versions/0001_vertical_slice.py`
- Create: `../study_game_server/tests/test_schema.py`
- Modify: `../study_game_server/app/routers/health.py`

**Interfaces:**
- Produces: `get_db() -> Iterator[Session]`
- Produces tables: `users`, `auth_identities`, `auth_sessions`, `wallets`, `wallet_ledger`, `creature_instances`, `coding_problems`, `coding_problem_versions`, `coding_test_cases`, `coding_submissions`, `submission_rate_events`, `reward_claims`

- [ ] **Step 1: Write migration assertions**

The test connects to the test PostgreSQL database after `alembic upgrade head` and asserts all twelve table names exist. It also inserts duplicate values to prove these constraints:

```text
auth_sessions.token_hash UNIQUE
auth_identities(provider, provider_subject) UNIQUE
coding_problems.slug UNIQUE
coding_problem_versions(problem_id, version) UNIQUE
coding_submissions(user_id, idempotency_key) UNIQUE
reward_claims(user_id, problem_version_id, reward_type) UNIQUE
wallet_ledger(user_id, idempotency_key) UNIQUE
```

- [ ] **Step 2: Run the schema test**

Expected: FAIL because no engine, models, or migration exists.

- [ ] **Step 3: Implement UUID-keyed models**

Use server-generated UUID primary keys and UTC timestamps. `auth_identities` maps a provider and provider subject to an internal user UUID. `creature_instances` reserves UUID ownership with `owner_user_id`, `species_id`, and `state`, but no creature reward behavior is added in this phase. Store bearer tokens only as SHA-256 hashes. Store test visibility as `is_hidden`; never return `coding_test_cases` through public schemas.

Required submission fields:

```text
id, user_id, problem_version_id, language, source_code_sha256,
status, judge_status, passed_count, total_count, runtime_ms,
memory_kb, created_at, started_at, lease_token, lease_expires_at,
completed_at, idempotency_key
```

`submission_rate_events` stores `user_id`, an HMAC-SHA256 `ip_hash`, and `created_at`. It never stores a raw IP address.

- [ ] **Step 4: Implement the initial Alembic migration**

Create all tables, foreign keys, checks for non-negative wallet balances, and the uniqueness constraints above. The migration downgrade drops tables in reverse dependency order.

- [ ] **Step 5: Make readiness query PostgreSQL**

`GET /health/ready` executes `SELECT 1`. Return `200 {"status":"ready"}` on success and `503 {"status":"unavailable"}` on failure without including credentials or driver exceptions.

- [ ] **Step 6: Run migration and tests**

Run:

```powershell
cd ..\study_game_server
uv run alembic upgrade head
uv run pytest tests/test_schema.py tests/test_health.py -q
```

- [ ] **Step 7: Commit**

```powershell
git -C ..\study_game_server add .
git -C ..\study_game_server commit -m "feat(server): add authoritative coding data model" -m "Constraint: ledger and reward uniqueness are database-enforced`nConfidence: high`nScope-risk: moderate"
```

---

### Task 4: Add Local-Only Guest Bootstrap

**Files:**
- Create: `../study_game_server/app/auth.py`
- Create: `../study_game_server/app/schemas.py`
- Create: `../study_game_server/app/routers/dev_sessions.py`
- Create: `../study_game_server/tests/test_dev_sessions.py`
- Modify: `../study_game_server/app/main.py`

**Interfaces:**
- Produces: `POST /v1/dev/sessions`
- Produces: `get_current_user(Authorization: Bearer <token>) -> User`
- Request: `{"device_id": "64-character-or-shorter opaque string"}`
- Response: `{"access_token": str, "token_type": "bearer", "user": {"id": UUID, "display_name": str}}`

- [ ] **Step 1: Write three failing tests**

```python
def test_local_guest_session_returns_token_and_user(client):
    response = client.post("/v1/dev/sessions", json={"device_id": "device-a"})
    assert response.status_code == 201
    assert response.json()["token_type"] == "bearer"
    assert response.json()["access_token"]


def test_same_device_reuses_guest_user_but_rotates_token(client):
    first = client.post("/v1/dev/sessions", json={"device_id": "device-a"}).json()
    second = client.post("/v1/dev/sessions", json={"device_id": "device-a"}).json()
    assert first["user"]["id"] == second["user"]["id"]
    assert first["access_token"] != second["access_token"]


def test_production_disables_dev_session(production_client):
    response = production_client.post("/v1/dev/sessions", json={"device_id": "device-a"})
    assert response.status_code == 404
```

The production case must return `404`, not a descriptive security response.

- [ ] **Step 2: Run tests and confirm route absence**

Run `uv run pytest tests/test_dev_sessions.py -q`. Expected: three failures.

- [ ] **Step 3: Implement guest bootstrap**

Validate `device_id` length `1..64`. In `local` and `test`, find or create an `auth_identities` row using provider `dev_device` and the device ID as `provider_subject`; create a wallet at zero balance; generate a 32-byte random bearer token; store only its SHA-256 hash in `auth_sessions`.

- [ ] **Step 4: Implement bearer authentication**

Missing, malformed, expired, or unknown tokens return the same `401` body:

```json
{"detail":"invalid_session"}
```

- [ ] **Step 5: Run tests and commit**

```powershell
cd ..\study_game_server
uv run pytest tests/test_dev_sessions.py tests/test_schema.py -q
git -C ..\study_game_server add .
git -C ..\study_game_server commit -m "feat(server): add local guest sessions" -m "Constraint: endpoint is absent outside local and test`nConfidence: high`nScope-risk: moderate"
```

---

### Task 5: Seed One Server-Only Python Problem

**Files:**
- Create: `../study_game_server/data/demo_frequency_kits.json`
- Create: `../study_game_server/scripts/seed_demo.py`
- Create: `../study_game_server/app/routers/problems.py`
- Create: `../study_game_server/tests/test_problems.py`
- Modify: `../study_game_server/app/main.py`

**Interfaces:**
- Produces: `GET /v1/problems`
- Produces: `GET /v1/problems/frequency-kits`
- Public detail excludes reference solution, expected outputs beyond public examples, and hidden tests.

- [ ] **Step 1: Write public-contract tests**

Assert the authenticated list and detail responses include:

```json
{
  "slug": "frequency-kits",
  "title": "문자 키트 만들기",
  "stage": "practice",
  "concepts": ["hash-map", "counting", "integer-division"],
  "language": "python",
  "statement": "target의 문자 묶음을 text의 문자로 최대 몇 개 만들 수 있는지 계산하세요.",
  "input_format": "첫 줄에 target, 둘째 줄에 text가 주어집니다.",
  "output_format": "만들 수 있는 최대 묶음 수를 정수로 출력합니다.",
  "examples": [{"input": "abc\nabccda\n", "output": "1\n"}],
  "starter_code": "target = input().strip()\ntext = input().strip()\n"
}
```

Also recursively assert that keys `hidden_tests`, `expected_output`, and `reference_solution` do not occur in either response.

- [ ] **Step 2: Run and confirm route failures**

Run `uv run pytest tests/test_problems.py -q`. Expected: `404`.

- [ ] **Step 3: Author the demo problem**

The problem contract is:

```text
Input line 1: target, a non-empty lowercase ASCII string.
Input line 2: text, a lowercase ASCII string.
Output: the maximum number of target multisets constructible from text.
Order does not matter and each available character can be consumed once.
```

Include two public examples and four server-only cases covering: a missing required character, repeated characters in `target`, a single bottleneck character, and multiple complete kits with leftovers. Exact hidden inputs, expected outputs, and the reference implementation are authored and committed only in `study_game_server`; they must not be copied into this plan or the Godot repository.

Reward: `coins = 300`. Limits: CPU `2.0s`, wall time `5.0s`, memory `128000KB`, maximum processes `30`.

- [ ] **Step 4: Implement idempotent seeding**

`seed_demo.py` upserts by `(slug, version)` and replaces that version's test cases in one transaction. Running it twice leaves one problem version, two public rows, and four hidden rows.

- [ ] **Step 5: Implement authenticated public routes**

Return only active problem versions. Use explicit Pydantic response models so adding a model column cannot accidentally expose it.

- [ ] **Step 6: Verify and commit**

Run the seed twice, then `uv run pytest tests/test_problems.py -q`.

```powershell
git -C ..\study_game_server add .
git -C ..\study_game_server commit -m "feat(content): add first Python coding problem" -m "Constraint: hidden tests remain server-only`nConfidence: high`nScope-risk: narrow"
```

---

### Task 6: Implement the Judge0 Adapter and Security Limits

**Files:**
- Create: `../study_game_server/app/services/judge.py`
- Create: `../study_game_server/tests/test_judge.py`

**Interfaces:**
- Produces:

```python
class JudgeCase(TypedDict):
    stdin: str
    expected_output: str

class JudgeLimits(TypedDict):
    cpu_time_limit: float
    wall_time_limit: float
    memory_limit_kb: int
    max_processes: int
    max_output_kb: int

class JudgeResult(TypedDict):
    verdict: Literal["accepted", "wrong_answer", "compile_error", "runtime_error",
                     "time_limit", "memory_limit", "output_limit", "internal_error"]
    passed_count: int
    total_count: int
    runtime_ms: int
    memory_kb: int

class JudgeClient(Protocol):
    def judge(self, source_code: str, cases: list[JudgeCase], limits: JudgeLimits) -> JudgeResult:
        raise NotImplementedError
```

- [ ] **Step 1: Write fake-HTTP adapter tests**

Cover:

1. POST creates a submission token.
2. GET polling treats status IDs `1` and `2` as non-terminal.
3. Accepted cases increment `passed_count`.
4. First non-Accepted case stops evaluation.
5. Poll deadline returns `internal_error`.
6. Source and stdin are base64 encoded.
7. Configured CPU, wall, memory, process, and output limits are forwarded.

- [ ] **Step 2: Run and confirm import failure**

Run `uv run pytest tests/test_judge.py -q`.

- [ ] **Step 3: Implement `Judge0Client`**

For each test:

```text
POST /submissions?base64_encoded=true
GET  /submissions/{token}?base64_encoded=true&fields=status,time,memory,stdout,stderr,compile_output,message
```

Use connect timeout `2s`, read timeout `6s`, overall polling deadline `10s`, and capped exponential polling intervals from `100ms` to `800ms`. Never log source code, stdin, expected output, bearer tokens, or Judge0 configuration secrets.

- [ ] **Step 4: Normalize terminal statuses**

Map Judge0 status IDs:

```text
3 -> accepted
4 -> wrong_answer
5 -> time_limit
6 -> compile_error
8 -> output_limit (SIGXFSZ)
7, 9..12 -> memory_limit when reported memory >= memory_limit_kb, otherwise runtime_error
13 -> internal_error
14 -> internal_error
```

Send `max_file_size = max_output_kb` to Judge0 to bound stdout/stderr files. Use Judge0-reported memory and time only for verdict normalization and display; never use client-supplied metrics for rewards. Add adapter fixtures for status `8`, a status `7` response at the memory ceiling, and a status `7` response below the ceiling.

- [ ] **Step 5: Verify configured Python language**

Add a startup diagnostic command to documentation:

```powershell
docker compose -f ..\study_game_server\compose.yml exec api python -c "import httpx; print(httpx.get('http://judge0-server:2358/languages/71').json())"
```

The expected local result identifies a Python language. If image `1.13.1` does not expose ID `71`, change only `JUDGE0_PYTHON_LANGUAGE_ID` after querying `/languages`; do not hardcode a second ID.

- [ ] **Step 6: Run tests and commit**

```powershell
git -C ..\study_game_server add .
git -C ..\study_game_server commit -m "feat(server): isolate Judge0 behind a bounded adapter" -m "Constraint: Judge0 is private and all execution limits are server-owned`nConfidence: high`nScope-risk: moderate"
```

---

### Task 7: Orchestrate Submissions Without Duplicate Execution

**Files:**
- Create: `../study_game_server/app/services/submissions.py`
- Create: `../study_game_server/app/routers/submissions.py`
- Create: `../study_game_server/tests/test_submissions.py`
- Modify: `../study_game_server/app/schemas.py`
- Modify: `../study_game_server/app/main.py`

**Interfaces:**
- Produces: `POST /v1/runs`
- Produces: `POST /v1/submissions`
- Submission states: `running`, `retryable`, `completed`
- Request:

```json
{
  "problem_slug": "frequency-kits",
  "language": "python",
  "source_code": "print(1)",
  "idempotency_key": "client-generated-uuid"
}
```

- Response:

```json
{
  "submission_id": "uuid",
  "verdict": "accepted",
  "passed_count": 6,
  "total_count": 6,
  "runtime_ms": 40,
  "memory_kb": 3200,
  "reward": {"granted": true, "coins": 300},
  "wallet": {"coins": 300}
}
```

- [ ] **Step 1: Write service tests with a fake judge**

Test public-run Accepted, final-submit Accepted, Wrong Answer, Compile Error, source over 32 KiB, NUL byte rejection, unsupported language, inactive problem, Judge0 internal error, expired running lease, per-user rate limit, per-IP rate limit, and repeated request with the same idempotency key.

`POST /v1/runs` executes only the problem version's public cases, never creates a reward claim or ledger entry, and returns the same verdict shape without `reward` or `wallet`.

The repeated request behavior must be state-sensitive:

```text
completed -> return stored result without judging again
running with unexpired lease -> return HTTP 202 with the same submission_id
running with expired lease -> atomically acquire a new lease and judge again
retryable -> atomically claim the same row and call the judge again
```

- [ ] **Step 2: Run and confirm failures**

Run `uv run pytest tests/test_submissions.py -q`.

- [ ] **Step 3: Implement validation and orchestration**

Algorithm:

```text
authenticate user
validate language == python, no NUL byte, and UTF-8 source <= 32768 bytes
enforce 10 new submissions/minute/user and 30/minute/IP
load active problem version and ordered test cases
load existing user/idempotency result if present
return completed result, return 202 for a live lease, or claim retryable/expired row
insert running submission with a random lease_token and computed lease when no row exists
call JudgeClient with server-owned cases and limits
persist a non-Accepted terminal result
for Accepted, finalize submission and grant reward in one database transaction
return stored submission, reward, and wallet projection
```

If Judge0 is unavailable, persist state `retryable` with verdict `internal_error`, grant nothing, and return HTTP `503` with `submission_id`. A retry uses the same idempotency key and the same submission row.

Compute lease seconds as `max(30, len(selected_cases) * 10 + 15)`, where `10` is the adapter's per-case polling deadline. Every claim receives a new random `lease_token`. Finalization updates only a row matching both `submission_id` and the worker's `lease_token`; a stale worker that lost its lease cannot finalize or reward.

- [ ] **Step 4: Prevent concurrent duplicate work**

Catch the unique-constraint race on `(user_id, idempotency_key)`, roll back, and load the winning submission. Use a row lock or conditional update so only one request can move `retryable` to `running`; all other concurrent requests return HTTP `202`.

- [ ] **Step 5: Enforce bounded submission rates**

Before creating a new final-submission idempotency row, insert a `submission_rate_events` row and count the preceding 60 seconds in the same transaction. Final submissions allow 10/minute/user and 30/minute/IP. Public runs use the same table and independently allow 20/minute/user and 60/minute/IP. Reject over-limit requests with HTTP `429`, error code `submission_rate_limited`, and integer `Retry-After`. Replays of an existing final-submission idempotency key bypass the limiter so network retries can retrieve or resume their existing submission. Hash the client IP with an environment-provided HMAC key before storage. Tests exhaust each of the four limits and assert that the next Judge0 call is not made.

- [ ] **Step 6: Recover abandoned work**

At API startup and before each submission claim, change `running` rows with `lease_expires_at < now()` to `retryable`. Add a test that commits a running row with an expired lease, creates a fresh app instance, retries with the same key, and observes exactly one new judge call.

- [ ] **Step 7: Run tests and commit**

```powershell
git -C ..\study_game_server add .
git -C ..\study_game_server commit -m "feat(server): orchestrate idempotent code submissions" -m "Constraint: duplicate network requests cannot duplicate execution`nConfidence: high`nScope-risk: moderate"
```

---

### Task 8: Grant the First Accepted Reward Atomically

**Files:**
- Create: `../study_game_server/app/services/rewards.py`
- Create: `../study_game_server/tests/test_rewards.py`
- Modify: `../study_game_server/app/services/submissions.py`

**Interfaces:**
- Produces:

```python
def grant_first_accept_reward(
    db: Session,
    *,
    user_id: UUID,
    problem_version_id: UUID,
    submission_id: UUID,
    coins: int,
) -> RewardOutcome:
    raise NotImplementedError
```

`RewardOutcome` contains `granted: bool`, `coins: int`, and `wallet_balance: int`.
The caller owns the transaction; this function flushes changes but does not commit independently.

- [ ] **Step 1: Write transaction tests**

Cover:

1. First Accepted finalizes the submission, creates one claim, creates one ledger row, and increments wallet by 300 in one commit.
2. Second Accepted for the same version returns `granted=false` and leaves balance unchanged.
3. Two concurrent transactions yield one winner and final balance 300.
4. An exception before commit leaves the submission non-completed and leaves claim, ledger, and wallet unchanged.
5. Wrong Answer never calls the reward service.

- [ ] **Step 2: Run and confirm failures**

Run `uv run pytest tests/test_rewards.py -q`.

- [ ] **Step 3: Implement one PostgreSQL transaction**

Use the unique reward-claim constraint as the final authority. The ledger idempotency key is:

```text
coding:first_accept:{user_id}:{problem_version_id}
```

The submission service opens one transaction, locks the submission and wallet rows, calls `grant_first_accept_reward()`, marks the submission `completed/accepted`, then commits all changes together. Use SQLAlchemy's `select(Wallet).where(Wallet.user_id == user_id).with_for_update()` for the wallet. Insert the claim with `insert(RewardClaim).values(user_id=user_id, problem_version_id=problem_version_id, reward_type="coding_first_accept").on_conflict_do_nothing().returning(RewardClaim.id)`; an empty return means `granted=false`, avoids aborting the outer transaction, and still permits the later Accepted submission to finalize atomically.

- [ ] **Step 4: Run all server tests**

Run `uv run pytest -q`. Expected: all pass.

- [ ] **Step 5: Commit**

```powershell
git -C ..\study_game_server add .
git -C ..\study_game_server commit -m "feat(economy): reward first accepted exactly once" -m "Constraint: PostgreSQL uniqueness is the final authority`nConfidence: high`nScope-risk: broad"
```

---

### Task 9: Assemble the Private Local Docker Topology

**Files:**
- Create: `../study_game_server/compose.yml`
- Create: `../study_game_server/judge0.conf.example`
- Create: `../study_game_server/.env.example`
- Create: `docs/LOCAL_CODING_SETUP.md`

**Interfaces:**
- Exposes to host: Game API `127.0.0.1:8000`
- Does not expose to host by default: app PostgreSQL, Judge0 server, Judge0 PostgreSQL, Redis, worker
- The API reaches Judge0 at `http://judge0-server:2358`

- [ ] **Step 1: Define two isolated networks**

`game-net` contains API and app DB. `judge-net` contains API, Judge0 server, worker, Judge0 DB, and Redis. Only API joins both.

- [ ] **Step 2: Pin service images**

Use:

```text
postgres:16-alpine
redis:7-alpine
judge0/judge0:1.13.1
```

Before merging, record immutable digests returned by:

```powershell
docker image inspect --format='{{index .RepoDigests 0}}' postgres:16-alpine
docker image inspect --format='{{index .RepoDigests 0}}' redis:7-alpine
docker image inspect --format='{{index .RepoDigests 0}}' judge0/judge0:1.13.1
```

Replace each tag-only image reference in `compose.yml` with the exact repository digest printed by the corresponding inspection command in the implementation commit.

- [ ] **Step 3: Configure health and startup order**

App DB, Judge0 DB, and Redis need health checks. Migration and seed one-shot services complete before API becomes ready. Judge0 worker and server use the official 1.13.1 configuration keys copied from the release archive; store real local secrets only in ignored `../study_game_server/judge0.conf`.

- [ ] **Step 4: Add security settings**

Judge0 execution has networking disabled, no host source mounts, no game/API secrets, no Docker socket, dropped capabilities except those required by the official Judge0 worker, read-only configuration mounts, and bounded CPU/memory/log sizes. Document that production requires a separate Linux VM or node pool.

- [ ] **Step 5: Start and verify infrastructure**

Run:

```powershell
Copy-Item ..\study_game_server\.env.example ..\study_game_server\.env.local
Copy-Item ../study_game_server/judge0.conf.example ../study_game_server/judge0.conf
docker compose -f ../study_game_server/compose.yml --env-file ..\study_game_server\.env.local config
docker compose -f ../study_game_server/compose.yml --env-file ..\study_game_server\.env.local up -d --build
Invoke-RestMethod http://127.0.0.1:8000/health/live
Invoke-RestMethod http://127.0.0.1:8000/health/ready
docker compose -f ../study_game_server/compose.yml --env-file ..\study_game_server\.env.local ps
```

Expected: both health endpoints succeed; only port `8000` is published, on loopback; Judge0 and both databases have no published host ports. A separate `db-debug` Compose profile may publish app PostgreSQL to `127.0.0.1:5433`, but it is disabled by default and never used by Godot.

- [ ] **Step 6: Run a direct disposable Judge0 smoke**

Submit `print(input())` with stdin `ok` through the private network using `docker compose exec api`; poll the returned token; expected status ID is `3`.

If Judge0 1.13.1 cannot execute under Docker Desktop's current cgroup mode, stop this task and document the evidence. Move only Judge0 services to a local WSL2/Linux VM; do not weaken isolation or use an unreviewed fork image.

- [ ] **Step 7: Commit**

```powershell
git -C ..\study_game_server add .
git -C ..\study_game_server commit -m "build: add private local judge topology" -m "Constraint: only the game API crosses the judge network boundary`nConfidence: medium`nScope-risk: broad`nNot-tested: production Linux isolation"
git add docs/LOCAL_CODING_SETUP.md
git commit -m "docs: add local coding service setup" -m "Constraint: server remains outside Godot resources`nConfidence: high`nScope-risk: narrow"
```

---

### Task 10: Add a Pure Godot API Contract Parser

**Files:**
- Create: `scripts/domain/api_response.gd`
- Modify: `tests/test_runner.gd`

**Interfaces:**
- Produces:

```gdscript
ApiResponse.parse_session(value: Variant) -> Dictionary
ApiResponse.parse_problem_list(value: Variant) -> Array[Dictionary]
ApiResponse.parse_problem(value: Variant) -> Dictionary
ApiResponse.parse_submission(value: Variant) -> Dictionary
```

Each function returns `{"ok": true, "value": normalized_value}` or `{"ok": false, "error": "stable_code"}`.

- [ ] **Step 1: Add parser tests to `_initialize()`**

Register `_test_api_response()` and cover a valid payload plus:

```text
non-dictionary root
missing access_token
problem list containing a non-dictionary item
unsupported language
missing statement
unknown verdict
negative reward or wallet balance
oversized starter code
```

- [ ] **Step 2: Run and confirm parser absence**

Run the primary Godot test command. Expected: parse failure because `ApiResponse` does not exist.

- [ ] **Step 3: Implement strict normalization**

Use explicit allowlists:

```gdscript
const VERDICTS := [
	"accepted", "wrong_answer", "compile_error", "runtime_error",
	"time_limit", "memory_limit", "output_limit", "internal_error"
]
const STAGES := ["learn", "practice", "interview", "challenge"]
const MAX_TEXT := 20000
const MAX_STARTER_CODE := 32768
```

Copy only known fields into returned dictionaries. Never pass a raw server dictionary to UI code.

- [ ] **Step 4: Run all Godot tests and commit**

```powershell
git add scripts/domain/api_response.gd tests/test_runner.gd
git commit -m "feat(godot): validate coding API payloads" -m "Constraint: untrusted server values are normalized before UI use`nConfidence: high`nScope-risk: narrow"
```

---

### Task 11: Add the Godot `GameApi` Autoload

**Files:**
- Create: `scripts/autoload/game_api.gd`
- Create: `tests/game_api_contract.gd`
- Modify: `project.godot`

**Interfaces:**
- Produces signals:

```gdscript
signal session_ready(user: Dictionary)
signal problems_loaded(problems: Array)
signal problem_loaded(problem: Dictionary)
signal public_run_completed(result: Dictionary)
signal submission_completed(result: Dictionary)
signal request_failed(operation: String, code: String)
```

- Produces methods:

```gdscript
func bootstrap_guest() -> void
func fetch_problems() -> void
func fetch_problem(slug: String) -> void
func run_public_tests(problem_slug: String, source_code: String) -> void
func submit_code(problem_slug: String, source_code: String, idempotency_key: String) -> void
func wallet_coins() -> int
```

- [ ] **Step 1: Create a deterministic local fake API**

`tests/game_api_contract.gd` starts a loopback `TCPServer` on an ephemeral port and responds to guest session, problem list, problem detail, public run, and final submission endpoints with fixed JSON. It records request paths, authorization headers, and submission bodies without logging source contents.

- [ ] **Step 2: Write contract assertions**

Assert:

1. Guest bootstrap stores the token only in memory.
2. Subsequent requests send `Authorization: Bearer`.
3. Problem payloads pass through `ApiResponse`.
4. Public runs emit `public_run_completed` and never update wallet state.
5. A duplicate run or submit click while one request is active emits `request_failed(operation, "request_in_flight")`.
6. Timeout, malformed JSON, non-2xx response, parser rejection, `202 running`, `429`, and `503 retryable` emit or preserve the documented stable states.
7. No token is written to `ProgressStore` or `progress.json`.

- [ ] **Step 3: Run and confirm autoload absence**

Run:

```powershell
C:\Users\admin\Downloads\all_project\godot\Godot_v4.6.2-stable_win64.exe --headless --path . --script res://tests/game_api_contract.gd
```

- [ ] **Step 4: Implement `GameApi`**

Use one `HTTPRequest` child per operation or serialize requests through one explicit queue. Set:

```gdscript
const DEFAULT_BASE_URL := "http://127.0.0.1:8000"
const REQUEST_TIMEOUT_SECONDS := 15.0
```

The base URL may be overridden by the `GAME_API_URL` environment variable for tests and local devices. Generate idempotency keys in the UI using 16 random bytes; `GameApi` rejects empty keys.

- [ ] **Step 5: Register after existing stores**

Add:

```ini
GameApi="*res://scripts/autoload/game_api.gd"
```

Do not modify or replace `ProgressStore` in this task.

- [ ] **Step 6: Run contract and baseline tests**

Expected: contract runner exits `0`; existing 129+ domain tests remain green; main scene boots even when the API is offline.

- [ ] **Step 7: Commit**

```powershell
git add project.godot scripts/autoload/game_api.gd tests/game_api_contract.gd
git commit -m "feat(godot): add local game API boundary" -m "Constraint: tokens stay memory-only and Judge0 is never called directly`nConfidence: high`nScope-risk: moderate"
```

---

### Task 12: Build the Python Coding Challenge Screen

**Files:**
- Create: `scenes/CodingChallenge.tscn`
- Create: `scripts/ui/coding_challenge.gd`
- Modify: `scripts/ui/ranch.gd`

**Interfaces:**
- Consumes: `GameApi` signals and methods from Task 11
- Produces: a usable desktop-first code challenge flow with a compact narrow-layout fallback

- [ ] **Step 1: Create the scene skeleton**

```ini
[gd_scene load_steps=2 format=3]

[ext_resource path="res://scripts/ui/coding_challenge.gd" type="Script" id="1"]

[node name="CodingChallenge" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1")
```

- [ ] **Step 2: Build the code-first layout**

Desktop:

```text
top bar: back, connection state, wallet
left 42%: title, stage, concepts, statement, examples
right 58%: Python label, CodeEdit, run-public-tests button, final-submit button, result panel
```

Under `760px`, switch to a `TabContainer` with `문제` and `코드` tabs. Do not shrink editor text based on viewport width.

- [ ] **Step 3: Implement states**

Use exact states:

```gdscript
enum ViewState { CONNECTING, LOADING, READY, RUNNING_PUBLIC, SUBMITTING, RESULT, ERROR }
```

Disable both execution buttons unless `READY` or `RESULT`. While either request is active, disable both buttons. Preserve source while switching state or resizing. Never render source or API error details into BBCode.

- [ ] **Step 4: Implement first-load flow**

On ready:

```text
if no session: bootstrap_guest
after session: fetch_problem("frequency-kits")
after problem: initialize CodeEdit with starter_code only if editor is empty
```

The editor supports Python indentation, line numbers, and horizontal scrolling. No local Python execution occurs.

- [ ] **Step 5: Implement public-run flow**

The public-run button calls `GameApi.run_public_tests()` and displays only public-case verdicts and counts. It does not create an idempotency key, alter wallet state, show a reward animation, or create an objective-quiz wrong-note entry.

- [ ] **Step 6: Implement final-submission flow**

Generate:

```gdscript
var idempotency_key := Crypto.new().generate_random_bytes(16).hex_encode()
```

Reuse that key only when retrying the same unresolved submission. Generate a new key after a terminal result or source edit.

Display verdict, passed/total, time, memory, reward granted, and authoritative wallet balance. Accepted with `reward.granted=false` says the reward was already received without framing it as punishment.

- [ ] **Step 7: Add ranch navigation**

Add a clearly labeled coding challenge navigation command using the existing `_make_nav_button` pattern and `change_scene_to_file("res://scenes/CodingChallenge.tscn")`. Keep existing quiz, collection, gacha, market, and settings navigation intact.

- [ ] **Step 8: Run scene smokes**

Run the scene headless with API offline and online. Offline must show a retryable connection state without Godot errors. Online must load the seeded title and starter code.

- [ ] **Step 9: Commit**

```powershell
git add scenes/CodingChallenge.tscn scripts/ui/coding_challenge.gd scripts/ui/ranch.gd
git commit -m "feat(godot): add Python coding challenge flow" -m "Constraint: desktop-first with a narrow-screen fallback`nConfidence: high`nScope-risk: moderate"
```

---

### Task 13: Verify the End-to-End Reward Boundary

**Files:**
- Create: `../study_game_server/tests/test_vertical_slice.py`
- Create: `tests/coding_e2e_smoke.gd`
- Modify: `docs/LOCAL_CODING_SETUP.md`
- Modify: `README.md`

**Interfaces:**
- Verifies all interfaces from Tasks 2-12 without adding new production behavior.

- [ ] **Step 1: Add the server end-to-end test**

Use real PostgreSQL and a `FakeJudgeClient` to verify:

```text
create guest
list and open frequency-kits
run public cases and observe no wallet or reward change
submit accepted source
observe reward 300 and wallet 300
repeat same idempotency key
observe same submission and wallet 300
submit accepted source with a new key
observe reward.granted false and wallet 300
leave a submission running with an expired lease, restart the app, and recover it with the same key
exceed the new-submission limit and observe 429 without blocking replay of an existing key
```

- [ ] **Step 2: Add the real-Judge0 integration marker**

The marked test loads the server-only reference source from `study_game_server/tests/fixtures/reference_frequency_kits.py`. Expected: `accepted`, `6/6`. It then loads `study_game_server/tests/fixtures/mutant_ignores_target_multiplicity.py`; expected: `wrong_answer`. Neither fixture is copied into `study_game_v2`, Godot resources, screenshots, or logs.

- [ ] **Step 3: Add the Godot UI smoke**

The smoke runner loads `CodingChallenge.tscn`, waits for `READY`, verifies title `문자 키트 만들기`, inserts the accepted source, triggers the same submit callback as the button, waits for `RESULT`, and asserts wallet `300`.

- [ ] **Step 4: Run the complete verification matrix**

Run:

```powershell
docker compose -f ../study_game_server/compose.yml --env-file ..\study_game_server\.env.local up -d --build
docker compose -f ../study_game_server/compose.yml --env-file ..\study_game_server\.env.local run --rm api pytest -q
docker compose -f ../study_game_server/compose.yml --env-file ..\study_game_server\.env.local run --rm api pytest -q -m judge0
C:\Users\admin\Downloads\all_project\godot\Godot_v4.6.2-stable_win64.exe --headless --path . --script res://tests/test_runner.gd
C:\Users\admin\Downloads\all_project\godot\Godot_v4.6.2-stable_win64.exe --headless --path . --script res://tests/ranch_off_smoke.gd
C:\Users\admin\Downloads\all_project\godot\Godot_v4.6.2-stable_win64.exe --headless --path . --script res://tests/quiz_regression.gd
C:\Users\admin\Downloads\all_project\godot\Godot_v4.6.2-stable_win64.exe --headless --path . --script res://tests/game_api_contract.gd
C:\Users\admin\Downloads\all_project\godot\Godot_v4.6.2-stable_win64.exe --headless --path . --script res://tests/coding_e2e_smoke.gd
C:\Users\admin\Downloads\all_project\godot\Godot_v4.6.2-stable_win64.exe --headless --path . --quit-after 30
```

Expected: every command exits `0`, no null-yard error appears, and the final PostgreSQL wallet balance is `300`.

- [ ] **Step 5: Perform security-negative checks**

Verify:

```text
Godot project contains no reference solution or hidden case values.
Judge0 port 2358 is not published to the host.
Production configuration returns 404 for /v1/dev/sessions.
API logs contain no source, stdin, expected output, token, or database URL.
32 KiB+ source returns 422 before Judge0 is called.
Judge0 outage returns no reward and supports an idempotent retry.
An expired running lease is recovered after API restart.
The eleventh new submission in 60 seconds returns 429; replaying an existing key remains retrievable.
Public runs never create reward claims, ledger rows, or objective-quiz wrong notes.
```

- [ ] **Step 6: Update documentation**

Document prerequisites, exact startup order, health commands, how to stop containers without deleting volumes, how to reset only the local demo database, cgroup troubleshooting, and the explicit statement that local demo tests are server-only but production problem content requires a private authoring pipeline.

- [ ] **Step 7: Final review and commit**

Run `git diff --check`, review only intended files, and request an independent code-review pass.

```powershell
git -C ..\study_game_server add tests/test_vertical_slice.py tests/fixtures
git -C ..\study_game_server commit -m "test: prove server coding reward boundary" -m "Constraint: hidden fixtures remain outside Godot resources`nConfidence: high`nScope-risk: broad"
git add README.md docs/LOCAL_CODING_SETUP.md tests/coding_e2e_smoke.gd
git commit -m "test: prove local coding reward vertical slice" -m "Constraint: completion requires real Godot-to-API-to-Judge0 evidence`nConfidence: high`nScope-risk: broad`nNot-tested: hosted production and mobile devices"
```

---

## Completion Gate

The phase is complete only when:

- Farm-disabled boot is error-free.
- Existing Godot domain tests still pass.
- The game API and application PostgreSQL are healthy.
- Judge0 is reachable only from the API network.
- Godot loads the public problem without hidden content.
- Accepted reference code passes all six cases.
- A representative mutant fails.
- First Accepted grants exactly 300 coins.
- Duplicate requests and later Accepted submissions leave the wallet at 300.
- Offline API and Judge0 outage states remain retryable and grant nothing.
- No production authentication, P2P market, or art migration work was silently pulled into this phase.
