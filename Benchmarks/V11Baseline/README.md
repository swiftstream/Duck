# Duck v1.1 Wave 00 Baseline

This nested SwiftPM executable freezes the current v1 A/B resource behavior before any v1.1 Product routing changes. It has one direct dependency on the local Duck package, with SQL 3.1.0 fixed by the frozen transitive lock. Duck re-exports SQL, so the executable imports Duck and builds all statements through that SQL API. The runner fences Product inputs before either benchmark build, preserves the exact timed Release executable inside the evidence packet, then binds that evidence-owned binary to the fence, this six-file harness, the Product checkout, dependency lock, and Swift toolchain before accepting samples.

## Idle Mac requirement

**Do not run timed samples unless the Mac is idle.** The measured suite is valid only after the maintainer has confirmed an idle Mac and the runner receives DUCK_BENCHMARK_MAC_IDLE=YES. The runner also records host load snapshots as supplementary context; they do not establish idleness.

## Build, smoke, and timing

Run from the repository root with the exact Xcode installations frozen by Wave 00:

Set `OUTPUT_DIR` once in this shell session. It must be a new path that does not already contain benchmark evidence. Before `prepare`, confirm the path does not exist or is empty; if it already contains anything, choose a different unique path. Use the exact same `OUTPUT_DIR` for `prepare` and `time`.

Never point these canonical commands at Attempt 01, Correction 01, the failed Correction 02 source packet, Repair 01, Repair 02, or any other historical evidence directory. Those packets are immutable records, not run destinations.

    OUTPUT_DIR="$PWD/.artifacts/benchmarks/v1-1-wave00-a-b-baseline-$(date +%Y%m%d-%H%M%S)"
    Benchmarks/V11Baseline/run-wave00.sh "$OUTPUT_DIR" prepare

prepare creates and verifies a deterministic Product input fence before resolving or building the benchmark binary. The package has one direct dependency on local Duck, with SQL fixed by the frozen transitive lock pin. It builds Release under Swift 6.3.3 and runs the Swift 6.4 Release compatibility build, using fresh Correction 02 scratch paths. Before each build, the runner verifies the corresponding resolved SQL checkout and the fenced Product inputs. After both builds and before prepared identity or smoke execution, it copies the exact Swift 6.3.3 Release executable to `PREPARED_BINARY/DuckV11Baseline`, verifies the source/copy SHA-256 and executable mode, then creates the prepared-run identity against the preserved file. Smoke and timing invoke that evidence-owned executable; the evidence manifest includes it. Prepare also validates the actual resource probes, exercises the production R01 validator with synthetic unique counts 37 (pass), 0 (fail), and 101 (fail), and behaviorally checks that time mode refuses a missing idle assertion before any sample can start.

After source and evidence preflight is green, run the measured suite:

    DUCK_BENCHMARK_MAC_IDLE=YES Benchmarks/V11Baseline/run-wave00.sh "$OUTPUT_DIR" time

The timing mode invokes only the preserved Swift 6.3.3 Release executable. It verifies the complete Product fence and prepared identity immediately before every sample, launches each scenario/lane/round in a fresh process, wraps it in /usr/bin/time -l, rotates lane order deterministically, and runs exactly seven rounds. A sample is appended only after its JSON and identity fields validate. After summaries and final cheap checks pass, the runner records `CANONICAL_FINALIZATION_READY=PASS` and `EVALUATOR_RECOVERY=NOT_USED`, creates and verifies the evidence manifest, then prints completion. It does not write a self-certified command-success marker; the command's actual exit status is its success result. Attempt 01 and Correction 01 samples are separate, superseded, and not inputs to this run.

## Scenarios and lanes

| Scenario | Workload | Lanes |
| --- | --- | --- |
| Q01_SMALL_READ_SEQ | 100 warmup, 1,000 measured scalar reads, one worker | A_ORDINARY, B_POOL_1, B_POOL_4 |
| Q02_SMALL_READ_CONCURRENT | 80 total warmup, 1,000 measured scalar reads, eight structured workers | A_ORDINARY, B_POOL_1, B_POOL_4, B_POOL_8 |
| T01_TRANSACTION_SEQ | one counter row; 10 warmup and 100 measured managed transactions | A_ORDINARY, B_POOL_1, B_POOL_4 |
| P01_APPENDER_BATCH_SEQ | one Appender scope per operation, 64 deterministic rows; 3 warmup and 30 measured | A_ORDINARY, B_POOL_1, B_POOL_4 |
| R01_CONNECTION_IDENTITY | 100 retained actor references | A_FRESH_EXPLICIT, B_POOL_4 |

A lanes call the public DatabaseIdentifier convenience for every operation. B read/Appender lanes call ConnectionPool.connection; B transaction lanes call ConnectionPool.transaction. Fixture DDL/population, warmup, deterministic Appender input-array preparation, final post-loop fixture verification, JSON encoding/writing, and summary generation are outside the measured intervals.

The scalar query is constructed with the SQL DSL and returns one integer. Scalar QueryResult validation is inside the operation latency. Transaction SELECT/result validation and transaction finalization/commit are inside transaction operation timing. For Q02, the per-operation percentile endpoint is immediately after scalar QueryResult validation; pooled lanes capture it inside `pool.connection`, before lease-return cleanup. Q02 whole-sample elapsed time and throughput include all worker operations and the complete pool API lifecycle, including return cleanup. For Appender, each Appender scope is timed while deterministic row data is prepared before timing; final row-count/content verification runs after the measured loop.

## Percentiles and checksums

Per-sample and summary latency percentiles use the nearest-rank method: sort the integer nanosecond observations and choose one-based rank ceil(p * N) (bounded to 1...N). The summary reports the median of the seven per-sample p50, p95, and p99 values; throughput min/max and median; median elapsed time per measured operation; and stable checksum agreement. It makes no significance, regression, or improvement claim.

The FNV-1a-style 64-bit digest is a deterministic correctness checksum over validated scalar results, committed counter values, or the fully verified ordered Appender rows. It is not a cryptographic integrity mechanism. File SHA-256 values are recorded separately for evidence identity.

## Resource identity

ObjectIdentifier(Connection) is reported only as a Swift actor object-identity proxy. It is not a native DuckDB pointer or native Connection count. Timed Q/P/T samples do not call a resource collector in their hot path. Separate resource-only probes collect pool checkout count, unique actor objects, and maximum simultaneously active pooled closures where the public API exposes a Connection. R01 retains all returned references through probe completion and reports observed uniqueness; A accepts any count from 1 through 100. B_POOL_4 checks 100 sequential checkouts, 1 through 4 unique actor proxies, and a maximum of one active borrowed closure.

## Output

All outputs go to the caller-provided directory, normally the stage evidence directory under .artifacts/benchmarks/. The runner refuses to place results inside this tracked package. The preserved `PREPARED_BINARY/DuckV11Baseline`, its copy/hash/mode record, and all identity/report files are included in the evidence manifest. `/usr/bin/time -l` stderr/resource output is preserved per sample. `SUMMARY.json` and `SUMMARY.md` are derived from the exact raw NDJSON set and optional resource probes.
