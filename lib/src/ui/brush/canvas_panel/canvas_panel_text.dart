part of '../brush_canvas_panel.dart';

/// THE TEXT TOOL — the hand the panel holds a text with ([CelTextTool]),
/// what the canvas shows for it, and the layer it mounts while the tool is
/// in hand (R9-rest).
///
/// A collaborator of `_BrushCanvasPanelState`, as the lift is
/// (`canvas_panel_lift.dart`), and for the lift's reason: the layer comes
/// and goes with the tool, and what it was holding has to outlive it long
/// enough to land.
class _CanvasPanelText implements CelTextToolHost {
  _CanvasPanelText(this._state);

  final _BrushCanvasPanelState _state;

  late final CelTextTool tool = CelTextTool(host: this);

  /// The app's channel this hand is bound to, so that it is the one let go
  /// of on the way out.
  CelTextCommands? _boundTo;

  /// Binds the hand to the app's channel — the tool settings and the keys
  /// reach it through there.
  void bind() {
    final commands = _state.widget.textCommands;
    if (identical(commands, _boundTo)) {
      return;
    }
    _boundTo?.unbind(tool);
    _boundTo = commands?..bind(tool);
  }

  void dispose() {
    _boundTo?.unbind(tool);
    _boundTo = null;
    tool.dispose();
  }

  /// Whether the tool is in hand on a panel that runs it.
  bool get layerMounted =>
      _state.widget.toolInputEnabled && _state._brush.tool == CanvasTool.text;

  @override
  TextToolOptions get options =>
      _state.widget.textToolOptions?.value ?? TextToolOptions.defaults;

  @override
  HistoryMark? get historyMark =>
      _state.widget.historyManager?.gestures.mark;

  @override
  void run(Command command, {HistoryMark? withCelMadeSince}) {
    final history = _state.widget.historyManager;
    if (history == null) {
      command.execute();
      return;
    }
    history.execute(command);
    if (withCelMadeSince != null) {
      _foldWithItsCel(history, withCelMadeSince);
    }
  }

  /// The text just filed and the cel its press made, as ONE step — I-10's
  /// answer for a stroke (유저 2026-08-30: merged), said of a text: one
  /// Ctrl+Z after typing on an empty frame leaves the frame empty again.
  ///
  /// The cel was filed when the press came up, a step of its own, as a tap
  /// leaves it (`AutoFrameForStroke.flushAutoFrameForStroke`) — the text is
  /// typed long after, so it cannot ride the press as a stroke does. The
  /// two are folded once the text lands ([HistoryGestures.foldSince]).
  ///
  /// ⛔ONLY WHILE THEY ARE THE TWO ENTRIES FILED SINCE [since], exactly.
  /// `foldSince` folds a whole run, and anything filed between the cel and
  /// its text is somebody else's edit: folded in, one Ctrl+Z would take
  /// that back with the text. Left apart they are two steps, each still
  /// undone in the order it was made.
  void _foldWithItsCel(HistoryManager history, HistoryMark since) {
    final now = history.gestures.mark;
    if (now.pushed - since.pushed == 2 && now.retracted == since.retracted) {
      history.gestures.foldSince(since, 'Set text on a new frame');
    }
  }

  @override
  void shownChanged() {
    if (_state.mounted) {
      _state._rebuild(() {});
    }
  }

  /// The verb a save takes to land what this canvas has IN FLIGHT
  /// (`LiveStrokeLanding`): [stroke] — the drawing view's own, the stroke
  /// the pen is in the middle of — and beside it the text in hand, landed
  /// as it is shown and kept in hand ([CelTextTool.landShown]). Null while
  /// the view that owns [stroke] is gone: there is no canvas then.
  ///
  /// One verb because it is one question — 「what has not reached the cel
  /// yet」 — and the door that asks it is one
  /// (`ProjectFileDoor._settleWorkInFlight`): a second kind of work in
  /// flight that had its own way to the save would be the fifth call site
  /// that door's comment says it exists to prevent.
  StrokeLander? landerBeside(StrokeLander? stroke) => stroke == null
      ? null
      : () {
          final strokeLanded = stroke();
          final textLanded = tool.landShown();
          return strokeLanded || textLanded;
        };

  /// The cel a press sets a text on or takes one from — null where none
  /// is under the playhead, or its row takes no marks.
  @override
  CelTextCel? get cel {
    final coordinator = _state.widget._editableCoordinator;
    if (coordinator == null) {
      return null;
    }
    return (
      key: coordinator.activeFrameKey,
      coordinator: coordinator,
      canvasSize: _state.widget.canvasSize,
      cacheInvalidationSink: _state.widget.cacheInvalidationSink,
    );
  }

  /// What the interactive painter draws for [key] in place of [cel] while a
  /// text of it is in hand — null when none is, or the one that is shows
  /// exactly as the cel carries it.
  BitmapSurface? shownSurfaceFor(BrushFrameKey key, BitmapSurface cel) =>
      tool.shownSurfaceFor(key, cel);

  Widget layer() => Positioned.fill(
    child: CelTextToolLayer(
      tool: tool,
      stage: CelTextStage(
        viewport: _state._viewportState._viewport,
        canvasSize: _state.widget.canvasSize,
        pose: _state.widget.interactiveContentPose,
      ),
      cel: cel,
      // 🚨WHOEVER HEARS THE PRESS ASKS FOR THE CEL, AND ONLY ONE DOES (I-10).
      // On a frame with no cel the drawing view stands down in place and
      // asks — but this layer is over it and takes the press, so it asks in
      // the view's stead. Where a cel IS there and its row takes no marks,
      // or nothing stands here at all, the host's own listener speaks
      // (`MainCanvasBrushHost`), and a second question would say it twice.
      onPressNeedsCel:
          _state.widget.coordinator != null && !_state.widget.celEditable
          ? _state.widget.onPressNeedsCel
          : null,
      onDragActive: (active) => _state._textDragActive = active,
      oneFingerAction: _state.widget.oneFingerAction,
    ),
  );
}
