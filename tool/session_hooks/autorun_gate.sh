#!/usr/bin/env bash
# Stop hook: while 자율진행 stands, a turn does not end by drifting to a halt.
#
# The user's complaint, verbatim: "자꾸 자율진행하라고해도 ai가 마지막에 작업
# 끝나고 이어서 하겠습니다 라고 말해놓고 이어서 작업 안하는경우가 너무많거든?"
# That is exactly right, and it is not forgetfulness in the ordinary sense --
# writing "I'll continue" and ending the turn FEELS like continuing. Nothing
# contradicts it until the user comes back and finds nothing happened.
#
# So stopping becomes a deliberate act instead of a default. While the marker
# stands, this blocks; to finish, the marker must be deleted, which is a thing
# someone has to decide to do. Same shape as `.gate-ack` on the PR gate: doing
# it is fine, walking away without doing it is what gets caught.
#
# THE CAP IS A CHECKPOINT, NOT A KILL SWITCH. After MAX turns it stops
# blocking, but it does not silently release -- it demands a report and an
# explicit ask. A cap that quietly ends autonomy would reproduce the exact
# failure this exists to prevent.
#
# Fails OPEN on anything unexpected: a turn must never be held hostage by a
# gate that cannot do its own job.
#
# 🚨ONE SESSION'S 자율진행 BELONGS TO THAT SESSION (2026-09-15). The marker
# used to be ONE file for the whole memory folder, and every session on this
# machine shares that folder. The day the user split the board between
# sessions, 「완주할때까지 자율진행」 said to one of them armed a marker that
# blocked the OTHER sessions' stops as well, and each of those blocked stops
# appended a `turn` to that one session's cap: several sessions working a day
# spend its 300 turns for it, and the cap then ends the autonomy the user
# asked for in a session that was still working. The hooks are handed the
# session id on stdin, so the marker is `.autorun.<session id>` now, and only
# that session's stops read it or count against it.
# ⚠️A bare `.autorun` -- armed before this, or by a payload that carried no
# session id -- still blocks EVERY session, exactly as it always did: it has
# no owner to ask, and letting it go quietly would end somebody's run.
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

MEM="${1:-}"
[ -d "$MEM" ] || exit 0

# Fast path, no subprocesses: with no marker of any kind there is nothing to
# resolve, and that is almost every turn.
set -- "$MEM"/.autorun*
[ -e "$1" ] || exit 0

payload=$(cat)
sid=$(printf '%s' "$payload" \
  | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
FLAG="$MEM/.autorun"
if [ -n "$sid" ] && [ -f "$MEM/.autorun.$sid" ]; then
  FLAG="$MEM/.autorun.$sid"
fi
# The cap is a backstop against a loop that neither works nor exits -- it is
# NOT a work budget. 2026-08-25 it was 40, which was less than one item per
# turn against a 52-card list; the user asked for it to stop stopping. Sized so
# a full day of real work never reaches it: at ~5 turns per card that is ten
# times the list. The genuine backstop against a runaway is the usage limit.
MAX=300

[ -f "$FLAG" ] || exit 0
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hook_says.sh"

turns=$(($(wc -l < "$FLAG" 2>/dev/null || echo 1)))
if [ "$turns" -gt "$MAX" ]; then
  rm -f "$FLAG"
  say_block "자율진행이 ${MAX}턴에 도달했습니다. 표식은 지웠으니 이 턴은 끝낼 수 있습니다.
⛔단 조용히 끝내지 마세요 — 유저에게 ①지금까지 무엇을 끝냈는지 ②무엇이 남았는지 ③계속할지를 물으세요. 캡이 자율진행을 소리 없이 끄는 것은 이 게이트가 막으려던 바로 그 실패입니다."
  exit 0
fi

printf 'turn\n' >> "$FLAG"
say_block "▶ 자율진행 중입니다(${turns}/${MAX}턴). 「이어서 하겠습니다」라고 쓰고 턴을 끝내는 것은 아무것도 안 하는 것입니다 — 유저가 이걸로 여러 번 발이 묶였습니다.
지금 셋 중 하나를 하세요:
1) 남은 일이 있으면 지금 하세요. 보고는 다 하고 나서 한 번에.
2) 유저의 답이 있어야만 진행되는 것뿐이면, 그 질문을 구체적으로 적고 '$FLAG' 를 지우세요.
3) 남은 것이 CI·빌드 결과 대기뿐이면, **감시가 실제로 걸려 있는지 확인한 뒤** '$FLAG' 를 지우고 무엇을 기다리는지 말하세요. 감시가 없으면 그건 대기가 아니라 방치입니다 — 먼저 거세요.
4) 진짜로 전부 끝났으면 '$FLAG' 를 지우고 끝내세요.
⛔「다음 세션에」·「나중에」는 어느 것도 아닙니다."
