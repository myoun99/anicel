#!/bin/bash
# THE LANE — one parallel line of work, from its own worktree to master.
#
#   bash tool/lane.sh open  <name>     a worktree + branch off master, ready to run
#   bash tool/lane.sh land  <name>     rebase onto master, run the gates, merge, clean up
#   bash tool/lane.sh native <name>    build the lane's C, run its tests and parity
#   bash tool/lane.sh engine [<name>]  this checkout's engine (or a lane's) built from its own C
#   bash tool/lane.sh backup           copy the trunk and every open lane to the mirror
#   bash tool/lane.sh list             what is open right now
#   bash tool/lane.sh drop  <name>     throw a lane away (its commits go with it)
#   bash tool/lane.sh sweep            delete the empty shells left by Windows
#
# 🚨WHY A SCRIPT AND NOT A PARAGRAPH. Round 8 ran ten lanes at once and every
# rule below was learned by breaking it. A paragraph is read once; this is read
# every time. The account is suspended, so origin is frozen and LOCAL master is
# the trunk — that is not a workaround to remember, it is what `open` does.
#
# ⛔THE SIX THINGS THIS REFUSES TO LET YOU DO
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
# 5. Land C that nobody compiled. `flutter analyze` does not read C, and the
#    parity tests load whatever engine the lane was OPENED with — `open`
#    copies the trunk's binary, so a lane's own C edits reach no test unless
#    its author remembers to rebuild. 2026-09-09: a splice left
#    `coverage = 1.0;` above qa_engine.c's first line; MSVC warned and built,
#    every test passed against the old binary, and the iPad build (Apple
#    clang) was the first thing to refuse it, a day later. So a lane that
#    touched packages/qa_native/src is built here — EVERY target, because the
#    pen DLL lives beside the engine and a directory holding only qa_engine
#    fails the pen tests for a reason that has nothing to do with the change
#    — then its C tests run, then the parity subset runs against what was
#    just built, with QA_REQUIRE_NATIVE=1 so a missing binary fails instead
#    of skipping. `bash tool/lane.sh native <name>` runs the same thing
#    without landing. Measured 2026-09-10 from a clean
#    directory: 241 s for all of it (configure, every target, the C tests, 67
#    parity files). A lane that did not touch the C pays nothing.
# 6. Hand anyone an engine that was not built from the C beside it. Every
#    build this file runs stamps the name of the C it came from
#    (`build/native_standalone/.built-from`; what that name is, and why not a
#    file time or the ABI number, is at the head of
#    tool/native_engine_provenance.dart), and every place that puts an engine
#    in a checkout asks: `open` brings the TRUNK's engine up to the trunk's C
#    before copying it, then asks again of the copy in the lane; `land` asks
#    of the trunk once the merge has moved it; `native` and `engine` build
#    only when the answer is no. Five times in five days a lane or the trunk
#    ran its native pins against another checkout's C (2026-09-09..13) and
#    each was found by running the same files somewhere else. ⚠️A trunk
#    engine that cannot be rebuilt — a test run holding the DLL, a build
#    already going — is a WARNING, never a failed land: the next lane builds
#    its own. ⚠️`land` does not rebuild the LANE after its rebase: its gates
#    never load the engine and a green land deletes the lane at once, so that
#    build would be thrown away every time. What loads the engine says it
#    instead — `affected_tests` names a foreign engine before and after it
#    runs.
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
#
# ⚠️LANDING A CHANGE TO THIS FILE: run the land through a COPY.
#   cp tool/lane.sh tool/.lane_run.sh && bash tool/.lane_run.sh land <name>
# bash reads a script LAZILY, so the `merge --ff-only` near the end of `land`
# swaps this file out from under the interpreter at a byte offset it has not
# reached yet, and everything after the merge is read out of the wrong file.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LANES="$ROOT/.claude/worktrees"
TRUNK=master
# THE MIRROR. ⛔Not a second trunk: nothing is ever pulled from it, and
# `.githooks/pre-push` lets it through ungated precisely because it runs no CI.
MIRROR=backup

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
  # Refusal 6: what gets copied is first made the trunk's own, so a lane
  # opened after a C landing does not inherit the engine from before it
  # (2026-09-13: 156 reds in a lane gate, the trunk's 09-10 DLL).
  ensure_engine "$ROOT" \
    || echo "lane: ⚠️the trunk's engine is not built from the trunk's C — this lane builds its own" >&2
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
  # And the copy is asked again, of the lane: the trunk's engine is still
  # the wrong one when it could not be rebuilt above, or when the main
  # checkout holds C nobody has committed.
  ensure_engine "$p" \
    || echo "lane: ⚠️this lane's engine is not built from its C — native results here describe other C" >&2
  (cd "$p" && flutter pub get >/dev/null 2>&1)
  echo "$p"
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

# 🚨THE TRUNK LIVES ON ONE DISK UNTIL SOMETHING COPIES IT. origin is frozen
# while the account is suspended, so `land` advancing local master is the whole
# record of a day's work — on 2026-09-10 there were 969 commits in exactly one
# place, and it had been that way for nine days without anyone noticing. A
# backup that waits for somebody to remember it is the failure mode this file
# exists to refuse, so `land` pushes the mirror itself.
#
# ⚠️A FAILED PUSH MUST NOT FAIL THE LAND. The merge already happened, and
# calling the lane broken would send the author looking for a problem that is
# not there. It says loudly what to run instead.
mirror_trunk() {
  git -C "$ROOT" remote get-url "$MIRROR" >/dev/null 2>&1 || {
    echo "lane: ⚠️no '$MIRROR' remote — $TRUNK exists on this disk only." >&2
    return 0
  }
  echo "lane: mirroring $TRUNK -> $MIRROR"
  git -C "$ROOT" push --quiet "$MIRROR" "$TRUNK" && return 0
  echo "lane: ⚠️THE MIRROR PUSH FAILED — $TRUNK is on this disk only." >&2
  echo "lane:   The merge landed; it is the COPY that is missing. Retry with:" >&2
  echo "lane:   bash tool/lane.sh backup" >&2
}

# Every open lane too, not just the trunk: a lane's commits live in its branch
# and nowhere else, and a lane can sit open for days. FORCED, because a lane
# rebases — the mirror is a copy of what is here now, not a history to protect.
cmd_backup() {
  mirror_trunk
  git -C "$ROOT" remote get-url "$MIRROR" >/dev/null 2>&1 || return 0
  git -C "$ROOT" push --quiet "$MIRROR" '+refs/heads/work/*:refs/heads/work/*' \
    || echo "lane: ⚠️the open lanes did not reach $MIRROR." >&2
  echo "lane: mirrored $TRUNK and $(git -C "$ROOT" for-each-ref \
    --format='%(refname)' 'refs/heads/work/**' | wc -l) open lane(s)"
}

# cmake is on PATH on a Mac or a Linux box; on this Windows machine it lives
# in its installer's folder, which Git Bash does not know about.
find_cmake() {
  command -v cmake 2>/dev/null && return 0
  local c="/c/Program Files/CMake/bin/cmake.exe"
  [ -x "$c" ] && { printf '%s\n' "$c"; return 0; }
  return 1
}

# Refusal 6: the one question, and the one build that answers it.
ENGINE_STAMP=build/native_standalone/.built-from

# Is the engine in checkout $1 built from the C beside it? When it is not,
# build it there and stamp it. Non-zero when the answer is still no; the
# caller decides whether that is a warning or a refusal. Everything it says
# goes to stderr, because `open` prints the lane's path as its only output.
ensure_engine() {
  local c="$1" out rc
  out="$(dart "$ROOT/tool/native_engine_provenance.dart" check "$c")"
  rc=$?
  [ "$rc" -eq 0 ] && return 0
  [ "$rc" -eq 1 ] || {
    echo "lane: ⚠️could not name the C in $c — its engine is unchecked" >&2
    return 1
  }
  echo "lane: engine in $c: ${out#* } — building it from the C there" >&2
  build_engine "$c" || return 1
  printf '%s\n' "${out%% *}" >"$c/$ENGINE_STAMP"
}

# ⚠️ONE BUILD PER CHECKOUT AT A TIME. `open` and `land` both reach the
# trunk's engine, and on the same minutes: a C landing is exactly when the
# trunk's engine falls behind and exactly when the next lane gets opened.
# Two MSBuilds in one directory overwrite each other's objects. The lock is
# a directory because `mkdir` creates it or fails, atomically; a build that
# is killed leaves it behind, and the warning names it.
#
# The stamp goes BEFORE the build starts, so a build that dies half way —
# some targets relinked, some not — is never read as current afterwards.
build_engine() {
  local c="$1" cm ok=1
  local lock="$c/build/.engine-building" log="$c/build/lane-native.log"
  cm="$(find_cmake)" || {
    echo "lane: ⚠️cmake not found — the engine in $c is not rebuilt" >&2
    return 1
  }
  mkdir -p "$c/build"
  mkdir "$lock" 2>/dev/null || {
    echo "lane: ⚠️an engine build already holds $c — not starting a second one on top of it" >&2
    echo "lane:   (if none is running, a killed one left $lock behind: remove it)" >&2
    return 1
  }
  rm -f "$c/$ENGINE_STAMP"
  : >"$log"
  # The directory `open` copied holds the TRUNK's project files and no cache
  # (open deletes it), so a lane that never configured here starts clean
  # rather than building on top of another checkout's generator state.
  [ -f "$c/build/native_standalone/CMakeCache.txt" ] || rm -rf "$c/build/native_standalone"
  (cd "$c" \
    && "$cm" -S packages/qa_native/src -B build/native_standalone -DCMAKE_BUILD_TYPE=Release \
    && "$cm" --build build/native_standalone --config Release) >>"$log" 2>&1 && ok=0
  rmdir "$lock"
  [ "$ok" -eq 0 ] || echo "lane: ⚠️the engine build in $c is red — the whole log: $log" >&2
  return "$ok"
}

# Refusal 6, runnable on its own: `engine` asks it of the checkout this file
# sits in — the trunk, or a lane when run from inside one — and
# `engine <name>` of that lane.
cmd_engine() {
  local c="$ROOT"
  if [ -n "${1:-}" ]; then
    c="$(lane_path "$1")"
    require_worktree "$c"
  fi
  ensure_engine "$c" || die "the engine in $c is not built from its C — see above"
  echo "lane: the engine in $c is built from its C"
}

# Refusal 5, runnable on its own. The header says why each step is there.
cmd_native() {
  local name="${1:-}"; [ -n "$name" ] || die "native needs a name"
  local p; p="$(lane_path "$name")"
  require_worktree "$p"
  local cm; cm="$(find_cmake)" || die "cmake not found — not on PATH, not in C:/Program Files/CMake"
  local log="$p/build/lane-native.log" list="$p/build/lane-parity.txt"
  mkdir -p "$p/build"
  : >"$log"
  echo "lane: native — every target, the C tests, then parity against them"
  # Refusal 6 does the build: an engine already stamped with this lane's C
  # was built from exactly that C, every target, and is not built twice.
  ensure_engine "$p" || {
    grep -aE 'error C[0-9]+|: error:| error ' "$log" | head -15 >&2
    die "the engine is not built from this lane's C — this is refusal 5; the whole log: $log"
  }
  (cd "$p/build/native_standalone" \
    && "$(dirname "$cm")/ctest" -C Release --output-on-failure) >>"$log" 2>&1 || {
    grep -aE 'Failed|\*\*\*' "$log" | head -15 >&2
    die "the C tests are red — this is refusal 5; the whole log: $log"
  }
  (cd "$p" && bash tool/native_parity_tests.sh >"$list") \
    || die "the parity selector chose nothing — see tool/native_parity_tests.sh"
  (cd "$p" && QA_REQUIRE_NATIVE=1 xargs flutter test --no-pub <"$list") >>"$log" 2>&1 || {
    tr '\r' '\n' <"$log" | grep -a '\[E\]' | head -10 >&2
    die "parity is red against the engine this lane just built — this is refusal 5; the whole log: $log"
  }
  echo "lane: native — green ($(wc -l <"$list") parity files)"
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

  # Refusal 5. Only a lane that touched the C pays for it.
  if [ -n "$(git -C "$p" diff --name-only "$TRUNK" HEAD -- packages/qa_native/src)" ]; then
    cmd_native "$name"
  fi

  git -C "$ROOT" merge --ff-only "work/$name" >/dev/null || die "fast-forward refused — someone moved $TRUNK under you; run land again"
  echo "lane: merged work/$name -> $(git -C "$ROOT" log --oneline -1)"

  git -C "$ROOT" worktree remove "$p" --force 2>/dev/null || rm -rf "$p" 2>/dev/null
  git -C "$ROOT" worktree prune
  git -C "$ROOT" branch -d "work/$name" 2>/dev/null
  echo "lane: $TRUNK is now $(git -C "$ROOT" rev-parse --short HEAD)"
  # ⛔NOBODY IS THERE TO ANSWER A LOGIN. A land runs unattended, and with no
  # saved login git-credential-manager waited for one: the land never
  # returned, the trunk's engine below was never rebuilt, and the copy was
  # never made (lane-land-hangs-on-mirror-login, 2026-09-24). Here the push
  # fails at once and says to run `backup`, which still asks — a person can
  # log in there.
  GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=Never mirror_trunk
  # Refusal 6: the merge moved the trunk's C whenever this lane carried any,
  # and the trunk's engine follows it HERE, in the trunk's own directory and
  # cache — ⛔never the lane's build copied over, whose cache names the
  # lane's path (see `open`). Last, because the land has already happened: a
  # trunk engine that cannot be rebuilt now is the next `open`'s to fix.
  ensure_engine "$ROOT" \
    || echo "lane: ⚠️the trunk's engine is not built from the trunk's C — the next open tries again" >&2
}

case "${1:-}" in
  open) shift; cmd_open "$@" ;;
  land) shift; cmd_land "$@" ;;
  native) shift; cmd_native "$@" ;;
  engine) shift; cmd_engine "$@" ;;
  backup) shift; cmd_backup "$@" ;;
  list) shift; cmd_list "$@" ;;
  drop) shift; cmd_drop "$@" ;;
  sweep) shift; cmd_sweep "$@" ;;
  *) sed -n '2,12p' "$0"; exit 2 ;;
esac
