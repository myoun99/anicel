#!/usr/bin/env bash
# Adversarial test for guard_dart_run.sh, run by hand:
#   bash tool/session_hooks/guard_dart_run_test.sh
# The payloads are what Claude Code hands a PreToolUse hook: the command as
# a JSON string (a Windows backslash doubled), the call's description after.
G="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/guard_dart_run.sh"
pass=0; fail=0

t() { # name, command as JSON string text, expected(block|allow)
  out=$(printf '{"tool_input":{"command":"%s","description":"x"}}' "$2" | bash "$G")
  got=$([ -n "$out" ] && echo block || echo allow)
  if [ "$got" = "$3" ]; then pass=$((pass+1)); mark="ok  "
  else fail=$((fail+1)); mark="FAIL"; fi
  printf '%s  %-46s got=%-5s want=%s\n' "$mark" "$1" "$got" "$3"
}

# --- must BLOCK: `dart run` of a tool, wherever a command starts ---
t "bare"                       "dart run tool/affected_tests.dart --list" block
t "a tool in a folder"         "dart run tool/session_hooks/install.dart --board x --memory y" block
t "a flag before it"           "dart run --enable-asserts tool/import_graph.dart" block
t "the SDK's dart by its path" "/c/flutter/bin/cache/dart-sdk/bin/dart.exe run tool/x.dart" block
t "a lane's tool by its path"  "dart run C:/Users/u/anicel/.claude/worktrees/lane-x/tool/x.dart" block
t "a windows path"             "dart run C:\\\\anicel\\\\tool\\\\x.dart" block
t "inside a subshell"          "( cd /c/lane && dart run tool/x.dart )" block
t "after a semicolon"          "echo go; dart run tool/x.dart" block
t "after a newline"            "ls\\ndart run tool/x.dart" block
t "past a variable in front"   "QA_X=1 dart run tool/x.dart" block
t "quoted path"                "dart run \\\"tool/x.dart\\\"" block

# --- must ALLOW: the two ways that build nothing ---
t "the exe"                    "bash tool/run.sh affected_tests --list" allow
t "by JIT"                     "dart tool/affected_tests.dart --list" allow
t "by JIT, a lane's"           "( cd /c/lane && dart tool/x.dart )" allow

# --- must ALLOW: `dart run` of anything not under tool/, or no dart run ---
t "a package's executable"     "dart run build_runner build" allow
t "a test folder"              "dart run test/x_test.dart" allow
t "a tool that only sounds so" "dart run tools.dart" allow
t "not dart at all"            "ls tool/" allow
t "dart format"                "dart format --output=none tool/x.dart" allow

# --- must ALLOW: PROSE ---
t "echo about the rule"        "echo never dart run tool/x.dart" allow
t "a commit message"           "git commit -m \\\"refuse dart run tool/ in the guard\\\"" allow
out=$(printf '{"tool_input":{"command":"ls","description":"x; dart run tool/x.dart"}}' | bash "$G")
if [ -z "$out" ]; then pass=$((pass+1)); mark="ok  "; else fail=$((fail+1)); mark="FAIL"; fi
printf '%s  %-46s got=%-5s want=%s\n' "$mark" "the description is not read" "$([ -n "$out" ] && echo block || echo allow)" allow

echo
echo "== $pass passed, $fail failed"
exit "$fail"
