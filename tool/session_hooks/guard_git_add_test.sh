#!/usr/bin/env bash
# Adversarial test for guard_git_add.sh. Lives in the scratchpad because it
# contains the exact strings the guard refuses -- running it from a Bash tool
# call would trip the guard on the test harness itself.
G="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/guard_git_add.sh"
pass=0; fail=0

t() { # name, payload, expected(block|allow)
  out=$(printf '%s' "$2" | bash "$G")
  got=$([ -n "$out" ] && echo block || echo allow)
  if [ "$got" = "$3" ]; then pass=$((pass+1)); mark="ok  "
  else fail=$((fail+1)); mark="FAIL"; fi
  printf '%s  %-40s got=%-5s want=%s\n' "$mark" "$1" "$got" "$3"
}

# --- must BLOCK: real invocations, in every position a command can start ---
t "bare -A"              '{"tool_input":{"command":"git add -A"}}'                       block
t "-C then -A"           '{"tool_input":{"command":"git -C /x add -A"}}'                 block
t "--all"                '{"tool_input":{"command":"git add --all"}}'                    block
t "dot"                  '{"tool_input":{"command":"git add ."}}'                        block
t "after semicolon"      '{"tool_input":{"command":"cd /x; git add ."}}'                 block
t "after &&"             '{"tool_input":{"command":"cd /x && git add -A"}}'              block
t "after newline"        '{"tool_input":{"command":"cd /x\\ngit add -A"}}'               block
t "leading whitespace"   '{"tool_input":{"command":"   git add -A"}}'                    block
t "dot mid-command"      '{"tool_input":{"command":"git add . && git commit -m x"}}'     block

# --- must ALLOW: explicit paths ---
t "one path"             '{"tool_input":{"command":"git add lib/foo.dart"}}'             allow
t "several paths"        '{"tool_input":{"command":"git add a.dart b.dart"}}'            allow
t "path with -C"         '{"tool_input":{"command":"git -C /x add lib/a.dart"}}'         allow
t "dotfile path"         '{"tool_input":{"command":"git add .gitignore"}}'               allow
t "add -p"               '{"tool_input":{"command":"git add -p lib/a.dart"}}'            allow

# --- must ALLOW: not git, or git without add ---
t "not git at all"       '{"tool_input":{"command":"ls -A"}}'                            allow
t "git status"           '{"tool_input":{"command":"git status --short"}}'               allow

# --- must ALLOW: PROSE. this is what v1 and v3 got wrong ---
t "echo about the rule"  '{"tool_input":{"command":"echo rule: git add -A is banned"}}'  allow
t "quoted in a string"   '{"tool_input":{"command":"x=\\"git add -A\\"; echo $x"}}'      allow
t "json record heredoc"  '{"tool_input":{"command":"cat >> b.jsonl <<E\\n{\\"t\\":\\"blocks git add -A\\"}\\nE"}}' allow
t "grep for the phrase"  '{"tool_input":{"command":"grep -rn \\"git add -A\\" docs/"}}'  allow
t "comment mentioning"   '{"tool_input":{"command":"ls  # never git add -A here"}}'      allow

# --- edge: no command field at all (other tools) ---
t "no command field"     '{"tool_input":{"file_path":"/x/git add -A.txt"}}'              allow

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] && echo "All tests passed!" || echo "SOME TESTS FAILED"
exit "$fail"
