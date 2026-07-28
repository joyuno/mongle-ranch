# Windows Piston Local Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make real Python coding-test execution work on the current Windows Docker Desktop environment through a private Piston backend, while retaining Judge0 unchanged for Linux and online deployment.

**Architecture:** FastAPI selects one `JudgeClient` at startup from `JUDGE_BACKEND`; submission persistence, idempotency, rate limiting, and rewards remain backend-neutral. The Windows Compose profile runs Piston alone on the internal judge network with a pinned Python runtime and fail-closed readiness probe. Judge0 remains the explicit Linux profile.

**Tech Stack:** Python 3.12; FastAPI; HTTPX async transport; pytest; PostgreSQL; Docker Compose; Piston commit `0a844d0a3c040dfe3adf1e9d903b9ad4e5ede155`, image digest `sha256:2f66b7456189c4d713aa986d98eccd0b6ee16d26c7ec5f21b30e942756fd127a`; Piston Python `3.12.0`, package SHA-256 `abc40b3231fc7e713799da2cd79844545c72b3904a4d2ffcc28c4d133ed21d0b`.

## Global Constraints

- Work in `C:\Users\admin\Downloads\all_project\study_game_server` on `codex/local-coding-vertical-slice`; documentation work stays in the Godot worktree on `codex/local-coding-implementation`.
- Piston is Windows-local only. `JUDGE_BACKEND=judge0` remains the online/Linux setting and Godot never selects a backend.
- Piston has no host port, no `game-net`, no database/API secrets, no Docker socket, and no host source bind mount.
- Privileged mode exists only in `compose.piston-windows.yml`; the base/Linux topology must not become privileged.
- Required limits are CPU 2,000 ms, wall 5,000 ms, memory 131,072,000 bytes (`128000 KiB`), process count 30, and output 1,048,576 bytes (`1024 KiB`).
- Set `PISTON_DISABLE_NETWORKING=true`, `PISTON_MAX_CONCURRENT_JOBS=1`, and `PISTON_MAX_PROCESS_COUNT=30`.
- A missing runtime, mismatched runtime version, unreachable engine, failed diagnostic, or unproven limit/isolation capability makes `/health/ready` return `503`. Never silently weaken a limit.
- Do not log source code, stdin, expected output, bearer tokens, engine response bodies, or database URLs.
- Do not add Piston-specific fields to the public API, database schema, Godot client, or `JudgeClient.judge()` signature.
- Keep the existing retry rule: `internal_error` is retryable and grants no reward.
- Every production edit begins with a failing focused test. Author and reviewer are separate passes.
- Do not push, deploy, delete volumes, or reset databases without a new explicit user approval.

**Server unit command:**

```powershell
uv run pytest -q
```

**Windows Piston Compose prefix:**

```powershell
docker compose -f compose.yml -f compose.piston-windows.yml --env-file .env.local --profile piston
```

**Linux Judge0 Compose prefix:**

```powershell
docker compose -f compose.yml --env-file .env.local --profile judge0
```

---

## Task 1: Add Explicit Backend Configuration

**Files:**
- Modify: `C:\Users\admin\Downloads\all_project\study_game_server\app\config.py`
- Create: `C:\Users\admin\Downloads\all_project\study_game_server\tests\test_judge_settings.py`

**Interfaces:**

```python
JudgeBackend = Literal["judge0", "piston"]
```

- [ ] **Step 1: Write settings validation tests**

Cover exact `JUDGE_BACKEND=judge0` and `JUDGE_BACKEND=piston` parsing, invalid backend validation, Judge0 defaults, and Piston URL/runtime defaults. Assert these are process settings only and do not appear in any public request schema.

- [ ] **Step 2: Run the focused test and capture RED**

```powershell
uv run pytest tests/test_judge_settings.py -q
```

Expected: assertions fail because the new settings do not exist.

- [ ] **Step 3: Add validated settings**

Add:

```python
judge_backend: Literal["judge0", "piston"] = "judge0"
piston_url: str = "http://piston:2000"
piston_python_version: str = "3.12.0"
```

Keep `judge0_url` and `judge0_python_language_id`. Do not infer the backend from URL or operating system. Do not wire selection into `create_app()` until Task 3, after both concrete clients exist.

- [ ] **Step 4: Run tests and commit**

```powershell
uv run pytest tests/test_judge_settings.py tests/test_health.py tests/test_submissions.py -q
git add app/config.py tests/test_judge_settings.py
git commit -m "feat: configure judge backend explicitly" -m "Constraint: backend selection is process configuration only`nConfidence: high`nScope-risk: narrow"
```

Expected: focused suites pass; no existing public contract changes.

---

## Task 2: Implement the Piston Adapter Under the Existing Contract

**Files:**
- Create: `C:\Users\admin\Downloads\all_project\study_game_server\app\services\piston.py`
- Create: `C:\Users\admin\Downloads\all_project\study_game_server\tests\test_piston.py`
- Modify: `C:\Users\admin\Downloads\all_project\study_game_server\app\services\submissions.py`

**Interfaces:**

```python
class PistonClient:
    def __init__(
        self,
        piston_url: str,
        python_version: str,
        *,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        raise NotImplementedError

    def judge(
        self,
        source_code: str,
        cases: list[JudgeCase],
        limits: JudgeLimits,
    ) -> JudgeResult:
        raise NotImplementedError
```

- [ ] **Step 1: Write exact request contract tests with `httpx.MockTransport`**

For each case assert one `POST /api/v2/execute` with:

```python
{
    "language": "python",
    "version": "3.12.0",
    "files": [{"name": "main.py", "content": source_code, "encoding": "utf8"}],
    "stdin": case["stdin"],
    "args": [],
    "run_timeout": 5000,
    "run_cpu_time": 2000,
    "run_memory_limit": 131_072_000,
}
```

Assert `trust_env=False`, a 10-second total adapter deadline, async-only transports, and sequential early stop after the first non-Accepted case.

- [ ] **Step 2: Write normalization tests**

Cover:

```text
status null + code 0 + exact normalized stdout -> accepted
status null + code 0 + output mismatch -> wrong_answer
status TO -> time_limit
status OL or EL -> output_limit
status RE or SG -> memory_limit when Piston reports a memory-limit message or measured memory reaches the limit, otherwise runtime_error
status XX, malformed JSON, 4xx/5xx, timeout, oversized response -> internal_error
unexpected compile object for Python -> internal_error
```

Compare output using the same exact string contract currently used by Judge0 expected-output evaluation. Sum runtime across accepted cases and retain peak memory; do not expose stdout/stderr.

- [ ] **Step 3: Add a log-capture negative test**

Place unique markers in source, stdin, and expected output; force transport and malformed-response failures; assert none appears in `caplog.text`.

- [ ] **Step 4: Run focused tests and capture RED**

```powershell
uv run pytest tests/test_piston.py -q
```

Expected: import failure because `PistonClient` does not exist.

- [ ] **Step 5: Implement the minimal adapter**

Reuse the existing synchronous-to-async thread boundary pattern. Bound the HTTP response body before JSON parsing to 2 MiB. Use Piston's `run.cpu_time`, `run.wall_time`, and `run.memory` integers directly; convert runtime milliseconds without floating-point seconds conversion.

- [ ] **Step 6: Align shared submission limits with the approved design**

Change `_LIMITS` in `app/services/submissions.py` to:

```python
{
    "cpu_time_limit": 2.0,
    "wall_time_limit": 5.0,
    "memory_limit_kb": 128000,
    "max_processes": 30,
    "max_output_kb": 1024,
}
```

Add a test asserting this exact bundle reaches a fake `JudgeClient`; this prevents drift between Piston configuration and application requests.

- [ ] **Step 7: Run adapter and Judge0 regressions**

```powershell
uv run pytest tests/test_piston.py tests/test_judge.py tests/test_submissions.py -q
```

Expected: both adapters satisfy the existing result vocabulary; submission tests remain green.

- [ ] **Step 8: Commit**

```powershell
git add app/services/piston.py app/services/submissions.py tests/test_piston.py tests/test_submissions.py
git commit -m "feat: add Piston judge adapter" -m "Constraint: Piston normalizes into the existing JudgeClient contract`nConfidence: high`nScope-risk: moderate"
```

---

## Task 3: Add Fail-Closed Piston Readiness

**Files:**
- Modify: `C:\Users\admin\Downloads\all_project\study_game_server\app\services\piston.py`
- Create: `C:\Users\admin\Downloads\all_project\study_game_server\app\services\judge_backend.py`
- Modify: `C:\Users\admin\Downloads\all_project\study_game_server\app\main.py`
- Modify: `C:\Users\admin\Downloads\all_project\study_game_server\app\routers\health.py`
- Create: `C:\Users\admin\Downloads\all_project\study_game_server\tests\test_judge_backend.py`
- Modify: `C:\Users\admin\Downloads\all_project\study_game_server\tests\test_health.py`
- Modify: `C:\Users\admin\Downloads\all_project\study_game_server\tests\test_piston.py`

**Interfaces:**

```python
@dataclass(frozen=True)
class JudgeBackendBundle:
    client: JudgeClient
    readiness: JudgeReadiness

class JudgeReadiness(Protocol):
    def check(self) -> bool:
        raise NotImplementedError

def build_judge_backend(settings: Settings) -> JudgeBackendBundle:
    raise NotImplementedError

class PistonReadiness:
    def check(self) -> bool:
        raise NotImplementedError
```

- [ ] **Step 1: Write factory selection tests**

Assert `judge0` returns `Judge0Client` plus a readiness object that preserves current behavior, `piston` returns `PistonClient` plus `PistonReadiness`, and invalid configuration never falls back to another backend.

- [ ] **Step 2: Write readiness tests**

Assert `False` for unreachable API, absent Python runtime, runtime other than exact `3.12.0`, any failed bounded diagnostic, malformed response, and expired cache. Assert `True` only when:

1. `GET /api/v2/runtimes` contains exact Python `3.12.0`.
2. `POST /api/v2/execute` runs the fixed server-owned `print(6 * 7)` diagnostic.
3. Response is code `0`, status `null`, stdout `42\n`.
4. A fixed socket diagnostic receives `PermissionError` and prints only `NETWORK_BLOCKED`.
5. Fixed timeout, memory, output, and 31-process diagnostics terminate with their required limit statuses.

Assert the complete successful diagnostic set is cached for 30 seconds and failures for 5 seconds using an injected monotonic clock.

- [ ] **Step 3: Write health route tests and capture RED**

When the database succeeds but `app.state.judge_readiness.check()` is false, expect only:

```json
{"status": "unavailable"}
```

with HTTP `503`. Do not expose backend names or diagnostic details.

```powershell
uv run pytest tests/test_judge_backend.py tests/test_health.py tests/test_piston.py -q
```

- [ ] **Step 4: Implement the factory and startup wiring**

In `create_app()`, build the bundle exactly once and assign:

```python
app.state.judge_client = bundle.client
app.state.judge_readiness = bundle.readiness
```

`judge0` returns the existing `Judge0Client` and a readiness object that returns `True`, preserving current Judge0 health behavior. No router or request body can replace the selected client.

- [ ] **Step 5: Implement readiness and route integration**

Run the fixed diagnostic set with strict CPU/wall/memory request values. Each program is a source constant owned by the server, each uses a shorter diagnostic limit than user submissions, and the entire probe has a 15-second outer deadline. Catch transport/schema exceptions and return `False` without logging response bodies. Preserve existing database failure behavior.

- [ ] **Step 6: Run focused and full tests**

```powershell
uv run pytest tests/test_health.py tests/test_piston.py tests/test_judge_backend.py -q
uv run pytest -q
```

Expected: all tests pass with only the already-recorded upstream FastAPI `TestClient` warning.

- [ ] **Step 7: Commit**

```powershell
git add app/services/piston.py app/services/judge_backend.py app/main.py app/routers/health.py tests/test_judge_backend.py tests/test_health.py tests/test_piston.py
git commit -m "feat: fail readiness when Piston is unsafe" -m "Constraint: missing isolation evidence blocks local execution`nConfidence: high`nScope-risk: moderate"
```

---

## Task 4: Create the Private Windows Piston Compose Profile

**Files:**
- Modify: `C:\Users\admin\Downloads\all_project\study_game_server\compose.yml`
- Create: `C:\Users\admin\Downloads\all_project\study_game_server\compose.piston-windows.yml`
- Modify: `C:\Users\admin\Downloads\all_project\study_game_server\.env.example`
- Create: `C:\Users\admin\Downloads\all_project\study_game_server\scripts\install_piston_runtime.py`
- Modify: `C:\Users\admin\Downloads\all_project\study_game_server\tests\test_local_topology.py`

**Interfaces:**
- Base profile: `--profile judge0`
- Windows override: `-f compose.yml -f compose.piston-windows.yml --profile piston`

- [ ] **Step 1: Extend static topology tests**

Parse both resolved configurations. For Windows Piston assert:

```text
services: api, app-db, migrate, seed, piston, piston-runtime
only api publishes 127.0.0.1:8000
piston and piston-runtime use judge-net only
piston has privileged=true and no host bind mounts
piston has no game secrets, Docker socket, or source mount
judge0-server, judge0-worker, judge0-db, redis are absent
judge-net remains internal
image uses the exact immutable Piston digest
Python installer requests exact 3.12.0
```

For Judge0 assert its current services and restrictions remain intact and Piston is absent.

- [ ] **Step 2: Run topology tests and capture RED**

```powershell
uv run pytest tests/test_local_topology.py -q
```

Expected: Windows override is missing and profile assertions fail.

- [ ] **Step 3: Profile the existing Judge0-only services**

Add `profiles: ["judge0"]` to `judge0-db`, `redis`, `judge0-server`, and `judge0-worker`. Update base `api.depends_on` only as required for the Judge0 profile; do not change images, capabilities, or networks.

- [ ] **Step 4: Add `compose.piston-windows.yml`**

Use Compose `!override` for `api.depends_on`, set:

```yaml
JUDGE_BACKEND: piston
PISTON_URL: http://piston:2000
PISTON_PYTHON_VERSION: "3.12.0"
```

Define Piston with:

```yaml
image: ghcr.io/engineer-man/piston@sha256:2f66b7456189c4d713aa986d98eccd0b6ee16d26c7ec5f21b30e942756fd127a
profiles: ["piston"]
privileged: true
networks: [judge-net]
volumes: [piston-packages:/piston/packages]
tmpfs: ["/tmp:exec"]
```

Set exact Piston environment:

```yaml
PISTON_DISABLE_NETWORKING: "true"
PISTON_MAX_PROCESS_COUNT: "30"
PISTON_OUTPUT_MAX_SIZE: "1048576"
PISTON_RUN_TIMEOUT: "5000"
PISTON_RUN_CPU_TIME: "2000"
PISTON_RUN_MEMORY_LIMIT: "131072000"
PISTON_MAX_CONCURRENT_JOBS: "1"
PISTON_LOG_LEVEL: "WARN"
```

Budget Piston at `768m`, `0.75` CPU, and container `pids_limit: 96`. Keep API/app DB/migration/seed budgets unchanged so the stack fits Docker Desktop's 2 CPU/4 GB/1 GB swap allocation.

- [ ] **Step 5: Add an idempotent runtime installer**

`scripts/install_piston_runtime.py` waits for `GET /api/v2/packages`, verifies the repository advertises Python `3.12.0`, installs it with `POST /api/v2/packages` only when absent, and then verifies `GET /api/v2/runtimes`. It never prints response bodies. Run it as one-shot `piston-runtime`, using the API image, on `judge-net` only, with no application secrets.

- [ ] **Step 6: Validate both resolved topologies**

```powershell
docker compose -f compose.yml --env-file .env.example --profile judge0 config
docker compose -f compose.yml -f compose.piston-windows.yml --env-file .env.example --profile piston config
uv run pytest tests/test_local_topology.py -q
```

Expected: both configurations resolve; tests prove exactly one execution backend per profile.

- [ ] **Step 7: Commit**

```powershell
git add compose.yml compose.piston-windows.yml .env.example scripts/install_piston_runtime.py tests/test_local_topology.py
git commit -m "build: add private Windows Piston profile" -m "Constraint: privileged Piston is local-only and host-private`nConfidence: high`nScope-risk: broad"
```

---

## Task 5: Prove Piston Execution and Isolation

**Files:**
- Create: `C:\Users\admin\Downloads\all_project\study_game_server\tests\test_piston_integration.py`
- Create: `C:\Users\admin\Downloads\all_project\study_game_server\tests\fixtures\piston_isolation_cases.py`
- Modify: `C:\Users\admin\Downloads\all_project\study_game_server\pyproject.toml`

**Interfaces:**
- Pytest marker: `piston`
- Required environment: `PISTON_URL=http://piston:2000`

- [ ] **Step 1: Register the integration marker**

Add:

```toml
markers = ["piston: requires the private local Piston service"]
```

The suite skips only when `PISTON_URL` is absent. Once present, any missing capability is a hard failure.

- [ ] **Step 2: Write actual-engine tests**

Through `PistonClient`, prove:

```text
Accepted: print(input()) with stdin ok
Wrong Answer: print("wrong") against ok
Runtime Error: raise RuntimeError()
Timeout: infinite loop reaches time_limit
Memory: allocations above 128000 KiB reach memory_limit
Output: output above 1 MiB reaches output_limit
Process: spawning beyond 30 is terminated or denied
Network: socket creation or outbound connection is denied
```

Use fixed, non-secret fixture programs. Do not print their stdout/stderr on failure; report only expected and normalized verdict.

- [ ] **Step 3: Add runtime and image assertions**

Assert `GET /api/v2/runtimes` returns exact Python `3.12.0`. From the host-side verification script, assert:

```powershell
docker image inspect ghcr.io/engineer-man/piston@sha256:2f66b7456189c4d713aa986d98eccd0b6ee16d26c7ec5f21b30e942756fd127a
```

matches the configured digest.

- [ ] **Step 4: Start the stack**

```powershell
Copy-Item .env.example .env.local
# Replace only CHANGE_ME values in .env.local before continuing.
docker compose -f compose.yml -f compose.piston-windows.yml --env-file .env.local --profile piston up -d --build
docker compose -f compose.yml -f compose.piston-windows.yml --env-file .env.local --profile piston ps
Invoke-RestMethod http://127.0.0.1:8000/health/live
Invoke-RestMethod http://127.0.0.1:8000/health/ready
```

Expected: Piston healthy, runtime installer completed successfully, API ready, and only loopback port 8000 published.

- [ ] **Step 5: Run actual isolation tests**

```powershell
docker compose -f compose.yml -f compose.piston-windows.yml --env-file .env.local --profile piston exec api uv run --no-sync pytest -q -m piston tests/test_piston_integration.py
```

Expected: every execution and isolation case passes. If any network/process/resource test fails, stop; do not proceed to Task 6 or weaken the assertion.

- [ ] **Step 6: Record resource evidence**

Capture `docker stats --no-stream` and verify the stack remains within 2 CPUs and 4 GB RAM. This is evidence only; do not change Docker Desktop allocation.

- [ ] **Step 7: Commit**

```powershell
git add pyproject.toml tests/test_piston_integration.py tests/fixtures/piston_isolation_cases.py
git commit -m "test: prove local Piston isolation" -m "Constraint: actual execution is required before API completion`nConfidence: high`nScope-risk: broad`nNot-tested: hostile-code penetration testing"
```

---

## Task 6: Prove the Real Game API Reward Boundary

**Files:**
- Create: `C:\Users\admin\Downloads\all_project\study_game_server\tests\test_piston_vertical_slice.py`
- Create: `C:\Users\admin\Downloads\all_project\study_game_server\tests\fixtures\reference_frequency_kits.py`
- Create: `C:\Users\admin\Downloads\all_project\study_game_server\tests\fixtures\mutant_frequency_kits.py`

**Interfaces:**
- Uses actual Piston and PostgreSQL through the FastAPI public routes.
- Wraps the actual `PistonClient` with an integration-only call counter; production code is unchanged.

- [ ] **Step 1: Write the vertical-slice integration test**

Seed `frequency-kits`, create a local guest session, and call the same public endpoints as Godot:

1. `POST /v1/runs` with the reference source: Accepted public cases, no reward.
2. `POST /v1/submissions` with the mutant: Wrong Answer persisted, no reward.
3. `POST /v1/submissions` with the reference source and key A: Accepted `6/6`, reward `300`, wallet `300`.
4. Repeat key A: same submission ID/result, Piston wrapper call count unchanged.
5. Submit the reference with key B: Accepted, `reward.granted=false`, wallet remains `300`.

- [ ] **Step 2: Assert database authority**

In PostgreSQL assert the terminal verdict rows, one reward claim, one immutable wallet ledger grant, and wallet balance `300`. Assert no public run creates a claim or ledger row.

- [ ] **Step 3: Assert outage retry behavior**

Force the Piston transport unavailable after a new key. Assert `internal_error`, submission `retryable`, no claim, no ledger, and no balance change. Restore the real client and replay the same key; assert it executes and completes without creating a second submission row.

- [ ] **Step 4: Run the actual vertical slice**

```powershell
docker compose -f compose.yml -f compose.piston-windows.yml --env-file .env.local --profile piston exec api uv run --no-sync pytest -q -m piston tests/test_piston_vertical_slice.py
```

Expected: all assertions pass against actual Piston and PostgreSQL.

- [ ] **Step 5: Run the full server regression**

```powershell
docker compose -f compose.yml -f compose.piston-windows.yml --env-file .env.local --profile piston exec api uv run --no-sync pytest -q
```

Expected: at least the existing 83 tests plus all new tests pass; only the known upstream FastAPI `TestClient` warning may remain.

- [ ] **Step 6: Commit**

```powershell
git add tests/test_piston_vertical_slice.py tests/fixtures/reference_frequency_kits.py tests/fixtures/mutant_frequency_kits.py
git commit -m "test: prove Piston coding reward boundary" -m "Constraint: duplicate execution and duplicate rewards are independently prohibited`nConfidence: high`nScope-risk: broad"
```

---

## Task 7: Update Operations Documentation and Close the Blocked Vertical Slice

**Files:**
- Modify: `C:\Users\admin\Downloads\all_project\study_game_v2\.worktrees\local-coding-implementation\docs\LOCAL_CODING_SETUP.md`
- Modify: `C:\Users\admin\Downloads\all_project\study_game_v2\.worktrees\local-coding-implementation\docs\superpowers\plans\2026-07-27-local-coding-vertical-slice.md`
- Modify: `C:\Users\admin\Downloads\all_project\study_game_v2\.worktrees\local-coding-implementation\.superpowers\sdd\2026-07-27-local-coding-vertical-slice\progress.md`
- Modify: `C:\Users\admin\Downloads\all_project\study_game_server\README.md`

- [ ] **Step 1: Document separate local and online commands**

Document:

```text
Windows local: compose.yml + compose.piston-windows.yml + --profile piston
Linux/online: compose.yml + --profile judge0
```

State prominently that privileged Piston is a local development convenience and prohibited in online deployment.

- [ ] **Step 2: Document pinned supply-chain data and resource budget**

Record the exact Piston image digest, upstream commit, Python `3.12.0` package hash, Docker Desktop 2 CPU/4 GB/1 GB swap requirement, and how readiness fails closed.

- [ ] **Step 3: Document non-destructive operations**

Include startup, status, health, logs without payload bodies, and:

```powershell
docker compose -f compose.yml -f compose.piston-windows.yml --env-file .env.local --profile piston down
```

Do not document `down -v` as a routine command. Put database/runtime volume deletion behind an explicit data-loss warning.

- [ ] **Step 4: Update the original plan and ledger**

Mark Task 9's Judge0 Windows execution as blocked by cgroup v2 with evidence, link the approved design and this plan, and record Piston verification commits/results. Do not mark original Tasks 10-13 complete unless their own criteria have actually passed.

- [ ] **Step 5: Run both repositories' final checks**

Server:

```powershell
uv run pytest -q
git diff --check
```

Godot:

```powershell
C:\Users\admin\Downloads\all_project\godot\Godot_v4.6.2-stable_win64.exe --headless --path . --script res://tests/test_runner.gd
C:\Users\admin\Downloads\all_project\godot\Godot_v4.6.2-stable_win64.exe --headless --path . --script res://tests\quiz_regression.gd
git diff --check
```

Expected: server passes; Godot baseline and auxiliary quiz regression pass; no hidden fixture exists under the Godot repository.

- [ ] **Step 6: Run independent review**

Request separate specification and quality reviews covering:

```text
backend cannot be request-selected
Windows profile starts no Judge0 services
online profile starts no Piston service
only API publishes a host port
Piston receives no game secrets/source/Docker socket
all required isolation tests use actual execution
idempotency prevents second execution
first Accepted grants exactly once
logs and Godot resources contain no hidden material
```

Resolve all Critical and Important findings, rerun affected tests, and record evidence in the SDD ledger.

- [ ] **Step 7: Commit documentation separately**

Server:

```powershell
git add README.md
git commit -m "docs: document local Piston operations" -m "Constraint: Piston is prohibited in online deployment`nConfidence: high`nScope-risk: narrow"
```

Godot:

```powershell
git add docs/LOCAL_CODING_SETUP.md docs/superpowers/plans/2026-07-27-local-coding-vertical-slice.md .superpowers/sdd/2026-07-27-local-coding-vertical-slice/progress.md
git commit -m "docs: close Windows judge fallback design" -m "Constraint: local Piston and online Judge0 remain separate topologies`nConfidence: high`nScope-risk: narrow"
```

---

## Completion Gate

This fallback is complete only when:

- Docker Desktop remains at 2 CPUs, 4 GB RAM, and 1 GB swap.
- The Windows profile starts Piston and does not start Judge0, Redis, or Judge0 PostgreSQL.
- Only `127.0.0.1:8000` is published.
- Python `3.12.0` and the Piston image/runtime hashes match the plan.
- Actual Accepted, Wrong Answer, runtime, timeout, memory, output, process, and network-isolation tests pass.
- `/health/ready` fails closed for any missing runtime or diagnostic/isolation failure.
- An actual `frequency-kits` submission persists Accepted `6/6`.
- Replaying an idempotency key does not execute Piston again.
- Distinct Accepted submissions grant exactly one 300-coin reward.
- Piston outage grants nothing and the same key remains retryable.
- Full server and existing Godot auxiliary-learning regressions pass.
- An independent reviewer has no open Critical or Important findings.
