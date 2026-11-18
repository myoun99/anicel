#!/usr/bin/env bash
# Which tests call into the engine's library — the ONE answer to that question.
#
# 🗣️WHAT IT PICKS, AND WHY IT STAYED (관제 2026-11-13, board
# what-still-runs-on-the-cpu). Every test file that names `src/native/`: the
# app's bindings to the engine's library live under `lib/src/native/`, so a
# test that imports one calls into the library itself. Chosen by what a test
# IMPORTS rather than from a list, so a new one joins without anybody
# remembering to add it.
#
# Four release workflows ask — the TestFlight build, the Mac build, the Linux
# build and the Windows ARM64 build — and each runs the list on the machine
# that built that platform's release, on the engine's library as that
# machine's compiler made it: the check a release cannot skip. For the three
# ARM ones it is also where a commit's engine first runs on that CPU. Both
# desks and every CI shard a push starts are x86_64, so what the engine does
# on ARM alone — the premultiplied copy's NEON step (native/premultiply) —
# runs on this road, or on one somebody started by hand (gpu-engine.yml,
# apple-nightly.yml).
#
# ⚠️THE NAME IS THE OLD MEANING, and is changed after the connection round.
# 「Parity」 was the C engine held to its Dart reference. The C went on
# 2026-11-13, and with it the fifth asker — `lane.sh land`, for a lane that
# touched the C's sources — and three of the names searched for here: the C
# engine's path helper, its loader and its binding class. The name waits
# because the four workflows' next run is their first on these changes, and
# a rename is four more places to be wrong in.
#
# Copies of a selector drift apart, and two builds that pick different sets
# are testing different things while printing the same green — so the four
# ask this one script, and hand what it prints to
# `tool/affected_tests.dart --files-from`: WHICH files is this script's
# answer, HOW they run is the run plan's.
#
# Prints one path per line, sorted, relative to the repository root.
# ⛔Exits 1 when it selects NOTHING: a selector that stopped matching would
# otherwise sail through as a pass — the one way this check could quietly
# stop checking.
set -u
cd "$(dirname "$0")/.." || exit 1
list=$(grep -rl 'src/native/' test --include='*_test.dart' | sort)
if [ -z "$list" ]; then
  echo "native_parity_tests: selected nothing" >&2
  exit 1
fi
printf '%s\n' "$list"
