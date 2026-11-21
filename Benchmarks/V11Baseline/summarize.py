#!/usr/bin/env python3
"""Summarize and cheaply qualify Duck v1.1 Wave 00 benchmark evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import statistics
import stat
import subprocess
import sys
from pathlib import Path
from typing import Any

EXPECTED_HEAD = "c3d47f2951bd4997798a3dd846360b8f8238e2d1"
PROTECTED_PATH = "Examples/SwiftUI/DuckDemo.xcodeproj/project.pbxproj"
PROTECTED_SHA256 = "ef3a46629337a79867e0a31e9c76c10df8d773914887151e8b721a5b66b74436"
ROOT_PACKAGE_SWIFT_SHA256 = "0893f4fa885dbce85e1f843a9eb8370bc570643458522fd2ba09ec6f3a26a322"
ROOT_PACKAGE_RESOLVED_SHA256 = "a6b87888ee3eec785ebae1d87c41724b10abad34d82079da05990c88d5172f0e"
SQL_REVISION = "b0c81191c3494d91b84b5382092e99c64d5c4647"
SQL_VERSION = "3.1.0"
BENCHMARK_VERSION = "v1.1-wave00-correction-02"
PACKAGE_MANIFEST_SHA256 = "1609b906682f3106da5fdd1bb197378bc5c229727f5cf3a8c2640503e48a54ad"
PACKAGE_LOCK_SHA256 = "cc1dc7ae2bbc0bc3b9a17fc0b97f96baec8b292914d34ca6521739b3c1e4f559"
ATTEMPT_01_RAW_SHA256 = "a736d173ed2e113534040cff28221b80cd20e757e696bdc04f2f1082efac839f"
ATTEMPT_01_SUMMARY_SHA256 = "3f5487610c9e23638d0be17018ba017c6322134d40799a18372baf886e681b4f"
ATTEMPT_01_MANIFEST_SHA256 = "7af9a323de3f52236ab41089e45d44a6d097244e449f9b786c8deb75150b8aaa"
CORRECTION_01_RAW_SHA256 = "eb857bb622fa36fec71725b4b22d9ac4e11ee19f3cdc2c181fd0720efdfa2077"
CORRECTION_01_SUMMARY_SHA256 = "226936d7a73030770842b2a026a4783a80ed97d53c7b5031cc2809b02cff12d1"
CORRECTION_01_MANIFEST_SHA256 = "39eccf2926ee8d055c8887c0a7e638b454904b356c1374f633104d75995d0b33"
SWIFT_6_3_3_DEVELOPER = "/Applications/Xcode-26-6.app/Contents/Developer"
SWIFT_6_3_3_SCRATCH_RELATIVE = ".build/wave00-correction02/swift-6.3.3"
SWIFT_6_4_SCRATCH_RELATIVE = ".build/wave00-correction02/swift-6.4"
CORRECTION_02_EVIDENCE_RELATIVE = ".artifacts/benchmarks/v1-1-wave00-a-b-baseline-correction-02-2026-11-20"
PRE_BUILD_FENCE_NAME = "PRE_BUILD_PRODUCT_INPUT_FENCE.json"
PRE_BUILD_FENCE_SHA_NAME = "PRE_BUILD_PRODUCT_INPUT_FENCE_SHA256.txt"
CANDIDATE_PATHS = [
    "Benchmarks/V11Baseline/Package.swift",
    "Benchmarks/V11Baseline/Package.resolved",
    "Benchmarks/V11Baseline/README.md",
    "Benchmarks/V11Baseline/Sources/DuckV11Baseline/main.swift",
    "Benchmarks/V11Baseline/run-wave00.sh",
    "Benchmarks/V11Baseline/summarize.py",
]

SPECS = {
    "Q01_SMALL_READ_SEQ": {"warmupOperations": 100, "measuredOperations": 1000, "concurrency": 1, "lanes": ["A_ORDINARY", "B_POOL_1", "B_POOL_4"]},
    "Q02_SMALL_READ_CONCURRENT": {"warmupOperations": 80, "measuredOperations": 1000, "concurrency": 8, "lanes": ["A_ORDINARY", "B_POOL_1", "B_POOL_4", "B_POOL_8"]},
    "T01_TRANSACTION_SEQ": {"warmupOperations": 10, "measuredOperations": 100, "concurrency": 1, "lanes": ["A_ORDINARY", "B_POOL_1", "B_POOL_4"]},
    "P01_APPENDER_BATCH_SEQ": {"warmupOperations": 3, "measuredOperations": 30, "concurrency": 1, "lanes": ["A_ORDINARY", "B_POOL_1", "B_POOL_4"]},
}
RESOURCE_PROBES = [
    ("Q01_SMALL_READ_SEQ", "B_POOL_1"),
    ("Q01_SMALL_READ_SEQ", "B_POOL_4"),
    ("Q02_SMALL_READ_CONCURRENT", "B_POOL_1"),
    ("Q02_SMALL_READ_CONCURRENT", "B_POOL_4"),
    ("Q02_SMALL_READ_CONCURRENT", "B_POOL_8"),
    ("P01_APPENDER_BATCH_SEQ", "B_POOL_1"),
    ("P01_APPENDER_BATCH_SEQ", "B_POOL_4"),
    ("R01_CONNECTION_IDENTITY", "A_FRESH_EXPLICIT"),
    ("R01_CONNECTION_IDENTITY", "B_POOL_4"),
]


class EvidenceError(Exception):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf-8")


def command_output(arguments: list[str], developer_directory: str | None = None) -> str:
    environment = os.environ.copy()
    if developer_directory is not None:
        environment["DEVELOPER_DIR"] = developer_directory
    completed = subprocess.run(arguments, text=True, env=environment, capture_output=True, check=True)
    return "\n".join(part.strip() for part in (completed.stdout, completed.stderr) if part.strip())


def git_blob_sha1(content: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(content)).encode("ascii") + b"\0" + content).hexdigest()


def git_sources_entries(repository: Path) -> list[dict[str, str]]:
    output = subprocess.run(
        ["git", "-C", str(repository), "ls-tree", "-r", "-z", "--full-tree", "HEAD", "--", "Sources"],
        check=True,
        capture_output=True,
    ).stdout
    entries: list[dict[str, str]] = []
    directories = {"Sources"}
    for item in output.split(b"\0"):
        if not item:
            continue
        metadata, raw_path = item.split(b"\t", 1)
        mode, object_type, object_id = metadata.decode("ascii").split()
        if object_type != "blob":
            raise EvidenceError(f"HEAD Sources entry is not a Git blob: {os.fsdecode(raw_path)}")
        relative_path = os.fsdecode(raw_path)
        path_parts = relative_path.split("/")
        directories.update("/".join(path_parts[:index]) for index in range(1, len(path_parts)))
        entries.append({
            "path": relative_path,
            "mode": mode,
            "objectType": object_type,
            "gitBlobSHA1": object_id,
        })
    entries.extend(
        {"path": directory, "mode": "040000", "objectType": "tree"}
        for directory in directories
    )
    return sorted(entries, key=lambda entry: entry["path"].encode("utf-8"))


def filesystem_sources_entries(repository: Path) -> list[dict[str, str]]:
    sources_root = repository / "Sources"
    if not sources_root.is_dir() or sources_root.is_symlink():
        raise EvidenceError("Sources directory is missing")
    pending = [sources_root]
    entries: list[dict[str, str]] = [{"path": "Sources", "mode": "040000", "objectType": "tree"}]
    while pending:
        directory = pending.pop()
        try:
            children = sorted(os.scandir(directory), key=lambda entry: os.fsencode(entry.name))
        except OSError as error:
            raise EvidenceError(f"cannot enumerate Product Sources directory {directory}: {error}") from error
        for child in children:
            path = Path(child.path)
            relative = path.relative_to(repository).as_posix()
            try:
                info = child.stat(follow_symlinks=False)
                if stat.S_ISDIR(info.st_mode):
                    entries.append({"path": relative, "mode": "040000", "objectType": "tree"})
                    pending.append(path)
                    continue
                if stat.S_ISLNK(info.st_mode):
                    content = os.fsencode(os.readlink(path))
                    mode = "120000"
                    object_type = "blob"
                elif stat.S_ISREG(info.st_mode):
                    content = path.read_bytes()
                    mode = "100755" if info.st_mode & 0o111 else "100644"
                    object_type = "blob"
                else:
                    raise EvidenceError(f"unsupported filesystem entry under Sources: {relative}")
            except OSError as error:
                raise EvidenceError(f"cannot read Product Sources entry {relative}: {error}") from error
            entries.append({
                "path": relative,
                "mode": mode,
                "objectType": object_type,
                "gitBlobSHA1": git_blob_sha1(content),
                "contentSHA256": hashlib.sha256(content).hexdigest(),
            })
    return sorted(entries, key=lambda entry: entry["path"].encode("utf-8"))


def source_tree_identity(entries: list[dict[str, str]]) -> str:
    comparable = source_entry_identity(entries)
    return hashlib.sha256(canonical_json(comparable)).hexdigest()


def source_entry_identity(entries: list[dict[str, str]]) -> list[dict[str, str]]:
    comparable = []
    for entry in entries:
        identity = {key: entry[key] for key in ("path", "mode", "objectType")}
        if entry["objectType"] == "blob":
            identity["gitBlobSHA1"] = entry["gitBlobSHA1"]
        comparable.append(identity)
    return comparable


def ignored_non_product_entries(
    repository: Path,
    head_entries: list[dict[str, str]],
    filesystem_entries: list[dict[str, str]],
) -> list[dict[str, str]]:
    tracked_paths = {entry["path"] for entry in head_entries}
    ignored: list[dict[str, str]] = []
    for entry in filesystem_entries:
        relative = entry["path"]
        if (
            relative in tracked_paths
            or Path(relative).name != ".DS_Store"
            or entry["objectType"] != "blob"
            or entry["mode"] != "100644"
        ):
            continue
        result = subprocess.run(
            ["git", "-C", str(repository), "check-ignore", "-q", "--", relative],
            check=False,
        )
        if result.returncode == 0:
            ignored.append(entry)
        elif result.returncode != 1:
            raise EvidenceError(f"could not classify ignored Finder metadata path: {relative}")
    return ignored


def check_index_product_inputs(repository: Path) -> None:
    result = subprocess.run(
        ["git", "-C", str(repository), "diff", "--cached", "--quiet", "HEAD", "--", "Sources", "Package.swift", "Package.resolved"],
        check=False,
    )
    if result.returncode != 0:
        raise EvidenceError("staged Product Sources or root package input differs from HEAD")
    if subprocess.run(["git", "-C", str(repository), "diff", "--cached", "--quiet"], check=False).returncode != 0:
        raise EvidenceError("Git index must remain empty during the benchmark stage")


def product_sources_state(
    repository: Path,
) -> tuple[
    str,
    list[dict[str, str]],
    list[dict[str, str]],
    list[dict[str, str]],
    str,
    str,
]:
    head = command_output(["git", "-C", str(repository), "rev-parse", "HEAD"])
    if head != EXPECTED_HEAD:
        raise EvidenceError(f"Git HEAD differs from the frozen Product input fence: {head}")
    head_entries = git_sources_entries(repository)
    worktree_entries = filesystem_sources_entries(repository)
    ignored_entries = ignored_non_product_entries(repository, head_entries, worktree_entries)
    ignored_paths = {entry["path"] for entry in ignored_entries}
    product_worktree_entries = [entry for entry in worktree_entries if entry["path"] not in ignored_paths]
    head_identity = source_tree_identity(head_entries)
    worktree_identity = source_tree_identity(product_worktree_entries)
    if head_identity != worktree_identity or source_entry_identity(head_entries) != source_entry_identity(product_worktree_entries):
        raise EvidenceError("WORKTREE_SOURCES_FILESYSTEM_SET_AND_CONTENT does not equal HEAD_SOURCES_TREE")
    check_index_product_inputs(repository)
    return head, head_entries, worktree_entries, ignored_entries, head_identity, worktree_identity


def candidate_hashes(repository: Path) -> dict[str, str]:
    return {relative: sha256(repository / relative) for relative in CANDIDATE_PATHS}


def create_pre_build_product_fence(repository: Path, package: Path, output: Path) -> tuple[dict[str, Any], str]:
    fence_path = output / PRE_BUILD_FENCE_NAME
    sha_path = output / PRE_BUILD_FENCE_SHA_NAME
    if fence_path.exists() or sha_path.exists():
        raise EvidenceError("refusing to overwrite pre-build Product input fence")
    head, head_entries, worktree_entries, ignored_entries, head_identity, worktree_identity = product_sources_state(repository)
    ignored_paths = {entry["path"] for entry in ignored_entries}
    root_package_sha = sha256(repository / "Package.swift")
    root_resolved_sha = sha256(repository / "Package.resolved")
    if root_package_sha != ROOT_PACKAGE_SWIFT_SHA256 or root_resolved_sha != ROOT_PACKAGE_RESOLVED_SHA256:
        raise EvidenceError("root Package.swift/Package.resolved differs from the accepted baseline")
    hashes = candidate_hashes(repository)
    if hashes["Benchmarks/V11Baseline/Package.swift"] != PACKAGE_MANIFEST_SHA256:
        raise EvidenceError("nested Package.swift differs from its frozen candidate identity")
    if hashes["Benchmarks/V11Baseline/Package.resolved"] != PACKAGE_LOCK_SHA256:
        raise EvidenceError("nested Package.resolved differs from its frozen candidate identity")
    ignored_paths = {entry["path"] for entry in ignored_entries}
    product_worktree_entries = [entry for entry in worktree_entries if entry["path"] not in ignored_paths]
    sources_match = source_entry_identity(head_entries) == source_entry_identity(product_worktree_entries)
    if not sources_match:
        raise EvidenceError("WORKTREE_SOURCES_FILESYSTEM_SET_AND_CONTENT does not equal HEAD_SOURCES_TREE")
    fence: dict[str, Any] = {
        "schemaVersion": 1,
        "gitHead": head,
        "rootPackageSwiftSHA256": root_package_sha,
        "rootPackageResolvedSHA256": root_resolved_sha,
        "sourcesTreeIdentity": head_identity,
        "sourcesEntryCount": len(head_entries),
        "sourcesFilesystemEntryCount": len(worktree_entries),
        "sourcesHeadEntries": head_entries,
        "sourcesFilesystemEntries": worktree_entries,
        "sourcesFilesystemProductEntries": [entry for entry in worktree_entries if entry["path"] not in ignored_paths],
        "nonProductIgnoredFilesystemEntries": ignored_entries,
        "nonProductIgnoredFilesystemPolicy": (
            "Git-ignored regular .DS_Store Finder metadata is recorded with content SHA-256 but excluded from the SwiftPM Product input equality."
        ),
        "productSourcesMatchHead": True,
        "candidatePreBuildSHA256": hashes,
    }
    data = canonical_json(fence)
    fence_sha = hashlib.sha256(data).hexdigest()
    fence_path.write_bytes(data)
    sha_path.write_text(f"{fence_sha}\n", encoding="utf-8")
    return fence, fence_sha


def verify_pre_build_product_fence(repository: Path, package: Path, output: Path) -> tuple[dict[str, Any], str]:
    fence_path = output / PRE_BUILD_FENCE_NAME
    sha_path = output / PRE_BUILD_FENCE_SHA_NAME
    data = fence_path.read_bytes()
    try:
        fence = json.loads(data)
    except json.JSONDecodeError as error:
        raise EvidenceError(f"pre-build Product input fence is invalid JSON: {error}") from error
    fence_sha = hashlib.sha256(data).hexdigest()
    if data != canonical_json(fence) or sha_path.read_text(encoding="utf-8") != f"{fence_sha}\n":
        raise EvidenceError("pre-build Product input fence JSON or SHA file is not canonical/consistent")
    if fence.get("schemaVersion") != 1 or fence.get("productSourcesMatchHead") is not True:
        raise EvidenceError("pre-build Product input fence schema/result is invalid")
    if fence.get("nonProductIgnoredFilesystemPolicy") != (
        "Git-ignored regular .DS_Store Finder metadata is recorded with content SHA-256 but excluded from the SwiftPM Product input equality."
    ):
        raise EvidenceError("pre-build Product input fence Finder metadata policy is invalid")
    head, head_entries, worktree_entries, ignored_entries, head_identity, worktree_identity = product_sources_state(repository)
    if head != fence.get("gitHead") or head_entries != fence.get("sourcesHeadEntries"):
        raise EvidenceError("current HEAD Sources tree differs from the frozen pre-build Product fence")
    if worktree_entries != fence.get("sourcesFilesystemEntries"):
        raise EvidenceError("current Sources filesystem path/content set differs from the frozen pre-build Product fence")
    if ignored_entries != fence.get("nonProductIgnoredFilesystemEntries"):
        raise EvidenceError("ignored Finder metadata inventory differs from the frozen Product fence")
    ignored_paths = {entry["path"] for entry in ignored_entries}
    product_worktree_entries = [entry for entry in worktree_entries if entry["path"] not in ignored_paths]
    if product_worktree_entries != fence.get("sourcesFilesystemProductEntries"):
        raise EvidenceError("current Sources Product input entries differ from the frozen Product fence")
    if len(worktree_entries) != fence.get("sourcesFilesystemEntryCount"):
        raise EvidenceError("pre-build Product fence Sources filesystem entry count is incorrect")
    if head_identity != fence.get("sourcesTreeIdentity") or worktree_identity != head_identity:
        raise EvidenceError("current Sources deterministic tree identity differs from the frozen Product fence")
    if fence.get("sourcesEntryCount") != len(head_entries):
        raise EvidenceError("pre-build Product fence Sources entry count is incorrect")
    root_package_sha = sha256(repository / "Package.swift")
    root_resolved_sha = sha256(repository / "Package.resolved")
    if root_package_sha != fence.get("rootPackageSwiftSHA256") or root_package_sha != ROOT_PACKAGE_SWIFT_SHA256:
        raise EvidenceError("root Package.swift differs from the pre-build Product fence")
    if root_resolved_sha != fence.get("rootPackageResolvedSHA256") or root_resolved_sha != ROOT_PACKAGE_RESOLVED_SHA256:
        raise EvidenceError("root Package.resolved differs from the pre-build Product fence")
    hashes = candidate_hashes(repository)
    if hashes != fence.get("candidatePreBuildSHA256"):
        raise EvidenceError("one or more benchmark candidate files differ from the pre-build hash map")
    if hashes["Benchmarks/V11Baseline/Package.swift"] != PACKAGE_MANIFEST_SHA256:
        raise EvidenceError("nested Package.swift differs from its frozen candidate identity")
    if hashes["Benchmarks/V11Baseline/Package.resolved"] != PACKAGE_LOCK_SHA256:
        raise EvidenceError("nested Package.resolved differs from its frozen candidate identity")
    return fence, fence_sha


def sql_pin(repository: Path) -> dict[str, str]:
    resolved = json.loads((repository / "Benchmarks/V11Baseline/Package.resolved").read_text(encoding="utf-8"))
    pins = resolved.get("pins", [])
    if len(pins) != 1 or pins[0].get("identity") != "sql":
        raise EvidenceError("nested Package.resolved must contain only the local Duck package's SQL dependency")
    pin = pins[0]
    state = pin.get("state", {})
    identity = {
        "location": str(pin.get("location", "")),
        "version": str(state.get("version", "")),
        "revision": str(state.get("revision", "")),
    }
    if identity != {
        "location": "https://github.com/SwiftStream/SQL",
        "version": SQL_VERSION,
        "revision": SQL_REVISION,
    }:
        raise EvidenceError("nested Package.resolved SQL pin differs from the frozen SQL 3.1.0 revision")
    return identity


def verify_sql_checkout(package: Path, scratch_relative: str) -> dict[str, Any]:
    pin = sql_pin(package.parent.parent)
    scratch = package / scratch_relative
    checkout_root = scratch / "checkouts"
    if not checkout_root.is_dir():
        raise EvidenceError(f"SwiftPM dependency checkout directory is missing: {checkout_root}")
    checkout_directories = sorted(
        (path for path in checkout_root.iterdir() if path.is_dir()),
        key=lambda path: path.name.casefold(),
    )
    actual_identities = [path.name.casefold() for path in checkout_directories]
    if actual_identities != ["sql"]:
        raise EvidenceError(f"unexpected SwiftPM dependency checkouts: {actual_identities}")
    checkout = checkout_directories[0].resolve(strict=True)
    if scratch.resolve() not in checkout.parents:
        raise EvidenceError("SQL checkout resolves outside the fresh toolchain scratch path")
    revision = command_output(["git", "-C", str(checkout), "rev-parse", "HEAD"])
    status = subprocess.run(
        ["git", "-C", str(checkout), "status", "--porcelain=v1", "--untracked-files=all"],
        check=True,
        text=True,
        capture_output=True,
    ).stdout
    if revision != SQL_REVISION or status:
        raise EvidenceError(f"SQL checkout identity/cleanliness mismatch: revision={revision}, status={status!r}")
    if subprocess.run(["git", "-C", str(checkout), "diff", "--quiet"], check=False).returncode != 0:
        raise EvidenceError("SQL checkout working tree diff is not clean")
    if subprocess.run(["git", "-C", str(checkout), "diff", "--cached", "--quiet"], check=False).returncode != 0:
        raise EvidenceError("SQL checkout index is not clean")
    return {
        "path": checkout.relative_to(package).as_posix(),
        "revision": revision,
        "version": pin["version"],
        "workingTreeClean": True,
        "indexClean": True,
    }


def verify_live_build_inputs(
    repository: Path,
    package: Path,
    output: Path,
    scratch_relatives: list[str],
) -> tuple[dict[str, Any], str, dict[str, dict[str, Any]]]:
    repository = repository.resolve()
    package = package.resolve()
    fence, fence_sha = verify_pre_build_product_fence(repository, package, output)
    branch = command_output(["git", "-C", str(repository), "branch", "--show-current"])
    relation = command_output([
        "git", "-C", str(repository), "rev-list", "--left-right", "--count", "origin/master...master"
    ]).split()
    if branch != "master" or relation != ["0", "10"]:
        raise EvidenceError(f"Git branch relation differs from the frozen fence: {branch} {relation}")
    if sha256(repository / PROTECTED_PATH) != PROTECTED_SHA256:
        raise EvidenceError("protected maintainer WIP SHA-256 differs from the authorized fence")
    sql_checkouts = {
        relative: verify_sql_checkout(package, relative)
        for relative in scratch_relatives
    }
    return fence, fence_sha, sql_checkouts


def build_prepared_identity(
    repository: Path,
    package: Path,
    binary: Path,
    output: Path,
) -> dict[str, Any]:
    repository = repository.resolve()
    package = package.resolve()
    binary_sha = verify_evidence_binary_path(binary, output)
    fence, fence_sha, sql_checkouts = verify_live_build_inputs(
        repository,
        package,
        output,
        [SWIFT_6_3_3_SCRATCH_RELATIVE, SWIFT_6_4_SCRATCH_RELATIVE],
    )
    binary = binary.resolve(strict=True)

    head = command_output(["git", "-C", str(repository), "rev-parse", "HEAD"])
    branch = command_output(["git", "-C", str(repository), "branch", "--show-current"])
    relation_counts = command_output([
        "git", "-C", str(repository), "rev-list", "--left-right", "--count", "origin/master...master"
    ]).split()
    if head != EXPECTED_HEAD or branch != "master" or relation_counts != ["0", "10"]:
        raise EvidenceError(f"Git identity differs from the frozen fence: HEAD={head}, branch={branch}, counts={relation_counts}")
    protected_sha = sha256(repository / PROTECTED_PATH)
    root_package_sha = sha256(repository / "Package.swift")
    root_resolved_sha = sha256(repository / "Package.resolved")
    if protected_sha != PROTECTED_SHA256:
        raise EvidenceError("protected maintainer WIP SHA-256 differs from the authorized fence")
    if root_package_sha != ROOT_PACKAGE_SWIFT_SHA256 or root_resolved_sha != ROOT_PACKAGE_RESOLVED_SHA256:
        raise EvidenceError("root package identity differs from the accepted Wave 00 baseline")

    candidate_hashes_after_build = candidate_hashes(repository)
    if candidate_hashes_after_build != fence["candidatePreBuildSHA256"]:
        raise EvidenceError("candidate file hashes differ from their pre-build Product fence")
    if candidate_hashes_after_build["Benchmarks/V11Baseline/Package.swift"] != PACKAGE_MANIFEST_SHA256:
        raise EvidenceError("nested Package.swift changed from the frozen Attempt 01 candidate identity")
    if candidate_hashes_after_build["Benchmarks/V11Baseline/Package.resolved"] != PACKAGE_LOCK_SHA256:
        raise EvidenceError("nested Package.resolved changed from the frozen Attempt 01 candidate identity")

    swift_compiler = command_output(["/usr/bin/xcrun", "swiftc", "-version"], SWIFT_6_3_3_DEVELOPER)
    swift_tool = command_output(["/usr/bin/xcrun", "swift", "--version"], SWIFT_6_3_3_DEVELOPER)
    xcode = command_output(["/usr/bin/xcodebuild", "-version"], SWIFT_6_3_3_DEVELOPER)
    if "Swift version 6.3.3" not in swift_compiler or "Swift version 6.3.3" not in swift_tool:
        raise EvidenceError("selected timing toolchain is not Swift 6.3.3")
    if not xcode.startswith("Xcode 26.6"):
        raise EvidenceError("selected timing toolchain is not Xcode 26.6")

    return {
        "schemaVersion": 1,
        "benchmarkVersion": BENCHMARK_VERSION,
        "productInputFenceSHA256": fence_sha,
        "preBuildProductInputFence": {
            "path": PRE_BUILD_FENCE_NAME,
            "sha256": fence_sha,
        },
        "git": {
            "head": head,
            "branch": branch,
            "relation": "master...origin/master [ahead 10]",
            "protectedPath": PROTECTED_PATH,
            "protectedSHA256": protected_sha,
        },
        "toolchain": {
            "developerDirectory": SWIFT_6_3_3_DEVELOPER,
            "swiftCompilerVersion": swift_compiler,
            "swiftToolVersion": swift_tool,
            "xcodeVersion": xcode,
        },
        "releaseBinary": {
            "path": str(binary),
            "sha256": binary_sha,
        },
        "candidateFiles": candidate_hashes_after_build,
        "rootPackageSwiftSHA256": root_package_sha,
        "rootPackageResolvedSHA256": root_resolved_sha,
        "nestedPackageResolvedSHA256": candidate_hashes_after_build["Benchmarks/V11Baseline/Package.resolved"],
        "sql": {
            **sql_pin(repository),
            "toolchainCheckouts": sql_checkouts,
        },
    }


def verify_evidence_binary_path(binary: Path, output: Path) -> str:
    candidate = Path(binary)
    expected = output.resolve() / "PREPARED_BINARY" / "DuckV11Baseline"
    if candidate.is_symlink():
        raise EvidenceError("prepared evidence binary must be a regular file, not a symlink")
    try:
        resolved = candidate.resolve(strict=True)
    except FileNotFoundError as error:
        raise EvidenceError(f"preserved prepared evidence binary is missing: {candidate}") from error
    if resolved != expected.resolve():
        raise EvidenceError(f"prepared executable is not the evidence-owned PREPARED_BINARY/DuckV11Baseline: {resolved}")
    if not resolved.is_file() or not os.access(resolved, os.X_OK):
        raise EvidenceError(f"preserved prepared Release executable is not an executable regular file: {resolved}")
    return sha256(resolved)


def preserve_binary_command(args: argparse.Namespace) -> None:
    source = Path(args.source).resolve(strict=True)
    destination = Path(args.destination)
    if destination.name != "DuckV11Baseline" or destination.parent.name != "PREPARED_BINARY":
        raise EvidenceError("preserved binary destination must be PREPARED_BINARY/DuckV11Baseline")
    if destination.exists() or destination.is_symlink():
        raise EvidenceError(f"refusing to overwrite preserved prepared binary: {destination}")
    if not source.is_file() or not os.access(source, os.X_OK):
        raise EvidenceError(f"source Release executable is not an executable regular file: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    source_sha = sha256(source)
    preserved_sha = sha256(destination)
    source_mode = stat.S_IMODE(source.stat().st_mode)
    preserved_mode = stat.S_IMODE(destination.stat().st_mode)
    if source_sha != preserved_sha or source_mode != preserved_mode or not os.access(destination, os.X_OK):
        raise EvidenceError("preserved binary bytes or executable mode differ from the built Release executable")
    print(
        "PRESERVED_BINARY=PASS\n"
        f"sourceSHA256={source_sha}\n"
        f"preservedSHA256={preserved_sha}\n"
        f"sourceMode={source_mode:04o}\n"
        f"preservedMode={preserved_mode:04o}\n"
        f"evidencePath={destination}"
    )


def verify_prepared_identity(
    repository: Path,
    package: Path,
    binary: Path,
    identity_path: Path,
    sha_path: Path,
) -> tuple[str, str, str]:
    identity_bytes = identity_path.read_bytes()
    try:
        identity = json.loads(identity_bytes)
    except json.JSONDecodeError as error:
        raise EvidenceError(f"prepared run identity is invalid JSON: {error}") from error
    if identity_bytes != canonical_json(identity):
        raise EvidenceError("prepared run identity is not canonical sorted-key JSON")
    if identity != build_prepared_identity(repository, package, binary, identity_path.parent):
        raise EvidenceError("one or more frozen prepared run identities changed")
    identity_sha = hashlib.sha256(identity_bytes).hexdigest()
    expected_sha_file = f"{identity_sha}\n"
    if sha_path.read_text(encoding="utf-8") != expected_sha_file:
        raise EvidenceError("PREPARED_RUN_IDENTITY_SHA256.txt does not match the identity JSON bytes")
    return identity_sha, identity["releaseBinary"]["sha256"], identity["productInputFenceSHA256"]


def create_prepared_identity(args: argparse.Namespace) -> None:
    identity_path = Path(args.identity)
    sha_path = Path(args.sha_file)
    if identity_path.exists() or sha_path.exists():
        raise EvidenceError("refusing to overwrite prepared-run identity evidence")
    identity = build_prepared_identity(
        Path(args.repository), Path(args.package), Path(args.binary), identity_path.parent
    )
    identity_bytes = canonical_json(identity)
    identity_path.write_bytes(identity_bytes)
    identity_sha = hashlib.sha256(identity_bytes).hexdigest()
    sha_path.write_text(f"{identity_sha}\n", encoding="utf-8")
    verified_sha, binary_sha, fence_sha = verify_prepared_identity(
        Path(args.repository), Path(args.package), Path(args.binary), identity_path, sha_path
    )
    print(
        "PREPARED_RUN_IDENTITY_CREATED=PASS\n"
        f"preparedRunIdentitySHA256={verified_sha}\n"
        f"preparedBinarySHA256={binary_sha}\n"
        f"productInputFenceSHA256={fence_sha}"
    )


def create_product_fence_command(args: argparse.Namespace) -> None:
    repository = Path(args.repository).resolve()
    package = Path(args.package).resolve()
    output = Path(args.output_dir)
    output.mkdir(parents=True, exist_ok=True)
    _, fence_sha = create_pre_build_product_fence(repository, package, output)
    print(f"PRE_BUILD_PRODUCT_INPUT_FENCE=PASS\nproductInputFenceSHA256={fence_sha}")


def verify_build_inputs_command(args: argparse.Namespace) -> None:
    repository = Path(args.repository).resolve()
    package = Path(args.package).resolve()
    output = Path(args.output_dir)
    scratch_relatives = list(args.scratch_relative)
    _, fence_sha, sql_checkouts = verify_live_build_inputs(
        repository, package, output, scratch_relatives
    )
    print(f"PRODUCT_INPUT_FENCE=PASS\nproductInputFenceSHA256={fence_sha}")
    for scratch, checkout in sql_checkouts.items():
        print(f"SQL_CHECKOUT_IDENTITY=PASS scratch={scratch} revision={checkout['revision']} path={checkout['path']}")


def write_harness_identities(args: argparse.Namespace) -> None:
    repository = Path(args.repository).resolve()
    package = Path(args.package).resolve()
    output = Path(args.output)
    if output.exists():
        raise EvidenceError(f"refusing to overwrite harness identities: {output}")
    lines = ["# Correction 02 Harness Identities", "", "SHA-256\tRepository-relative path"]
    lines.extend(f"{sha256(repository / relative)}\t{relative}" for relative in CANDIDATE_PATHS)
    identity_path = output.parent / "PREPARED_RUN_IDENTITY.json"
    sha_path = output.parent / "PREPARED_RUN_IDENTITY_SHA256.txt"
    identity = json.loads(identity_path.read_text(encoding="utf-8"))
    identity_sha = sha_path.read_text(encoding="utf-8").strip()
    lines.extend([
        "",
        f"preparedRunIdentitySHA256\t{identity_sha}",
        f"preparedBinarySHA256\t{identity['releaseBinary']['sha256']}",
        f"productInputFenceSHA256\t{identity['productInputFenceSHA256']}",
        f"preparedBinaryPath\t{identity['releaseBinary']['path']}",
    ])
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")


def read_json_lines(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            raise EvidenceError(f"{path}:{line_number}: empty NDJSON line")
        try:
            record = json.loads(line)
        except json.JSONDecodeError as error:
            raise EvidenceError(f"{path}:{line_number}: invalid JSON: {error}") from error
        if not isinstance(record, dict):
            raise EvidenceError(f"{path}:{line_number}: expected a JSON object")
        records.append(record)
    return records


def read_prepared_identity_evidence(output: Path, repository: Path) -> tuple[dict[str, Any], str, str]:
    identity_path = output / "PREPARED_RUN_IDENTITY.json"
    sha_path = output / "PREPARED_RUN_IDENTITY_SHA256.txt"
    identity_bytes = identity_path.read_bytes()
    try:
        identity = json.loads(identity_bytes)
    except json.JSONDecodeError as error:
        raise EvidenceError(f"prepared run identity is invalid JSON: {error}") from error
    if identity_bytes != canonical_json(identity):
        raise EvidenceError("prepared run identity is not canonical sorted-key JSON")
    identity_sha = hashlib.sha256(identity_bytes).hexdigest()
    if sha_path.read_text(encoding="utf-8") != f"{identity_sha}\n":
        raise EvidenceError("prepared run identity SHA file does not match its JSON bytes")
    binary_sha = identity.get("releaseBinary", {}).get("sha256")
    if not isinstance(binary_sha, str) or not re.fullmatch(r"[0-9a-f]{64}", binary_sha):
        raise EvidenceError("prepared identity has no valid prepared binary SHA-256")
    fence_sha = identity.get("productInputFenceSHA256")
    if not isinstance(fence_sha, str) or not re.fullmatch(r"[0-9a-f]{64}", fence_sha):
        raise EvidenceError("prepared identity has no valid Product input fence SHA-256")
    _, verified_fence_sha = verify_pre_build_product_fence(
        repository.resolve(), repository.resolve() / "Benchmarks/V11Baseline", output
    )
    if verified_fence_sha != fence_sha:
        raise EvidenceError("prepared identity Product input fence SHA differs from its frozen evidence")
    return identity, identity_sha, binary_sha


def validate_record(
    record: dict[str, Any],
    kind: str,
    expected_identity: tuple[str, str, str] | None = None,
) -> None:
    required = {
        "schemaVersion", "benchmarkVersion", "gitHead", "productInputFenceSHA256", "preparedRunIdentitySHA256",
        "preparedBinarySHA256", "scenario", "lane", "round",
        "warmupOperations", "measuredOperations", "concurrency", "poolCapacity",
        "elapsedNanoseconds", "operationsPerSecond", "latencyP50Nanoseconds",
        "latencyP95Nanoseconds", "latencyP99Nanoseconds", "perOperationLatencyEndpoint",
        "sampleElapsedEndpoint", "checksum",
        "resourceIdentityMode", "observedCheckoutCount", "observedUniqueConnectionObjects",
        "observedMaxSimultaneousBorrowedConnections",
    }
    missing = sorted(required - record.keys())
    if missing:
        raise EvidenceError(f"record missing required fields: {', '.join(missing)}")
    if record["schemaVersion"] != 1 or record["benchmarkVersion"] != BENCHMARK_VERSION:
        raise EvidenceError("unexpected schema or benchmark version")
    if not isinstance(record["gitHead"], str) or not record["gitHead"]:
        raise EvidenceError("gitHead must be a non-empty string")
    if not isinstance(record["checksum"], str) or not record["checksum"]:
        raise EvidenceError("checksum must be a non-empty string")
    fence_sha = record["productInputFenceSHA256"]
    if not isinstance(fence_sha, str) or not re.fullmatch(r"[0-9a-f]{64}", fence_sha):
        raise EvidenceError("record requires a valid Product input fence SHA-256")
    environment_fence = os.environ.get("DUCK_BENCHMARK_PRODUCT_INPUT_FENCE_SHA256")
    if environment_fence is not None and fence_sha != environment_fence:
        raise EvidenceError("record Product input fence differs from the runner-verified environment")
    for key in ("warmupOperations", "measuredOperations", "concurrency"):
        if not isinstance(record[key], int) or isinstance(record[key], bool) or record[key] < 0:
            raise EvidenceError(f"{key} must be a non-negative integer")
    if not isinstance(record["poolCapacity"], (int, type(None))):
        raise EvidenceError("poolCapacity must be an integer or null")
    if kind == "sample":
        for key in ("preparedRunIdentitySHA256", "preparedBinarySHA256"):
            if not isinstance(record[key], str) or not re.fullmatch(r"[0-9a-f]{64}", record[key]):
                raise EvidenceError(f"timed sample requires valid {key}")
        if expected_identity is not None and (
            record["preparedRunIdentitySHA256"], record["preparedBinarySHA256"], record["productInputFenceSHA256"]
        ) != expected_identity:
            raise EvidenceError("timed sample prepared identity differs from the frozen run identity")
        environment_identity = os.environ.get("DUCK_BENCHMARK_PREPARED_RUN_IDENTITY_SHA256")
        environment_binary = os.environ.get("DUCK_BENCHMARK_PREPARED_BINARY_SHA256")
        if environment_identity is not None and record["preparedRunIdentitySHA256"] != environment_identity:
            raise EvidenceError("timed sample run identity differs from the runner-verified environment")
        if environment_binary is not None and record["preparedBinarySHA256"] != environment_binary:
            raise EvidenceError("timed sample binary identity differs from the runner-verified environment")
        if not isinstance(record["round"], int) or isinstance(record["round"], bool):
            raise EvidenceError("timed sample round must be an integer")
        for key in ("elapsedNanoseconds", "operationsPerSecond", "latencyP50Nanoseconds",
                    "latencyP95Nanoseconds", "latencyP99Nanoseconds"):
            value = record[key]
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                raise EvidenceError(f"{key} must be a numeric timing value")
            if not math.isfinite(float(value)) or value <= 0:
                raise EvidenceError(f"{key} must be finite and positive")
        if not (record["latencyP50Nanoseconds"] <= record["latencyP95Nanoseconds"] <= record["latencyP99Nanoseconds"]):
            raise EvidenceError("latency percentiles are not ordered")
        expected_rate = record["measuredOperations"] * 1_000_000_000 / record["elapsedNanoseconds"]
        if not math.isclose(record["operationsPerSecond"], expected_rate, rel_tol=1e-12):
            raise EvidenceError("operationsPerSecond does not match measuredOperations / elapsedNanoseconds")
        if record["scenario"] == "Q02_SMALL_READ_CONCURRENT":
            expected_endpoint = (
                "after-queryresult-validation"
                if record["lane"] == "A_ORDINARY"
                else "inside-pool-closure-after-queryresult-validation"
            )
            if record["perOperationLatencyEndpoint"] != expected_endpoint:
                raise EvidenceError("Q02 per-operation latency endpoint does not match the frozen validation endpoint")
            if record["sampleElapsedEndpoint"] != "after-all-workers-and-pool-return-cleanup":
                raise EvidenceError("Q02 sample elapsed endpoint must include complete worker and pool lifecycle")
        elif record["perOperationLatencyEndpoint"] is not None or record["sampleElapsedEndpoint"] is not None:
            raise EvidenceError("non-Q02 samples must not declare the Q02 endpoint contract")
        for key in ("observedCheckoutCount", "observedUniqueConnectionObjects",
                    "observedMaxSimultaneousBorrowedConnections"):
            if record[key] is not None:
                raise EvidenceError("timed samples must keep resource metrics in separate probes")
    elif kind == "probe":
        if record["preparedRunIdentitySHA256"] is not None or record["preparedBinarySHA256"] is not None:
            raise EvidenceError("resource-only probes must not claim timed sample identity")
        if record["perOperationLatencyEndpoint"] is not None or record["sampleElapsedEndpoint"] is not None:
            raise EvidenceError("resource-only probes must not declare timing endpoints")
        if record["round"] is not None:
            raise EvidenceError("resource-only probe round must be null")
        if any(record[key] is not None for key in (
            "elapsedNanoseconds", "operationsPerSecond", "latencyP50Nanoseconds",
            "latencyP95Nanoseconds", "latencyP99Nanoseconds",
        )):
            raise EvidenceError("resource-only probes must not report timing values")
        if record["observedUniqueConnectionObjects"] is None:
            raise EvidenceError("resource-only probe must report unique Connection object identities")
        if not isinstance(record["observedUniqueConnectionObjects"], int) or isinstance(record["observedUniqueConnectionObjects"], bool):
            raise EvidenceError("unique Connection actor proxy count must be an integer")
    else:
        raise EvidenceError(f"unknown record kind {kind}")


def validate_single(path: Path, kind: str, scenario: str, lane: str, round_number: int | None) -> None:
    records = read_json_lines(path)
    if len(records) != 1:
        raise EvidenceError(f"{path}: expected exactly one JSON object, found {len(records)}")
    record = records[0]
    expected_identity = None
    if kind == "sample":
        expected_identity = (
            os.environ.get("DUCK_BENCHMARK_PREPARED_RUN_IDENTITY_SHA256", ""),
            os.environ.get("DUCK_BENCHMARK_PREPARED_BINARY_SHA256", ""),
            os.environ.get("DUCK_BENCHMARK_PRODUCT_INPUT_FENCE_SHA256", ""),
        )
    validate_record(record, kind, expected_identity)
    if record["scenario"] != scenario or record["lane"] != lane:
        raise EvidenceError(f"{path}: scenario/lane did not match requested {scenario}/{lane}")
    if kind == "sample" and record["round"] != round_number:
        raise EvidenceError(f"{path}: round did not match requested {round_number}")


def expected_matrix() -> list[tuple[str, str]]:
    return [(scenario, lane) for scenario, spec in SPECS.items() for lane in spec["lanes"]]


def expected_run_order() -> list[tuple[int, str, str]]:
    result: list[tuple[int, str, str]] = []
    for scenario, spec in SPECS.items():
        lanes = spec["lanes"]
        for round_number in range(1, 8):
            shift = round_number - 1
            for index in range(len(lanes)):
                result.append((round_number, scenario, lanes[(index + shift) % len(lanes)]))
    return result


def validate_matrix(
    records: list[dict[str, Any]],
    exact_count: bool = True,
    expected_identity: tuple[str, str, str] | None = None,
) -> dict[tuple[str, str], list[dict[str, Any]]]:
    expected = expected_matrix()
    if exact_count and len(records) != 91:
        raise EvidenceError(f"RAW_SAMPLES.ndjson must contain exactly 91 samples; found {len(records)}")
    grouped: dict[tuple[str, str], list[dict[str, Any]]] = {}
    seen: set[tuple[str, str, int]] = set()
    for record in records:
        validate_record(record, "sample", expected_identity)
        key = (record["scenario"], record["lane"])
        identity = (record["scenario"], record["lane"], record["round"])
        if key not in expected:
            raise EvidenceError(f"unexpected timed scenario/lane: {key}")
        if identity in seen:
            raise EvidenceError(f"duplicate timed round: {identity}")
        seen.add(identity)
        grouped.setdefault(key, []).append(record)
        spec = SPECS[record["scenario"]]
        if record["warmupOperations"] != spec["warmupOperations"]:
            raise EvidenceError(f"{identity}: incorrect warmupOperations")
        if record["measuredOperations"] != spec["measuredOperations"]:
            raise EvidenceError(f"{identity}: incorrect measuredOperations")
        if record["concurrency"] != spec["concurrency"]:
            raise EvidenceError(f"{identity}: incorrect concurrency")
        capacity = {"B_POOL_1": 1, "B_POOL_4": 4, "B_POOL_8": 8}.get(record["lane"])
        if record["poolCapacity"] != capacity:
            raise EvidenceError(f"{identity}: incorrect poolCapacity")
        if record["gitHead"] != EXPECTED_HEAD:
            raise EvidenceError(f"{identity}: gitHead differs from the frozen baseline")
    if exact_count:
        if set(grouped) != set(expected):
            raise EvidenceError("timed sample scenario/lane matrix is incomplete")
        for key, samples in grouped.items():
            if sorted(sample["round"] for sample in samples) != list(range(1, 8)):
                raise EvidenceError(f"{key}: rounds must be 1...7 exactly once")
            if len({sample["checksum"] for sample in samples}) != 1:
                raise EvidenceError(f"{key}: checksums differ across rounds")
        for scenario in SPECS:
            checksums = {sample["checksum"] for key, samples in grouped.items() if key[0] == scenario for sample in samples}
            if len(checksums) != 1:
                raise EvidenceError(f"{scenario}: checksums differ across lanes")
    return grouped


def parse_rss(path: Path) -> int | None:
    if not path.is_file():
        return None
    text = path.read_text(encoding="utf-8", errors="replace")
    matches = re.findall(r"^\s*(\d+)\s+maximum resident set size\b", text, flags=re.MULTILINE)
    if len(matches) != 1:
        return None
    value = int(matches[0])
    return value if value > 0 else None


def aggregate_group(key: tuple[str, str], samples: list[dict[str, Any]], logs_directory: Path) -> dict[str, Any]:
    scenario, lane = key
    throughputs = [float(sample["operationsPerSecond"]) for sample in samples]
    elapsed_per_operation = [
        int(sample["elapsedNanoseconds"]) / int(sample["measuredOperations"]) for sample in samples
    ]
    p50 = [int(sample["latencyP50Nanoseconds"]) for sample in samples]
    p95 = [int(sample["latencyP95Nanoseconds"]) for sample in samples]
    p99 = [int(sample["latencyP99Nanoseconds"]) for sample in samples]
    rss_values = [
        parse_rss(logs_directory / f"{scenario}__{lane}__r{round_number}.stderr-time.log")
        for round_number in range(1, 8)
    ]
    parsed_rss = [value for value in rss_values if value is not None]
    rss_complete = len(parsed_rss) == 7
    return {
        "scenario": scenario,
        "lane": lane,
        "rounds": sorted(int(sample["round"]) for sample in samples),
        "measuredOperations": int(samples[0]["measuredOperations"]),
        "poolCapacity": samples[0]["poolCapacity"],
        "medianElapsedNanosecondsPerOperation": statistics.median(elapsed_per_operation),
        "medianOperationsPerSecond": statistics.median(throughputs),
        "medianLatencyP50Nanoseconds": statistics.median(p50),
        "medianLatencyP95Nanoseconds": statistics.median(p95),
        "medianLatencyP99Nanoseconds": statistics.median(p99),
        "minimumOperationsPerSecond": min(throughputs),
        "maximumOperationsPerSecond": max(throughputs),
        "checksum": samples[0]["checksum"],
        "checksumConsistentAcrossRounds": len({sample["checksum"] for sample in samples}) == 1,
        "maximumResidentSetSizeBytes": {
            "median": statistics.median(parsed_rss) if rss_complete else None,
            "maximum": max(parsed_rss) if rss_complete else None,
            "parsedLogCount": len(parsed_rss),
            "expectedLogCount": 7,
            "reliable": rss_complete,
        },
        "rawSampleIdentities": [
            {"scenario": scenario, "lane": lane, "round": int(sample["round"])}
            for sample in sorted(samples, key=lambda item: int(item["round"]))
        ],
    }


def validate_resource_probes(records: list[dict[str, Any]], raw_groups: dict[tuple[str, str], list[dict[str, Any]]]) -> list[dict[str, Any]]:
    expected = set(RESOURCE_PROBES)
    actual: dict[tuple[str, str], dict[str, Any]] = {}
    for record in records:
        validate_record(record, "probe")
        key = (record["scenario"], record["lane"])
        if key not in expected:
            raise EvidenceError(f"unexpected resource probe: {key}")
        if key in actual:
            raise EvidenceError(f"duplicate resource probe: {key}")
        actual[key] = record
        if key[0] == "R01_CONNECTION_IDENTITY":
            if record["measuredOperations"] != 100 or record["warmupOperations"] != 0 or record["concurrency"] != 1:
                raise EvidenceError(f"{key}: R01 probe workload mismatch")
            if key[1] == "A_FRESH_EXPLICIT":
                if not (1 <= record["observedUniqueConnectionObjects"] <= record["measuredOperations"]):
                    raise EvidenceError("R01 A_FRESH_EXPLICIT observed uniqueness is outside 1...100 basic sanity")
                if record["observedCheckoutCount"] is not None or record["observedMaxSimultaneousBorrowedConnections"] is not None:
                    raise EvidenceError("R01 A lane must not report pool checkout/borrow metrics")
            else:
                if record["observedCheckoutCount"] != 100 or not (1 <= record["observedUniqueConnectionObjects"] <= 4):
                    raise EvidenceError("R01 B_POOL_4 structural counts are outside basic sanity")
                if record["observedMaxSimultaneousBorrowedConnections"] != 1:
                    raise EvidenceError("R01 B_POOL_4 is a sequential checkout probe")
        else:
            spec = SPECS[key[0]]
            if record["warmupOperations"] != spec["warmupOperations"]:
                raise EvidenceError(f"{key}: resource probe warmup mismatch")
            if record["measuredOperations"] != spec["measuredOperations"]:
                raise EvidenceError(f"{key}: resource probe measuredOperations mismatch")
            if record["concurrency"] != spec["concurrency"]:
                raise EvidenceError(f"{key}: resource probe concurrency mismatch")
            if record["observedCheckoutCount"] != spec["measuredOperations"]:
                raise EvidenceError(f"{key}: resource-only pool checkout count mismatch")
            capacity = {"B_POOL_1": 1, "B_POOL_4": 4, "B_POOL_8": 8}[key[1]]
            unique = record["observedUniqueConnectionObjects"]
            maximum = record["observedMaxSimultaneousBorrowedConnections"]
            if not (1 <= unique <= capacity and 1 <= maximum <= capacity):
                raise EvidenceError(f"{key}: pooled identity/max-borrow values violate capacity sanity")
            if {sample["checksum"] for sample in raw_groups[key]} != {record["checksum"]}:
                raise EvidenceError(f"{key}: resource-only checksum differs from timed samples")
    if set(actual) != expected:
        raise EvidenceError(f"resource probe matrix is incomplete: {sorted(expected - set(actual))}")
    return [actual[key] for key in RESOURCE_PROBES]


def synthetic_resource_probe(scenario: str, lane: str, observed_unique: int) -> dict[str, Any]:
    if scenario == "R01_CONNECTION_IDENTITY":
        spec = {"warmupOperations": 0, "measuredOperations": 100, "concurrency": 1}
        checkout_count = None if lane == "A_FRESH_EXPLICIT" else 100
        maximum_borrowed = None if lane == "A_FRESH_EXPLICIT" else 1
        unique = observed_unique if lane == "A_FRESH_EXPLICIT" else 2
        identity_mode = "synthetic-r01"
    else:
        spec = SPECS[scenario]
        capacity = {"B_POOL_1": 1, "B_POOL_4": 4, "B_POOL_8": 8}[lane]
        checkout_count = spec["measuredOperations"]
        maximum_borrowed = 1
        unique = 1
        identity_mode = "synthetic-pool"
    return {
        "schemaVersion": 1,
        "benchmarkVersion": BENCHMARK_VERSION,
        "gitHead": EXPECTED_HEAD,
        "productInputFenceSHA256": os.environ.get("DUCK_BENCHMARK_PRODUCT_INPUT_FENCE_SHA256", "0" * 64),
        "preparedRunIdentitySHA256": None,
        "preparedBinarySHA256": None,
        "scenario": scenario,
        "lane": lane,
        "round": None,
        "warmupOperations": spec["warmupOperations"],
        "measuredOperations": spec["measuredOperations"],
        "concurrency": spec["concurrency"],
        "poolCapacity": {"B_POOL_1": 1, "B_POOL_4": 4, "B_POOL_8": 8}.get(lane),
        "elapsedNanoseconds": None,
        "operationsPerSecond": None,
        "latencyP50Nanoseconds": None,
        "latencyP95Nanoseconds": None,
        "latencyP99Nanoseconds": None,
        "perOperationLatencyEndpoint": None,
        "sampleElapsedEndpoint": None,
        "checksum": "synthetic-r01-validation",
        "resourceIdentityMode": identity_mode,
        "observedCheckoutCount": checkout_count,
        "observedUniqueConnectionObjects": unique,
        "observedMaxSimultaneousBorrowedConnections": maximum_borrowed,
    }


def r01_validator_selftest() -> list[str]:
    raw_groups = {
        key: [{"checksum": "synthetic-r01-validation"}]
        for key in RESOURCE_PROBES
        if key[0] != "R01_CONNECTION_IDENTITY"
    }
    results: list[str] = []
    for unique, should_pass in ((37, True), (0, False), (101, False)):
        records = [synthetic_resource_probe(scenario, lane, unique) for scenario, lane in RESOURCE_PROBES]
        try:
            validate_resource_probes(records, raw_groups)
        except EvidenceError:
            if should_pass:
                raise EvidenceError("synthetic R01 A unique=37 must pass the production resource validator")
            results.append(f"unique={unique}:FAIL (expected)")
        else:
            if not should_pass:
                raise EvidenceError(f"synthetic R01 A unique={unique} unexpectedly passed the production validator")
            results.append(f"unique={unique}:PASS")
    return results


def r01_selftest_command(_: argparse.Namespace) -> None:
    results = r01_validator_selftest()
    print("R01_A_PRODUCTION_VALIDATOR_SELFTEST=PASS " + ", ".join(results))


def validate_resource_file_command(args: argparse.Namespace) -> None:
    records = read_json_lines(Path(args.path))
    raw_groups = {
        (record["scenario"], record["lane"]): [{"checksum": record["checksum"]}]
        for record in records
        if record["scenario"] != "R01_CONNECTION_IDENTITY"
    }
    validate_resource_probes(records, raw_groups)
    if len(records) != len(RESOURCE_PROBES):
        raise EvidenceError("resource probe packet must contain exactly the frozen nine probes")
    print("RESOURCE_PROBES=PASS count=9; R01 A observed " + str(next(
        record["observedUniqueConnectionObjects"] for record in records
        if record["scenario"] == "R01_CONNECTION_IDENTITY" and record["lane"] == "A_FRESH_EXPLICIT"
    )))


def validate_run_order(path: Path) -> None:
    actual = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        fields = line.split("\t")
        if len(fields) != 3:
            raise EvidenceError(f"{path}:{line_number}: expected round, scenario, lane")
        try:
            actual.append((int(fields[0]), fields[1], fields[2]))
        except ValueError as error:
            raise EvidenceError(f"{path}:{line_number}: invalid round number") from error
    if actual != expected_run_order():
        raise EvidenceError("RUN_ORDER.txt differs from the documented deterministic rotation")
    for scenario, spec in SPECS.items():
        first_lanes = [
            lane for _, item_scenario, lane in actual if item_scenario == scenario
        ][: len(spec["lanes"])]
        if len(set(first_lanes)) != len(spec["lanes"]):
            raise EvidenceError(f"{scenario}: first-lane rotation does not cover every lane")


def write_summaries(args: argparse.Namespace) -> None:
    output_directory = Path(args.output_dir)
    repository = Path(args.repository).resolve()
    raw_path = Path(args.raw)
    resource_path = Path(args.resources)
    logs_directory = Path(args.logs)
    identity, identity_sha, binary_sha = read_prepared_identity_evidence(output_directory, repository)
    verify_prepared_identity(
        repository,
        repository / "Benchmarks/V11Baseline",
        Path(identity["releaseBinary"]["path"]),
        output_directory / "PREPARED_RUN_IDENTITY.json",
        output_directory / "PREPARED_RUN_IDENTITY_SHA256.txt",
    )
    records = read_json_lines(raw_path)
    groups = validate_matrix(
        records,
        expected_identity=(identity_sha, binary_sha, identity["productInputFenceSHA256"]),
    )
    resources = validate_resource_probes(read_json_lines(resource_path), groups)
    aggregates = [aggregate_group(key, groups[key], logs_directory) for key in expected_matrix()]
    resource_by_key = {(record["scenario"], record["lane"]): record for record in resources}
    for aggregate in aggregates:
        resource = resource_by_key.get((aggregate["scenario"], aggregate["lane"]))
        aggregate["resourceProbe"] = None if resource is None else {
            "source": "separate resource-only probe; not collected in timed loop",
            "observedCheckoutCount": resource["observedCheckoutCount"],
            "observedUniqueConnectionObjects": resource["observedUniqueConnectionObjects"],
            "observedMaxSimultaneousBorrowedConnections": resource["observedMaxSimultaneousBorrowedConnections"],
            "resourceIdentityMode": resource["resourceIdentityMode"],
        }

    raw_identities = [
        {"scenario": record["scenario"], "lane": record["lane"], "round": int(record["round"])}
        for record in sorted(records, key=lambda item: (item["scenario"], item["lane"], int(item["round"])))
    ]
    source_facts = [
        {
            "fact": "SQLable.query(on: DatabaseIdentifier) calls connect() for that operation, then runs on that Connection.",
            "source": "Sources/Duck/SQLable+Execution.swift",
        },
        {
            "fact": "DatabaseIdentifier.appender opens a fresh Connection for each Appender scope.",
            "source": "Sources/Duck/Appender.swift",
        },
        {
            "fact": "ConnectionPool.connection performs scoped checkout/return and stores reusable Connection actors; pool.transaction delegates through pool.connection.",
            "source": "Sources/Duck/ConnectionPool.swift",
        },
        {
            "fact": "ObjectIdentifier(Connection) is a Swift actor object-identity proxy and is not a native DuckDB pointer/create count.",
            "source": "Benchmarks/V11Baseline/README.md",
        },
    ]
    summary = {
        "schemaVersion": 1,
        "benchmarkVersion": BENCHMARK_VERSION,
        "reportKind": "fresh Correction 02 A/B baseline; descriptive metrics only",
        "preparedRunIdentitySHA256": identity_sha,
        "preparedBinarySHA256": binary_sha,
        "productInputFenceSHA256": identity["productInputFenceSHA256"],
        "attempt01Policy": "Attempt 01 and Correction 01 are separate and superseded; neither packet contributes sample inputs to Correction 02.",
        "rawSampleFile": raw_path.name,
        "rawSampleSHA256": sha256(raw_path),
        "rawSampleCount": len(records),
        "rawSampleIdentities": raw_identities,
        "percentileMethod": "nearest-rank: sort integer nanoseconds and select one-based rank ceil(p*N), bounded to 1...N",
        "timingMetrics": aggregates,
        "timingContract": {
            "outsideMeasuredIntervals": [
                "fixture DDL and population",
                "warmup",
                "deterministic Appender input-array preparation",
                "final post-loop fixture verification",
                "JSON encoding and writing",
                "summary generation",
            ],
            "insideOperationTiming": [
                "scalar QueryResult validation",
                "transaction in-body SELECT and result validation",
                "transaction finalization and commit for transaction operation timing",
                "Appender scope itself",
            ],
            "q02PerOperationPercentileEndpoint": "Immediately after scalar QueryResult validation; pooled lanes capture validationEnd inside pool.connection before pooled lease return cleanup.",
            "q02WholeSampleElapsedAndThroughput": "Includes the complete worker lifecycle, including pool.connection return and mandatory lease cleanup.",
            "appender": "Deterministic row data is prepared before timing; final row-count/content verification is after the measured loop.",
        },
        "structuralResourceProxies": [
            {
                "scenario": record["scenario"],
                "lane": record["lane"],
                "warmupOperations": record["warmupOperations"],
                "measuredOperations": record["measuredOperations"],
                "concurrency": record["concurrency"],
                "poolCapacity": record["poolCapacity"],
                "checksum": record["checksum"],
                "resourceIdentityMode": record["resourceIdentityMode"],
                "observedCheckoutCount": record["observedCheckoutCount"],
                "observedUniqueConnectionObjects": record["observedUniqueConnectionObjects"],
                "observedMaxSimultaneousBorrowedConnections": record["observedMaxSimultaneousBorrowedConnections"],
            }
            for record in resources
        ],
        "sourceEstablishedFacts": source_facts,
        "interpretationLimit": "No significance test, regression threshold, or improvement claim is made. Resource values are Swift actor object identity proxies.",
    }
    resource_report = {
        "schemaVersion": 1,
        "benchmarkVersion": BENCHMARK_VERSION,
        "productInputFenceSHA256": identity["productInputFenceSHA256"],
        "probeKind": "untimed/resource-only",
        "probeCount": len(resources),
        "probes": summary["structuralResourceProxies"],
        "interpretationLimit": "ObjectIdentifier values describe public Swift actor identity only; they do not count native DuckDB connection creation or destruction.",
    }
    output_directory.mkdir(parents=True, exist_ok=True)
    (output_directory / "SUMMARY.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    (output_directory / "RESOURCE_IDENTITIES.json").write_text(
        json.dumps(resource_report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    (output_directory / "SUMMARY.md").write_text(render_markdown(summary), encoding="utf-8")


def render_markdown(summary: dict[str, Any]) -> str:
    lines = [
        "# Wave 00 Correction 02 A/B Baseline",
        "",
        f"Raw source: {summary['rawSampleFile']} ({summary['rawSampleCount']} samples, SHA-256 {summary['rawSampleSHA256']}).",
        f"Prepared run identity SHA-256: {summary['preparedRunIdentitySHA256']}; timed Release binary SHA-256: {summary['preparedBinarySHA256']}.",
        "",
        summary["attempt01Policy"],
        "This report is descriptive evidence. It makes no statistical significance, regression, or improvement claim.",
        "",
        "## TIMING METRICS",
        "",
        "Each row aggregates seven independent processes. Latency percentiles are nearest-rank within each sample, then medianed across the seven rounds. Throughput uses measured operation count divided by the sample elapsed interval.",
        "",
        "| Scenario | Lane | Median ops/s | Min ops/s | Max ops/s | Median elapsed/op (ns) | Median p50 (ns) | Median p95 (ns) | Median p99 (ns) | RSS median / max (bytes) | Checksum |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    for item in summary["timingMetrics"]:
        rss = item["maximumResidentSetSizeBytes"]
        rss_text = (
            f"{int(rss['median']):,} / {rss['maximum']:,}"
            if rss["reliable"]
            else f"unavailable ({rss['parsedLogCount']}/7 logs parsed)"
        )
        lines.append(
            "| {scenario} | {lane} | {median_rate:,.2f} | {minimum:,.2f} | {maximum:,.2f} | "
            "{elapsed:,.0f} | {p50:,.0f} | {p95:,.0f} | {p99:,.0f} | {rss} | {checksum} |".format(
                scenario=item["scenario"],
                lane=item["lane"],
                median_rate=item["medianOperationsPerSecond"],
                minimum=item["minimumOperationsPerSecond"],
                maximum=item["maximumOperationsPerSecond"],
                elapsed=item["medianElapsedNanosecondsPerOperation"],
                p50=item["medianLatencyP50Nanoseconds"],
                p95=item["medianLatencyP95Nanoseconds"],
                p99=item["medianLatencyP99Nanoseconds"],
                rss=rss_text,
                checksum=item["checksum"],
            )
        )
    lines.extend(
        [
            "",
            "## STRUCTURAL RESOURCE PROXIES",
            "",
            "These untimed probes are separate from RAW_SAMPLES.ndjson. ObjectIdentifier is a Swift actor identity proxy, not native pointer identity or native create/destroy accounting.",
            "",
            "| Scenario | Lane | Checkouts | Unique Connection actor objects | Max simultaneous borrowed closures |",
            "| --- | --- | ---: | ---: | ---: |",
        ]
    )
    for item in summary["structuralResourceProxies"]:
        checkout = "not applicable" if item["observedCheckoutCount"] is None else str(item["observedCheckoutCount"])
        maximum = (
            "not applicable"
            if item["observedMaxSimultaneousBorrowedConnections"] is None
            else str(item["observedMaxSimultaneousBorrowedConnections"])
        )
        lines.append(
            f"| {item['scenario']} | {item['lane']} | {checkout} | "
            f"{item['observedUniqueConnectionObjects']} | {maximum} |"
        )
    lines.extend(["", "## SOURCE-ESTABLISHED FACTS", ""])
    for item in summary["sourceEstablishedFacts"]:
        lines.append(f"- {item['fact']} Source: {item['source']}.")
    lines.extend(
        [
            "",
            "## Interpretation limits",
            "",
            summary["interpretationLimit"],
            "",
            "## Timing contract",
            "",
            "Outside measured intervals: fixture DDL/population, warmup, deterministic Appender input-array preparation, final post-loop fixture verification, JSON encoding/writing, and summary generation.",
            "",
            "Inside applicable operation timing: scalar QueryResult validation, transaction in-body SELECT/result validation, transaction finalization/commit for transaction operation timing, and the Appender scope itself.",
            "",
            f"Q02 per-operation percentile latency endpoint: {summary['timingContract']['q02PerOperationPercentileEndpoint']}",
            f"Q02 whole-sample elapsed/throughput scope: {summary['timingContract']['q02WholeSampleElapsedAndThroughput']}",
            "",
            summary["timingContract"]["appender"],
            "",
            "Resource-only probes keep identity collection out of timed query/Appender/transaction loops. Q02 checkout/unique-object/max-borrow values come from a separate concurrent run with the same operation distribution.",
            "",
        ]
    )
    return "\n".join(lines)


def evidence_manifest_paths(output: Path) -> list[Path]:
    manifest_name = "EVIDENCE_IDENTITIES.md"
    paths = sorted(
        path for path in output.rglob("*")
        if path.is_file() and path.name != manifest_name
    )
    if not paths:
        raise EvidenceError("corrected evidence directory contains no files to manifest")
    return paths


def write_evidence_manifest(args: argparse.Namespace) -> None:
    output = Path(args.output_dir).resolve()
    manifest = output / "EVIDENCE_IDENTITIES.md"
    if manifest.exists():
        raise EvidenceError(f"refusing to overwrite finalized evidence manifest: {manifest}")
    lines = [
        "# Correction 02 Evidence Identities",
        "",
        "This manifest covers every canonical file in this Correction 02 evidence directory except this manifest itself.",
        "Attempt 01 and Correction 01 are separate and superseded; neither prior packet contributes sample inputs to Correction 02.",
        "",
        "SHA-256\tEvidence-relative path",
    ]
    lines.extend(
        f"{sha256(path)}\t{path.relative_to(output).as_posix()}"
        for path in evidence_manifest_paths(output)
    )
    manifest.write_text("\n".join(lines) + "\n", encoding="utf-8")


def verify_evidence_manifest(args: argparse.Namespace) -> None:
    output = Path(args.output_dir).resolve()
    manifest_path = output / "EVIDENCE_IDENTITIES.md"
    lines = manifest_path.read_text(encoding="utf-8").splitlines()
    if "Attempt 01 and Correction 01 are separate and superseded; neither prior packet contributes sample inputs to Correction 02." not in lines:
        raise EvidenceError("evidence manifest does not state that both prior packets are separate and excluded")
    identities: dict[str, str] = {}
    for line in lines:
        fields = line.split("\t")
        if len(fields) == 2 and re.fullmatch(r"[0-9a-f]{64}", fields[0]):
            identities[fields[1]] = fields[0]
    expected_paths = {path.relative_to(output).as_posix() for path in evidence_manifest_paths(output)}
    if set(identities) != expected_paths:
        raise EvidenceError("evidence manifest does not cover exactly every canonical evidence file")
    for relative, expected_sha in identities.items():
        if sha256(output / relative) != expected_sha:
            raise EvidenceError(f"evidence manifest SHA-256 mismatch: {relative}")
    print(f"EVIDENCE_MANIFEST=PASS files={len(identities)} sha256={sha256(manifest_path)}")


def cheap_check(args: argparse.Namespace) -> None:
    repository = Path(args.repository).resolve()
    output = Path(args.output_dir).resolve()
    passes: list[str] = []
    identity, identity_sha, binary_sha = read_prepared_identity_evidence(output, Path(args.repository))
    verified_identity_sha, verified_binary_sha, verified_fence_sha = verify_prepared_identity(
        repository,
        repository / "Benchmarks/V11Baseline",
        Path(identity["releaseBinary"]["path"]),
        output / "PREPARED_RUN_IDENTITY.json",
        output / "PREPARED_RUN_IDENTITY_SHA256.txt",
    )
    if (identity_sha, binary_sha, identity["productInputFenceSHA256"]) != (
        verified_identity_sha,
        verified_binary_sha,
        verified_fence_sha,
    ):
        raise EvidenceError("recomputed prepared identity differs from frozen identity values")
    passes.append("PREPARED_IDENTITY, BINARY_IDENTITY, PRODUCT_INPUT_FENCE, SQL checkout and toolchain identities recompute and match.")
    records = read_json_lines(Path(args.raw))
    fence_sha = identity["productInputFenceSHA256"]
    groups = validate_matrix(records, expected_identity=(identity_sha, binary_sha, fence_sha))
    passes.append("RAW_SAMPLES.ndjson has exactly 91 valid JSON timing samples with a complete 13 x 7 matrix.")
    raw_sha = sha256(Path(args.raw))
    if raw_sha == ATTEMPT_01_RAW_SHA256:
        raise EvidenceError("Correction 02 raw samples are byte-identical to the superseded Attempt 01 sample file")
    if raw_sha == CORRECTION_01_RAW_SHA256:
        raise EvidenceError("Correction 02 raw samples are byte-identical to the superseded Correction 01 sample file")
    passes.append("All 91 fresh Correction 02 samples carry the exact Product fence, prepared identity, and binary SHA; both prior packets are excluded.")
    passes.append("Every required lane has rounds 1...7 exactly once and consistent checksums.")
    passes.append("All checksums agree across A/B lanes within each scenario.")
    passes.append("No timing, throughput, or percentile value is zero, negative, NaN, or infinite.")
    passes.append("Q02 percentile records declare the post-validation endpoint; pooled endpoints are inside pool.connection and whole-sample throughput includes return cleanup.")

    validate_run_order(output / "RUN_ORDER.txt")
    passes.append("RUN_ORDER.txt matches the deterministic lane rotation across rounds.")

    resource_records = read_json_lines(Path(args.resources))
    validate_resource_probes(resource_records, groups)
    selftest_results = r01_validator_selftest()
    if selftest_results != ["unique=37:PASS", "unique=0:FAIL (expected)", "unique=101:FAIL (expected)"]:
        raise EvidenceError(f"synthetic R01 production-validator self-tests are incomplete: {selftest_results}")
    passes.append("Production R01 validator synthetic A_FRESH_EXPLICIT records: unique=37 PASS; 0 FAIL; 101 FAIL.")
    if len(resource_records) != len(RESOURCE_PROBES):
        raise EvidenceError("RESOURCE_PROBES.ndjson must contain exactly the frozen 9 resource-only probes")
    passes.append("Resource-only probe matrix is complete and agrees with timed correctness checksums.")
    r01_a = next(record for record in resource_records if record["scenario"] == "R01_CONNECTION_IDENTITY" and record["lane"] == "A_FRESH_EXPLICIT")
    r01_b = next(record for record in resource_records if record["scenario"] == "R01_CONNECTION_IDENTITY" and record["lane"] == "B_POOL_4")
    passes.append(f"R01 A observed {r01_a['observedUniqueConnectionObjects']} actor proxies in range 1...100; B observed {r01_b['observedCheckoutCount']} checkouts, {r01_b['observedUniqueConnectionObjects']} proxies in range 1...4, and max borrowed closures {r01_b['observedMaxSimultaneousBorrowedConnections']}.")

    summary = json.loads((output / "SUMMARY.json").read_text(encoding="utf-8"))
    expected_ids = [
        {"scenario": record["scenario"], "lane": record["lane"], "round": int(record["round"])}
        for record in sorted(records, key=lambda item: (item["scenario"], item["lane"], int(item["round"])))
    ]
    raw_path = Path(args.raw)
    if summary["rawSampleCount"] != len(records):
        raise EvidenceError("SUMMARY.json rawSampleCount does not match RAW_SAMPLES.ndjson")
    if summary["rawSampleSHA256"] != sha256(raw_path):
        raise EvidenceError("SUMMARY.json raw sample SHA-256 does not match RAW_SAMPLES.ndjson")
    if summary["rawSampleIdentities"] != expected_ids:
        raise EvidenceError("SUMMARY.json does not reference exactly the raw sample set")
    if (
        summary.get("preparedRunIdentitySHA256") != identity_sha
        or summary.get("preparedBinarySHA256") != binary_sha
        or summary.get("productInputFenceSHA256") != identity["productInputFenceSHA256"]
    ):
        raise EvidenceError("SUMMARY.json prepared identity values differ from the frozen run identity")
    expected_attempt_policy = "Attempt 01 and Correction 01 are separate and superseded; neither packet contributes sample inputs to Correction 02."
    if summary.get("benchmarkVersion") != BENCHMARK_VERSION or summary.get("attempt01Policy") != expected_attempt_policy:
        raise EvidenceError("SUMMARY.json does not identify Correction 02 and exclude both prior packets")
    if len(summary["timingMetrics"]) != len(expected_matrix()):
        raise EvidenceError("SUMMARY.json aggregate count does not match the raw matrix")
    aggregate_keys = [(item["scenario"], item["lane"]) for item in summary["timingMetrics"]]
    if len(set(aggregate_keys)) != len(expected_matrix()) or set(aggregate_keys) != set(expected_matrix()):
        raise EvidenceError("SUMMARY.json aggregate keys do not match the exact 13 scenario/lane combinations")
    resource_by_key = {(record["scenario"], record["lane"]): record for record in resource_records}
    for aggregate in summary["timingMetrics"]:
        key = (aggregate["scenario"], aggregate["lane"])
        expected_aggregate = aggregate_group(key, groups[key], Path(args.logs))
        resource = resource_by_key.get(key)
        expected_aggregate["resourceProbe"] = None if resource is None else {
            "source": "separate resource-only probe; not collected in timed loop",
            "observedCheckoutCount": resource["observedCheckoutCount"],
            "observedUniqueConnectionObjects": resource["observedUniqueConnectionObjects"],
            "observedMaxSimultaneousBorrowedConnections": resource["observedMaxSimultaneousBorrowedConnections"],
            "resourceIdentityMode": resource["resourceIdentityMode"],
        }
        if aggregate != expected_aggregate:
            raise EvidenceError(f"summary aggregate does not reproduce from raw samples and time logs: {key}")
    timing_contract = summary.get("timingContract", {})
    if timing_contract.get("outsideMeasuredIntervals") != [
        "fixture DDL and population", "warmup", "deterministic Appender input-array preparation",
        "final post-loop fixture verification", "JSON encoding and writing", "summary generation",
    ]:
        raise EvidenceError("summary outside-interval timing explanation differs from the corrected contract")
    if timing_contract.get("insideOperationTiming") != [
        "scalar QueryResult validation", "transaction in-body SELECT and result validation",
        "transaction finalization and commit for transaction operation timing", "Appender scope itself",
    ]:
        raise EvidenceError("summary inside-operation timing explanation differs from the corrected contract")
    if "pool.connection return" not in timing_contract.get("q02WholeSampleElapsedAndThroughput", ""):
        raise EvidenceError("summary timing contract omits complete pooled Q02 API lifecycle")
    if "Q02 per-operation percentile latency endpoint:" not in (output / "SUMMARY.md").read_text(encoding="utf-8"):
        raise EvidenceError("SUMMARY.md omits the explicit Q02 per-operation percentile latency endpoint label")
    if "Q02 whole-sample elapsed/throughput scope:" not in (output / "SUMMARY.md").read_text(encoding="utf-8"):
        raise EvidenceError("SUMMARY.md omits the explicit Q02 whole-sample elapsed/throughput scope label")
    if (output / "SUMMARY.md").read_text(encoding="utf-8") != render_markdown(summary):
        raise EvidenceError("SUMMARY.md does not reproduce byte-for-byte from SUMMARY.json")
    passes.append("Every summary aggregate, RSS value, checksum, and SUMMARY.md line reproduces from corrected raw data and logs.")

    expected_log_names = {
        f"{scenario}__{lane}__r{round_number}.stderr-time.log"
        for scenario, lane in expected_matrix()
        for round_number in range(1, 8)
    }
    actual_log_names = {path.name for path in Path(args.logs).glob("*.stderr-time.log")}
    if actual_log_names != expected_log_names:
        raise EvidenceError("/usr/bin/time -l logs do not contain exactly the 91 corrected sample processes")
    if any(parse_rss(Path(args.logs) / name) is None for name in expected_log_names):
        raise EvidenceError("one or more /usr/bin/time -l RSS values are missing, nonpositive, or ambiguous")
    passes.append("All 91 raw /usr/bin/time -l logs contain exactly one positive maximum resident set size value.")

    nested = json.loads((repository / "Benchmarks/V11Baseline/Package.resolved").read_text(encoding="utf-8"))
    pins = [pin for pin in nested.get("pins", []) if pin.get("identity") == "sql"]
    if len(pins) != 1:
        raise EvidenceError("nested Package.resolved must contain exactly one SQL pin")
    pin = pins[0]
    state = pin.get("state", {})
    if pin.get("location") != "https://github.com/SwiftStream/SQL" or state.get("version") != SQL_VERSION or state.get("revision") != SQL_REVISION:
        raise EvidenceError("nested Package.resolved SQL version/revision/location differs from the accepted pin")
    manifest_text = (repository / "Benchmarks/V11Baseline/Package.swift").read_text(encoding="utf-8")
    if manifest_text.count(".package(") != 1 or '.package(path: "../..")' not in manifest_text or "url:" in manifest_text:
        raise EvidenceError("nested benchmark package must depend directly only on local Duck")
    passes.append("Nested package directly depends only on local Duck; Package.resolved pins SQL 3.1.0 at the frozen revision.")

    expected_candidate_paths = set(CANDIDATE_PATHS)
    status = subprocess.check_output(
        ["git", "-C", str(repository), "status", "--short", "--untracked-files=all"], text=True
    )
    changed_paths = {line[3:] for line in status.splitlines() if line.strip()}
    ignored_lockfile = "Benchmarks/V11Baseline/Package.resolved"
    visible_candidate_paths = expected_candidate_paths - {ignored_lockfile}
    if changed_paths != visible_candidate_paths | {PROTECTED_PATH}:
        raise EvidenceError(f"Git status paths differ from visible candidate/protected set: {sorted(changed_paths)}")
    ignored_result = subprocess.run(
        ["git", "-C", str(repository), "check-ignore", "-q", "--", ignored_lockfile],
        check=False,
    )
    if ignored_result.returncode != 0:
        raise EvidenceError("nested Package.resolved must remain ignored by Git while present and hashed as a candidate")
    if subprocess.run(["git", "-C", str(repository), "diff", "--cached", "--quiet"]).returncode != 0:
        raise EvidenceError("Git index is not empty")
    passes.append(
        "Git diff is limited to the six benchmark candidates and protected WIP; staged paths are empty."
    )

    actual_head = subprocess.check_output(["git", "-C", str(repository), "rev-parse", "HEAD"], text=True).strip()
    if actual_head != EXPECTED_HEAD:
        raise EvidenceError(f"HEAD changed: {actual_head}")
    branch = subprocess.check_output(["git", "-C", str(repository), "branch", "--show-current"], text=True).strip()
    relation = subprocess.check_output(
        ["git", "-C", str(repository), "rev-list", "--left-right", "--count", "origin/master...master"], text=True
    ).strip().split()
    if branch != "master" or relation != ["0", "10"]:
        raise EvidenceError(f"branch relation changed: branch={branch} counts={relation}")
    passes.append("HEAD and master...origin/master [ahead 10] match the stage fence.")

    if sha256(repository / PROTECTED_PATH) != PROTECTED_SHA256:
        raise EvidenceError("Protected SwiftUI project-file SHA-256 changed.")
    if sha256(repository / "Package.swift") != ROOT_PACKAGE_SWIFT_SHA256:
        raise EvidenceError("Root Package.swift SHA-256 changed.")
    if sha256(repository / "Package.resolved") != ROOT_PACKAGE_RESOLVED_SHA256:
        raise EvidenceError("Root Package.resolved SHA-256 changed.")
    passes.append("Protected project WIP and root Package.swift/Package.resolved identities are unchanged.")

    product_diff = subprocess.check_output(
        ["git", "-C", str(repository), "diff", "HEAD", "--name-only", "--", "Sources", "Tests", ".agent", "README.md"],
        text=True,
    ).strip()
    if product_diff:
        raise EvidenceError(f"Product/stable paths changed: {product_diff}")
    passes.append("Sources, Tests, .agent, and README.md are unchanged from HEAD.")

    package_root = repository / "Benchmarks/V11Baseline"
    identity_map: dict[str, str] = {}
    for line in (output / "HARNESS_IDENTITIES.md").read_text(encoding="utf-8").splitlines():
        fields = line.split("\t")
        if len(fields) == 2 and re.fullmatch(r"[0-9a-f]{64}", fields[0]):
            identity_map[fields[1]] = fields[0]
    candidate_files = sorted(path for path in package_root.rglob("*") if path.is_file() and ".build" not in path.parts)
    for file_path in candidate_files:
        relative = file_path.relative_to(repository).as_posix()
        if relative not in expected_candidate_paths:
            raise EvidenceError(f"unexpected candidate file: {relative}")
        if identity_map.get(relative) != sha256(file_path):
            raise EvidenceError(f"harness source identity changed or is missing: {relative}")
        if any(line.rstrip("\r\n").endswith((" ", "\t")) for line in file_path.read_text(encoding="utf-8").splitlines(keepends=True)):
            raise EvidenceError(f"trailing whitespace in {relative}")
    if set(identity_map) != expected_candidate_paths:
        raise EvidenceError("HARNESS_IDENTITIES.md does not list exactly the six candidate files")
    if {path.relative_to(repository).as_posix() for path in candidate_files} != expected_candidate_paths:
        raise EvidenceError("benchmark package file set differs from the exact six-file contract")
    actual_candidate_hashes = {relative: sha256(repository / relative) for relative in CANDIDATE_PATHS}
    if identity.get("candidateFiles") != actual_candidate_hashes:
        raise EvidenceError("candidate SHA-256 values differ from PREPARED_RUN_IDENTITY.json")
    if actual_candidate_hashes["Benchmarks/V11Baseline/Package.swift"] != PACKAGE_MANIFEST_SHA256:
        raise EvidenceError("nested Package.swift changed from its frozen Attempt 01 candidate SHA")
    if actual_candidate_hashes["Benchmarks/V11Baseline/Package.resolved"] != PACKAGE_LOCK_SHA256:
        raise EvidenceError("nested Package.resolved changed from its frozen Attempt 01 candidate SHA")
    harness_identity_lines = (output / "HARNESS_IDENTITIES.md").read_text(encoding="utf-8").splitlines()
    if f"preparedRunIdentitySHA256\t{identity_sha}" not in harness_identity_lines:
        raise EvidenceError("HARNESS_IDENTITIES.md does not bind the prepared run identity")
    if f"preparedBinarySHA256\t{binary_sha}" not in harness_identity_lines:
        raise EvidenceError("HARNESS_IDENTITIES.md does not bind the prepared Release executable")
    if f"productInputFenceSHA256\t{fence_sha}" not in harness_identity_lines:
        raise EvidenceError("HARNESS_IDENTITIES.md does not bind the Product input fence")
    readme_text = (repository / "Benchmarks/V11Baseline/README.md").read_text(encoding="utf-8")
    summary_markdown = (output / "SUMMARY.md").read_text(encoding="utf-8")
    forbidden_timing_claims = (
        "result validation, JSON encoding, and summary generation stay outside the timed interval",
        "result validation, JSON encoding, and summary generation are outside each timed interval",
    )
    if any(claim in readme_text or claim in summary_markdown for claim in forbidden_timing_claims):
        raise EvidenceError("README/SUMMARY contains a contradictory result-validation timing statement")
    passes.append("Harness file set, frozen SHA-256 identities, and whitespace checks pass.")

    identity_json = (output / "PREPARED_RUN_IDENTITY.json").read_bytes()
    if hashlib.sha256(identity_json).hexdigest() + "\n" != (output / "PREPARED_RUN_IDENTITY_SHA256.txt").read_text(encoding="utf-8"):
        raise EvidenceError("prepared identity SHA file does not match actual JSON bytes")
    post_timing = (output / "POST_TIMING_IDENTITY_CHECK.md").read_text(encoding="utf-8")
    required_post_timing = (
        "POST_TIMING_IDENTITY_CHECK=PASS",
        "PRODUCT_INPUT_FENCE=PASS",
        "PREPARED_IDENTITY=PASS",
        "BINARY_IDENTITY=PASS",
        "SQL_CHECKOUT_IDENTITY=PASS",
        "validatedSampleCount=91",
    )
    if any(marker not in post_timing for marker in required_post_timing):
        raise EvidenceError("post-timing identity check does not report a recomputed PASS after sample 91")
    passes.append("Pre-build fence SHA, prepared identity SHA, binary, SQL checkout, and all post-sample-91 identity markers match.")

    if "MAINTAINER_ASSERTED_MAC_IDLE=YES" not in (output / "TIMING_ASSERTION.log").read_text(encoding="utf-8"):
        raise EvidenceError("idle Mac assertion was not recorded verbatim")
    timing_assertion = (output / "TIMING_ASSERTION.log").read_text(encoding="utf-8")
    terminal_time_markers = ("CANONICAL_FINALIZATION_READY=PASS", "EVALUATOR_RECOVERY=NOT_USED")
    if args.pre_finalization:
        if any(marker in timing_assertion for marker in terminal_time_markers):
            raise EvidenceError("finalization readiness markers were recorded before validation completed")
    elif any(marker not in timing_assertion for marker in terminal_time_markers):
        raise EvidenceError("TIMING_ASSERTION.log lacks verified pre-manifest readiness/no-recovery markers")
    if "MAINTAINER_ASSERTED_MAC_IDLE=YES" not in (output / "ENVIRONMENT.md").read_text(encoding="utf-8"):
        raise EvidenceError("ENVIRONMENT.md does not record the maintainer idle assertion")
    passes.append("Maintainer idle assertion is recorded verbatim in timing and environment evidence.")
    if not args.pre_finalization:
        passes.append("Pre-manifest finalization readiness passed and evaluator recovery was not used; command success remains its actual exit status.")

    prior_directory = repository / ".artifacts/benchmarks/v1-1-wave00-a-b-baseline-2026-11-20"
    prior_hashes = {
        "RAW_SAMPLES.ndjson": ATTEMPT_01_RAW_SHA256,
        "SUMMARY.json": ATTEMPT_01_SUMMARY_SHA256,
        "EVIDENCE_IDENTITIES.md": ATTEMPT_01_MANIFEST_SHA256,
    }
    for filename, expected_sha in prior_hashes.items():
        if sha256(prior_directory / filename) != expected_sha:
            raise EvidenceError(f"frozen Attempt 01 identity changed: {filename}")
    correction01_directory = repository / ".artifacts/benchmarks/v1-1-wave00-a-b-baseline-correction-01-2026-11-20"
    correction01_hashes = {
        "RAW_SAMPLES.ndjson": CORRECTION_01_RAW_SHA256,
        "SUMMARY.json": CORRECTION_01_SUMMARY_SHA256,
        "EVIDENCE_IDENTITIES.md": CORRECTION_01_MANIFEST_SHA256,
    }
    for filename, expected_sha in correction01_hashes.items():
        if sha256(correction01_directory / filename) != expected_sha:
            raise EvidenceError(f"frozen Correction 01 identity changed: {filename}")
    passes.append("All Attempt 01 and Correction 01 evidence identities remain unchanged and separate.")

    final_identity_sha, final_binary_sha, final_fence_sha = verify_prepared_identity(
        repository,
        repository / "Benchmarks/V11Baseline",
        Path(identity["releaseBinary"]["path"]),
        output / "PREPARED_RUN_IDENTITY.json",
        output / "PREPARED_RUN_IDENTITY_SHA256.txt",
    )
    if (identity_sha, binary_sha, fence_sha) != (final_identity_sha, final_binary_sha, final_fence_sha):
        raise EvidenceError("final prepared identity check differs from the frozen run identity")
    passes.append("Final prepared identity, evidence-owned binary SHA, Product fence, SQL checkout, and candidate files reverify before manifest creation.")

    text = "# Wave 00 Cheap Checks\n\n"
    text += "\n".join(f"- PASS: {item}" for item in passes)
    text += (
        "\n\nExpected sample matrix: Q01 3 lanes, Q02 4 lanes, T01 3 lanes, P01 3 lanes; "
        "13 lane/scenario combinations x 7 rounds = 91 timed samples. "
        "R01 and Q/P resource-only runs are outside RAW_SAMPLES.ndjson.\n"
    )
    (output / "CHEAP_CHECKS.md").write_text(text, encoding="utf-8")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    create_fence_parser = subparsers.add_parser("create-product-fence")
    create_fence_parser.add_argument("--repository", required=True)
    create_fence_parser.add_argument("--package", required=True)
    create_fence_parser.add_argument("--output-dir", required=True)
    verify_build_inputs_parser = subparsers.add_parser("verify-build-inputs")
    verify_build_inputs_parser.add_argument("--repository", required=True)
    verify_build_inputs_parser.add_argument("--package", required=True)
    verify_build_inputs_parser.add_argument("--output-dir", required=True)
    verify_build_inputs_parser.add_argument("--scratch-relative", action="append", required=True)
    create_identity_parser = subparsers.add_parser("create-identity")
    create_identity_parser.add_argument("--repository", required=True)
    create_identity_parser.add_argument("--package", required=True)
    create_identity_parser.add_argument("--binary", required=True)
    create_identity_parser.add_argument("--identity", required=True)
    create_identity_parser.add_argument("--sha-file", required=True)
    preserve_binary_parser = subparsers.add_parser("preserve-binary")
    preserve_binary_parser.add_argument("--source", required=True)
    preserve_binary_parser.add_argument("--destination", required=True)
    verify_identity_parser = subparsers.add_parser("verify-identity")
    verify_identity_parser.add_argument("--repository", required=True)
    verify_identity_parser.add_argument("--package", required=True)
    verify_identity_parser.add_argument("--binary", required=True)
    verify_identity_parser.add_argument("--identity", required=True)
    verify_identity_parser.add_argument("--sha-file", required=True)
    verify_identity_parser.add_argument("--emit-values", action="store_true")
    harness_parser = subparsers.add_parser("harness-identities")
    harness_parser.add_argument("--repository", required=True)
    harness_parser.add_argument("--package", required=True)
    harness_parser.add_argument("--output", required=True)
    validate_parser = subparsers.add_parser("validate-sample")
    validate_parser.add_argument("path")
    validate_parser.add_argument("kind", choices=("sample", "probe"))
    validate_parser.add_argument("scenario")
    validate_parser.add_argument("lane")
    validate_parser.add_argument("round", nargs="?", type=int)
    subparsers.add_parser("selftest-r01")
    resource_parser = subparsers.add_parser("validate-resources")
    resource_parser.add_argument("--path", required=True)
    summarize_parser = subparsers.add_parser("summarize")
    summarize_parser.add_argument("--repository", required=True)
    summarize_parser.add_argument("--raw", required=True)
    summarize_parser.add_argument("--resources", required=True)
    summarize_parser.add_argument("--logs", required=True)
    summarize_parser.add_argument("--output-dir", required=True)
    cheap_parser = subparsers.add_parser("cheap-check")
    cheap_parser.add_argument("--repository", required=True)
    cheap_parser.add_argument("--output-dir", required=True)
    cheap_parser.add_argument("--raw", required=True)
    cheap_parser.add_argument("--resources", required=True)
    cheap_parser.add_argument("--logs", required=True)
    cheap_parser.add_argument("--pre-finalization", action="store_true")
    manifest_parser = subparsers.add_parser("evidence-manifest")
    manifest_parser.add_argument("--output-dir", required=True)
    verify_manifest_parser = subparsers.add_parser("verify-evidence-manifest")
    verify_manifest_parser.add_argument("--output-dir", required=True)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "create-identity":
            create_prepared_identity(args)
        elif args.command == "preserve-binary":
            preserve_binary_command(args)
        elif args.command == "create-product-fence":
            create_product_fence_command(args)
        elif args.command == "verify-build-inputs":
            verify_build_inputs_command(args)
        elif args.command == "verify-identity":
            identity_sha, binary_sha, fence_sha = verify_prepared_identity(
                Path(args.repository), Path(args.package), Path(args.binary),
                Path(args.identity), Path(args.sha_file)
            )
            if args.emit_values:
                print(f"{identity_sha}\t{binary_sha}\t{fence_sha}")
            else:
                print(f"PREPARED_RUN_IDENTITY=PASS {identity_sha} binary={binary_sha}")
        elif args.command == "harness-identities":
            write_harness_identities(args)
        elif args.command == "validate-sample":
            validate_single(Path(args.path), args.kind, args.scenario, args.lane, args.round)
        elif args.command == "selftest-r01":
            r01_selftest_command(args)
        elif args.command == "validate-resources":
            validate_resource_file_command(args)
        elif args.command == "summarize":
            write_summaries(args)
        elif args.command == "cheap-check":
            cheap_check(args)
        elif args.command == "evidence-manifest":
            write_evidence_manifest(args)
        elif args.command == "verify-evidence-manifest":
            verify_evidence_manifest(args)
        return 0
    except (EvidenceError, OSError, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        print(f"summarize.py: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
