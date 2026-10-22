#!/usr/bin/env bash
# PreToolUse guard: a `cd` that would move the session never runs.
#
# A Bash call's working directory outlives the call, and the harness moves
# the SESSION there with it: one `cd <lane> && grep ...` and every later
# relative path reads the lane, a landing deletes the directory the shell
# sits in, and the next call starts nowhere (2026-10-08). Twenty-one times
# from 2026-10-14 to 10-16, on both machines and in three sessions, each
# time with the rule written down in front of it (board
# a-bare-cd-into-a-lane-is-refused): a lane, a folder of the main checkout,
# a path in a variable, a leftover `cd` in front of a subshell. Writing it
# down did not stop it, so this does.
#
# WHAT IS REFUSED: a `cd` where it runs in the session's own shell — at
# the top level of the command, a `{ }` group or a loop body included,
# whatever the path looks like (a variable, `2>/dev/null` after it).
# WHAT RUNS: a `cd` inside `( )`, `$( )` or backticks — a subshell,
# which takes its directory with it when it ends — and any `cd` that is only
# TEXT: quoted, in a comment, in a heredoc's body.
#
# ⚠️ONE `cd` IS LET THROUGH: back to the main checkout itself, the place a
# session stands — the way back if anything ever moved it.
#
# THIS READS THE SHELL, NOT THE WORDS (guard_git_add.sh's three versions
# say why): `.tool_input.command` is read out of the payload as the JSON
# string it is, and walked by the quoting, nesting and heredoc rules a shell
# reads it by. `jq` is not on PATH here, hence awk.
#
# ⛔NOT TO THE LAST QUOTE, as guard_git_add.sh cuts it: the payload goes on
# after the command (`description`, then the hook's own fields), and a `cd`
# that ends the command took that tail in as its path — `cd` alone read as
# `cd"},"description":...` and ran.
set -u

payload=$(cat)
case "$payload" in *cd*) ;; *) exit 0 ;; esac

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"

bare=$(printf '%s' "$payload" | awk -v root="$root" '
function norm(path) {
  path = tolower(path)
  gsub(/\\/, "/", path)
  sub(/\/+$/, "", path)
  if (path ~ /^\/[a-z]\//) path = substr(path, 2, 1) ":" substr(path, 3)
  return path
}
function prefix_word(word) {
  return word == "if" || word == "then" || word == "elif" ||
    word == "else" || word == "do" || word == "while" || word == "until" ||
    word == "!" || word == "{" || word == "time" || word == "builtin" ||
    word == "command"
}
# A word ended. At a command position it is the command — or a prefix
# that leaves the next word one. After a top-level cd, it is where to.
function end_word() {
  if (!has) return
  if (skip_target) { skip_target = 0 }
  else if (in_cd) {
    if (target == "" && (w !~ /^-/ || w == "-")) target = w
  } else if (cmdpos) {
    if (w ~ /^[A-Za-z_][A-Za-z_0-9]*=/ || prefix_word(w)) { }
    else {
      cmdpos = 0
      if (w == "cd" && depth == 0) { in_cd = 1; target = "" }
    }
  }
  w = ""
  has = 0
}
# A command ended: a top-level cd in it is refused unless it goes to the
# root.
function end_command() {
  end_word()
  if (in_cd && (target == "" || norm(target) != norm(root))) {
    refused = refused (refused == "" ? "" : " | ") "cd" \
      (target == "" ? "" : " " target)
  }
  in_cd = 0
  target = ""
  skip_target = 0
  cmdpos = 1
}
# Into a substitution (its word goes on after it) or a subshell (a command
# of its own): what the level outside was doing is kept to come back to.
function open_level(kind) {
  stack_kind[++sp] = kind
  stack_w[sp] = w
  stack_has[sp] = has
  stack_cmd[sp] = cmdpos
  depth++
  w = ""
  has = 0
  cmdpos = 1
}
function close_level() {
  end_word()
  if (stack_kind[sp] == "substitution") {
    w = stack_w[sp]
    has = 1
    cmdpos = stack_cmd[sp]
  } else {
    cmdpos = 0
  }
  sp--
  depth--
}
BEGIN { RS = "\001" }
{
  # .tool_input.command, the JSON string unescaped into ch[1..m]: to its
  # closing quote, not past it.
  if (!match($0, /"command"[ \t\r\n]*:[ \t\r\n]*"/)) exit
  n = length($0)
  m = 0
  for (i = RSTART + RLENGTH; i <= n; i++) {
    c = substr($0, i, 1)
    if (c == "\"") break
    if (c == "\\" && i < n) {
      d = substr($0, ++i, 1)
      if (d == "n") c = "\n"
      else if (d == "t") c = "\t"
      else if (d == "r") continue
      else if (d == "u") { c = "?"; i += 4 }
      else c = d
    }
    ch[++m] = c
  }
  cmdpos = 1; depth = 0; sp = 0; w = ""; has = 0; in_cd = 0; target = ""
  skip_target = 0; refused = ""; pending = 0; in_tick = 0
  i = 1
  while (i <= m) {
    c = ch[i]
    if (c == "\047") {
      for (i++; i <= m && ch[i] != "\047"; i++) w = w ch[i]
      has = 1; i++; continue
    }
    if (c == "\"") {
      for (i++; i <= m && ch[i] != "\""; i++) {
        if (ch[i] == "\\" && i < m) i++
        w = w ch[i]
      }
      has = 1; i++; continue
    }
    if (c == "\\" && ch[i + 1] == "\n") { i += 2; continue }  # a line goes on
    if (c == "\\") { w = w ch[i + 1]; has = 1; i += 2; continue }
    if (c == "#" && !has) {
      while (i <= m && ch[i] != "\n") i++
      continue
    }
    if (c == "$" && ch[i + 1] == "(") {
      open_level("substitution"); i += 2; continue
    }
    if (c == "`") {
      if (in_tick) { close_level(); in_tick = 0 }
      else { open_level("substitution"); in_tick = 1 }
      i++; continue
    }
    if (c == "(") {
      end_word(); open_level("subshell"); i++; continue
    }
    if (c == ")") {
      if (sp > 0) close_level()
      else end_command()  # a case pattern: its body starts here
      i++; continue
    }
    if (c == "<" && ch[i + 1] == "<" && ch[i + 2] != "<") {
      end_word()
      i += 2
      if (ch[i] == "-") { strip[pending + 1] = 1; i++ }
      else strip[pending + 1] = 0
      while (ch[i] == " " || ch[i] == "\t") i++
      delim = ""
      while (i <= m && ch[i] !~ /[ \t\n;&|<>()]/) {
        if (ch[i] != "\047" && ch[i] != "\"" && ch[i] != "\\") delim = delim ch[i]
        i++
      }
      if (delim != "") heredoc[++pending] = delim
      continue
    }
    if (c == "<" || c == ">") {
      if (c == ">" && ch[i + 1] == "&") i++
      if (w ~ /^[0-9]+$/) { w = ""; has = 0 }  # the fd it redirects
      end_word()
      skip_target = 1
      i++; continue
    }
    if (c == "&" && (ch[i + 1] == ">")) {
      end_word(); skip_target = 1; i += 2; continue
    }
    if (c == ";" || c == "&" || c == "|" || c == "\n") {
      end_command()
      if (c == "\n" && pending > 0) {
        # The heredocs this line opened: their bodies are text.
        for (h = 1; h <= pending; h++) {
          for (;;) {
            i++
            line = ""
            while (i <= m && ch[i] != "\n") line = line ch[i++]
            if (strip[h]) sub(/^\t+/, "", line)
            if (line == heredoc[h] || i > m) break
          }
        }
        pending = 0
      }
      i++; continue
    }
    if (c == " " || c == "\t") { end_word(); i++; continue }
    w = w c; has = 1; i++
  }
  end_command()
  printf "%s", refused
}')

[ -z "$bare" ] && exit 0

. "$here/hook_says.sh"
say_deny "⛔ 맨 \`$bare\` — 세션의 자리를 옮깁니다(10-14~16 스물한 번: 레인 · 본진 하위 폴더 · \`cd \$변수\` · 서브셸 앞의 찌꺼기). 괄호 서브셸 \`( cd X && … )\` · 절대 경로 · \`git -C <경로>\` 로 쓰세요. 통과하는 맨 \`cd\` 는 본진으로 돌아오는 \`cd $root\` 하나입니다."
