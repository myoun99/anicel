#!/usr/bin/env bash
# PreToolUse guard: a cargo that would build into the trunk's shared target
# folder runs in its turn (tool/cargo_turn.sh), or not at all.
#
# 관제 2026-11-06 (native-memory-safety): two cargos in that folder at once
# replace each other's builds — a land's doc-tests failed twice with
# `E0463 can't find crate for media` while another checkout built under
# them. "No cargo there while a gate runs" was written down and broken the
# same day; tool/cargo_turn.sh is the turn, and this keeps a session from
# walking past it.
#
# WHAT IS REFUSED: `cargo` where a command starts — after `;` `&&` `||`
# `|`, a newline or a bracket, past any `NAME=value` words in front of it —
# running a subcommand that builds (build · check · test · run · bench ·
# clippy · doc · rustc · rustdoc · fix, and their one-letter forms), in a
# call that names the shared folder: the trunk's
# `packages/gpu_engine/rust/target`, or the trunk's crate folders, whose
# own target that folder is — written out, or relative from the main
# checkout where a session stands.
# WHAT RUNS: the turn itself (`bash tool/cargo_turn.sh …`, where `cargo`
# is an argument); a cargo whose CARGO_TARGET_DIR is somewhere else; a
# cargo in a lane's folder (its own `target`) or in the fuzz crate (a
# workspace of its own); a cargo that builds nothing (metadata · tree ·
# fmt …); `cargo` that is only a word in a sentence.
#
# ⚠️This reads words, not the whole shell (guard_bare_cd.sh does that for
# `cd`): a heredoc whose body has a line starting with a building cargo, in
# a call that also names the trunk's crate, is refused too. The refusal says
# how to run it, so the cost of that mistake is one more call.
# ⛔NOT TO THE LAST QUOTE (guard_bare_cd.sh's lesson): the command is read
# up to the first quote the JSON does not escape, so the call's
# `description` after it is never read as a command.
set -u

payload=$(cat)
case "$payload" in *cargo*) ;; *) exit 0 ;; esac

verdict=$(printf '%s' "$payload" | awk '
BEGIN { RS = "^$" }
{
  if (!match($0, /"command"[ \t]*:[ \t]*"/)) exit
  rest = substr($0, RSTART + RLENGTH)
  # The JSON string, to its closing quote; then its escapes undone — a
  # `\\` as `/`, so a Windows path and a bash path read the same.
  text = ""
  for (i = 1; i <= length(rest); i++) {
    c = substr(rest, i, 1)
    if (c == "\"") break
    if (c == "\\") {
      d = substr(rest, ++i, 1)
      if (d == "n") c = "\n"
      else if (d == "t") c = "\t"
      else if (d == "\\") c = "/"
      else c = d
    }
    text = text c
  }
  low = tolower(text)
  # The fuzz crate is a workspace of its own, with its own target.
  gsub(/packages\/+gpu_engine\/+rust\/+fuzz/, "", low)
  shared = (low ~ /anicel\/+packages\/+gpu_engine\/+rust\/+target/)
  trunk = (low ~ /anicel\/+packages\/+gpu_engine\/+rust/) ||
    (low ~ /(^|[ \t\n"'"'"'=(])packages\/+gpu_engine\/+rust/)
  elsewhere = (low ~ /cargo_target_dir=/) && !shared
  if (!shared && !(trunk && !elsewhere)) exit
  n = split(text, segments, /[;&|\n(){}`]/)
  for (i = 1; i <= n; i++) {
    s = segments[i]
    sub(/^[ \t]+/, "", s)
    while (s ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
      if (!sub(/^[A-Za-z_][A-Za-z0-9_]*=("[^"]*"|'"'"'[^'"'"']*'"'"'|[^ \t]*)[ \t]+/, "", s)) break
    }
    while (s ~ /^(exec|command|time|env|nice)[ \t]/) sub(/^[a-z]+[ \t]+/, "", s)
    w = split(s, words, /[ \t]+/)
    if (w == 0) continue
    first = words[1]
    sub(/^.*\//, "", first)
    if (first != "cargo" && first != "cargo.exe") continue
    for (k = 2; k <= w; k++) {
      word = words[k]
      if (word ~ /^\+/) continue
      if (word ~ /^-/) {
        if (word ~ /^(--manifest-path|--config|-Z|-C|--color)$/) k++
        continue
      }
      if (word ~ /^(build|b|check|c|test|t|run|r|bench|clippy|doc|d|rustc|rustdoc|fix)$/) {
        print "refuse"
        exit
      }
      break
    }
  }
}')

[ "$verdict" = refuse ] || exit 0

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hook_says.sh"
say_deny '⛔ 트렁크의 공유 target(packages/gpu_engine/rust/target)에 짓는 cargo 는 차례를 잡고 돈다: `bash tool/cargo_turn.sh <cargo 인자>` — 트렁크든 레인이든 그 자리에서. 두 cargo 가 겹치면 서로의 빌드를 갈아 끼운다(11-06 착지 게이트의 doc-test 가 `E0463 can'"'"'t find crate for media` 로 두 번 떨어졌다). 공유가 필요 없으면 CARGO_TARGET_DIR 를 다른 곳(예: D:\rust\target-<이름>)에 두면 그대로 돈다.'
