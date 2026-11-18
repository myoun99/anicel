#!/bin/bash
# Whether the probe's report (lib/main.dart) says the screen showed the very
# bytes the GPU wrote — the GPU engine's CI asks it of each platform's
# plugin half (.github/workflows/gpu-engine.yml).
#
#   bash report_matched.sh <report.txt>
#
# Prints the report; exit 0 when it ran to DONE, compared the screen at
# least once and every comparison was a MATCH. A surface a platform
# refuses (RGBA on iOS and macOS, BGRA on Linux) is reported and compared
# with nothing, so it counts neither way.

report="$1"
if [ ! -f "$report" ]; then
  echo "report_matched: no report at $report" >&2
  exit 1
fi
cat "$report"
grep -q '^DONE$' "$report" || { echo "report_matched: the probe did not finish" >&2; exit 1; }
if grep -q 'MISMATCH' "$report"; then
  echo "report_matched: the screen showed other bytes" >&2
  exit 1
fi
grep -q 'screen bytes .*: MATCH$' "$report" || {
  echo "report_matched: the screen was compared nowhere" >&2
  exit 1
}
