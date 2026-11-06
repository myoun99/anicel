#!/usr/bin/env bash
# THE PACKAGES THE APP DOES NOT DEPEND ON, resolved in their own folders.
#
#   bash tool/resolve_packages.sh <checkout> [<flags for pub get>...]
#
# `flutter analyze` with no arguments -- the merge gate -- descends into
# them, but the root's `pub get` never resolves them, so a checkout that has
# not run theirs reads every import as missing: 16 errors for
# packages/gpu_engine (measured 2026-11-05). The user chose that the gate
# resolve and analyze it rather than leave it out (gpu-engine-skeleton-Q2).
# One `pub get` there resolves its example/ too.
#
# The one list, read by both places the gate runs: tool/lane.sh
# (resolve_packages) and CI's analyze job. The lanes pass --offline — a
# download is the user's to allow, in chat (관제 2026-11-06,
# native-memory-safety; tool/lane.sh resolve_offline) — and CI passes
# nothing: its runner starts with no packages at all.
set -u

checkout="${1:-.}"
[ $# -eq 0 ] || shift
for package in packages/gpu_engine; do
  [ -f "$checkout/$package/pubspec.yaml" ] || continue
  (cd "$checkout" && flutter pub get "$@" --directory "$package") || exit 1
done
