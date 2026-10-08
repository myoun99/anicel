#!/usr/bin/env bash
# What the board gate SAYS, read back as JSON — run by hand; the suite spawns
# no process.
#
# 🚨IT RUNS A STAGED COPY, never the gate where it stands. The gate brings the
# board up as it goes (`board_up.sh`), and on the machine that holds the board
# that script stops whatever listens on the board's port and starts a server
# on the folder it was handed — a throwaway folder would take the live board
# down. The stage holds the gate, the one mouth it speaks through, and a
# `board_up.sh` that only notes it was called.
#
# 2026-10-07: until this file nothing asked whether the gate's output could
# be READ. Its block was not JSON whenever the checker had several lines to
# say, and its red-PR half ended the script on an unset name — both looked,
# from outside, exactly like a board with nothing wrong.
#
# usage: bash board_gate_test.sh [<board_check.exe>]
#   the checker to stage; this machine's own sits in its board folder, which
#   is where ANICEL_BOARD_TOKEN_FILE points.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="${1:-}"
if [ -z "$CHECK" ] && [ -n "${ANICEL_BOARD_TOKEN_FILE:-}" ]; then
  CHECK="$(dirname "$ANICEL_BOARD_TOKEN_FILE")/board_check.exe"
fi
[ -x "$CHECK" ] || { echo "no checker to stage — pass the path of board_check.exe"; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/board-gate-test.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
STAGE="$TMP/stage/tool/session_hooks"
mkdir -p "$STAGE" "$TMP/gh"
cp "$HERE/board_gate.sh" "$HERE/hook_says.sh" "$STAGE/"
printf '#!/usr/bin/env bash\ntouch "$1/.board-up-was-called"\n' > "$STAGE/board_up.sh"
# The stand-in for gh: each of the gate's three queries names a field no
# other one asks for, and is answered from the file of that name.
cat > "$TMP/gh/gh" <<'GH'
#!/usr/bin/env bash
dir="$(dirname "$0")"
case "$*" in
  *mergeStateStatus*) cat "$dir/ready.tsv" 2>/dev/null ;;
  *statusCheckRollup*) cat "$dir/red.tsv" 2>/dev/null ;;
  *mergedAt*) cat "$dir/merged.tsv" 2>/dev/null ;;
esac
exit 0
GH
chmod +x "$TMP/gh/gh" 2>/dev/null

pass=0; fail=0
chk() {  # chk <what> <got> <want>
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf 'ok    %s\n' "$1"
  else fail=$((fail + 1)); printf 'FAIL  %s\n  got:  %s\n  want: %s\n' "$1" "$2" "$3"; fi
}

# board <name> <line>...: a board folder holding the staged checker and these
# records; prints the folder.
board() {
  local dir="$TMP/$1"; shift
  mkdir -p "$dir"
  cp "$CHECK" "$dir/board_check.exe"
  printf '%s\n' "$@" > "$dir/board.jsonl"
  printf '%s' "$dir"
}
# gate <board folder> <gh: none|stub> [<place>]: the staged gate's stdout.
# ⚠️The door's secret is pointed at a file that is not there: a session's own
# environment names the real one, and no test hands that to anything.
gate() {
  local gh="$TMP/gh/gh"
  # 「none」 is a path where nothing is. ⚠️It has to be HANDED to the gate:
  # left to look for itself, the gate finds this machine's real gh, which
  # answers over the network about a board that is not the real one.
  [ "$2" = none ] && gh="$TMP/no-such-gh"
  printf '{"session_id":"t","stop_hook_active":false}' \
    | BOARD_GATE_GH="$gh" ANICEL_BOARD_TOKEN_FILE="$TMP/no-such-token" \
      bash "$STAGE/board_gate.sh" "$1" ${3:+"$3"}
}
# readable <output>: yes when it is one line, a block, and its reason is a
# well-formed JSON string — every quote escaped, every backslash the start
# of an escape JSON knows, no raw control character.
readable() {
  local out="$1" body
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] || { echo "no: $(printf '%s\n' "$out" | wc -l | tr -d ' ') lines"; return; }
  case "$out" in '{"decision":"block","reason":"'*'"}') ;; *) echo "no: not a block"; return ;; esac
  body="${out#'{"decision":"block","reason":"'}"; body="${body%'"}'}"
  [ "$(printf '%s' "$body" | tr -d '\001-\037' | wc -c)" = "$(printf '%s' "$body" | wc -c)" ] \
    || { echo "no: a raw control character"; return; }
  body="$(printf '%s' "$body" | sed -e 's/\\\\//g' -e 's/\\"//g' -e 's/\\n//g' -e 's/\\t//g')"
  case "$body" in *'"'*) echo "no: a bare quote"; return ;; *'\'*) echo "no: a stray backslash"; return ;; esac
  echo yes
}
old='2026-01-05T10:00:0'
item="{\"kind\":\"item\",\"id\":\"x-card\",\"at\":\"유저\",\"said\":\"hello\",\"ts\":\"${old}0.000000\"}"
question="{\"kind\":\"decision\",\"id\":\"x-card-Q1\",\"of\":\"x-card\",\"at\":\"질문\",\"title\":\"no options here\",\"ts\":\"${old}1.000000\"}"
landed='{"kind":"meta","landedSince":"2026-01-01T00:00:00Z"}'
done_card="{\"kind\":\"item\",\"id\":\"y-card\",\"at\":\"완료\",\"note\":\"done\",\"ts\":\"${old}2.000000\"}"

# --- a clean board says nothing, with gh or without --------------------------
: > "$TMP/gh/ready.tsv"; : > "$TMP/gh/red.tsv"; : > "$TMP/gh/merged.tsv"
clean="$(board clean "$done_card" "$landed")"
chk "깨끗한 보드 · gh 없음 → 조용"            "$(gate "$clean" none)" ""
chk "깨끗한 보드 · gh 있음(할 말 없음) → 조용"  "$(gate "$clean" stub)" ""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "$clean/.board-up-was-called" ] && break
  sleep 0.2
done
chk "진짜 board_up 은 무대에 없다(흉내가 불렸다)" "$(test -f "$clean/.board-up-was-called" && echo yes)" "yes"

# --- the checker's complaint: several lines, quotes in them ------------------
dirty="$(board dirty "$item" "$question" "$landed")"
raw="$("$dirty/board_check.exe" "$dirty/board.jsonl" 2>/dev/null)"
chk "전제: 검사기의 불평이 여러 줄이다"         "$([ "$(printf '%s\n' "$raw" | wc -l)" -gt 1 ] && echo yes)" "yes"
out="$(gate "$dirty" none)"
chk "🚨불평 · gh 없음 → 읽히는 막음"            "$(readable "$out")" "yes"
chk "그 막음은 검사기의 첫 줄로 시작한다"        "$(printf '%s' "$out" | grep -cF "\"reason\":\"$(printf '%s\n' "$raw" | head -n 1)")" "1"
chk "결정 카드의 모양을 따옴표째 싣는다"         "$(printf '%s' "$out" | grep -c '{\\"kind\\":\\"decision\\",\\"id\\":…,\\"at\\":\\"질문\\"')" "1"

# --- the PR half: titles are whatever somebody typed -------------------------
printf '41\tReady with "quotes" in it\n' > "$TMP/gh/ready.tsv"
printf '42\tRed: a back\\slash and a\ttab\n' > "$TMP/gh/red.tsv"
printf '43\tLanded with no card\t2026-01-02T00:00:00Z\n' > "$TMP/gh/merged.tsv"
out="$(gate "$dirty" stub)"
chk "🚨불평 + PR 셋 → 읽히는 막음"              "$(readable "$out")" "yes"
chk "🚨빨간 PR 의 줄이 나온다(전에는 여기서 죽었다)" "$(printf '%s' "$out" | grep -c 'CI가 빨간 PR이 열린 채로')" "1"
chk "빨간 PR 의 제목이 이스케이프되어 실린다"     "$(printf '%s' "$out" | grep -c '#42 Red: a back\\\\slash and a\\ttab')" "1"
chk "머지 준비가 끝난 PR 의 줄과 제목"           "$(printf '%s' "$out" | grep -c '머지 준비가 끝난 PR이 열린 채로.*#41 Ready with \\"quotes\\" in it')" "1"
chk "카드 없는 착지의 줄"                        "$(printf '%s' "$out" | grep -c '카드가 없는 PR:\\n#43 Landed with no card')" "1"
chk "불평이 PR 줄들보다 먼저 온다"               "$(printf '%s' "$out" | grep -c "$(printf '%s\n' "$raw" | head -n 1).*카드가 없는 PR.*CI가 빨간.*머지 준비가")" "1"
out="$(gate "$clean" stub)"
chk "깨끗한 보드 + PR 셋 → 읽히는 막음"          "$(readable "$out")" "yes"
printf '41 leave it open: waiting for a person\n42\n' > "$clean/.gate-ack"
printf '43 another session landed it\n' >> "$clean/.gate-ack"
chk "셋 다 손대지 않기로 적으면 → 조용"          "$(gate "$clean" stub)" ""
: > "$TMP/gh/ready.tsv"; : > "$TMP/gh/red.tsv"; : > "$TMP/gh/merged.tsv"

# --- a (card, PR) pair that left the records ---------------------------------
gone="$(board gone "$done_card" "$landed")"
printf 'old-card 7\ny-card 9\n' > "$gone/.board-prs"
out="$(gate "$gone" none)"
chk "사라진 (카드, PR) 짝 → 읽히는 막음"         "$(readable "$out")" "yes"
chk "사라진 짝을 줄마다 댄다"                    "$(printf '%s' "$out" | grep -c '사라졌습니다:\\nold-card 7\\ny-card 9\\n\\n이 파일은')" "1"

# --- a checker that could not run is not a clean board -----------------------
out="$(gate "$clean" none "http://127.0.0.1:9")"
chk "닿지 않는 보드 → 읽히는 막음"               "$(readable "$out")" "yes"
chk "그 막음은 돌지 못했다고 말한다"             "$(printf '%s' "$out" | grep -c 'board_check 가 돌지 못했습니다 (exit [2-9])')" "1"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] && echo "All tests passed!" || echo "SOME TESTS FAILED"
exit "$fail"
