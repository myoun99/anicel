#!/usr/bin/env bash
# PostToolUse guard: the memory index has a hard ceiling and keeps hitting it.
#
# Above 24KB the index is not read at all, and it has crossed that line FIVE
# times -- 31KB, 19.9, 20, 30.7, 24.7, 12.2 -- every time because a session
# appended to its own line and never measured. The failure is not carelessness,
# it is that nobody looks at a file's size while writing prose into it.
#
# So this looks at the moment prose goes in. It does not block: growing the
# index is often correct, and the right response is to find a line to cut,
# which is a judgement call. It only makes the number impossible not to see.
#
# THIS COSTS NOTHING WHEN IT DOES NOT FIRE: the settings entry filters on the
# MEMORY.md path, so ordinary edits never spawn it.
#
# 🏠IN THE REPOSITORY SINCE 2026-10-07 (유저: 「훅 보관위치 알아서
# 권장대로해줘」, card work-runs-on-the-surface-too), and handed the index
# it measures: the memory folder is one both machines see, in a place each
# machine names for itself, so the settings entry passes the path of the
# MEMORY.md its own `if` watches.
set -u

INDEX="${1:-}"
CEILING=24576
WARN=20480

[ -f "$INDEX" ] || exit 0
size=$(wc -c < "$INDEX" 2>/dev/null) || exit 0
[ "$size" -lt "$WARN" ] && exit 0

if [ "$size" -ge "$CEILING" ]; then
  msg="🚨 MEMORY.md 가 ${size}B — 24576B 를 넘었습니다. 이 크기면 색인이 통째로 안 읽힙니다. 늘린 줄을 이 턴에서 도로 줄이세요(다섯 번 재발한 병입니다)."
else
  msg="⚠️ MEMORY.md 가 ${size}B — 한계(24576B)까지 $((CEILING - size))B 남았습니다. 지금 줄일 자리를 찾아두는 게 쌉니다."
fi

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hook_says.sh"
say_context PostToolUse "$msg"
