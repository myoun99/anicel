#!/usr/bin/env bash
# Test for session_letters.sh — run by hand; the suite spawns no process.
#
# It hands the hook a throwaway board folder and a stand-in for curl that
# notes how it was called and answers from a file, so nothing here reaches a
# board, and the door's secret used below is a made-up word.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/session_letters.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/session-letters-test.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
MEM="$TMP/board"; STUB="$TMP/stub"
mkdir -p "$MEM/.session-names" "$STUB/bin"
export STUB
cat > "$STUB/bin/curl" <<'CURL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB/argv"
cat > "$STUB/stdin"
[ -f "$STUB/exit" ] && exit "$(cat "$STUB/exit")"
cat "$STUB/answer" 2>/dev/null
exit 0
CURL
chmod +x "$STUB/bin/curl" 2>/dev/null

pass=0; fail=0
chk() {  # chk <what> <got> <want>
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf 'ok    %s\n' "$1"
  else fail=$((fail + 1)); printf 'FAIL  %s\n  got:  %s\n  want: %s\n' "$1" "$2" "$3"; fi
}
# hook <session id> <start|stop> [<board folder>]: the hook's stdout.
hook() {
  printf '{"session_id":"%s","prompt":"hello"}' "$1" \
    | PATH="$STUB/bin:$PATH" bash "$HOOK" "${3:-$MEM}" "http://board.test:4321/" "$2"
}
calls() { if [ -f "$STUB/argv" ]; then wc -l < "$STUB/argv" | tr -d ' '; else echo 0; fi; }
fresh() { rm -f "$STUB/argv" "$STUB/stdin" "$STUB/exit" "$STUB/answer"; }

# --- a session that registered no 담당 is told once, at a start, and left ---
fresh
out="$(hook nobody start)"
chk "등록 안 한 세션 · 시작 → 등록하는 법을 한 번 말한다" "$(printf '%s' "$out" | grep -c 'dart run tool/board_me.dart')" 1
chk "그 말은 UserPromptSubmit 의 덧붙임 한 줄이다"       "$(printf '%s\n' "$out" | grep -c '^{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"')" 1
chk "두 번째부터는 조용하다"                             "$(hook nobody start)" ""
chk "끝에서는 처음이어도 말하지 않는다"                   "$(hook another stop)" ""
chk "🚨이름 없는 세션은 보드에 묻지 않는다"               "$(calls)" 0

# --- a registered session is shown what waits for it ------------------------
printf '보드/통합\r\n' > "$MEM/.session-names/s"
printf 'made-up-secret\n' > "$MEM/.board-token"
printf '📨 보드에 「보드/통합」 앞으로 남은 전달 1건\n\n━ 관제 → 보드/통합 · 카드 W\n"sync" 했습니다\n' > "$STUB/answer"
fresh_answer="$(cat "$STUB/answer")"
out="$(hook s start)"
chk "받은 것이 있으면 · 시작 → 덧붙임 한 줄"             "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 1
chk "글이 줄바꿈 · 따옴표째 실린다"                       "$(printf '%s' "$out" | grep -c '전달 1건\\n\\n━ 관제 → 보드/통합 · 카드 W\\n\\"sync\\" 했습니다"}}$')" 1
chk "보드에 한 번 물었다"                                 "$(calls)" 1
chk "받는 담당을 이름으로 묻는다(줄 끝의 CR 없이)"         "$(grep -c '^data-urlencode = "to=보드/통합"$' "$STUB/stdin")" 1
chk "쓰는 요청으로, 이름은 주소에 실어 묻는다"            "$(grep -c -x -e 'request = "POST"' -e 'get' "$STUB/stdin")" 2
# A Windows program is handed its command line in the machine's code page:
# a Korean name there arrives as something else (session_letters.sh says
# what that cost). ⚠️This stand-in is a shell script and would never have
# noticed — the check is on WHERE the name travels.
chk "🚨이름은 명령줄에 없다 — 명령줄에는 옵션뿐이다"       "$(cat "$STUB/argv")" "-s -f -m 5 -K -"
chk "묻는 길은 받기 길이다(주소 끝의 빗금은 하나로)"       "$(grep -c '^url = "http://board.test:4321/letters/take"$' "$STUB/stdin")" 1
chk "🚨비밀값은 명령줄에 없다"                            "$(grep -c 'made-up-secret' "$STUB/argv")" 0
chk "비밀값은 표준 입력으로 간다"                         "$(grep -c '^header = "Authorization: Bearer made-up-secret"$' "$STUB/stdin")" 1

out="$(hook s stop)"
chk "받은 것이 있으면 · 끝 → 막음 한 줄"                  "$(printf '%s\n' "$out" | grep -c '^{"decision":"block","reason":"📨 ')" 1
chk "막는 말에 끝내도 된다는 안내가 붙는다"               "$(printf '%s' "$out" | grep -c '그대로 끝내면 됩니다.)"}$')" 1

# --- nothing waiting, or nobody to ask: silent ------------------------------
: > "$STUB/answer"
chk "받은 것이 없으면 조용하다(시작)"                     "$(hook s start)" ""
chk "받은 것이 없으면 조용하다(끝)"                       "$(hook s stop)" ""
printf '%s\n' "$fresh_answer" > "$STUB/answer"; echo 7 > "$STUB/exit"
chk "🚨보드가 안 닿으면 조용하다 — 턴을 붙잡지 않는다"    "$(hook s stop)" ""
rm -f "$STUB/exit"
rm -f "$MEM/.board-token"; hook s start > /dev/null
chk "비밀값 파일이 없으면 머리 없이 묻는다"               "$(grep -c 'Authorization' "$STUB/stdin")" 0
before="$(calls)"
out="$(printf '{"prompt":"no id here"}' | PATH="$STUB/bin:$PATH" bash "$HOOK" "$MEM" "http://board.test:4321" start)"
chk "세션 id 없는 부름은 조용하고 묻지 않는다"            "$out$(( $(calls) - before ))" "0"
chk "보드 폴더가 없으면 조용하다"                         "$(hook s start "$TMP/no-such-folder")" ""

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] && echo "All tests passed!" || echo "SOME TESTS FAILED"
exit "$fail"
