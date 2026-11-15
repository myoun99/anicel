#!/usr/bin/env bash
# Runs a list of test files on a CI runner — the ONE way every workflow does.
#
#   bash tool/runner_tests.sh <file with one test path a line>
#
# By the run plan (tool/affected_tests.dart), as every list run goes: the
# pins that wait for the collector alone and last, the files that need
# Impeller on their own engine (dart_test.yaml, the gpu and impeller tags),
# each batch no longer than the command line Windows takes.
#
# --outside-the-line: a runner holds this one job, so there is no machine's
# line to share, and on Windows the line would wait for room it measures
# through PowerShell. --concurrency: half the runner's cores, package:test's
# own default — what a CI shard's `flutter test` ran at before the plan ran
# it (ci-shards-crowd-the-collector-pins).
# ↩️THE RELEASE WORKFLOWS RAN IN THE LINE TILL 2026-11-16, and a runner has
# no machine file, so the line gave each batch its default of ten suites:
# ten engines on the four cores of the Windows ARM64 runner, whose GPU is
# software, had `the GPU did not finish within 30s` 57 times and were cut at
# the job's 60 minutes (round 1091, run 43755979454); ten on the Mac's three
# held TestFlight past its 50 (run 43724266096). A runner is a runner, so the
# shards and the release builds run their lists here, alike (관제 2026-11-16,
# board round-1091-builds-all-stop-at-their-checks).
#
# ⛔`dart tool/…`, not `dart run tool/…`: `dart run` runs every package's
# build hook for the Dart VM first — the GPU engine's Rust among them — for
# a tool that imports none of them (tool/session_hooks/guard_dart_run.sh;
# 관제 2026-11-08, ci-dart-run-tools-build-the-engine-again).
set -euo pipefail

list=${1:?which list to run}
cores=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN)
half=$(( cores / 2 ))
[ "$half" -ge 1 ] || half=1
echo "runner_tests: $(wc -l < "$list") file(s) at $half of $cores cores"
dart tool/affected_tests.dart \
  --files-from "$list" \
  --outside-the-line --concurrency "$half"
