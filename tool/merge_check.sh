#!/usr/bin/env bash
#
# Is this pull request actually safe to merge?
#
# GitHub's green tick answers "did the checks pass", not "did they pass
# against the master you are about to merge into". Those came apart on
# 2026-08-12: #939 sat at five green checks and its author reported it as
# ready, but #959 had landed in the meantime and added a required argument
# to importMediaFiles — the branch no longer compiled against the master it
# was aiming at. Nothing on the PR page said so.
#
# Branch protection can enforce this ("require branches to be up to date"),
# and we deliberately do not turn it on: it makes every second open PR pay a
# rebase and a full CI round. This script is the cheap half of that trade —
# it costs three API calls and tells you the same thing.
#
# The third question is the one no PR page can answer, because it is about
# OTHER pull requests: does anything else in flight touch the same files?
# Two branches can both be CLEAN and both be up to date and still break each
# other on merge, and the first you hear of it is a red master.
#
# Exit code is the verdict: 0 merge it, 1 do not, 2 could not tell,
# 3 behind master but only in files this PR never touched — your call.
#
# Usage:
#   bash tool/merge_check.sh          # the PR for the current branch
#   bash tool/merge_check.sh 964      # a specific PR

set -uo pipefail

# gh is not on PATH in the usual Windows install, and hardcoding the Windows
# path would make this script useless on the machines that build the Apple
# and Linux targets.
if command -v gh > /dev/null 2>&1; then
  GH=gh
elif [ -x "/c/Program Files/GitHub CLI/gh.exe" ]; then
  GH="/c/Program Files/GitHub CLI/gh.exe"
elif [ -x "C:/Program Files/GitHub CLI/gh.exe" ]; then
  GH="C:/Program Files/GitHub CLI/gh.exe"
else
  echo "gh (GitHub CLI) not found — install it or put it on PATH." >&2
  exit 2
fi

# Every gh call is a process launch, and a process launch is not free on a
# loaded machine: with the test suite running locally this box sat at 100%
# CPU and `gh --version` — no network, no auth — took 20 SECONDS. So this
# script is written to make three gh calls, not one per question. Read the
# remote from git rather than asking gh for it; that is one launch saved of
# something an order of magnitude cheaper to start.
REPO=$(git remote get-url origin 2>/dev/null \
  | sed -E 's#^.*github\.com[:/]+##; s#\.git$##; s#/+$##')
if [ -z "$REPO" ]; then
  echo "could not resolve the repository — run this inside the checkout." >&2
  exit 2
fi

PR="${1:-}"
if [ -z "$PR" ]; then
  PR=$("$GH" pr view --json number --jq .number 2>/dev/null)
  if [ -z "$PR" ]; then
    echo "no pull request for the current branch — pass a number." >&2
    exit 2
  fi
fi

# One call for everything this PR can tell us — state, checks, and the files
# it touches — rather than one call per field.
info=$("$GH" pr view "$PR" --repo "$REPO" \
  --json state,headRefName,mergeStateStatus,statusCheckRollup,files \
  --jq '"\(.state)\t\(.headRefName)\t\(.mergeStateStatus)\t\([.statusCheckRollup[] | if (.conclusion // "") == "" then "PENDING" else .conclusion end] | join(","))\t\([.files[].path] | join(","))"' 2>/dev/null)
if [ -z "$info" ]; then
  echo "could not read PR #$PR from $REPO." >&2
  exit 2
fi

prstate=$(printf '%s' "$info" | cut -f1)
branch=$(printf '%s' "$info" | cut -f2)
state=$(printf '%s' "$info" | cut -f3)
checks=$(printf '%s' "$info" | cut -f4)
myfiles=$(printf '%s' "$info" | cut -f5)

# A merged or closed PR has nothing to decide, and its head branch is
# usually deleted — which makes every question below meaningless rather
# than alarming. Say so instead of reporting it as unmergeable.
if [ "$prstate" != "OPEN" ]; then
  echo "PR #$PR ($branch) is $prstate — nothing to merge."
  exit 2
fi

# Counted apart, because "has not finished" and "went wrong" are different
# news and putting them in one number reads as the worse one. This printed
# "13 total, 12 not SUCCESS" while nothing had failed at all — twelve jobs
# were simply still running — and the first reading of that was a broken
# branch. The same confusion cost an hour on 2026-08-15 elsewhere: a hung
# job shows up as `pending 0` in `gh pr checks`, indistinguishable from one
# that has not started.
total=$(printf '%s' "$checks" | tr ',' '\n' | grep -c .)
pending=$(printf '%s' "$checks" | tr ',' '\n' | grep -c '^PENDING$')
failed=$(printf '%s' "$checks" | tr ',' '\n' | grep -cv '^SUCCESS$\|^PENDING$')
# The verdict below still turns on "not green", which is both of them.
bad=$((pending + failed))
# Compared the other way round on purpose: base=branch, head=master makes
# `ahead_by` the number of commits this branch is BEHIND, and hands back the
# files THOSE commits touched in the same response. One call, two answers.
#
# Being behind is not one situation but two, and they deserve different
# advice. Master moving in files you never touched is routine — in a repo
# with several branches in flight it happens during every CI round, and
# rebasing for it is a treadmill. Master moving in files you also changed is
# the one that earned this script.
#
# gh prints an API error BODY to stdout, so a 404 arrives as JSON rather
# than as an empty string; anything non-numeric is "we could not tell".
cmp=$("$GH" api "repos/$REPO/compare/$branch...master" \
  --jq '"\(.ahead_by)\t\([.files[].filename] | join(","))"' 2>/dev/null)
behind=$(printf '%s' "$cmp" | cut -f1)
theirfiles=$(printf '%s' "$cmp" | cut -f2)
case "$behind" in
  '' | *[!0-9]*) behind="?"; theirfiles="" ;;
esac

# The compare API returns at most 300 files. Past that we cannot claim the
# intersection is empty, so we do not.
their_count=$(printf '%s' "$theirfiles" | tr ',' '\n' | grep -c .)
truncated=no
[ "$their_count" -ge 300 ] && truncated=yes

collided=$(printf '%s\n' "$theirfiles" | awk -F',' -v mine="$myfiles" '
  BEGIN {
    n = split(mine, m, ",")
    for (i = 1; i <= n; i++) have[m[i]] = 1
  }
  {
    c = split($0, f, ",")
    for (i = 1; i <= c; i++) if (f[i] in have) print f[i]
  }' | sort -u)
collided_count=$(printf '%s' "$collided" | grep -c . || true)

# Every other open PR's files, in ONE call rather than one call per PR. A
# shared file is not proof of a conflict — it is the only cheap signal that
# one is possible, and it is the signal an author working inside a single
# branch cannot see.
others=$("$GH" pr list --repo "$REPO" --state open --json number,files \
  --jq '.[] | "\(.number)\t\([.files[].path] | join(","))"' 2>/dev/null)
overlaps=$(printf '%s\n' "$others" | awk -F'\t' -v me="$PR" -v mine="$myfiles" '
  BEGIN {
    n = split(mine, m, ",")
    for (i = 1; i <= n; i++) have[m[i]] = 1
  }
  $1 != "" && $1 != me {
    c = split($2, f, ",")
    shown = 0
    for (i = 1; i <= c; i++) {
      if (f[i] in have) {
        if (shown == 0) printf "  #%s shares:\n", $1
        shown++
        if (shown <= 5) printf "    %s\n", f[i]
      }
    }
    if (shown > 5) printf "    ...and %d more\n", shown - 5
  }')

echo "PR #$PR  ($branch)  in $REPO"
echo "  mergeable state : $state"
if [ "$bad" -eq 0 ]; then
  echo "  checks          : $total, all green"
else
  echo "  checks          : $total — $failed failed, $pending still running"
fi
if [ "$behind" = "0" ] || [ "$behind" = "?" ]; then
  echo "  behind master   : $behind commit(s)"
elif [ "$collided_count" -eq 0 ] && [ "$truncated" = "no" ]; then
  echo "  behind master   : $behind commit(s), touching $their_count file(s)," \
    "none of them yours"
else
  echo "  behind master   : $behind commit(s), touching $their_count file(s)," \
    "$collided_count of them yours"
  printf '%s\n' "$collided" | sed 's/^/                      /' | head -5
fi
if [ -n "$overlaps" ]; then
  echo "  open PRs touching the same files:"
  printf '%s\n' "$overlaps"
else
  echo "  open PRs touching the same files: none"
fi
echo

if [ "$state" = "CLEAN" ] && [ "$bad" -eq 0 ] && [ "$behind" = "0" ]; then
  if [ -n "$overlaps" ]; then
    echo "MERGE IT — but the PRs listed above will need a rebase afterwards,"
    echo "and their green is stale the moment this lands."
  else
    echo "MERGE IT."
  fi
  exit 0
fi

# Behind in files you never touched, with everything else clean, is the one
# failure that is usually not a failure — and in a repo where master moves
# several times per CI round, treating it as one means rebasing forever.
# It gets its own exit code so a caller can tell the two apart, and a
# paragraph rather than an order, because the call is a human's.
if [ "$state" != "DIRTY" ] && [ "$bad" -eq 0 ] && [ "$behind" != "0" ] \
  && [ "$behind" != "?" ] && [ "$collided_count" -eq 0 ] && [ "$truncated" = "no" ]; then
  echo "YOUR CALL:"
  echo "  - $behind commit(s) landed on master while this ran, but none of"
  echo "    them touched a file this PR touches, so the green above is"
  echo "    probably still true."
  echo "  - Probably, not certainly: a change can break you through an API"
  echo "    you call in a file you never edited. If this PR calls into"
  echo "    anything those commits rewrote, rebase instead."
  exit 3
fi

echo "DO NOT MERGE:"
case "$state" in
  CLEAN) ;;
  DIRTY)
    echo "  - GitHub says DIRTY: this branch conflicts with master."
    ;;
  UNKNOWN)
    echo "  - GitHub has not finished working out whether this merges"
    echo "    (UNKNOWN). Ask again in a moment rather than believing it."
    ;;
  *)
    echo "  - GitHub says $state."
    ;;
esac
[ "$failed" -ne 0 ] && echo "  - $failed check(s) FAILED."
[ "$pending" -ne 0 ] && echo "  - $pending check(s) have not finished — this is a wait, not a break."
if [ "$behind" != "0" ] && [ "$behind" != "?" ]; then
  if [ "$collided_count" -gt 0 ]; then
    echo "  - $behind commit(s) behind master, and they changed" \
      "$collided_count file(s)"
    echo "    this PR also changed. The green above was earned against a"
    echo "    master that no longer exists. Rebase and let CI run again."
  else
    echo "  - $behind commit(s) behind master. Rebase and let CI run again."
  fi
fi
exit 1
