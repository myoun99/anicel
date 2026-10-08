#!/usr/bin/env bash
# What a lane's gate, its stamp, its send and its land DO — run by hand; the
# suite spawns no process (tests_do_not_race_the_code_test), so what holds
# each step in its place there is the order of its lines
# (test/tool/a_land_takes_only_what_its_gates_measured_test.dart,
# a_lane_made_on_one_machine_lands_on_another_test.dart).
#
# 🚨IT RUNS IN SCRATCH REPOSITORIES, never in this one: a bare "mirror", a
# "home" clone that holds the trunk and an "away" clone that named itself,
# each given a copy of the lane script beside this file. `flutter` and
# `dart` are stand-ins first on PATH that write down every call — so 「the
# gates ran」 and 「the gates did not run」 are COUNTED, not believed — and
# can be told to be slow, to fail, or to edit or commit in the lane while a
# gate runs.
#
# What it holds (2026-10-08, card a-sent-lane-is-gated-once): a gate stamps
# the commit it passed on and nothing else · a lane that moved under its
# gates is neither stamped nor merged · a sent lane carries its stamp, and
# only the stamp of the very commit sent · a lane gated on its commit, on a
# trunk that has not moved, lands without being measured again — and every
# other lane is rebased and measured once · a stamp goes with its lane ·
# two lands started together both land, the second after the first · a
# lane that landed is kept on the machine that sent it while its worktree
# holds work nobody committed (card
# a-landed-lane-is-dropped-with-its-uncommitted-work).
#
# ⚠️The script before these changes fails 38 of the 70: it has no gate,
# refuses a sent lane that is behind the trunk, measures every lane twice,
# loses one of two lands started together, and deletes the uncommitted
# file.
#
# 🆕And the room (same day, same card — sections O to Q, 86 checks in
# all): the gates ask the machine before they launch — a gate for one of
# the four places, a land for the headroom alone — wait while there is no
# room, launch nothing when it cannot be measured, and run at Idle. ⚠️The
# script before THAT fails 12 of the 86: it asks nothing, so it neither
# waits nor refuses, and its gates run in the class it was started in.
# ⚠️It takes minutes, not seconds: the scratch lanes are real worktrees,
# and one section waits out the script's own twenty seconds.
#
# 🆕And the copy (2026-10-08, card the-mirror-login-lapsed — section R, 99
# checks in all): a backup that cannot reach the mirror says so, calls
# nothing mirrored and fails, on either machine; a land whose copy fails has
# still landed. ⚠️The script before THAT fails 4 of the 13 there: it ended
# on 「mirrored …」 and on 0 with both pushes failed.
#
# usage: bash tool/lane_test.sh [<another lane.sh to try>]
SCRIPT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lane.sh}"
E="$(mktemp -d "${TMPDIR:-/tmp}/lane-test.XXXXXX")" || exit 2
trap 'rm -rf "$E"' EXIT
mkdir -p "$E/bin"
export LANE_TEST_LOG="$E/flutter.log"; : > "$LANE_TEST_LOG"
cat > "$E/bin/flutter" <<'EOF'
#!/bin/bash
echo "$(basename "$PWD") flutter $*" >> "$LANE_TEST_LOG"
[ -z "${LANE_TEST_PRIORITY:-}" ] || powershell.exe -NoProfile -Command \
  "(Get-Process -Id $(cat /proc/$$/winpid)).PriorityClass" | tr -d '\r' >> "$LANE_TEST_LOG.priority"
case "${LANE_TEST_FLUTTER:-ok}" in
  slow) [ "$1" = analyze ] && sleep 5 ;;
  red) [ "$1" = analyze ] && exit 1 ;;
  edit) [ "$1" = analyze ] && echo edited >> a.txt ;;
  commit) [ "$1" = analyze ] && { echo x >> during.txt; git add during.txt; git commit -q -m "during the gates"; } ;;
esac
exit 0
EOF
# `dart` writes down what it was asked. Asked for the room
# (tool/flutter_room.dart) it answers what LANE_TEST_ROOM says — `full` is
# no room the first time and room after, `blind` cannot measure, anything
# else is room; asked for any other tool it only succeeds.
cat > "$E/bin/dart" <<'EOF'
#!/bin/bash
echo "$(basename "$PWD") dart $(basename "$1")${2:+ $2}" >> "$LANE_TEST_LOG"
[ "$(basename "$1")" = flutter_room.dart ] || exit 0
case "${LANE_TEST_ROOM:-ok}" in
  full) mkdir "$LANE_TEST_LOG.asked" 2>/dev/null && { echo "runs=4 free_gb=9 room=no"; exit 1; } ;;
  blind) echo "flutter_room: this machine could not be measured" >&2; exit 2 ;;
esac
echo "runs=0 free_gb=9 room=yes"
exit 0
EOF
chmod +x "$E/bin/flutter" "$E/bin/dart"
export PATH="$E/bin:$PATH"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
FAILS=0
say() { echo; echo "== $*"; }
check() {  # check <what> <got> <want>
  if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1 — got [$2], want [$3]"; FAILS=$((FAILS + 1)); fi
}
has() {  # has <what> <text> <needle>
  case "$2" in *"$3"*) echo "  ok   $1" ;; *) echo "  FAIL $1 — [$3] not in: $2"; FAILS=$((FAILS + 1)) ;; esac
}
lacks() {
  case "$2" in *"$3"*) echo "  FAIL $1 — [$3] in: $2"; FAILS=$((FAILS + 1)) ;; *) echo "  ok   $1" ;; esac
}
out() {  # out <dir> <lane.sh args...>: the command's output and exit, on one line
  local d=$1; shift
  (cd "$d" && bash tool/lane.sh "$@" 2>&1 | grep -v "^Preparing worktree" | tr '\n' ' '; echo "[exit ${PIPESTATUS[0]}]")
}
quiet() { local d=$1; shift; (cd "$d" && bash tool/lane.sh "$@" >/dev/null 2>&1); }
gates_run() { grep -c "flutter analyze\|flutter test test/architecture" "$LANE_TEST_LOG"; }
mirror_heads() { git -C "$E/mirror.git" for-each-ref --format='%(refname:short)' refs/heads | tr '\n' ' '; }
commit() { echo "$3" > "$1/$2"; git -C "$1" add "$2" 2>/dev/null; git -C "$1" commit -q -m "$3" 2>/dev/null; }
stamp() { git -C "$1" rev-parse -q --verify "refs/lane-gated/$2" 2>/dev/null || echo none; }
AW="$E/away/.claude/worktrees"; HW="$E/home/.claude/worktrees"

git init -q --bare "$E/mirror.git"
git init -q -b master "$E/home" 2>/dev/null
mkdir -p "$E/home/tool"; cp "$SCRIPT" "$E/home/tool/lane.sh"; echo one > "$E/home/a.txt"
printf '.claude/\nbuild/\n' > "$E/home/.gitignore"
git -C "$E/home" add -f tool/lane.sh a.txt .gitignore 2>/dev/null; git -C "$E/home" commit -q -m first
git -C "$E/home" remote add backup "$E/mirror.git"
quiet "$E/home" backup
git clone -q -o backup "$E/mirror.git" "$E/away"
git -C "$E/away" config anicel.machine surface11

say "A away: gate runs the land's gates on the lane as it stands and stamps the commit"
quiet "$E/away" open fix; commit "$AW/lane-surface11-fix" a.txt "fix it"
HEAD_FIX=$(git -C "$AW/lane-surface11-fix" rev-parse HEAD)
check "no stamp before the gate" "$(stamp "$E/away" surface11/fix)" none
N=$(gates_run); O=$(out "$E/away" gate fix)
has "gate says what it stamped" "$O" "gated work/surface11/fix at ${HEAD_FIX:0:10}"
check "both gates ran, once each" "$(( $(gates_run) - N ))" 2
check "the stamp names the lane's commit" "$(stamp "$E/away" surface11/fix)" "$HEAD_FIX"
check "the stamp is no branch" "$(git -C "$E/away" branch --list '*gated*' | wc -l | tr -d ' ')" 0

say "B a gate that fails, or a lane that moved under its gates, stamps nothing"
quiet "$E/away" open bad; commit "$AW/lane-surface11-bad" b.txt "bad"
O=$(LANE_TEST_FLUTTER=red out "$E/away" gate bad)
has "a red gate refuses" "$O" "[exit 1]"
check "and stamps nothing" "$(stamp "$E/away" surface11/bad)" none
O=$(LANE_TEST_FLUTTER=commit out "$E/away" gate bad)
has "a commit made while the gates ran is refused (refusal 7)" "$O" "got a commit while its gates ran"
has "and says which command to run again" "$O" "Run gate again"
check "and stamps nothing" "$(stamp "$E/away" surface11/bad)" none
O=$(LANE_TEST_FLUTTER=edit out "$E/away" gate bad)
has "an edit made while the gates ran is refused (refusal 7)" "$O" "was edited while its gates ran"
check "and stamps nothing" "$(stamp "$E/away" surface11/bad)" none
git -C "$AW/lane-surface11-bad" checkout -q -- . 2>/dev/null
echo dirty > "$AW/lane-surface11-bad/b.txt"
O=$(out "$E/away" gate bad)
has "a lane with uncommitted changes is not gated at all" "$O" "uncommitted changes in the lane"
quiet "$E/away" drop bad

say "C the trunk moves; send no longer asks the lane to sit on top of it, and carries the stamp"
quiet "$E/home" open own; commit "$HW/lane-own" c.txt "own work"; quiet "$E/home" land own
O=$(out "$E/away" send fix)
has "send goes through though the trunk moved" "$O" "sent work/surface11/fix"
has "and says the lane was gated here" "$O" "gated here at that commit"
has "the offer is on the mirror" "$(mirror_heads)" "sent/surface11/fix"
has "and its stamp beside it" "$(mirror_heads)" "gated/surface11/fix"
check "the mirror's stamp names the offered commit" "$(git -C "$E/mirror.git" rev-parse gated/surface11/fix)" "$HEAD_FIX"

say "D home: the trunk moved since the lane was gated — rebased and measured ONCE, as before"
quiet "$E/home" receive surface11/fix
check "receive brings the stamp" "$(stamp "$E/home" surface11/fix)" "$HEAD_FIX"
N=$(gates_run); O=$(out "$E/home" land surface11/fix)
has "it lands" "$O" "merged work/surface11/fix"
lacks "and does not claim it was already measured" "$O" "not measured again"
check "the gates ran once here" "$(( $(gates_run) - N ))" 2
lacks "the offer left the mirror" "$(mirror_heads)" "sent/surface11/fix"
lacks "and its stamp" "$(mirror_heads)" "gated/surface11/fix"
check "and the stamp left this machine" "$(stamp "$E/home" surface11/fix)" none
quiet "$E/away" sync

say "E home: a lane gated on its very commit, on a trunk that has not moved, lands UNMEASURED AGAIN"
quiet "$E/away" open two; commit "$AW/lane-surface11-two" d.txt "two"
quiet "$E/away" gate two; quiet "$E/away" send two
TWO=$(git -C "$AW/lane-surface11-two" rev-parse HEAD)
quiet "$E/home" receive surface11/two
N=$(gates_run); BEFORE=$(git -C "$E/home" rev-parse master)
O=$(out "$E/home" land surface11/two)
has "it says so" "$O" "not measured again"
has "and lands" "$O" "merged work/surface11/two"
check "no gate ran here" "$(( $(gates_run) - N ))" 0
check "master is the lane's commit itself — nothing was rebased" "$(git -C "$E/home" rev-parse master)" "$TWO"
check "the file is on master" "$(cat "$E/home/d.txt" 2>/dev/null)" "two"
quiet "$E/away" sync

say "F a stamp of an EARLIER commit vouches for nothing: it does not travel, and the gates run"
quiet "$E/away" open three; commit "$AW/lane-surface11-three" e.txt "three"
quiet "$E/away" gate three; quiet "$E/away" send three
has "the first offer carried its stamp" "$(mirror_heads)" "gated/surface11/three"
commit "$AW/lane-surface11-three" f.txt "one more commit after the gate"
O=$(out "$E/away" send three)
has "send says the lane is not gated" "$O" "not gated here"
lacks "the stale stamp left the mirror" "$(mirror_heads)" "gated/surface11/three"
quiet "$E/home" receive surface11/three
check "nothing vouches for it at home" "$(stamp "$E/home" surface11/three)" none
N=$(gates_run); O=$(out "$E/home" land surface11/three)
has "it lands" "$O" "merged work/surface11/three"
check "behind the gates, run here" "$(( $(gates_run) - N ))" 2
quiet "$E/away" sync

say "G a stamp left at home under a name does not vouch for a later lane of that name"
quiet "$E/away" open four; commit "$AW/lane-surface11-four" g.txt "four"; quiet "$E/away" send four
git -C "$E/home" update-ref refs/lane-gated/surface11/four "$(git -C "$E/home" rev-parse master)"
quiet "$E/home" receive surface11/four
check "receive clears what was there" "$(stamp "$E/home" surface11/four)" none
# …and one FORGED for the right commit by hand is believed: the stamp is the
# tool's word, and nothing here can tell a hand from the tool. Said, not hidden.
N=$(gates_run); O=$(out "$E/home" land surface11/four)
check "an unstamped lane is measured" "$(( $(gates_run) - N ))" 2
quiet "$E/away" sync

say "H unsend takes the stamp off the mirror with the offer; drop forgets the stamp"
quiet "$E/away" open five; commit "$AW/lane-surface11-five" h.txt "five"
quiet "$E/away" gate five; quiet "$E/away" send five
has "offered with its stamp" "$(mirror_heads)" "gated/surface11/five"
quiet "$E/away" unsend five
lacks "the offer is gone" "$(mirror_heads)" "sent/surface11/five"
lacks "and so is its stamp" "$(mirror_heads)" "gated/surface11/five"
check "the away machine keeps its own stamp" "$(stamp "$E/away" surface11/five)" "$(git -C "$AW/lane-surface11-five" rev-parse HEAD)"
quiet "$E/away" drop five
check "until the lane is dropped" "$(stamp "$E/away" surface11/five)" none

say "I home: a lane of its own, gated and then landed on an unmoved trunk, is not measured twice either"
quiet "$E/home" open six; commit "$HW/lane-six" i.txt "six"
quiet "$E/home" gate six
N=$(gates_run); O=$(out "$E/home" land six)
has "it says so" "$O" "not measured again"
check "no gate ran" "$(( $(gates_run) - N ))" 0
check "the stamp is gone with the lane" "$(stamp "$E/home" six)" none

say "J ONE LAND AT A TIME: two lands started together both land — the second waits, then rebases onto the first"
quiet "$E/home" open p; commit "$HW/lane-p" p.txt "p"
quiet "$E/home" open q; commit "$HW/lane-q" q.txt "q"
( LANE_TEST_FLUTTER=slow out "$E/home" land p > "$E/land_p.txt" ) &
sleep 1
( LANE_TEST_FLUTTER=slow out "$E/home" land q > "$E/land_q.txt" ) &
wait
P=$(cat "$E/land_p.txt"); Q=$(cat "$E/land_q.txt")
has "p landed" "$P" "merged work/p"
has "q landed" "$Q" "merged work/q"
has "q waited for its turn" "$Q" "another lane is landing"
lacks "nobody's fast-forward was refused" "$P$Q" "fast-forward refused"
check "master holds both" "$(ls "$E/home/p.txt" "$E/home/q.txt" 2>/dev/null | wc -l | tr -d ' ')" 2
check "the turn was given back" "$(ls -d "$E/home/.git/lane-land.turn" 2>/dev/null | wc -l | tr -d ' ')" 0

say "K a lander that was killed left its turn behind: the next land takes it over"
mkdir -p "$E/home/.git/lane-land.turn"; echo 999999 > "$E/home/.git/lane-land.turn/pid"
quiet "$E/home" open r; commit "$HW/lane-r" r.txt "r"
O=$(out "$E/home" land r)
has "it lands" "$O" "merged work/r"
check "and gives the turn back" "$(ls -d "$E/home/.git/lane-land.turn" 2>/dev/null | wc -l | tr -d ' ')" 0

say "L a land that is refused gives its turn back too"
quiet "$E/home" open s; commit "$HW/lane-s" s.txt "s"
O=$(LANE_TEST_FLUTTER=red out "$E/home" land s)
has "the red gate refuses the land" "$O" "analyze is not clean"
check "and the turn is free" "$(ls -d "$E/home/.git/lane-land.turn" 2>/dev/null | wc -l | tr -d ' ')" 0

say "M a LAND asks again too: a lane that moved under its gates is not merged"
quiet "$E/home" open t; commit "$HW/lane-t" t.txt "t"
BEFORE=$(git -C "$E/home" rev-parse master)
O=$(LANE_TEST_FLUTTER=commit out "$E/home" land t)
has "a commit made while the gates ran is refused (refusal 7)" "$O" "got a commit while its gates ran"
has "and says which command to run again" "$O" "Run land again"
check "master did not move" "$(git -C "$E/home" rev-parse master)" "$BEFORE"
O=$(LANE_TEST_FLUTTER=edit out "$E/home" land t)
has "an edit made while the gates ran is refused (refusal 7)" "$O" "was edited while its gates ran"
check "master did not move" "$(git -C "$E/home" rev-parse master)" "$BEFORE"
check "and the turn is free" "$(ls -d "$E/home/.git/lane-land.turn" 2>/dev/null | wc -l | tr -d ' ')" 0
git -C "$HW/lane-t" checkout -q -- . 2>/dev/null
O=$(out "$E/home" land t)
has "the lane lands once it is still" "$O" "merged work/t"

say "N away: a lane that landed is NOT let go while its worktree holds work nobody committed"
quiet "$E/away" sync
quiet "$E/away" open keep; commit "$AW/lane-surface11-keep" k.txt "keep"
quiet "$E/away" send keep
echo "typed after the send, never committed" > "$AW/lane-surface11-keep/draft.txt"
quiet "$E/home" receive surface11/keep; quiet "$E/home" land surface11/keep
O=$(out "$E/away" sync)
has "sync says the lane is kept, and why" "$O" "holds changes nobody committed"
has "and names what it holds" "$O" "draft.txt"
check "the lane is still there" "$(git -C "$E/away" branch --list 'work/surface11/keep' --format='%(refname:short)')" "work/surface11/keep"
check "and so is the uncommitted file" "$(cat "$AW/lane-surface11-keep/draft.txt" 2>/dev/null)" "typed after the send, never committed"
O=$(out "$E/away" open another)
check "another lane opened on that machine does not take it either" "$(cat "$AW/lane-surface11-keep/draft.txt" 2>/dev/null)" "typed after the send, never committed"
rm -f "$AW/lane-surface11-keep/draft.txt"
O=$(out "$E/away" sync)
has "once the worktree is clean the lane is let go" "$O" "keep landed — letting go"
check "and it is gone" "$(git -C "$E/away" branch --list 'work/surface11/keep' | wc -l | tr -d ' ')" 0

say "O ROOM FIRST: the gates ask the machine before they launch — a gate for a place, a land for the headroom alone"
asks() { grep -c " dart flutter_room.dart" "$LANE_TEST_LOG"; }
quiet "$E/home" open u; commit "$HW/lane-u" u.txt "u"
: > "$LANE_TEST_LOG"
quiet "$E/home" gate u
check "a gate asks for a place, before anything runs" "$(head -n 1 "$LANE_TEST_LOG")" "home dart flutter_room.dart"
commit "$HW/lane-u" u2.txt "u again"
: > "$LANE_TEST_LOG"
O=$(out "$E/home" land u)
check "a land asks for the headroom alone, before anything runs" "$(head -n 1 "$LANE_TEST_LOG")" "home dart flutter_room.dart --land"
has "and lands" "$O" "merged work/u"
quiet "$E/home" open v; commit "$HW/lane-v" v.txt "v"
quiet "$E/home" gate v
: > "$LANE_TEST_LOG"
quiet "$E/home" land v
check "a land that is not measured again asks nothing" "$(asks)" 0

say "P no room: the gates wait and launch nothing — and an instrument that cannot measure launches nothing either"
quiet "$E/home" open w; commit "$HW/lane-w" w.txt "w"
: > "$LANE_TEST_LOG"; rmdir "$LANE_TEST_LOG.asked" 2>/dev/null
O=$(LANE_TEST_ROOM=full out "$E/home" land w)
has "it says it is waiting" "$O" "no room for the gates yet"
has "and what it saw" "$O" "runs=4 free_gb=9 room=no"
check "it asked twice" "$(asks)" 2
check "and nothing ran between the two answers" "$(sed -n 2p "$LANE_TEST_LOG")" "home dart flutter_room.dart --land"
has "then it lands" "$O" "merged work/w"
quiet "$E/home" open x; commit "$HW/lane-x" x.txt "x"
BEFORE=$(git -C "$E/home" rev-parse master); N=$(gates_run)
O=$(LANE_TEST_ROOM=blind out "$E/home" land x)
has "a room that cannot be measured refuses the land" "$O" "could not be measured"
check "no gate ran" "$(( $(gates_run) - N ))" 0
check "master did not move" "$(git -C "$E/home" rev-parse master)" "$BEFORE"
check "the lane is kept" "$(git -C "$E/home" branch --list work/x --format='%(refname:short)')" "work/x"
check "and the turn is free" "$(ls -d "$E/home/.git/lane-land.turn" 2>/dev/null | wc -l | tr -d ' ')" 0

say "Q AT IDLE: what the gates launch runs in the lowest class"
if command -v powershell.exe >/dev/null 2>&1; then
  rm -f "$LANE_TEST_LOG.priority"
  O=$(LANE_TEST_PRIORITY=1 out "$E/home" land x)
  has "the lane lands" "$O" "merged work/x"
  check "and every gate ran at Idle" "$(sort -u "$LANE_TEST_LOG.priority" 2>/dev/null | tr '\n' ' ')" "Idle "
else
  echo "  (not Windows: nothing is lowered here)"
fi

say "R a backup that cannot reach the mirror SAYS so and fails — and a land whose copy fails has still landed"
git -C "$E/home" remote set-url backup "$E/nowhere.git"
O=$(out "$E/home" backup)
has "the trunk's push says it failed" "$O" "THE MIRROR PUSH FAILED"
lacks "and nothing is called mirrored" "$O" "lane: mirrored"
has "the command fails" "$O" "[exit 1]"
quiet "$E/home" open y; commit "$HW/lane-y" y.txt "y"
O=$(out "$E/home" land y)
has "a land still lands" "$O" "merged work/y"
has "and says its copy is missing" "$O" "THE MIRROR PUSH FAILED"
has "with a land's own exit" "$O" "[exit 0]"
git -C "$E/away" remote set-url backup "$E/nowhere.git"
quiet "$E/away" open z 2>/dev/null; commit "$AW/lane-surface11-z" z.txt "z"
O=$(out "$E/away" backup)
lacks "an away backup that cannot reach it calls nothing mirrored either" "$O" "lane: mirrored"
has "and fails" "$O" "[exit 1]"
git -C "$E/home" remote set-url backup "$E/mirror.git"
git -C "$E/away" remote set-url backup "$E/mirror.git"
O=$(out "$E/home" backup)
has "with the mirror back, a backup says what it copied" "$O" "lane: mirrored master and"
has "and succeeds" "$O" "[exit 0]"
check "the mirror has the trunk" "$(git -C "$E/mirror.git" rev-parse master)" "$(git -C "$E/home" rev-parse master)"
O=$(out "$E/away" backup)
has "and so does the away machine's, of its own lanes" "$O" "lane: mirrored"
has "which succeeds" "$O" "[exit 0]"

echo
echo "== $FAILS failed"
exit "$FAILS"
