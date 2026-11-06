#!/usr/bin/env bash
# Adversarial test for guard_shared_target.sh, run by hand:
#   bash tool/session_hooks/guard_shared_target_test.sh
# The payloads are what Claude Code hands a PreToolUse hook: the command as
# a JSON string (a Windows backslash doubled), the call's description after.
G="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/guard_shared_target.sh"
pass=0; fail=0

t() { # name, command as JSON string text, expected(block|allow)
  out=$(printf '{"tool_input":{"command":"%s","description":"x"}}' "$2" | bash "$G")
  got=$([ -n "$out" ] && echo block || echo allow)
  if [ "$got" = "$3" ]; then pass=$((pass+1)); mark="ok  "
  else fail=$((fail+1)); mark="FAIL"; fi
  printf '%s  %-46s got=%-5s want=%s\n' "$mark" "$1" "$got" "$3"
}

# The checkout the guard sits in is the trunk it guards, wherever that is.
TRUNK="$(cd "$(dirname "$G")/../.." && pwd)"
LANE="$TRUNK/.claude/worktrees/lane-x"
# Its Windows spelling as a JSON string holds it — each `\` doubled; the
# bash spelling where there is no other.
WIN="$(cd "$TRUNK" && pwd -W 2>/dev/null || pwd)"
WIN_JSON="$(printf '%s' "$WIN" | sed 's#/#\\\\\\\\#g')"

# --- must BLOCK: a building cargo on the shared folder ---
t "target in the variable"     "export CARGO_TARGET_DIR=$TRUNK/packages/gpu_engine/rust/target; ( cd $LANE/packages/gpu_engine/rust && cargo test --release )" block
t "target as a prefix word"    "CARGO_TARGET_DIR=$TRUNK/packages/gpu_engine/rust/target cargo +1.99.1 test --offline" block
t "windows target, quoted"     "export CARGO_TARGET_DIR='$WIN_JSON\\\\packages\\\\gpu_engine\\\\rust\\\\target'; cargo build" block
t "windows crate, forward"     "( cd $WIN/packages/gpu_engine/rust && cargo test )" block
t "in the trunk's crate"       "( cd $TRUNK/packages/gpu_engine/rust && cargo test --lib -- kernels::flood )" block
t "in a trunk native crate"    "( cd $TRUNK/packages/gpu_engine/rust/native/audio && cargo test )" block
t "relative from the trunk"    "( cd packages/gpu_engine/rust && cargo check )" block
t "manifest path in trunk"     "cargo test --manifest-path $TRUNK/packages/gpu_engine/rust/Cargo.toml" block
t "after a newline"            "export A=1\\n( cd $TRUNK/packages/gpu_engine/rust && cargo t )" block
t "cargo by its full path"     "( cd $TRUNK/packages/gpu_engine/rust && /d/rust/cargo/bin/cargo.exe build --release )" block
t "two env words in front"     "( cd $TRUNK/packages/gpu_engine/rust && RUSTUP_HOME='D:\\\\rust' QA=1 cargo clippy )" block

# --- must ALLOW: the turn, and cargos with a target of their own ---
t "the turn, trunk crate"      "( cd $TRUNK/packages/gpu_engine/rust && bash $TRUNK/tool/cargo_turn.sh test --release )" allow
t "the turn, relative"         "( cd packages/gpu_engine/rust && bash ../../../tool/cargo_turn.sh test )" allow
t "own target on D:"           "export CARGO_TARGET_DIR='D:\\\\rust\\\\target-fuzzcheck'; ( cd $TRUNK/packages/gpu_engine/rust && cargo test )" allow
t "a lane's own target"        "( cd $LANE/packages/gpu_engine/rust && cargo test --release )" allow
t "the fuzz crate"             "( cd $TRUNK/packages/gpu_engine/rust/fuzz && cargo build )" allow
t "a scratch crate"            "( cd /c/tmp/fuzzcheck && cargo +1.99.1 build --offline )" allow
t "builds nothing: metadata"   "( cd $TRUNK/packages/gpu_engine/rust && cargo metadata --offline --format-version 1 )" allow
t "builds nothing: tree"       "( cd $TRUNK/packages/gpu_engine/rust && cargo tree -p media )" allow
t "no cargo at all"            "ls $TRUNK/packages/gpu_engine/rust/target" allow
t "cargo only in prose"        "echo run cargo test in $TRUNK/packages/gpu_engine/rust later" allow
t "cargo in a grep pattern"    "grep -n 'cargo test' $TRUNK/packages/gpu_engine/rust/README.md" allow
t "lane.sh land"               "bash tool/lane.sh land some-lane" allow

# --- the description after the command is never read as one ---
out=$(printf '{"tool_input":{"command":"ls","description":"x; cd %s/packages/gpu_engine/rust && cargo test"}}' "$TRUNK" | bash "$G")
if [ -z "$out" ]; then pass=$((pass+1)); echo "ok    description is not the command"; else fail=$((fail+1)); echo "FAIL  description is not the command"; fi

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
