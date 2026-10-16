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

  late final CelTextTool tool = CelTextTool(host: this)
    ..shownInHand.addListener(_shownInHand);

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
    float.dispose();
    _letTheLandingGo();
  }

  /// Whether the tool is in hand on a panel that runs it.
  bool get layerMounted =>
      _state.widget.toolInputEnabled && _state._brush.tool == CanvasTool.text;

  @override
  TextToolOptions get options =>
      _state.widget.textToolOptions?.value ?? TextToolOptions.defaults;

  @override
  set options(TextToolOptions options) =>
      _state.widget.textToolOptions?.value = options;

  @override
  int? get brushColour => _state.widget.brushToolState?.value.color;

  @override
  HistoryMark? get historyMark =>
      _state.widget.historyManager?.gestures.mark;

  @override
  void run(
    Command command, {
    HistoryMark? withCelMadeSince,
    Set<String> setIn = const {},
  }) {
    final history = _state.widget.historyManager;
    // ONE entry of history either way: the registering of a face rides
    // INSIDE the text's step, so the fold below still counts two.
    final step =
        _state.widget.textCommands?.landingWith?.call(command, setIn) ??
        command;
    if (history == null) {
      step.execute();
      return;
    }
    history.execute(step);
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
  /// text of it is in hand — null when none is: the HOLE the text in hand
  /// left, with [float] over it. Where the float is what the cel will show
  /// there ([_floatsTheLanding]), the texts above the one in hand stay in
  /// the hole, as they are on the cel.
  BitmapSurface? shownSurfaceFor(BrushFrameKey key, BitmapSurface cel) =>
      _floatsTheLanding
      ? tool.onCanvas.shownWithoutFor(key, cel)
      : tool.onCanvas.shownSurfaceFor(key, cel);

  /// Whether what floats over the hole is what the cel will SHOW where the
  /// text in hand lands ([CelTextLanding]) — on a row that keys its colours
  /// — rather than the text's own pixels ([CelTextFloat]).
  ///
  /// 🗣️유저 2026-10-15 (F-344-Q3), asked how a keyed row should show a text
  /// in hand over ink: 「놓을 때와 같은 코드로 — 완전히 같게」. The answer
  /// kept every other row on the float as it was (its words: 「키 없는
  /// 레이어는 지금처럼 GPU 플로트」) — there the float already lands as it is
  /// shown, but for partly clear pixels over ink, one apart at most, and
  /// it costs nothing per move of the hand.
  bool get _floatsTheLanding =>
      celSourceEffectSignature(_state.widget.activeSourceEffects).isNotEmpty;

  // ── the float ───────────────────────────────────────────────────────

  /// What floats over the hole the text in hand left (F-344,
  /// [CelTextOnCanvas.floatingOn]) — read by the painter of that hole itself
  /// (`BitmapSurfacePainter.landingPreview`), so a hand carrying the text
  /// draws the canvas again and builds nothing.
  final ValueNotifier<LandingPreview?> float = ValueNotifier(null);

  /// The cel the painter of the hole was made for, which is the cel the
  /// float is made over until that painter is made again.
  ({BitmapSurface surface, BrushFrameKey key, String fx})? _floatOn;

  /// Makes [float] over [identity], the cel the painter is drawing now —
  /// asked as that painter is chosen, so the hole and what floats over it
  /// are of one moment.
  ///
  /// A write during build is safe here for the selection layer's reason
  /// (`_publishFloats`): a repaint is all it triggers.
  void floatOver(({BitmapSurface surface, BrushFrameKey key, String fx})? on) {
    _floatOn = on;
    _float();
  }

  /// The text in hand showed something else — a hand carried it, a bake
  /// made it.
  void _shownInHand() => _float();

  void _float() {
    final on = _floatOn;
    final floating = on == null
        ? null
        : tool.onCanvas.floatingOn(on.key, on.surface);
    if (on == null || floating == null) {
      _letTheLandingGo();
      float.value = null;
      return;
    }
    if (_floatsTheLanding) {
      float.value = _landingOf(floating, on);
      return;
    }
    _letTheLandingGo();
    float.value = _floatOf(floating, on);
  }

  /// What the cel will show where the text in hand lands, made once for
  /// each place a hand carries it to ([celTextLandingAsShown]) — null where
  /// it holds no ink.
  ///
  /// Made again when the text's pixels or their place are others (a plate
  /// is the object it is: its map compares by identity), when the picture
  /// it was lifted off is another — the texts above it are of that picture
  /// — or when the row's keys are.
  CelTextLanding? _landingOf(
    CelTextFloating floating,
    ({BitmapSurface surface, BrushFrameKey key, String fx}) on,
  ) {
    final (:pixels, :under, :above) = floating;
    final kept = _landing;
    if (kept != null &&
        kept.of == pixels &&
        identical(kept.under, under) &&
        kept.fx == on.fx) {
      return kept.shown;
    }
    _letTheLandingGo();
    final made = celTextLandingAsShown(
      under: under,
      carried: pixels,
      above: above,
      effects: _state.widget.activeSourceEffects,
    );
    final shown = made == null
        ? null
        : CelTextLanding.of(made.region, made.straight);
    _landing = (of: pixels, under: under, fx: on.fx, shown: shown);
    return shown;
  }

  ({
    CelTextPixels of,
    BitmapSurface under,
    String fx,
    CelTextLanding? shown,
  })?
  _landing;

  /// The landing last made is shown no more.
  void _letTheLandingGo() {
    _landing?.shown?.letGo();
    _landing = null;
  }

  CelTextFloat _floatOf(
    CelTextFloating floating,
    ({BitmapSurface surface, BrushFrameKey key, String fx}) on,
  ) {
    final (:pixels, under: _, :above) = floating;
    // The pasteboard: what crosses it is cut there, as it is on the cel.
    final wall = on.surface.canvasSize.pasteboardRect;
    return CelTextFloat(
      held: SelectionFloatPaint(
        surface: _heldPainter(pixels.plate, on),
        surfaceOffset: CanvasPoint(
          x: pixels.dx.toDouble(),
          y: pixels.dy.toDouble(),
        ),
        clip: wall,
      ),
      above: above.isEmpty
          ? null
          : SelectionFloatPaint(surface: _abovePainter(above, on), clip: wall),
    );
  }

  /// The painter of a plate, made once for it, as its cel shows it
  /// ([celSurfaceAsShown]).
  BitmapSurfacePainter _heldPainter(
    Map<TileCoord, BitmapTile> plate,
    ({BitmapSurface surface, BrushFrameKey key, String fx}) on,
  ) {
    final kept = _held;
    if (kept != null && identical(kept.of, plate) && kept.fx == on.fx) {
      return kept.painter;
    }
    final painter = floatPainter(
      celTextPlateSurface(
        plate,
        canvasSize: on.surface.canvasSize,
        tileSize: on.surface.tileSize,
      ),
      _state.widget.activeSourceEffects,
    );
    _held = (of: plate, fx: on.fx, painter: painter);
    return painter;
  }

  ({Object of, String fx, BitmapSurfacePainter painter})? _held;

  /// The painter of the texts above the one in hand, made once for them.
  BitmapSurfacePainter _abovePainter(
    List<CelText> above,
    ({BitmapSurface surface, BrushFrameKey key, String fx}) on,
  ) {
    final kept = _above;
    if (kept != null && identical(kept.of, above) && kept.fx == on.fx) {
      return kept.painter;
    }
    final painter = floatPainter(
      BitmapSurface(
        canvasSize: on.surface.canvasSize,
        tileSize: on.surface.tileSize,
        texts: above,
      ),
      _state.widget.activeSourceEffects,
    );
    _above = (of: above, fx: on.fx, painter: painter);
    return painter;
  }

  ({Object of, String fx, BitmapSurfacePainter painter})? _above;

  Widget layer() => Positioned.fill(
    child: CelTextToolLayer(
      tool: tool,
      stage: CelTextStage(
        viewport: _state._viewportState._viewport,
        canvasSize: _state.widget.canvasSize,
        placement: _state.widget.interactiveContentPose,
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
