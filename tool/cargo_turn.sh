#!/bin/bash
# THE SHARED TARGET'S TURN — one cargo at a time builds into the trunk's
# target folder, and keeps it from its build to its last test.
#
#   bash tool/cargo_turn.sh [--folder hook] <cargo arguments…>
#   bash tool/cargo_turn.sh [--folder hook] --hold
#   bash tool/cargo_turn.sh [--folder hook] --where
#
# cargo, run where it is called from, with the trunk's
# packages/gpu_engine/rust/target as its target folder and no incremental
# cache, once no other cargo holds it; its exit code is cargo's.
#
# `--hold` runs no cargo: once the turn is its, it says that folder on its
# first line and keeps the turn until what it reads ends. It is for a caller
# that runs its cargo itself and keeps the turn past it — the engine's build
# hook (packages/gpu_engine/hook/build.dart), which copies its library out
# of the folder before another cargo may build there again (관제 ·
# 브러시/렌더링 2026-11-07, connection-round-checklist (나) ⓑ).
#
# `--where` takes no turn and runs no cargo: it says the folder as `--hold`
# does, for the hook to look there for what another checkout built from the
# same files before it asks for the turn (hook/shared_copies.dart).
#
# `--folder hook` is the build hook's folder of its own,
# packages/gpu_engine/rust/target-hook, with a turn of its own — the same
# law on a second folder (관제 2026-11-08 00:24, connection-round-checklist
# 00:21): under the crate folder's turn a lane's first test waited for a
# gate's whole run (445 s against 19 s), and the hook's release build,
# for a target named on its command line, shares the gate's host build
# scripts there — after a gate the hook built 14 of them and 30 crates
# again (45 s). Apart, neither builds a file of the other's.
#
# WHY (관제 2026-11-06, native-memory-safety): the trunk and every lane
# build the GPU engine's workspace into that one folder — wgpu is minutes
# cold, and the folder was 14 GB that day (47 GB on 2026-11-07), so one per
# checkout does not fit on this machine's C: (lane.sh, refusal 8). Cargo
# gives a workspace crate's build the same name in every checkout, and each
# checkout builds its own
# (QA_CHECKOUT, src/kernels/shared/one_checkout.rs) — so a second
# checkout's cargo REPLACES the first's builds while the first still runs:
# a land's release doc-tests failed twice with `E0463 can't find crate for
# media` when another checkout built `compress` and `media` again under it
# (타임라인/콘티, 14:56:40). Cargo's own lock is let go before the tests
# that read those builds. "Run no cargo there while a gate runs" was a
# rule written down, and it was not enough; this is the turn instead.
#
# ⛔EVERY CARGO THAT BUILDS INTO THAT FOLDER TAKES IT: the land's crate gate
# (lane.sh, cmd_crate), the engine's build hook (`--hold`) and every
# hand-run one alike — a session's Bash call
# that would build there any other way is refused before it runs
# (session_hooks/guard_shared_target.sh). A cargo with a target folder of
# its own — CARGO_TARGET_DIR elsewhere, or a lane's own default `target` —
# shares nothing, and needs no turn.
#
# ⛔NO INCREMENTAL CACHE IN A SHARED FOLDER (관제 2026-11-08 01:10,
# connection-round-checklist 01:06): cargo keeps one per crate and checkout
# and never removes one — 22 of the crate folder's 59 GB, 15 GB of it
# written on 2026-11-07 alone, with C: at 95 %. Off, a checkout's first
# build is 6–8 s faster (22–26 s against 30–33 s) and a rebuild after one
# line of the engine 6 s slower (10 s against 4 s); the disk decided. It is
# set here and not in Cargo.toml's [profile.dev], which would take it from a
# cargo with a folder of its own too. Were it back on, the old session
# folders would be what to sweep.
#
# ⚠️A holder that was killed leaves its turn behind. It is taken over when
# the process that held it is gone, or when it is older than any cargo run
# takes — the land's turn (lane.sh, land_turn) is kept the same way.
#
# 🚨FIRST COME, FIRST SERVED (card
# a-batch-is-cut-silent-while-it-waits-for-the-hook-turn, 2026-11-14): a
# waiter takes the turn only when its ticket is the oldest of a waiter that
# lives. With every waiter trying the folder every 5 s, the one that tried
# first after a holder let go took it — at 00:20 that day a hook that came
# at 00:11:56 took the hook folder's turn before two waiting since 00:05:24
# and 00:07:12, and the later one's batch was cut by 15 minutes of silence
# (tool/affected_tests.dart, kSilentBatch) before a test of it had run. A
# killed waiter's ticket goes when the next waiter finds its process gone.
# ⚠️No `set -u`: the Mac's bash 3.2 calls an empty "$@" unbound.

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON="$(git -C "$TOOL_DIR" rev-parse --path-format=absolute --git-common-dir)" || {
  echo "cargo_turn: $TOOL_DIR is not in a git checkout" >&2
  exit 2
}
TRUNK_ROOT="$(cd "$COMMON/.." && pwd)"
FOLDER=crate
if [ "$1" = --folder ]; then
  FOLDER="$2"
  shift 2
fi
case "$FOLDER" in
  crate)
    SHARED_TARGET="$TRUNK_ROOT/packages/gpu_engine/rust/target"
    TURN="$COMMON/cargo-target.turn"
    ;;
  hook)
    SHARED_TARGET="$TRUNK_ROOT/packages/gpu_engine/rust/target-hook"
    TURN="$COMMON/cargo-target-hook.turn"
    ;;
  *)
    echo "cargo_turn: no shared target is named '$FOLDER' (crate, hook)" >&2
    exit 2
    ;;
esac
# Longer than a cold debug and release build with every test after it.
STALE_MINUTES=120

say_folder() {
  mkdir -p "$SHARED_TARGET"
  # The caller may be no bash: on Windows, the folder as Windows writes it.
  (cd "$SHARED_TARGET" && { pwd -W 2>/dev/null || pwd; })
}
if [ "$1" = --where ]; then
  say_folder
  exit 0
fi

LINE="$TURN.line"
mkdir -p "$LINE"
TICKET="$(date +%s)-$$"
: >"$LINE/$TICKET"
# shellcheck disable=SC2064
trap "rm -f '$LINE/$TICKET'" EXIT

# The oldest ticket of a waiter that lives; a dead waiter's goes.
first_in_line() {
  for ticket in $(ls "$LINE" 2>/dev/null | sort); do
    if kill -0 "${ticket##*-}" 2>/dev/null; then
      echo "$ticket"
      return
    fi
    rm -f "$LINE/$ticket"
  done
}

told=
until [ "$(first_in_line)" = "$TICKET" ] && mkdir "$TURN" 2>/dev/null; do
  holder="$(cat "$TURN/pid" 2>/dev/null || true)"
  if { [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; } \
    || [ -n "$(find "$TURN" -maxdepth 0 -mmin +$STALE_MINUTES 2>/dev/null)" ]; then
    rm -rf "$TURN"
    continue
  fi
  if [ -z "$told" ]; then
    echo "cargo_turn: the shared target is held ($(cat "$TURN/what" 2>/dev/null || echo 'by the line before this run')) — waiting" >&2
    told=1
  fi
  # A land that waits here is alive: its turn is not one to take over
  # (lane.sh, still_landing).
  [ -z "$LANE_LAND_TURN" ] || touch -c "$LANE_LAND_TURN"
  sleep 5
done
rm -f "$LINE/$TICKET"
echo "$$" >"$TURN/pid"
echo "$(pwd) · cargo $*" >"$TURN/what"
# shellcheck disable=SC2064
trap "rm -rf '$TURN'" EXIT
[ -z "$told" ] || echo "cargo_turn: the shared target is this run's now" >&2

if [ "$1" = --hold ]; then
  say_folder
  cat >/dev/null
  exit 0
fi

CARGO_TARGET_DIR="$SHARED_TARGET" CARGO_INCREMENTAL=0 cargo "$@"
