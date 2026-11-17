# THE MACHINE'S MEASUREMENT WINDOW, as the shell reads it — for
# tool/cargo_turn.sh and tool/lane.sh. tool/measure_window.dart opens and
# closes it and says what it is for; this reads the same file and says the
# same words (TWO READERS, NOT THREE — change both or neither).
# Sourced after tool/machine_folder.sh: it sets MEASURE_WINDOW and starts
# nothing.
MEASURE_WINDOW="$MACHINE_FOLDER/test_queue/window"

# While the window is open: the words a run that waits for it says, and
# success. Closed, or past its deadline: nothing, and failure.
window_words() {
  local until= who=
  { IFS=$'\t' read -r until who <"$MEASURE_WINDOW"; } 2>/dev/null || return 1
  case "$until" in '' | *[!0-9]*) return 1 ;; esac
  [ "$(date +%s)" -lt "$until" ] || return 1
  # GNU date reads `-d @seconds`; the Mac's reads `-r seconds`.
  echo "기다리는 중 — 측정 창($who · $(date -d "@$until" +%H:%M 2>/dev/null \
    || date -r "$until" +%H:%M)까지)"
}
