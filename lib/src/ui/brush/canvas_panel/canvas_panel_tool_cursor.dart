part of '../brush_canvas_panel.dart';

/// The TOOL CURSOR — the cursor layers drawn for the active tool (brush,
/// fill, eyedropper, stamp preview), which one is active, and the hover
/// the eyedropper samples — as its own object.
///
/// 🚨A collaborator carved out of `_BrushCanvasPanelState` (the audit's SRP
/// cut, 2026-09-02). Measured before cutting: six State members shared.
/// It reaches the State through `_state` and rebuilds through `_rebuild`.
class _CanvasPanelToolCursor {
  _CanvasPanelToolCursor(this._state);

  final _BrushCanvasPanelState _state;

  /// Where the stamp would land, in CANVAS pixels.
  ///
  /// ⚠️CANVAS space, not viewport space, and that is the point: the painter
  /// draws its tiles in canvas coordinates, so a ghost stated in screen
  /// pixels would slide against the artwork at every zoom. The cursor
  /// overlay this replaced could state screen pixels because it lived on
  /// top of the canvas; nothing on that side of the transform can honour a
  /// layer.
  ///
  /// Centre-anchored, matching where a click actually drops it —
  /// [buildCutPasteDab] centres on `origin + size / 2` and the commit
  /// rounds from there.
  CutStampPreview _stampPreviewAt(
    Offset position,
    CutPiece piece,
    ui.Image? image,
  ) {
    final centre = _state._viewportState._viewport.viewportToCanvas(
      ViewportPoint(x: position.dx, y: position.dy),
    );
    final width = piece.stampWidth.toDouble();
    final height = piece.stampHeight.toDouble();
    return CutStampPreview(
      piece: piece,
      image: image,
      canvasRect: Rect.fromLTWH(
        centre.x - width / 2,
        centre.y - height / 2,
        width,
        height,
      ),
      opacity: _state.widget.brushToolState.cutStampOpacity,
      blendMode: _state.widget.brushToolState.cutStampBlendMode,
    );
  }

  /// R26 #23: the fill tool's own cursor icon (no sampling involved).
  bool get fillCursorActive =>
      _state.widget.toolCursorsEnabled &&
      _state.widget.brushToolState.tool == CanvasTool.fill;

  /// The brush/eraser tip outline — the selection tools own the pointer
  /// outright, and a held eyedropper is a tool switch now (I-15), so it
  /// never shares the pointer with the outline.
  bool get brushCursorActive =>
      _state.widget.toolCursorsEnabled &&
      canvasToolPaints(_state.widget.brushToolState.tool);

  /// Whether the eyedropper cursor + hover swatch are armed: the tool is
  /// the eyedropper — picked, or held (a mapped button or Alt switches to it
  /// for as long as it is held, I-15).
  bool get eyedropperCursorActive =>
      _state.widget.sampleColorAt != null &&
      _state.widget.brushToolState.tool == CanvasTool.eyedropper &&
      _state.widget.onEyedropperPick != null;

  /// R27 #17: the last pointer position seen on the canvas — hovers AND
  /// button-held moves alike.
  ///
  /// The eyedropper's icon and swatch only appeared once a fresh hover
  /// event reached their tracker. Entering the tool from a HELD button
  /// (the pen's barrel / right-click mapping) captures the pointer at the
  /// press, so no hover ever arrives — leaving the system cursor hidden
  /// (the tracker's `MouseCursor.none` is mounted regardless) and nothing
  /// drawn in its place: the "커서가 사라짐" report. Seeding from here on
  /// the first frame the cursor arms gives the icon somewhere to be.

  /// Guards the seeding to once per arming.
  bool _eyedropperHoverSeeded = false;

  /// 🚨★★D34 PROBE — **the ONE writer of the aim, and it says who wrote it.**
  ///
  /// 유저 재보고 (2026-08-23): the ring still appears on a pinch after the
  /// promoted-touch gate and the seed guard both shipped. Four candidate
  /// paths were eliminated from source (a finger writing the aim; a
  /// promoted mouse arriving as an app event; the zoom re-mapping the
  /// position; the seed republishing a stale one) — so if it still happens
  /// there is a FIFTH route I have not read, and no amount of further
  /// reading has found it.
  ///
  /// ★So stop reading and measure. Every write goes through here and names
  /// itself; the Input Inspector prints the line the moment the ring
  /// appears, and whichever source is on that line IS the answer.
  ///
  /// ⚠️This became possible only after H21 — the card used to freeze on the
  /// first build-time probe, which is exactly why the same question cost
  /// three wrong guesses yesterday. The instrument had to be repaired
  /// before it could be believed.
  ///
  /// Costs nothing while the inspector is hidden: [InputInspector.note]
  /// returns on the visibility check before touching anything.
  void setToolCursorHover(Offset? position, String source) {
    if (InputInspector.visible.value &&
        _state._toolCursorHover.value != position) {
      final where = position == null
          ? 'null'
          : '(${position.dx.round()},${position.dy.round()})';
      InputInspector.note(
        'aim $source -> $where'
        ' held=${_state._tap.aimIsHeld} touch=${CanvasTouchContacts.appWideCount}/${CanvasTouchContacts.count}'
        ' draws=${AppInput.touchDraws}',
      );
    }
    _state._toolCursorHover.value = position;
  }

  /// 🐛유저, R3 #8: 선택툴 누르고 필이나 지우개나 다른툴누르면 커서가 사라짐.
  ///
  /// A tool cursor hides the system one and draws itself at the last
  /// position the census reported — and the census only reports on real
  /// pointer EVENTS. Arming a cursor while the pointer sits still (which is
  /// exactly what pressing a tool button does) therefore hid the system
  /// cursor and drew nothing in its place, until the hand moved. Flutter
  /// synthesises enter/exit for a freshly mounted region but never a hover,
  /// so there is nothing to wait for: the position we already know IS the
  /// answer.
  /// 🚨★★D34 (유저 2026-08-23, 실기): 「확대축소시 매번 보이는게아니라
  /// **생겼다 없었다** 하고 … **남아있으면 다음 터치시 계속 남아있고,
  /// 사라지고나서 터치하면 비교적 커서 안생기는거같아.** 다만 커서 생길때는
  /// **2핑거 조작후 0.5초정도 뒤에 생기는느낌** … 커서 생긴상태에서 손뗄때도
  /// 생겼을때는 **커서가 존재하는채로 순간이동**」
  ///
  /// ⛔THIS RUNS FROM `build()`, AND IT RESURRECTS A DEAD AIM. All five of
  /// those observations are this one line:
  ///
  /// * a zoom changes the viewport, so the panel REBUILDS — and every
  ///   rebuild re-publishes the stale position (생겼다 없었다);
  /// * it fires on a rebuild rather than on an event, so it lands a beat
  ///   late (0.5초 뒤에 생기는 느낌);
  /// * what it republishes is wherever the pointer last WAS, so the ring
  ///   comes back somewhere else entirely (순간이동);
  /// * once non-null it early-returns, and a refused finger clears nothing,
  ///   so it stays (남아있으면 계속);
  /// * after a real clear `_lastCanvasPointer` is null too, so there is
  ///   nothing left to resurrect (사라지고나서 터치하면 안 생김).
  ///
  /// ⚠️The D34 write gate does NOT cover this: that one stops a promoted
  /// mouse from WRITING the position, while this republishes one already
  /// stored. Two different verbs on the same field.
  ///
  /// ★So the seed asks whether anyone still HOLDS the aim. It exists for
  /// R3 #8 — arming a cursor while the pointer sits still, which is exactly
  /// what pressing a tool button does — and there the mouse or pen IS on
  /// the glass, so [_state._tap.aimIsHeld] is true and that fix is untouched. What it
  /// must never do is put a ring back for a pointer that has left, at
  /// coordinates nobody is pointing at any more.
  // ⛔THE SEED IS GONE. It existed because the aim lived in TWO fields: the
  // notifier the ring reads, and a plain `_lastCanvasPointer` that kept the
  // position while no cursor was armed — so arming one later had to copy
  // the second into the first, from `build()`.
  //
  // 🚨That copy is the whole D34 tail. It republished a position nobody was
  // pointing at any more (#1184), and it undid the touch-landed clear one
  // frame later (#1189) — because clearing one field never cleared the
  // other. Three fixes, one shape.
  //
  // ★The notifier holds the aim unconditionally now, and every cursor is
  // already mounted behind its own `brushCursorActive` gate: the value
  // simply being there IS the arming. R3 #8's report — 「선택툴 누르고 필이나
  // 지우개나 다른툴누르면 커서가 사라짐」 — stays fixed, by construction
  // rather than by a build-time copy.

  /// The four tool cursors' VISUALS, for the deck above the artwork.
  ///
  /// They used to be `Positioned` siblings of the canvas inside one Stack,
  /// which is what made a hover cost a full re-record of the layer stack.
  /// Their TRACKERS stay down there on purpose (see the deck's comment):
  /// those are full-bleed `MouseRegion`s that decide hit-testing and which
  /// system cursor wins, and moving them would reorder both for no gain.
  ///
  /// ⚠️CONTRACT for every widget returned here: it either paints nothing or
  /// carries its own `RepaintBoundary`. A cursor whose notifier is null
  /// returns `SizedBox.shrink()` and satisfies the first half — and keeping
  /// that shrink, rather than an always-mounted render object gated in
  /// `paint`, is what keeps `find.byKey(...)` answering `findsNothing`
  /// before the pointer has been anywhere. That assertion is the standing
  /// oracle for R3 #8 (선택툴 누르고 다른 툴 누르면 커서가 사라짐).
  List<Widget> toolCursorLayers() {
    return [
      if (eyedropperCursorActive) ...[
        // The hover SWATCH gets no boundary, deliberately. Its content
        // changes on every sample, so it would re-record anyway — and its
        // `BoxShadow` draws outside its 26px box, which a boundary's cull
        // rect is entitled to clip (harder under Impeller than Skia).
        ValueListenableBuilder<({Offset position, int color})?>(
          valueListenable: _state._eyedropperHover,
          builder: (context, hover, _) {
            if (hover == null) {
              return const SizedBox.shrink();
            }
            return Positioned(
              left: hover.position.dx + 14,
              top: hover.position.dy - 34,
              child: IgnorePointer(
                child: Container(
                  key: const ValueKey<String>('eyedropper-hover-swatch'),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Color(0xFF000000 | hover.color),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black38, blurRadius: 3),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        // R26 #22: the eyedropper ICON as the cursor. Its tip is the hot
        // spot, so the glyph hangs up-left of the point being sampled.
        //
        // A constant glyph, so its layer is worth caching: moving it is
        // then a layer offset rather than a text-and-icon re-record.
        ValueListenableBuilder<({Offset position, int color})?>(
          valueListenable: _state._eyedropperHover,
          builder: (context, hover, _) {
            if (hover == null) {
              return const SizedBox.shrink();
            }
            return Positioned(
              left: hover.position.dx - 3,
              top: hover.position.dy - 21,
              child: const IgnorePointer(
                child: RepaintBoundary(
                  child: _ToolCursorIcon(
                    keyValue: 'eyedropper-cursor-icon',
                    icon: Icons.colorize,
                  ),
                ),
              ),
            );
          },
        ),
      ],
      // R26 #23: the fill tool wears the bucket.
      if (fillCursorActive)
        ValueListenableBuilder<Offset?>(
          valueListenable: _state._toolCursorHover,
          builder: (context, position, _) {
            if (position == null) {
              return const SizedBox.shrink();
            }
            return Positioned(
              left: position.dx - 3,
              top: position.dy - 20,
              child: const IgnorePointer(
                child: RepaintBoundary(
                  child: _ToolCursorIcon(
                    keyValue: 'fill-cursor-icon',
                    icon: Icons.format_color_fill,
                  ),
                ),
              ),
            );
          },
        ),
      // The painting tools wear their own footprint: an outline of the tip
      // that follows the pointer, so a stroke can be aimed before it starts.
      //
      // `BrushCursorOverlay` already has the right shape inside
      // (`Positioned > IgnorePointer > RepaintBoundary > CustomPaint`), so
      // there is nothing to add here.
      // The stamp wears the PIECE, for the same reason the brush wears its
      // footprint: without it the only way to learn where a stamp lands is
      // to drop it and undo. It matters more here — a stamp puts down a
      // whole drawing, not a dot.
      // 🚨★★★F-33 (유저): the stamp's ghost now rides the SURFACE PAINTER,
      // not a widget above the canvas — 「레이어 블렌드모드나 **합성같은게
      // 다** 반영되는」. This branch publishes it and draws nothing; the
      // painter's `layerPaint` is what makes the layer's opacity, blend and
      // group buffer reach it.
      //
      // ⛔It still MOUNTS here, because the decoded image belongs to
      // [CutPieceImageHost] and the publisher drops the reference in the
      // same dispose that frees it.
      if (canvasToolStamps(_state.widget.brushToolState.tool) &&
          _state.widget.cutPieceSlot != null)
        ListenableBuilder(
          listenable: _state.widget.cutPieceSlot!,
          builder: (context, _) {
            final piece = _state.widget.cutPieceSlot!.piece;
            if (piece == null) {
              return CutStampPreviewPublisher(
                sink: _state._stampPreview,
                preview: null,
              );
            }
            return ValueListenableBuilder<Offset?>(
              valueListenable: _state._toolCursorHover,
              builder: (context, position, _) => CutPieceImageHost(
                piece: piece,
                builder: (context, image) => CutStampPreviewPublisher(
                  sink: _state._stampPreview,
                  preview: position == null
                      ? null
                      : _stampPreviewAt(position, piece, image),
                ),
              ),
            );
          },
        ),
      if (brushCursorActive)
        ValueListenableBuilder<Offset?>(
          valueListenable: _state._toolCursorHover,
          builder: (context, position, _) {
            if (position == null) {
              return const SizedBox.shrink();
            }
            return BrushCursorOverlay(
              position: position,
              viewport: _state._viewportState._viewport,
              size: _state.widget.brushToolState.size,
              roundness: _state.widget.brushToolState.roundness,
              angleDegrees: _state.widget.brushToolState.angleDegrees,
            );
          },
        ),
    ];
  }

  void seedEyedropperHoverIfNeeded() {
    if (!eyedropperCursorActive) {
      _eyedropperHoverSeeded = false;
      return;
    }
    if (_eyedropperHoverSeeded || _state._eyedropperHover.value != null) {
      return;
    }
    final position = _state._toolCursorHover.value;
    if (position == null) {
      return;
    }
    _eyedropperHoverSeeded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_state.mounted &&
          eyedropperCursorActive &&
          _state._eyedropperHover.value == null) {
        sampleEyedropperHover(position);
      }
    });
  }

  void sampleEyedropperHover(Offset localPosition) {
    final sample = _state.widget.sampleColorAt;
    if (sample == null) {
      return;
    }
    final color = sample(
      _state._viewportState._viewport.viewportToCanvas(
        ViewportPoint(x: localPosition.dx, y: localPosition.dy),
      ),
    );
    _state._eyedropperHover.value = color == null
        ? null
        : (position: localPosition, color: color);
  }
}
