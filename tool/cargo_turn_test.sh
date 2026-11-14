#!/usr/bin/env bash
# What tool/cargo_turn.sh DOES — run by hand; the suite spawns no process
# (tests_do_not_race_the_code_test).
#
# 🚨IT RUNS A STAGED COPY AGAINST A STAND-IN: the stage is a git repository
# of its own holding the script, with a worktree beside it as a lane is,
# and `cargo` is a stand-in that writes down when it ran, where it was
# told to build and what it was asked, then waits a moment and exits as it
# is told. Nothing of this machine's own target folder is touched.
#
# What it holds (관제 2026-11-06, native-memory-safety): cargo builds into
# the trunk's packages/gpu_engine/rust/target, from the trunk or from a
# lane · it is handed its arguments and its exit code is the run's · two
# runs at once never overlap — the second waits, and says so · the turn is
# let go after a run that failed too · a turn left by a dead holder is
# taken over · it keeps no incremental cache (관제 2026-11-08 01:10) ·
# the turn goes to the waiter that came first, and a killed waiter holds no
# one back (2026-11-14) · before the turn is let go, each crate keeps its
# last 8 builds in every folder of builds, and what was just built, a crate
# of one build, `build/` and the hook's copies stay (the same day).
#
# usage: bash tool/cargo_turn_test.sh
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cargo-turn-test.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
STAGE="$TMP/stage"
LANE="$TMP/lane"
LOG="$TMP/calls"
mkdir -p "$STAGE/tool" "$TMP/bin"
cp "$HERE/cargo_turn.sh" "$STAGE/tool/"
git -C "$STAGE" init -q
git -C "$STAGE" -c user.name=t -c user.email=t@t add tool/cargo_turn.sh
git -C "$STAGE" -c user.name=t -c user.email=t@t commit -qm stage
git -C "$STAGE" worktree add -q "$LANE" 2>/dev/null
cat > "$TMP/bin/cargo" <<CARGO
#!/usr/bin/env bash
echo "start \$\$ \$(date +%s%N) \$CARGO_TARGET_DIR \$*" >> "$LOG"
echo "incremental \${CARGO_INCREMENTAL-unset}" >> "$TMP/env"
sleep "\${FAKE_SECONDS:-1}"
for f in \${FAKE_BUILD:-}; do
  mkdir -p "\$(dirname "\$CARGO_TARGET_DIR/\$f")"
  : > "\$CARGO_TARGET_DIR/\$f"
done
echo "end \$\$ \$(date +%s%N)" >> "$LOG"
exit "\${FAKE_EXIT:-0}"
CARGO
chmod +x "$TMP/bin/cargo"
export PATH="$TMP/bin:$PATH"
TURN="$STAGE/.git/cargo-target.turn"
# The trunk as git spells it, as the script finds it: on Windows the
# system temp is mounted at /tmp, and git says /tmp where `pwd` says the
# folder (three checks failed so till 2026-11-14).
WANT_TARGET="$(cd "$(git -C "$STAGE" rev-parse --path-format=absolute \
  --git-common-dir)/.." && pwd)/packages/gpu_engine/rust/target"

pass=0; fail=0
check() { # name, condition result (0 = holds)
  if [ "$2" -eq 0 ]; then pass=$((pass+1)); echo "ok    $1"
  else fail=$((fail+1)); echo "FAIL  $1"; fi
}

# 1. One run from the trunk: the trunk's target, the arguments, the code.
: > "$LOG"
(cd "$STAGE" && FAKE_EXIT=3 bash tool/cargo_turn.sh test --release -p media) 2>/dev/null
code=$?
check "its exit code is cargo's" "$([ "$code" -eq 3 ]; echo $?)"
check "cargo builds into the trunk's target" \
  "$(grep -q "^start [0-9]* [0-9]* $WANT_TARGET test --release -p media\$" "$LOG"; echo $?)"
check "the turn is let go after a run that failed" "$([ ! -e "$TURN" ]; echo $?)"

# 2. From a lane: still the trunk's target, and the trunk's turn.
: > "$LOG"
(cd "$LANE" && bash tool/cargo_turn.sh build) 2>/dev/null
check "from a lane, the trunk's target" \
  "$(grep -q "^start [0-9]* [0-9]* $WANT_TARGET build\$" "$LOG"; echo $?)"

# 3. Two at once, one from each checkout: never overlapping.
: > "$LOG"
(cd "$STAGE" && FAKE_SECONDS=2 bash tool/cargo_turn.sh test) 2>"$TMP/first.err" &
sleep 0.5
(cd "$LANE" && FAKE_SECONDS=1 bash tool/cargo_turn.sh test) 2>"$TMP/second.err" &
wait
first_end=$(awk '$1 == "end" { print $3; exit }' "$LOG")
second_start=$(awk '$1 == "start" { n++; if (n == 2) { print $3; exit } }' "$LOG")
check "two runs at once: the second starts after the first ends" \
  "$([ -n "$first_end" ] && [ -n "$second_start" ] && [ "$second_start" -ge "$first_end" ]; echo $?)"
check "the one that waits says so" "$(grep -q 'held' "$TMP/second.err"; echo $?)"
check "and nothing is left held" "$([ ! -e "$TURN" ]; echo $?)"

# 4. A turn whose holder is gone is taken over.
: > "$LOG"
mkdir "$TURN"
echo 999999 > "$TURN/pid"
echo "a run that was killed" > "$TURN/what"
(cd "$STAGE" && timeout 20 bash tool/cargo_turn.sh check) 2>/dev/null
check "a dead holder's turn is taken over" "$(grep -q ' check$' "$LOG"; echo $?)"

# 5. --hold: no cargo — the folder on its first line, the turn held until
# what it reads ends (the engine's build hook).
: > "$LOG"
{ sleep 2; date +%s%N > "$TMP/fed"; } \
  | (cd "$LANE" && bash tool/cargo_turn.sh --hold) > "$TMP/hold.out" 2>/dev/null &
sleep 0.5
(cd "$STAGE" && FAKE_SECONDS=0 bash tool/cargo_turn.sh build) 2>/dev/null
wait
said_folder="$(head -1 "$TMP/hold.out")"
want_folder="$(cd "$WANT_TARGET" && { pwd -W 2>/dev/null || pwd; })"
check "--hold says the trunk's target, as this system writes it" \
  "$([ -n "$said_folder" ] && [ "$said_folder" = "$want_folder" ]; echo $?)"
check "--hold runs no cargo" "$([ "$(grep -c '^start' "$LOG")" -eq 1 ]; echo $?)"
check "a cargo started while it holds waits until what it reads ends" \
  "$(awk -v fed="$(cat "$TMP/fed")" '$1 == "start" { exit !($3 >= fed) }' "$LOG"; echo $?)"
check "and the turn is let go then" "$([ ! -e "$TURN" ]; echo $?)"

# 6. --folder hook: the build hook's folder and a turn of its own — a run
# there and one in the crate folder at once do not wait for each other.
: > "$LOG"
(cd "$LANE" && bash tool/cargo_turn.sh --folder hook build) 2>/dev/null
check "--folder hook builds into the trunk's target-hook" \
  "$(grep -q "^start [0-9]* [0-9]* ${WANT_TARGET}-hook build\$" "$LOG"; echo $?)"
: > "$LOG"
(cd "$STAGE" && FAKE_SECONDS=2 bash tool/cargo_turn.sh test) 2>/dev/null &
sleep 0.5
(cd "$LANE" && FAKE_SECONDS=0 bash tool/cargo_turn.sh --folder hook build) \
  2>"$TMP/hook.err"
wait
crate_pid=$(awk '$1 == "start" && $4 !~ /-hook$/ { print $2; exit }' "$LOG")
crate_end=$(awk -v p="$crate_pid" '$1 == "end" && $2 == p { print $3; exit }' "$LOG")
hook_start=$(awk '$1 == "start" && $4 ~ /-hook$/ { print $3; exit }' "$LOG")
check "a hook run does not wait for a crate run" \
  "$([ -n "$hook_start" ] && [ -n "$crate_end" ] && [ "$hook_start" -lt "$crate_end" ]; echo $?)"
check "and says no wait" "$(! grep -q 'held' "$TMP/hook.err"; echo $?)"
: > "$LOG"
(cd "$STAGE" && bash tool/cargo_turn.sh --folder elsewhere build) 2>/dev/null
code=$?
check "a folder of no name is refused, and runs no cargo" \
  "$([ "$code" -eq 2 ] && [ ! -s "$LOG" ]; echo $?)"

# 7. No incremental cache in a shared folder, whatever the caller asks.
: > "$TMP/env"
(cd "$LANE" && CARGO_INCREMENTAL=1 bash tool/cargo_turn.sh test) 2>/dev/null
check "cargo builds there with no incremental cache" \
  "$([ "$(cat "$TMP/env")" = "incremental 0" ]; echo $?)"

# 8. First come, first served (a-batch-is-cut-silent-while-it-waits-for-
# the-hook-turn, 2026-11-14): one that comes the moment the holder lets go,
# while another has waited, waits behind it — the one waiting tries again
# only seconds later, and the folder was free for whoever tried first.
: > "$LOG"
(cd "$STAGE" && FAKE_SECONDS=3 bash tool/cargo_turn.sh first) 2>/dev/null &
sleep 0.3
(cd "$LANE" && FAKE_SECONDS=0 bash tool/cargo_turn.sh second) 2>/dev/null &
for _ in $(seq 100); do
  grep -q '^end' "$LOG" && break
  sleep 0.1
done
(cd "$STAGE" && FAKE_SECONDS=0 bash tool/cargo_turn.sh third) 2>/dev/null &
wait
second_start=$(awk '$1 == "start" && $5 == "second" { print $3 }' "$LOG")
third_start=$(awk '$1 == "start" && $5 == "third" { print $3 }' "$LOG")
check "one that came later waits behind one already waiting" \
  "$([ -n "$second_start" ] && [ -n "$third_start" ] && [ "$second_start" -lt "$third_start" ]; echo $?)"
check "and no ticket is left in the line" \
  "$([ -z "$(ls "$TURN.line" 2>/dev/null)" ]; echo $?)"

# 9. A waiter that was killed leaves its ticket: it holds no one back.
: > "$LOG"
mkdir -p "$TURN.line"
: > "$TURN.line/1000000000-999999"
(cd "$STAGE" && timeout 20 bash tool/cargo_turn.sh check) 2>/dev/null
check "a dead waiter's ticket holds no one back" \
  "$(grep -q ' check$' "$LOG"; echo $?)"
check "and goes" "$([ ! -e "$TURN.line/1000000000-999999" ]; echo $?)"

# 10 (2026-11-14). --where: the folder --hold says, while another holds the
# turn — no wait and no cargo.
: > "$LOG"
{ sleep 2; } | (cd "$STAGE" && bash tool/cargo_turn.sh --folder hook --hold) \
  > /dev/null 2>&1 &
sleep 0.5
said_where="$(cd "$LANE" && timeout 3 bash tool/cargo_turn.sh --folder hook \
  --where 2>"$TMP/where.err")"
code=$?
wait
check "--where says the hook folder, as --hold does, and does not wait" \
  "$([ "$code" -eq 0 ] && [ "$said_where" = "$(cd "${WANT_TARGET}-hook" && { pwd -W 2>/dev/null || pwd; })" ] && ! grep -q held "$TMP/where.err"; echo $?)"
check "and runs no cargo" "$([ ! -s "$LOG" ]; echo $?)"

# 11 (the-shared-crate-target-never-shrinks-itself, 2026-11-14). A floor
# under every folder of builds, laid before the turn is let go: eight
# builds of a crate stand, a run builds a ninth, and the oldest goes alone.
built() { # folder crate hash minutes-ago: a build, as cargo leaves one
  local f
  for f in "$2-$3.d" "lib$2-$3.rlib" "$2-$3.pdb" "$2-$3"; do
    : > "$1/$f"
    touch -d "$4 minutes ago" "$1/$f"
  done
  mkdir -p "${1%/*}/.fingerprint/$2-$3"
}
D="$WANT_TARGET/debug/deps"
X="$WANT_TARGET/debug/examples"
B="$WANT_TARGET/debug/build/many-00000000000000b0"
mkdir -p "$D" "$X" "$B"
: > "$B/out"
for i in 1 2 3 4 5 6 7 8; do
  built "$D" many "00000000000000a$i" $((100 - i))
  built "$X" sample "00000000000000e$i" $((100 - i))
done
built "$D" few 00000000000000c1 5000
built "$X" sample 00000000000000e9 1
# A crate's library builds and its test binary's, nine between them: one
# crate, which a library's lib<crate> files alone would split in two.
for i in 1 2 3 4 5 6 7 8 9; do
  if [ "$i" -le 5 ]; then set -- "aaa-00000000000000d$i.d" "libaaa-00000000000000d$i.rlib"
  else set -- "aaa-00000000000000d$i.d" "aaa-00000000000000d$i.exe" "aaa-00000000000000d$i.pdb"; fi
  for f in "$@"; do : > "$D/$f"; touch -d "$((100 - i)) minutes ago" "$D/$f"; done
done
set --
(cd "$LANE" && FAKE_SECONDS=0 FAKE_BUILD="debug/deps/many-00000000000000a9.d \
  debug/deps/libmany-00000000000000a9.rlib" bash tool/cargo_turn.sh test) \
  2>/dev/null
check "a ninth build takes out the oldest, its files and its fingerprint" \
  "$([ -z "$(ls "$D" | grep 00000000000000a1)" ] \
    && [ ! -e "$WANT_TARGET/debug/.fingerprint/many-00000000000000a1" ]; echo $?)"
check "and only the oldest" \
  "$([ "$(ls "$D" | grep -c '^\(lib\)\?many-00000000000000a[2-8]')" -eq 28 ] \
    && [ -d "$WANT_TARGET/debug/.fingerprint/many-00000000000000a2" ]; echo $?)"
check "what the run just built stays" \
  "$([ -e "$D/many-00000000000000a9.d" ] && [ -e "$D/libmany-00000000000000a9.rlib" ]; echo $?)"
check "a crate's library and its test binary are one crate's builds" \
  "$([ -z "$(ls "$D" | grep 00000000000000d1)" ] \
    && [ "$(ls "$D" | grep -c 00000000000000d2)" -eq 2 ]; echo $?)"
check "a crate of one build stays, however old" \
  "$([ "$(ls "$D" | grep -c 00000000000000c1)" -eq 4 ]; echo $?)"
check "an example folder keeps its last eight as well" \
  "$([ -z "$(ls "$X" | grep 00000000000000e1)" ] \
    && [ "$(ls "$X" | grep -c 'sample-00000000000000e[2-9]')" -eq 32 ]; echo $?)"
check "build/ is not touched" "$([ -e "$B/out" ]; echo $?)"
H="${WANT_TARGET}-hook"
HD="$H/x86_64-pc-windows-msvc/release/deps"
mkdir -p "$HD" "$H/copies/0123456789abcdef/key"
: > "$H/copies/0123456789abcdef/key/engine.dll"
for i in 1 2 3 4 5 6 7 8 9; do
  built "$HD" fx "00000000000000f$i" $((100 - i))
done
: | (cd "$LANE" && bash tool/cargo_turn.sh --folder hook --hold) >/dev/null 2>&1
check "a target's folder in the hook's floors too, after a --hold" \
  "$([ -z "$(ls "$HD" | grep 00000000000000f1)" ] \
    && [ "$(ls "$HD" | grep -c '^\(lib\)\?fx-')" -eq 32 ]; echo $?)"
check "and the hook's copies are not touched" \
  "$([ -e "$H/copies/0123456789abcdef/key/engine.dll" ]; echo $?)"

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
