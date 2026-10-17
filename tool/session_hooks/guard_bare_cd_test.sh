#!/usr/bin/env bash
# Adversarial test for guard_bare_cd.sh — every shape of the twenty-one
# recorded moves must be refused, and every `cd` that cannot move the
# session must run. Payloads are JSON as the hook is handed them — `\n` in
# a single-quoted string here is the JSON escape of a line break, `\\` of a
# backslash — and the command is followed by a field of its own, as the
# real payload's `description` follows it.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
G="$here/guard_bare_cd.sh"
root="$(cd "$here/../.." && pwd)"
root_w="$(cd "$here/../.." && pwd -W)"
pass=0; fail=0

t() { # name, payload, expected(block|allow)
  out=$(printf '%s' "$2" | bash "$G")
  got=$([ -n "$out" ] && echo block || echo allow)
  if [ "$got" = "$3" ]; then pass=$((pass+1)); mark="ok  "
  else fail=$((fail+1)); mark="FAIL"; fi
  printf '%s  %-44s got=%-5s want=%s\n' "$mark" "$1" "$got" "$3"
}
c() { printf '{"tool_input":{"command":"%s"},"cwd":"/x"}' "$1"; }

# --- must BLOCK: the recorded moves, in their own shapes -------------------
t "cd then &&"                "$(c 'cd /x && ls')"                         block
t "cd then ;"                 "$(c 'cd /x; ls')"                           block
t "after ;"                   "$(c 'ls; cd /x')"                           block
t "a path in a variable"      "$(c 'P=/x; cd $P && git log')"              block
t "test -f guard, then cd"    "$(c 'test -f \"$P/.git\" && cd $P/test 2>/dev/null; (cd $P && grep a b)')" block
t "leftover before subshell"  "$(c 'cd $L 2>/dev/null; (cd $L && file x)')" block
t "second line"               "$(c 'ls\ncd /x')"                           block
t "line goes on into cd"      "$(c 'ls && \\\ncd /x')"                     block
t "loop body"                 "$(c 'for d in a b; do cd $d; done')"        block
t "brace group"               "$(c '{ cd /x; ls; }')"                      block
t "if condition"              "$(c 'if cd /x; then ls; fi')"               block
t "case body"                 "$(c 'case $a in x) cd /y ;; esac')"         block
t "assignment prefix"         "$(c 'X=1 cd /x')"                           block
t "quoted path"               "$(c 'cd \"/x y\" && ls')"                   block
t "redirect after"            "$(c 'cd /x 2>/dev/null')"                   block
t "comment after"             "$(c 'cd /x # go there')"                    block
t "home"                      "$(c 'cd')"                                  block
t "back"                      "$(c 'cd -')"                                block
t "a folder of the root"      "$(c "cd $root/lib && wc -l a")"            block
t "the root, in a variable"   "$(c "R=$root; cd \$R; ls")"                 block
t "after a heredoc ends"      "$(c 'cat <<EOF\ntext\nEOF\ncd /x')"         block
t "after a quoted one ends"   "$(c "cat <<'EOF'\nx\nEOF\ncd /x")"         block
t "after a tab-stripped one"  "$(c 'cat <<-EOF\n\tx\n\tEOF\ncd /x')"       block
t "assigned by substitution"  "$(c 'x=$(pwd) cd /x')"                      block
t "redirect before it"        "$(c '2>/dev/null cd /x')"                   block

# --- must ALLOW: a subshell takes its directory with it --------------------
t "subshell"                  "$(c '(cd /x && ls)')"                       allow
t "spaced subshell"           "$(c '( cd /x && ls )')"                     allow
t "substitution"              "$(c 'x=$(cd /x && pwd); echo $x')"          allow
t "backticks"                 "$(c 'x=`ls; cd /x`; echo $x')"              allow
t "subshell after a cd-less"  "$(c 'ls && (cd /x && ls)')"                 allow
t "quoted to bash -c"         "$(c 'bash -c \"cd /x && ls\"')"             allow

# --- must ALLOW: the way back to the root ----------------------------------
t "back to the root"          "$(c "cd $root")"                            allow
t "root, trailing slash"      "$(c "cd $root/ && ls")"                     allow
t "root, Windows spelling"    "$(c "cd $root_w")"                          allow
t "root, after an option"     "$(c "cd -P $root")"                         allow

# --- must ALLOW: cd that is only text --------------------------------------
t "echo double-quoted"        "$(c 'echo \"a; cd /x\"')"                   allow
t "escaped quote inside"      "$(c 'echo \"a\\\"; cd /x\"')"               allow
t "echo single-quoted"        "$(c "echo 'a; cd /x'")"                     allow
t "escaped separator"         "$(c 'echo a\\;cd /x')"                      allow
t "grep for it"               "$(c 'grep -rn \"cd /x\" docs/')"            allow
t "comment"                   "$(c 'ls # cd /x')"                          allow
t "heredoc body"              "$(c "cat > f.sh <<'EOF'\\ncd /x\\nls\\nEOF\\nbash f.sh")" allow
t "tab-stripped heredoc"      "$(c 'cat <<-EOF\n\tcd /x\n\tEOF\nls')"      allow
t "commit message heredoc"    "$(c "git commit -m \\\"\$(cat <<'EOF'\ncd guard: it did not refuse\nEOF\n)\\\"")" allow
t "argument, not command"     "$(c 'echo cd /x')"                          allow
t "argument after a sub"      "$(c 'echo $(pwd) cd')"                      allow
t "inside a word"             "$(c 'abcd /x; ls cd/x')"                    allow
t "git -C"                    "$(c 'git -C /x status')"                    allow
t "redirect target"           "$(c 'ls >cd')"                              allow
t "a target named cd, first"  "$(c '>cd ls')"                              allow

# --- edge: no command field (other tools) -----------------------------------
t "no command field"          '{"tool_input":{"file_path":"/x/cd /y"}}'     allow

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] && echo "All tests passed!" || echo "SOME TESTS FAILED"
exit "$fail"
