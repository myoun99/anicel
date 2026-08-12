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

REPO=$("$GH" repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)
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

info=$("$GH" pr view "$PR" --repo "$REPO" \
  --json headRefName,mergeStateStatus,statusCheckRollup \
  --jq '"\(.headRefName)\t\(.mergeStateStatus)\t\([.statusCheckRollup[] | if (.conclusion // "") == "" then "PENDING" else .conclusion end] | join(","))"' 2>/dev/null)
if [ -z "$info" ]; then
  echo "could not read PR #$PR from $REPO." >&2
  exit 2
fi

branch=$(printf '%s' "$info" | cut -f1)
state=$(printf '%s' "$info" | cut -f2)
checks=$(printf '%s' "$info" | cut -f3)

total=$(printf '%s' "$checks" | tr ',' '\n' | grep -c .)
bad=$(printf '%s' "$checks" | tr ',' '\n' | grep -cv '^SUCCESS$')
behind=$("$GH" api "repos/$REPO/compare/master...$branch" --jq '.behind_by' 2>/dev/null)
[ -z "$behind" ] && behind="?"

# Files this PR touches, against every other open PR's files. A shared file
# is not proof of a conflict — it is the only cheap signal that one is
# possible, and it is the signal an author working in one branch cannot see.
mine=$("$GH" pr view "$PR" --repo "$REPO" --json files --jq '.files[].path' 2>/dev/null | sort)
overlaps=""
for other in $("$GH" pr list --repo "$REPO" --state open --json number --jq '.[].number' 2>/dev/null); do
  [ "$other" = "$PR" ] && continue
  shared=$("$GH" pr view "$other" --repo "$REPO" --json files --jq '.files[].path' 2>/dev/null \
    | sort | comm -12 - <(printf '%s\n' "$mine") | head -5)
  [ -n "$shared" ] && overlaps="$overlaps\n  #$other shares:\n$(printf '%s' "$shared" | sed 's/^/    /')"
done

echo "PR #$PR  ($branch)  in $REPO"
echo "  mergeable state : $state"
echo "  checks          : $total total, $bad not SUCCESS"
echo "  behind master   : $behind commit(s)"
if [ -n "$overlaps" ]; then
  # shellcheck disable=SC2059
  printf "  open PRs touching the same files:$overlaps\n"
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
[ "$state" != "CLEAN" ] && echo "  - GitHub says $state (DIRTY means it conflicts with master)."
[ "$bad" -ne 0 ] && echo "  - $bad check(s) are not SUCCESS."
[ "$behind" != "0" ] && echo "  - $behind commit(s) behind master: the green above was earned against"
[ "$behind" != "0" ] && echo "    a master that no longer exists. Rebase and let CI run again."
exit 1
