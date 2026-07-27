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
