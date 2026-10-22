# Sourced, not run: what an exe built from a tool/ entry is made of.
# Read by `tool/session_hooks/board_up.sh` (the board's two exes) and
# `tool/run.sh` (any tool, built once per machine).
#
# ⚠️ONE READER FOR 「이 exe 가 이 소스인가」 -- this file, used for every
# binary AND by the board server itself, which compares the same copy to
# decide whether a refresh should bring new code. A BYTE COPY, not a hash:
# the server has no hashing package and this needs no maintaining, and the
# copy doubles as 「what this exe was built from」 if anyone ever has to look.
# 🚨★★★AN EXE IS MADE OF MORE THAN ITS ENTRY FILE (#1434).
# ⛔This compared the entry file ALONE, so a change to `board_model.dart` --
# which BOTH board binaries compile in -- rebuilt neither. 🧪#1433 changed
# only the model and board_server.exe went on serving the previous one;
# nothing anywhere would have noticed.
# 🆕EVERY LEVEL, NOT ONE (2026-10-18, card tests-crowd-the-machine). One
# level was the whole graph only for the two board exes, and `board_door.dart`
# had to promise to import nothing of ours to keep it so. The third reader,
# `tool/run.sh`, builds any tool — and `board_ack` imports `board_check`,
# which imports `board_model`. The imports are followed until nothing new
# turns up: the same answer for the two board exes, the right one for the
# rest. DERIVED, not listed -- a listed name is a word somebody has to
# remember.
# ⛔THE SAME RULE LIVES IN board_server.dart (`sourcesOfEntry`), because the
# server compares this stamp itself between hook runs. Change both or
# neither. ⚠️That includes the ORDER: `LC_ALL=C` sorts by byte, as Dart's
# `sort` does by code unit — a collation that ignores `_` would put the same
# files in another order, and the server would relaunch on every request.
# 🚨AND THE STAMP HAS A NEW NAME (.srcs). `.src` held a copy of the ENTRY
# file; this holds the concatenation. They cannot share a path: the writer
# (board_up.sh) and the reader (the repo) cannot land in the same instant,
# and I proved it by taking the live board down -- the old exe found the
# concatenation different on every request and exited every time.
# ⚠️ONE awk, not a loop of grep · sed · sort: `tool/run.sh` pays this on
# every call, and on a busy machine every process an Idle shell starts costs
# tens of milliseconds — the loop it replaced took 1.0s of a 5.8s call
# (2026-10-18, measured while a test batch ran). The files are in the
# entry's folder (an import with a `/` in it is not one of ours here), the
# folder of an entry with no folder is `.`, and the list is sorted by byte.
sources_of() {
  LC_ALL=C awk -v entry="$1" '
    BEGIN {
      dir = entry
      if (!sub(/\/[^\/]*$/, "", dir)) dir = "."
      seen[entry] = 1; queue[1] = entry; head = 1; tail = 1
      while (head <= tail) {
        file = queue[head++]
        while ((getline line < file) > 0) {
          if (match(line, /^import \047[A-Za-z0-9_]+\.dart\047/)) {
            path = dir "/" substr(line, 9, RLENGTH - 9)
            if (!(path in seen)) { seen[path] = 1; queue[++tail] = path }
          }
        }
        close(file)
      }
      for (i = 1; i <= tail; i++) {
        v = queue[i]
        for (j = i - 1; j > 0 && sorted[j] > v; j--) sorted[j + 1] = sorted[j]
        sorted[j + 1] = v
      }
      for (i = 1; i <= tail; i++) print sorted[i]
    }'
}
stamp_of() {
  local IFS=$'\n' files
  files="$(sources_of "$1")"
  set -f
  cat $files 2>/dev/null
  set +f
}
built_from() { [ -f "$2" ] && stamp_of "$1" | cmp -s - "$2"; }
