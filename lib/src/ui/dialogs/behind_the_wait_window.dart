import 'package:flutter/material.dart';

import '../../services/command.dart' show WallMove, WorkAhead;
import '../text/app_strings.dart';
import 'app_progress_dialog.dart';

/// A move of the canvas's walls — its size, or how far its pasteboard
/// reaches past it — the one way every door runs it. Each cuts every
/// picture past the new wall, so each takes as long as the pictures do.
///
/// 🗣️F-432 (유저 2026-10-21): 「이런 시간 걸리는 로직은 규칙으로서 공용
/// 로딩창 표시해야함」 — the pasteboard's size and its use joined the
/// canvas size here, under their own [title].
///
/// D3: the app's ONE wait-for-this window, exactly as save wears it.
/// The command is synchronous, but runWithAppProgress paints the
/// window before starting the task; the trailing endOfFrame holds
/// the modal barrier over the SECOND half of the resize — the
/// canvas host's adoption pass and the first recomposite land on
/// the next frame, and no input may slip between the halves (an
/// edit there would commit a stroke at the wrong canvas size).
///
/// [ahead] runs first, behind the same window — what the move can work
/// out off the UI thread, its progress the window's.
Future<void> resizeBehindTheWaitWindow(
  BuildContext context,
  VoidCallback resize, {
  required String title,
  Future<void> Function(void Function(double done) report)? ahead,
}) => runWithAppProgress<void>(
  context: context,
  title: title,
  titleIcon: Icons.aspect_ratio,
  runningLabel: AppText.strings.resizeProgressRunning,
  doneLabel: AppText.strings.resizeProgressDone,
  windowKey: const ValueKey<String>('resize-progress-dialog'),
  task: (report) async {
    await ahead?.call(report);
    resize();
    await WidgetsBinding.instance.endOfFrame;
  },
);

/// A step that moves the canvas's walls taken behind their wait window —
/// an undo, a redo, a 겸용 변경 — while what it works out [ahead] runs; or
/// at once, where it works nothing out.
///
/// 🗣️a-resize-redo-moves-every-cel-on-the-ui-thread-Q1 (유저 2026-10-22:
/// 「다시 하기도 대기 창 뒤에서 옮긴다」): the window the move of that wall
/// stands behind where it is first made — 「캔버스 크기」, or the
/// pasteboard's.
Future<void> stepBehindTheWaitWindow(
  BuildContext context,
  WorkAhead? ahead,
  VoidCallback step,
) async {
  if (ahead == null) {
    step();
    return;
  }
  await resizeBehindTheWaitWindow(
    context,
    step,
    title: switch (ahead.wall) {
      WallMove.canvasSize => AppText.strings.canvasSizeTitle,
      WallMove.pasteboard => AppText.strings.pasteboardTitle,
    },
    ahead: ahead.run,
  );
}
