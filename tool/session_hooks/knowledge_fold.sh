#!/usr/bin/env bash
# Stop hook, for as long as the memory folder is in two places.
#
# 2026-10-07: the knowledge files moved to a folder both machines see (유저:
# 「드롭박스에 두기로 할게」, card work-runs-on-the-surface-too). A session's
# memory folder is fixed when the session starts, so the ones running that
# day go on reading and writing the OLD folder until they are started
# again. Until then this keeps the two the same: a file changed on one side
# since the two last agreed is copied to the other.
#
#   bash knowledge_fold.sh <old folder> <new folder>        the hook
#   bash knowledge_fold.sh <old folder> <new folder> now    carry, and wait
#
# (It sat in the old folder and found it by sitting there until the hooks
# moved into the repository the same day; the old folder is its first
# argument now. Only the machine that HAD an old folder runs it.)
#
# ⏱OFF THE TURN'S CLOCK. Listing two folders costs about a second of
# process starts on this machine, and a Stop hook is paid at the end of
# every turn of every session. So the hook starts the carry behind itself
# and leaves at once; a carry that met a both-sides change writes what it
# has to say into `.knowledge-fold.says`, and while that file stands the
# hook carries in the foreground instead and says it.
#
# ⛔IT NEVER CHOOSES BETWEEN TWO CHANGES. A file changed on BOTH sides is
# left as it is on both and named in a block, so the session that sees it
# reads both and writes one — a newer clock is not a better memory.
#
# ⛔IT NEVER DELETES. A file removed on one side is MOVED out of the other
# into `.knowledge-gone/` here, so the two agree and nothing is lost: a
# memory deleted on purpose and a file that vanished for another reason
# look the same from this script.
#
# What stays in this folder and is never carried: the board and its
# screenshots, the two exes with their stamps, the hook scripts, and every
# dot-file (the flags) — those belong to this machine.
#
# Fails OPEN everywhere: a turn must never be held by a carry that could
# not run. The only thing it blocks on is the both-sides case above.
#
# 🪦WHEN NO SESSION FROM BEFORE THE MOVE IS LEFT: delete this file and the
# `--old-memory` it is installed by, `.knowledge-fold*` and
# `.knowledge-gone/` in the old folder — and then the knowledge files there.
set -u

# The hook form, before anything is worked out: every fork here is paid by
# every turn.
if [ "${3:-}" != "now" ] && [ ! -s "${1:-}/.knowledge-fold.says" ]; then
  (bash "${BASH_SOURCE[0]}" "${1:-}" "${2:-}" now >/dev/null 2>&1 &)
  exit 0
fi

OLD="${1:-}"
NEW="${2:-}"
[ -d "$OLD" ] && [ -d "$NEW" ] || exit 0
OLD="$(cd "$OLD" && pwd)"
NEW="$(cd "$NEW" && pwd)"
SEEN="$OLD/.knowledge-fold"
SAYS="$OLD/.knowledge-fold.says"
GONE="$OLD/.knowledge-gone"
LOCK="$OLD/.knowledge-fold.lock"


# The knowledge files of one side, NUL-separated and relative. The old side
# is this folder minus what belongs to the machine; the new side holds
# nothing else, bar what the sync client drops at its top.
old_files() {
  (cd "$OLD" && {
    find . -maxdepth 1 -type f ! -name '.*' ! -name 'board.jsonl' \
      ! -name 'board_check.exe*' ! -name 'board_server.exe*' ! -name '*.sh' \
      -print0
    find . -mindepth 2 -type f ! -path './.*' ! -path './board-shots/*' \
      -print0
  })
}
new_files() {
  (cd "$NEW" && {
    find . -maxdepth 1 -type f ! -name '.*' ! -name 'desktop.ini' -print0
    find . -mindepth 2 -type f ! -path './.*' -print0
  })
}

# Fast path: each side holds as many files as the two last agreed on, and
# none of them was written or put there since. Almost every turn ends here.
# ⚠️`-cnewer` beside `-newer`: a file the sync client brings in keeps the
# modification time it had on the machine that wrote it, which can be
# OLDER than the last agreement — when it arrived is its change time.
count() { tr -cd '\0' | wc -c; }
if [ -f "$SEEN" ]; then
  agreed=$(($(wc -l < "$SEEN")))
  if [ "$(old_files | count)" -eq "$agreed" ] \
    && [ "$(new_files | count)" -eq "$agreed" ]; then
    moved=$( {
      find "$OLD" -maxdepth 1 -type f \( -newer "$SEEN" -o -cnewer "$SEEN" \) \
        ! -name '.*' ! -name 'board.jsonl' ! -name 'board_check.exe*' \
        ! -name 'board_server.exe*' ! -name '*.sh' -print -quit
      find "$OLD" -mindepth 2 -type f \( -newer "$SEEN" -o -cnewer "$SEEN" \) \
        ! -path "$OLD/.*" ! -path "$OLD/board-shots/*" -print -quit
      find "$NEW" -type f \( -newer "$SEEN" -o -cnewer "$SEEN" \) \
        ! -path "$NEW/.*" ! -name 'desktop.ini' -print -quit
    } 2>/dev/null | head -n 1)
    [ -z "$moved" ] && exit 0
  fi
fi

# One carry at a time: every session's Stop runs this, often together. A
# lock older than two minutes is one a killed run left behind.
if [ -d "$LOCK" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then
  rmdir "$LOCK" 2>/dev/null
fi
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

TMP="$(mktemp -d 2>/dev/null)" || exit 0
trap 'rm -rf "$TMP"; rmdir "$LOCK" 2>/dev/null' EXIT

# `<sha1>\t<path>` a line. Taken BEFORE the stamp below, so a write that
# lands while this runs is newer than the stamp and is seen next time.
sums() { xargs -0 -r sha1sum 2>/dev/null | sed 's/^\([0-9a-f]\{40\}\) [ *]/\1\t/'; }
touch "$TMP/stamp"
old_files | (cd "$OLD" && sums) > "$TMP/old"
new_files | (cd "$NEW" && sums) > "$TMP/new"
if [ -f "$SEEN" ]; then
  cp "$SEEN" "$TMP/seen"
  touch -r "$SEEN" "$TMP/prior"
else
  : > "$TMP/seen"
  touch -d 2000-01-01 "$TMP/prior"
fi

# One verdict a path: what each side holds now against what both held when
# they last agreed (empty = no such file).
awk -F'\t' '
  FILENAME == ARGV[1] { seen[$2] = $1; all[$2]; next }
  FILENAME == ARGV[2] { old[$2] = $1; all[$2]; next }
  { new[$2] = $1; all[$2] }
  END {
    for (p in all) {
      s = seen[p]; o = old[p]; n = new[p]
      if (o == n)                        v = (o == "" ? "none" : "same")
      else if (n == s && o != "")        v = "old-to-new"
      else if (o == s && n != "")        v = "new-to-old"
      else if (o == "" && n == s)        v = "left-old"
      else if (n == "" && o == s)        v = "left-new"
      else                               v = "both"
      print v "\t" (o == "" ? "-" : o) "\t" (n == "" ? "-" : n) "\t" \
        (s == "" ? "-" : s) "\t" p
    }
  }
' "$TMP/seen" "$TMP/old" "$TMP/new" > "$TMP/verdicts"

carry() {  # carry <from root> <to root> <path>
  mkdir -p "$(dirname "$2/$3")" && cp -p "$1/$3" "$2/$3"
}
put_away() {  # put_away <root> <path>
  mkdir -p "$(dirname "$GONE/$2")" && mv -f "$1/$2" "$GONE/$2"
}

: > "$TMP/seen.next"
both=""
while IFS=$'\t' read -r verdict o n s path; do
  case "$verdict" in
    same)
      printf '%s\t%s\n' "$o" "$path" >> "$TMP/seen.next" ;;
    old-to-new)
      if carry "$OLD" "$NEW" "$path"; then
        printf '%s\t%s\n' "$o" "$path" >> "$TMP/seen.next"
      elif [ "$s" != "-" ]; then
        printf '%s\t%s\n' "$s" "$path" >> "$TMP/seen.next"
      fi ;;
    new-to-old)
      if carry "$NEW" "$OLD" "$path"; then
        printf '%s\t%s\n' "$n" "$path" >> "$TMP/seen.next"
      elif [ "$s" != "-" ]; then
        printf '%s\t%s\n' "$s" "$path" >> "$TMP/seen.next"
      fi ;;
    left-old)
      put_away "$NEW" "$path" \
        || printf '%s\t%s\n' "$s" "$path" >> "$TMP/seen.next" ;;
    left-new)
      put_away "$OLD" "$path" \
        || printf '%s\t%s\n' "$s" "$path" >> "$TMP/seen.next" ;;
    both)
      [ "$s" != "-" ] && printf '%s\t%s\n' "$s" "$path" >> "$TMP/seen.next"
      both="$both${path#./}
" ;;
  esac
done < "$TMP/verdicts"

sort -t$'\t' -k2 "$TMP/seen.next" > "$SEEN.next" && mv -f "$SEEN.next" "$SEEN"
# The agreement is as old as the look it was made from, not as this write.
# ⚠️And no newer than before while a both-sides change stands: the fast
# path asks 「anything since the agreement」, and a change that is still
# waiting for somebody has to keep answering yes — said once and then
# quiet, it would simply stay split.
if [ -z "$both" ]; then
  touch -r "$TMP/stamp" "$SEEN"
  rm -f "$SAYS"
  exit 0
fi
touch -r "$TMP/prior" "$SEEN"
OLDW="$(cd "$OLD" && pwd -W)"
NEWW="$(cd "$NEW" && pwd -W)"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hook_says.sh"
say_block "메모리 파일이 두 자리에서 따로 바뀌었습니다(옮기는 중이라 자리가 둘입니다):
${both}옛 자리: $OLDW
새 자리: $NEWW
어느 쪽도 덮지 않았습니다. 두 파일을 다 읽고 합친 내용을 **두 자리에 같은 바이트로** 쓰세요 — 그러면 다음 턴부터 조용해집니다. ⛔한쪽을 그냥 다른 쪽으로 복사하지 마세요: 다른 세션이 적은 메모가 사라집니다." | tee "$SAYS"
