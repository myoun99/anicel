#!/usr/bin/env bash
# What tool/run.sh DOES — run by hand; the suite spawns no process
# (tests_do_not_race_the_code_test).
#
# 🚨IT RUNS A STAGED COPY AGAINST STAND-INS: the stage holds run.sh, the
# stamp law it reads and a few tools; `flutter` is a stand-in whose SDK
# beside it holds a stand-in `dart` that writes down every call. Asked to
# compile, that `dart` copies a real program in as the "exe" — `printenv`,
# so a run of it says what the tool was handed — or fails when told to. The
# cache is a folder of the stage, so nothing of this machine is touched.
#
# What it holds (2026-10-18, card tests-crowd-the-machine): a tool is built
# once and then run as its exe, with its arguments and its exit code · a
# change to any file it is made of — two imports down included — builds
# another · a build that fails runs the tool by JIT and says why · a build
# under way is waited for, a lock left by a dead builder is taken over · a
# tool that is not there goes to dart as it is · the tool is told where it
# was built from.
#
# usage: bash tool/run_test.sh
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/run-test.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
STAGE="$TMP/stage"
SDK="$TMP/flutter/bin/cache/dart-sdk"
mkdir -p "$STAGE/tool" "$SDK/bin" "$TMP/cache"
cp "$HERE/run.sh" "$HERE/exe_stamp.sh" "$STAGE/tool/"
echo "3.99.0" > "$SDK/version"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/flutter/bin/flutter"
LOG="$TMP/calls"
PRINTENV="$(type -P printenv)"
cat > "$SDK/bin/dart" <<DART
#!/usr/bin/env bash
# compile exe <entry> -o <out> · or a JIT run: <entry> <args…>
if [ "\$1" = compile ]; then
  echo "build \$(basename "\$3")" >> "$LOG"
  [ -e "$TMP/build-fails" ] && { echo "the compiler said no" >&2; exit 1; }
  [ -e "$TMP/build-slow" ] && sleep 3
  cp "$PRINTENV" "\$5"
  exit 0
fi
echo "jit \$(basename "\$1") \${*:2}" >> "$LOG"
exit 7
DART
chmod +x "$SDK/bin/dart" "$TMP/flutter/bin/flutter" 2>/dev/null
EXT=; case "$OSTYPE" in msys* | cygwin*) EXT=.exe ;; esac
export PATH="$TMP/flutter/bin:$PATH"
export LOCALAPPDATA="$TMP/cache"
CACHE="$TMP/cache/anicel/tools"

pass=0; fail=0
chk() {  # chk <what> <got> <want>
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf 'ok    %s\n' "$1"
  else fail=$((fail + 1)); printf 'FAIL  %s\n  got:  %s\n  want: %s\n' "$1" "$2" "$3"; fi
}
calls() { grep -c "$1" "$LOG" 2>/dev/null || true; }
exes() { find "$CACHE" -maxdepth 1 -type f -name "$1-*" ! -name '*.part*' 2>/dev/null | wc -l | tr -d ' '; }
run() { (cd "$STAGE" && bash tool/run.sh "$@"); }

printf "import 'b_model.dart';\nvoid main() {}\n" > "$STAGE/tool/a_tool.dart"
printf "import 'c_model.dart';\n" > "$STAGE/tool/b_model.dart"
printf "const c = 1;\n" > "$STAGE/tool/c_model.dart"
: > "$LOG"

echo "A built once, then run as the exe"
OUT="$(run a_tool PATH)"
chk "the first call builds" "$(calls '^build a_tool.dart')" 1
chk "and runs the exe with the arguments" "$OUT" "$PATH"
run a_tool PATH >/dev/null
chk "the second call builds nothing" "$(calls '^build a_tool.dart')" 1
chk "and runs nothing by JIT" "$(calls '^jit')" 0
chk "one exe in the cache" "$(exes a_tool)" 1
chk "the tool is told where it was built from" \
  "$(run a_tool ANICEL_TOOL_DIR)" "$(cd "$STAGE/tool" && { pwd -W 2>/dev/null || pwd; })"
run a_tool NO_SUCH_VARIABLE >/dev/null; RC=$?
chk "the exe's exit code is the call's" "$RC" 1

echo "B any file it is made of"
printf "const c = 2;\n" > "$STAGE/tool/c_model.dart"
run a_tool PATH >/dev/null
chk "a change two imports down builds another" "$(calls '^build a_tool.dart')" 2
chk "and the first is kept (another checkout may hold it)" "$(exes a_tool)" 2
printf "// a comment\n" > "$STAGE/tool/unrelated.dart"
run a_tool PATH >/dev/null
chk "a file it is not made of builds nothing" "$(calls '^build a_tool.dart')" 2

echo "C a build that fails"
printf "void main() {}\n" > "$STAGE/tool/d_tool.dart"
touch "$TMP/build-fails"
run d_tool x y >/dev/null; RC=$?
chk "the tool goes to JIT" "$(calls '^jit d_tool.dart x y')" 1
chk "with JIT's exit code" "$RC" 7
chk "and why is written down" "$(cat "$CACHE/d_tool.build.log")" "the compiler said no"
chk "no exe is left" "$(exes d_tool)" 0
chk "no lock is left" "$(find "$CACHE" -name '*.building' | wc -l | tr -d ' ')" 0
rm -f "$TMP/build-fails"
run d_tool PATH >/dev/null
chk "the next call builds again" "$(calls '^build d_tool.dart')" 2

echo "D one builder"
printf "void main() {}\n" > "$STAGE/tool/e_tool.dart"
touch "$TMP/build-slow"
(run e_tool PATH >/dev/null) &
sleep 1
OUT="$(run e_tool PATH)"
wait
rm -f "$TMP/build-slow"
chk "two calls at once build once" "$(calls '^build e_tool.dart')" 1
chk "the second waits and runs the exe" "$OUT" "$PATH"
chk "and runs nothing by JIT" "$(calls '^jit e_tool')" 0
printf "void main() {}\n" > "$STAGE/tool/f_tool.dart"
mkdir -p "$CACHE"
KEY="$(run f_tool PATH >/dev/null; ls "$CACHE" | sed -n 's/^f_tool-\([0-9a-f]*\).*/\1/p' | head -1)"
rm -f "$CACHE"/f_tool-*
mkdir "$CACHE/f_tool-$KEY$EXT.building"
touch -t "$(date -d "-20 min" +%Y%m%d%H%M 2>/dev/null || date -v-20M +%Y%m%d%H%M)" "$CACHE/f_tool-$KEY$EXT.building"
run f_tool PATH >/dev/null
chk "a lock older than ten minutes is taken over" "$(calls '^build f_tool.dart')" 2
chk "and the exe is there" "$(exes f_tool)" 1

echo "E a tool that is not there"
run nothing_here a b >/dev/null
chk "goes to dart as it is" "$(calls '^jit nothing_here.dart a b')" 1
chk "and builds nothing" "$(calls '^build nothing_here')" 0

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
