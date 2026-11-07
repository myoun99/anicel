#!/usr/bin/env bash
# PreToolUse guard: a tool of this repository is not run by `dart run`.
#
# 관제 2026-11-07 (connection-round-checklist 22:10): the app depends on
# the GPU engine, whose build hook compiles its Rust, and `dart run` runs
# the hooks for the Dart VM — a configuration of its own, so a checkout
# that a `flutter test` already built the engine in builds it once more:
# 485 MB and a minute (measured that day in a fresh lane, beside the
# test's 485 MB and 110 s). `bash tool/run.sh <tool>` runs the tool's
# exe, and `dart tool/<tool>.dart` runs it by JIT: neither runs a hook
# (measured the same day: 2 s, nothing built). A rule written down is
# broken by the session that does not read it, so this refuses instead.
#
# WHAT IS REFUSED: `dart run` where a command starts — after `;` `&&` `||`
# `|`, a newline or a bracket, past any `NAME=value` words in front of it
# — naming a file under a `tool/` folder, in either spelling of a path.
# WHAT RUNS: `bash tool/run.sh …` and `dart tool/….dart`; `dart run` of
# anything that is not under `tool/`; `dart run` that is only a word in a
# sentence.
#
# ⚠️This reads words, not the whole shell (guard_bare_cd.sh does that for
# `cd`): a heredoc whose body has a line starting with `dart tool/` is
# refused too. The refusal says what to run instead, so the cost of that
# mistake is one more call.
# ⛔NOT TO THE LAST QUOTE (guard_bare_cd.sh's lesson): the command is read
# up to the first quote the JSON does not escape, so the call's
# `description` after it is never read as a command.
set -u
payload=$(cat)
case "$payload" in *dart*) ;; *) exit 0 ;; esac
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
  n = split(text, segments, /[;&|\n(){}`]/)
  for (i = 1; i <= n; i++) {
    s = segments[i]
    sub(/^[ \t]+/, "", s)
    while (s ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
      if (!sub(/^[A-Za-z_][A-Za-z0-9_]*=("[^"]*"|'"'"'[^'"'"']*'"'"'|[^ \t]*)[ \t]+/, "", s)) break
    }
    while (s ~ /^(exec|command|time|env|nice)[ \t]/) sub(/^[a-z]+[ \t]+/, "", s)
    w = split(s, words, /[ \t]+/)
    if (w < 2) continue
    first = words[1]
    gsub(/["'"'"']/, "", first)
    sub(/^.*\//, "", first)
    if (tolower(first) != "dart" && tolower(first) != "dart.exe") continue
    if (words[2] != "run") continue
    for (k = 3; k <= w; k++) {
      word = words[k]
      if (word ~ /^-/) continue
      gsub(/["'"'"']/, "", word)
      if (word ~ /(^|\/)tool\//) {
        print "refuse"
        exit
      }
      break
    }
  }
}')

[ "$verdict" = refuse ] || exit 0

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hook_says.sh"
say_deny '⛔ `dart tool/…` 은 이 체크아웃에 엔진 Rust 를 한 벌 더 짓는다(Dart VM 의 설정으로 — 485 MB · 1분, 2026-11-07 실측). `bash tool/run.sh <도구> <인자…>`(도구의 exe) 또는 `dart tool/<도구>.dart <인자…>`(JIT — 예: `dart tool/session_hooks/install.dart --board …`) 로 돌려라 — 둘 다 훅을 안 돌린다.'
