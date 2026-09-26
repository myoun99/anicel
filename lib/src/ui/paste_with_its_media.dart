import 'package:flutter/material.dart';

import 'dialogs/app_progress_dialog.dart';
import 'text/app_strings.dart';

/// A paste that may bring media from ANOTHER project (I-7): when the copy
/// carries media this project's pool lacks, their bytes are held first — as
/// this project's own carries, behind the wait window every wait has (F-53:
/// 「로딩창 안 떠서 여는 중인지 아닌지 모르겠어」) — and the paste lands after,
/// with them, as one undo. With nothing to hold it lands at once, inside
/// this call.
///
/// ONE door for every paste entrance that can bring media: the frame
/// pill's button and its key, and the layer menu's paste.
Future<void> pasteWithItsMedia(
  BuildContext context, {
  required String title,
  required bool mustHold,
  required Future<void> Function() hold,
  required void Function() paste,
}) async {
  if (mustHold) {
    await runWithAppProgress<void>(
      context: context,
      title: title,
      titleIcon: Icons.content_paste,
      runningLabel: AppText.strings.pasteProgressRunning,
      doneLabel: AppText.strings.pasteProgressDone,
      windowKey: const ValueKey<String>('paste-media-progress'),
      task: (_) => hold(),
    );
    if (!context.mounted) {
      return;
    }
  }
  paste();
}
