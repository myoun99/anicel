#!/usr/bin/env bash
# Stop-hook gate: a PR that is ready to merge must not survive the end of a turn.
#
# THIS IS THE THIRD THING THIS GATE HAS GUARDED, and the first one worth
# keeping permanently.
#   1. board staleness -- retired when the board became a served page and
#      could no longer be stale. ⛔THAT PREMISE WAS WRONG AND IT IS BACK
#      (2026-08-31, below): the PAGE is drawn on every open, but the SERVER
#      drawing it is a compiled exe, so a board fix merged mid-session sat
#      unbuilt until the next SessionStart. Cheap now -- one stat.
#   2. a malformed records line -- retired because the server writes every
#      record now, it never once fired, and it cost 2.4s of every single turn
#      (`dart run` JIT startup was 1.8s of that). The board shows unreadable
#      lines itself, which is free.
#   3. this.
#
# WHY THIS ONE IS DIFFERENT: it has already happened, and it cost real time.
# 2026-08-22, PR #1176 went up with "I'll merge when CI is green" and the turn
# ended. CI went green in minutes; the PR sat for two hours until the user
# asked. Writing "I'll merge later" is not doing anything -- when the turn ends
# nobody is watching. A rule cannot fix that, because the failure IS forgetting.
#
# It fires only on CLEAN -- mergeable, checks green, nothing left to wait for.
# A PR that is still building is a wait, not a mistake, so it stays silent.
#
# ESCAPE HATCH, deliberately a written act: if a green PR should stay open,
# put its number in .gate-ack with a reason. Deciding to leave it is fine;
# walking away without deciding is what this stops.
#
# Fails OPEN everywhere -- no gh, no network, no repo. A turn must never be
# held hostage by a gate that cannot do its own job.
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
# ⚠️ITS SECOND ARGUMENT IS WHERE THE BOARD IS: the records file on the
# machine that holds it, the address of that machine's server anywhere else
# (tool/board_door.dart). The board's own gate asks whichever it is; the
# halves below that read the records file directly — the PR claims that may
# not vanish, the landings without a card — run only where the file is.
set -u

MEM="${1:-}"
[ -d "$MEM" ] || exit 0
PLACE="${2:-$MEM/board.jsonl}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -W)"
# Where the installer puts gh on Windows; anywhere else, wherever PATH has it.
GH="C:/Program Files/GitHub CLI/gh.exe"
[ -x "$GH" ] || GH="$(cygpath -m "$(command -v gh 2>/dev/null)" 2>/dev/null)"
ACK="$MEM/.gate-ack"
REPO="myoun99/anicel"

# --- 🚨보드가 낡은 빌드를 내주고 있나 ------------------------------------
# 유저 2026-08-31 이 「마지막이 아닌데도 착수가능이거든?」이라 물었을 때,
# 그 규칙은 이미 12분 전에 머지돼 있었다(#1395, 17:09). 화면이 옛 답을
# 내주고 있었을 뿐이다 — board_server.exe 는 16:57:48 에 떴고, 그 뒤로
# 아무도 다시 컴파일하지 않았다.
#
# ⛔이 파일 머리말의 1번 「board staleness -- retired when the board became
# a served page and could no longer be stale」가 바로 그 무너진 전제다.
# 페이지는 열 때마다 그려지지만 **그 페이지를 그리는 서버는 컴파일된
# 바이너리**라서, 세션 도중 머지된 보드 수정은 다음 SessionStart 까지
# 절대 화면에 도달하지 않는다. board_up.sh 가 비교를 하긴 했는데 그게
# mtime 이었고(지금은 내용 해시다), 부르는 곳도 SessionStart 하나뿐이었다.
#
# ⚠️판단은 board_up.sh 가 전부 갖고 있다(비교·중지·재컴파일·재기동·
# 확인). 여기서 다시 쓰지 않는다 — 여기 있는 것은 **언제 부를지**뿐이고,
# 그 답은 「매 턴」이다. board_up.sh 는 할 일이 없으면 곧바로 빠진다.
#
# ⛔처음엔 여기서 mtime 을 한 번 재고 그럴 때만 불렀다. 그것이 바로 이
# 버그를 만든 계측이다 — 소스 16:57:11, exe 16:57:44 로 **소스가 더 낡은
# 채 내용은 새것**이었고(git 은 이미 들고 있는 내용을 다시 쓰지 않는다),
# 내가 새로 짠 게이트가 「조용함」이라고 답했다. 규칙을 두 곳에 두면
# 둘째 사본이 첫째와 다른 질문을 한다.
#
# 🚨백그라운드로 띄운다: 재컴파일은 10초쯤 걸리고, 턴이 그걸 기다릴
# 이유가 없다.
("$HERE/board_up.sh" "$MEM" >/dev/null 2>&1 &)


# --- 답할 수 없는 결정 카드가 남았나 --------------------------------------
# 🚨2026-08-26, 유저: 「지금 답할것 질문이 자세하게 안써있고 **대답칸도 없어서**
# 뭘 말하는건지 모르겠어. **계속 그러는데** … **규칙으로 강제해줘」**
#
# 원인은 문체가 아니라 기계적인 것이었다: `_askPanel` 은 where·why·options 만
# 그리고 **note 는 아예 안 그린다.** note 한 덩어리로 쓴 카드는 화면에 제목만
# 뜨고, 라디오 버튼이 곧 options 이므로 **답할 방법 자체가 없었다.** 그날 그런
# 카드가 다섯 개 쌓여 있었고 둘은 다른 세션이 쓴 것이었다 — 문서에 적는 규칙이
# 잡을 수 있는 종류가 아니다.
# 🚨COLLECTED, NOT SHORT-CIRCUITED. This used to `exit 0` the moment
# board_check said anything, which meant the PR half below — merge-ready,
# red, and uncarded landings — NEVER RAN while any card anywhere in the file
# had a formatting complaint. On 2026-08-28 that was every turn, and eight of
# my own landings went uncarded behind a complaint about somebody else's
# card. ⇒ The file's own rule, written for hits/reds/cardless, applies here
# too: EVERY complaint, not the first one that matches.
# 🚨★★★A GATE THAT COULD NOT RUN IS NOT A CLEAN BOARD.
# ⛔This read stdout and threw stderr away, so every way the checker can fail
# to run -- wrong arguments, missing file -- arrived here as an empty string
# and was read as 「문제 없음」. 🧪2026-08-31 I hit the same hole by hand:
# `board_check.exe --records <path>` read nothing, exited 0, and five real
# complaints stayed invisible. The checker now exits 2 when it cannot run;
# this is the half that has to notice.
boardComplaint=""
# A server is asked with the door's secret, which sits beside the flags.
case "$PLACE" in
  http://*|https://*)
    boardThere=yes
    export ANICEL_BOARD_TOKEN_FILE="${ANICEL_BOARD_TOKEN_FILE:-$MEM/.board-token}"
    ;;
  *) boardThere=; [ -f "$PLACE" ] && boardThere=yes ;;
esac
if [ -x "$MEM/board_check.exe" ] && [ -n "$boardThere" ]; then
  gateErr="$(mktemp 2>/dev/null || echo "$MEM/.board_check.err")"
  raw=$("$MEM/board_check.exe" "$PLACE" 2>"$gateErr")
  gateCode=$?
  gateWhy=$(cat "$gateErr" 2>/dev/null)
  rm -f "$gateErr"
  if [ "$gateCode" -ge 2 ]; then
    boardComplaint="🚨board_check 가 돌지 못했습니다 (exit $gateCode) — 보드는 검사되지 않았습니다.\n$gateWhy\n\n"
  elif [ -n "$raw" ]; then
    boardComplaint="$raw\n\n칸을 고치고 턴을 끝내세요. 결정 카드의 필수 형태:\n  {\\\"kind\\\":\\\"decision\\\",\\\"id\\\":…,\\\"state\\\":\\\"ask\\\",\\\"title\\\":…,\n   \\\"where\\\":\\\"화면에서 거기까지 가는 길\\\",\n   \\\"why\\\":\\\"왜 막혔나\\\",\n   \\\"options\\\":[{\\\"key\\\":\\\"1\\\",\\\"label\\\":…,\\\"what\\\":\\\"고르면 화면이 어떻게 되나\\\",\\\"cost\\\":…}, …],\n   \\\"recommend\\\":\\\"1\\\"}\n⛔note 에 적은 설명은 유저에게 보이지 않습니다.\n\n"
  fi
fi

# --- 로그에서 사실이 사라졌나 (추가 전용이어야 한다) ----------------------
# 🚨2026-08-30. `pixel-pass-native` 가 「확인할 것」에 잘못 올라가 있었다 —
# `pr` 필드에 1269가 박혀 있었는데 그건 그 일을 **정당화한 실측**이지 착지가
# 아니었다. 내가 고른 해법은 **그 줄에서 pr 을 지우는 것**이었고, 그것은
# 「#1269가 이 일의 근거」라는 진짜 사실을 없애는 짓이었다.
#
# ⛔옳은 해법은 `rest` 필드였다. **08-26에 유저가 같은 말을 해서 그때 만들어진
# 필드**이고 주석에 유저 문장까지 들어 있는데, 나는 찾아보지 않고 발명했다.
# 유저 08-30: 「내가 말햇던걸 안지키고 두번이나 같은거 말하게 했단거네?」
#
# ⇒ 그래서 이 검사는 규칙이 아니라 **자물쇠**다. board.jsonl 은 추가 전용이고,
# 한번 적힌 (카드, PR) 짝은 사라질 수 없다. 사라졌으면 과거를 고쳐 쓴 것이다.
# ⚠️`pr` 로 좁힌 이유: 다른 필드는 나중 줄이 덮어쓰는 게 정상이지만, PR 청구는
# **누적**된다(보드가 `prs` 리스트로 모은다). 그래서 줄어들 수 있는 유일한 길이
# 과거 줄을 지우는 것뿐이다.
FACTS="$MEM/.board-prs"
if [ -f "$MEM/board.jsonl" ]; then
  # ⛔Per line, and independent of field ORDER — `pr` sits before `id` on some
  # rows and after it on others. An earlier spelling used one regex spanning
  # both and it silently matched `"pr":null` as an empty number, which put a
  # nonsense pair in the file and would have blocked for ever.
  nowPairs=$(awk '
    {
      if (match($0, "\"id\":\"[^\"]*\"") == 0) next
      id = substr($0, RSTART + 6, RLENGTH - 7)
      s = $0
      while (match(s, "\"pr\":[0-9]+")) {
        print id " " substr(s, RSTART + 5, RLENGTH - 5)
        s = substr(s, RSTART + RLENGTH)
      }
    }
  ' "$MEM/board.jsonl" 2>/dev/null | sort -u)
  if [ -f "$FACTS" ]; then
    gone=$(comm -23 "$FACTS" <(printf '%s\n' "$nowPairs") 2>/dev/null | head -10)
    if [ -n "$gone" ]; then
      cat <<JSON
{"decision":"block","reason":"board.jsonl 에서 (카드, PR) 짝이 사라졌습니다:\n$(printf '%s' "$gone" | sed 's/$/\\n/' | tr -d '\n')\n이 파일은 추가 전용이고 PR 청구는 누적됩니다 — 줄어들었다는 것은 **과거 줄을 고쳐 사실을 지웠다**는 뜻입니다.\n⛔카드가 엉뚱한 칸에 있어서 지운 것이라면 그건 08-30에 제가 한 실수 그대로입니다. 지우지 말고 **rest 필드**를 쓰세요 — 남은 것이 있으면 보드가 알아서 확인할 것에서 빼고 대기중·착수 가능으로 내립니다(유저가 08-26과 08-30 두 번 말한 그것입니다).\n⇒ 되돌리고, 그 카드에 rest 를 한 줄 적으세요."}
JSON
      exit 0
    fi
  fi
  printf '%s\n' "$nowPairs" > "$FACTS"
fi

# --- 리포 루트에 세션 산출물이 남았나 -------------------------------------
# 규칙은 오래전부터 있었고 검사가 없었다: 검증 리다이렉트는 스크래치패드로,
# 리포 루트는 유저의 작업 공간이다. 검사가 없는 동안 산출물 12개가 쌓였고
# 그중 둘(`downs=2`·`seen=6783`)은 공개 리포에 커밋까지 됐다.
# 🚨A NAME OF ITS OWN. This used to be `REPO`, and `REPO` is the SLUG the PR
# query below needs — so this line silently overwrote `myoun99/anicel` with a
# filesystem path, `gh pr list --repo C:/Users/...` failed, and the `|| exit 0`
# right after it swallowed the failure. ⇒ **the whole PR half of this gate was
# dead from the moment this check was added**, and it looked exactly like
# "nothing to block" every single turn. Found 2026-08-26 by simulating a red
# PR and getting silence — the same "the instrument is lying" shape this
# project keeps stepping in.
WORKTREE="$(cd "$HERE/../.." && pwd -W)"
if [ -d "$WORKTREE" ]; then
  junk=$(ls "$WORKTREE" 2>/dev/null | grep -E '\.log$|^downs=|^seen=|^out\.txt$' | head -20)
  if [ -n "$junk" ]; then
    list=$(echo "$junk" | tr '\n' ' ')
    cat <<JSON
{"decision":"block","reason":"리포 루트에 세션 산출물이 남았습니다: $list\n리다이렉트는 스크래치패드로 보내야 합니다(리포 폴더는 유저의 작업 공간). 지우고 턴을 끝내세요 — 검사가 없던 동안 12개가 쌓였고 그중 둘은 공개 리포에 커밋됐습니다."}
JSON
    exit 0
  fi
fi

# ⚠️No gh = the PR half cannot run, but the BOARD half already did — so
# report that rather than exiting silently. Failing open must not mean
# swallowing a complaint that needed no network.
if [ ! -x "$GH" ]; then
  if [ -n "$boardComplaint" ]; then
    printf '{"decision":"block","reason":"%s"}\n' "$boardComplaint"
  fi
  exit 0
fi

# TWO verdicts now, not one. 🚨2026-08-26, 유저: 「빨간 PR도 막는다」 — this
# gate only ever looked at CLEAN, so a PR sitting RED survived the end of a
# turn untouched. A red PR is not a wait: it is a thing to fix or close. The
# red ones got caught this far only because a watch happened to be armed,
# and that is a habit, not a mechanism.
#
# ⚠️`mergeStateStatus` cannot tell red from still-running — both read
# UNSTABLE — so the failing set comes from the check rollup instead.
# 🧪Positive-controlled before it shipped: flipped to SUCCESS the same
# selector matched all 20 recent PRs, so the traversal and the case fold
# work, and a real failed job reports `failure`, which ascii_upcase lands on
# FAILURE below. ⛔An empty result from a repo with no red PR proves nothing.
ready=$("$GH" pr list --repo "$REPO" --state open \
  --json number,title,mergeStateStatus \
  --jq '.[] | select(.mergeStateStatus=="CLEAN") | "\(.number)\t\(.title)"' \
  2>/dev/null) || exit 0
red=$("$GH" pr list --repo "$REPO" --state open \
  --json number,title,statusCheckRollup \
  --jq '.[] | select([.statusCheckRollup[]? | (.conclusion // .state // "") | ascii_upcase | select(. == "FAILURE" or . == "TIMED_OUT" or . == "ACTION_REQUIRED" or . == "ERROR")] | length > 0) | "\(.number)\t\(.title)"' \
  2>/dev/null)

# The ack file exempts a number from BOTH lists: deciding to leave a PR alone
# is one decision, whatever colour it is.
# 🚨FIRST TOKEN, not the whole line. `.gate-ack`'s own header documents the
# format as `<key> <reason>`, and tool/board_check.dart reads it that way —
# but this gate matched with `grep -qx`, whole line. So the moment anyone
# followed the documented format the ack went silently dead and the gate kept
# naming a landing that had already been accounted for. That is the third
# thing in this file to fail by looking exactly like「nothing to block」.
#
# ⛔ONE reader, called from both checks. The same question was being asked in
# two places, and only one of them had to drift for them to disagree again.
# Comment lines never match: they start with `#`, not with the key.
acked() {
  grep -qE "^$1([[:space:]]|$)" "$ACK" 2>/dev/null
}

listed() {
  out=""
  while IFS=$'\t' read -r num title; do
    [ -z "$num" ] && continue
    acked "$num" && continue
    out="$out#$num $title\\n"
  done <<< "$1"
  printf '%s' "$out"
}

# --- 내가 머지한 PR 중 카드가 없는 것 -------------------------------------
# 🚨출구는 전부 카드다(유저 2026-08-27). 카드 없는 착지는 보드에 영어 PR 제목
# 한 줄로 떠서 「무엇을 볼지」를 못 말한다 — 08-27에 그런 행이 열여덟이었고 그중
# 둘이 내 것이었다. 남의 세션 것은 내가 쓸 수 없으니 `--author @me` 로 좁힌다.
#
# ⚠️착지 기준선(landedSince) 이후만 본다. 그 전 것은 보드가 생기기 전 이력이라
# 카드가 없는 게 정상이고, 매 턴 그것들을 물고 늘어지는 게이트는 읽히지 않는다.
since=$(grep -o '"landedSince":"[^"]*"' "$MEM/board.jsonl" 2>/dev/null | tail -1 | cut -d'"' -f4)
cardless=""
lastMerge=""
if [ -n "$since" ] && [ -f "$MEM/board.jsonl" ]; then
  # 🚨ONE round trip, not two. This gate has a 15s hook timeout and already
  # measured 7.9s on three `gh` calls; a fourth for `lastMerge` alone would
  # put a slow network over the edge, and a hook that times out does not
  # complain — it simply does not run, which looks exactly like「nothing to
  # block」. So mergedAt rides along on the query that was already being
  # made, and the max is taken locally.
  mine=$("$GH" pr list --repo "$REPO" --state merged --author @me --limit 40 \
    --json number,title,mergedAt \
    --jq ".[] | select(.mergedAt > \"$since\") | \"\(.number)\t\(.title)\t\(.mergedAt)\"" 2>/dev/null)
  # When my most recent landing happened, in THIS machine's clock — the board
  # writes local timestamps and gh answers in UTC, so one of them has to move
  # before they can be compared. See the stale-card check below.
  lastMerge=$(printf '%s' "$mine" | cut -f3 | sort | tail -1)
  [ -n "$lastMerge" ] && lastMerge=$(date -d "$lastMerge" +%Y-%m-%dT%H:%M:%S 2>/dev/null)
  while IFS=$'\t' read -r num title _mergedAt; do
    [ -z "$num" ] && continue
    # ⚠️THE ACK IS FOR ANOTHER SESSION'S LANDING, and only that.
    # `--author @me` cannot tell sessions apart — every session on this
    # machine pushes as the same account — so a merge listed here may be
    # one I never made, and I cannot write its card. ⛔It is NOT a way out
    # of carding my own: those have no legitimate uncarded state.
    acked "$num" && continue
    # ⏱🚨★★★A LANDING GETS A GRACE PERIOD BEFORE IT COUNTS AS UNCARDED.
    #
    # ⛔Without one this fires the instant a PR merges, and the session that
    # merged it has not written its card yet — so the OTHER session sees a
    # bare landing, cannot tell whose it is (one account, `--author @me` on
    # everything), and acks it as 「남의 세션」. Minutes later the owner cards
    # it and the ack is dead. 🧪It happened three times in one evening:
    # #1400 and #1403 were MINE and another session acked them away, and I
    # acked #1402 and #1404 which their owner carded right after.
    #
    # ⇒ Twenty minutes. Long enough that the owner has finished the turn it
    # merged in; short enough that a landing nobody cards still gets named
    # the same evening. **Nobody has to guess whose PR it is any more.**
    if [ -n "$_mergedAt" ]; then
      ageMin=$(( ( $(date +%s) - $(date -d "$_mergedAt" +%s 2>/dev/null || echo 0) ) / 60 ))
      [ "$ageMin" -lt 20 ] && continue
    fi
    # 🚨THE COMPARISON, which this loop went without. From the day it was
    # added until 2026-08-28 the body did nothing but `continue` — it never
    # looked at board.jsonl and never appended, so `cardless` was ALWAYS
    # empty and this half of the gate was dead. That is the SECOND dead half
    # in this file (the first is the `REPO` overwrite documented above), and
    # both looked exactly like "nothing to block" every single turn.
    # ⇒ The user found eight uncarded landings by scrolling the board.
    #
    # A card counts if the board mentions the number either way it can be
    # written: the `pr` field the gate's own message asks for, or `#1234`
    # inside a note.
    if grep -q "\"pr\":$num\b" "$MEM/board.jsonl" 2>/dev/null; then
      continue
    fi
    if grep -q "#$num\b" "$MEM/board.jsonl" 2>/dev/null; then
      continue
    fi
    cardless="$cardless#$num $title\n"
  done <<< "$mine"
fi

# --- 답이 온 뒤로 착수 전 칸에 그대로 앉아 있는 카드 → board_check 로 갔다 ---
# 🪦2026-08-31에 여기서 지웠다. 이 자리에는 awk 로 **보드 머지를 다시 구현한**
# 80줄이 있었다 — `at`·`state`·`title`·`rest`·`pr`·`answer` 를 손으로 합치고
# 「a != "착수 가능" && a != "구현" …」로 칸을 판정했다.
#
# ⛔그 판정은 이제 틀렸을 뿐 아니라 **두 번째 리더**다. 칸은 이야기의 마지막
# 대분류가 정하고, 그 답은 `board_model.dart` 하나가 갖는다. 셸이 자기 사본으로
# 같은 질문에 답하는 것이 바로 이번 개편이 없앤 버그이고, 하필 그걸 잡으라고
# 있는 물건 안에 있었다.
#
# 🔑둘 다 Dart 게이트가 흡수했다:
# · 「답이 온 뒤로 착수 전 칸」 — 답은 이제 카드에 `유저` 항목으로 접혀 들어가
#   카드를 분류 전으로 데려온다. 거기 하루 넘게 있으면 board_check 가 말한다.
#   **구조적으로 놓칠 수 없게 됐으므로 규칙이 아니라 모델이 답한다.**
# · 「pr 을 들고 queue/inbox 인데 rest 가 비었다」 — board_check 의
#   「착지했는데 실기 확인으로 안 올라온 카드」와 같은 질문이다.
hits=$(listed "$ready")
reds=$(listed "$red")
# 🚨EVERY complaint, not the first one that matches. This used to fire only
# when nothing ELSE was wrong, so a single open green PR hid every uncarded
# landing behind it — and on a day with PRs in flight back to back, that is
# every turn. 08-27: four landings went uncarded that way and the user found
# them, not the gate.
[ -z "$hits" ] && [ -z "$reds" ] && [ -z "$cardless" ] && [ -z "$boardComplaint" ] && exit 0

reason="$boardComplaint"
if [ -n "$cardless" ]; then
  reason="$reason내가 머지했는데 카드가 없는 PR:\n$cardless\n출구는 전부 카드입니다 — 카드 없는 착지는 보드에 영어 PR 제목 한 줄로 떠서 「무엇을 볼지」를 못 말합니다.\n⇒ board.jsonl 에 그 착지의 구현 공정을 한 줄 적으세요: at=구현 · pr=번호 · note=무엇을 왜 바꿨나 · how=이렇게 확인한다.\n⚠️남의 세션 착지면(계정이 하나라 구분이 안 됩니다) 번호를 .gate-ack 에 적고 유저에게 말하세요 — 내 것이면 카드 없이 넘어갈 길은 없습니다.\n";
fi
if [ -n "$reds" ]; then
  reason="$reasonCI가 빨간 PR이 열린 채로 턴이 끝나려 합니다:\\n$reds\\n빨간 것은 기다림이 아닙니다 — 고치거나 닫아야 할 것입니다. 로그부터: gh api repos/$REPO/actions/jobs/<잡ID>/logs\\n"
fi
if [ -n "$hits" ]; then
  reason="$reason머지 준비가 끝난 PR이 열린 채로 턴이 끝나려 합니다:\\n$hits\\n2026-08-22에 이걸로 초록인 PR이 두 시간 방치됐습니다 — 「CI 끝나면 머지하겠다」고 쓰는 것은 아무것도 안 하는 것입니다.\\n1) bash tool/merge_check.sh <번호> 가 exit 0 이면 gh pr merge --squash --delete-branch, 그리고 본진·워크트리 둘 다 pull\\n"
fi

cat <<JSON
{"decision":"block","reason":"${reason}2) 손대면 안 되는 이유가 있으면 그 번호를 '$ACK' 에 한 줄로 적고(이유는 유저에게 말할 것)\\n3) merge_check 가 막으면 그 이유를 유저에게 보고\\n⛔이 턴에서 결정하세요. 「나중에」의 나중은 영영 오지 않습니다."}
JSON
