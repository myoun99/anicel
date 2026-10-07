#!/usr/bin/env bash
# Test for the 자율진행 pair.
#
# 🚨IT NEVER TOUCHES THE REAL MARKERS. The scripts keep their markers in
# the folder they are handed, and this hands them a throwaway one. (Until
# 2026-10-07 they found the markers beside themselves and this ran COPIES
# of them — and the first version drove the scripts in the memory folder
# itself and began with `rm -f .autorun`: harmless while one session used
# the folder, and a way to silently end another session's 자율진행 once
# several share it, 2026-09-15.)
#
# usage: bash autorun_test.sh [<directory holding autorun_arm.sh and
#        autorun_gate.sh>]   (defaults to this file's own directory)
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ $# -ge 1 ] && SRC="$1"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/autorun-test.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
ARM="$SRC/autorun_arm.sh"; GATE="$SRC/autorun_gate.sh"
pass=0; fail=0

chk() { # name, actual, expected
  if [ "$2" = "$3" ]; then pass=$((pass+1)); printf 'ok    %-52s %s\n' "$1" "$2"
  else fail=$((fail+1)); printf 'FAIL  %-52s got=%s want=%s\n' "$1" "$2" "$3"; fi
}
flag_of() { if [ -n "$1" ]; then echo "$TMP/.autorun.$1"; else echo "$TMP/.autorun"; fi; }
armed() { [ -f "$(flag_of "${1:-}")" ] && echo yes || echo no; }
gate() { # session id ('' = a payload with no session id)
  if [ -n "$1" ]; then printf '{"session_id":"%s","stop_hook_active":false}' "$1"
  else printf '{}'; fi | bash "$GATE" "$TMP"
}
blocks() { gate "${1:-}" | grep -c '"decision":"block"'; }
say() { # session id, prompt
  if [ -n "$1" ]; then printf '{"session_id":"%s","prompt":"%s"}' "$1" "$2"
  else printf '{"prompt":"%s"}' "$2"; fi | bash "$ARM" "$TMP" > /dev/null
}
lines() { wc -l < "$1" | tr -d ' '; }
reset() { rm -f "$TMP"/.autorun "$TMP"/.autorun.*; }

# --- ordinary prompts never arm it ---------------------------------------
say s "보드 고쳐줘"                        ; chk "무관한 프롬프트"                       "$(armed s)" no
chk "아무것도 안 켜졌으면 게이트 조용(s)"   "$(blocks s)" 0
chk "아무것도 안 켜졌으면 게이트 조용(t)"   "$(blocks t)" 0

# --- the word arms THAT session ------------------------------------------
say s "자율진행으로 남은거 다 해줘"
chk "자율진행 -> s 켜짐"                     "$(armed s)" yes
chk "t 는 안 켜진다"                          "$(armed t)" no
chk "공용 표식은 안 생긴다"                   "$(armed '')" no
chk "s 의 턴은 막는다"                        "$(blocks s)" 1
chk "🚨t 의 턴은 안 막는다"                   "$(blocks t)" 0

# --- counting belongs to the session that armed ---------------------------
before=$(lines "$(flag_of s)")
blocks s > /dev/null
chk "s 가 막힐 때마다 s 의 턴이 하나 는다"     "$(( $(lines "$(flag_of s)") - before ))" 1
before=$(lines "$(flag_of s)")
blocks t > /dev/null
chk "🚨t 의 멈춤은 s 의 턴을 안 깎는다"        "$(( $(lines "$(flag_of s)") - before ))" 0
chk "막는 말은 s 자기 표식을 지우라고 한다"     "$(gate s | grep -c '\.autorun\.s')" 1

# --- disarm is per session too --------------------------------------------
say t "자율진행 그만"                      ; chk "t 의 「그만」은 s 를 안 끈다"          "$(armed s)" yes
say s "자율진행 그만"                      ; chk "s 의 「그만」 -> s 꺼짐"               "$(armed s)" no
chk "끈 뒤엔 안 막는다"                       "$(blocks s)" 0
say s "자율진행 중단해"                    ; chk "이미 꺼져 있으면 그대로"                "$(armed s)" no

say s "자율진행 해줘"                      ; chk "다시 켜기"                             "$(armed s)" yes
say s "자율 진행 종료"                     ; chk "'자율 진행 종료'(띄어쓰기)"             "$(armed s)" no

reset
say s "자율진행으로 이 작업 종료까지 해줘"  ; chk "문장 뒤쪽의 「종료」로 꺼지지 않는다"   "$(armed s)" yes
reset
say s "자율진행이 뭔지 설명해줘"            ; chk "설명 요청도 켠다(의도된 무딤)"          "$(armed s)" yes
reset

# --- two sessions armed at once stay apart --------------------------------
say s "자율진행"; say t "자율진행"
chk "둘 다 켜진다(s)"                         "$(armed s)" yes
chk "둘 다 켜진다(t)"                         "$(armed t)" yes
say t "자율진행 끄기"                      ; chk "t 만 꺼진다"                            "$(armed t)$(armed s)" noyes
reset

# --- a bare .autorun has no owner, so it blocks everyone as it always did --
printf 'armed\n' > "$TMP/.autorun"
chk "주인 없는 표식은 s 를 막는다"            "$(blocks s)" 1
chk "주인 없는 표식은 t 도 막는다"            "$(blocks t)" 1
chk "세션 id 없는 멈춤도 막는다"              "$(blocks '')" 1
say s "자율진행"                           ; chk "그 위에서 켜면 s 표식이 따로 생긴다"    "$(armed s)" yes
before=$(lines "$TMP/.autorun")
blocks s > /dev/null
chk "s 는 자기 표식에 센다(공용 표식 그대로)"  "$(( $(lines "$TMP/.autorun") - before ))" 0
say t "자율진행 그만"                      ; chk "누구의 「그만」이든 주인 없는 표식은 꺼진다" "$(armed '')" no
chk "그때 s 표식은 그대로"                    "$(armed s)" yes
reset

# --- a payload with no session id falls back to the bare marker ------------
say '' "자율진행"                          ; chk "id 없는 켜기 -> 주인 없는 표식"          "$(armed '')" yes
chk "그 표식은 누구든 막는다"                  "$(blocks t)" 1
reset

# --- the cap releases THAT session, and demands a report ------------------
say s "자율진행"; say t "자율진행"
MAXV=$(grep -oE '^MAX=[0-9]+' "$GATE" | cut -d= -f2)
for i in $(seq 1 $((MAXV + 1))); do printf 'turn\n' >> "$(flag_of s)"; done
out=$(gate s)
chk "캡 도달 시에도 block 으로 말한다"         "$(echo "$out" | grep -c '"decision":"block"')" 1
chk "캡 도달 시 보고를 요구한다"               "$(echo "$out" | grep -c '유저에게')" 1
chk "캡 도달 시 s 표식을 지운다"               "$(armed s)" no
chk "🚨t 는 그대로 켜져 있다"                  "$(armed t)" yes
reset

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] && echo "All tests passed!" || echo "SOME TESTS FAILED"
exit "$fail"
