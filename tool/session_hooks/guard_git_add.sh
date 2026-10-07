#!/usr/bin/env bash
# PreToolUse guard: a blanket `git add` never runs in this repo.
#
# 2026-08-23, two zero-byte files with typo names -- `downs=2` and `seen=6783`,
# the debris of a mistyped shell redirect -- were committed to a PUBLIC
# repository in c72e6d01 (#1186). Nothing referenced them; the damage was that
# they were there, in public, looking like they might mean something.
#
# A blanket add is the only way that happens. The rule against it has been
# written down for months and had nothing behind it.
#
# THIS COSTS NOTHING WHEN IT DOES NOT FIRE: the settings entry filters on
# `Bash(git *)`, so a non-git command never even spawns this.
#
# MATCHING PROSE IS NOT A SAFE DIRECTION TO BE WRONG IN. Three versions, each
# broken in a way only a test could show:
#   v1 matched the words anywhere in the payload. Within the hour it refused a
#      heredoc that merely WROTE ABOUT the rule, then refused the command that
#      would have fixed this file. A guard that blocks writing about itself is
#      a guard that gets uninstalled.
#   v2 anchored to `^git` and silently stopped blocking ANYTHING: the hook is
#      handed the whole JSON payload, so the command sits inside a quoted
#      string and never starts a line. Worse than blunt -- it still looks
#      installed.
#   v3 (v2 + splitting on `"` to reach inside the JSON) turned every quoted
#      string in the command into a command position, so a shell one-liner
#      that merely QUOTED the words was refused again.
# The fix is to stop guessing at the text and take the field: pull
# `.tool_input.command` out, unescape it, and split that on shell separators
# alone. `jq` is not on PATH in this environment, hence sed.
set -u

payload=$(cat)

# .tool_input.command -- greedy to the last quote, which can over-capture a
# trailing field; harmless, since the tail is split and anchored the same way.
cmd=$(printf '%s' "$payload" \
  | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p')
[ -z "$cmd" ] && exit 0

hit=$(printf '%s' "$cmd" \
  | sed 's/\\n/\n/g; s/\\"/"/g' \
  | tr ';|&' '\n\n\n' \
  | sed 's/^[[:space:]]*//' \
  | grep -E '^git\b' \
  | grep -cE '\badd[[:space:]]+(-A\b|--all\b|\.([[:space:]]|$))')

[ "$hit" -eq 0 ] && exit 0

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"⛔ 전체 스테이징(-A / --all / .)은 이 리포에서 금지입니다. 2026-08-23 에 이걸로 오타 파일 둘(`downs=2`·`seen=6783`)이 공개 리포에 커밋됐습니다(c72e6d01). 올릴 파일 경로를 직접 적으세요."}}
JSON
