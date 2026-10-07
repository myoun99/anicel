#!/usr/bin/env bash
# What hook_says.sh prints for text that is awkward to put in JSON — run by
# hand (`bash tool/session_hooks/hook_says_test.sh`); the suite spawns no
# process. Every expectation is the exact bytes: an escaper that is nearly
# right is the bug this file is for.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/hook_says.sh"

pass=0; fail=0
chk() {  # chk <what> <got> <want>
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n  got:  %s\n  want: %s\n' "$1" "$2" "$3"
  fi
}

chk "a plain line is itself"          "$(json_text 'one line')"        'one line'
chk "nothing is nothing"              "$(json_text '')"                ''
chk "a line break is \\n"             "$(json_text $'a\nb')"           'a\nb'
chk "an empty line between is kept"   "$(json_text $'a\n\nb')"         'a\n\nb'
chk "a quote is escaped"              "$(json_text 'say "x"')"         'say \"x\"'
chk "a backslash is doubled"          "$(json_text 'C:\Users\x')"      'C:\\Users\\x'
chk "a backslash before a quote"      "$(json_text '\"')"              '\\\"'
chk "a typed \\n stays two letters"   "$(json_text 'a\nb')"            'a\\nb'
chk "a tab is \\t"                    "$(json_text $'a\tb')"           'a\tb'
chk "Windows line ends lose the CR"   "$(json_text $'a\r\nb\r')"       'a\nb'
chk "an escape character is dropped"  "$(json_text $'a\033[31mb')"     'a[31mb'
chk "Korean and brackets pass"        "$(json_text '「분류 전」 — 카드')"   '「분류 전」 — 카드'

# The case this file exists for: what the board's checker really prints.
complaint=$'분류 전에 하루 넘게 남은 카드: F-282\n⇒ 읽고 한 줄 적어 옮기세요: {"id":…, "at":"<대분류>", "note":…}'
chk "the checker's complaint, blocked" "$(say_block "$complaint")" \
  '{"decision":"block","reason":"분류 전에 하루 넘게 남은 카드: F-282\n⇒ 읽고 한 줄 적어 옮기세요: {\"id\":…, \"at\":\"<대분류>\", \"note\":…}"}'

chk "context names its event" "$(say_context UserPromptSubmit $'on\n"now"')" \
  '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"on\n\"now\""}}'
chk "a refusal of a tool call" "$(say_deny 'no `git add -A`')" \
  '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"no `git add -A`"}}'
chk "each says exactly one line" "$(say_block $'a\nb' | wc -l | tr -d ' ')" '1'

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
