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
/// The pair gates on the SHIFT ANCHOR, which is the playhead — so it owns
/// its own committed-seek subscription rather than making whatever mounts
/// it rebuild. Two booleans re-derived per seek (measured at 3.7µs), and a
/// `setState` only when one of them flips: the alternative was the host
/// rebuilding its whole command bar per arrow press (11ms of build).
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
  void _handleSeek() {
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

  @override
  void initState() {
    super.initState();
    _canPush = _derivedPush;
    _canPull = _derivedPull;
    widget.session.frameSeekCommitted.addListener(_handleSeek);
  }

  @override
  void didUpdateWidget(covariant TimelineShiftButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      oldWidget.session.frameSeekCommitted.removeListener(_handleSeek);
      widget.session.frameSeekCommitted.addListener(_handleSeek);
    }
    // Already rebuilding — assign, never setState.
    _canPush = _derivedPush;
    _canPull = _derivedPull;
  }

  @override
  void dispose() {
    widget.session.frameSeekCommitted.removeListener(_handleSeek);
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
