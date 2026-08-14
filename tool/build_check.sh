#!/usr/bin/env bash
#
# Is master worth shipping to the iPad right now, and what would ship?
#
# Two questions, and the second is the one that gets skipped. "Is CI green"
# is easy to remember; "what am I actually putting on somebody's device" is
# not, and the answer matters most when a session has just merged six things
# you did not read.
#
# What this deliberately does NOT check: anything about apple.yml. That used
# to belong here — before a build you had to work out whether the last Apple
# run had seen this commit, and on 2026-08-14 that reasoning went wrong (the
# newest apple.yml success was a BRANCH run, not master). The fix was not a
# better check, it was moving the check into testflight.yml itself, where the
# release path cannot skip it. Do not add it back here.
#
# Usage:
#   bash tool/build_check.sh
#
# Exit code is the verdict: 0 ship it, 1 do not, 2 could not tell.

set -uo pipefail

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

REPO=$(git remote get-url origin 2>/dev/null \
  | sed -E 's#^.*github\.com[:/]+##; s#\.git$##; s#/+$##')
if [ -z "$REPO" ]; then
  echo "could not resolve the repository — run this inside the checkout." >&2
  exit 2
fi

git fetch --quiet --prune origin 2>/dev/null
head=$(git rev-parse origin/master 2>/dev/null)
if [ -z "$head" ]; then
  echo "could not read origin/master." >&2
  exit 2
fi
short=${head:0:8}

# Three calls, because on a loaded machine each gh launch costs more than
# the query does — see the note in merge_check.sh.
ci=$("$GH" run list --repo "$REPO" --workflow ci.yml --branch master --limit 8 \
  --json headSha,status,conclusion \
  --jq '.[] | "\(.headSha)\t\(.status)\t\(.conclusion // "-")"' 2>/dev/null)
last_build=$("$GH" run list --repo "$REPO" --workflow testflight.yml --limit 12 \
  --json headSha,conclusion,number \
  --jq '[.[] | select(.conclusion == "success")][0] | "\(.headSha)\t\(.number)"' 2>/dev/null)
open_prs=$("$GH" pr list --repo "$REPO" --state open --limit 30 \
  --json number,title --jq '.[] | "  #\(.number) \(.title)"' 2>/dev/null)

ci_line=$(printf '%s\n' "$ci" | awk -F'\t' -v h="$head" '$1 == h {print; exit}')
ci_status=$(printf '%s' "$ci_line" | cut -f2)
ci_conclusion=$(printf '%s' "$ci_line" | cut -f3)

built_sha=$(printf '%s' "$last_build" | cut -f1)
built_number=$(printf '%s' "$last_build" | cut -f2)

echo "master $short — $(git log -1 --format=%s "$head" | cut -c1-60)"
if [ -z "$ci_line" ]; then
  echo "  CI            : no run for this commit yet"
else
  echo "  CI            : $ci_status/$ci_conclusion"
fi

# What would ship that is not already on the device. This is the half people
# skip, and it is the half that tells you whether to ship at all.
if [ -n "$built_sha" ] && git cat-file -e "$built_sha^{commit}" 2>/dev/null; then
  ahead=$(git rev-list --count "$built_sha..$head" 2>/dev/null)
  echo "  last shipped  : build #$built_number (${built_sha:0:8}), $ahead commit(s) ago"
  if [ "${ahead:-0}" -gt 0 ]; then
    echo "  new in this build:"
    git log --oneline "$built_sha..$head" | head -12 | sed 's/^/    /'
    extra=$((ahead - 12))
    [ "$extra" -gt 0 ] && echo "    ...and $extra more"
  fi
else
  echo "  last shipped  : unknown (no successful TestFlight run found locally)"
fi

if [ -n "$open_prs" ]; then
  echo "  open PRs (not in this build):"
  printf '%s\n' "$open_prs"
fi
echo

if [ -z "$ci_line" ]; then
  echo "CANNOT TELL: no CI run for $short. Push moved fast, or the run was"
  echo "cancelled — look before shipping."
  exit 2
fi
if [ "$ci_status" != "completed" ]; then
  echo "WAIT: CI is still $ci_status on $short."
  exit 1
fi
if [ "$ci_conclusion" != "success" ]; then
  echo "DO NOT SHIP: CI concluded $ci_conclusion on $short."
  exit 1
fi

echo "SHIP IT — CI green on $short."
echo "  gh workflow run testflight.yml --repo $REPO --ref master"
echo "  (the build runs the Apple parity check itself; nothing to dispatch first)"
exit 0
