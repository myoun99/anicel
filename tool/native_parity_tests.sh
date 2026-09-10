#!/usr/bin/env bash
# Which tests exercise the native engine — the ONE answer to that question.
#
# Three places ask it: the TestFlight build on GitHub, the same build on
# Codemagic, and `lane.sh land` when a lane touched the C sources. Three
# copies of a selector drift apart, and a local gate that picks a different
# set from the CI it stands in for is testing something else while printing
# the same green. Chosen by what a test IMPORTS rather than from a list, so a
# new parity test joins without anybody remembering to add it.
#
# Prints one path per line, sorted, relative to the repository root.
# ⛔Exits 1 when it selects NOTHING: a selector that stopped matching would
# otherwise sail through as a pass — the one way this check could quietly
# stop checking.
set -u
cd "$(dirname "$0")/.." || exit 1
list=$(grep -rl 'native_engine_path\|qa_engine_abi\|QaNativeEngine\|src/native/' \
  test --include='*_test.dart' | sort)
if [ -z "$list" ]; then
  echo "native_parity_tests: selected nothing" >&2
  exit 1
fi
printf '%s\n' "$list"
