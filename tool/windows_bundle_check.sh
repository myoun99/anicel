#!/usr/bin/env bash
#
# Would this Windows Release folder actually START on somebody's machine?
#
# 🚨2026-09-10: `flutter build windows --release` printed
# `√ Built build\windows\x64\runner\Release\Anicel.exe` and the exe died
# immediately:
#
#   'FlutterEngineInitialize' returned 'kInvalidArguments'.
#   Not running in AOT mode but could not resolve the kernel binary.
#
# The output folder still held the DEBUG engine (`flutter_windows.dll`,
# 45,549,056 bytes) from an earlier build in the same tree, next to a
# release `app.so`. A debug engine wants a JIT kernel; the release bundle
# does not ship one. The build did not overwrite the DLL and did not
# complain, so the only way to find out was to run it — and shipping is
# exactly the case where nobody does.
#
# ⛔This does NOT replace running the app. It catches the one failure that
# a green build line hides.
#
# Usage:
#   bash tool/windows_bundle_check.sh [path-to-Release-folder]
#
# Exit code: 0 the bundle is consistent · 1 it is not · 2 could not tell.

set -uo pipefail

BUNDLE="${1:-build/windows/x64/runner/Release}"

if [ ! -d "$BUNDLE" ]; then
  echo "could not tell: no such folder — $BUNDLE"
  echo "  (build one first: flutter build windows --release)"
  exit 2
fi

FLUTTER_ROOT="$(dirname "$(dirname "$(command -v flutter 2>/dev/null || echo /nonexistent/x/y)")")"
ENGINE="$FLUTTER_ROOT/bin/cache/artifacts/engine/windows-x64-release/flutter_windows.dll"

fail=0
say_fail() {
  echo "✗ $1"
  fail=1
}

# ① The engine has to be the RELEASE one. This is the check that would have
# caught it: the debug engine is roughly twice the size, and a size compare
# needs no hashing tool that may not be installed.
SHIPPED="$BUNDLE/flutter_windows.dll"
if [ ! -f "$SHIPPED" ]; then
  say_fail "no flutter_windows.dll in the bundle"
elif [ ! -f "$ENGINE" ]; then
  echo "could not tell: the SDK has no release engine to compare against"
  echo "  looked for: $ENGINE"
  exit 2
else
  shipped_size=$(wc -c < "$SHIPPED" | tr -d ' ')
  engine_size=$(wc -c < "$ENGINE" | tr -d ' ')
  if [ "$shipped_size" != "$engine_size" ]; then
    say_fail "the bundled engine is not the release engine"
    echo "    bundle: $shipped_size bytes"
    echo "    SDK   : $engine_size bytes  ($ENGINE)"
    echo "  ⇒ rm '$SHIPPED' && flutter build windows --release"
    echo "    (a build in the same tree does not overwrite it)"
  fi
fi

# ② A release bundle carries the AOT snapshot and no kernel. Either half
# missing is the same crash from the other side.
[ -f "$BUNDLE/data/app.so" ] || say_fail "no data/app.so — this is not an AOT bundle"
if [ -f "$BUNDLE/data/kernel_blob.bin" ]; then
  say_fail "data/kernel_blob.bin is present — a JIT bundle wearing a release name"
fi

# ③ The things it cannot start without.
[ -f "$BUNDLE/data/icudtl.dat" ] || say_fail "no data/icudtl.dat"
[ -d "$BUNDLE/data/flutter_assets" ] || say_fail "no data/flutter_assets"
ls "$BUNDLE"/*.exe > /dev/null 2>&1 || say_fail "no .exe in the bundle"

if [ "$fail" -eq 0 ]; then
  echo "✓ the bundle is consistent — release engine, AOT snapshot, assets"
  exit 0
fi
exit 1
