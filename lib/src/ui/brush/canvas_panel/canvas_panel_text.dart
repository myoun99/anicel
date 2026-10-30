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
  HistoryGestures? get gestures => _state.widget.historyManager?.gestures;

  @override
  void run(Command command, {Set<String> setIn = const {}}) {
    final history = _state.widget.historyManager;
    // ONE entry of history either way: the registering of a face rides
    // INSIDE the text's step, so a run the step is written in counts it
    // one (`HistoryRun.write`).
    final step =
        _state.widget.textCommands?.landingWith?.call(command, setIn) ??
        command;
    if (history == null) {
      step.execute();
      return;
    }
    history.execute(step);
  }

  @override
  void shownChanged() {
    if (_state.mounted) {
      _state._rebuild(() {});
    }
  }

  /// What a save lands of what this canvas has IN FLIGHT
  /// (`LiveStrokeLanding`): [stroke] — the drawing view's own, the stroke
  /// the pen is in the middle of — and beside it the text in hand, landed
  /// as it is shown and kept in hand ([CelTextTool.landShown]). Nothing
  /// while the view that owns [stroke] is gone: there is no canvas then.
  /// Answers whether anything landed.
  ///
  /// One verb because it is one question — 「what has not reached the cel
  /// yet」 — and the door that asks it is one
  /// (`ProjectFileDoor._settleWorkInFlight`): a second kind of work in
  /// flight that had its own way to the save would be the fifth call site
  /// that door's comment says it exists to prevent.
  bool landBeside(StrokeLander? stroke) {
    if (stroke == null) {
      return false;
    }
    final strokeLanded = stroke();
    final textLanded = tool.landShown();
    return strokeLanded || textLanded;
  }

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
  ///
  /// 🗣️I-132-Q32 b: and on a row whose chain runs a plugin, which may
  /// change the cel anywhere — its landing is the whole cel's
  /// ([celTextLandingAsShown]).
  bool get _floatsTheLanding =>
      celSourceEffectSignature(_state.widget.activeSourceEffects).isNotEmpty ||
      celSourcePlugin(_state.widget.activeSourceEffects) != null;

  // ── the float ───────────────────────────────────────────────────────

  /// What floats over the hole the text in hand left (F-344,
  /// [CelTextOnCanvas.floatingOn]) — read by the painter of that hole itself
  /// (`BitmapSurfacePainter.landingPreview`), so a hand carrying the text
  /// draws the canvas again and builds nothing.
  final ValueNotifier<LandingPreview?> float = ValueNotifier(null);

  /// The cel the painter of the hole was made for, which is the cel the
  /// float is made over until that painter is made again.
  ({BitmapSurface surface, BrushFrameKey key, _ShownThrough fx})? _floatOn;

  /// Makes [float] over [identity], the cel the painter is drawing now —
  /// asked as that painter is chosen, so the hole and what floats over it
  /// are of one moment.
  ///
  /// A write during build is safe here for the selection layer's reason
  /// (`_publishFloats`): a repaint is all it triggers.
  void floatOver(({BitmapSurface surface, BrushFrameKey key, _ShownThrough fx})? on) {
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
    ({BitmapSurface surface, BrushFrameKey key, _ShownThrough fx}) on,
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
    _ShownThrough fx,
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
    ({BitmapSurface surface, BrushFrameKey key, _ShownThrough fx}) on,
  ) {
    final (:pixels, under: _, :above) = floating;
    // The pasteboard: what crosses it is cut there, as it is on the cel.
    final wall = on.surface.pasteboard.rect;
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
    ({BitmapSurface surface, BrushFrameKey key, _ShownThrough fx}) on,
  ) {
    final kept = _held;
    if (kept != null && identical(kept.of, plate) && kept.fx == on.fx) {
      return kept.painter;
    }
    final painter = floatPainter(
      celTextPlateSurface(
        plate,
        canvasSize: on.surface.canvasSize,
        pasteboardReach: on.surface.pasteboardReach,
        tileSize: on.surface.tileSize,
      ),
      _state.widget.activeSourceEffects,
    );
    _held = (of: plate, fx: on.fx, painter: painter);
    return painter;
  }

  ({Object of, _ShownThrough fx, BitmapSurfacePainter painter})? _held;

  /// The painter of the texts above the one in hand, made once for them.
  BitmapSurfacePainter _abovePainter(
    List<CelText> above,
    ({BitmapSurface surface, BrushFrameKey key, _ShownThrough fx}) on,
  ) {
    final kept = _above;
    if (kept != null && identical(kept.of, above) && kept.fx == on.fx) {
      return kept.painter;
    }
    final painter = floatPainter(
      BitmapSurface(
        canvasSize: on.surface.canvasSize,
        pasteboardReach: on.surface.pasteboardReach,
        tileSize: on.surface.tileSize,
        texts: above,
      ),
      _state.widget.activeSourceEffects,
    );
    _above = (of: above, fx: on.fx, painter: painter);
    return painter;
  }

  ({Object of, _ShownThrough fx, BitmapSurfacePainter painter})? _above;

  Widget layer() => Positioned.fill(
    child: CelTextToolLayer(
      tool: tool,
      stage: CelTextStage(
        viewport: _state._viewportState._viewport,
        pasteboard: _state._stagePasteboard,
        placement: _state.widget.interactiveContentPose,
      ),
      cel: cel,
      onPressNeedsCel: _state._markDoorOverTheView,
      markMakesItsOwnCel: _state.widget.markMakesItsOwnCel,
      onDragActive: (active) => _state._textDragActive = active,
      wearsItsCursor: _state.widget.toolCursorsEnabled,
      oneFingerAction: _state.widget.oneFingerAction,
    ),
  );
}
