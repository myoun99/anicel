#!/usr/bin/env bash
# What the start-up hook ENDS and STARTS — run by hand; the suite spawns no
# process.
#
# 🚨IT RUNS A STAGED COPY AGAINST STAND-INS, never the hook where it stands:
# the real one ends a server and starts another. The stage holds the hook and
# two empty sources; `powershell`, `dart` and `git` are stand-ins first on
# PATH, so no process is ended, nothing listens and nothing is built.
#
# The stand-in for PowerShell keeps ONE fact — the exe of whatever listens on
# the port, in the file `listening` — and answers the hook's three questions
# from it: who listens (`ours` when that exe is the one the question names),
# end this exe (the fact goes when it is that exe), start this exe (it
# becomes the fact). ⚠️So what is held here is what the hook ASKS FOR and
# what it does with the answer; that PowerShell itself compares two paths the
# way the stand-in does was read off the live port once, by hand (2026-10-07:
# this board's folder `ours` in either case, another folder `other`, a free
# port nothing).
#
# usage: bash board_up_test.sh
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/board-up-test.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
STAGE="$TMP/stage"
BIN="$TMP/bin"
mkdir -p "$STAGE/tool/session_hooks" "$BIN"
cp "$HERE/board_up.sh" "$STAGE/tool/session_hooks/"
printf '// the server\n' > "$STAGE/tool/board_server.dart"
printf '// the gate\n' > "$STAGE/tool/board_check.dart"

cat > "$BIN/powershell" <<'PS'
#!/usr/bin/env bash
# The command is the last argument; the exe it names is its one quoted path.
dir="$(dirname "$0")"
command="${!#}"
plain() { printf '%s' "$1" | tr '\\' '/' | tr 'A-Z' 'a-z'; }
named="$(printf '%s' "$command" | sed -n "s/.*GetFullPath('\([^']*\)').*/\1/p")"
case "$command" in
  *Get-NetTCPConnection*)
    echo "ask" >> "$dir/calls"
    [ -s "$dir/listening" ] || exit 0
    if [ "$(plain "$(cat "$dir/listening")")" = "$(plain "$named")" ]
    then echo ours; else echo other; fi ;;
  *Stop-Process*)
    echo "stop $named" >> "$dir/calls"
    if [ -s "$dir/listening" ] \
        && [ "$(plain "$(cat "$dir/listening")")" = "$(plain "$named")" ]
    then rm -f "$dir/listening"; fi ;;
  *Start-Process*)
    started="$(printf '%s' "$command" | sed -n "s/.*-FilePath '\([^']*\)'.*/\1/p")"
    echo "start $started" >> "$dir/calls"
    [ -e "$dir/start-fails" ] || printf '%s' "$started" > "$dir/listening" ;;
esac
exit 0
PS
cat > "$BIN/dart" <<'DART'
#!/usr/bin/env bash
# `dart compile exe <source> -o <exe>`: the exe appears, unless told to fail.
dir="$(dirname "$0")"
echo "build ${!#}" >> "$dir/calls"
[ -e "$dir/build-fails" ] && exit 1
printf 'built\n' > "${!#}"
DART
cat > "$BIN/git" <<'GIT'
#!/usr/bin/env bash
# The one question the hook asks git: which machine is this.
dir="$(dirname "$0")"
case "$*" in *anicel.machine*) cat "$dir/machine" 2>/dev/null ;; esac
exit 0
GIT
chmod +x "$BIN/powershell" "$BIN/dart" "$BIN/git" 2>/dev/null

pass=0; fail=0
chk() {  # chk <what> <got> <want>
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf 'ok    %s\n' "$1"
  else fail=$((fail + 1)); printf 'FAIL  %s\n  got:  %s\n  want: %s\n' "$1" "$2" "$3"; fi
}

# fresh <name>: a new board folder (as the hook will spell it) and a clean
# slate of stand-in facts.
fresh() {
  rm -f "$BIN/calls" "$BIN/listening" "$BIN/build-fails" "$BIN/start-fails" \
    "$BIN/machine"
  mkdir -p "$TMP/$1"
  FOLDER="$(cygpath -m "$TMP/$1")"
}
# built: the folder already holds both binaries, built from the staged sources.
built() {
  for name in board_server board_check; do
    printf 'built\n' > "$FOLDER/$name.exe"
    cat "$STAGE/tool/$name.dart" > "$FOLDER/$name.exe.srcs"
  done
}
run() { PATH="$BIN:$PATH" bash "$STAGE/tool/session_hooks/board_up.sh" "$@"; }
calls() { grep -v '^ask$' "$BIN/calls" 2>/dev/null | tr '\n' ';'; }
log() { sed 's/^[0-9-]* [0-9:]* //' "$FOLDER/.board_up.log" 2>/dev/null | tr '\n' ';'; }
OTHER='C:\Somewhere\Else\board_server.exe'

echo "--- nothing listens"
fresh a; built
run "$FOLDER"
chk "this folder's server is started" "$(calls)" "start $FOLDER/board_server.exe;"
chk "and nothing is written down" "$(log)" ""

echo "--- this folder's server listens"
fresh b; built
printf '%s' "$FOLDER/board_server.exe" > "$BIN/listening"
run "$FOLDER"
chk "fresh: nothing is ended, built or started" "$(calls)" ""
fresh c; built
printf '// the server, changed\n' > "$FOLDER/board_server.exe.srcs"
printf '%s' "$FOLDER/board_server.exe" | tr 'a-z/' 'A-Z\\' > "$BIN/listening"
run "$FOLDER"
chk "stale: it is ended, built and started again — however its path is cased" \
  "$(calls)" \
  "stop $FOLDER/board_server.exe;build $FOLDER/board_server.exe;start $FOLDER/board_server.exe;"
chk "and the new build is on record" \
  "$(cat "$FOLDER/board_server.exe.srcs")" "// the server"

echo "--- ANOTHER board's server listens"
fresh d
printf '%s' "$OTHER" > "$BIN/listening"
run "$FOLDER"
chk "it still listens" "$(cat "$BIN/listening")" "$OTHER"
chk "the only exe asked to end is this folder's own" \
  "$(grep -c '^stop ' "$BIN/calls"):$(grep '^stop ' "$BIN/calls" | grep -vcF "stop $FOLDER/board_server.exe")" "1:0"
chk "nothing is started on its port" "$(grep -c '^start ' "$BIN/calls")" "0"
chk "and that is written down" "$(log)" \
  "board_up: port 4321 is held by something that is not $FOLDER/board_server.exe -- left alone;"
fresh e; built
printf '%s' "$OTHER" > "$BIN/listening"
run "$FOLDER"
chk "fresh binaries: nothing is ended, built or started" "$(calls)" ""
chk "it still listens" "$(cat "$BIN/listening")" "$OTHER"

echo "--- a build that fails"
fresh f
touch "$BIN/build-fails"
run "$FOLDER"
chk "is written down, for both binaries" "$(log)" \
  "board_up: could not build $FOLDER/board_server.exe -- what was there goes on;board_up: could not build $FOLDER/board_check.exe -- what was there goes on;"
chk "and leaves no record of a build" \
  "$(ls "$FOLDER" | grep -c '\.srcs$')" "0"

echo "--- a server that does not come up"
fresh g; built
touch "$BIN/start-fails"
run "$FOLDER"
chk "is tried twice" "$(grep -c '^start ' "$BIN/calls")" "2"
chk "and written down" "$(log)" "board_up: server did not come up on port 4321;"

echo "--- a machine that does not hold the board"
fresh h
printf 'surface11\n' > "$BIN/machine"
run "$FOLDER"
chk "builds the gate's binary and nothing else, and asks the port nothing" \
  "$(cat "$BIN/calls" | tr '\n' ';')" "build $FOLDER/board_check.exe;"

echo "--- the folder, spelled the way this shell spells it"
fresh i; built
run "$TMP/i"
chk "reaches PowerShell as Windows spells it" "$(calls)" \
  "start $FOLDER/board_server.exe;"
chk "(premise: this shell spells that folder another way)" \
  "$([ "$TMP/i" != "$FOLDER" ] && echo differs)" "differs"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
