#!/usr/bin/env bash
set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPOSITORY_DIR="$(cd "$PACKAGE_DIR/../.." && pwd -P)"
EVIDENCE_ROOT="$REPOSITORY_DIR/.artifacts/handoff/v1-1-wave03b-benchmark-preparation-2026-11-22"
SUMMARIZER="$PACKAGE_DIR/summarize.py"
DEVELOPER_6_3_3="/Applications/Xcode-26-6.app/Contents/Developer"
DEVELOPER_6_4="/Applications/Xcode-27.app/Contents/Developer"
SCENARIOS=(
    Q01_SMALL_READ_SEQ
    Q02_SMALL_READ_CONCURRENT
    W01_MIXED_SHORT_RW_CONCURRENT
    T01_TRANSACTION_SEQ
    P01_APPENDER_BATCH_SEQ
)
CAPACITIES=(1 2 4 8)

usage() {
    printf 'Usage: %s OUTPUT_DIRECTORY prepare|smoke|time|finalize\n' "$0" >&2
    exit 2
}

if [[ "$#" -ne 2 ]]; then
    usage
fi

OUTPUT_ARGUMENT="$1"
MODE="$2"
case "$MODE" in
    prepare|smoke|time|finalize) ;;
    *) usage ;;
esac

# This check intentionally precedes output-path resolution, directory creation,
# identity reads, and every possible sample-file operation.
if [[ "$MODE" == "time" && "${DUCK_BENCHMARK_MAC_IDLE:-}" != "YES" ]]; then
    printf 'REFUSING TO RUN TIMED BENCHMARK SAMPLES\n' >&2
    printf 'No timing sample has been started by this runner invocation.\n' >&2
    exit 3
fi

OUTPUT_DIR="$(cd "$(dirname "$OUTPUT_ARGUMENT")" && pwd -P)/$(basename "$OUTPUT_ARGUMENT")"
RUN_TAG="$(basename "$OUTPUT_DIR")"
RAW_DIR="$EVIDENCE_ROOT/raw/$RUN_TAG"
SCRATCH_6_3_3="$OUTPUT_DIR/SCRATCH_SWIFT_6_3_3"
SCRATCH_6_4="$OUTPUT_DIR/SCRATCH_SWIFT_6_4"

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

require_manifest() {
    python3 "$SUMMARIZER" verify-manifest
}

identity_environment() {
    local values
    values="$(python3 "$SUMMARIZER" identity-values --output "$OUTPUT_DIR")"
    IFS=$'\t' read -r DUCK_BENCHMARK_PRODUCT_MANIFEST_SHA256 \
        DUCK_BENCHMARK_PREPARED_RUN_IDENTITY_SHA256 \
        DUCK_BENCHMARK_PREPARED_BINARY_SHA256 \
        DUCK_BENCHMARK_PREPARED_HEAD \
        DUCK_BENCHMARK_PREPARED_BINARY_PATH <<< "$values"
    export DUCK_BENCHMARK_PRODUCT_MANIFEST_SHA256
    export DUCK_BENCHMARK_PREPARED_RUN_IDENTITY_SHA256
    export DUCK_BENCHMARK_PREPARED_BINARY_SHA256
    export DUCK_BENCHMARK_PREPARED_HEAD
    export DUCK_BENCHMARK_REPOSITORY="$REPOSITORY_DIR"
}

fresh_output_directory() {
    if [[ -e "$OUTPUT_DIR" ]]; then
        if [[ ! -d "$OUTPUT_DIR" || -n "$(/usr/bin/find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
            fail "Refusing non-fresh output directory: $OUTPUT_DIR"
        fi
    fi
    if [[ -e "$RAW_DIR" ]]; then
        fail "Refusing non-fresh raw evidence directory: $RAW_DIR"
    fi
    mkdir -p "$OUTPUT_DIR" "$RAW_DIR"
}

write_toolchain_log() {
    local developer_dir="$1"
    local expected_swift="$2"
    local expected_xcode="$3"
    local output="$4"
    {
        printf 'DEVELOPER_DIR=%s\n' "$developer_dir"
        printf 'Command: DEVELOPER_DIR=%s /usr/bin/xcrun swift --version\n' "$developer_dir"
        DEVELOPER_DIR="$developer_dir" /usr/bin/xcrun swift --version
        printf '\nCommand: DEVELOPER_DIR=%s xcodebuild -version\n' "$developer_dir"
        DEVELOPER_DIR="$developer_dir" xcodebuild -version
    } > "$output" 2>&1
    rg -q "Swift version $expected_swift|Apple Swift version $expected_swift" "$output" || fail "Expected Swift $expected_swift in $output"
    rg -q "Xcode $expected_xcode" "$output" || fail "Expected Xcode $expected_xcode in $output"
}

capture_command() {
    local log_path="$1"
    shift
    {
        printf '\n$'
        printf ' %q' "$@"
        printf '\n'
        "$@"
    } 2>&1 | tee -a "$log_path"
}

write_sha_sidecar() {
    local file="$1"
    local sidecar="$2"
    python3 - "$file" "$sidecar" <<'PY'
from pathlib import Path
import hashlib
import sys
source = Path(sys.argv[1])
destination = Path(sys.argv[2])
destination.write_text(f"{hashlib.sha256(source.read_bytes()).hexdigest()}  {source.name}\n")
PY
}

run_smoke_matrix() {
    local binary="$1"
    local smoke_output_dir="$2"
    local smoke_raw_dir="$3"
    local smoke_log="$smoke_output_dir/SMOKE.log"
    local probes="$smoke_output_dir/RESOURCE_PROBES.ndjson"
    [[ ! -e "$smoke_log" && ! -e "$probes" ]] || fail "Refusing to overwrite existing smoke/resource evidence"
    : > "$smoke_log"
    : > "$probes"
    for scenario in "${SCENARIOS[@]}"; do
        for capacity in "${CAPACITIES[@]}"; do
            python3 "$SUMMARIZER" verify-identity --output "$OUTPUT_DIR" >> "$smoke_raw_dir/IDENTITY_CHECKS.log"
            "$binary" smoke "$scenario" "$capacity" >> "$probes"
            printf 'SMOKE_RESOURCE_PASS scenario=%s lane=C_CANONICAL_%s\n' "$scenario" "$capacity" | tee -a "$smoke_log" "$smoke_raw_dir/SMOKE.log"
        done
    done
    python3 "$SUMMARIZER" validate-probes --path "$probes" --output "$smoke_output_dir/RESOURCE_PROBES.md" \
        --prepared-output "$OUTPUT_DIR" | tee -a "$smoke_log" "$smoke_raw_dir/SMOKE.log"
    cp "$probes" "$smoke_raw_dir/RESOURCE_PROBES.ndjson"
    write_sha_sidecar "$probes" "$smoke_output_dir/RESOURCE_PROBES_SHA256.txt"
    cp "$smoke_output_dir/RESOURCE_PROBES_SHA256.txt" "$smoke_raw_dir/RESOURCE_PROBES_SHA256.txt"
}

verify_negative_idle_guard() {
    local refusal_output
    local refusal_status=0
    refusal_output="$(env -u DUCK_BENCHMARK_MAC_IDLE bash "$0" "$OUTPUT_DIR" time 2>&1)" || refusal_status=$?
    if [[ "$refusal_status" -ne 3 || "$refusal_output" != *"REFUSING TO RUN TIMED BENCHMARK SAMPLES"* || \
          "$refusal_output" != *"No timing sample has been started by this runner invocation."* ]]; then
        fail "negative idle guard did not emit the exact refusal before sample execution"
    fi
    if [[ -e "$OUTPUT_DIR/RAW_SAMPLES.ndjson" || -e "$RAW_DIR/RAW_SAMPLES.ndjson" || \
          -e "$OUTPUT_DIR/SAMPLE_LOG_MANIFEST.json" ]]; then
        fail "negative idle guard created sample evidence"
    fi
    printf '%s\n' "$refusal_output" > "$OUTPUT_DIR/NEGATIVE_IDLE_GUARD.log"
    printf 'NEGATIVE_IDLE_GUARD=PASS; refusal preceded all sample-file creation.\n' >> "$OUTPUT_DIR/SMOKE.log"
    cp "$OUTPUT_DIR/NEGATIVE_IDLE_GUARD.log" "$RAW_DIR/NEGATIVE_IDLE_GUARD.log"
}

run_prepare() {
    require_manifest
    fresh_output_directory
    local log633="$OUTPUT_DIR/BUILD_SWIFT_6_3_3.log"
    local log64="$OUTPUT_DIR/BUILD_SWIFT_6_4.log"
    local raw633="$RAW_DIR/BUILD_SWIFT_6_3_3.log"
    local raw64="$RAW_DIR/BUILD_SWIFT_6_4.log"

    write_toolchain_log "$DEVELOPER_6_3_3" "6.3.3" "26.6" "$OUTPUT_DIR/TOOLCHAIN_SWIFT_6_3_3.log"
    write_toolchain_log "$DEVELOPER_6_4" "6.4" "27.0" "$OUTPUT_DIR/TOOLCHAIN_SWIFT_6_4.log"
    cp "$OUTPUT_DIR/TOOLCHAIN_SWIFT_6_3_3.log" "$RAW_DIR/TOOLCHAIN_SWIFT_6_3_3.log"
    cp "$OUTPUT_DIR/TOOLCHAIN_SWIFT_6_4.log" "$RAW_DIR/TOOLCHAIN_SWIFT_6_4.log"
    : > "$log633"
    : > "$log64"
    cp "$log633" "$raw633"
    cp "$log64" "$raw64"

    capture_command "$log633" env DEVELOPER_DIR="$DEVELOPER_6_3_3" /usr/bin/xcrun swift package resolve \
        --package-path "$PACKAGE_DIR" --scratch-path "$SCRATCH_6_3_3"
    python3 "$SUMMARIZER" verify-manifest
    capture_command "$log633" env DEVELOPER_DIR="$DEVELOPER_6_3_3" /usr/bin/xcrun swift build \
        --package-path "$PACKAGE_DIR" --scratch-path "$SCRATCH_6_3_3" --configuration release
    python3 "$SUMMARIZER" verify-manifest

    capture_command "$log64" env DEVELOPER_DIR="$DEVELOPER_6_4" /usr/bin/xcrun swift package resolve \
        --package-path "$PACKAGE_DIR" --scratch-path "$SCRATCH_6_4"
    python3 "$SUMMARIZER" verify-manifest
    capture_command "$log64" env DEVELOPER_DIR="$DEVELOPER_6_4" /usr/bin/xcrun swift build \
        --package-path "$PACKAGE_DIR" --scratch-path "$SCRATCH_6_4" --configuration release
    python3 "$SUMMARIZER" verify-manifest
    cp "$log633" "$raw633"
    cp "$log64" "$raw64"

    local bin_dir
    bin_dir="$(DEVELOPER_DIR="$DEVELOPER_6_3_3" /usr/bin/xcrun swift build \
        --package-path "$PACKAGE_DIR" --scratch-path "$SCRATCH_6_3_3" \
        --configuration release --show-bin-path)"
    local built_binary="$bin_dir/DuckV11Wave03B"
    [[ -x "$built_binary" ]] || fail "Swift 6.3.3 Release executable is missing: $built_binary"
    mkdir -p "$OUTPUT_DIR/PREPARED_BINARY"
    cp -p "$built_binary" "$OUTPUT_DIR/PREPARED_BINARY/DuckV11Wave03B"
    chmod 755 "$OUTPUT_DIR/PREPARED_BINARY/DuckV11Wave03B"
    python3 "$SUMMARIZER" create-identity \
        --output "$OUTPUT_DIR" \
        --binary "$OUTPUT_DIR/PREPARED_BINARY/DuckV11Wave03B" \
        --swift633-log "$OUTPUT_DIR/TOOLCHAIN_SWIFT_6_3_3.log" \
        --swift64-log "$OUTPUT_DIR/TOOLCHAIN_SWIFT_6_4.log" | tee "$OUTPUT_DIR/PREPARED_BINARY_IDENTITY.log"
    cp "$OUTPUT_DIR/PREPARED_BINARY_IDENTITY.log" "$RAW_DIR/PREPARED_BINARY_IDENTITY.log"
    identity_environment
    run_smoke_matrix "$DUCK_BENCHMARK_PREPARED_BINARY_PATH" "$OUTPUT_DIR" "$RAW_DIR"

    python3 "$SUMMARIZER" selftest-selection --output "$OUTPUT_DIR/SELECTION_SELFTESTS.json" \
        | tee "$OUTPUT_DIR/SELECTION_SELFTESTS.log" "$RAW_DIR/SELECTION_SELFTESTS.log"
    cp "$OUTPUT_DIR/SELECTION_SELFTESTS.json" "$RAW_DIR/SELECTION_SELFTESTS.json"
    python3 "$SUMMARIZER" selftest-time-log --output "$OUTPUT_DIR/TIME_LOG_PARSER_SELFTESTS.json" \
        | tee "$OUTPUT_DIR/TIME_LOG_PARSER_SELFTESTS.log" "$RAW_DIR/TIME_LOG_PARSER_SELFTESTS.log"
    cp "$OUTPUT_DIR/TIME_LOG_PARSER_SELFTESTS.json" "$RAW_DIR/TIME_LOG_PARSER_SELFTESTS.json"
    verify_negative_idle_guard
    if [[ -e "$OUTPUT_DIR/RAW_SAMPLES.ndjson" || -e "$OUTPUT_DIR/SAMPLE_LOG_MANIFEST.json" ]]; then
        fail "prepare unexpectedly created timing sample evidence"
    fi
    cat > "$OUTPUT_DIR/PREPARATION_RESULT.md" <<'EOF'
# Wave03B Preparation Result

Product correctness was validated separately under Swift 6.3.3 and Swift 6.4. This runner built the Release harness under both toolchains, preserved the Swift 6.3.3 executable, passed all 20 deterministic smoke/resource probes, passed selection self-tests S01-S06, and passed the missing-idle guard.

TIMED_SAMPLES_RUN=NO
EOF
    cp "$OUTPUT_DIR/PREPARATION_RESULT.md" "$RAW_DIR/PREPARATION_RESULT.md"
    printf 'HARNESS_RELEASE_BUILD_SWIFT_6_3_3=PASS\nHARNESS_RELEASE_BUILD_SWIFT_6_4=PASS\nRESOURCE_PROBE_SMOKE=PASS\nSELECTION_RULE_SELFTESTS=PASS\nNEGATIVE_IDLE_GUARD=PASS\nTIMED_SAMPLES_RUN=NO\n'
}

run_smoke() {
    require_manifest
    identity_environment
    local smoke_tag="smoke-rerun-$(date -u '+%Y%m%dT%H%M%SZ')"
    local smoke_output="$OUTPUT_DIR/$smoke_tag"
    local smoke_raw="$RAW_DIR/$smoke_tag"
    [[ ! -e "$smoke_output" && ! -e "$smoke_raw" ]] || fail "Refusing to overwrite smoke rerun evidence"
    mkdir -p "$smoke_output" "$smoke_raw"
    run_smoke_matrix "$DUCK_BENCHMARK_PREPARED_BINARY_PATH" "$smoke_output" "$smoke_raw"
}

run_time() {
    require_manifest
    identity_environment
    python3 "$SUMMARIZER" verify-identity --output "$OUTPUT_DIR"
    local raw="$OUTPUT_DIR/RAW_SAMPLES.ndjson"
    local log_manifest="$OUTPUT_DIR/SAMPLE_LOG_MANIFEST.json"
    [[ ! -e "$raw" && ! -e "$log_manifest" ]] || fail "Refusing to overwrite existing timed sample evidence"
    local stderr_dir="$RAW_DIR/TIME_STDERR"
    [[ ! -e "$stderr_dir" ]] || fail "Refusing to overwrite existing /usr/bin/time logs"
    mkdir -p "$stderr_dir"
    : > "$raw"
    local round scenario_index capacity_index scenario capacity id temp time_log
    for round in 1 2 3 4 5 6 7; do
        scenario_index=0
        for scenario in "${SCENARIOS[@]}"; do
            for capacity_index in 0 1 2 3; do
                local rotated_index=$(((capacity_index + round - 1 + scenario_index) % 4))
                capacity="${CAPACITIES[$rotated_index]}"
                id="${scenario}_C${capacity}_R$(printf '%02d' "$round")"
                temp="$OUTPUT_DIR/.${id}.json.tmp"
                time_log="$stderr_dir/${id}.stderr-time.log"
                python3 "$SUMMARIZER" verify-identity --output "$OUTPUT_DIR"
                if ! /usr/bin/time -l "$DUCK_BENCHMARK_PREPARED_BINARY_PATH" sample \
                    "$scenario" "$capacity" "$round" > "$temp" 2> "$time_log"; then
                    cp "$temp" "$RAW_DIR/${id}.stdout.failed" 2>/dev/null || true
                    fail "timed sample failed: $id"
                fi
                python3 "$SUMMARIZER" validate-sample \
                    --sample "$temp" --output "$OUTPUT_DIR" \
                    --scenario "$scenario" --capacity "$capacity" --round "$round"
                cat "$temp" >> "$raw"
                cp "$temp" "$RAW_DIR/${id}.stdout.json"
                rm "$temp"
            done
            scenario_index=$((scenario_index + 1))
        done
    done
    python3 "$SUMMARIZER" freeze-time-logs --output "$OUTPUT_DIR" --stderr-dir "$stderr_dir"
    cp "$raw" "$RAW_DIR/RAW_SAMPLES.ndjson"
    write_sha_sidecar "$raw" "$OUTPUT_DIR/RAW_SAMPLES_SHA256.txt"
    cp "$OUTPUT_DIR/RAW_SAMPLES_SHA256.txt" "$RAW_DIR/RAW_SAMPLES_SHA256.txt"
    cp "$log_manifest" "$RAW_DIR/SAMPLE_LOG_MANIFEST.json"
    printf 'TIMED_SAMPLES=PASS count=140 idleAssertion=YES\n'
}

run_finalize() {
    require_manifest
    identity_environment
    python3 "$SUMMARIZER" verify-identity --output "$OUTPUT_DIR"
    python3 "$SUMMARIZER" finalize --output "$OUTPUT_DIR" | tee "$OUTPUT_DIR/FINALIZE.log" "$RAW_DIR/FINALIZE.log"
    cp "$OUTPUT_DIR/SUMMARY.json" "$RAW_DIR/SUMMARY.json"
    cp "$OUTPUT_DIR/SELECTION_STATUS.json" "$RAW_DIR/SELECTION_STATUS.json"
}

case "$MODE" in
    prepare) run_prepare ;;
    smoke) run_smoke ;;
    time) run_time ;;
    finalize) run_finalize ;;
esac
