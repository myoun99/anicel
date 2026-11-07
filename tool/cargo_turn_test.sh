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
# taken over.
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
sleep "\${FAKE_SECONDS:-1}"
echo "end \$\$ \$(date +%s%N)" >> "$LOG"
exit "\${FAKE_EXIT:-0}"
CARGO
chmod +x "$TMP/bin/cargo"
export PATH="$TMP/bin:$PATH"
TURN="$STAGE/.git/cargo-target.turn"
WANT_TARGET="$(cd "$STAGE" && pwd)/packages/gpu_engine/rust/target"

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

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
