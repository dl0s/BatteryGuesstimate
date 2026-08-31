# Garmin Lightweight RC Acceptance

## Verification status (2026-08-31)

The production boundary is the explicit source allowlist in
`app/fenix7-v1.jungle`. Graph, History, watch-side analytics, WebDAV export,
legacy carousel/details delegates, and their transitive production paths are
not compiled into this target.

Build configuration: Connect IQ SDK 8.4.1, type checking level 2, release
stripping, and code-size optimization (`-l 2 -r -O z`).

| Target | Production build | Total PRG | Glance data | Glance code |
| --- | --- | ---: | ---: | ---: |
| fēnix 7 | PASS | 56,588 B | 7,345 B | 17,016 B |
| fēnix 7 Pro | PASS | 56,732 B | 7,345 B | 17,016 B |
| fēnix 7X | PASS | 56,636 B | 7,345 B | 17,016 B |
| fēnix 7X Pro | NOT RUN | — | — | — |

The fēnix 7X Pro device package is not installed on this workstation. Its
manifest target and shared round-260/280 resource qualifier remain present.

## Simulator suite

The fēnix 7 Pro test PRG compiled and executed in the simulator:

```text
Ran 28 tests
PASSED (passed=28, failed=0, errors=0)
```

Coverage includes:

- first install, append/page rollover, restart, capacity recycling, explicit
  data loss, metadata recovery, and legacy schema migration;
- retry/backoff, disconnected-phone behavior, immediate backlog drain,
  transport-success-without-ACK, durable ACK, retry, and restart resume;
- final 13-field wire row, control messages, descriptor request, firmware and
  old candidate-row compatibility;
- numeric activity timer/sport context and connection bitmask;
- valid, negative, unknown, stale, cached, refresh-interval, and real-timestamp
  temperature behavior;
- Glance cold/warm summary-only access and isolation from schema initialization,
  migration, PageStore/history, metadata, and sync;
- background-style append preserving ACK state and lightweight performance
  budgets.

## Measured lightweight paths

Simulator measurements from the final suite:

```text
glanceColdMs=0
glanceWarmMs=0
normalCallbackCoreMs=16
temperatureReadMs=0
```

The temperature result means the newest-one-entry simulator path completed
within the timer's resolution; it is not a physical-device latency claim.
Glance uses one `Application.Storage.getValue()` call for the compact summary
and performs no store construction, migration, recovery, history scan, or sync.

## Remaining release-freeze gates

- Run the same build for a locally installed fēnix 7X Pro device package.
- Complete the existing 72-hour fēnix 7 Pro real-device run and record callback
  duration, temperature refresh duration, crash count, sequence continuity,
  offline backlog, replay, and durable-ACK behavior.
- Keep Battery Protocol V1 at **FREEZE CANDIDATE** until the real-device gate
  passes; positional changes after freezing require V2.

Code and simulator acceptance therefore reach **GARMIN BATTERY TELEMETRY —
LIGHTWEIGHT RC**. Protocol freeze and broad physical-device release remain
separate gates.
