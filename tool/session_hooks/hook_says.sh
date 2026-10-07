#!/usr/bin/env bash
# WHAT A HOOK SAYS TO CLAUDE CODE — the one place a sentence becomes JSON.
# Sourced, never run: `. "$HERE/hook_says.sh"`.
#
# Every hook here answers with one JSON object on stdout, and every one used
# to build it by hand: a literal with `\n` typed into it and a variable
# dropped in the middle. A variable that holds a real line break or a quote
# makes that literal NOT JSON, and Claude Code reads output it cannot parse
# as plain text — so a hook that meant to stop the turn stops nothing, and
# nothing says so.
#
# 🧪2026-10-07, found on the Surface and reproduced on the first machine: the
# board gate dropped the checker's complaint — several lines, with quotes in
# them — straight into its `block`, and a JSON parser answers 「Control
# character in string」. The gate was unreadable exactly when the board had
# something to say. The same shape stood in ten more places, safe only
# because what they dropped in happened to be one tame line.
#
# So a hook hands these functions PLAIN TEXT — real line breaks, real
# quotes, whatever a tool printed — and the escaping is done here, once.
# ⛔No hook spells `"decision"` or `hookSpecificOutput` itself:
# test/tool/a_hook_speaks_through_one_mouth_test.dart reads the scripts for
# it. What these print for awkward text is pinned by hook_says_test.sh.

# json_text <text>: [text] as the inside of a JSON string. Backslash first,
# or the escapes written after it would be escaped again. A carriage return
# is dropped (Windows tools end lines with one) and so is every other
# control character JSON forbids raw: none of them is anything to read.
json_text() {
  printf '%s' "$1" \
    | tr -d '\000-\010\013-\037' \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' \
    | awk 'NR > 1 { printf "\\n" } { printf "%s", $0 }'
}

# say_block <reason>: a Stop hook's 「not yet」 — the turn goes on, and
# Claude is told why.
say_block() {
  printf '{"decision":"block","reason":"%s"}\n' "$(json_text "$1")"
}

# say_context <event> <text>: [text] put in front of Claude, from a hook of
# [event] (UserPromptSubmit, PostToolUse, SessionStart).
say_context() {
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' \
    "$1" "$(json_text "$2")"
}

# say_deny <reason>: a PreToolUse hook's refusal of the call about to run.
say_deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
    "$(json_text "$1")"
}
