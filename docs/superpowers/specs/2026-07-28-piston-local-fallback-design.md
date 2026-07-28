# Piston Local Fallback Design

Date: 2026-07-28
Status: Approved design

## Context

The coding-test vertical slice uses a replaceable `JudgeClient` boundary. The
target online deployment remains Judge0 CE 1.13.1 on a Linux host.

Docker Desktop on this Windows machine uses WSL 2 with cgroup v2. Judge0 CE
1.13.1 invokes `isolate --cg` against the cgroup v1 memory hierarchy, so a
real Python submission fails with Judge0 status 13. The failure reproduces
after the API, databases, Redis, server, and worker become healthy.

The following local remediation attempts did not make Judge0 executable:

- Docker Desktop's deprecated cgroup v1 setting is ignored by the current WSL
  backend.
- Hyper-V Docker Desktop could not start a 4 GB, 3 GB, or 2 GB Linux VM with
  the host's available memory.

Docker Desktop was restored to the working WSL configuration: 2 CPUs, 4 GB
RAM, 1 GB swap, and cgroup v2.

## Decision

Use Piston only as the Windows local-development execution backend. Keep
Judge0 as the Linux and online-deployment backend.

The game API and Godot client continue to depend only on the existing
`JudgeClient` contract. Backend selection occurs once at FastAPI startup:

```text
JUDGE_BACKEND=piston  # Windows local development
JUDGE_BACKEND=judge0  # Linux integration and online deployment
```

No request can choose or override the backend.

## Architecture

### Shared boundary

`JudgeClient.run(source_code, cases, limits)` remains the only path from the
game API to an execution engine. Both implementations return the existing
normalized verdicts and case counts.

```text
Godot
  -> FastAPI submission service
    -> JudgeClient
      -> PistonClient (Windows local profile)
      -> Judge0Client (Linux/online profile)
```

Submission persistence, idempotency, rate limiting, rewards, and public versus
hidden test selection remain unchanged and PostgreSQL-authoritative.

### Piston local profile

The Windows local Compose override adds a Piston service to `judge-net`.

- Piston has no host-published port.
- Only the API can reach it.
- Piston is not connected to `game-net`.
- Piston receives no game database credentials, API secrets, Docker socket,
  or host source directory.
- Its image and Python runtime package are pinned to immutable versions and
  recorded digests.
- Privileged mode is permitted only in the explicitly named Windows local
  override because Piston requires it for sandbox setup.
- The local setup documentation must state that privileged Piston is a
  development convenience, not an online deployment topology.

The existing Judge0 services remain in the base/Linux Compose path. The
Windows local command selects the Piston override and does not start the
Judge0 server, worker, Judge0 PostgreSQL, or Redis.

## Limit Mapping

`PistonClient` translates the existing `JudgeLimits` into Piston's execution
request:

- CPU time: 2 seconds
- wall time: 5 seconds
- memory: 128000 KB
- output: bounded to the existing maximum output size
- process count: enforced when supported and validated at startup

The adapter must reject startup or readiness when the installed Piston/runtime
contract cannot enforce a required limit. It must not silently omit a
security limit.

Network access for submitted programs must be disabled or proven unavailable
by an integration test. If the selected Piston release cannot provide this
guarantee, the fallback is blocked rather than weakened.

## Execution Semantics

The adapter runs each server-selected case and normalizes Piston results to the
existing verdict vocabulary. It must:

- compare output using the existing JudgeClient output contract;
- stop according to the existing case aggregation rules;
- never expose hidden input or expected output;
- never log source code, stdin, expected output, or raw engine responses that
  contain them;
- map transport errors, engine errors, and local deadline expiry to
  `internal_error`.

An `internal_error` leaves final submissions `retryable`. It never creates a
reward claim, wallet ledger entry, or coin balance change.

## Readiness

When `JUDGE_BACKEND=piston`, API readiness verifies:

1. Piston API reachability.
2. The pinned Python runtime is installed.
3. A bounded diagnostic program executes successfully.
4. Required isolation capabilities are available.

The diagnostic contains no user source and runs only during startup/readiness
with caching to avoid executing on every health request.

When `JUDGE_BACKEND=judge0`, the existing Judge0 behavior remains unchanged.

## Testing

### Adapter contract tests

Use HTTPX `MockTransport` to prove:

- exact request encoding and limit mapping;
- Accepted, Wrong Answer, runtime, compile, timeout, and internal-error maps;
- total deadline enforcement;
- response-size enforcement;
- no source or hidden-case data in logs.

Run the same backend-neutral contract suite against both client
implementations where practical.

### Local integration tests

With the Windows Piston Compose override:

1. Confirm only `127.0.0.1:8000` is published.
2. Confirm Piston is reachable only from the private judge network.
3. Confirm the Python runtime version and pinned image digest.
4. Run a known Accepted Python submission.
5. Run a known Wrong Answer submission.
6. Prove submitted code cannot open an outbound network connection.
7. Prove timeout, memory, and output limits terminate execution.
8. Submit `frequency-kits` through the game API.
9. Confirm PostgreSQL records the verdict.
10. Retry the same idempotency key and confirm no second engine execution.
11. Submit Accepted twice with distinct keys and confirm the reward is granted
    exactly once.

### Regression tests

The full FastAPI suite and existing Godot quiz/ranch regression suites remain
green. The local fallback must not change the auxiliary quiz mode or the
public game API contract.

## Operations

Local Windows commands and secrets are documented separately from Linux and
online commands. Example environment files contain placeholders only.

The online deployment must not enable the Piston profile. Moving from local
Piston to online Judge0 requires changing deployment configuration, not Godot
code, API schemas, database rows, or submission logic.

## Success Criteria

The fallback is complete when, on Docker Desktop with 2 CPUs, 4 GB RAM, and
1 GB swap:

- the Piston local stack becomes healthy;
- actual Python Accepted and Wrong Answer executions succeed;
- isolation checks for network, time, memory, output, and process behavior
  pass;
- the game API records an actual `frequency-kits` submission;
- a duplicate idempotency key causes no second execution;
- the first Accepted reward is granted exactly once;
- no service except the API is published to the Windows host.

## Rejected Alternatives

### Unofficial patched Judge0 image

Rejected because the image and cgroup v2 patch are not an official Judge0
release and would add an insufficiently reviewed supply-chain dependency to
the execution boundary.

### Disable Judge0 cgroup isolation

Rejected because running untrusted code without required resource isolation is
not an acceptable local workaround.

### Continue with a mock judge

Rejected because the vertical-slice completion criterion requires an actual
Python execution.

### Require Hyper-V Judge0 now

Rejected for the current local workflow because Docker Desktop could not
allocate even the reduced VM memory while normal development applications were
open. Judge0 remains valid for a dedicated Linux host or future online
environment.
