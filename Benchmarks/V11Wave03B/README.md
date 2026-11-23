# Duck v1.1 Wave03B Capacity Harness

This nested SwiftPM executable measures the accepted Wave03 canonical pool through `Database.configure(maximumConnections:)` and `Database.connection {}`. Each lane uses a unique named in-memory `Database`, configured at capacity 1, 2, 4, or 8 before its first checkout. Repository-owned core counts come from `@_spi(DuckBenchmark)` pool snapshots; public `Connection` handle identity is not used as a core reuse signal.

## Mac idle requirement

**Do not run timed samples unless the Mac is idle.** A later timing run must receive the explicit `DUCK_BENCHMARK_MAC_IDLE=YES` assertion. The runner refuses before creating a sample file when the assertion is absent. Preparation, Release builds, correctness smoke, resource probes, and selection-rule self-tests produce no accepted timing samples.

## Prepare, smoke, time, and finalize

From the repository root, choose a new output path that does not exist:

```sh
bash Benchmarks/V11Wave03B/run-wave03b.sh \
  .artifacts/handoff/v1-1-wave03b-benchmark-preparation-2026-11-22/preparation-evidence/run-01 \
  prepare
```

`prepare` resolves the nested package, builds Release with Swift 6.3.3 / Xcode 26.6 and Swift 6.4 / Xcode 27, preserves the exact Swift 6.3.3 executable, records the prepared identity, then runs all scenario/capacity smoke and resource probes. It also runs the S01-S06 synthetic selection tests and verifies the missing-idle refusal. It never invokes a timed sample.

The separate `smoke` mode may be used once with the same prepared output directory. For a later authorized timing campaign, use that prepared directory only after confirming Mac idleness:

```sh
DUCK_BENCHMARK_MAC_IDLE=YES \
  bash Benchmarks/V11Wave03B/run-wave03b.sh \
  .artifacts/handoff/v1-1-wave03b-benchmark-preparation-2026-11-22/preparation-evidence/run-01 \
  time
```

The runner uses only the preserved Swift 6.3.3 Release executable, starts seven fresh-process rounds per scenario/capacity, rotates capacities deterministically, and wraps each sample in `/usr/bin/time -l`. It checks Product, harness, binary, and prepared-run identities immediately before every sample. Raw JSON and time stderr remain paired by a unique scenario/capacity/round identity. `finalize` validates the exact 5 × 4 × 7 matrix and applies the frozen PRIMARY selection rule.

## Scenarios and lanes

| Scenario | Workload | Timed operations |
| --- | --- | ---: |
| `Q01_SMALL_READ_SEQ` | One scalar `SELECT` per canonical checkout | 1,000 |
| `Q02_SMALL_READ_CONCURRENT` | Eight structured workers; scalar read per checkout | 1,000 total |
| `W01_MIXED_SHORT_RW_CONCURRENT` | Eight workers update and read their own deterministic row | 800 total |
| `T01_TRANSACTION_SEQ` | Managed transaction with update and in-transaction read | 100 |
| `P01_APPENDER_BATCH_SEQ` | One scoped Appender per operation, 64 deterministic rows | 30 |

Every scenario uses `C_CANONICAL_1`, `C_CANONICAL_2`, `C_CANONICAL_4`, and `C_CANONICAL_8`. Setup, fixture creation, warmup, Appender row-array preparation, final content checks, JSON output, and shutdown are outside measured operation intervals. Total operation latency starts before `Database.connection` and ends after lease return cleanup; checkout wait ends at entry to the closure.

## Resource and selection evidence

Each smoke/resource probe records before/after SPI snapshots, opened-core and retirement deltas, quiescent pool state, expected and observed checkout counts, and the maximum simultaneously borrowed canonical closures. It verifies reuse on repeated workloads and that all core and borrow counts stay within lane capacity.

The production selector chooses the smallest capacity meeting the contract's throughput, p95 latency, correctness, and resource thresholds. If capacity 8 is the only qualifier while the 4-to-8 frontier still improves beyond the boundary threshold, the result requires a separately authorized capacity-16 extension. The selector is exercised by deterministic S01-S06 synthetic cases before preparation passes.

`PRESELECTION_PRODUCT_MANIFEST.json` freezes the accepted uncommitted Product/test input and the harness. Its own hash is omitted from its file map to avoid recursive self-hashing; the manifest remains required in the exact seven-file harness set and is independently validated before build, time, or finalize work. A harness-only HEAD commit may change the prepared HEAD while the frozen Product/test identities remain fixed.
