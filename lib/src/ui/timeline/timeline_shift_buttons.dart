import 'package:flutter/material.dart';

import '../../models/timeline_row_address.dart';
import '../editor_session_manager.dart';
import '../shortcuts/editor_action_registry.dart';
import '../sliced_value_listenable_builder.dart';
import '../text/app_strings.dart';
import '../widgets/app_icon_button.dart';
import 'toolbar_panel_context.dart';

/// THE push / pull pair (design D), shared by every rail that has rows.
///
/// One pair, not one per axis: a cut is a block on the cut row exactly as
/// an exposure is a block on a layer row, so "shove from here" is one verb
/// aimed at whatever is selected. The session picks the axis and the
/// commit; the button only says which rail is asking, for the one case
/// where nothing is selected at all.
/// The pair owns its own subscriptions rather than making whatever mounts it
/// rebuild. Two booleans re-derived per signal (measured at 3.7µs), and a
/// rebuild only when one of them flips: the alternative was the host
/// rebuilding its whole command bar per arrow press (11ms of build).
///
/// 🚨T17 — it subscribes to TWO things, and the second one was missing.
/// This class used to say the pair "gates on the SHIFT ANCHOR, which is the
/// playhead", and subscribed to committed seeks alone. That was half the
/// truth: [EditorSessionManager.canPullBlocks] also asks whether there is
/// SLACK BEHIND the block — the arrangement — and an arrangement changes by
/// EDITING, not by seeking. So pressing push opened a gap and pull stayed
/// grey, holding the answer from the last committed seek; stepping one frame
/// away and back "fixed" it, which is how the user found it.
///
/// The parent cannot cover this: the bar around the pair is kept while it is
/// built for the same thing, and no push/pull answer is among those things.
///
/// ★The law it broke is the one this codebase keeps re-learning: **what a
/// predicate READS and what its widget SUBSCRIBES to have to be the same
/// set**, or the button answers about a moment that has passed. ↩️The pair
/// kept its own two listeners and its own flip gate; it hears the bar's one
/// list now ([toolbarGateNews] — the bands and the stand its scope reads
/// were heard only through the bar's host) through the one slice every
/// group on the bar answers with (a-gate-rebuilds-the-whole-toolbar,
/// 2026-10-24).
class TimelineShiftButtons extends StatelessWidget {
  const TimelineShiftButtons({super.key, required this.session, this.panel});

  final EditorSessionManager session;

  /// The asking rail, whose [ToolbarPanelContext.shiftCurrentRow] is read
  /// ONLY when nothing is selected (the timeline's "current row at the
  /// current cell" rule) — the row its push/pull keys aim at too. The
  /// timeline's answers null: its current row is the active layer, which is
  /// the session's own fallback, as it is with no panel at all.
  final ToolbarPanelContext? panel;

  /// What the pair shows: both answers, the row they were asked about and
  /// the words of the tooltips.
  (bool, bool, TimelineRowAddress?, Object) _shown() {
    final currentRow = panel?.shiftCurrentRow;
    return (
      session.blockShift.canPushBlocks(currentRow: currentRow),
      session.blockShift.canPullBlocks(currentRow: currentRow),
      currentRow,
      session.languageSettings.value,
    );
  }

  @override
  Widget build(BuildContext context) => SlicedListenableBuilder(
    listenable: toolbarGateNews(session),
    slice: _shown,
    builder: (context, shown) {
      final (canPush, canPull, currentRow, _) = shown;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIconButton(
            keyValue: 'push-blocks-button',
            tooltip: AppText.strings.tlPush,
            shortcuts: const [EditorActionIds.timelinePushBlocks],
            icon: const Icon(Icons.keyboard_tab),
            onPressed: canPush
                ? () => session.blockShift.pushBlocks(1, currentRow: currentRow)
                : null,
          ),
          AppIconButton(
            keyValue: 'pull-blocks-button',
            tooltip: AppText.strings.tlPull,
            shortcuts: const [EditorActionIds.timelinePullBlocks],
            icon: const Icon(Icons.keyboard_backspace),
            onPressed: canPull
                ? () => session.blockShift.pullBlocks(1, currentRow: currentRow)
                : null,
          ),
        ],
      );
    },
  );
}
