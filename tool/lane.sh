#!/bin/bash
# THE LANE — one parallel line of work, from its own worktree to master.
#
#   bash tool/lane.sh open  <name>     a worktree + branch off master, ready to run
#   bash tool/lane.sh land  <name>     rebase onto master, run the gates, merge, clean up
#   bash tool/lane.sh list             what is open right now
#   bash tool/lane.sh drop  <name>     throw a lane away (its commits go with it)
#   bash tool/lane.sh sweep            delete the empty shells left by Windows
#
# 🚨WHY A SCRIPT AND NOT A PARAGRAPH. Round 8 ran ten lanes at once and every
# rule below was learned by breaking it. A paragraph is read once; this is read
# every time. The account is suspended, so origin is frozen and LOCAL master is
# the trunk — that is not a workaround to remember, it is what `open` does.
#
# ⛔THE FOUR THINGS THIS REFUSES TO LET YOU DO
#
# 1. Run a git command in a worktree that is not one. `git worktree remove`
#    fails on Windows whenever a file is locked, and it leaves the DIRECTORY
#    behind with no `.git` in it. `git -C <that path> rebase` then walks up and
#    rebases THE MAIN CHECKOUT — 2026-09-07, master was rebased that way and
#    came back through the reflog. Every command here checks `test -f "$P/.git"`
#    first, and a lane whose directory survives its removal is re-opened under a
#    NEW path rather than reused.
# 2. Delete a lane before its merge lands. `land` removes the worktree only
#    after `merge --ff-only` returns 0. A rebase conflict stops the whole thing
#    with the worktree intact — resolve it there and run `land` again.
# 3. Merge without measuring. `land` runs `flutter analyze` WITH NO ARGUMENTS
#    and `flutter test test/architecture` after the rebase and before the merge.
#    A merge that rebases cleanly can still not compile: two lanes touching the
#    two ENDS of one type are each green alone (2026-09-07, a required parameter
#    on one side and a fixture on the other).
# 4. Leave master behind. `land` fast-forwards master last, so the next lane
#    someone opens is based on what just landed.
#
# ⚠️WHAT THIS CANNOT DO FOR YOU: judge a LAW COLLISION. Two lanes that never
# touch the same file still invent the same law under two names — seven times in
# round 8. When the rebase conflicts on a law rather than a line, the rule is:
# EQUIVALENT sides keep the name that landed first; UNEQUAL sides keep the one
# that removes more duplication, and the loser's unique contribution is carried
# onto the survivor. ⛔Never resolve by taking one side of a whole file: the
# other side's changes OUTSIDE the conflict markers go with it.
#
# ⚠️ONE FLUTTER COMMAND AT A TIME per machine. Ten concurrent runs exhausted the
# process table on 2026-09-07 (bash fork failures, a dead editor). Concurrent
# runs also share `build/test_cache` and die with PathExistsException; when a
# suite stalls, delete that folder and run it alone.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LANES="$ROOT/.claude/worktrees"
TRUNK=master

die() { echo "lane: $*" >&2; exit 1; }

# A path is a worktree only if it holds a `.git` FILE. See refusal 1.
require_worktree() {
  [ -f "$1/.git" ] || die "not a worktree: $1
  A directory with no .git inside is a leftover shell, and git -C on it runs in
  the MAIN checkout instead. Remove it and open the lane under a new name."
}

lane_path() { echo "$LANES/lane-$1"; }

cmd_open() {
  local name="${1:-}"; [ -n "$name" ] || die "open needs a name"
  # Clear the shells first, so a name freed by a landed lane is usable again
  # rather than burned for ever. It only ever removes what is not a worktree.
  cmd_sweep >/dev/null
  local p; p="$(lane_path "$name")"
  [ -e "$p" ] && die "already there: $p (pick another name — reusing a path mixes the old build cache in)"
  git -C "$ROOT" worktree add "$p" -b "work/$name" "$TRUNK" >/dev/null || die "worktree add failed"
  mkdir -p "$p/build"
  # The native engine, so parity pins RUN instead of skipping. A skip is not a pass.
  [ -d "$ROOT/build/native_standalone" ] && cp -r "$ROOT/build/native_standalone" "$p/build/" 2>/dev/null
  # 🚨AND THROW AWAY THE CMAKE CACHE THAT CAME WITH IT. A CMakeCache.txt
  # remembers the ABSOLUTE directory it was created in, so `cmake --build
  # build/native_standalone` inside the lane builds into the MAIN CHECKOUT
  # — a lane's uncommitted C landing in the trunk's binary, silently
  # (2026-09-08, caught while proving a decoder change). What the copy is
  # for is the built .dll; the cache is not part of that, and deleting it
  # makes a lane that wants to rebuild re-configure in its own directory,
  # which is the only correct answer.
  rm -f "$p/build/native_standalone/CMakeCache.txt"
  warn_if_engine_is_stale
  (cd "$p" && flutter pub get >/dev/null 2>&1)
  echo "$p"
}

# 🚨THE COPIED ENGINE CAN BE OLDER THAN THE C IT CAME FROM, and an ABI bump
# turns that into SEVENTY red tests at once (2026-09-09, v32: audio, video,
# resample and every parity pin, all saying the same thing — "the engine did
# not load — an ABI mismatch after a bump is the usual cause"). One cause,
# one line, and a whole gate run to find it.
#
# ⚠️Measured in the MAIN CHECKOUT, never in the lane: the lane's sources were
# written by `worktree add` seconds ago, so there every .c looks newer than
# every binary and the check would fire always and mean nothing.
warn_if_engine_is_stale() {
  local src="$ROOT/packages/qa_native/src"
  local dll
  for dll in "$ROOT/build/native_standalone/Release/qa_engine.dll" \
             "$ROOT/build/native_standalone/libqa_engine.dylib" \
             "$ROOT/build/native_standalone/libqa_engine.so"; do
    [ -f "$dll" ] || continue
    [ -n "$(find "$src" -type f -newer "$dll" -print -quit 2>/dev/null)" ] || return 0
    echo "lane: ⚠️the engine this lane copied is OLDER than packages/qa_native/src." >&2
    echo "lane:   Rebuild it IN THE LANE before you gate, or every native pin fails at once:" >&2
    echo "lane:   cmake -S packages/qa_native/src -B build/native_standalone -DCMAKE_BUILD_TYPE=Release" >&2
    echo "lane:   cmake --build build/native_standalone --config Release" >&2
    return 0
  done
}

cmd_list() {
  git -C "$ROOT" worktree list | grep -E "lane-" || echo "(none)"
}

# 🚨THE SHELLS ACCUMULATE, AND THEY ARE NOT HARMLESS. `land` and `drop` both
# try `worktree remove` and then `rm -rf`, and on Windows BOTH fail while any
# file under the directory is locked — a dart analysis server, a flutter_tester
# that has not exited, an editor with the folder open. What is left is a
# directory with no `.git` in it, and refusal 1 exists because `git -C` on one
# of those runs in the MAIN CHECKOUT.
#
# 🧪Measured 2026-09-10: 88 of the 96 directories under `.claude/worktrees`
# were shells, three days after the round that made them. They also BURN THE
# NAME — `open` refuses a path that exists, so every landed lane's name is
# unusable for ever unless something removes it.
#
# ⛔It deletes ONLY a directory that git does not list as a worktree AND that
# holds no `.git`. Either test alone is not enough: a live worktree that git
# has not been pruned about still holds its `.git` file, and a directory git
# still lists must never be removed behind git's back.
cmd_sweep() {
  local registered
  registered="|$(git -C "$ROOT" worktree list --porcelain \
    | sed -n 's|^worktree .*/worktrees/||p' | tr '\n' '|')"
  local gone=0 kept=0 d name
  for d in "$LANES"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    if [ -e "$d/.git" ] || [ "$name" = "logs" ] \
      || echo "$registered" | grep -q "|$name|"; then
      kept=$((kept + 1))
      continue
    fi
    rm -rf "$d" 2>/dev/null && gone=$((gone + 1)) || kept=$((kept + 1))
  done
  git -C "$ROOT" worktree prune
  echo "lane: swept $gone shell(s); $kept left (live worktrees and locked ones)"
}

cmd_drop() {
  local name="${1:-}"; [ -n "$name" ] || die "drop needs a name"
  local p; p="$(lane_path "$name")"
  git -C "$ROOT" worktree remove "$p" --force 2>/dev/null || rm -rf "$p"
  git -C "$ROOT" worktree prune
  git -C "$ROOT" branch -D "work/$name" 2>/dev/null
  echo "dropped work/$name"
}

cmd_land() {
  local name="${1:-}"; [ -n "$name" ] || die "land needs a name"
  local p; p="$(lane_path "$name")"
  require_worktree "$p"

  # The platform folders are rewritten by the build hooks on every run; they are
  # never anyone's change.
  git -C "$p" checkout -- linux macos windows 2>/dev/null
  # ⚠️UNTRACKED FILES COUNT. `--untracked-files=no` would let a new file the
  # author forgot to `git add` sit in the lane and vanish with the worktree —
  # the merge would take the callers and leave the file they call. Anything
  # .gitignore covers is already invisible here, so what is left is real work.
  # ⚠️REFRESH THE STAT CACHE FIRST. git calls a file modified when its mtime
  # moved, before comparing any bytes — and anything that merely READS a
  # worktree can move an mtime (a fleet of review agents opening files did it
  # twice on 2026-09-08). Without this, `land` refuses a lane whose content is
  # identical to HEAD and the author goes looking for a change that is not
  # there. `--refresh` compares the bytes and rewrites the cache; it changes
  # no file and stages nothing, so a REAL edit still stops the merge below.
  git -C "$p" update-index -q --really-refresh >/dev/null 2>&1 || true
  [ -z "$(git -C "$p" status --short)" ] || {
    git -C "$p" status --short >&2
    die "uncommitted changes in the lane — commit them first
  A '??' line is a file nobody added; it does NOT travel with the merge."
  }

  echo "lane: rebasing work/$name onto $TRUNK"
  git -C "$p" rebase "$TRUNK" >/dev/null 2>&1 || die "REBASE CONFLICT in $p
  Resolve it IN THE REBASE, commit by commit: fix the files, \`git -C $p add\`
  them, \`git -C $p rebase --continue\`, repeat. Then run land again.
  ⛔DO NOT abort and merge master into the lane instead. \`git rebase\` DROPS
  merge commits, so the merge you just resolved is thrown away and the same
  commits conflict again at the same places — 2026-09-08, 36 hunks resolved
  and lost that way before anyone noticed.
  If the conflict is a LAW rather than a line, read the rule at the top of
  this file before choosing a side."

  echo "lane: flutter analyze (no arguments)"
  (cd "$p" && flutter analyze) >/dev/null 2>&1 || {
    (cd "$p" && flutter analyze) | tail -20 >&2
    die "analyze is not clean after the rebase — this is refusal 3"
  }

  echo "lane: flutter test test/architecture"
  (cd "$p" && flutter test test/architecture) >/dev/null 2>&1 || {
    (cd "$p" && flutter test test/architecture) | grep -A4 '\[E\]' | head -20 >&2
    die "the architecture gate is red after the rebase
  A 'grew past' failure is the lane's. A 'ceiling is slack' failure is the
  trunk's: land the lane, then lower the ceiling to the measured number."
  }

  git -C "$ROOT" merge --ff-only "work/$name" >/dev/null || die "fast-forward refused — someone moved $TRUNK under you; run land again"
  echo "lane: merged work/$name -> $(git -C "$ROOT" log --oneline -1)"

  git -C "$ROOT" worktree remove "$p" --force 2>/dev/null || rm -rf "$p" 2>/dev/null
  git -C "$ROOT" worktree prune
  git -C "$ROOT" branch -d "work/$name" 2>/dev/null
  echo "lane: $TRUNK is now $(git -C "$ROOT" rev-parse --short HEAD)"
}

case "${1:-}" in
  open) shift; cmd_open "$@" ;;
  land) shift; cmd_land "$@" ;;
  list) shift; cmd_list "$@" ;;
  drop) shift; cmd_drop "$@" ;;
  sweep) shift; cmd_sweep "$@" ;;
  *) sed -n '2,9p' "$0"; exit 2 ;;
esac
