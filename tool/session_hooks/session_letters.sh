#!/usr/bin/env bash
# What other sessions left for this one, put in front of it — at the start of
# a turn and at its end.
#
#   bash session_letters.sh <board folder> <board address> <start|stop>
#
# 유저 2026-10-07 (the-board-is-one-server-for-both-machines-Q2: 「글은
# 카드의 흐름에 적고, 「전달」 보기는 그것을 모아 보여 주기만 한다」 — 그
# 안의 문장: 「세션은 턴이 시작하고 끝날 때 자기 앞의 안 읽은 줄을 훅이 보여
# 준다」). Two machines run sessions under two accounts, and a session's own
# messages do not cross accounts; the board is the one thing both reach. A
# session leaves a line for another by naming its 담당 (`"to"`), and this is
# the half that delivers it.
#
# ⚠️IT CANNOT WAKE A SESSION THAT IS DOING NOTHING. A hook runs when a turn
# starts or ends; a letter left for an idle session waits for its next turn.
#
# WHO THIS SESSION IS: the 담당 it registered with `tool/board_me.dart`,
# kept in the board folder under `.session-names/<session id>` — a fact of
# this machine, never on the board. A session that registered nothing is
# told once how to, at the start of a turn, and is otherwise left alone.
#
# IT ASKS THE SERVER, never the records: taking a letter marks it read, and
# the server is the one hand that writes the board. The letters come back as
# text and are marked by that same request (`takeLetters` says why it is one
# act). The door's secret goes to curl on its standard input, not on its
# command line — a command line is something other processes can read.
#
# THIS RUNS ON EVERY PROMPT, so a session with no name costs no process: the
# id is cut out of the payload and the name file is read by the shell itself.
# Fails OPEN everywhere — no folder, no name, no server, no curl: a turn is
# never held by a letter that could not be fetched.
set -u

MEM="${1:-}"
BOARD="${2:-}"
WHEN="${3:-start}"
[ -d "$MEM" ] || exit 0
[ -n "$BOARD" ] || exit 0

payload=$(cat)
case "$payload" in
  *'"session_id"'*) ;;
  *) exit 0 ;;
esac
sid="${payload#*\"session_id\"}"
sid="${sid#*\"}"
sid="${sid%%\"*}"
[ -n "$sid" ] || exit 0

NAMES="$MEM/.session-names"
name=""
if [ -f "$NAMES/$sid" ]; then
  IFS= read -r name < "$NAMES/$sid" || true
  name="${name%$'\r'}"
fi

if [ -z "$name" ]; then
  # Said once a session, and only where a turn begins: an end is no place
  # to learn a new thing.
  [ "$WHEN" = start ] || exit 0
  [ -e "$NAMES/.asked.$sid" ] && exit 0
  mkdir -p "$NAMES" 2>/dev/null && : > "$NAMES/.asked.$sid"
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hook_says.sh"
  say_context UserPromptSubmit "📨 이 세션은 보드에 담당 이름을 등록하지 않았습니다 — 다른 세션이 이 세션 앞으로 남긴 전달을 받으려면 한 번 등록하세요:
  dart run tool/board_me.dart <담당 이름>   (예: 보드/통합 · 타임라인/콘티 · 캔버스 베이스 패널)
담당이 없는 세션이면 그대로 두면 됩니다. 이 안내는 다시 나오지 않습니다."
  exit 0
fi

command -v curl >/dev/null 2>&1 || exit 0
secret=""
if [ -s "$MEM/.board-token" ]; then
  IFS= read -r secret < "$MEM/.board-token" || true
  secret="${secret%$'\r'}"
fi
text=$(
  {
    [ -n "$secret" ] && printf 'header = "Authorization: Bearer %s"\n' "$secret"
    printf 'url = "%s/letters/take"\n' "${BOARD%/}"
  } | curl -s -f -m 5 -X POST -G --data-urlencode "to=$name" -K - 2>/dev/null
) || exit 0
[ -n "$text" ] || exit 0

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hook_says.sh"
if [ "$WHEN" = stop ]; then
  say_block "$text

(턴을 끝내기 전에 온 전달입니다 — 읽고, 할 일이 있으면 하고, 없으면 그대로 끝내면 됩니다.)"
else
  say_context UserPromptSubmit "$text"
fi
