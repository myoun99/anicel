#!/usr/bin/env bash
# SessionStart hook: make sure the board is up. Never takes it down.
#
# Asymmetric on purpose. Starting it is safe to repeat -- if the port is
# already listening there is nothing to do. STOPPING it is not: parallel
# sessions share one server, so an end-of-session kill would pull the board
# out from under another session, and the hands-on checklist is exactly the
# thing you fill in while testing the app with no session open at all. The
# server costs 14 MB and zero CPU while nobody looks at it, so the shutdown
# logic would cost more than the thing it turns off. It dies at reboot.
#
# It also rebuilds when the source no longer matches the binary. Without that,
# a fix to board_server.dart would sit in the repo while the machine kept
# serving the old build -- the exact "the instrument is lying" shape this
# project keeps stepping in.
#
# 🚨★★★IT ASKED mtime UNTIL 2026-08-31, AND mtime UNDER-REBUILT. 유저 asked
# why a card was 착수 가능 when its 남은 것 was not last; that rule had merged
# twelve minutes earlier (#1395) and the screen was serving a build from
# before it. The source in the main checkout read 16:57:11 and the exe
# 16:57:44 -- OLDER source, NEWER content, because git does not rewrite a
# path whose content it is already holding. So the stat said "fresh" and
# nothing rebuilt, for hours.
#
# ⛔The old note here chose mtime knowing the risk and picked the wrong side
# of its own argument: 「over-rebuilding wastes ten seconds, under-rebuilding
# serves stale code, and only one of those is recoverable by noticing」 -- and
# then took the one that under-rebuilds. A hash of the source, recorded beside
# the exe at build time, does neither: it cannot miss a change and it cannot
# invent one. It costs one sha1 of a 100 KB file.
#
# It fails OPEN everywhere. A session must never fail to start because the
# board would not come up.
# 🏠IN THE REPOSITORY SINCE 2026-10-07, and handed its folder. These hooks
# sat in the memory folder — outside the repository, with no history — and
# found the board and the flags by sitting beside them. A second machine has
# to run the same ones (유저: 「훅 보관위치 알아서 권장대로해줘」 = the
# repository, card work-runs-on-the-surface-too), so the script lives here
# and the BOARD FOLDER of the machine it runs on is its argument: the local
# folder that holds that machine's flags and exes, and on the machine that
# holds the board, the records. `tool/session_hooks/install.dart` writes the
# settings entry that passes it.
#
# ⚠️ON A MACHINE THAT DOES NOT HOLD THE BOARD (a clone that named itself,
# `git config anicel.machine …` — see tool/lane.sh) there is no server to
# bring up: the board is one file on one machine and that machine serves
# it. What this does there is keep the GATE's exe built, which asks that
# server.
set -u

MEM="${1:-}"
[ -d "$MEM" ] || exit 0
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -W)"
AWAY="$(git -C "$REPO" config --get anicel.machine 2>/dev/null || true)"
SRC="$REPO/tool/board_server.dart"
EXE="$MEM/board_server.exe"
RECORDS="$MEM/board.jsonl"
# Where the installer puts gh on Windows; anywhere else, wherever PATH has it.
GH="C:/Program Files/GitHub CLI/gh.exe"
[ -x "$GH" ] || GH="$(cygpath -m "$(command -v gh 2>/dev/null)" 2>/dev/null)"
PORT=4321

listening() {
  powershell -NoProfile -Command \
    "if (Get-NetTCPConnection -LocalPort $PORT -State Listen -EA 0) {'yes'}" \
    2>/dev/null | tr -d '\r '
}

stop() {
  local pid
  pid=$(powershell -NoProfile -Command \
    "(Get-NetTCPConnection -LocalPort $PORT -State Listen -EA 0).OwningProcess" \
    2>/dev/null | tr -d '\r ')
  [ -n "$pid" ] && powershell -NoProfile -Command \
    "Stop-Process -Id $pid -Force -EA 0" >/dev/null 2>&1
}

# ⚠️ONE READER FOR 「이 exe 가 이 소스인가」 -- this function, used for both
# binaries AND by the server itself, which compares the same copy to decide
# whether a refresh should bring new code. A BYTE COPY, not a hash: the server
# has no hashing package and this needs no maintaining, and the copy doubles
# as 「what this exe was built from」 if anyone ever has to look.
# 🚨★★★AN EXE IS MADE OF MORE THAN ITS ENTRY FILE (#1434).
# ⛔This compared the entry file ALONE, so a change to `board_model.dart` --
# which BOTH binaries compile in -- rebuilt neither. 🧪#1433 changed only the
# model and board_server.exe went on serving the previous one; nothing
# anywhere would have noticed.
# ⚠️ONE LEVEL is the whole graph: each entry imports board_model.dart and that
# imports nothing of ours. DERIVED, not listed -- a listed name is a word
# somebody has to remember.
# ⛔THE SAME RULE LIVES IN board_server.dart (`sourcesOfEntry`), because the
# server compares this stamp itself between hook runs. Change both or neither.
# 🚨AND THE STAMP HAS A NEW NAME (.srcs). `.src` held a copy of the ENTRY
# file; this holds the concatenation. They cannot share a path: the writer
# (this file) and the reader (the repo) cannot land in the same instant, and
# I proved it by taking the live board down -- the old exe found the
# concatenation different on every request and exited every time.
sources_of() {
  dir="$(dirname "$1")"
  { printf '%s\n' "$1"
    grep -o "^import '[A-Za-z0-9_]*\.dart'" "$1" 2>/dev/null \
      | sed "s|^import '|$dir/|; s|'$||"
  } | sort -u
}
stamp_of() { sources_of "$1" | tr '\n' '\0' | xargs -0 cat 2>/dev/null; }
built_from() { [ -f "$2" ] && stamp_of "$1" | cmp -s - "$2"; }

# Rebuild when the recorded source hash is not this source. Windows will not
# let us overwrite a running exe, so the old one has to come down first --
# which is what we want anyway: the point of rebuilding is to serve the new
# code. ⚠️The stamp is written only after a compile that EXITED 0, so a
# failed build leaves the old stamp and is retried next turn instead of being
# recorded as done.
if [ -z "$AWAY" ] && [ -f "$SRC" ] && command -v dart >/dev/null 2>&1; then
  if [ ! -f "$EXE" ] || ! built_from "$SRC" "$EXE.srcs"; then
    stop
    if (cd "$(dirname "$SRC")/.." && dart compile exe "$SRC" -o "$EXE") >/dev/null 2>&1
    then stamp_of "$SRC" > "$EXE.srcs"; fi
  fi
fi

# The BOARD'S GATE, built the same way and for the same reason: `dart run`
# costs 1.8s of JIT on every turn, which is exactly what retired the last
# gate-side dart check (see board_gate.sh's header). An exe starts in tens of
# milliseconds, so the check can run on every Stop without anyone noticing.
CHECK_SRC="$REPO/tool/board_check.dart"
CHECK_EXE="$MEM/board_check.exe"
# ⚠️Same reader: the gate's own binary went stale the same way, and a gate
# built from last week's rules is worse than no gate -- it answers with
# confidence.
if [ -f "$CHECK_SRC" ] && command -v dart >/dev/null 2>&1; then
  if [ ! -f "$CHECK_EXE" ] || ! built_from "$CHECK_SRC" "$CHECK_EXE.srcs"; then
    if (cd "$(dirname "$CHECK_SRC")/.." \
        && dart compile exe "$CHECK_SRC" -o "$CHECK_EXE") >/dev/null 2>&1
    then stamp_of "$CHECK_SRC" > "$CHECK_EXE.srcs"; fi
  fi
fi

[ -z "$AWAY" ] || exit 0
[ -f "$EXE" ] || exit 0
[ "$(listening)" = "yes" ] && exit 0

# 🆕2026-10-07 — THE DOOR TO THE HOME NETWORK. 유저: 「서피스는 집에서만
# 쓸거야. 컴은 랜선 서피스들은 같은 모뎀?에서 흘러오는 와이파이」 (card
# the-board-is-one-server-for-both-machines, 답 「집 네트워크에서 보드
# 서버를 연다」). The server listens beyond this machine only together with a
# secret (tool/board_door.dart), and the secret is made HERE, once: 24 random
# bytes as 48 hex digits, in a dot-file beside the records — a flag of this
# machine, which no sync folder and no repository ever holds. ⛔Never print
# it: this script's output lands in hook logs and transcripts.
# ⚠️An exe from before the door ignores the two flags (it reads only the
# names it knows) and goes on listening on loopback, so this script and the
# code it launches may arrive in either order.
# ⚠️The firewall rule is the user's (`Anicel board`, TCP 4321, LocalSubnet —
# made by hand 2026-10-07; a session does not change security settings).
TOKEN="$MEM/.board-token"
if [ ! -s "$TOKEN" ]; then
  (umask 077; head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$TOKEN") \
    2>/dev/null
fi

# Start-Process, not `&`: the child has to outlive this shell.
# Each value carries its own quotes. `Start-Process -ArgumentList` joins the
# array with spaces and does NOT quote anything, so a path containing a space
# arrives at the exe as several arguments -- which is how `--gh` spent an
# evening receiving "C:/Program" and the board rendered its PR sections empty
# while returning a perfectly healthy 200.
launch() {
  powershell -NoProfile -Command "Start-Process -FilePath '$EXE' -ArgumentList \
'--records','\"$RECORDS\"','--gh','\"$GH\"','--git','\"$REPO\"','--port','$PORT','--open-to','lan','--token-file','\"$TOKEN\"' -WindowStyle Hidden" \
    >/dev/null 2>&1 || true
}

# Launch, then CONFIRM, then launch once more. The first attempt after a
# rebuild lost a race with the freshly written exe and failed silently -- the
# script reported success and no server was running. Each `listening` call
# costs a couple of hundred milliseconds, which doubles as the settle time.
up() {
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ "$(listening)" = "yes" ] && return 0
  done
  return 1
}

launch
up && exit 0
launch
up && exit 0

# Never silent about failing: a board that did not come up must leave a trace,
# or the next person to look assumes it is fine and finds an empty bookmark.
echo "$(date '+%F %T') board_up: server did not come up on port $PORT" \
  >> "$MEM/.board_up.log"
exit 0
