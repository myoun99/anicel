import 'package:flutter/material.dart';

import '../../models/timeline_row_address.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import '../widgets/app_icon_button.dart';

/// THE push / pull pair (design D), shared by every rail that has rows.
///
/// One pair, not one per axis: a cut is a block on the cut row exactly as
/// an exposure is a block on a layer row, so "shove from here" is one verb
/// aimed at whatever is selected. The session picks the axis and the
/// commit; the button only says which rail is asking, for the one case
/// where nothing is selected at all.
/// The pair owns its own subscriptions rather than making whatever mounts it
/// rebuild. Two booleans re-derived per signal (measured at 3.7µs), and a
/// `setState` only when one of them flips: the alternative was the host
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
/// The parent cannot cover this: the action toolbar is cached on
/// `_deriveActionsToken`, and no push/pull dimension is in that token, so a
/// notify that changed only the arrangement never reaches this widget as a
/// rebuild either.
///
/// ★The law it broke is the one this codebase keeps re-learning: **what a
/// predicate READS and what its widget SUBSCRIBES to have to be the same
/// set**, or the button answers about a moment that has passed.
class TimelineShiftButtons extends StatefulWidget {
  const TimelineShiftButtons({
    super.key,
    required this.session,
    this.currentRow,
  });

  final EditorSessionManager session;

  /// The asking rail's current row — read ONLY when nothing is selected
  /// (the timeline's "current row at the current cell" rule). The timeline
  /// leaves it null: its current row is the active layer, which is the
  /// session's own fallback.
  final TimelineRowAddress? currentRow;

  @override
  State<TimelineShiftButtons> createState() => _TimelineShiftButtonsState();
}

class _TimelineShiftButtonsState extends State<TimelineShiftButtons> {
  late bool _canPush;
  late bool _canPull;

  bool get _derivedPush =>
      widget.session.canPushBlocks(currentRow: widget.currentRow);
  bool get _derivedPull =>
      widget.session.canPullBlocks(currentRow: widget.currentRow);

  /// Re-derives after a signal that does NOT come through a parent rebuild.
  ///
  /// The flip gate is what keeps the session subscription cheap: an edit that
  /// leaves both answers alone (drawing a stroke, renaming a layer) costs the
  /// two derivations and stops there.
  void _reread() {
    final canPush = _derivedPush;
    final canPull = _derivedPull;
    if (canPush == _canPush && canPull == _canPull) {
      return;
    }
    setState(() {
      _canPush = canPush;
      _canPull = canPull;
    });
  }

  void _listen(EditorSessionManager session) {
    // The ANCHOR moving (a seek is not a session notify), in every way it
    // can move — #10 (2026-08-21). This used to be `frameSeekCommitted`
    // alone, which fires on the RELEASE, so a ruler drag held both answers
    // at the frame it began on; and past the film's end the playhead moves
    // by PARKING, which is a third channel again. One listenable answers
    // all of them, and the flip gate in [_reread] keeps it cheap.
    session.playheadMoved.addListener(_reread);
    // … and the ARRANGEMENT changing (T17). An edit notifies; a seek does not.
    // Both are needed because the two predicates read both.
    session.addListener(_reread);
  }

  void _unlisten(EditorSessionManager session) {
    session.playheadMoved.removeListener(_reread);
    session.removeListener(_reread);
  }

  @override
  void initState() {
    super.initState();
    _canPush = _derivedPush;
    _canPull = _derivedPull;
    _listen(widget.session);
  }

  @override
  void didUpdateWidget(covariant TimelineShiftButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      _unlisten(oldWidget.session);
      _listen(widget.session);
    }
    // Already rebuilding — assign, never setState.
    _canPush = _derivedPush;
    _canPull = _derivedPull;
  }

  @override
  void dispose() {
    _unlisten(widget.session);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final currentRow = widget.currentRow;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconButton(
          keyValue: 'push-blocks-button',
          tooltip: AppText.strings.tlPush,
          icon: const Icon(Icons.keyboard_tab),
          onPressed: _canPush
              ? () => session.pushBlocks(1, currentRow: currentRow)
              : null,
        ),
        AppIconButton(
          keyValue: 'pull-blocks-button',
          tooltip: AppText.strings.tlPull,
          icon: const Icon(Icons.keyboard_backspace),
          onPressed: _canPull
              ? () => session.pullBlocks(1, currentRow: currentRow)
              : null,
        ),
      ],
    );
  }
}
