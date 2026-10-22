import 'package:flutter/foundation.dart';

import 'canvas_selection_commands.dart';

/// EVERY CANVAS'S POLYGON TRACE, as the window's verbs ask after one: the
/// canvas's, on the window's channel, and each viewer's, on its own.
///
/// 🗣️F-380 (유저 2026-10-17): 「뷰어패널에서 잘라내기쓸때 개미행렬 라이브가
/// 안보임. 법 통일해서 보이도록」 — a viewer's trace is tapped out on a
/// channel of its own, and 확정 (Enter, the rail's ↵, the tool settings'
/// 닫기), ↶ ↷ and Escape asked the canvas's alone: with a trace open in a
/// viewer, Enter laid the last stroke down again on the canvas.
///
/// Which trace is the verbs' own law: the thing the user is in the MIDDLE
/// of (`HistoryVerbs`), the newest thing a confirm can be closing
/// (`ConfirmVerb`) — of the traces open, the one last added to or taken
/// back from ([CanvasSelectionCommands.traceTouchedAt]).
class CanvasTraces {
  CanvasTraces(this._channels) : changes = Listenable.merge(_channels);

  final List<CanvasSelectionCommands> _channels;

  /// Everything [open] and [toRedo] depend on.
  final Listenable changes;

  /// The open trace the user is in the middle of, or null.
  CanvasSelectionCommands? get open =>
      _newest((channel) => channel.hasOpenPolygon);

  /// The trace a redo puts a vertex back on, or null.
  CanvasSelectionCommands? get toRedo =>
      _newest((channel) => channel.canRedoPolygonPoint);

  CanvasSelectionCommands? _newest(
    bool Function(CanvasSelectionCommands channel) holds,
  ) {
    CanvasSelectionCommands? newest;
    for (final channel in _channels.where(holds)) {
      if (newest == null || channel.traceTouchedAt > newest.traceTouchedAt) {
        newest = channel;
      }
    }
    return newest;
  }
}
