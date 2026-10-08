#!/bin/bash
# THE LANE — one parallel line of work, from its own worktree to master.
#
#   bash tool/lane.sh open  <name>     a worktree + branch off master, ready to run
#   bash tool/lane.sh land  <name>     rebase onto master, run the gates, merge, clean up
#   bash tool/lane.sh gate  <name>     run the land's gates on a lane as it stands, and stamp it
#   bash tool/lane.sh native <name>    build the lane's C, run its tests and parity
#   bash tool/lane.sh engine [<name>]  this checkout's engine (or a lane's) built from its own C
#   bash tool/lane.sh backup           copy the trunk and every open lane to the mirror
#   bash tool/lane.sh list             what is open right now
#   bash tool/lane.sh drop  <name>     throw a lane away (its commits go with it)
#   bash tool/lane.sh sweep            delete the empty shells left by Windows
#   bash tool/lane.sh sync             (away) make this machine's master the trunk's
#   bash tool/lane.sh send  <name>     (away) put a finished lane on the mirror
#   bash tool/lane.sh unsend <name>    (away) take that offer back
#   bash tool/lane.sh receive <machine>/<name>   take a sent lane, ready to land
#   bash tool/lane.sh incoming         what other machines sent that is not here
#
# 🚨WHY A SCRIPT AND NOT A PARAGRAPH. Round 8 ran ten lanes at once and every
# rule below was learned by breaking it. A paragraph is read once; this is read
# every time. The account is suspended, so origin is frozen and LOCAL master is
# the trunk — that is not a workaround to remember, it is what `open` does.
#
# ⛔THE SEVEN THINGS THIS REFUSES TO LET YOU DO
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
#    on one side and a fixture on the other). (Measured ONCE: a lane whose
#    gates passed on the very commit that merges is not measured a second
#    time — see MEASURED ONCE below.)
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
# 7. Land a lane that moved while its gates ran. The gates measure the
#    WORKING TREE; the merge takes COMMITS, and the worktree is removed with
#    --force right after it. 2026-09-30: while a land sat in `flutter
#    analyze`, its author fixed the very architecture test that was red — in
#    the lane, uncommitted. The gates measured the fix and passed, the merge
#    took the commits without it, the removal destroyed it, and master's
#    test/architecture, the gate every later land has to pass, stayed red
#    until a lane of its own repaired it (66e598ba4, then 6ab4facd1). So
#    after its last gate `land` asks again what it asked before the rebase —
#    does the tree hold exactly the lane's commits — and whether HEAD is
#    still the commit the rebase made. On either no it refuses and the lane
#    stays as it is: commit the edit (or discard it) and land again.
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
# 🆕A SECOND MACHINE (2026-10-07). 유저: 「작업을 노트북이 해줫으면
# 한단거지」 — one machine queues its Flutter runs, and there are others in
# the house. And on how its branches reach this one: 「브랜치는 깃 랩 미러로
# 하고」 (cards work-runs-on-the-surface-too,
# a-lane-arrives-from-another-machine).
#
# ONE machine holds the trunk: the one whose clone names no machine. Every
# other clone names itself once —
#     git config anicel.machine surface11
# — and from then on it is an AWAY machine, where three things differ:
#   · its master is a COPY of the trunk. `sync` takes it from the mirror
#     (`open` does that first), and nothing ever lands on it: `land`
#     refuses, and it never pushes master anywhere. Two machines that each
#     landed would be two trunks.
#   · its lanes are work/<machine>/<name>. Two machines that both open
#     「fix」 keep apart on the mirror, where lanes are pushed with force —
#     and a lane of the trunk's machine, whose name can hold no slash, can
#     never be taken for one that came from elsewhere.
#   · a finished lane is SENT, not landed: `send <name>` puts it on the
#     mirror — with the stamp of its gates, when it was gated here.
# The trunk's machine takes it with `receive <machine>/<name>` and from
# there it is a lane like any other — `land` merges it, behind every gate
# (run on THIS machine unless they were run on that very commit already:
# MEASURED ONCE, below), and takes it off the mirror.
#
# ⚠️TWO PLACES ON THE MIRROR, BECAUSE THEY MEAN TWO THINGS. work/… is a
# COPY — `backup` keeps one of every open lane, finished or not. sent/…
# is an OFFER — only `send` writes there, `incoming` and `receive` read
# only there, and `land` takes it away. With one place for both, a lane
# that was merely backed up half-done would look exactly like one waiting
# to be landed (found running the commands for real, 2026-10-07). An offer
# that has left the mirror is how an away machine knows to LOOK: its next
# `sync` asks the trunk whether it holds the lane's commits, and lets go of
# the lane only then — an offer can also leave because it was taken back
# (`unsend`) or turned down, and those lanes hold work that is nowhere else.
#
# 🆕MEASURED ONCE (2026-10-08, card a-sent-lane-is-gated-once). 유저, as the
# 관제 session wrote it down that day: 「순서 기다리는게 싫어서 서피스로
# 옮겼던건데 똑같이 순서기다리고 리베이스해야하고 20분소모하고 이러는거
# 싫어서」 — and to the changes it then proposed: 「다 권하는대로 하자.
# 낭비없애자고」. Measured over the seven lanes sent that night: one pass of
# the land's gates took six to ten minutes, and four of the seven arrived
# sitting on master exactly as their machine had measured them — and were
# measured again here.
#   · `gate <name>` runs the land's gates on a lane as it stands and STAMPS
#     the commit they passed on. The stamp is the tool's, never a session's
#     word: nothing else writes it.
#   · `send` carries the stamp with the offer, and no longer asks that the
#     lane sit on the trunk as the mirror has it at that moment. ↩️It did,
#     so that 「what arrives is what was measured」 — the trunk moves some
#     thirty times a day, so the author rebased and measured again, only
#     for the trunk's machine to do both once more.
#   · `land` does not measure twice: a lane that still sits on master and
#     whose stamp names its very commit merges as it is. A master that
#     moved is what it always was — rebase, every gate, once.
# ⚠️A stamp says 「the gates passed on THIS commit」 and nothing about any
# other: one more commit, or a rebase, and it names nothing.
#
# ⚠️ONE LAND AT A TIME. `land` holds the trunk from before its rebase to
# after its merge; a second one waits its turn and then rebases onto what
# the first left. ↩️Two ran side by side, and the one whose gates finished
# second had its fast-forward refused — six minutes of gates thrown away,
# to be run again (2026-10-08, 관제: F-291's land lost that way to
# top-strip-narrows').
#
# ⚠️THE GATES ASK THE MACHINE BEFORE THEY LAUNCH, AND RUN AT IDLE. That is
# CLAUDE.md's 「Flutter 실행은 여유만큼」 (유저 2026-09-26 · 10-01): 4GB of
# commit headroom, fewer than four runs across every session, all of it
# Idle. One tool measures — tool/flutter_room.dart, whose head says what
# takes a place. ↩️Until 2026-10-08 this script measured nothing and
# lowered nothing: every session wrapped it in a waiter of its own, so a
# land waited for one of the four places like any run. 유저 that day, on
# the board (a-sent-lane-is-gated-once-Q1), chose 「착지 게이트는 이 넷에
# 세지 않는다 — 커밋 여유 4GB 는 똑같이 재고, 우선순위도 Idle 그대로」.
# So `land` waits for the headroom alone, `gate` — an ordinary run — for a
# place as well, and neither wants a waiter around it.
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
# THE MIRROR. ⛔Not a second trunk, and `.githooks/pre-push` lets it through
# ungated precisely because it runs no CI.
# ↩️Until 2026-10-07 this said 「nothing is ever pulled from it」. 유저 that
# day, on where a second machine's branches travel: 「브랜치는 깃 랩 미러로
# 하고」 (card a-lane-arrives-from-another-machine). What made the old
# sentence true still holds: THE TRUNK'S MACHINE NEVER TAKES MASTER FROM
# IT — master moves by `land`, here, and nowhere else. What changed: a lane
# made on another machine arrives through it (`receive`), and another
# machine takes its copy of master from it (`sync`) — origin's master only
# follows when a bundle is pushed; the mirror's follows every `land`.
MIRROR=backup

# WHICH MACHINE THIS IS. The one that holds the trunk says nothing; every
# other clone has named itself (the header says what that changes).
MACHINE="$(git -C "$ROOT" config --get anicel.machine 2>/dev/null || true)"
away() { [ -n "$MACHINE" ]; }

die() { echo "lane: $*" >&2; exit 1; }

# A path is a worktree only if it holds a `.git` FILE. See refusal 1.
require_worktree() {
  [ -f "$1/.git" ] || die "not a worktree: $1
  A directory with no .git inside is a leftover shell, and git -C on it runs in
  the MAIN checkout instead. Remove it and open the lane under a new name."
}

# A lane's directory. The slash of another machine's lane becomes a dash:
# the directories all sit side by side.
lane_path() { echo "$LANES/lane-${1//\//-}"; }

# Where a lane's gate stamp is kept on this machine: the commit `gate` saw
# every gate pass on (MEASURED ONCE, above). ⛔Not under refs/heads — it is
# no branch, and `backup`, `list` and the lanes' own patterns must never
# take it for a lane. On the mirror it travels as gated/<name>, beside the
# offer it vouches for.
gate_ref() { echo "refs/lane-gated/$1"; }

# The commit a lane was gated at, or nothing.
gated_at() {
  git -C "$ROOT" rev-parse -q --verify "$(gate_ref "$1")^{commit}" 2>/dev/null || true
}

# The lane a name means on this machine: an away machine's lanes all live
# under its own name, whether or not the caller spelled it out.
lane_named() {
  local name="$1"
  case "$name" in
    ''|*[!A-Za-z0-9._/-]*|*..*|/*|*/|*/*/*) die "not a lane name: '$name'" ;;
  esac
  if away; then
    case "$name" in
      "$MACHINE"/*) ;;
      */*) die "'$name' is another machine's lane — this one is $MACHINE" ;;
      *) name="$MACHINE/$name" ;;
    esac
  fi
  printf '%s\n' "$name"
}

cmd_open() {
  local name="${1:-}"; [ -n "$name" ] || die "open needs a name"
  name="$(lane_named "$name")" || exit 1
  if away; then
    # A lane is cut from the trunk as the mirror has it. Offline is not a
    # reason to refuse a lane — but it is said, because the lane will have
    # to be rebased before it can be sent.
    (cmd_sync) >/dev/null 2>&1 \
      || echo "lane: ⚠️could not take $TRUNK from $MIRROR — this lane starts from the $TRUNK this machine last saw" >&2
  else
    case "$name" in */*) die "'$name' names another machine's lane — \`receive\` takes those" ;; esac
  fi
  # Clear the shells first, so a name freed by a landed lane is usable again
  # rather than burned for ever. It only ever removes what is not a worktree.
  cmd_sweep >/dev/null
  local p; p="$(lane_path "$name")"
  [ -e "$p" ] && die "already there: $p (pick another name — reusing a path mixes the old build cache in)"
  git -C "$ROOT" worktree add "$p" -b "work/$name" "$TRUNK" >/dev/null || die "worktree add failed"
  furnish "$p"
  echo "$p"
}

# What a fresh worktree needs before anything can run in it. `open` and
# `receive` both end here, so a lane that arrived from another machine is
# given exactly what one cut on this machine is.
furnish() {
  local p="$1"
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
  name="$(lane_named "$name")" || exit 1
  local p; p="$(lane_path "$name")"
  git -C "$ROOT" worktree remove "$p" --force 2>/dev/null || rm -rf "$p"
  git -C "$ROOT" worktree prune
  git -C "$ROOT" branch -D "work/$name" 2>/dev/null
  # Its stamp goes with it: a lane opened later under the same name is
  # another lane.
  git -C "$ROOT" update-ref -d "$(gate_ref "$name")" 2>/dev/null
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
  # ⛔AN AWAY MACHINE NEVER PUSHES MASTER. Its master is a copy; the mirror's
  # is the trunk's, and a copy pushed over it — stale, or carrying a commit
  # somebody made on the wrong branch — is what the trunk's next `land`
  # would then fail to mirror.
  away && return 0
  git -C "$ROOT" remote get-url "$MIRROR" >/dev/null 2>&1 || {
    echo "lane: ⚠️no '$MIRROR' remote — $TRUNK exists on this disk only." >&2
    return 0
  }
  echo "lane: mirroring $TRUNK -> $MIRROR"
  git -C "$ROOT" push --quiet "$MIRROR" "$TRUNK" && return 0
  echo "lane: ⚠️THE MIRROR PUSH FAILED — $TRUNK is on this disk only." >&2
  echo "lane:   The merge landed; it is the COPY that is missing. Retry with:" >&2
  echo "lane:   bash tool/lane.sh backup" >&2
  # Said, and ANSWERED: `land` goes on whatever this returns — nothing of
  # its own depends on the copy — and `backup` fails on it.
  return 1
}

# Every open lane too, not just the trunk: a lane's commits live in its branch
# and nowhere else, and a lane can sit open for days. FORCED, because a lane
# rebases — the mirror is a copy of what is here now, not a history to protect.
#
# ⚠️EACH MACHINE PUSHES ITS OWN LANES AND NOBODY ELSE'S. The push is forced,
# so a lane this machine merely RECEIVED — work/<machine>/<name> — pushed
# back from here would overwrite whatever its author sent since. The
# trunk's machine therefore leaves every lane under a machine's name alone,
# and an away machine pushes only the ones under its own.
# ⛔A BACKUP SAYS WHAT REACHED THE MIRROR, AND FAILS WHEN ITS COPY DID NOT.
# ↩️It ended on 「mirrored master and N open lane(s)」 and on 0, whatever
# had happened. 2026-10-08: the mirror's login was gone, both pushes failed,
# and that line stood under their two warnings — on the one command whose
# whole job is the copy.
cmd_backup() {
  local missed=
  mirror_trunk || missed=1
  git -C "$ROOT" remote get-url "$MIRROR" >/dev/null 2>&1 || return 0
  if away; then
    # First take the trunk and let go of what landed there — a lane the
    # trunk already has, pushed again, is a copy of nothing. `sync` does
    # both, and in that order: whether a lane landed is asked of THIS
    # machine's master, which has to be the trunk's before the answer means
    # anything. A master `sync` refuses is said, and is no reason not to
    # back up.
    (cmd_sync) || true
    git -C "$ROOT" push --quiet "$MIRROR" \
      "+refs/heads/work/$MACHINE/*:refs/heads/work/$MACHINE/*" \
      || die "the open lanes did not reach $MIRROR — nothing was copied"
    echo "lane: mirrored $(git -C "$ROOT" for-each-ref \
      --format='%(refname)' "refs/heads/work/$MACHINE/**" | wc -l) open lane(s)"
    return 0
  fi
  # ⚠️Named one by one. `refs/heads/work/*` stops at a slash in
  # for-each-ref and does NOT in a push refspec, where it would sweep the
  # received lanes along — and a refspec may hold one `*`, so there is no
  # pattern that says 「one level」.
  local own; own="$(git -C "$ROOT" for-each-ref \
    --format='+%(refname):%(refname)' 'refs/heads/work/*')"
  if [ -n "$own" ]; then
    # shellcheck disable=SC2086
    git -C "$ROOT" push --quiet "$MIRROR" $own || {
      echo "lane: ⚠️the open lanes did not reach $MIRROR." >&2
      missed=1
    }
  fi
  [ -z "$missed" ] || die "the backup did not reach $MIRROR — what is said above is what is missing"
  echo "lane: mirrored $TRUNK and $(printf '%s' "$own" | grep -c .) open lane(s)"
}

# (away) This machine's master becomes the trunk's, as the mirror has it.
# ⛔The trunk's machine refuses: its master IS the trunk, and taking
# another over it is the one thing the mirror must never be used for.
cmd_sync() {
  away || die "sync is for an away machine — this one holds the trunk"
  git -C "$ROOT" remote get-url "$MIRROR" >/dev/null 2>&1 \
    || die "no '$MIRROR' remote — add the mirror first"
  [ "$(git -C "$ROOT" branch --show-current)" = "$TRUNK" ] \
    || die "the main checkout is not on $TRUNK — lanes are worktrees, the main checkout stays on $TRUNK"
  git -C "$ROOT" fetch --quiet "$MIRROR" "$TRUNK" \
    || die "could not fetch $TRUNK from $MIRROR"
  # ⚠️ASKED BEFORE THE MERGE, not left to it. `merge --ff-only` of a commit
  # this master is already AHEAD of succeeds — there is nothing to do — and
  # that is exactly the master that must be refused: it holds a commit the
  # trunk does not (found running this for real, 2026-10-07).
  git -C "$ROOT" merge-base --is-ancestor "$TRUNK" FETCH_HEAD \
    || die "this machine's $TRUNK holds commits the trunk does not
  Nothing lands on an away machine. Keep them — git branch work/$MACHINE/rescue $TRUNK —
  then put $TRUNK back: git reset --keep FETCH_HEAD."
  git -C "$ROOT" merge --ff-only FETCH_HEAD >/dev/null 2>&1 \
    || die "could not move $TRUNK to the trunk's — is the main checkout clean?"
  echo "lane: $TRUNK is the trunk's $(git -C "$ROOT" rev-parse --short HEAD)"
  landed_lanes_leave
}

# (away) Let go of the lanes that landed. A lane this machine sent, whose
# offer is no longer on the mirror, is ASKED ABOUT — and dropped here only
# when the trunk holds every commit of it, it has not grown since it was
# sent, and its worktree holds nothing uncommitted. Everything else stays
# and says why: commits written after the send exist nowhere else, neither
# does work typed into the worktree and never committed, and neither does a
# lane whose offer left the mirror without landing.
# ⚠️Silent and harmless when the mirror cannot be asked: a lane is only
# ever looked at on the mirror's own word that the offer is gone.
#
# ⛔「THE OFFER IS GONE」 IS NOT 「IT LANDED」. The first version dropped on
# that alone, and an offer leaves the mirror three ways — `land`, `unsend`,
# and somebody deleting the branch. Two of the three would have thrown away
# the only copy of the work (2026-10-07, read before any machine used it).
landed_lanes_leave() {
  local offers
  offers="$(GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=Never git -C "$ROOT" \
    ls-remote --heads "$MIRROR" "refs/heads/sent/$MACHINE/*" 2>/dev/null)" \
    || return 0
  local ref name sent p
  git -C "$ROOT" for-each-ref --format='%(refname:short)' \
    "refs/heads/work/$MACHINE/*" | while read -r ref; do
      name="${ref#work/}"
      sent="$(git -C "$ROOT" config --get "branch.$ref.sent" 2>/dev/null)" || continue
      printf '%s\n' "$offers" | grep -q "refs/heads/sent/$name\$" && continue
      if ! trunk_holds "$sent"; then
        git -C "$ROOT" config --unset "branch.$ref.sent"
        echo "lane: ⚠️$name is no longer offered on $MIRROR, and $TRUNK does not hold it." >&2
        echo "lane:   It was taken back or turned down (or landed with its conflicts resolved by hand): the lane is kept." >&2
      elif [ "$(git -C "$ROOT" rev-parse "$ref")" = "$sent" ]; then
        # ⛔ITS COMMITS LANDED; WHAT WAS TYPED INTO ITS WORKTREE SINCE DID
        # NOT. The tip only says no commit was added, and a drop removes the
        # worktree with --force. 2026-10-08, the second machine: a session
        # kept working in a lane it had sent, uncommitted; the lane landed,
        # ANOTHER session's `open` ran this, and two files went with the
        # worktree (card a-landed-lane-is-dropped-with-its-uncommitted-work).
        # So the worktree is asked, through the one check a land asks — new
        # files count. It stays asked about: once it is clean it is let go,
        # and once its edits are committed it is 「has commits since」, below.
        p="$(lane_path "$name")"
        if [ -f "$p/.git" ] && ! lane_is_clean "$p"; then
          echo "lane: ⚠️$name landed, and its worktree holds changes nobody committed (above) — it is kept." >&2
          echo "lane:   They are in no commit and on no other machine: commit them, or move them to a new lane." >&2
          continue
        fi
        echo "lane: $name landed — letting go of it here"
        (cmd_drop "$name") >/dev/null 2>&1
      else
        git -C "$ROOT" config --unset "branch.$ref.sent"
        echo "lane: ⚠️$name landed as it was sent (${sent:0:10}), and has commits since." >&2
        echo "lane:   They are on no other machine: rebase the lane onto $TRUNK and send it again." >&2
      fi
    done
}

# Does the trunk hold every commit that leads to $1? Asked by PATCH, not by
# name: `land` rebases a lane before it merges, so what landed carries other
# hashes than what was sent. A `+` from `git cherry` is a commit whose patch
# the trunk does not have; none of them means all of it landed.
trunk_holds() {
  local missing
  missing="$(git -C "$ROOT" cherry "$TRUNK" "$1" 2>/dev/null)" || return 1
  ! printf '%s\n' "$missing" | grep -q '^+'
}

# (away) Put a finished lane on the mirror for the trunk's machine — as it
# stands, with the stamp of its gates when `gate` made one for this very
# commit.
# ↩️Until 2026-10-08 the lane had to sit on top of the trunk as the mirror
# had it at that moment (「what arrives there is what was measured here」),
# and `send` took the trunk first to ask. The trunk moves some thirty times
# a day: the author rebased and ran the gates again just to be allowed to
# send, and the trunk's machine then did both once more. 유저 that day, of
# the waiting: 「다 권하는대로 하자. 낭비없애자고」 (MEASURED ONCE, above). A
# lane behind the trunk is rebased where it lands, as every lane is.
cmd_send() {
  away || die "send is for an away machine — on the trunk's machine a lane lands"
  local name="${1:-}"; [ -n "$name" ] || die "send needs a name"
  name="$(lane_named "$name")" || exit 1
  local p; p="$(lane_path "$name")"
  require_worktree "$p"
  lane_is_clean "$p" || die "uncommitted changes in the lane — commit them first
  A '??' line is a file nobody added; it does NOT travel with the push."
  local head; head="$(git -C "$p" rev-parse HEAD)"
  # The stamp travels only when it names the commit that is offered: one of
  # an earlier commit vouches for nothing here, and leaves the mirror.
  local stamped=; [ "$(gated_at "$name")" = "$head" ] && stamped=1
  git -C "$ROOT" push --quiet "$MIRROR" \
    "+refs/heads/work/$name:refs/heads/sent/$name" \
    ${stamped:+"+$(gate_ref "$name"):refs/heads/gated/$name"} \
    || die "the lane did not reach $MIRROR"
  [ -n "$stamped" ] || git -C "$ROOT" push --quiet "$MIRROR" \
    --delete "gated/$name" >/dev/null 2>&1 || true
  # What was offered, so `landed_lanes_leave` can tell a lane that landed
  # from one that landed AND was worked on since.
  git -C "$ROOT" config "branch.work/$name.sent" "$head"
  echo "lane: sent work/$name at ${head:0:10}"
  if [ -n "$stamped" ]; then
    echo "lane:   gated here at that commit — it lands unmeasured again while the trunk has not moved"
  else
    echo "lane:   not gated here (\`gate $name\` stamps it) — the trunk's machine runs the gates"
  fi
  echo "lane:   on the trunk's machine: bash tool/lane.sh receive $name"
}

# (away) Take an offer back — sent by mistake, or not ready after all. The
# lane itself is not touched, and it stops being asked about.
cmd_unsend() {
  away || die "unsend is for an away machine — offers are made there"
  local name="${1:-}"; [ -n "$name" ] || die "unsend needs a name"
  name="$(lane_named "$name")" || exit 1
  git -C "$ROOT" push --quiet "$MIRROR" --delete "sent/$name" 2>/dev/null \
    || die "nothing sent as $name on $MIRROR"
  # The stamp that went with the offer leaves with it; this machine's own
  # stays, and travels again if the same commit is sent again.
  git -C "$ROOT" push --quiet "$MIRROR" --delete "gated/$name" >/dev/null 2>&1 || true
  git -C "$ROOT" config --unset "branch.work/$name.sent" 2>/dev/null
  echo "lane: took back the offer of work/$name — the lane is as it was"
}

# Take a lane another machine sent. It comes in as a worktree furnished
# like any other, and `land <machine>/<name>` does the rest — the rebase,
# every gate, the merge — on this machine.
# ⚠️It fetches THAT BRANCH and nothing else: master never comes from the
# mirror to the machine that holds the trunk.
cmd_receive() {
  away && die "receive is for the machine that holds the trunk"
  local name="${1:-}"
  case "$name" in
    */*) ;;
    *) die "receive needs <machine>/<name> — \`incoming\` lists what waits" ;;
  esac
  name="$(lane_named "$name")" || exit 1
  local p; p="$(lane_path "$name")"
  cmd_sweep >/dev/null
  [ -e "$p" ] && die "already there: $p (drop it first to take the lane again)"
  git -C "$ROOT" show-ref --verify --quiet "refs/heads/work/$name" \
    && die "a branch work/$name is already here (drop it first to take the lane again)"
  GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=Never git -C "$ROOT" fetch --quiet \
    "$MIRROR" "refs/heads/sent/$name:refs/heads/work/$name" \
    || die "nothing sent as $name on $MIRROR (or no saved login for it — \`backup\` asks for one)"
  # The stamp its machine's `gate` made, when it sent one (MEASURED ONCE).
  # Whatever stamp an earlier lane of this name left here goes first: a
  # lane that arrives without one arrives unmeasured.
  git -C "$ROOT" update-ref -d "$(gate_ref "$name")" 2>/dev/null
  GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=Never git -C "$ROOT" fetch --quiet \
    "$MIRROR" "+refs/heads/gated/$name:$(gate_ref "$name")" >/dev/null 2>&1 || true
  git -C "$ROOT" worktree add "$p" "work/$name" >/dev/null || die "worktree add failed"
  furnish "$p"
  echo "$p"
}

# What other machines have sent. A lane already received says so.
cmd_incoming() {
  away && die "incoming is for the machine that holds the trunk"
  GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=Never git -C "$ROOT" ls-remote \
    --heads "$MIRROR" 'refs/heads/sent/*/*' \
    | sed -n 's|.*refs/heads/sent/||p' \
    | while read -r name; do
        if git -C "$ROOT" show-ref --verify --quiet "refs/heads/work/$name"; then
          echo "$name (received)"
        else
          echo "$name"
        fi
      done
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
    local name; name="$(lane_named "$1")" || exit 1
    c="$(lane_path "$name")"
    require_worktree "$c"
  fi
  ensure_engine "$c" || die "the engine in $c is not built from its C — see above"
  echo "lane: the engine in $c is built from its C"
}

# Refusal 5, runnable on its own. The header says why each step is there.
cmd_native() {
  local name="${1:-}"; [ -n "$name" ] || die "native needs a name"
  name="$(lane_named "$name")" || exit 1
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

# Is the lane's working tree exactly its commits? Printing what is not.
# `land` asks it twice — before the rebase, and after the gates (refusal 7) —
# and both times through this one function, so the two answers cannot drift.
lane_is_clean() {
  local p="$1"
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
  # no file and stages nothing, so a REAL edit still stops the land.
  git -C "$p" update-index -q --really-refresh >/dev/null 2>&1 || true
  [ -z "$(git -C "$p" status --short)" ] && return 0
  git -C "$p" status --short >&2
  return 1
}

# The turn this process holds while it lands (`land_turn` sets it).
HELD_TURN=

# ROOM FIRST (the head of this file: THE GATES ASK THE MACHINE). $1 is
# `land` for a land's gates — the headroom alone — and anything else for a
# run that takes one of the four places.
# ⛔An instrument that cannot measure launches nothing: 「no answer」 is not
# 「room」.
room_first() {
  local flag= seen rc told=
  [ "$1" = land ] && flag=--land
  until seen="$(dart "$ROOT/tool/flutter_room.dart" ${flag:+"$flag"} 2>&1)"; do
    rc=$?
    [ "$rc" -eq 1 ] || die "the machine's room could not be measured — nothing was launched
  $seen"
    [ -n "$told" ] || echo "lane: no room for the gates yet ($seen) — waiting"
    told=1
    # A land that waits is alive: its turn is not one to take over.
    [ -z "$HELD_TURN" ] || touch "$HELD_TURN"
    sleep 20
  done
}

# …AND AT IDLE: this shell is lowered, and Windows hands an Idle parent's
# class to everything it launches (measured 2026-10-08 — through a
# subshell, and through a bash script that execs a Windows program).
at_idle() {
  command -v powershell.exe >/dev/null 2>&1 || return 0
  local me; me="$(cat "/proc/$$/winpid" 2>/dev/null)" || return 0
  powershell.exe -NoProfile -NonInteractive -Command \
    "(Get-Process -Id $me).PriorityClass = 'Idle'" >/dev/null 2>&1 || true
}

# THE GATES A LANDING STANDS BEHIND, on the lane at $2 as it is checked
# out — refusals 3 and 5. `land` runs them after its rebase and `gate` on a
# lane as it stands: the same lines, so a stamp vouches for exactly what a
# land would have measured. $3 says which of the two is asking, for the
# room alone.
gates() {
  local name="$1" p="$2"
  room_first "${3:-}"
  at_idle
  echo "lane: flutter analyze (no arguments)"
  (cd "$p" && flutter analyze) >/dev/null 2>&1 || {
    (cd "$p" && flutter analyze) | tail -20 >&2
    die "analyze is not clean — this is refusal 3"
  }

  echo "lane: flutter test test/architecture"
  (cd "$p" && flutter test test/architecture) >/dev/null 2>&1 || {
    (cd "$p" && flutter test test/architecture) | grep -A4 '\[E\]' | head -20 >&2
    die "the architecture gate is red
  A 'grew past' failure is the lane's. A 'ceiling is slack' failure is the
  trunk's: land the lane, then lower the ceiling to the measured number."
  }

  # Refusal 5. Only a lane that touched the C pays for it.
  if [ -n "$(git -C "$p" diff --name-only "$TRUNK" HEAD -- packages/qa_native/src)" ]; then
    cmd_native "$name"
  fi
}

# Refusal 7, asked after the LAST gate: every gate read the working tree,
# and what follows — a merge, or a stamp — takes only the commit $2 that
# was read before the first. $3 is the command to run again.
unmoved_since() {
  local p="$1" measured="$2" again="$3"
  local now; now="$(git -C "$p" rev-parse HEAD)"
  [ "$now" = "$measured" ] || die "the lane got a commit while its gates ran — this is refusal 7
  HEAD was ${measured:0:10} when they started and is ${now:0:10} now: what
  the gates never measured would pass as measured. Run $again again."
  lane_is_clean "$p" || die "the lane was edited while its gates ran — this is refusal 7
  The gates measured these edits, but only the commits go on from here — a
  land merges them and removes the worktree with --force right after:
  master would get what nobody measured, and the edits would be destroyed.
  Commit them (or discard them) and run $again again."
}

# Run the land's gates on a lane as it stands, and STAMP the commit they
# passed on (MEASURED ONCE, at the head of this file). On an away machine
# this is what lets the trunk's machine land the lane without measuring it
# a second time.
# ⛔The stamp is written HERE and nowhere else — after the last gate, and
# only for the commit read before the first.
cmd_gate() {
  local name="${1:-}"; [ -n "$name" ] || die "gate needs a name"
  name="$(lane_named "$name")" || exit 1
  local p; p="$(lane_path "$name")"
  require_worktree "$p"
  lane_is_clean "$p" || die "uncommitted changes in the lane — commit them first
  A stamp names a COMMIT; the gates would be measuring more than it holds."
  local measured; measured="$(git -C "$p" rev-parse HEAD)"
  gates "$name" "$p" gate
  unmoved_since "$p" "$measured" gate
  git -C "$ROOT" update-ref "$(gate_ref "$name")" "$measured" \
    || die "the gates passed, and the stamp could not be written"
  echo "lane: gated work/$name at ${measured:0:10}"
}

# ONE LAND AT A TIME (the head of this file says what two at once cost).
# The turn is a directory in the repository's own .git — one for every
# worktree and every session — held from here to the end of the land,
# however it ends.
# ⚠️A lander that was killed leaves its turn behind. It is taken over when
# the process that held it is gone, or when it is older than any land takes.
land_turn() {
  local turn; turn="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)/lane-land.turn"
  local holder told=
  until mkdir "$turn" 2>/dev/null; do
    holder="$(cat "$turn/pid" 2>/dev/null || true)"
    if { [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; } \
      || [ -n "$(find "$turn" -maxdepth 0 -mmin +45 2>/dev/null)" ]; then
      rm -rf "$turn"
      continue
    fi
    [ -n "$told" ] || echo "lane: another lane is landing — waiting for its turn to end"
    told=1
    sleep 10
  done
  echo "$$" >"$turn/pid"
  HELD_TURN="$turn"
  # shellcheck disable=SC2064
  trap "rm -rf '$turn'" EXIT
}

cmd_land() {
  # ⛔NOTHING LANDS ON AN AWAY MACHINE. Its master is a copy of the trunk;
  # a merge into it would be a second trunk that no other machine has.
  away && die "nothing lands on an away machine ($MACHINE) — \`send\` the lane to the trunk's"
  local name="${1:-}"; [ -n "$name" ] || die "land needs a name"
  name="$(lane_named "$name")" || exit 1
  local p; p="$(lane_path "$name")"
  require_worktree "$p"

  land_turn

  lane_is_clean "$p" || die "uncommitted changes in the lane — commit them first
  A '??' line is a file nobody added; it does NOT travel with the merge."

  # MEASURED ONCE: the gates passed on this very commit, and the trunk has
  # not moved from under it — the tree that merges is the tree that was
  # measured, and measuring it again would say the same.
  local head; head="$(git -C "$p" rev-parse HEAD)"
  if [ "$(gated_at "$name")" = "$head" ] \
    && git -C "$p" merge-base --is-ancestor "$TRUNK" HEAD; then
    echo "lane: work/$name was gated at ${head:0:10} and sits on $TRUNK as it stands — not measured again"
  else
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
    # Refusal 7: the commit the gates below are measuring.
    local measured; measured="$(git -C "$p" rev-parse HEAD)"
    gates "$name" "$p" land
    unmoved_since "$p" "$measured" land
  fi

  git -C "$ROOT" merge --ff-only "work/$name" >/dev/null || die "fast-forward refused — someone moved $TRUNK under you; run land again"
  echo "lane: merged work/$name -> $(git -C "$ROOT" log --oneline -1)"

  git -C "$ROOT" worktree remove "$p" --force 2>/dev/null || rm -rf "$p" 2>/dev/null
  git -C "$ROOT" worktree prune
  git -C "$ROOT" branch -d "work/$name" 2>/dev/null
  # The stamp was for the lane that just merged; the name is free again.
  git -C "$ROOT" update-ref -d "$(gate_ref "$name")" 2>/dev/null
  echo "lane: $TRUNK is now $(git -C "$ROOT" rev-parse --short HEAD)"
  # A landed lane is finished on the mirror too: its OFFER goes — that is
  # how the machine that sent it, and `incoming` here, see that it landed —
  # and so do its stamp and its copy. (A lane that was never there has
  # nothing to take off; the push says so and is not listened to.)
  local gone
  for gone in "sent/$name" "gated/$name" "work/$name"; do
    GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=Never git -C "$ROOT" push --quiet \
      "$MIRROR" --delete "$gone" >/dev/null 2>&1 || true
  done
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
  sync) shift; cmd_sync "$@" ;;
  send) shift; cmd_send "$@" ;;
  unsend) shift; cmd_unsend "$@" ;;
  receive) shift; cmd_receive "$@" ;;
  incoming) shift; cmd_incoming "$@" ;;
  gate) shift; cmd_gate "$@" ;;
  *) sed -n '2,18p' "$0"; exit 2 ;;
esac
