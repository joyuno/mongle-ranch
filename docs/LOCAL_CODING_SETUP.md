# Local Coding Service Setup

The local topology exposes only the game API at `http://127.0.0.1:8000`.
PostgreSQL, Redis, and Judge0 do not publish host ports. Real values belong only
in ignored `.env.local` and `judge0.conf` files.

## Start

From `study_game_server`:

```powershell
Copy-Item .env.example .env.local
Copy-Item judge0.conf.example judge0.conf
# Replace every CHANGE_ME value with a unique local secret.
docker compose --env-file .env.local config
docker compose --env-file .env.local up -d --build
Invoke-RestMethod http://127.0.0.1:8000/health/live
Invoke-RestMethod http://127.0.0.1:8000/health/ready
docker compose --env-file .env.local ps
```

`migrate` and `seed` are one-shot services. The API waits for both to complete
successfully. `judge0.conf` uses Judge0 CE 1.13.1 keys, disables submission
networking, callbacks, compiler options, command-line arguments, batch
submissions, additional files, and telemetry.

## Network And Security

`game-net` contains the API, app PostgreSQL, migrations, and seed. `judge-net`
is internal and contains Judge0, Judge0 PostgreSQL, Redis, and the API. The API
is the only service on both networks. The Judge0 configuration mount is
read-only; no source, Docker socket, or game/API secret is mounted into Judge0.
The worker drops all capabilities except `CHOWN`, `SETGID`, `SETUID`,
`SYS_ADMIN`, and `SYS_CHROOT`, which the official worker's sudo/isolate path
requires. Resource and log limits target Docker Desktop's 2 CPU and 4 GiB
minimum.

Production execution requires a separate Linux VM or node pool. Do not run
Judge0 on the game API host.

## Docker Desktop Limitation

Judge0 CE 1.13.1 cannot execute submissions in this Docker Desktop backend:
its bundled isolate 1.8.1 invokes `--cg` and requires the cgroup v1 memory
hierarchy, while the backend exposes only read-only cgroup v2. The direct
language-71 smoke therefore reaches Judge0 but returns status `13` with no
submission box. Do not switch the Judge0 per-process limit settings merely to
bypass cgroups, and do not weaken the worker to privileged mode.

Move only Judge0 server, worker, PostgreSQL, and Redis to a local WSL2/Linux VM
that has been verified to expose the cgroup v1 memory hierarchy. Point the API
at that private Judge0 endpoint, retain its network isolation, and re-run the
language-71 smoke before enabling coding submissions.

## Windows Local Vs Online: Two Separate Commands

Because Judge0 cannot execute here (above), Windows local development uses a
second, disjoint execution backend, Piston, behind the same `JudgeClient`
boundary the API already depends on. See
`docs/superpowers/specs/2026-07-28-piston-local-fallback-design.md` and
`docs/superpowers/plans/2026-07-28-piston-local-fallback.md` for the full
design and task breakdown. The two profiles never run together and never
share a compose file invocation:

```powershell
# Windows local development only
docker compose -f compose.yml -f compose.piston-windows.yml --env-file .env.local --profile piston up -d
# Linux / online deployment only
docker compose -f compose.yml --env-file .env.local --profile judge0 up -d
```

Privileged Piston is a local-development convenience only and is prohibited
in online deployment; the Windows profile starts no Judge0/Redis/Judge0
PostgreSQL service, and the online profile starts no Piston service.

## Pinned Supply-Chain Data (Piston, Windows Local)

- Image: `ghcr.io/engineer-man/piston@sha256:2f66b7456189c4d713aa986d98eccd0b6ee16d26c7ec5f21b30e942756fd127a`
- Upstream: `engineer-man/piston`, isolate binary `2.0` (`Built on 2025-02-08 from Git commit af6db68`)
- Runtime package: Python `3.12.0` exact (installed at first startup by `piston-runtime`/`scripts/install_piston_runtime.py` into the `piston-packages` volume; not baked into the pinned image)
- Docker Desktop resource budget: 2 CPUs, 4 GB RAM, 1 GB swap, cgroup v2 backend
- `judge-net` is `internal: true` for the online/Judge0 profile but `internal: false` for the Windows Piston profile only — Piston fetches its own package index/runtime from GitHub on first startup (a DNS-blocked `judge-net` makes the stack never become ready; proven live). Submitted code is still denied network access by `PISTON_DISABLE_NETWORKING`, a per-job isolate control independent of this Docker-level route.

## Non-Destructive Operations

```powershell
# start (idempotent; safe to re-run)
docker compose -f compose.yml -f compose.piston-windows.yml --env-file .env.local --profile piston up -d
# status
docker compose -f compose.yml -f compose.piston-windows.yml --env-file .env.local --profile piston ps
# health
Invoke-RestMethod http://127.0.0.1:8000/health/live
Invoke-RestMethod http://127.0.0.1:8000/health/ready
# logs (no payload bodies)
docker compose -f compose.yml -f compose.piston-windows.yml --env-file .env.local --profile piston logs piston
# stop containers, keep all data/package volumes
docker compose -f compose.yml -f compose.piston-windows.yml --env-file .env.local --profile piston down
```

`down -v` deletes the app database and the installed Piston Python package —
do not run it as a routine command. Only use it deliberately, and re-run
`piston-runtime`'s installer afterward.

## Verification Status (2026-07-30)

Live-started for the first time this session (previously only statically
validated via `docker compose config`). Found and fixed while live:

- `judge-net: internal: true` blocked Piston's own package bootstrap (see
  "Pinned Supply-Chain Data" above) — fixed.
- `piston-runtime` raced `piston`'s readiness (`depends_on: service_started`
  with no healthcheck) — `piston` now has a real healthcheck and
  `piston-runtime` depends on `service_healthy`; re-verified deterministic
  from a cold `down`/`up`.
- Three diagnostic bugs in `app/services/piston.py`'s `PistonReadiness`
  (network probe tested `socket()` creation, not `connect()`; the memory
  diagnostic required `status="SG"` but this build reports its OOM kill as
  `status="RE"`/`code=137`; the process-count diagnostic's exact
  `len(_children) == 29` never matched because the un-`exec`'d
  `bash -> python3.12` run wrapper already occupies 2 of the configured
  process slots) — all three fixed in source and individually re-verified
  against the live service with an equivalent inline probe.

**Proven**: rebuilt for real (a new `test` build target/service carries dev
dependencies and the test suite the `runtime` image deliberately excludes —
see `study_game_server/Dockerfile` and `compose.yml`'s `test` service,
profile-gated under `--profile test`), created and migrated a `game_test`
PostgreSQL database, and ran the suites against the live stack:

- `pytest -m piston tests/test_piston_integration.py` — 9/9 passed. All
  five isolation properties enforced under the production `_LIMITS`.
- `pytest -m piston tests/test_piston_vertical_slice.py` — 2/2 passed.
  Reward exactly-once, idempotent replay, and outage-retry all proven
  against real Piston + real PostgreSQL.
- Full server suite (excluding `tests/test_local_topology.py`, which needs
  the host `docker` CLI and cannot run inside any container): 158/158
  passed, twice in a row.
- Godot: `test_runner.gd` 129/129, `quiz_regression.gd` and
  `ranch_off_smoke.gd` all PASS (re-verified in this worktree).
- Independently reviewed (separate pass, `feature-dev:code-reviewer`) against
  the plan's Task 7 Step 6 checklist: all 10 properties PASS.

One doc-integrity finding from that review: this section and the SDD ledger
still said "not run" after the rebuild had already proven otherwise — both
are now corrected here. See `study_game_server/README.md` and commits
`363fe69`/`225218d` for full detail, including two more real bugs the actual
`pytest -m piston` run exposed beyond the ones found via inline probes
(the isolation-cases fixture's own stale network probe, and two
pre-existing test-hygiene gaps in `test_judge_settings.py`/`test_problems.py`
that only manifested once the tests actually ran together for the first
time).

`test_health.py::test_readiness` and `test_busy_loop_hits_the_time_limit`
each failed once and passed on immediate retry — both depend on tight time
budgets and this host ran the whole session at roughly 400 MB/14 GB free
memory. Treat as host-load flakiness, not a code defect, unless it
reproduces on a normal machine.
