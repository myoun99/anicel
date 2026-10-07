#!/usr/bin/env bash
# Stop hook: a memory file two machines changed at once must not sit there
# unread.
#
# The memory folder is one both machines see (유저 2026-10-07: 「드롭박스에
# 두기로 할게」, card work-runs-on-the-surface-too), kept the same by a file
# sync. A sync cannot merge: when two machines change one file before either
# has seen the other's change, it keeps BOTH — one under the file's name,
# the other beside it as 「<name> (<machine>'s conflicted copy <date>).md」 —
# and says nothing. A memory in a file no index names is a memory nobody
# reads, and the index itself is the file both machines write most.
#
# So this looks, at the end of every turn. Every memory file is named in
# kebab-case, which a conflicted copy never is: its name holds spaces and
# parentheses in whatever language the sync client speaks. The test is the
# SHAPE of the name, not the client's words for it.
#
#   bash guard_memory_conflicts.sh <the memory folder>
#
# ⚠️The top of the folder only — where the index and every topic file are.
# A look into the folders of attached material would cost a process on
# every turn of every session.
#
# THIS COSTS NO PROCESS WHEN THERE IS NOTHING: the look is two globs.
# Fails OPEN — a folder that is not there (the sync client not set up yet)
# is not a conflict.
set -u

DIR="${1:-}"
[ -d "$DIR" ] || exit 0

NL='
'
found=""
for f in "$DIR"/*" "* "$DIR"/*"("*; do
  [ -e "$f" ] || continue
  name="${f##*/}"
  case "$NL$found" in *"$NL$name$NL"*) continue ;; esac
  found="$found$name$NL"
done
[ -z "$found" ] && exit 0

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hook_says.sh"
say_block "메모리 폴더에 두 기계가 같은 파일을 동시에 고쳐서 생긴 사본이 있습니다:
${found}동기화는 합치지 못해서 둘 다 남깁니다 — 원래 이름의 파일이 한쪽 것, 이 사본이 다른 쪽 것입니다.
두 파일을 다 읽고 합친 내용을 **원래 이름의 파일**에 쓴 뒤 사본을 지우세요. ⛔사본을 그냥 지우지 마세요: 다른 기계의 세션이 적은 메모가 사라집니다."
