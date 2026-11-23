#!/usr/bin/env python3
"""Identity fencing, resource validation, sample finalization, and selection tests."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import os
import re
import statistics
import subprocess
import sys
from pathlib import Path
from typing import Any


PACKAGE_DIR = Path(__file__).resolve().parent
REPOSITORY_DIR = PACKAGE_DIR.parents[1]
EVIDENCE_ROOT = REPOSITORY_DIR / ".artifacts/handoff/v1-1-wave03b-benchmark-preparation-2026-11-22"
CONTRACT_PATH = EVIDENCE_ROOT / "PRIMARY_WAVE03B_BENCHMARK_CONTRACT.md"
AUDIT_ENTRY_PATH = REPOSITORY_DIR / ".artifacts/reviews/duck-v1-1-wave03-canonical-pool-controller-external-audit-2026-11-22/PRIMARY_EXTERNAL_AUDIT_ENTRY.md"
AUDIT_REPORT_PATH = REPOSITORY_DIR / ".artifacts/reviews/duck-v1-1-wave03-canonical-pool-controller-external-audit-2026-11-22/SOL_EXTERNAL_WAVE03_IMPLEMENTATION_AUDIT_REPORT.md"
MANIFEST_PATH = PACKAGE_DIR / "PRESELECTION_PRODUCT_MANIFEST.json"
PREPARED_HEAD = "65054148e597252bc15637045ff50df1e78e9e7d"
PREPARED_BRANCH_RELATION = "## master...origin/master [ahead 24]"
EXPECTED_CONTRACT_SHA256 = "ec672dbb69da1d285e0302e5ff8d85378710402d812c62904d19d5a2bbdc7d88"
EXPECTED_AUDIT_ENTRY_SHA256 = "9f99b4b563c21d990f11fc2f85237e03229ea61d56d4eeaea393cd9472986f3e"
EXPECTED_AUDIT_REPORT_SHA256 = "9f144d3445ac46daf83a57e32191f04bf0ee381b39cee5735eb257ef09c30d05"
EXPECTED_CONNECTION_POOL_SHA256 = "48c4266a986e77ccb10de73333a68d381050d6e920a3a7a211a20a4ed2809120"
EXPECTED_PROTECTED_PATH = "Examples/SwiftUI/DuckDemo.xcodeproj/project.pbxproj"
EXPECTED_PROTECTED_SHA256 = "ef3a46629337a79867e0a31e9c76c10df8d773914887151e8b721a5b66b74436"
EXPECTED_ROOT_PACKAGE_SHA256 = {
    "Package.swift": "0893f4fa885dbce85e1f843a9eb8370bc570643458522fd2ba09ec6f3a26a322",
    "Package.resolved": "a6b87888ee3eec785ebae1d87c41724b10abad34d82079da05990c88d5172f0e",
}
SCENARIOS = {
    "Q01_SMALL_READ_SEQ": {"warmup": 100, "measured": 1000, "concurrency": 1, "kind": "sequential"},
    "Q02_SMALL_READ_CONCURRENT": {"warmup": 80, "measured": 1000, "concurrency": 8, "kind": "primary"},
    "W01_MIXED_SHORT_RW_CONCURRENT": {"warmup": 80, "measured": 800, "concurrency": 8, "kind": "primary"},
    "T01_TRANSACTION_SEQ": {"warmup": 10, "measured": 100, "concurrency": 1, "kind": "sequential"},
    "P01_APPENDER_BATCH_SEQ": {"warmup": 3, "measured": 30, "concurrency": 1, "kind": "sequential"},
}
CAPACITIES = [1, 2, 4, 8]
PRIMARY_SCENARIOS = ["Q02_SMALL_READ_CONCURRENT", "W01_MIXED_SHORT_RW_CONCURRENT"]
SEQUENTIAL_SCENARIOS = ["Q01_SMALL_READ_SEQ", "T01_TRANSACTION_SEQ", "P01_APPENDER_BATCH_SEQ"]
HARNESS_RELATIVE_FILES = [
    "Package.swift",
    "Package.resolved",
    "README.md",
    "PRESELECTION_PRODUCT_MANIFEST.json",
    "Sources/DuckV11Wave03B/main.swift",
    "run-wave03b.sh",
    "summarize.py",
]
HASHED_HARNESS_RELATIVE_FILES = [path for path in HARNESS_RELATIVE_FILES if path != "PRESELECTION_PRODUCT_MANIFEST.json"]


class Blocked(Exception):
    pass


def fail(message: str) -> None:
    raise Blocked(message)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, indent=2, separators=(",", ": ")) + "\n").encode()


def git(*args: str, check: bool = True) -> str:
    result = subprocess.run(
        ["/usr/bin/git", "-C", str(REPOSITORY_DIR), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and result.returncode != 0:
        fail(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def git_status_paths() -> set[str]:
    result = subprocess.run(
        ["/usr/bin/git", "-C", str(REPOSITORY_DIR), "status", "--porcelain=v1", "-z"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        fail("could not read Git porcelain status")
    paths: set[str] = set()
    for record in result.stdout.split(b"\0"):
        if not record:
            continue
        if len(record) < 4:
            fail(f"unexpected Git porcelain record: {record!r}")
        paths.add(os.fsdecode(record[3:]))
    return paths


def require_empty_index() -> None:
    result = subprocess.run(
        ["/usr/bin/git", "-C", str(REPOSITORY_DIR), "diff", "--cached", "--quiet"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        fail("staged index is not empty")


def read_audit_candidates() -> dict[str, str]:
    if sha256_file(AUDIT_ENTRY_PATH) != EXPECTED_AUDIT_ENTRY_SHA256:
        fail("accepted PRIMARY_EXTERNAL_AUDIT_ENTRY.md checksum changed")
    pattern = re.compile(r"^([0-9a-f]{64})\s+(Sources/Duck/\S+|Tests/DuckTests/\S+)$", re.M)
    candidates = {path: digest for digest, path in pattern.findall(AUDIT_ENTRY_PATH.read_text())}
    if len(candidates) != 28:
        fail(f"accepted audit entry exposed {len(candidates)} candidate paths, expected 28")
    if sum(path.startswith("Sources/Duck/") for path in candidates) != 12:
        fail("accepted audit entry does not contain exactly 12 Product candidates")
    if sum(path.startswith("Tests/DuckTests/") for path in candidates) != 16:
        fail("accepted audit entry does not contain exactly 16 test candidates")
    candidates["Sources/Duck/ConnectionPool.swift"] = EXPECTED_CONNECTION_POOL_SHA256
    return candidates


def exact_file_tree(directory: Path) -> dict[str, str]:
    if not directory.is_dir():
        fail(f"required source tree is missing: {directory}")
    output: dict[str, str] = {}
    for path in sorted(directory.rglob("*")):
        if path.is_file():
            rel = path.relative_to(REPOSITORY_DIR).as_posix()
            output[rel] = sha256_file(path)
    return output


def require_exact_candidate_worktree(candidates: dict[str, str]) -> None:
    changed = {
        path for path in git_status_paths()
        if path.startswith("Sources/Duck/") or path.startswith("Tests/DuckTests/")
    }
    if changed != set(candidates):
        missing = sorted(set(candidates) - changed)
        unexpected = sorted(changed - set(candidates))
        fail(f"Product/test changed-path set differs from accepted 28 paths; missing={missing}, unexpected={unexpected}")


def verify_entry_fence() -> dict[str, Any]:
    if sha256_file(CONTRACT_PATH) != EXPECTED_CONTRACT_SHA256:
        fail("PRIMARY Wave03B benchmark contract checksum changed")
    if sha256_file(AUDIT_REPORT_PATH) != EXPECTED_AUDIT_REPORT_SHA256:
        fail("accepted Wave03 implementation audit report checksum changed")
    if git("rev-parse", "HEAD") != PREPARED_HEAD:
        fail("entry HEAD differs from the frozen Wave03B preparation HEAD")
    relation = git("status", "-sb").splitlines()[0]
    if relation != PREPARED_BRANCH_RELATION:
        fail(f"entry branch relation differs: {relation!r}")
    if git("branch", "--show-current") != "master":
        fail("entry branch is not master")
    require_empty_index()
    candidates = read_audit_candidates()
    for path, expected in candidates.items():
        source = REPOSITORY_DIR / path
        if not source.is_file() or sha256_file(source) != expected:
            fail(f"accepted candidate identity mismatch: {path}")
    for path, expected in EXPECTED_ROOT_PACKAGE_SHA256.items():
        if sha256_file(REPOSITORY_DIR / path) != expected:
            fail(f"root package identity mismatch: {path}")
    if sha256_file(REPOSITORY_DIR / EXPECTED_PROTECTED_PATH) != EXPECTED_PROTECTED_SHA256:
        fail("protected SwiftUI project WIP identity mismatch")
    require_exact_candidate_worktree(candidates)
    return {"candidates": candidates, "branchRelation": relation}


def harness_file_set() -> set[str]:
    return {
        path.relative_to(PACKAGE_DIR).as_posix()
        for path in PACKAGE_DIR.rglob("*")
        if path.is_file()
    }


def make_manifest() -> dict[str, Any]:
    entry = verify_entry_fence()
    if MANIFEST_PATH.exists():
        fail("PRESELECTION_PRODUCT_MANIFEST.json already exists; refusing silent regeneration")
    expected_without_manifest = set(HARNESS_RELATIVE_FILES) - {"PRESELECTION_PRODUCT_MANIFEST.json"}
    if harness_file_set() != expected_without_manifest:
        fail(f"harness file set before manifest creation differs: {sorted(harness_file_set())}")
    current_candidates = entry["candidates"]
    root_hashes = {name: sha256_file(REPOSITORY_DIR / name) for name in EXPECTED_ROOT_PACKAGE_SHA256}
    manifest = {
        "schemaVersion": 1,
        "stage": "duck-v1.1-wave03b-preselection",
        "headAtFreeze": PREPARED_HEAD,
        "branchAtFreeze": "master",
        "branchRelationAtFreeze": entry["branchRelation"],
        "authority": {
            "contractSHA256": EXPECTED_CONTRACT_SHA256,
            "acceptedAuditEntrySHA256": EXPECTED_AUDIT_ENTRY_SHA256,
            "acceptedAuditReportSHA256": EXPECTED_AUDIT_REPORT_SHA256,
        },
        "rootPackageFiles": root_hashes,
        "protectedWorktreeFile": {
            "path": EXPECTED_PROTECTED_PATH,
            "sha256": EXPECTED_PROTECTED_SHA256,
        },
        "productCandidates": {
            path: digest for path, digest in sorted(current_candidates.items()) if path.startswith("Sources/Duck/")
        },
        "testCandidates": {
            path: digest for path, digest in sorted(current_candidates.items()) if path.startswith("Tests/DuckTests/")
        },
        "sourcesDuckTree": exact_file_tree(REPOSITORY_DIR / "Sources/Duck"),
        "testsDuckTestsTree": exact_file_tree(REPOSITORY_DIR / "Tests/DuckTests"),
        "benchmarkHarness": {
            "exactFiles": sorted(HARNESS_RELATIVE_FILES),
            "hashedFiles": {
                path: sha256_file(PACKAGE_DIR / path) for path in HASHED_HARNESS_RELATIVE_FILES
            },
            "selfHashPolicy": "PRESELECTION_PRODUCT_MANIFEST.json is present in exactFiles but excluded from hashedFiles to avoid recursive self-hashing.",
        },
    }
    MANIFEST_PATH.write_bytes(canonical_json(manifest))
    return manifest


def load_manifest() -> dict[str, Any]:
    if not MANIFEST_PATH.is_file():
        fail("frozen Product manifest is missing")
    try:
        value = json.loads(MANIFEST_PATH.read_text())
    except Exception as error:  # noqa: BLE001
        fail(f"frozen Product manifest is invalid JSON: {error}")
    if value.get("schemaVersion") != 1:
        fail("unsupported Product manifest schema")
    return value


def verify_manifest() -> dict[str, Any]:
    manifest = load_manifest()
    if git("branch", "--show-current") != "master":
        fail("current branch is not master")
    require_empty_index()
    if set(manifest["benchmarkHarness"]["exactFiles"]) != set(HARNESS_RELATIVE_FILES):
        fail("frozen harness file set does not match the exact contract-owned seven files")
    if harness_file_set() != set(HARNESS_RELATIVE_FILES):
        fail(f"live benchmark harness file set differs: {sorted(harness_file_set())}")
    if sha256_file(CONTRACT_PATH) != EXPECTED_CONTRACT_SHA256:
        fail("benchmark contract identity changed")
    if sha256_file(AUDIT_ENTRY_PATH) != EXPECTED_AUDIT_ENTRY_SHA256:
        fail("accepted audit entry identity changed")
    if sha256_file(AUDIT_REPORT_PATH) != EXPECTED_AUDIT_REPORT_SHA256:
        fail("accepted audit report identity changed")
    if manifest["authority"] != {
        "contractSHA256": EXPECTED_CONTRACT_SHA256,
        "acceptedAuditEntrySHA256": EXPECTED_AUDIT_ENTRY_SHA256,
        "acceptedAuditReportSHA256": EXPECTED_AUDIT_REPORT_SHA256,
    }:
        fail("manifest authority identities do not match the accepted records")
    for rel, expected in manifest["rootPackageFiles"].items():
        if sha256_file(REPOSITORY_DIR / rel) != expected:
            fail(f"root package file changed after product freeze: {rel}")
    protected = manifest["protectedWorktreeFile"]
    if protected["path"] != EXPECTED_PROTECTED_PATH or sha256_file(REPOSITORY_DIR / protected["path"]) != protected["sha256"]:
        fail("protected WIP differs from the frozen manifest")
    frozen_candidates = {**manifest["productCandidates"], **manifest["testCandidates"]}
    current_expected = read_audit_candidates()
    if set(frozen_candidates) != set(current_expected):
        fail("manifest candidate path set differs from the accepted 28-path candidate")
    for path, expected in frozen_candidates.items():
        if current_expected[path] != expected:
            fail(f"manifest candidate hash differs from accepted entry: {path}")
        if sha256_file(REPOSITORY_DIR / path) != expected:
            fail(f"frozen Product/test candidate changed: {path}")
    require_exact_candidate_worktree(frozen_candidates)
    for tree_key, directory in [("sourcesDuckTree", "Sources/Duck"), ("testsDuckTestsTree", "Tests/DuckTests")]:
        if exact_file_tree(REPOSITORY_DIR / directory) != manifest[tree_key]:
            fail(f"source file set or hashes changed: {directory}")
    hashed = manifest["benchmarkHarness"]["hashedFiles"]
    if set(hashed) != set(HASHED_HARNESS_RELATIVE_FILES):
        fail("manifest harness hash policy is incomplete or changed")
    for rel, expected in hashed.items():
        if sha256_file(PACKAGE_DIR / rel) != expected:
            fail(f"benchmark harness file changed after freeze: {rel}")
    return manifest


def product_fence_identity(manifest: dict[str, Any]) -> str:
    value = {
        "rootPackageFiles": manifest["rootPackageFiles"],
        "protectedWorktreeFile": manifest["protectedWorktreeFile"],
        "productCandidates": manifest["productCandidates"],
        "testCandidates": manifest["testCandidates"],
        "sourcesDuckTree": manifest["sourcesDuckTree"],
        "testsDuckTestsTree": manifest["testsDuckTestsTree"],
    }
    return sha256_bytes(canonical_json(value))


def extract_toolchain(log_path: Path, swift_version: str, xcode_version: str, developer_dir: str) -> dict[str, str]:
    if not log_path.is_file():
        fail(f"required toolchain log is missing: {log_path}")
    content = log_path.read_text(errors="replace")
    if swift_version not in content or xcode_version not in content:
        fail(f"toolchain log does not identify Swift {swift_version} / Xcode {xcode_version}: {log_path}")
    return {
        "developerDir": developer_dir,
        "swiftVersion": swift_version,
        "xcodeVersion": xcode_version,
        "logSHA256": sha256_file(log_path),
    }


def create_identity(output: Path, binary: Path, log633: Path, log64: Path) -> dict[str, Any]:
    manifest = verify_manifest()
    if not binary.is_file() or not os.access(binary, os.X_OK):
        fail(f"preserved Swift 6.3.3 executable is missing or not executable: {binary}")
    if log633.resolve() == log64.resolve():
        fail("toolchain build logs must be distinct")
    identity_path = output / "PREPARED_RUN_IDENTITY.json"
    sha_path = output / "PREPARED_RUN_IDENTITY_SHA256.txt"
    if identity_path.exists() or sha_path.exists():
        fail("prepared-run identity already exists; refusing overwrite")
    identity = {
        "schemaVersion": 1,
        "preparedAtUTC": dt.datetime.now(dt.timezone.utc).isoformat(),
        "head": git("rev-parse", "HEAD"),
        "branch": git("branch", "--show-current"),
        "productManifestSHA256": sha256_file(MANIFEST_PATH),
        "productInputFenceSHA256": product_fence_identity(manifest),
        "rootPackageFiles": manifest["rootPackageFiles"],
        "productCandidates": manifest["productCandidates"],
        "testCandidates": manifest["testCandidates"],
        "sourcesDuckTreeSHA256": sha256_bytes(canonical_json(manifest["sourcesDuckTree"])),
        "testsDuckTestsTreeSHA256": sha256_bytes(canonical_json(manifest["testsDuckTestsTree"])),
        "harnessFiles": manifest["benchmarkHarness"]["hashedFiles"],
        "harnessManifestSelfHashPolicy": manifest["benchmarkHarness"]["selfHashPolicy"],
        "preparedBinary": {
            "path": str(binary.resolve()),
            "sha256": sha256_file(binary),
            "mode": oct(binary.stat().st_mode & 0o777),
        },
        "toolchains": {
            "swift6_3_3": extract_toolchain(
                log633,
                "6.3.3",
                "26.6",
                "/Applications/Xcode-26-6.app/Contents/Developer",
            ),
            "swift6_4": extract_toolchain(
                log64,
                "6.4",
                "27.0",
                "/Applications/Xcode-27.app/Contents/Developer",
            ),
        },
        "timedSamplesRunDuringPreparation": False,
        "idleAssertionRequiredForTime": "DUCK_BENCHMARK_MAC_IDLE=YES",
    }
    payload = canonical_json(identity)
    identity_path.write_bytes(payload)
    digest = sha256_bytes(payload)
    sha_path.write_text(f"{digest}  PREPARED_RUN_IDENTITY.json\n")
    return identity


def verify_identity(output: Path) -> tuple[dict[str, Any], str]:
    manifest = verify_manifest()
    identity_path = output / "PREPARED_RUN_IDENTITY.json"
    sha_path = output / "PREPARED_RUN_IDENTITY_SHA256.txt"
    if not identity_path.is_file() or not sha_path.is_file():
        fail("prepared-run identity files are missing")
    identity_bytes = identity_path.read_bytes()
    identity_sha = sha256_bytes(identity_bytes)
    recorded = sha_path.read_text().split()[0]
    if recorded != identity_sha:
        fail("prepared-run identity checksum mismatch")
    identity = json.loads(identity_bytes)
    if identity["head"] != git("rev-parse", "HEAD"):
        fail("current HEAD differs from the prepared-run HEAD")
    if identity["branch"] != "master" or git("branch", "--show-current") != "master":
        fail("prepared-run/current branch identity is not master")
    if identity["productManifestSHA256"] != sha256_file(MANIFEST_PATH):
        fail("prepared-run Product manifest identity mismatch")
    if identity["productInputFenceSHA256"] != product_fence_identity(manifest):
        fail("prepared-run Product input fence identity mismatch")
    binary_path = Path(identity["preparedBinary"]["path"])
    if not binary_path.is_file() or not os.access(binary_path, os.X_OK):
        fail("preserved timing executable is missing or not executable")
    if sha256_file(binary_path) != identity["preparedBinary"]["sha256"]:
        fail("preserved timing executable checksum mismatch")
    if oct(binary_path.stat().st_mode & 0o777) != identity["preparedBinary"]["mode"]:
        fail("preserved timing executable mode changed")
    if identity["harnessFiles"] != manifest["benchmarkHarness"]["hashedFiles"]:
        fail("prepared-run harness identity mismatch")
    return identity, identity_sha


def identity_values(output: Path) -> tuple[str, str, str, str, str]:
    identity, identity_sha = verify_identity(output)
    print(
        "\t".join(
            [
                identity["productManifestSHA256"],
                identity_sha,
                identity["preparedBinary"]["sha256"],
                identity["head"],
                identity["preparedBinary"]["path"],
            ]
        )
    )
    return (
        identity["productManifestSHA256"],
        identity_sha,
        identity["preparedBinary"]["sha256"],
        identity["head"],
        identity["preparedBinary"]["path"],
    )


def probe_combinations() -> set[tuple[str, int]]:
    return {(scenario, capacity) for scenario in SCENARIOS for capacity in CAPACITIES}


def validate_probe_records(
    path: Path,
    output: Path | None = None,
    prepared_output: Path | None = None,
) -> list[dict[str, Any]]:
    lines = path.read_text().splitlines()
    records = [json.loads(line) for line in lines if line.strip()]
    expected = probe_combinations()
    keys = [(record.get("scenario"), record.get("capacity")) for record in records]
    if len(records) != 20 or len(set(keys)) != 20 or set(keys) != expected:
        fail("resource probes do not cover the exact 5 scenario x 4 capacity matrix")
    identity = None
    identity_sha = None
    if prepared_output is not None:
        identity, identity_sha = verify_identity(prepared_output)
    expected_checkouts = {
        "Q01_SMALL_READ_SEQ": 12,
        "Q02_SMALL_READ_CONCURRENT": 24,
        "W01_MIXED_SHORT_RW_CONCURRENT": 26,
        "T01_TRANSACTION_SEQ": 5,
        "P01_APPENDER_BATCH_SEQ": 4,
    }
    for record in records:
        capacity = record["capacity"]
        before, after = record["before"], record["after"]
        opened_delta = after["openedConnectionCount"] - before["openedConnectionCount"]
        retire_delta = after["retireCompletionCount"] - before["retireCompletionCount"]
        if record.get("correctness") != "PASS" or record.get("resourceProbe") != "PASS":
            fail(f"resource/correctness probe failed for {record['scenario']} capacity {capacity}")
        if record.get("expectedCheckoutCount") != record.get("observedCheckoutCount"):
            fail(f"resource probe checkout count mismatch for {record['scenario']} capacity {capacity}")
        if record.get("expectedCheckoutCount") != expected_checkouts[record["scenario"]]:
            fail(f"resource probe does not match the expected harness checkout semantics for {record['scenario']}")
        if identity is not None:
            if record.get("gitHead") != identity["head"]:
                fail(f"resource probe HEAD differs from prepared identity for {record['scenario']} capacity {capacity}")
            if record.get("productManifestSHA256") != identity["productManifestSHA256"]:
                fail(f"resource probe Product manifest differs for {record['scenario']} capacity {capacity}")
            if record.get("preparedRunIdentitySHA256") != identity_sha or record.get("preparedBinarySHA256") != identity["preparedBinary"]["sha256"]:
                fail(f"resource probe prepared identity differs for {record['scenario']} capacity {capacity}")
        if record["observedCheckoutCount"] <= 1 or opened_delta <= 0 or record.get("reuseDemonstrated") is not True:
            fail(f"resource probe did not demonstrate repeated core reuse for {record['scenario']} capacity {capacity}")
        if retire_delta != 0 or record.get("retireCompletionDelta") != 0:
            fail(f"healthy resource probe retired a core for {record['scenario']} capacity {capacity}")
        if record["maxSimultaneouslyBorrowedCanonicalClosures"] > capacity:
            fail(f"borrowed closure count exceeded capacity for {record['scenario']} capacity {capacity}")
        for key in ["currentMaterializedConnectionCount", "peakMaterializedConnectionCount"]:
            if after[key] > capacity:
                fail(f"{key} exceeded capacity for {record['scenario']} capacity {capacity}")
        for key in ["activeLeaseCount", "returningLeaseCount", "queuedWaiterCount", "creationReservationCount"]:
            if after[key] != 0:
                fail(f"non-quiescent resource probe state {key} for {record['scenario']} capacity {capacity}")
    if output:
        output.write_text("RESOURCE_PROBE_SMOKE=PASS\nSCENARIO_CAPACITY_COMBINATIONS=20/20\n")
    return records


def synthetic_metrics(
    primary_throughput: dict[int, float],
    primary_p95: dict[int, float] | None = None,
    sequential_throughput: dict[int, float] | None = None,
    sequential_p95: dict[int, float] | None = None,
) -> dict[str, Any]:
    primary_p95 = primary_p95 or {capacity: 100.0 for capacity in CAPACITIES}
    sequential_throughput = sequential_throughput or {capacity: 100.0 for capacity in CAPACITIES}
    sequential_p95 = sequential_p95 or {capacity: 100.0 for capacity in CAPACITIES}
    capacities: dict[str, Any] = {}
    for capacity in CAPACITIES:
        scenarios: dict[str, Any] = {}
        for scenario in SCENARIOS:
            is_primary = scenario in PRIMARY_SCENARIOS
            scenarios[scenario] = {
                "throughput": float(primary_throughput[capacity] if is_primary else sequential_throughput[capacity]),
                "p95": float(primary_p95[capacity] if is_primary else sequential_p95[capacity]),
            }
        capacities[str(capacity)] = {
            "resourceProbePass": True,
            "correctnessPass": True,
            "capacity": capacity,
            "maxBorrowed": min(capacity, 1),
            "currentCores": min(capacity, 1),
            "peakCores": min(capacity, 1),
            "retireDelta": 0,
            "scenarios": scenarios,
        }
    return {"integrityPass": True, "capacities": capacities}


def evaluate_selection(evidence: dict[str, Any]) -> dict[str, Any]:
    if evidence.get("integrityPass") is not True:
        return {"status": "BLOCKED_HANDOFF_REQUIRED", "selectedCapacity": None, "reason": "evidence integrity flag is not PASS"}
    raw = evidence.get("capacities")
    if not isinstance(raw, dict) or set(raw) != {str(capacity) for capacity in CAPACITIES}:
        return {"status": "BLOCKED_HANDOFF_REQUIRED", "selectedCapacity": None, "reason": "capacity evidence set is incomplete or unexpected"}
    values: dict[int, dict[str, Any]] = {}
    for capacity in CAPACITIES:
        item = raw[str(capacity)]
        if item.get("capacity") != capacity or item.get("resourceProbePass") is not True or item.get("correctnessPass") is not True:
            return {"status": "BLOCKED_HANDOFF_REQUIRED", "selectedCapacity": None, "reason": f"resource/correctness evidence inconsistent at capacity {capacity}"}
        if item.get("retireDelta") != 0 or item.get("maxBorrowed", capacity + 1) > capacity:
            return {"status": "BLOCKED_HANDOFF_REQUIRED", "selectedCapacity": None, "reason": f"resource counts inconsistent at capacity {capacity}"}
        if item.get("currentCores", capacity + 1) > capacity or item.get("peakCores", capacity + 1) > capacity:
            return {"status": "BLOCKED_HANDOFF_REQUIRED", "selectedCapacity": None, "reason": f"materialized core count inconsistent at capacity {capacity}"}
        scenarios = item.get("scenarios")
        if not isinstance(scenarios, dict) or set(scenarios) != set(SCENARIOS):
            return {"status": "BLOCKED_HANDOFF_REQUIRED", "selectedCapacity": None, "reason": f"scenario evidence incomplete at capacity {capacity}"}
        for scenario, metrics in scenarios.items():
            throughput, p95 = metrics.get("throughput"), metrics.get("p95")
            if not isinstance(throughput, (int, float)) or not math.isfinite(throughput) or throughput <= 0:
                return {"status": "BLOCKED_HANDOFF_REQUIRED", "selectedCapacity": None, "reason": f"invalid throughput for {scenario} capacity {capacity}"}
            if not isinstance(p95, (int, float)) or not math.isfinite(p95) or p95 <= 0:
                return {"status": "BLOCKED_HANDOFF_REQUIRED", "selectedCapacity": None, "reason": f"invalid p95 for {scenario} capacity {capacity}"}
        values[capacity] = item

    best_throughput = {
        scenario: max(values[c]["scenarios"][scenario]["throughput"] for c in CAPACITIES)
        for scenario in SCENARIOS
    }
    best_p95 = {
        scenario: min(values[c]["scenarios"][scenario]["p95"] for c in CAPACITIES)
        for scenario in SCENARIOS
    }
    aggregate: dict[int, float] = {}
    ratios: dict[int, dict[str, float]] = {}
    for capacity in CAPACITIES:
        primary_ratios = [
            values[capacity]["scenarios"][scenario]["throughput"] / best_throughput[scenario]
            for scenario in PRIMARY_SCENARIOS
        ]
        aggregate[capacity] = math.sqrt(primary_ratios[0] * primary_ratios[1])
        ratios[capacity] = {scenario: values[capacity]["scenarios"][scenario]["throughput"] / best_throughput[scenario] for scenario in SCENARIOS}
    best_aggregate = max(aggregate.values())
    qualifying: list[int] = []
    for capacity in CAPACITIES:
        item = values[capacity]
        passes = all(ratios[capacity][scenario] >= 0.90 for scenario in PRIMARY_SCENARIOS)
        passes = passes and aggregate[capacity] >= 0.95 * best_aggregate
        passes = passes and all(item["scenarios"][scenario]["p95"] <= 1.10 * best_p95[scenario] for scenario in PRIMARY_SCENARIOS)
        passes = passes and all(ratios[capacity][scenario] >= 0.90 for scenario in SEQUENTIAL_SCENARIOS)
        passes = passes and all(item["scenarios"][scenario]["p95"] <= 1.25 * best_p95[scenario] for scenario in SEQUENTIAL_SCENARIOS)
        if passes:
            qualifying.append(capacity)

    frontier_aggregate_improvement = aggregate[8] / aggregate[4] - 1.0
    frontier_p95_improvements = {
        scenario: values[4]["scenarios"][scenario]["p95"] / values[8]["scenarios"][scenario]["p95"] - 1.0
        for scenario in PRIMARY_SCENARIOS
    }
    detail = {
        "qualifyingCapacities": qualifying,
        "bestThroughput": best_throughput,
        "bestP95": best_p95,
        "aggregateConcurrentThroughputScore": {str(capacity): aggregate[capacity] for capacity in CAPACITIES},
        "frontierAggregateImprovement4To8": frontier_aggregate_improvement,
        "frontierPrimaryP95Improvement4To8": frontier_p95_improvements,
        "thresholds": {
            "primaryThroughputMinimum": 0.90,
            "aggregateScoreMinimumOfBest": 0.95,
            "primaryP95MaximumOfBest": 1.10,
            "sequentialThroughputMinimum": 0.90,
            "sequentialP95MaximumOfBest": 1.25,
            "capacity8BoundaryImprovementStrictlyGreaterThan": 0.10,
        },
    }
    if not qualifying:
        return {"status": "VALUE_HANDOFF_REQUIRED", "selectedCapacity": None, "reason": "no capacity qualifies", **detail}
    if qualifying == [8] and (
        frontier_aggregate_improvement > 0.10
        or any(value > 0.10 for value in frontier_p95_improvements.values())
    ):
        return {
            "status": "VALUE_HANDOFF_REQUIRED",
            "selectedCapacity": None,
            "reason": "capacity 8 is the only qualifier and the measured frontier still improves beyond the boundary rule",
            "requiredExtension": "CAPACITY_16_EXTENSION_REQUIRED",
            **detail,
        }
    return {"status": "SELECTED", "selectedCapacity": min(qualifying), "reason": "smallest qualifying capacity", **detail}


def run_selection_selftests() -> list[dict[str, Any]]:
    cases: list[tuple[str, dict[str, Any], str, int | None, str | None]] = []
    cases.append(("S01", synthetic_metrics({1: 70, 2: 98, 4: 100, 8: 100}), "SELECTED", 2, None))
    cases.append(("S02", synthetic_metrics({1: 70, 2: 80, 4: 100, 8: 100}), "SELECTED", 4, None))
    cases.append(("S03", synthetic_metrics({1: 65, 2: 75, 4: 80, 8: 100}, primary_p95={1: 150, 2: 140, 4: 120, 8: 100}), "VALUE_HANDOFF_REQUIRED", None, "CAPACITY_16_EXTENSION_REQUIRED"))
    cases.append(("S04", synthetic_metrics({1: 70, 2: 80, 4: 99, 8: 100}, sequential_p95={1: 100, 2: 100, 4: 130, 8: 100}), "SELECTED", 8, None))
    cases.append(("S05", synthetic_metrics({1: 100, 2: 80, 4: 80, 8: 80}, sequential_throughput={1: 80, 2: 80, 4: 80, 8: 100}), "VALUE_HANDOFF_REQUIRED", None, None))
    inconsistent = synthetic_metrics({1: 70, 2: 98, 4: 100, 8: 100})
    inconsistent["capacities"]["4"]["maxBorrowed"] = 5
    cases.append(("S06", inconsistent, "BLOCKED_HANDOFF_REQUIRED", None, None))
    results = []
    for name, evidence, expected_status, expected_capacity, expected_extension in cases:
        actual = evaluate_selection(evidence)
        passed = actual["status"] == expected_status and actual.get("selectedCapacity") == expected_capacity
        passed = passed and actual.get("requiredExtension") == expected_extension
        if not passed:
            fail(f"selection self-test {name} failed: expected {expected_status}/{expected_capacity}/{expected_extension}, got {actual}")
        results.append({"id": name, "status": actual["status"], "selectedCapacity": actual.get("selectedCapacity"), "requiredExtension": actual.get("requiredExtension"), "result": "PASS"})
    return results


def parse_time_log_text(text: str) -> dict[str, int | float | None]:
    # macOS /usr/bin/time -l prints resource counters as:
    # "<value>  maximum resident set size".
    rss_matches = re.findall(r"^\s*(\d+)\s+maximum resident set size\b", text, flags=re.MULTILINE)
    user_match = re.search(r"([0-9]+(?:\.[0-9]+)?)\s+user\b", text)
    system_match = re.search(r"([0-9]+(?:\.[0-9]+)?)\s+sys\b", text)
    return {
        "maximumResidentSetBytes": int(rss_matches[0]) if len(rss_matches) == 1 else None,
        "userCPUSeconds": float(user_match.group(1)) if user_match else None,
        "systemCPUSeconds": float(system_match.group(1)) if system_match else None,
    }


def parse_time_log(path: Path) -> dict[str, int | float | None]:
    return parse_time_log_text(path.read_text(errors="replace"))


def run_time_log_parser_selftests() -> list[dict[str, Any]]:
    cases = [
        (
            "TLP01_MACOS_CANONICAL",
            "        0.12 real         0.08 user         0.02 sys\n"
            "          12345678  maximum resident set size\n",
            {"maximumResidentSetBytes": 12345678, "userCPUSeconds": 0.08, "systemCPUSeconds": 0.02},
        ),
        (
            "TLP02_MACOS_WHITESPACE",
            "0.01 real 0.00 user 0.01 sys\n"
            "\t9876543 maximum resident set size\n",
            {"maximumResidentSetBytes": 9876543, "userCPUSeconds": 0.0, "systemCPUSeconds": 0.01},
        ),
        (
            "TLP03_REVERSED_RSS_REJECTED",
            "0.01 real 0.00 user 0.01 sys\n"
            "maximum resident set size 555\n",
            {"maximumResidentSetBytes": None, "userCPUSeconds": 0.0, "systemCPUSeconds": 0.01},
        ),
    ]
    results: list[dict[str, Any]] = []
    for name, source, expected in cases:
        actual = parse_time_log_text(source)
        if actual != expected:
            fail(f"time-log parser self-test {name} failed: expected {expected}, got {actual}")
        results.append({"id": name, "result": "PASS", **actual})
    return results


def nearest_rank(values: list[int], fraction: float) -> int:
    ordered = sorted(values)
    rank = max(1, math.ceil(fraction * len(ordered)))
    return ordered[min(rank - 1, len(ordered) - 1)]


def validate_one_sample(sample_path: Path, output: Path, scenario: str, capacity: int, round_number: int) -> None:
    identity, identity_sha = verify_identity(output)
    data = sample_path.read_text().strip().splitlines()
    if len(data) != 1:
        fail("sample executable must produce exactly one JSON line")
    sample = json.loads(data[0])
    spec = SCENARIOS[scenario]
    expected = {
        "schemaVersion": 1,
        "benchmarkVersion": "v1.1-wave03b-preselection-1",
        "gitHead": identity["head"],
        "productManifestSHA256": identity["productManifestSHA256"],
        "preparedRunIdentitySHA256": identity_sha,
        "preparedBinarySHA256": identity["preparedBinary"]["sha256"],
        "scenario": scenario,
        "lane": f"C_CANONICAL_{capacity}",
        "round": round_number,
        "warmupOperations": spec["warmup"],
        "measuredOperations": spec["measured"],
        "concurrency": spec["concurrency"],
        "capacity": capacity,
        "correctness": "PASS",
    }
    for key, value in expected.items():
        if sample.get(key) != value:
            fail(f"sample field {key} differs from prepared/contract identity")
    total = sample.get("totalOperationLatenciesNanoseconds")
    waits = sample.get("checkoutWaitLatenciesNanoseconds")
    if not isinstance(total, list) or len(total) != spec["measured"] or not all(isinstance(value, int) and value > 0 for value in total):
        fail("sample total-operation latency vector is missing or malformed")
    if not isinstance(waits, list) or len(waits) != spec["measured"] or not all(isinstance(value, int) and value >= 0 for value in waits):
        fail("sample checkout-wait latency vector is missing or malformed")
    if sample.get("elapsedNanoseconds", 0) <= 0:
        fail("sample elapsed time must be positive")
    calculated_rate = spec["measured"] * 1_000_000_000 / sample["elapsedNanoseconds"]
    if not math.isclose(sample.get("operationsPerSecond", 0), calculated_rate, rel_tol=1e-12):
        fail("sample throughput does not match measured count / whole-sample elapsed time")
    for prefix, values in [("totalOperation", total), ("checkoutWait", waits)]:
        for suffix, fraction in [("P50", 0.50), ("P95", 0.95), ("P99", 0.99)]:
            if sample.get(prefix + suffix + "Nanoseconds") != nearest_rank(values, fraction):
                fail(f"sample {prefix} {suffix} does not match nearest-rank percentile")
    if not re.fullmatch(r"[0-9a-f]+", str(sample.get("checksum", ""))):
        fail("sample correctness checksum is malformed")


def freeze_time_logs(output: Path, stderr_dir: Path) -> dict[str, Any]:
    raw = output / "RAW_SAMPLES.ndjson"
    if not raw.is_file():
        fail("raw sample matrix is missing")
    lines = raw.read_bytes().splitlines(keepends=True)
    if len(lines) != 140:
        fail(f"cannot freeze time logs for {len(lines)} samples; expected 140")
    records = [json.loads(line) for line in lines]
    entries: dict[str, Any] = {}
    expected_logs: set[Path] = set()
    for line, record in zip(lines, records):
        key = sample_id(record["scenario"], int(record["capacity"]), int(record["round"]))
        log_name = f"{record['scenario']}_C{record['capacity']}_R{int(record['round']):02d}.stderr-time.log"
        log_path = stderr_dir / log_name
        if not log_path.is_file():
            fail(f"paired /usr/bin/time log is missing for {key}")
        expected_logs.add(log_path)
        entries[key] = {
            "rawLineSHA256": sha256_bytes(line),
            "timeLogPath": log_path.relative_to(REPOSITORY_DIR).as_posix(),
            "timeLogSHA256": sha256_file(log_path),
            **parse_time_log(log_path),
        }
    actual_logs = {path for path in stderr_dir.iterdir() if path.is_file()}
    if actual_logs != expected_logs or len(entries) != 140:
        fail("/usr/bin/time log set does not exactly match the 140 samples")
    manifest_path = output / "SAMPLE_LOG_MANIFEST.json"
    if manifest_path.exists():
        fail("sample log manifest already exists")
    manifest_path.write_bytes(canonical_json(entries))
    return entries


def sample_id(scenario: str, capacity: int, round_number: int) -> str:
    return f"{scenario}|C_CANONICAL_{capacity}|R{round_number:02d}"


def finalize(output: Path) -> dict[str, Any]:
    identity, identity_sha = verify_identity(output)
    raw_path = output / "RAW_SAMPLES.ndjson"
    raw_sha_path = output / "RAW_SAMPLES_SHA256.txt"
    logs_path = output / "SAMPLE_LOG_MANIFEST.json"
    probes_path = output / "RESOURCE_PROBES.ndjson"
    probes_sha_path = output / "RESOURCE_PROBES_SHA256.txt"
    if not all(path.is_file() for path in [raw_path, raw_sha_path, logs_path, probes_path, probes_sha_path]):
        fail("finalization inputs are incomplete")
    recorded_raw_sha = raw_sha_path.read_text().split()[0]
    if recorded_raw_sha != sha256_file(raw_path):
        fail("raw sample file checksum mismatch")
    recorded_probe_sha = probes_sha_path.read_text().split()[0]
    if recorded_probe_sha != sha256_file(probes_path):
        fail("resource probe file checksum mismatch")
    probe_records = validate_probe_records(probes_path, prepared_output=output)
    log_manifest = json.loads(logs_path.read_text())
    if not isinstance(log_manifest, dict):
        fail("sample log manifest is not an object")
    raw_lines = raw_path.read_bytes().splitlines(keepends=True)
    if len(raw_lines) != 140:
        fail(f"raw sample matrix has {len(raw_lines)} lines, expected 140")
    samples = []
    raw_hash_by_id: dict[str, str] = {}
    for line in raw_lines:
        if not line.strip():
            fail("raw sample file contains an empty line")
        record = json.loads(line)
        samples.append(record)
        key = sample_id(record["scenario"], int(record["capacity"]), int(record["round"]))
        raw_hash_by_id[key] = sha256_bytes(line)
    expected_ids = {
        sample_id(scenario, capacity, round_number)
        for scenario in SCENARIOS for capacity in CAPACITIES for round_number in range(1, 8)
    }
    observed_ids = [sample_id(item.get("scenario", ""), int(item.get("capacity", 0)), int(item.get("round", 0))) for item in samples]
    if len(set(observed_ids)) != 140 or set(observed_ids) != expected_ids:
        fail("timed sample identities are duplicated or do not form the exact 140-sample matrix")
    if set(log_manifest) != expected_ids:
        fail("sample/time-log manifest does not exactly cover the 140 sample identities")
    checksums_by_scenario: dict[str, set[str]] = {scenario: set() for scenario in SCENARIOS}
    sample_groups: dict[tuple[str, int], list[dict[str, Any]]] = {}
    cpu_rss: dict[tuple[str, int], list[dict[str, int | float | None]]] = {}
    for record, key in zip(samples, observed_ids):
        scenario = record["scenario"]
        capacity = int(record["capacity"])
        round_number = int(record["round"])
        spec = SCENARIOS[scenario]
        if record.get("schemaVersion") != 1 or record.get("correctness") != "PASS":
            fail(f"sample schema/correctness check failed: {key}")
        if record.get("benchmarkVersion") != "v1.1-wave03b-preselection-1":
            fail(f"unexpected benchmark version: {key}")
        if record.get("gitHead") != identity["head"]:
            fail(f"sample HEAD differs from prepared identity: {key}")
        if record.get("productManifestSHA256") != identity["productManifestSHA256"]:
            fail(f"sample Product manifest identity differs: {key}")
        if record.get("preparedRunIdentitySHA256") != identity_sha or record.get("preparedBinarySHA256") != identity["preparedBinary"]["sha256"]:
            fail(f"sample prepared binary/run identity differs: {key}")
        if record.get("lane") != f"C_CANONICAL_{capacity}" or record.get("warmupOperations") != spec["warmup"] or record.get("measuredOperations") != spec["measured"] or record.get("concurrency") != spec["concurrency"]:
            fail(f"sample workload identity differs from the contract: {key}")
        latencies = record.get("totalOperationLatenciesNanoseconds")
        waits = record.get("checkoutWaitLatenciesNanoseconds")
        if not isinstance(latencies, list) or not isinstance(waits, list) or len(latencies) != spec["measured"] or len(waits) != spec["measured"]:
            fail(f"sample latency vector has the wrong length: {key}")
        if not all(isinstance(value, int) and value > 0 for value in latencies) or not all(isinstance(value, int) and value >= 0 for value in waits):
            fail(f"sample latency vector contains invalid values: {key}")
        if record.get("elapsedNanoseconds", 0) <= 0 or record.get("operationsPerSecond", 0) <= 0:
            fail(f"sample elapsed or throughput is not positive: {key}")
        expected_rate = spec["measured"] * 1_000_000_000 / record["elapsedNanoseconds"]
        if not math.isclose(record["operationsPerSecond"], expected_rate, rel_tol=1e-12):
            fail(f"sample throughput arithmetic is inconsistent: {key}")
        for prefix, vector in [("totalOperation", latencies), ("checkoutWait", waits)]:
            for suffix, fraction in [("P50", 0.50), ("P95", 0.95), ("P99", 0.99)]:
                if record.get(prefix + suffix + "Nanoseconds") != nearest_rank(vector, fraction):
                    fail(f"sample percentile arithmetic is inconsistent: {key} {prefix}{suffix}")
        if not re.fullmatch(r"[0-9a-f]+", str(record.get("checksum", ""))):
            fail(f"sample correctness checksum is malformed: {key}")
        checksums_by_scenario[scenario].add(record["checksum"])
        sample_groups.setdefault((scenario, capacity), []).append(record)
        log_item = log_manifest[key]
        if log_item.get("rawLineSHA256") != raw_hash_by_id[key]:
            fail(f"raw sample line checksum mismatch: {key}")
        time_log = Path(log_item.get("timeLogPath", ""))
        if not time_log.is_absolute():
            time_log = REPOSITORY_DIR / time_log
        if not time_log.is_file() or sha256_file(time_log) != log_item.get("timeLogSHA256"):
            fail(f"/usr/bin/time stderr log identity mismatch: {key}")
        time_metrics = parse_time_log(time_log)
        if time_metrics["maximumResidentSetBytes"] is None:
            fail(f"/usr/bin/time -l RSS is missing or unparsable: {key}")
        cpu_rss.setdefault((scenario, capacity), []).append(time_metrics)
    for scenario, checksums in checksums_by_scenario.items():
        if len(checksums) != 1:
            fail(f"deterministic correctness checksums disagree across lanes/rounds for {scenario}")
    summaries: dict[str, Any] = {}
    selection_input: dict[str, Any] = {"integrityPass": True, "capacities": {}}
    for capacity in CAPACITIES:
        cap_scenarios: dict[str, Any] = {}
        cap_resource_ok = True
        cap_max_borrowed = 0
        cap_current = 0
        cap_peak = 0
        cap_retire = 0
        cap_rss: list[int] = []
        for scenario in SCENARIOS:
            group = sample_groups[(scenario, capacity)]
            rates = [item["operationsPerSecond"] for item in group]
            elapsed_per_op = [item["elapsedNanoseconds"] / item["measuredOperations"] for item in group]
            total_p50 = [item["totalOperationP50Nanoseconds"] for item in group]
            total_p95 = [item["totalOperationP95Nanoseconds"] for item in group]
            total_p99 = [item["totalOperationP99Nanoseconds"] for item in group]
            wait_p50 = [item["checkoutWaitP50Nanoseconds"] for item in group]
            wait_p95 = [item["checkoutWaitP95Nanoseconds"] for item in group]
            wait_p99 = [item["checkoutWaitP99Nanoseconds"] for item in group]
            resources = next(item for item in probe_records if item["scenario"] == scenario and item["capacity"] == capacity)
            after = resources["after"]
            cap_max_borrowed = max(cap_max_borrowed, resources["maxSimultaneouslyBorrowedCanonicalClosures"])
            cap_current = max(cap_current, after["currentMaterializedConnectionCount"])
            cap_peak = max(cap_peak, after["peakMaterializedConnectionCount"])
            cap_retire += resources["retireCompletionDelta"]
            cap_resource_ok = cap_resource_ok and resources["resourceProbe"] == "PASS" and resources["correctness"] == "PASS"
            log_values = cpu_rss[(scenario, capacity)]
            rss_values = [item["maximumResidentSetBytes"] for item in log_values if item["maximumResidentSetBytes"] is not None]
            cap_rss.extend(rss_values)
            cap_scenarios[scenario] = {
                "rounds": 7,
                "medianOperationsPerSecond": statistics.median(rates),
                "minimumOperationsPerSecond": min(rates),
                "maximumOperationsPerSecond": max(rates),
                "medianElapsedNanosecondsPerOperation": statistics.median(elapsed_per_op),
                "medianTotalOperationP50Nanoseconds": statistics.median(total_p50),
                "medianTotalOperationP95Nanoseconds": statistics.median(total_p95),
                "medianTotalOperationP99Nanoseconds": statistics.median(total_p99),
                "medianCheckoutWaitP50Nanoseconds": statistics.median(wait_p50),
                "medianCheckoutWaitP95Nanoseconds": statistics.median(wait_p95),
                "medianCheckoutWaitP99Nanoseconds": statistics.median(wait_p99),
                "medianMaximumResidentSetBytes": statistics.median(rss_values) if rss_values else None,
                "maximumResidentSetBytes": max(rss_values) if rss_values else None,
                "medianUserCPUSeconds": statistics.median([item["userCPUSeconds"] for item in log_values if item["userCPUSeconds"] is not None]) if any(item["userCPUSeconds"] is not None for item in log_values) else None,
                "medianSystemCPUSeconds": statistics.median([item["systemCPUSeconds"] for item in log_values if item["systemCPUSeconds"] is not None]) if any(item["systemCPUSeconds"] is not None for item in log_values) else None,
                "correctnessChecksum": next(iter(checksums_by_scenario[scenario])),
                "resourceProbe": resources,
            }
            cap_scenarios[scenario]["sampleIdentities"] = [sample_id(scenario, capacity, round_number) for round_number in range(1, 8)]
        selection_input["capacities"][str(capacity)] = {
            "capacity": capacity,
            "resourceProbePass": cap_resource_ok and cap_retire == 0 and cap_max_borrowed <= capacity and cap_current <= capacity and cap_peak <= capacity,
            "correctnessPass": cap_resource_ok,
            "maxBorrowed": cap_max_borrowed,
            "currentCores": cap_current,
            "peakCores": cap_peak,
            "retireDelta": cap_retire,
            "scenarios": {
                scenario: {
                    "throughput": cap_scenarios[scenario]["medianOperationsPerSecond"],
                    "p95": cap_scenarios[scenario]["medianTotalOperationP95Nanoseconds"],
                }
                for scenario in SCENARIOS
            },
        }
        summaries[f"C_CANONICAL_{capacity}"] = cap_scenarios
    selection = evaluate_selection(selection_input)
    final = {
        "schemaVersion": 1,
        "productManifestSHA256": identity["productManifestSHA256"],
        "preparedRunIdentitySHA256": identity_sha,
        "preparedBinarySHA256": identity["preparedBinary"]["sha256"],
        "rawSamplesSHA256": recorded_raw_sha,
        "resourceProbesSHA256": recorded_probe_sha,
        "sampleCount": len(samples),
        "scenarioCount": len(SCENARIOS),
        "capacityCount": len(CAPACITIES),
        "roundsPerCell": 7,
        "summaries": summaries,
        "selection": selection,
    }
    (output / "SUMMARY.json").write_bytes(canonical_json(final))
    markdown = [
        "# Wave03B Finalized Timing Summary",
        "",
        "This report is generated only from the exact 140-sample matrix and its paired resource/time evidence.",
        "",
        f"Selection status: `{selection['status']}`",
        f"Selected capacity: `{selection.get('selectedCapacity')}`",
        "",
        "| Scenario | Capacity | Median ops/s | Median total p95 (ns) | Median checkout p95 (ns) | Median RSS (bytes) |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for capacity in CAPACITIES:
        for scenario in SCENARIOS:
            row = summaries[f"C_CANONICAL_{capacity}"][scenario]
            markdown.append(
                f"| {scenario} | {capacity} | {row['medianOperationsPerSecond']:.3f} | {row['medianTotalOperationP95Nanoseconds']:.0f} | {row['medianCheckoutWaitP95Nanoseconds']:.0f} | {row['medianMaximumResidentSetBytes'] if row['medianMaximumResidentSetBytes'] is not None else 'unavailable'} |"
            )
    markdown.extend(["", f"Raw sample SHA-256: `{recorded_raw_sha}`", f"Resource probe SHA-256: `{recorded_probe_sha}`", ""])
    (output / "SUMMARY.md").write_text("\n".join(markdown))
    (output / "SELECTION_STATUS.json").write_bytes(canonical_json(selection))
    return final


def command_line() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("entry-fence")
    sub.add_parser("create-manifest")
    sub.add_parser("verify-manifest")
    selftest = sub.add_parser("selftest-selection")
    selftest.add_argument("--output", type=Path)
    time_log_selftest = sub.add_parser("selftest-time-log")
    time_log_selftest.add_argument("--output", type=Path)
    identity = sub.add_parser("create-identity")
    identity.add_argument("--output", type=Path, required=True)
    identity.add_argument("--binary", type=Path, required=True)
    identity.add_argument("--swift633-log", type=Path, required=True)
    identity.add_argument("--swift64-log", type=Path, required=True)
    verify = sub.add_parser("verify-identity")
    verify.add_argument("--output", type=Path, required=True)
    values = sub.add_parser("identity-values")
    values.add_argument("--output", type=Path, required=True)
    probes = sub.add_parser("validate-probes")
    probes.add_argument("--path", type=Path, required=True)
    probes.add_argument("--output", type=Path)
    probes.add_argument("--prepared-output", type=Path)
    sample = sub.add_parser("validate-sample")
    sample.add_argument("--sample", type=Path, required=True)
    sample.add_argument("--output", type=Path, required=True)
    sample.add_argument("--scenario", choices=SCENARIOS, required=True)
    sample.add_argument("--capacity", type=int, choices=CAPACITIES, required=True)
    sample.add_argument("--round", type=int, choices=range(1, 8), required=True)
    logs = sub.add_parser("freeze-time-logs")
    logs.add_argument("--output", type=Path, required=True)
    logs.add_argument("--stderr-dir", type=Path, required=True)
    finalizer = sub.add_parser("finalize")
    finalizer.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        if arguments.command == "entry-fence":
            result = verify_entry_fence()
            print(f"ENTRY_FENCE=PASS candidatePaths={len(result['candidates'])} branch={result['branchRelation']}")
        elif arguments.command == "create-manifest":
            manifest = make_manifest()
            print(f"PRODUCT_MANIFEST=CREATED sha256={sha256_file(MANIFEST_PATH)} candidatePaths=28")
        elif arguments.command == "verify-manifest":
            manifest = verify_manifest()
            print(f"PRODUCT_MANIFEST=PASS sha256={sha256_file(MANIFEST_PATH)} productFenceSHA256={product_fence_identity(manifest)}")
        elif arguments.command == "selftest-selection":
            results = run_selection_selftests()
            payload = {"schemaVersion": 1, "evaluator": "evaluate_selection", "tests": results, "result": "PASS"}
            if arguments.output:
                arguments.output.write_bytes(canonical_json(payload))
            for result in results:
                print(f"{result['id']}={result['result']} status={result['status']} selected={result['selectedCapacity']} extension={result['requiredExtension']}")
            print("SELECTION_RULE_SELFTESTS=PASS cases=6/6")
        elif arguments.command == "selftest-time-log":
            results = run_time_log_parser_selftests()
            payload = {"schemaVersion": 1, "parser": "parse_time_log_text", "tests": results, "result": "PASS"}
            if arguments.output:
                arguments.output.write_bytes(canonical_json(payload))
            for result in results:
                print(f"{result['id']}={result['result']} rss={result['maximumResidentSetBytes']} user={result['userCPUSeconds']} sys={result['systemCPUSeconds']}")
            print("TIME_LOG_PARSER_SELFTESTS=PASS cases=3/3")
        elif arguments.command == "create-identity":
            identity = create_identity(arguments.output, arguments.binary, arguments.swift633_log, arguments.swift64_log)
            print(f"PREPARED_IDENTITY=CREATED sha256={sha256_file(arguments.output / 'PREPARED_RUN_IDENTITY.json')} binarySHA256={identity['preparedBinary']['sha256']} head={identity['head']}")
        elif arguments.command == "verify-identity":
            identity, identity_sha = verify_identity(arguments.output)
            print(f"PREPARED_IDENTITY=PASS sha256={identity_sha} binarySHA256={identity['preparedBinary']['sha256']} head={identity['head']}")
        elif arguments.command == "identity-values":
            identity_values(arguments.output)
        elif arguments.command == "validate-probes":
            records = validate_probe_records(arguments.path, arguments.output, arguments.prepared_output)
            print(f"RESOURCE_PROBE_SMOKE=PASS scenarioCapacityPairs={len(records)}/20")
        elif arguments.command == "validate-sample":
            validate_one_sample(arguments.sample, arguments.output, arguments.scenario, arguments.capacity, arguments.round)
            print(f"SAMPLE_IDENTITY=PASS scenario={arguments.scenario} capacity={arguments.capacity} round={arguments.round}")
        elif arguments.command == "freeze-time-logs":
            entries = freeze_time_logs(arguments.output, arguments.stderr_dir)
            print(f"TIME_LOG_MANIFEST=PASS samples={len(entries)}")
        elif arguments.command == "finalize":
            final = finalize(arguments.output)
            print(f"FINALIZE=PASS samples={final['sampleCount']} selection={final['selection']['status']} selected={final['selection'].get('selectedCapacity')}")
        return 0
    except (Blocked, OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"BLOCKED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(command_line())
