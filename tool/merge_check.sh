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
# Usage:
#   bash tool/merge_check.sh          # the PR for the current branch
#   bash tool/merge_check.sh 964      # a specific PR
#
# Exit code is the verdict: 0 = merge it, 1 = do not.

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

total=$(printf '%s' "$checks" | tr ',' '\n' | grep -c .)
bad=$(printf '%s' "$checks" | tr ',' '\n' | grep -cv '^SUCCESS$')
# gh prints an API error BODY to stdout, so a 404 here arrives as JSON, not
# as an empty string — and an unchecked `behind` would print that JSON where
# a number belongs. Anything non-numeric is "we could not tell".
behind=$("$GH" api "repos/$REPO/compare/master...$branch" --jq '.behind_by' 2>/dev/null)
case "$behind" in
  '' | *[!0-9]*) behind="?" ;;
esac

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
echo "  checks          : $total total, $bad not SUCCESS"
echo "  behind master   : $behind commit(s)"
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
[ "$bad" -ne 0 ] && echo "  - $bad check(s) are not SUCCESS."
[ "$behind" != "0" ] && echo "  - $behind commit(s) behind master: the green above was earned against"
[ "$behind" != "0" ] && echo "    a master that no longer exists. Rebase and let CI run again."
exit 1
