#!/usr/bin/env bash
# UserPromptSubmit hook: arms and disarms 자율진행.
#
# The user says 자율진행 and means it: keep going as far as the work actually
# goes. What happens instead is a turn that ends with "이어서 하겠습니다" and
# nothing following, because when a turn ends nobody is watching -- the same
# failure the PR gate exists for, in a different costume.
#
# A rule cannot fix that: the failure IS the intention evaporating at the turn
# boundary. So the intention is written down here, the moment it is spoken, and
# `autorun_gate.sh` refuses to let a turn end while it stands.
#
# WHY A HOOK AND NOT ME REMEMBERING: making the assistant notice the word and
# create the marker puts the fix inside the thing that is failing. This runs on
# the user's keystroke, before any of that.
#
# THIS ONE HAS NO `if` FILTER TO HIDE BEHIND -- UserPromptSubmit fires on every
# message the user sends, so its cost is paid on every message. Measured at
# 453ms when it did its work with sed and grep, against a 152ms floor that is
# just bash starting on Windows. Hence the glob fast path below: a prompt with
# no 자율진행 in it spawns nothing at all and pays only the floor. The careful
# matching still runs, but only for prompts that mention it.
#
# 🚨THE MARKER IS PER SESSION (2026-09-15) -- `autorun_gate.sh` says why.
# 「자율진행」 arms the session it was said to (`.autorun.<session id>`), and
# 「자율진행 그만」 disarms that session -- plus a bare `.autorun` if one
# stands, because that one has no owner and a user saying stop is the only
# signal it will ever get.
# 🏠IN THE REPOSITORY SINCE 2026-10-07, and handed its folder. These hooks
# sat in the memory folder — outside the repository, with no history — and
# found the board and the flags by sitting beside them. A second machine has
# to run the same ones (유저: 「훅 보관위치 알아서 권장대로해줘」 = the
# repository, card work-runs-on-the-surface-too), so the script lives here
# and the BOARD FOLDER of the machine it runs on is its argument: the local
# folder that holds that machine's flags and exes, and on the machine that
# holds the board, the records. `tool/session_hooks/install.dart` writes the
# settings entry that passes it.
set -u

payload=$(cat)

# Fast path, no subprocesses: almost every prompt leaves here.
case "$payload" in
  *자율진행*|*'자율 진행'*) ;;
  *) exit 0 ;;
esac

MEM="${1:-}"
[ -d "$MEM" ] || exit 0
LEGACY="$MEM/.autorun"
sid=$(printf '%s' "$payload" \
  | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
if [ -n "$sid" ]; then
  FLAG="$MEM/.autorun.$sid"
else
  FLAG="$LEGACY"
fi

# Disarm is checked first: "자율진행 그만" contains "자율진행". The window is
# deliberately narrow -- 종료 must follow within a few non-Hangul characters,
# so "자율진행으로 이 작업 종료까지 해줘" arms rather than disarms.
if printf '%s' "$payload" \
    | grep -qE '자율[[:space:]]*진행[^가-힣]{0,4}(종료|중단|해제|그만|끄|off|OFF)'; then
  [ -f "$FLAG" ] || [ -f "$LEGACY" ] || exit 0
  rm -f "$FLAG" "$LEGACY"
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' \
    "⏹ 자율진행을 껐습니다. 이제 턴을 끝내도 막지 않습니다."
  exit 0
fi

[ -f "$FLAG" ] && exit 0
printf 'armed\n' > "$FLAG"
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' \
  "▶ 자율진행이 켜졌습니다. 남은 일이 있는 한 턴이 끝나지 않습니다. 진짜로 다 끝났을 때만 '$FLAG' 를 지우고 끝내세요 — 「이어서 하겠습니다」라고 쓰고 끝내는 것은 이제 불가능합니다."
