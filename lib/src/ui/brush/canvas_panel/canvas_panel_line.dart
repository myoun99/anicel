part of '../brush_canvas_panel.dart';

/// 「직전 획에서 직선」 (I-119) — while its key is held ([CanvasLineHold])
/// with a tool that paints, a straight line from where the last stroke
/// ended to the hand: shown as the shape tool shows its line while it is
/// dragged, and landed by a click as that tool lands it.
///
/// 🗣️유저 2026-10-21: 「브러시 도구(브러시,지우개) 전용기능, … 누르고있으면
/// 저번에 찍은 마지막 dab? 점 부터 현재 호버중인 커서까지 라이브로 직선
/// 보여주고(도형도구의 직선이랑 최대한 동일하게 로직 재사용. 법 통일) 거기서
/// 찍으면 직선 그림. 물론 쉬프트누르면 스냅 작동」 — I-119-Q1: 「호버 중에도
/// 실제 브러시 획까지」 · I-119-Q2: 「도중에 … 키를 떼면 취소임. 호버하면서
/// 위치 정하고, 클릭해야 직선 착지」.
///
/// 🗣️F-483 (유저 2026-10-27): 「z로 마지막 찍은 점에서 직선 그을때, 필압 최대
/// 고정인데, 마지막 찍은 필압 기준으로 직선 그리도록」 — the line is laid at
/// the pressure of the last dab the last stroke laid, the whole way. ↩️It
/// was laid at full, as the shape tool's line is, which no pen pressed.
///
/// 🗣️F-513 (유저 2026-10-30): 「z를 여러번 하면 매번 직전 찍은 필압? 기준으로
/// 해야하는데 z로 찍는건 그 기준에 안들어가서 … z로 찍다가 중간에 마우스로
/// 찍고 다시z누르면 진해져있어야하는데」 — the click that lands a line is a
/// press of its own: the NEXT line is laid at what it pressed with, read as
/// a stroke reads its pen ([ShapeShow.pressureOf]). ↩️The next line took
/// the landed line's dabs, which are its start's, so a run of lines kept
/// the first stroke's pressure whatever pressed them.
///
/// ★THE SHAPE TOOL'S LINE FROM ANOTHER START, not one like it: that tool's
/// own drag ([MarqueeDrag] of a [CanvasShapeKind.line]) begun at the last
/// stroke's end instead of at a press — its end where the hand is, kept to
/// eight ways while Shift is held — its copies made by the same guide
/// ([drawnCopiesOf]), its ants drawn by the same painter, and the stroke
/// under them shown and landed through the shape tool's own two doors
/// ([_BrushCanvasPanelState._showTraced] ·
/// [_BrushCanvasPanelState._landTraced]) as ONE STROKE of the tool in hand —
/// the brush's or the eraser's.
///
/// ⚠️While it is in force the deck takes no pointer — the drawing view
/// would draw — and the census hears the press instead, as the gesture
/// layer hears a view hold's ([ViewHoldGate]). The line runs to the ONE aim
/// the census writes ([_BrushCanvasPanelState._toolCursorHover]) and lands
/// where its press lets go; the key let go first takes it back.
class _CanvasPanelLine {
  _CanvasPanelLine(this._state);

  final _BrushCanvasPanelState _state;

  /// Where the last stroke drawn here ended, on the canvas, and the
  /// pressure its last dab was laid at — null before there was one. A line
  /// landed is a stroke, so its end is the next one's start.
  ({CanvasPoint at, double pressure})? _from;

  /// The press the line lands at when it lets go, and what it pressed with.
  ({int pointer, double pressure})? _press;

  /// What the press that landed the last line pressed with — the next
  /// line's start ([heard]) — until the next press goes down ([press]):
  /// every stroke heard here began with a press the census heard.
  double? _landingPress;

  /// Whether a line of this hand is on screen — what a take-back takes.
  /// ⛔Without it every aim out of force would take back the drawing
  /// view's show, the shape tool's included.
  bool _shown = false;

  /// Whether the line is in force: its key held, a tool in hand that
  /// paints, and a stroke to start from. The deck stands down while it is.
  final ValueNotifier<bool> inForce = ValueNotifier<bool>(false);

  /// What the ants draw — the line and every copy the guide makes of it.
  final ValueNotifier<List<List<CanvasPoint>>> trails =
      ValueNotifier<List<List<CanvasPoint>>>(const []);

  void bind() {
    CanvasLineHold.held.addListener(refresh);
    _state._toolCursorHover.addListener(follow);
  }

  void unbind() {
    CanvasLineHold.held.removeListener(refresh);
    _state._toolCursorHover.removeListener(follow);
    inForce.dispose();
    trails.dispose();
  }

  /// [stroke] has landed: where its path ended, at its last dab's pressure
  /// (full where it laid none, as a stroke opens) — or, a line of this
  /// hand, at the press that landed it — is the next line's start. A mark
  /// with no path (a fill, a stamp) leaves the start where it was.
  void heard(BrushStrokeCommitData stroke) {
    final end = stroke.end;
    if (end == null) {
      return;
    }
    _from = (
      at: _state._selectionSeat.pointOnTheCanvas(end),
      pressure: _landingPress ?? stroke.sourceDabs.lastOrNull?.pressure ?? 1,
    );
    refresh();
  }

  /// Asks again whether the line is in force — the key, the tool or the
  /// start moved — and runs it to the hand, or takes it back. Out of force,
  /// the press it had is let go of for good: the key pressed again before
  /// the click lets go lands nothing.
  void refresh() {
    inForce.value =
        CanvasLineHold.held.value &&
        canvasToolPaints(_state._brush.tool) &&
        _from != null;
    if (!inForce.value) {
      _press = null;
    }
    follow();
  }

  /// The line runs to the hand where it is now — none while it is out of
  /// force, while the hand is off the canvas, and while a stroke is being
  /// drawn: a key that went down under a drawing pen starts its line where
  /// that stroke ends.
  void follow() {
    final hand = _state._toolCursorHover.value?.at;
    _show(
      !inForce.value || hand == null || _state._strokeActive
          ? null
          : _lineTo(hand),
    );
  }

  /// The census heard [event] go down: a primary press while the line is
  /// in force and aimed is the line's, and lands it where it lets go.
  ///
  /// Any press is a stroke of its own: a landing heard by no one — a row
  /// that takes no strokes, a cel that never came — leaves its press for no
  /// stroke to take.
  void press(PointerDownEvent event) {
    _landingPress = null;
    if (!inForce.value ||
        _state._toolCursorHover.value == null ||
        _state._strokeActive ||
        !canvasPrimaryDown(event.buttons)) {
      return;
    }
    _press = (
      pointer: event.pointer,
      pressure: _state._shapeShow.now?.pressureOf(event) ?? 1,
    );
  }

  /// The census heard [event] let go: the line's press lands it there — a
  /// cancelled one takes it back. A press the line went out of force under
  /// is no longer its own ([refresh]): 「도중에 … 키를 떼면 취소임」.
  void letGo(PointerEvent event) {
    final press = _press;
    if (press == null || event.pointer != press.pointer) {
      return;
    }
    _press = null;
    final line = event is PointerUpEvent ? _lineTo(event.localPosition) : null;
    final copies = drawnCopiesOf(line, guideCarriesOf(_state.widget.guides));
    if (copies == null) {
      _show(null);
      return;
    }
    _setTrails(const [], shown: false);
    // Before the landing: a line laid and landed in one go is heard inside
    // it, and one that waits for its cel a frame later.
    _landingPress = press.pressure;
    _state._landTraced(copies, asStroke: true, pressure: _from!.pressure);
  }

  /// The shape tool's line from [_from] to [hand] — the census's, local to
  /// the deck — or null where the two ends are too close to have meant one.
  ///
  /// The drag is the tool's own, begun where no press began it: it has no
  /// pointer (the hand only hovers) and no region to put back, and a line
  /// has no lock for the guides and the zoom to make.
  DrawnShapePath? _lineTo(Offset hand) {
    final viewport = _state._viewportState._viewport;
    final drag = MarqueeDrag(
      pointer: -1,
      shapeKind: CanvasShapeKind.line,
      before: null,
      at: _from!.at,
      guides: _state.widget.guides ?? CutGuides(),
      zoom: viewport.zoom,
    )..update(
      viewport.viewportOffsetToCanvas(hand),
      // 「물론 쉬프트누르면 스냅 작동」: the shape tool's Shift, its eight
      // ways. The brush keeps no 「비율 고정」 of its own to flip.
      keepsRatio: ModifierKeys.isShiftPressed,
    );
    return drag.path();
  }

  /// Shows [line] with every copy the guide makes of it — the ants over,
  /// the stroke under — or takes back what this hand showed. Past the first
  /// return there is a start: a line runs from it, and one was shown.
  void _show(DrawnShapePath? line) {
    if (line == null && !_shown) {
      return;
    }
    final copies = drawnCopiesOf(line, guideCarriesOf(_state.widget.guides));
    _setTrails(
      [for (final copy in copies ?? const <DrawnShapePath>[]) copy.points],
      shown: copies != null,
    );
    _state._showTraced(copies, asStroke: true, pressure: _from!.pressure);
  }

  void _setTrails(List<List<CanvasPoint>> next, {required bool shown}) {
    _shown = shown;
    trails.value = next;
    _state._runPanelAnts();
  }

  /// The line's ants over the deck: what [trails] says, nothing while it
  /// is empty — the painter the shape tool's drag draws its line with.
  Widget ants() => IgnorePointer(
    child: RepaintBoundary(
      child: ValueListenableBuilder<List<List<CanvasPoint>>>(
        valueListenable: trails,
        builder: (context, trails, _) => CustomPaint(
          painter: SelectionAntsPainter(
            repaint: _state._idleAnts,
            viewport: _state._viewportState._viewport,
            committedRegion: null,
            screenOffset: Offset.zero,
            marqueeShapes: const [],
            openTrails: trails,
            trailCarries: guideCarriesOf(_state.widget.guides),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}
