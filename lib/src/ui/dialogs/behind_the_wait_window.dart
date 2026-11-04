import 'package:flutter/material.dart';

import '../../services/command.dart' show WorkAhead;
import '../../services/wait_window.dart' show StepBehind;
import '../text/app_strings.dart';
import 'app_progress_dialog.dart';

/// A step taken behind the app's one wait window ([window]) — the way every
/// door that takes a heavy step runs it, and every undo and redo of one
/// ([stepBehindTheWaitWindow]).
///
/// D3: the app's ONE wait-for-this window, exactly as save wears it.
/// The step is synchronous, but runWithAppProgress paints the
/// window before starting the task; the trailing endOfFrame holds
/// the modal barrier over the SECOND half of the step — the
/// canvas host's adoption pass and the first recomposite land on
/// the next frame, and no input may slip between the halves (an
/// edit there would commit a stroke at the wrong canvas size).
///
/// [ahead] runs first, behind the same window — what the step can work
/// out off the UI thread, its progress the window's.
///
/// 🗣️F-551 (유저 2026-11-04): 「연산 필요한거? 무거운거? 들은 왠만하면 다
/// 로딩창띄우도록. 색변환이나 색삭제나 그런거.」 · Q1 「전부 늘 띄운다」 — the
/// copy, the paste, the 확정 and every other step a hand takes many times
/// too, every time. ⇒ The window goes with the step's second half, no done
/// line after it (bundle-red-paste-behind-the-wait-window-Q1): a hand that
/// takes it many times presses again right away.
Future<void> takeBehindTheWaitWindow(
  BuildContext context,
  VoidCallback step, {
  required AppWaitWindow window,
  WorkAhead? ahead,
}) => window.standBehind<void>(context, (report) async {
  await ahead?.call(report);
  step();
  await WidgetsBinding.instance.endOfFrame;
});

/// A move of the canvas's walls — its size, or how far its pasteboard
/// reaches past it ([takeBehindTheWaitWindow]). Each cuts every picture
/// past the new wall, so each takes as long as the pictures do.
///
/// 🗣️F-432 (유저 2026-10-21): 「이런 시간 걸리는 로직은 규칙으로서 공용
/// 로딩창 표시해야함」 — the pasteboard's size and its use joined the
/// canvas size here, under their own [title].
Future<void> resizeBehindTheWaitWindow(
  BuildContext context,
  VoidCallback resize, {
  required String title,
  WorkAhead? ahead,
}) => takeBehindTheWaitWindow(
  context,
  resize,
  window: AppWaitWindow(
    title: title,
    titleIcon: Icons.aspect_ratio,
    runningLabel: AppText.strings.resizeProgressRunning,
    windowKey: const ValueKey<String>('resize-progress-dialog'),
  ),
  ahead: ahead,
);

/// An undo or a redo taken behind the window its step's first run stood
/// behind ([StepBehind]), while what it works out ahead runs.
///
/// 🗣️a-resize-redo-moves-every-cel-on-the-ui-thread-Q1 (유저 2026-10-22:
/// 「다시 하기도 대기 창 뒤에서 옮긴다」) · F-551-Q1 (유저 2026-11-04:
/// 「전부 늘 띄운다」).
Future<void> stepBehindTheWaitWindow(
  BuildContext context,
  StepBehind behind,
  VoidCallback step,
) async {
  // Only the app draws a window; one it did not make has nothing to show.
  if (behind.window case final AppWaitWindow window) {
    await takeBehindTheWaitWindow(
      context,
      step,
      window: window,
      ahead: behind.ahead,
    );
    return;
  }
  step();
}
