#!/bin/bash
# THE SHARED TARGET'S TURN — one cargo at a time builds into the trunk's
# target folder, and keeps it from its build to its last test.
#
#   bash tool/cargo_turn.sh <cargo arguments…>
#   bash tool/cargo_turn.sh --hold
#
# cargo, run where it is called from, with the trunk's
# packages/gpu_engine/rust/target as its target folder, once no other cargo
# holds it; its exit code is cargo's.
#
# `--hold` runs no cargo: once the turn is its, it says that folder on its
# first line and keeps the turn until what it reads ends. It is for a caller
# that runs its cargo itself and keeps the turn past it — the engine's build
# hook (packages/gpu_engine/hook/build.dart), which copies its library out
# of the folder before another cargo may build there again (관제 ·
# 브러시/렌더링 2026-11-07, connection-round-checklist (나) ⓑ).
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
# ⚠️A holder that was killed leaves its turn behind. It is taken over when
# the process that held it is gone, or when it is older than any cargo run
# takes — the land's turn (lane.sh, land_turn) is kept the same way.
# ⚠️No `set -u`: the Mac's bash 3.2 calls an empty "$@" unbound.

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON="$(git -C "$TOOL_DIR" rev-parse --path-format=absolute --git-common-dir)" || {
  echo "cargo_turn: $TOOL_DIR is not in a git checkout" >&2
  exit 2
}
TRUNK_ROOT="$(cd "$COMMON/.." && pwd)"
SHARED_TARGET="$TRUNK_ROOT/packages/gpu_engine/rust/target"
TURN="$COMMON/cargo-target.turn"
# Longer than a cold debug and release build with every test after it.
STALE_MINUTES=120

told=
until mkdir "$TURN" 2>/dev/null; do
  holder="$(cat "$TURN/pid" 2>/dev/null || true)"
  if { [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; } \
    || [ -n "$(find "$TURN" -maxdepth 0 -mmin +$STALE_MINUTES 2>/dev/null)" ]; then
    rm -rf "$TURN"
    continue
  fi
  if [ -z "$told" ]; then
    echo "cargo_turn: the shared target is held ($(cat "$TURN/what" 2>/dev/null)) — waiting" >&2
    told=1
  fi
  sleep 5
done
echo "$$" >"$TURN/pid"
echo "$(pwd) · cargo $*" >"$TURN/what"
# shellcheck disable=SC2064
trap "rm -rf '$TURN'" EXIT
[ -z "$told" ] || echo "cargo_turn: the shared target is this run's now" >&2

if [ "$1" = --hold ]; then
  mkdir -p "$SHARED_TARGET"
  # The caller may be no bash: on Windows, the folder as Windows writes it.
  (cd "$SHARED_TARGET" && { pwd -W 2>/dev/null || pwd; })
  cat >/dev/null
  exit 0
fi

CARGO_TARGET_DIR="$SHARED_TARGET" cargo "$@"
