part of '../editor_workspace.dart';

/// THE FOLDED STORYBOARD, STANDING ON ANOTHER ROW THAN ITS V ROW — which row
/// that is, how tall the room the fold keeps, and its overlay — as its own
/// object beside the collapsed rows ([_WorkspaceCollapsedRows]), which keep
/// the timeline's folded row and the storyboard's V row.
///
/// 🗣️F-322 (유저 2026-10-09): 「콘티패널 간편오버레이가 제대로 서있는곳 행에
/// 맞춰서 안보여주고 V행고정인데 서있는곳 보여주도록. 타임라인패널이랑
/// 통일」. The folded timeline is the row it stands on; this is the folded
/// storyboard so: that row as the panel draws it
/// ([StoryboardRowsChannel.foldedRowFor]), at its own height. ↩️The folded
/// storyboard showed its V row whatever row stood.
class _WorkspaceFoldedStoryboard {
  _WorkspaceFoldedStoryboard(this._state);

  final _EditorWorkspaceState _state;

  /// Where the storyboard stands — which row the fold is — and how tall the
  /// room it keeps for that row ([row]; null on the V row). A channel of its
  /// own: a stand rides the rows' notifier, no session notify, and only the
  /// region's layout has to hear it — once per row stood on, not per step
  /// of the timeline's ([Standing.currentRowListenable] carries both
  /// panels'). And once per change of how tall the rail lays that row: a
  /// graph opened over the lane stood on, a twirl, a filter, an edit.
  /// ↩️It heard the stand alone, and a graph opened over the lane the fold
  /// stood on kept the V row's room (card
  /// a-folded-conte-row-keeps-its-height-through-a-graph).
  final ValueNotifier<({TimelineRowAddress? row, double? height})> fold =
      ValueNotifier((row: null, height: null));

  EditorSessionManager? _session;
  Listenable? _heard;

  void _follow() => fold.value = (
    row: _session?.standing.storyboardStandingRow,
    height: row()?.height,
  );

  /// Follows [session]'s stand and the rail it is laid on — the
  /// workspace's door for the project coming on screen (I-7).
  void bindSession(EditorSessionManager session) {
    unbindSession();
    _session = session;
    _heard = Listenable.merge([
      session.standing.currentRowListenable,
      session,
      session.railView.drawn,
      session.rowSelection,
    ])..addListener(_follow);
    _follow();
  }

  /// Lets go of the project going behind.
  void unbindSession() {
    _heard?.removeListener(_follow);
    _heard = null;
    _session = null;
  }

  void dispose() {
    unbindSession();
    fold.dispose();
  }

  /// The row the folded storyboard stands on, as its panel builds it — null
  /// on the V row, which is the collapsed rows' own track row.
  StoryboardFoldedRow? row() => _state._storyboardRows.foldedRowFor(
    _state.widget.session.standing.storyboardStandingRow,
  );

  /// [folded] laid over the artwork — the timeline's folded row's shape, on
  /// the storyboard's rail and axis, turned by [follows].
  Widget overlay(StoryboardFoldedRow folded, CollapsedRowFollows follows) {
    final session = _state.widget.session;
    final pixelsPerFrame = _state._storyboardPixelsPerFrame.value;
    final frames = folded.frames;
    return CollapsedRowOverlay(
      height: folded.height,
      snapshot: folded.snapshot(),
      rail: _state._railExtents[LayerRailId.storyboard],
      frameAxisOffset: _state._frameAxisOffsets[LayerRailId.storyboard],
      naturalRailWidth: StoryboardTrackLabelRow.railWidthIn(_state.context),
      pixelsPerFrame: pixelsPerFrame,
      framesPerSecond: session.projectSettings.projectFrameRate.countingBase,
      railChild: folded.rail?.call(),
      dashedFrames: folded.dashes,
      frameRowBuilder: frames == null
          ? null
          : (context, geometry) => Stack(
              fit: StackFit.expand,
              children: [
                frames(context, geometry),
                // Where you are, on its own tick layer — the V row's.
                StoryboardPlayheadTint(
                  playhead: session.playheadCursors.trackFrame,
                  pixelsPerFrame: pixelsPerFrame,
                  firstFrame: geometry.value.frameStartIndex,
                ),
              ],
            ),
      follows: follows,
    );
  }
}
