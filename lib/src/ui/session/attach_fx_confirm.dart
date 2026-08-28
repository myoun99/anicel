import 'package:flutter/foundation.dart';

/// A drop is waiting on a yes/no, because taking it would throw fx away.
///
/// 🚨★★★THE SESSION ASKS; THE WORKSPACE SHOWS. 유저 2026-08-29 chose this
/// over each surface popping its own dialog: the drag lives below the widget
/// tree and has no `BuildContext`, and TWO surfaces end a row drag (the
/// timeline and the storyboard). One channel means one place that knows the
/// sentence, however many surfaces learn to end a drag later.
///
/// The shape is [PanelFlashController]'s, which is this repo's existing
/// answer to 「the model needs the UI to do something」 — a notifier the
/// workspace listens to. What it adds is the way back: a flash is told, a
/// question is answered.
///
/// ⚠️[answer] must be called exactly once. Until it is, the drag is still
/// held — nothing has been committed and nothing has been thrown away — so
/// a dialog that is dismissed without answering leaves the drop in limbo.
/// Every dismissal path (button, escape, barrier) has to route here.
@immutable
class AttachFxConfirmRequest {
  const AttachFxConfirmRequest({
    required this.seq,
    required this.rowNames,
    required this.answer,
  });

  /// Monotonic, so asking twice about the same rows re-opens the dialog
  /// rather than looking like nothing happened.
  final int seq;

  /// What is about to lose its fx, for a message that names it.
  final List<String> rowNames;

  final void Function(bool proceed) answer;
}

/// One per workspace, exactly as the flash controller is.
class AttachFxConfirmController {
  final ValueNotifier<AttachFxConfirmRequest?> pending =
      ValueNotifier<AttachFxConfirmRequest?>(null);

  int _seq = 0;

  /// Raises the question. [answer] is handed straight back to the caller's
  /// continuation, so the drag decides what commit and cancel mean — this
  /// object only carries the ask.
  void ask({
    required List<String> rowNames,
    required void Function(bool proceed) answer,
  }) {
    _seq += 1;
    pending.value = AttachFxConfirmRequest(
      seq: _seq,
      rowNames: rowNames,
      answer: (proceed) {
        // ⛔Cleared BEFORE the continuation runs: answering commits the drop,
        // which rebuilds the rows, and a request still standing at that
        // moment would open a second dialog over the result.
        pending.value = null;
        answer(proceed);
      },
    );
  }

  void dispose() => pending.dispose();
}
