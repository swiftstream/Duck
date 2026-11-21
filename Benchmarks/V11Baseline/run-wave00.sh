#!/usr/bin/env bash
set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPOSITORY_DIR="$(cd "$PACKAGE_DIR/../.." && pwd -P)"
SUMMARIZER="$PACKAGE_DIR/summarize.py"
SWIFT_6_3_3_DEVELOPER="/Applications/Xcode-26-6.app/Contents/Developer"
SWIFT_6_4_DEVELOPER="/Applications/Xcode-27.app/Contents/Developer"
SCRATCH_6_3_3="$PACKAGE_DIR/.build/wave00-correction02/swift-6.3.3"
SCRATCH_6_4="$PACKAGE_DIR/.build/wave00-correction02/swift-6.4"
SCRATCH_RELATIVE_6_3_3=".build/wave00-correction02/swift-6.3.3"
SCRATCH_RELATIVE_6_4=".build/wave00-correction02/swift-6.4"

usage() {
    printf 'Usage: %s OUTPUT_DIRECTORY prepare|smoke|time\n' "$0" >&2
    exit 2
}

[[ "$#" -eq 2 ]] || usage
OUTPUT_ARGUMENT="$1"
MODE="$2"
[[ "$MODE" == "prepare" || "$MODE" == "smoke" || "$MODE" == "time" ]] || usage
[[ -f "$PACKAGE_DIR/Package.swift" && -f "$SUMMARIZER" ]] || {
    printf 'Wave 00 package or summarizer is missing.\n' >&2
    exit 2
}

mkdir -p "$OUTPUT_ARGUMENT"
OUTPUT_DIR="$(cd "$OUTPUT_ARGUMENT" && pwd -P)"
IDENTITY_FILE="$OUTPUT_DIR/PREPARED_RUN_IDENTITY.json"
IDENTITY_SHA_FILE="$OUTPUT_DIR/PREPARED_RUN_IDENTITY_SHA256.txt"
case "$OUTPUT_DIR/" in
    "$PACKAGE_DIR/"*)
        printf 'Refusing to write benchmark results inside tracked Benchmarks/V11Baseline.\n' >&2
        exit 2
        ;;
esac

fail_if_exists() {
    local path="$1"
    if [[ -e "$path" ]]; then
        printf 'Refusing to overwrite existing evidence: %s\n' "$path" >&2
        exit 2
    fi
}

append_command_header() {
    local path="$1"
    local label="$2"
    printf '\n===== %s =====\n' "$label" >> "$path"
}

capture_host_snapshot() {
    local path="$1"
    {
        printf 'captured_utc='
        date -u '+%Y-%m-%dT%H:%M:%SZ'
        printf 'uptime='
        uptime
        printf 'loadavg='
        sysctl -n vm.loadavg 2>/dev/null || true
    } > "$path"
}

verify_prepared_identity() {
    local binary="$1"
    local values
    values="$(python3 "$SUMMARIZER" verify-identity \
        --repository "$REPOSITORY_DIR" \
        --package "$PACKAGE_DIR" \
        --binary "$binary" \
        --identity "$IDENTITY_FILE" \
        --sha-file "$IDENTITY_SHA_FILE" \
        --emit-values)"
    local identity_sha binary_sha fence_sha
    IFS=$'\t' read -r identity_sha binary_sha fence_sha <<< "$values"
    [[ "$identity_sha" =~ ^[0-9a-f]{64}$ && "$binary_sha" =~ ^[0-9a-f]{64}$ && "$fence_sha" =~ ^[0-9a-f]{64}$ ]] || {
        printf 'Prepared identity verifier returned malformed values.\n' >&2
        exit 1
    }
    export DUCK_BENCHMARK_PREPARED_RUN_IDENTITY_SHA256="$identity_sha"
    export DUCK_BENCHMARK_PREPARED_BINARY_SHA256="$binary_sha"
    export DUCK_BENCHMARK_PRODUCT_INPUT_FENCE_SHA256="$fence_sha"
    printf 'PRODUCT_INPUT_FENCE=PASS productInputFenceSHA256=%s\n' "$fence_sha"
    printf 'PREPARED_IDENTITY=PASS preparedRunIdentitySHA256=%s\n' "$identity_sha"
    printf 'BINARY_IDENTITY=PASS preparedBinarySHA256=%s\n' "$binary_sha"
    printf 'SQL_CHECKOUT_IDENTITY=PASS revision=b0c81191c3494d91b84b5382092e99c64d5c4647 scratchCheckouts=2\n'
}

verify_build_inputs() {
    local log_path="$1"
    shift
    python3 "$SUMMARIZER" verify-build-inputs \
        --repository "$REPOSITORY_DIR" \
        --package "$PACKAGE_DIR" \
        --output-dir "$OUTPUT_DIR" \
        "$@" | tee -a "$log_path"
}

prepared_binary() {
    python3 - "$IDENTITY_FILE" <<'PY'
import json
import sys
from pathlib import Path
identity = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(identity["releaseBinary"]["path"])
PY
}

find_primary_binary() {
    local binary_directory
    binary_directory="$(DEVELOPER_DIR="$SWIFT_6_3_3_DEVELOPER" /usr/bin/xcrun swift build \
        --package-path "$PACKAGE_DIR" \
        --scratch-path "$SCRATCH_6_3_3" \
        --configuration release \
        --show-bin-path)"
    printf '%s/DuckV11Baseline\n' "$binary_directory"
}

verify_negative_idle_guard() {
    local refusal_output
    local refusal_status=0
    refusal_output="$(env DUCK_BENCHMARK_MAC_IDLE= "$0" "$REPOSITORY_DIR" time 2>&1)" || refusal_status=$?
    if [[ "$refusal_status" != "3" || "$refusal_output" != *"REFUSING TO RUN TIMED BENCHMARK SAMPLES"* || \
          "$refusal_output" != *"No timing sample has been started by this runner invocation."* ]]; then
        printf 'Negative idle guard did not refuse the time command before sample execution.\n' >&2
        exit 1
    fi
    printf 'NEGATIVE_IDLE_GUARD=PASS missing idle assertion refused before any sample.\n' >> "$OUTPUT_DIR/SMOKE.log"
}

write_environment() {
    fail_if_exists "$OUTPUT_DIR/ENVIRONMENT.md"
    {
        printf '# Correction 02 Environment\n\n'
        printf 'MAINTAINER_ASSERTED_MAC_IDLE=YES\n\n'
        printf 'The maintainer supplied the exact `MAC_IDLE_ASSERTION=YES` line in the stage invocation. Host load snapshots are supplementary and are not used to infer idleness.\n\n'
        printf 'Host OS: '
        /usr/bin/sw_vers -productVersion
        printf 'Host architecture: '
        /usr/bin/uname -m
        printf 'Build/timing toolchain: Xcode 26.6, Swift 6.3.3 at `%s`.\n' "$SWIFT_6_3_3_DEVELOPER"
        printf 'Compatibility toolchain: Xcode 27.0, Swift 6.4 at `%s`.\n' "$SWIFT_6_4_DEVELOPER"
        printf 'Correction build scratch: `%s` and `%s`.\n' "$SCRATCH_6_3_3" "$SCRATCH_6_4"
        printf 'Attempt 01 and Correction 01 samples are separate, superseded, and neither packet contributes inputs to Correction 02.\n'
    } > "$OUTPUT_DIR/ENVIRONMENT.md"
}

run_prepare() {
    if [[ -e "$SCRATCH_6_3_3" || -e "$SCRATCH_6_4" ]]; then
        printf 'Correction 02 scratch paths must be new and empty before the build gates.\n' >&2
        exit 2
    fi
    fail_if_exists "$OUTPUT_DIR/PRE_BUILD_PRODUCT_INPUT_FENCE.json"
    fail_if_exists "$OUTPUT_DIR/PRE_BUILD_PRODUCT_INPUT_FENCE_SHA256.txt"
    fail_if_exists "$OUTPUT_DIR/BUILD_SWIFT_6_3_3.log"
    fail_if_exists "$OUTPUT_DIR/BUILD_SWIFT_6_4.log"
    fail_if_exists "$OUTPUT_DIR/SMOKE.log"
    fail_if_exists "$OUTPUT_DIR/RESOURCE_PROBES.ndjson"
    fail_if_exists "$OUTPUT_DIR/PREPARED_RUN_IDENTITY.json"
    fail_if_exists "$OUTPUT_DIR/PREPARED_RUN_IDENTITY_SHA256.txt"
    fail_if_exists "$OUTPUT_DIR/PREPARED_BINARY_COPY.log"
    fail_if_exists "$OUTPUT_DIR/PREPARED_BINARY"
    fail_if_exists "$OUTPUT_DIR/HARNESS_IDENTITIES.md"
    fail_if_exists "$OUTPUT_DIR/ENVIRONMENT.md"

    python3 "$SUMMARIZER" create-product-fence \
        --repository "$REPOSITORY_DIR" \
        --package "$PACKAGE_DIR" \
        --output-dir "$OUTPUT_DIR" | tee "$OUTPUT_DIR/BUILD_SWIFT_6_3_3.log"

    {
        printf 'Command: DEVELOPER_DIR=%s /usr/bin/xcrun swiftc -version\n' "$SWIFT_6_3_3_DEVELOPER"
        DEVELOPER_DIR="$SWIFT_6_3_3_DEVELOPER" /usr/bin/xcrun swiftc -version
        printf '\nCommand: DEVELOPER_DIR=%s /usr/bin/xcrun swift --version\n' "$SWIFT_6_3_3_DEVELOPER"
        DEVELOPER_DIR="$SWIFT_6_3_3_DEVELOPER" /usr/bin/xcrun swift --version
        printf '\nCommand: DEVELOPER_DIR=%s xcodebuild -version\n' "$SWIFT_6_3_3_DEVELOPER"
        DEVELOPER_DIR="$SWIFT_6_3_3_DEVELOPER" xcodebuild -version
    } >> "$OUTPUT_DIR/BUILD_SWIFT_6_3_3.log" 2>&1
    {
        printf '\nCommand: DEVELOPER_DIR=%s /usr/bin/xcrun swift package resolve --package-path %s --scratch-path %s\n' "$SWIFT_6_3_3_DEVELOPER" "$PACKAGE_DIR" "$SCRATCH_6_3_3"
        DEVELOPER_DIR="$SWIFT_6_3_3_DEVELOPER" /usr/bin/xcrun swift package resolve \
            --package-path "$PACKAGE_DIR" \
            --scratch-path "$SCRATCH_6_3_3"
    } 2>&1 | tee -a "$OUTPUT_DIR/BUILD_SWIFT_6_3_3.log"
    verify_build_inputs "$OUTPUT_DIR/BUILD_SWIFT_6_3_3.log" \
        --scratch-relative "$SCRATCH_RELATIVE_6_3_3"
    {
        printf '\nCommand: DEVELOPER_DIR=%s /usr/bin/xcrun swift build -c release --scratch-path %s\n' "$SWIFT_6_3_3_DEVELOPER" "$SCRATCH_6_3_3"
        DEVELOPER_DIR="$SWIFT_6_3_3_DEVELOPER" /usr/bin/xcrun swift build \
            --package-path "$PACKAGE_DIR" \
            --scratch-path "$SCRATCH_6_3_3" \
            --configuration release
    } 2>&1 | tee -a "$OUTPUT_DIR/BUILD_SWIFT_6_3_3.log"

    {
        printf 'Command: DEVELOPER_DIR=%s /usr/bin/xcrun swiftc -version\n' "$SWIFT_6_4_DEVELOPER"
        DEVELOPER_DIR="$SWIFT_6_4_DEVELOPER" /usr/bin/xcrun swiftc -version
        printf '\nCommand: DEVELOPER_DIR=%s /usr/bin/xcrun swift --version\n' "$SWIFT_6_4_DEVELOPER"
        DEVELOPER_DIR="$SWIFT_6_4_DEVELOPER" /usr/bin/xcrun swift --version
        printf '\nCommand: DEVELOPER_DIR=%s xcodebuild -version\n' "$SWIFT_6_4_DEVELOPER"
        DEVELOPER_DIR="$SWIFT_6_4_DEVELOPER" xcodebuild -version
    } > "$OUTPUT_DIR/BUILD_SWIFT_6_4.log" 2>&1
    {
        printf '\nCommand: DEVELOPER_DIR=%s /usr/bin/xcrun swift package resolve --package-path %s --scratch-path %s\n' "$SWIFT_6_4_DEVELOPER" "$PACKAGE_DIR" "$SCRATCH_6_4"
        DEVELOPER_DIR="$SWIFT_6_4_DEVELOPER" /usr/bin/xcrun swift package resolve \
            --package-path "$PACKAGE_DIR" \
            --scratch-path "$SCRATCH_6_4"
    } 2>&1 | tee -a "$OUTPUT_DIR/BUILD_SWIFT_6_4.log"
    verify_build_inputs "$OUTPUT_DIR/BUILD_SWIFT_6_4.log" \
        --scratch-relative "$SCRATCH_RELATIVE_6_4"
    {
        printf '\nCommand: DEVELOPER_DIR=%s /usr/bin/xcrun swift build -c release --scratch-path %s (compile-only compatibility gate)\n' "$SWIFT_6_4_DEVELOPER" "$SCRATCH_6_4"
        DEVELOPER_DIR="$SWIFT_6_4_DEVELOPER" /usr/bin/xcrun swift build \
            --package-path "$PACKAGE_DIR" \
            --scratch-path "$SCRATCH_6_4" \
            --configuration release
    } 2>&1 | tee -a "$OUTPUT_DIR/BUILD_SWIFT_6_4.log"

    verify_build_inputs "$OUTPUT_DIR/BUILD_SWIFT_6_4.log" \
        --scratch-relative "$SCRATCH_RELATIVE_6_3_3" \
        --scratch-relative "$SCRATCH_RELATIVE_6_4"
    local build_binary
    build_binary="$(find_primary_binary)"
    [[ -x "$build_binary" ]] || {
        printf 'Swift 6.3.3 Release executable is missing: %s\n' "$build_binary" >&2
        exit 1
    }
    python3 "$SUMMARIZER" preserve-binary \
        --source "$build_binary" \
        --destination "$OUTPUT_DIR/PREPARED_BINARY/DuckV11Baseline" | tee "$OUTPUT_DIR/PREPARED_BINARY_COPY.log"
    local binary="$OUTPUT_DIR/PREPARED_BINARY/DuckV11Baseline"
    export DUCK_BENCHMARK_REPOSITORY="$REPOSITORY_DIR"
    export DEVELOPER_DIR="$SWIFT_6_3_3_DEVELOPER"
    write_environment
    python3 "$SUMMARIZER" create-identity \
        --repository "$REPOSITORY_DIR" \
        --package "$PACKAGE_DIR" \
        --binary "$binary" \
        --identity "$IDENTITY_FILE" \
        --sha-file "$IDENTITY_SHA_FILE"
    verify_prepared_identity "$binary"
    python3 "$SUMMARIZER" harness-identities \
        --repository "$REPOSITORY_DIR" \
        --package "$PACKAGE_DIR" \
        --output "$OUTPUT_DIR/HARNESS_IDENTITIES.md"

    run_smoke_and_resource_probes "$binary"
    verify_negative_idle_guard
}

run_smoke_only() {
    [[ -f "$OUTPUT_DIR/BUILD_SWIFT_6_3_3.log" && -f "$OUTPUT_DIR/BUILD_SWIFT_6_4.log" ]] || {
        printf 'Refusing smoke continuation: both toolchain build logs are required.\n' >&2
        exit 2
    }
    fail_if_exists "$OUTPUT_DIR/SMOKE.log"
    fail_if_exists "$OUTPUT_DIR/RESOURCE_PROBES.ndjson"
    local binary
    binary="$(prepared_binary)"
    [[ -x "$binary" ]] || {
        printf 'Swift 6.3.3 Release executable is missing: %s\n' "$binary" >&2
        exit 1
    }
    export DUCK_BENCHMARK_REPOSITORY="$REPOSITORY_DIR"
    export DEVELOPER_DIR="$SWIFT_6_3_3_DEVELOPER"
    verify_prepared_identity "$binary"
    run_smoke_and_resource_probes "$binary"
    verify_negative_idle_guard
}

run_smoke_and_resource_probes() {
    local binary="$1"
    : > "$OUTPUT_DIR/SMOKE.log"
    run_smoke_scenario "$binary" Q01_SMALL_READ_SEQ A_ORDINARY B_POOL_1 B_POOL_4
    run_smoke_scenario "$binary" Q02_SMALL_READ_CONCURRENT A_ORDINARY B_POOL_1 B_POOL_4 B_POOL_8
    run_smoke_scenario "$binary" T01_TRANSACTION_SEQ A_ORDINARY B_POOL_1 B_POOL_4
    run_smoke_scenario "$binary" P01_APPENDER_BATCH_SEQ A_ORDINARY B_POOL_1 B_POOL_4
    run_smoke_probe "$binary" R01_CONNECTION_IDENTITY A_FRESH_EXPLICIT
    run_smoke_probe "$binary" R01_CONNECTION_IDENTITY B_POOL_4

    : > "$OUTPUT_DIR/RESOURCE_PROBES.ndjson"
    run_resource_probe "$binary" Q01_SMALL_READ_SEQ B_POOL_1
    run_resource_probe "$binary" Q01_SMALL_READ_SEQ B_POOL_4
    run_resource_probe "$binary" Q02_SMALL_READ_CONCURRENT B_POOL_1
    run_resource_probe "$binary" Q02_SMALL_READ_CONCURRENT B_POOL_4
    run_resource_probe "$binary" Q02_SMALL_READ_CONCURRENT B_POOL_8
    run_resource_probe "$binary" P01_APPENDER_BATCH_SEQ B_POOL_1
    run_resource_probe "$binary" P01_APPENDER_BATCH_SEQ B_POOL_4
    run_resource_probe "$binary" R01_CONNECTION_IDENTITY A_FRESH_EXPLICIT
    run_resource_probe "$binary" R01_CONNECTION_IDENTITY B_POOL_4
    python3 "$SUMMARIZER" validate-resources --path "$OUTPUT_DIR/RESOURCE_PROBES.ndjson" >> "$OUTPUT_DIR/SMOKE.log"
    python3 "$SUMMARIZER" selftest-r01 >> "$OUTPUT_DIR/SMOKE.log"
    verify_prepared_identity "$binary" >> "$OUTPUT_DIR/SMOKE.log"
    printf 'SMOKE_ACCEPTANCE=PASS\n' >> "$OUTPUT_DIR/SMOKE.log"
    printf 'Prepare gates complete. Swift 6.3.3 executable: %s\n' "$binary"
}

run_smoke_scenario() {
    local binary="$1"
    local scenario="$2"
    shift 2
    local lane
    local stdout_file="$OUTPUT_DIR/.smoke.stdout"
    local stderr_file="$OUTPUT_DIR/.smoke.stderr"
    for lane in "$@"; do
        append_command_header "$OUTPUT_DIR/SMOKE.log" "UNTIMED sample $scenario $lane 0"
        verify_prepared_identity "$binary" >> "$OUTPUT_DIR/SMOKE.log"
        "$binary" sample "$scenario" "$lane" 0 > "$stdout_file" 2> "$stderr_file"
        python3 "$SUMMARIZER" validate-sample "$stdout_file" sample "$scenario" "$lane" 0
        cat "$stdout_file" >> "$OUTPUT_DIR/SMOKE.log"
        if [[ -s "$stderr_file" ]]; then
            printf 'stderr:\n' >> "$OUTPUT_DIR/SMOKE.log"
            cat "$stderr_file" >> "$OUTPUT_DIR/SMOKE.log"
        fi
        rm -f "$stdout_file" "$stderr_file"
    done
}

run_smoke_probe() {
    local binary="$1"
    local scenario="$2"
    local lane="$3"
    local stdout_file="$OUTPUT_DIR/.smoke.stdout"
    local stderr_file="$OUTPUT_DIR/.smoke.stderr"
    append_command_header "$OUTPUT_DIR/SMOKE.log" "UNTIMED structural probe $scenario $lane"
    verify_prepared_identity "$binary" >> "$OUTPUT_DIR/SMOKE.log"
    "$binary" probe "$scenario" "$lane" > "$stdout_file" 2> "$stderr_file"
    python3 "$SUMMARIZER" validate-sample "$stdout_file" probe "$scenario" "$lane"
    cat "$stdout_file" >> "$OUTPUT_DIR/SMOKE.log"
    if [[ -s "$stderr_file" ]]; then
        printf 'stderr:\n' >> "$OUTPUT_DIR/SMOKE.log"
        cat "$stderr_file" >> "$OUTPUT_DIR/SMOKE.log"
    fi
    rm -f "$stdout_file" "$stderr_file"
}

run_resource_probe() {
    local binary="$1"
    local scenario="$2"
    local lane="$3"
    local stdout_file="$OUTPUT_DIR/.resource.stdout"
    local stderr_file="$OUTPUT_DIR/.resource.stderr"
    verify_prepared_identity "$binary" >> "$OUTPUT_DIR/SMOKE.log"
    "$binary" probe "$scenario" "$lane" > "$stdout_file" 2> "$stderr_file"
    python3 "$SUMMARIZER" validate-sample "$stdout_file" probe "$scenario" "$lane"
    cat "$stdout_file" >> "$OUTPUT_DIR/RESOURCE_PROBES.ndjson"
    if [[ -s "$stderr_file" ]]; then
        append_command_header "$OUTPUT_DIR/SMOKE.log" "RESOURCE probe stderr $scenario $lane"
        cat "$stderr_file" >> "$OUTPUT_DIR/SMOKE.log"
    fi
    rm -f "$stdout_file" "$stderr_file"
}

run_time() {
    if [[ "${DUCK_BENCHMARK_MAC_IDLE:-}" != "YES" ]]; then
        cat >&2 <<'REFUSAL'
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
REFUSING TO RUN TIMED BENCHMARK SAMPLES

The required maintainer idle assertion is absent.
Set DUCK_BENCHMARK_MAC_IDLE=YES only after confirming the Mac is idle.
Load snapshots are supplementary and cannot replace that assertion.
No timing sample has been started by this runner invocation.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
REFUSAL
        exit 3
    fi
    [[ -f "$OUTPUT_DIR/BUILD_SWIFT_6_3_3.log" && -f "$OUTPUT_DIR/BUILD_SWIFT_6_4.log" && -f "$OUTPUT_DIR/SMOKE.log" ]] || {
        printf 'Refusing timing: prepare build/smoke evidence is incomplete.\n' >&2
        exit 2
    }
    for marker in \
        'RESOURCE_PROBES=PASS' \
        'R01_A_PRODUCTION_VALIDATOR_SELFTEST=PASS' \
        'SMOKE_ACCEPTANCE=PASS' \
        'NEGATIVE_IDLE_GUARD=PASS'; do
        if ! /usr/bin/grep -Fq "$marker" "$OUTPUT_DIR/SMOKE.log"; then
            printf 'Refusing timing: prepare evidence is missing %s.\n' "$marker" >&2
            exit 2
        fi
    done
    [[ -s "$OUTPUT_DIR/RESOURCE_PROBES.ndjson" ]] || {
        printf 'Refusing timing: the validated resource probe packet is missing.\n' >&2
        exit 2
    }
    [[ ! -e "$OUTPUT_DIR/RAW_SAMPLES.ndjson" && ! -e "$OUTPUT_DIR/RUN_ORDER.txt" && ! -e "$OUTPUT_DIR/resource-logs" ]] || {
        printf 'Refusing to overwrite or mix an existing timing run.\n' >&2
        exit 2
    }
    for path in TIMING_ASSERTION.log POST_TIMING_IDENTITY_CHECK.md SUMMARY.json SUMMARY.md CHEAP_CHECKS.md EVIDENCE_IDENTITIES.md; do
        fail_if_exists "$OUTPUT_DIR/$path"
    done

    local binary
    binary="$(prepared_binary)"
    [[ -x "$binary" ]] || {
        printf 'Refusing timing: Swift 6.3.3 Release executable is missing: %s\n' "$binary" >&2
        exit 2
    }
    export DUCK_BENCHMARK_REPOSITORY="$REPOSITORY_DIR"
    export DEVELOPER_DIR="$SWIFT_6_3_3_DEVELOPER"
    verify_prepared_identity "$binary"
    printf 'MAINTAINER_ASSERTED_MAC_IDLE=YES\n' > "$OUTPUT_DIR/TIMING_ASSERTION.log"

    : > "$OUTPUT_DIR/RUN_ORDER.txt"
    run_order_scenario Q01_SMALL_READ_SEQ A_ORDINARY B_POOL_1 B_POOL_4
    run_order_scenario Q02_SMALL_READ_CONCURRENT A_ORDINARY B_POOL_1 B_POOL_4 B_POOL_8
    run_order_scenario T01_TRANSACTION_SEQ A_ORDINARY B_POOL_1 B_POOL_4
    run_order_scenario P01_APPENDER_BATCH_SEQ A_ORDINARY B_POOL_1 B_POOL_4

    capture_host_snapshot "$OUTPUT_DIR/PRE_RUN_HOST_SNAPSHOT.txt"
    : > "$OUTPUT_DIR/RAW_SAMPLES.ndjson"
    mkdir -p "$OUTPUT_DIR/resource-logs"
    time_scenario "$binary" Q01_SMALL_READ_SEQ A_ORDINARY B_POOL_1 B_POOL_4
    time_scenario "$binary" Q02_SMALL_READ_CONCURRENT A_ORDINARY B_POOL_1 B_POOL_4 B_POOL_8
    time_scenario "$binary" T01_TRANSACTION_SEQ A_ORDINARY B_POOL_1 B_POOL_4
    time_scenario "$binary" P01_APPENDER_BATCH_SEQ A_ORDINARY B_POOL_1 B_POOL_4
    capture_host_snapshot "$OUTPUT_DIR/POST_RUN_HOST_SNAPSHOT.txt"

    local sample_count
    sample_count="$(wc -l < "$OUTPUT_DIR/RAW_SAMPLES.ndjson" | tr -d ' ')"
    [[ "$sample_count" == "91" ]] || {
        printf 'Timed suite has %s samples; expected exactly 91.\n' "$sample_count" >&2
        exit 1
    }
    verify_prepared_identity "$binary" > "$OUTPUT_DIR/POST_TIMING_IDENTITY_CHECK.md"
    {
        printf '\nPOST_TIMING_IDENTITY_CHECK=PASS\n'
        printf 'All frozen prepared identities were recomputed and matched immediately after sample 91.\n'
        printf 'preparedRunIdentitySHA256=%s\n' "$DUCK_BENCHMARK_PREPARED_RUN_IDENTITY_SHA256"
        printf 'preparedBinarySHA256=%s\n' "$DUCK_BENCHMARK_PREPARED_BINARY_SHA256"
        printf 'validatedSampleCount=%s\n' "$sample_count"
    } >> "$OUTPUT_DIR/POST_TIMING_IDENTITY_CHECK.md"

    python3 "$SUMMARIZER" summarize \
        --repository "$REPOSITORY_DIR" \
        --raw "$OUTPUT_DIR/RAW_SAMPLES.ndjson" \
        --resources "$OUTPUT_DIR/RESOURCE_PROBES.ndjson" \
        --logs "$OUTPUT_DIR/resource-logs" \
        --output-dir "$OUTPUT_DIR"
    python3 "$SUMMARIZER" cheap-check \
        --repository "$REPOSITORY_DIR" \
        --output-dir "$OUTPUT_DIR" \
        --raw "$OUTPUT_DIR/RAW_SAMPLES.ndjson" \
        --resources "$OUTPUT_DIR/RESOURCE_PROBES.ndjson" \
        --logs "$OUTPUT_DIR/resource-logs" \
        --pre-finalization
    verify_prepared_identity "$binary" >> "$OUTPUT_DIR/POST_TIMING_IDENTITY_CHECK.md"
    printf 'CANONICAL_FINALIZATION_READY=PASS\nEVALUATOR_RECOVERY=NOT_USED\n' >> "$OUTPUT_DIR/TIMING_ASSERTION.log"
    python3 "$SUMMARIZER" evidence-manifest --output-dir "$OUTPUT_DIR"
    python3 "$SUMMARIZER" verify-evidence-manifest --output-dir "$OUTPUT_DIR"
    printf 'Timed Wave 00 suite complete: %s samples.\n' "$(wc -l < "$OUTPUT_DIR/RAW_SAMPLES.ndjson" | tr -d ' ')"
}

run_order_scenario() {
    local scenario="$1"
    shift
    local lanes=("$@")
    local lane_count="${#lanes[@]}"
    local round
    local index
    local lane
    for ((round = 1; round <= 7; round++)); do
        for ((index = 0; index < lane_count; index++)); do
            lane="${lanes[$(((index + round - 1) % lane_count))]}"
            printf '%s\t%s\t%s\n' "$round" "$scenario" "$lane" >> "$OUTPUT_DIR/RUN_ORDER.txt"
        done
    done
}

time_scenario() {
    local binary="$1"
    local scenario="$2"
    shift 2
    local lanes=("$@")
    local lane_count="${#lanes[@]}"
    local round
    local index
    local lane
    local stdout_file="$OUTPUT_DIR/.sample.stdout"
    local log_file
    for ((round = 1; round <= 7; round++)); do
        for ((index = 0; index < lane_count; index++)); do
            lane="${lanes[$(((index + round - 1) % lane_count))]}"
            log_file="$OUTPUT_DIR/resource-logs/${scenario}__${lane}__r${round}.stderr-time.log"
            printf 'round=%s scenario=%s lane=%s\n' "$round" "$scenario" "$lane"
            verify_prepared_identity "$binary" >> "$OUTPUT_DIR/TIMING_ASSERTION.log"
            /usr/bin/time -l "$binary" sample "$scenario" "$lane" "$round" > "$stdout_file" 2> "$log_file"
            python3 "$SUMMARIZER" validate-sample "$stdout_file" sample "$scenario" "$lane" "$round"
            cat "$stdout_file" >> "$OUTPUT_DIR/RAW_SAMPLES.ndjson"
            rm -f "$stdout_file"
        done
    done
}

if [[ "$MODE" == "prepare" ]]; then
    run_prepare
elif [[ "$MODE" == "smoke" ]]; then
    run_smoke_only
else
    run_time
fi
