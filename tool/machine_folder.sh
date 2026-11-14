# The machine's own folder for what the tools keep — per account, never
# synced: Windows' local app data, else the cache folder. It is
# `machineCacheFolder` of tool/test_seconds.dart, spelt for the shell, and
# the one shell spelling: tool/run.sh builds its exes under it and
# tool/lane.sh keeps its crate greens there (2026-11-14 — a third copy was
# about to be written).
# Sourced: it sets MACHINE_FOLDER and starts nothing, for run.sh pays for
# every step on every call.
if [ -n "${LOCALAPPDATA:-}" ]; then
  MACHINE_FOLDER="${LOCALAPPDATA//\\//}/anicel"
else
  MACHINE_FOLDER="${XDG_CACHE_HOME:-$HOME/.cache}/anicel"
fi
