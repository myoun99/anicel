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
# 🆕And together (2026-10-18, tests-crowd-the-machine-Q2 — section S): the
# architecture tests start while analyze still runs, and a red gate is shown
# from the output it left, not run a second time to print it.
#
# 🆕And refusal 8 (2026-11-05, gpu-engine-skeleton — section T, 117 checks
# in all): a lane pays for the crate it changed itself, not for crate
# commits the trunk took after it was opened; and a lane stamped on another
# machine still runs the crate's tests on this one before it merges.
# ⚠️The script before THAT fails 4 of the 11 there: it refuses the Dart
# lane, and lands a ledger row this machine's GPU never ran. 🆕Since
# native-to-rust (2026-11-06) it also holds that a crate lane is refused,
# before any crate test, when its engine — the native crates' answer key —
# is not built from its C; and that a lane that changed only the C runs
# the crates' tests too, held to it. And a run that passed no test is
# refused, though it exits 0.
#
# 🆕And the mirror's login (2026-11-05, gpu-engine-skeleton — section U,
# 119 checks in all): a `git` in front of the real one writes down every
# call of the whole run that reached the mirror, and none of them could ask
# for a login. ⚠️The script before THAT fails 1 of the 2 there: its backup
# pushed master, and its sync fetched it, free to ask.
#
# 🆕And offline (2026-11-06, native-memory-safety — section T's last case
# and section V, 135 checks in all): a crate lane whose lock names a crate
# this machine has not downloaded is refused, naming that crate and the
# command that would download it, and no gate of the whole run downloaded
# one. ⚠️The script before THAT fails 5 of the 7 there: it downloads the
# crate, and lands.
# ↩️And the turn every cargo takes (tool/cargo_turn.sh) is copied into the
# scratch trunk: since the gates took it (948f1c65d) every crate run here
# was red for want of it, the script under test and the one before alike.
# 🆕And pub the same (section V, 149 checks in all): a lane resolves
# offline, its gates run with --no-pub, and a package its locks name that
# this machine has not downloaded refuses the land — and the open, as no
# refusal of the gates'. A `flutter` that writes down every call that could
# download finds none in the whole run. ⚠️The script before THAT fails 10 of
# the 15 there: it resolves online, and lands.
# 🆕And this platform's crates (2026-11-07, native-memory-safety — section
# T's last case, 151 checks in all): of the crates not downloaded, refusal 8
# names those this machine's build takes — for its cfg, for its triple,
# through a member's manifest and through a crate's index entry — and none
# for another platform, and offers to fetch this platform's alone; the
# list is the real tool's (crates_for_host.dart), behind the stand-in
# `dart`. ⚠️The script before THAT fails 5 of the 8 there: it names every
# platform's, and offers to fetch them all.
# 🆕And one red hides nothing (same day, gpu-engine-skeleton — section T,
# 153 checks in all): the crates' tests run past a red crate, release runs
# after a red debug, and the refusal names both. ⚠️The script before THAT
# fails both: it stops at debug's red.
# 🆕And where it looked (same day — sections T and V, 155 checks in all): a
# refusal to download names the cargo home or the pub cache it read. ⚠️The
# script before THAT fails both: it names what is missing, not from where.
# 🆕And a link (2026-11-08, the-hook-folder-lost-an-android-dep-file —
# section X, 171 checks in all): a lane holding a link to a folder outside
# it is dropped and landed with the folder's files kept. ⚠️The script
# before THAT fails 2 of the 5 there: on Windows its `git worktree remove`
# empties the folder through the junction.
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
# A `pub get` not offline, and an analyze or a test that runs one itself,
# could download: each is written down where no section clears it. When
# LANE_TEST_FLUTTER says absent, a package of the app is not in the cache,
# and an offline `pub get` of the app fails as pub does; absent_package, of
# a package the app does not depend on; absent_trunk, of that one in the
# trunk alone.
case " $* " in
  *" pub get "*) case " $* " in
      *" --offline "*)
        where=app; case " $* " in *" --directory "*) where=package ;; esac
        case "${LANE_TEST_FLUTTER:-ok}:$where:$(basename "$PWD")" in
          absent:app:*|absent_package:package:*|absent_trunk:package:home)
            echo "Because app depends on args any which doesn't exist (could not find package args in cache), version solving failed."
            exit 69 ;;
        esac ;;
      *) echo "could download: flutter $*" >> "$LANE_TEST_LOG.downloads" ;;
    esac ;;
  *" --no-pub "*) ;;
  " analyze "*|" test "*) echo "could download: flutter $*" >> "$LANE_TEST_LOG.downloads" ;;
esac
case "${LANE_TEST_FLUTTER:-ok}" in
  slow) [ "$1" = analyze ] && sleep 5 ;;
  red) [ "$1" = analyze ] && exit 1 ;;
  edit) [ "$1" = analyze ] && echo edited >> a.txt ;;
  commit) [ "$1" = analyze ] && { echo x >> during.txt; git add during.txt; git commit -q -m "during the gates"; } ;;
  together) [ "$1" = analyze ] && { sleep 3; echo "$(basename "$PWD") analyze done" >> "$LANE_TEST_LOG"; } ;;
  red_arch) [ "$1" = test ] && { echo "[E] the red one"; exit 1; } ;;
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
# Asked whether an engine is built from its C, it says no when
# LANE_TEST_ENGINE says stale.
[ "$(basename "$1")" = native_engine_provenance.dart ] && [ "${LANE_TEST_ENGINE:-}" = stale ] \
  && { echo "0000 not built from its C"; exit 1; }
# Asked which crates a build takes, it is the real tool: its list is what
# refusal 8 is checked for.
[ "$(basename "$1")" = crates_for_host.dart ] && exec "$LANE_TEST_DART" "$@"
[ "$(basename "$1")" = flutter_room.dart ] || exit 0
case "${LANE_TEST_ROOM:-ok}" in
  full) mkdir "$LANE_TEST_LOG.asked" 2>/dev/null && { echo "runs=4 free_gb=9 room=no"; exit 1; } ;;
  blind) echo "flutter_room: this machine could not be measured" >&2; exit 2 ;;
esac
echo "runs=0 free_gb=9 room=yes"
exit 0
EOF
# `cargo` writes down which lane it ran in — the crate is three folders
# down — and fails when LANE_TEST_CARGO says red. Green, it answers as a
# workspace of two crates does: two tests, then a doc-test run of none —
# or, when LANE_TEST_CARGO says empty, the doc-tests alone. When it says
# absent, a crate is not downloaded: offline it fails as cargo does, and
# online it downloads — which it writes down where no section clears it.
# When it says nowasm, the machine lacks the WebAssembly target: that
# build fails as cargo does there, and the tests still pass.
cat > "$E/bin/cargo" <<'EOF'
#!/bin/bash
echo "$(basename "$(dirname "$(dirname "$(dirname "$PWD")")")") cargo $*" >> "$LANE_TEST_LOG"
# Asked for the members' manifests, it answers as the absent lane's
# workspace would: one member, one of its dependencies for Android and one
# for Windows.
if [ "$1" = metadata ]; then
  printf '%s\n' '{"packages":[{"name":"gpu_engine","version":"0.1.0","dependencies":[' \
    '{"name":"cpal","kind":null,"target":null},{"name":"have","kind":null,"target":null},' \
    '{"name":"android-only","kind":null,"target":"cfg(target_os = \"android\")"},' \
    '{"name":"windows-only","kind":null,"target":"cfg(windows)"}]}]}'
  exit 0
fi
if [ "${LANE_TEST_CARGO:-ok}" = absent ]; then
  case " $* " in
    *" --offline "*|*" --frozen "*)
      printf 'error: failed to download `cpal v0.18.2`\n\nCaused by:\n'
      echo "  attempting to make an HTTP request, but --offline was specified"
      exit 101 ;;
    *) echo "downloaded cpal v0.18.2: cargo $*" >> "$LANE_TEST_LOG.downloads" ;;
  esac
fi
if [ "${LANE_TEST_CARGO:-ok}" = nowasm ] && [ "$1" = build ]; then
  echo "error[E0463]: can't find crate for \`core\`"
  echo "  = note: the \`wasm32-unknown-unknown\` target may not be installed"
  exit 101
fi
[ "${LANE_TEST_CARGO:-ok}" = red ] && { echo "test grid ... FAILED"; exit 101; }
[ "${LANE_TEST_CARGO:-ok}" = empty ] || echo "test result: ok. 2 passed; 0 failed"
echo "test result: ok. 0 passed; 0 failed"
EOF
# `cmake` and `ctest`, for a lane that changed the C (refusal 5): the
# engine builds — red when LANE_TEST_ENGINE says stale, so a stale engine
# stays stale — and the C tests pass.
cat > "$E/bin/cmake" <<'EOF'
#!/bin/bash
echo "$(basename "$PWD") cmake $*" >> "$LANE_TEST_LOG"
[ "${LANE_TEST_ENGINE:-}" = stale ] && exit 1
exit 0
EOF
printf '#!/bin/bash\nexit 0\n' > "$E/bin/ctest"
# `rustc` answers for a machine of its own: its host, and its cfg.
cat > "$E/bin/rustc" <<'EOF'
#!/bin/bash
case "$*" in
  -vV) printf 'rustc 1.0.0\nhost: x86_64-lane-test\n' ;;
  "--print cfg") printf 'target_os="windows"\nwindows\n' ;;
  *) exit 1 ;;
esac
EOF
# `git` writes down every call that reaches the mirror (the remote named
# backup) and whether it was let ask for a login, then hands every call,
# that one too, to the real git.
REAL_GIT="$(command -v git)"
cat > "$E/bin/git" <<EOF
#!/bin/bash
case " \$* " in *" backup "*)
  case " \$* " in *" push "*|*" fetch "*|*" ls-remote "*)
    echo "\$* prompt=\${GIT_TERMINAL_PROMPT:-} gcm=\${GCM_INTERACTIVE:-}" >> "\$LANE_TEST_LOG.mirror" ;;
  esac ;;
esac
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$E/bin/flutter" "$E/bin/dart" "$E/bin/cargo" "$E/bin/cmake" "$E/bin/ctest" "$E/bin/git" \
  "$E/bin/rustc"
# The SDK's own dart, past its launcher, as tool/run.sh calls it: the
# launcher, with these stand-ins first on PATH, cannot tell its engine's
# version and runs nothing.
REAL_FLUTTER="$(command -v flutter)"
for LANE_TEST_DART in "${REAL_FLUTTER%/*}/cache/dart-sdk/bin/dart.exe" \
  "${REAL_FLUTTER%/*}/cache/dart-sdk/bin/dart" "$(command -v dart)"; do
  [ -x "$LANE_TEST_DART" ] && break
done
export LANE_TEST_DART
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
gates_run() { grep -c "flutter analyze\|flutter test.* test/architecture" "$LANE_TEST_LOG"; }
mirror_heads() { git -C "$E/mirror.git" for-each-ref --format='%(refname:short)' refs/heads | tr '\n' ' '; }
commit() { echo "$3" > "$1/$2"; git -C "$1" add "$2" 2>/dev/null; git -C "$1" commit -q -m "$3" 2>/dev/null; }
stamp() { git -C "$1" rev-parse -q --verify "refs/lane-gated/$2" 2>/dev/null || echo none; }
AW="$E/away/.claude/worktrees"; HW="$E/home/.claude/worktrees"

git init -q --bare "$E/mirror.git"
git init -q -b master "$E/home" 2>/dev/null
mkdir -p "$E/home/tool"; cp "$SCRIPT" "$E/home/tool/lane.sh"; echo one > "$E/home/a.txt"
# The launcher the gates ask the room through, and the stamp law it reads.
# No tool sources beside them, so it hands every call to the stand-in `dart`.
# And the turn every cargo building in the shared target takes, and what
# works out the crates a build takes, with the bracket reading it cuts a
# cfg by.
cp "$(dirname "${BASH_SOURCE[0]}")/run.sh" "$(dirname "${BASH_SOURCE[0]}")/exe_stamp.sh" \
  "$(dirname "${BASH_SOURCE[0]}")/cargo_turn.sh" "$(dirname "${BASH_SOURCE[0]}")/crates_for_host.dart" \
  "$(dirname "${BASH_SOURCE[0]}")/source_brackets.dart" "$E/home/tool/"
# And the parity selector the gate of a lane that changed the C asks.
printf '#!/bin/bash\necho test/parity_test.dart\n' > "$E/home/tool/native_parity_tests.sh"
# And the packages the app does not depend on, with one to resolve.
cp "$(dirname "${BASH_SOURCE[0]}")/resolve_packages.sh" "$E/home/tool/"
mkdir -p "$E/home/packages/gpu_engine"; echo "name: gpu_engine" > "$E/home/packages/gpu_engine/pubspec.yaml"
printf '.claude/\nbuild/\n' > "$E/home/.gitignore"
git -C "$E/home" add -f tool/lane.sh tool/run.sh tool/exe_stamp.sh tool/cargo_turn.sh tool/native_parity_tests.sh \
  tool/crates_for_host.dart tool/source_brackets.dart tool/resolve_packages.sh \
  packages/gpu_engine/pubspec.yaml a.txt .gitignore 2>/dev/null
git -C "$E/home" commit -q -m first
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

say "S TOGETHER: analyze and the architecture tests run side by side — and a red one is shown from what it left"
quiet "$E/home" open tg; commit "$HW/lane-tg" tg.txt "tg"
: > "$LANE_TEST_LOG"
O=$(LANE_TEST_FLUTTER=together out "$E/home" land tg)
has "it lands" "$O" "merged work/tg"
check "the architecture tests start while analyze still runs" \
  "$(grep -m1 -o 'test/architecture\|analyze done' "$LANE_TEST_LOG")" "test/architecture"
quiet "$E/home" open tr; commit "$HW/lane-tr" tr.txt "tr"
: > "$LANE_TEST_LOG"
O=$(LANE_TEST_FLUTTER=red out "$E/home" land tr)
has "a red analyze refuses the land" "$O" "analyze is not clean"
check "and analyze ran once" "$(grep -c 'flutter analyze' "$LANE_TEST_LOG")" 1
quiet "$E/home" open ta; commit "$HW/lane-ta" ta.txt "ta"
: > "$LANE_TEST_LOG"
O=$(LANE_TEST_FLUTTER=red_arch out "$E/home" land ta)
has "a red architecture test refuses the land" "$O" "the architecture gate is red"
has "and shows what failed" "$O" "[E] the red one"
check "and the architecture tests ran once" "$(grep -c 'flutter test.* test/architecture' "$LANE_TEST_LOG")" 1

say "T REFUSAL 8: a lane pays for the crate IT changed — and a stamp made elsewhere does not answer for this machine's GPU"
cargo_runs() { grep -c "$1 cargo test" "$LANE_TEST_LOG"; }
quiet "$E/home" open dart4; commit "$HW/lane-dart4" d.txt "four Dart files"
quiet "$E/home" open kern; mkdir -p "$HW/lane-kern/packages/gpu_engine/rust"
commit "$HW/lane-kern" packages/gpu_engine/rust/k.wgsl "a kernel"
: > "$LANE_TEST_LOG"
O=$(out "$E/home" land kern)
has "a lane that changed the crate lands" "$O" "merged work/kern"
check "and its tests ran, debug and release" "$(cargo_runs lane-kern)" 2
check "after the fx SDK example was built once as WebAssembly" \
  "$(grep -c 'lane-kern cargo build .*-p fx_sdk_example --target wasm32-unknown-unknown' "$LANE_TEST_LOG")" 1
check "before them" \
  "$(grep -m1 -o 'lane-kern cargo build\|lane-kern cargo test' "$LANE_TEST_LOG")" "lane-kern cargo build"
check "in the lane's own target folder for it, where the tests read it" \
  "$(grep -c 'lane-kern cargo build .* --target-dir .*/lane-kern/build/fx_wasm$' "$LANE_TEST_LOG")" 1
has "and each says what passed in all the crates, debug" "$O" "debug green (2 passed)"
has "and release, its own run alone" "$O" "release green (2 passed)"
: > "$LANE_TEST_LOG"
O=$(out "$E/home" gate dart4)
has "a lane opened before the trunk took the crate is gated" "$O" "gated work/dart4"
check "and the trunk's crate is not taken for its own" "$(cargo_runs lane-dart4)" 0
quiet "$E/home" open sdkfx; mkdir -p "$HW/lane-sdkfx/sdk/fx"
commit "$HW/lane-sdkfx" sdk/fx/s.rs "the fx SDK's source alone"
: > "$LANE_TEST_LOG"
O=$(out "$E/home" land sdkfx)
has "a lane that changed the fx SDK alone lands" "$O" "merged work/sdkfx"
check "and pays for the crate it feeds, debug and release" "$(cargo_runs lane-sdkfx)" 2
quiet "$E/home" open nowasm; mkdir -p "$HW/lane-nowasm/sdk/fx"
commit "$HW/lane-nowasm" sdk/fx/w.rs "the fx SDK on a machine without the target"
: > "$LANE_TEST_LOG"
O=$(LANE_TEST_CARGO=nowasm out "$E/home" land nowasm)
has "a red WebAssembly build is no refusal of its own: the tests that open the module refuse" \
  "$O" "merged work/nowasm"
has "and it says so" "$O" "that build is red; the fx tests that open it say so"
has "in cargo's words" "$O" "target may not be installed"
check "the tests ran past it, debug and release" "$(cargo_runs lane-nowasm)" 2
quiet "$E/away" sync
quiet "$E/away" open line; mkdir -p "$AW/lane-surface11-line/test/fixtures"
commit "$AW/lane-surface11-line" test/fixtures/fingerprints.json "a row pinned there"
quiet "$E/away" gate line; quiet "$E/away" send line
quiet "$E/home" receive surface11/line
: > "$LANE_TEST_LOG"
O=$(out "$E/home" land surface11/line)
has "a stamped lane on an unmoved trunk is not measured again" "$O" "not measured again"
check "no gate ran" "$(gates_run)" 0
check "but the crate's tests ran here, debug and release" "$(cargo_runs lane-surface11-line)" 2
has "and it lands" "$O" "merged work/surface11/line"
quiet "$E/away" sync
quiet "$E/away" open row; mkdir -p "$AW/lane-surface11-row/test/fixtures"
commit "$AW/lane-surface11-row" test/fixtures/fingerprints.json "a row this GPU disagrees with"
quiet "$E/away" gate row; quiet "$E/away" send row
quiet "$E/home" receive surface11/row
BEFORE=$(git -C "$E/home" rev-parse master)
: > "$LANE_TEST_LOG"
O=$(LANE_TEST_CARGO=red out "$E/home" land surface11/row)
has "a row this machine's GPU disagrees with refuses the stamped land" "$O" "this is refusal 8"
check "every crate ran past a red one, and release after a red debug" \
  "$(grep -c 'lane-surface11-row cargo test .*--no-fail-fast' "$LANE_TEST_LOG")" 2
has "and the refusal names both" "$O" "tests are red in debug release — this is refusal 8"
check "master did not move" "$(git -C "$E/home" rev-parse master)" "$BEFORE"
check "and the turn is free" "$(ls -d "$E/home/.git/lane-land.turn" 2>/dev/null | wc -l | tr -d ' ')" 0
quiet "$E/home" open stale; mkdir -p "$HW/lane-stale/packages/gpu_engine/rust"
commit "$HW/lane-stale" packages/gpu_engine/rust/s.wgsl "a kernel beside an engine of other C"
: > "$LANE_TEST_LOG"; BEFORE=$(git -C "$E/home" rev-parse master)
O=$(LANE_TEST_ENGINE=stale out "$E/home" land stale)
has "a crate lane whose engine is not built from its C is refused — the native crates' answer key" \
  "$O" "not built from this lane's C — this is refusal 8"
check "before a crate test ran" "$(cargo_runs lane-stale)" 0
check "master did not move" "$(git -C "$E/home" rev-parse master)" "$BEFORE"
mkdir -p "$E/home/build/native_standalone"  # the trunk's engine, which `open` copies
quiet "$E/home" open cfile; mkdir -p "$HW/lane-cfile/packages/qa_native/src"
commit "$HW/lane-cfile" packages/qa_native/src/c.c "C that a module's Rust is held to"
: > "$LANE_TEST_LOG"
O=$(out "$E/home" land cfile)
has "a lane that changed only the C lands" "$O" "merged work/cfile"
check "and the crates were held to it, debug and release" "$(cargo_runs lane-cfile)" 2
quiet "$E/home" open none; mkdir -p "$HW/lane-none/packages/gpu_engine/rust"
commit "$HW/lane-none" packages/gpu_engine/rust/n.wgsl "a kernel whose crate ran no test"
: > "$LANE_TEST_LOG"; BEFORE=$(git -C "$E/home" rev-parse master)
O=$(LANE_TEST_CARGO=empty out "$E/home" land none)
has "a crate run that passed no test is refused, though it exits 0" \
  "$O" "ran no test in debug — this is refusal 8"
check "master did not move" "$(git -C "$E/home" rev-parse master)" "$BEFORE"
# A lock of seven crates from the registry and the workspace's own, and a
# machine that downloaded one of them. Of the six not here, four are built
# for this machine's platform — cpal; windows-only, which the member
# declares for Windows; dasp_sample through cpal's index entry, and
# host-only, which that entry declares for this machine's triple — and two
# for others': android-only, which the member declares for Android, and
# alsa, which cpal's index entry declares for Linux.
quiet "$E/home" open absent; mkdir -p "$HW/lane-absent/packages/gpu_engine/rust"
REGISTRY='source = "registry+https://github.com/rust-lang/crates.io-index"'
printf '%s\n' '[[package]]' 'name = "alsa"' 'version = "0.11.0"' "$REGISTRY" '' \
  '[[package]]' 'name = "android-only"' 'version = "1.0.0"' "$REGISTRY" '' \
  '[[package]]' 'name = "cpal"' 'version = "0.18.2"' "$REGISTRY" \
  'dependencies = [' ' "alsa",' ' "dasp_sample",' ' "host-only",' ']' '' \
  '[[package]]' 'name = "dasp_sample"' 'version = "0.11.0"' "$REGISTRY" '' \
  '[[package]]' 'name = "gpu_engine"' 'version = "0.1.0"' \
  'dependencies = [' ' "android-only",' ' "cpal",' ' "have",' ' "windows-only",' ']' '' \
  '[[package]]' 'name = "have"' 'version = "1.0.0"' "$REGISTRY" '' \
  '[[package]]' 'name = "host-only"' 'version = "1.0.0"' "$REGISTRY" '' \
  '[[package]]' 'name = "windows-only"' 'version = "1.0.0"' "$REGISTRY" \
  > "$HW/lane-absent/packages/gpu_engine/rust/Cargo.lock"
git -C "$HW/lane-absent" add packages/gpu_engine/rust/Cargo.lock
git -C "$HW/lane-absent" commit -q -m "a crate this machine has not downloaded"
mkdir -p "$E/cargo-home/registry/cache/index.crates.io-0"
: > "$E/cargo-home/registry/cache/index.crates.io-0/have-1.0.0.crate"
# The index entries cargo resolved them from, as its cache keeps them: a
# header, then a version and its JSON, each ended by a zero byte.
entry() {  # entry <folder under .cache> <name> <version> <deps JSON>
  mkdir -p "$E/cargo-home/registry/index/index.crates.io-0/.cache/$1"
  printf '\003\002\0\0\0etag\0%s\0%s\0' "$3" \
    "{\"name\":\"$2\",\"vers\":\"$3\",\"deps\":[$4],\"cksum\":\"0\",\"features\":{}}" \
    > "$E/cargo-home/registry/index/index.crates.io-0/.cache/$1/$2"
}
entry cp/al cpal 0.18.2 '{"name":"alsa","req":"^0.11","target":"cfg(target_os = \"linux\")","kind":"normal"},{"name":"dasp_sample","req":"^0.11","target":null,"kind":"normal"},{"name":"host-only","req":"^1","target":"x86_64-lane-test","kind":"normal"}'
entry da/sp dasp_sample 0.11.0 ''
entry ha/ve have 1.0.0 ''
BEFORE=$(git -C "$E/home" rev-parse master)
# Spelled as Windows spells it, where it can be: the main PC's is D:\rust\cargo.
HOME_SPELT="$(cygpath -w "$E/cargo-home" 2>/dev/null || echo "$E/cargo-home")"
O=$(CARGO_HOME="$HOME_SPELT" LANE_TEST_CARGO=absent out "$E/home" land absent)
has "a crate lane whose build takes a crate not downloaded here is refused" \
  "$O" "has not downloaded every crate its build takes — this is refusal 8"
has "and it names the crates this machine's build takes, for its cfg, its triple and through a crate" \
  "$O" "Not here: cpal-0.18.2 dasp_sample-0.11.0 host-only-1.0.0 windows-only-1.0.0 "
lacks "and not the one that is here" "$O" "have-1.0.0"
lacks "nor the workspace's own" "$O" "gpu_engine-0.1.0"
lacks "nor one a member takes for another platform" "$O" "android-only"
lacks "nor one a crate takes for another platform" "$O" "alsa"
has "and the command that would download this platform's alone" "$O" \
  "cargo fetch --locked --target x86_64-lane-test)"
has "and the cargo home it looked in" "$O" "Looked in: $HOME_SPELT/registry/cache "
check "master did not move" "$(git -C "$E/home" rev-parse master)" "$BEFORE"

say "U NOBODY IS ASKED FOR A LOGIN: every call that reached the mirror in this whole run"
check "LIVENESS — the run reached the mirror, on both machines, every way" \
  "$(grep -o ' \(push\|fetch\|ls-remote\) ' "$LANE_TEST_LOG.mirror" 2>/dev/null | sort -u | tr -d ' ' | tr '\n' ' ')" "fetch ls-remote push "
check "and not one call could ask" "$(grep -v 'prompt=0 gcm=Never$' "$LANE_TEST_LOG.mirror" | head -3 | tr '\n' ' ')" ""

say "V NOTHING IS DOWNLOADED: a lane resolves offline, and its gates run on what it resolved"
# A lock of two packages from pub and one from the SDK, and a machine whose
# pub cache has one of them.
quiet "$E/home" open pubs
printf '%s\n' 'packages:' '  args:' '    dependency: transitive' '    description:' \
  '      name: args' '      url: "https://pub.dev"' '    source: hosted' '    version: "2.5.0"' \
  '  flutter:' '    dependency: "direct main"' '    description: flutter' '    source: sdk' \
  '    version: "0.0.0"' '  have:' '    dependency: transitive' '    description:' \
  '      name: have' '      url: "https://pub.dev"' '    source: hosted' '    version: "1.0.0"' \
  'sdks:' '  dart: ">=3.5.0 <4.0.0"' > "$HW/lane-pubs/pubspec.lock"
git -C "$HW/lane-pubs" add pubspec.lock
git -C "$HW/lane-pubs" commit -q -m "a package this machine has not downloaded"
mkdir -p "$E/pub-cache/hosted/pub.dev/have-1.0.0"
: > "$LANE_TEST_LOG"; BEFORE=$(git -C "$E/home" rev-parse master)
O=$(PUB_CACHE="$E/pub-cache" LANE_TEST_FLUTTER=absent out "$E/home" land pubs)
has "a lane whose lock names a package not downloaded here is refused" \
  "$O" "has not downloaded every package the locks name — this is refusal 3"
has "and it names the package" "$O" "Not here: args-2.5.0 "
has "and the pub cache it looked in" "$O" "Looked in: $E/pub-cache/hosted "
lacks "and not the one that is here" "$O" "have-1.0.0"
lacks "nor the SDK's" "$O" "flutter-0.0.0"
has "and the command that would download it" "$O" "flutter pub get)"
check "before a gate ran" "$(gates_run)" 0
check "master did not move" "$(git -C "$E/home" rev-parse master)" "$BEFORE"
O=$(out "$E/home" land pubs)
has "with the package here, it lands" "$O" "merged work/pubs"
O=$(PUB_CACHE="$E/pub-cache" LANE_TEST_FLUTTER=absent out "$E/home" open pubs2)
has "and a lane cut from that trunk is refused too, naming it" "$O" "Not here: args-2.5.0 "
lacks "where opening a lane is no refusal of the gates'" "$O" "this is refusal"
O=$(PUB_CACHE="$E/pub-cache" LANE_TEST_FLUTTER=absent_package out "$E/home" open pubs3)
has "as it is when the miss is in a package the app does not depend on" "$O" "Not here: args-2.5.0 "
quiet "$E/home" open pubt; commit "$HW/lane-pubt" t.txt "a lane the trunk resolves after"
O=$(LANE_TEST_FLUTTER=absent_trunk out "$E/home" land pubt)
has "a miss in the trunk after a land is the next open's: the land stands" "$O" "merged work/pubt"
has "and says it landed" "$O" "[exit 0]"

say "W A CHECKOUT'S OWN RESOLVER IS NOT ASKED: furnish resolves with the trunk's, offline"
# A checkout older than the offline fix holds a resolver that drops what it
# is handed (b60cbd54d's): furnished with it, it resolved online (관제
# 2026-11-07, 캔버스 베이스 22:14 — the Surface downloaded code_assets 2.2.0).
quiet "$E/home" open oldpub
printf '%s\n' '#!/usr/bin/env bash' 'checkout="${1:-.}"' 'for package in packages/gpu_engine; do' \
  '  [ -f "$checkout/$package/pubspec.yaml" ] || continue' \
  '  (cd "$checkout" && flutter pub get --directory "$package") || exit 1' 'done' \
  > "$HW/lane-oldpub/tool/resolve_packages.sh"
git -C "$HW/lane-oldpub" commit -q -am "the resolver before it passed its flags on"
quiet "$E/home" furnish "$HW/lane-oldpub"
check "furnished, its packages resolve offline" \
  "$(grep -c '^lane-oldpub flutter pub get --offline --directory packages/gpu_engine' "$LANE_TEST_LOG")" 2
check "and never as its own resolver would have them" \
  "$(grep -c '^lane-oldpub flutter pub get --directory' "$LANE_TEST_LOG")" 0
# The whole run: every open, receive, gate, land and furnish above.
check "not one crate or package could be downloaded" \
  "$(cat "$LANE_TEST_LOG.downloads" 2>/dev/null | head -3 | tr '\n' ' ')" ""
check "LIVENESS — and the packages the app does not depend on were resolved" \
  "$(grep -q 'pub get --offline --directory packages/gpu_engine' "$LANE_TEST_LOG" && echo resolved)" resolved

say "X A LINK IN A LANE GOES WITH IT, AND WHAT IT POINTS AT STAYS: drop and land empty no folder outside the lane"
# The engine's build hook stands a junction in a lane into the trunk's hook
# folder while it builds, and a run killed there leaves it standing; Git for
# Windows' `worktree remove` deleted through one
# (the-hook-folder-lost-an-android-dep-file, 2026-11-08). Under build/,
# which the scratch trunk ignores, so the lane is clean to land.
link_into() {  # link_into <link> <folder>: a junction on Windows, as the hook's
  if command -v cygpath >/dev/null 2>&1; then
    cmd //c mklink //J "$(cygpath -w "$1")" "$(cygpath -w "$2")" >/dev/null
  else
    ln -s "$2" "$1"
  fi
}
SHARED="$E/shared"; mkdir -p "$SHARED"; echo kept > "$SHARED/kept"
quiet "$E/home" open linkd; mkdir -p "$HW/lane-linkd/build"
link_into "$HW/lane-linkd/build/target" "$SHARED"
check "LIVENESS — the link reads the folder" "$(cat "$HW/lane-linkd/build/target/kept")" kept
quiet "$E/home" drop linkd
check "a dropped lane takes nothing through its link" "$(ls "$SHARED")" kept
check "and is gone" "$(test -e "$HW/lane-linkd" && echo there || echo gone)" gone
quiet "$E/home" open linkl; commit "$HW/lane-linkl" x.txt "a lane with a link"
mkdir -p "$HW/lane-linkl/build"; link_into "$HW/lane-linkl/build/target" "$SHARED"
O=$(out "$E/home" land linkl)
has "a lane with a link lands" "$O" "merged work/linkl"
check "and takes nothing through it either" "$(ls "$SHARED")" kept

echo
echo "== $FAILS failed"
exit "$FAILS"
