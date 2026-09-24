part of '../brush_canvas_panel.dart';

/// The TOOL CURSOR — the cursor layers drawn for the active tool (brush,
/// fill, eyedropper, stamp preview) and which one is active — as its own
/// object.
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
      opacity: _state._brush.cutStampOpacity,
      blendMode: _state._brush.cutStampBlendMode,
    );
  }

  /// R26 #23: the fill tool's own cursor icon (no sampling involved).
  bool get fillCursorActive =>
      _state.widget.toolCursorsEnabled &&
      _state._brush.tool == CanvasTool.fill;

  /// The brush/eraser tip outline — the selection tools own the pointer
  /// outright, and a held eyedropper is a tool switch now (I-15), so it
  /// never shares the pointer with the outline.
  bool get brushCursorActive =>
      _state.widget.toolCursorsEnabled &&
      canvasToolPaints(_state._brush.tool);

  /// Whether the eyedropper cursor + hover swatch are armed: the tool is
  /// the eyedropper — picked, or held (a mapped button or Alt switches to it
  /// for as long as it is held, I-15).
  bool get eyedropperCursorActive =>
      _state.widget.sampleColorAt != null &&
      _state._brush.tool == CanvasTool.eyedropper &&
      _state.widget.onEyedropperPick != null;

  /// R27 #17: the last pointer position seen on the canvas — hovers AND
  /// button-held moves alike.
  ///
  /// The eyedropper's icon and swatch only appeared once a fresh hover
  /// event reached their tracker. Entering the tool from a HELD button
  /// (the pen's barrel / right-click mapping) captures the pointer at the
  /// press, so no hover ever arrives — leaving the system cursor hidden
  /// (the tracker's `MouseCursor.none` was mounted regardless) and nothing
  /// drawn in its place: the "커서가 사라짐" report. Seeding from here on
  /// the first frame the cursor armed gave the icon somewhere to be.
  ///
  /// ⛔THE EYEDROPPER SEED IS GONE TOO (F-130, 2026-09-15). It copied the
  /// aim into a second notifier — position plus the colour sampled under
  /// it — because the swatch and the icon read that second notifier. They
  /// read the aim itself now, and the swatch samples in its own `paint`;
  /// the position the census already holds IS where they appear, on the
  /// first frame the tool arms, with nothing to copy and no seed to guard.
  /// R27 #17 stays fixed by construction, the way R3 #8 does below.

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
  /// ⛔THIS RAN FROM `build()`, AND IT RESURRECTED A DEAD AIM. All five of
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

  /// The brush cursor's look for the tool state and the viewport as they
  /// are now: the outline of the tip, in a box that certainly holds it.
  ToolCursorLook _brushLook() => brushCursorLook(
    brushCursorShape(
      viewport: _state._viewportState._viewport,
      size: _state._brush.size,
      roundness: _state._brush.roundness,
      angleDegrees: _state._brush.angleDegrees,
    ),
  );

  /// The composite colour under a panel-local point, for the eyedropper's
  /// swatch — or null while the tool has no sampler.
  int? _sampleAt(Offset viewportPosition) {
    final sample = _state.widget.sampleColorAt;
    if (sample == null) {
      return null;
    }
    return sample(
      _state._viewportState._viewport.viewportToCanvas(
        ViewportPoint(x: viewportPosition.dx, y: viewportPosition.dy),
      ),
    );
  }

  /// The tool cursors' VISUALS, for the deck above the artwork: a sprite
  /// per cursor (`ToolCursorSprite`, moved by layer offset — 유저, F-130:
  /// 「앱 커서만 최대한 가볍게」), and the stamp's ghost publisher.
  ///
  /// They used to be `Positioned` siblings of the canvas inside one Stack,
  /// which is what made a hover cost a full re-record of the layer stack.
  /// Their TRACKERS stay down there on purpose (see the deck's comment):
  /// those are full-bleed `MouseRegion`s that decide hit-testing and which
  /// system cursor wins, and moving them would reorder both for no gain.
  ///
  /// ⚠️CONTRACT for every widget returned here: it either paints nothing or
  /// carries its own `RepaintBoundary`. A sprite IS its own boundary, and
  /// paints nothing while the aim is null — which used to be a
  /// `SizedBox.shrink()` returned from a builder, so that `find.byKey(...)`
  /// answered `findsNothing` before the pointer had been anywhere. That
  /// assertion was the standing oracle for R3 #8 (선택툴 누르고 다른 툴 누르면
  /// 커서가 사라짐); F-130 moved it to `RenderToolCursorSprite.debugPosition`,
  /// which is null for exactly the same reason, so a sprite could be
  /// mounted once and moved without a build.
  List<Widget> toolCursorLayers() {
    final aim = _state._toolCursorHover;
    return [
      if (eyedropperCursorActive) ...[
        // The hover SWATCH: its pixels change with the colour under the
        // pointer, so its picture is re-recorded per move — a disc — and
        // it samples in its own paint, once per frame.
        Positioned.fill(
          child: ToolCursorSprite(
            key: const ValueKey<String>('eyedropper-hover-swatch'),
            position: aim,
            look: eyedropperSwatchLook(position: aim, sample: _sampleAt),
          ),
        ),
        // R26 #22: the eyedropper ICON as the cursor. Its tip is the hot
        // spot, so the glyph hangs up-left of the point being sampled.
        Positioned.fill(
          child: ToolCursorSprite(
            key: const ValueKey<String>('eyedropper-cursor-icon'),
            position: aim,
            look: eyedropperCursorLook(),
          ),
        ),
      ],
      // R26 #23: the fill tool wears the bucket.
      if (fillCursorActive)
        Positioned.fill(
          child: ToolCursorSprite(
            key: const ValueKey<String>('fill-cursor-icon'),
            position: aim,
            look: fillCursorLook(),
          ),
        ),
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
      if (canvasToolStamps(_state._brush.tool) &&
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
            // The ghost wears the stamp's opacity and blend, so it hears the
            // brush as well as the aim — the panel no longer rebuilds for
            // either (H40 ②).
            final brush = _state.widget.brushToolState;
            return ListenableBuilder(
              listenable: brush == null ? aim : Listenable.merge([aim, brush]),
              builder: (context, _) {
                final position = aim.value;
                return CutPieceImageHost(
                  piece: piece,
                  builder: (context, image) => CutStampPreviewPublisher(
                    sink: _state._stampPreview,
                    preview: position == null
                        ? null
                        : _stampPreviewAt(position, piece, image),
                  ),
                );
              },
            );
          },
        ),
      // The painting tools wear their own footprint: an outline of the tip
      // that follows the pointer, so a stroke can be aimed before it starts.
      if (brushCursorActive) Positioned.fill(child: _brushCursor(aim)),
    ];
  }

  /// The brush cursor. The tip's footprint — size, roundness, angle — is
  /// the one part of the brush it SHOWS, so it hears those three for
  /// itself: the panel around it no longer rebuilds for the brush
  /// (H40 ②, see [BrushCanvasPanel.brushToolState]).
  Widget _brushCursor(ValueListenable<Offset?> aim) {
    Widget sprite() => ToolCursorSprite(
      key: const ValueKey<String>('brush-cursor-overlay'),
      position: aim,
      look: _brushLook(),
    );
    final brush = _state.widget.brushToolState;
    if (brush == null) {
      return sprite();
    }
    return SlicedValueListenableBuilder<
      BrushToolState,
      (double, double, double)
    >(
      valueListenable: brush,
      slice: (state) => (state.size, state.roundness, state.angleDegrees),
      builder: (context, _) => sprite(),
    );
  }
}
