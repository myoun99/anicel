#!/usr/bin/env bash
# Runs a tool of this folder as an exe, built once per machine per source.
#
#   bash tool/run.sh flutter_room --land
#   bash tool/run.sh board_say "$ANICEL_BOARD" lines.jsonl
#   bash tool/run.sh affected_tests --list
#
# The working directory, the arguments, the output and the exit code are the
# tool's own, exactly as `dart tool/<tool>.dart` would have them.
#
# 🆕2026-10-18 (card tests-crowd-the-machine; 유저 「원인 파악하고 확실하게
# 프로들이 하는대로 해결하면 전체적인 작업 빨라질거같은데」). Measured on the
# main PC under load: `dart tool/flutter_room.dart` took 16.5s where
# `dart.exe --version` took 0.26s — nearly all of a tool call was the JIT
# compiling the tool again, and a lane waiting for room asks every twenty
# seconds. And `dart` · `flutter` reached through the SDK's launcher take one
# lock for the whole machine (bin/cache/flutter.bat.lock) and run git and
# PowerShell inside it on every call: seventeen calls queued there on
# 2026-10-18 and every tool on the machine stopped for sixteen minutes.
# ⇒ The tool is compiled ONCE, into an exe named after what it was built
# from, and the SDK's own dart is called directly — past the lock.
#
# WHERE: the machine's own cache, never the repository and never a synced
# folder — %LOCALAPPDATA%\anicel\tools on Windows, ~/.cache/anicel/tools
# elsewhere. Per account: an account that is switched to builds its own,
# once (유저 「계정 바뀌는것도 감안하고 다른 서피스11디바이스/계정에서도
# 적용되도록」).
# WHAT IT IS MADE OF: tool/exe_stamp.sh — every file the tool imports, at
# every level — and the SDK's version. Two checkouts holding two versions of
# a tool hold two exes; neither rebuilds the other's.
#
# ⛔IT NEVER STANDS IN THE WAY. No SDK beside `flutter`, a compile that
# failed, a build somebody else is running that does not finish: the tool
# runs as it always did, by JIT, and a failed build is written down
# (<cache>/<tool>.build.log) instead of being retried silently forever.
# ⚠️No `set -u`: the Mac's bash 3.2 calls an empty "$@" unbound, and a tool
# asked with no arguments would die here.

# The Windows spelling where there is one: a tool hands this folder to
# programs that are not bash (git's working directory, for one), and those
# cannot read `/c/…`.
TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && { pwd -W 2>/dev/null || pwd; })"
. "$TOOL_DIR/exe_stamp.sh"
NAME="${1:?usage: bash tool/run.sh <tool> [arguments…]}"
shift
ENTRY="$TOOL_DIR/$NAME.dart"
# An exe does not sit beside its source, so a tool that has to find its own
# folder (flutter_room asks git from there) is told where it was built from.
export ANICEL_TOOL_DIR="$TOOL_DIR"

# The SDK's own dart, past the launcher's lock; whatever PATH calls `dart`
# when there is no SDK beside `flutter`.
dart_of() {
  local flutter sdk
  if flutter="$(command -v flutter 2>/dev/null)"; then
    sdk="${flutter%/*}/cache/dart-sdk/bin"
    for d in "$sdk/dart.exe" "$sdk/dart"; do
      [ -x "$d" ] && { printf '%s\n' "$d"; return 0; }
    done
  fi
  command -v dart
}
DART="$(dart_of)" || { echo "run.sh: no dart on this machine" >&2; exit 2; }
jit() { exec "$DART" "$ENTRY" "$@"; }
[ -f "$ENTRY" ] || jit "$@"

# ⚠️Every step here is paid on every call, and a call made from an Idle
# shell on a busy machine pays each process it starts many times over — so
# what bash can say itself is not asked of a program.
case "$OSTYPE" in msys* | cygwin*) EXT=.exe ;; *) EXT= ;; esac
if [ -n "${LOCALAPPDATA:-}" ]; then
  CACHE="${LOCALAPPDATA//\\//}/anicel/tools"
else
  CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/anicel/tools"
fi
sum() { if command -v sha1sum >/dev/null 2>&1; then sha1sum; else shasum; fi; }
read -r KEY _ < <({ cat "${DART%/*}/../version" 2>/dev/null; stamp_of "$ENTRY"; } | sum)
KEY="${KEY:0:16}"
EXE="$CACHE/$NAME-$KEY$EXT"
[ -x "$EXE" ] && exec "$EXE" "$@"

# One builder per exe. A build that is already under way is waited for —
# a second compile, or a JIT run beside it, would spend the same CPU twice —
# and a lock left by a builder that died is taken over after ten minutes.
LOCK="$EXE.building"
mkdir -p "$CACHE" 2>/dev/null || jit "$@"
[ -n "$(find "$LOCK" -maxdepth 0 -mmin +10 2>/dev/null)" ] && rmdir "$LOCK" 2>/dev/null
if mkdir "$LOCK" 2>/dev/null; then
  PART="$CACHE/$NAME-$KEY.$$.part$EXT"
  # From the repository's root, where the package config is.
  if (cd "$TOOL_DIR/.." && "$DART" compile exe "$ENTRY" -o "$PART") \
      > "$CACHE/$NAME.build.log" 2>&1; then
    mv -f "$PART" "$EXE" 2>/dev/null
  fi
  rm -f "$PART"
  rmdir "$LOCK" 2>/dev/null
  # A week unasked is old. ⚠️Not 「every other version」: two checkouts can
  # hold two versions of one tool at once, and each would delete the other's
  # on every build. One that is running cannot be deleted on Windows; it is
  # simply asked again next time.
  find "$CACHE" -maxdepth 1 -name "*-*$EXT" -mtime +7 -type f -delete 2>/dev/null
else
  for _ in $(seq 1 120); do
    [ -x "$EXE" ] || [ ! -d "$LOCK" ] && break
    sleep 1
  done
fi
[ -x "$EXE" ] && exec "$EXE" "$@"
jit "$@"
