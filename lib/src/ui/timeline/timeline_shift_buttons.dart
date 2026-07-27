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
class TimelineShiftButtons extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconButton(
          keyValue: 'push-blocks-button',
          tooltip: AppText.strings.tlPush,
          icon: const Icon(Icons.keyboard_tab),
          onPressed: session.canPushBlocks(currentRow: currentRow)
              ? () => session.pushBlocks(1, currentRow: currentRow)
              : null,
        ),
        AppIconButton(
          keyValue: 'pull-blocks-button',
          tooltip: AppText.strings.tlPull,
          icon: const Icon(Icons.keyboard_backspace),
          onPressed: session.canPullBlocks(currentRow: currentRow)
              ? () => session.pullBlocks(1, currentRow: currentRow)
              : null,
        ),
      ],
    );
  }
}
