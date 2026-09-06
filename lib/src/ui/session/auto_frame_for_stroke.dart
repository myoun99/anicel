part of '../editor_session_manager.dart';

/// The AUTO FRAME FOR A STROKE — a stroke landing on an empty cell makes
/// the drawing the stroke needs, and the frame it made is taken or flushed
/// when the stroke ends — as its own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: one field of its own and five
/// session members touched. It reaches the session through `_session`.
class _AutoFrameForStroke {
  _AutoFrameForStroke(this._session);

  final EditorSessionManager _session;

  /// 🚨I-10 — THE BLOCK A PEN-DOWN MADE, waiting to be undone WITH the
  /// stroke it was made for.
  ///
  /// 유저 2026-08-30, on the undo boundary: 「답은 추천대로」 = **merged**.
  /// One stroke on an empty cell is ONE undo, and both halves go together.
  ///
  /// ⛔It is held rather than pushed because the two halves happen at
  /// different MOMENTS — see `createDrawingFrameCommandForLayer`. Nothing
  /// else may push history between the down and the up, or this lands in
  /// the wrong place; the brush host is the only caller and it holds the
  /// pointer for that whole time.
  Command? _autoFrameForStroke;

  /// Whether a press on the cell under the playhead would MAKE a block
  /// rather than be refused (I-10).
  ///
  /// ⛔Asks `canCreateDrawingAtCurrentFrame`, which already knows about
  /// synced attaches, single-cel rows and media references — the auto path
  /// must refuse everywhere the manual button does, or the toggle becomes a
  /// second answer to 「can this row take a cel」.
  bool get canAutoCreateFrameForStroke =>
      AppInput.settings.value.autoCreateFrameOnDraw &&
      _autoFrameForStroke == null &&
      _session.canCreateDrawingAtCurrentFrame;

  /// Makes the block a stroke is about to be drawn into, and HOLDS its
  /// command. Returns false when nothing was made.
  bool beginAutoFrameForStroke() {
    // A block from a press that never became a stroke is settled here
    // rather than left to be swept into THIS press's undo entry.
    flushAutoFrameForStroke();
    final layer = _session.activeLayer;
    if (layer == null || !canAutoCreateFrameForStroke) {
      return false;
    }
    _session._frameSequence += 1;
    final command = _session.timelineController
        .createDrawingFrameCommandForLayer(
          layerId: layer.id,
          frameId: FrameId(_session.nextFrameId(layer.id)),
        );
    command.execute();
    _autoFrameForStroke = command;
    _session.notifyChanged();
    return true;
  }

  /// Hands the held block command to whoever is pushing the stroke, so the
  /// two land as one entry. Null when this press made no block.
  Command? takeAutoFrameForStroke() {
    final command = _autoFrameForStroke;
    _autoFrameForStroke = null;
    return command;
  }

  /// 🚨A BLOCK THAT NO STROKE CLAIMED KEEPS ITS OWN UNDO.
  ///
  /// ⛔I very nearly made this DISCARD the block — 「a press that drew
  /// nothing leaves nothing」 sounded obviously right and was mine, not the
  /// user's. What they said is 「**빈 칸에서 펜다운하면 블록이 생기고**
  /// 그대로 그려진다」: the pen-DOWN makes it. A tap that makes a block is
  /// the feature, not a leak.
  ///
  /// ⚠️What WOULD be a bug is the block outliving its command. Held and
  /// never composed, it sits in the project with no history entry at all —
  /// unundoable. So an unclaimed one is pushed on its own, exactly as the
  /// manual 「add frame」 button would have left it.
  ///
  /// ⛔Safe in either order, which is why there is no race to reason about:
  /// if the stroke already took it this is a no-op, and if it has not, the
  /// block is undoable either way.
  void flushAutoFrameForStroke() {
    final command = _autoFrameForStroke;
    if (command == null) {
      return;
    }
    _autoFrameForStroke = null;
    // Already executed at pen-down; this records it without re-running
    // anything that matters (the layer edit holds its own before/after).
    _session.historyManager.execute(command);
    _session.notifyChanged();
  }
}
