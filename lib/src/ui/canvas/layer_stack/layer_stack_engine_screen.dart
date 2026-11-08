part of '../canvas_layer_stack_view.dart';

/// The canvas's screen on the engine (screen-on-the-engine c6): a frame's
/// rows folded into the engine's ([EngineRow]) and laid by the one
/// translator ([planCompositeTree]) onto the frame the engine keeps
/// ([GpuScreen]) — the world a frame's picture holds, the page and every
/// row's content ([StackedFrame.drawing]) — and shown through the view's
/// camera onto a target: a [ScreenTexture]'s next ([ScreenTexture.present]).
// ⏳The widget asks it at the end of the flip lane (관제 11-08 15:02 ⓐ);
// [ScreenTexture] says why.
final class EngineStackScreen {
  /// A screen of [composite]'s, laying cel numbers in [letters].
  EngineStackScreen(this._composite, this._letters);

  final GpuComposite _composite;
  final EngineLetters _letters;

  GpuScreen? _screen;

  /// The world pixels [_screen] keeps.
  Rect _kept = Rect.zero;

  /// Lays [frame] onto the kept frame over the world pixels [changed] —
  /// all of it the first time, and when the world the frame holds is not
  /// the one kept: a stroke past the page grows it. Where it changed is
  /// the caller's to say ([StackedFrame.movedSince]); null is everywhere.
  void compose(StackedFrame frame, {Rect? changed}) {
    final pass = _LayerStackPaintPass(frame._painter);
    // A frame of nothing keeps one pixel of nothing: shown through any
    // camera, it shows nothing.
    final world = switch (pass.frameExtent()) {
      final extent when extent.isEmpty => const Rect.fromLTWH(0, 0, 1, 1),
      final extent => extent,
    };
    var screen = _screen;
    if (screen == null || world != _kept) {
      screen?.free();
      screen = _screen = GpuScreen(_composite, _edgesOf(world));
      _kept = world;
    }
    final ledger = EngineTileLedger.instance;
    ledger.held((hold) {
      final plan = GpuPlan();
      try {
        planCompositeTree(
          plan,
          mapCompositeLeaves<_PaintRow, EngineRow>(
            pass._rootNodes,
            pass._engineRowOf,
          ),
          hold: hold,
          paper: frame._painter.canvasSize.canvasRect,
          letters: _letters,
        );
        screen!.compose(ledger.pool, plan, _edgesOf(changed ?? world));
      } finally {
        plan.free();
      }
    });
  }

  /// The kept frame through [viewport] at [devicePixelRatio] onto [target]
  /// of [size] texels, columns by rows, one a device pixel — the camera the
  /// walk draws through ([applyViewportTransform]), its pan snapped as
  /// there — waiting for the GPU ([GpuScreen.show]).
  void show(
    GpuTarget target,
    (int, int) size, {
    required CanvasViewport viewport,
    required double devicePixelRatio,
  }) {
    final screen =
        _screen ??
        (throw StateError('a screen is shown before a frame is laid on it'));
    final camera = viewportInverseTransformMatrix(
      renderSnappedViewport(viewport, devicePixelRatio),
    ).storage;
    // A texel is a device pixel, the camera's unit a logical one.
    final per = 1 / devicePixelRatio;
    final scale = displayScaleOf(viewport.zoom, devicePixelRatio);
    final (columns, rows) = size;
    screen.show(
      target,
      inverse: [
        camera[0] * per,
        camera[4] * per,
        camera[12],
        camera[1] * per,
        camera[5] * per,
        camera[13],
      ],
      scale: scale,
      sampling: gpuSamplingOf(filterQualityForDisplayScale(scale)),
      rect: (0, 0, columns, rows),
    );
  }

  /// Frees the kept frame; before its executor is.
  void free() {
    _screen?.free();
    _screen = null;
  }

  /// [rect], of whole pixels, as the engine's edges: [left, top, right,
  /// bottom).
  static (int, int, int, int) _edgesOf(Rect rect) => (
    rect.left.floor(),
    rect.top.floor(),
    rect.right.ceil(),
    rect.bottom.ceil(),
  );
}

extension on _LayerStackPaintPass {
  /// [row] as the engine lays it: the paper a solid over the page, a
  /// surface row its slot ([_slotOf]) — its tiles as its painter shows
  /// them, a live stroke's in their place ([BitmapSurfacePainter
  /// .shownSurface]), kept under its cel's lineage, and what a hand holds
  /// over them where the walk draws it ([_heldOver]).
  EngineRow _engineRowOf(_PaintRow row) => switch (row) {
    _PaintPaper() => EngineSolid(
      argb: _painter.paperBackground.paintedArgb,
      rect: DirtyRegion.fromLTBR(
        left: _painter.canvasSize.canvasRect.left.floor(),
        top: _painter.canvasSize.canvasRect.top.floor(),
        rightExclusive: _painter.canvasSize.canvasRect.right.ceil(),
        bottomExclusive: _painter.canvasSize.canvasRect.bottom.ceil(),
      ),
    ),
    _PaintCelSurface(:final lineage) => _engineTilesOf(row, lineage: lineage),
    final _SurfaceRow row => _engineTilesOf(row),
  };

  EngineTiles _engineTilesOf(_SurfaceRow row, {Object? lineage}) {
    final slot = _slotOf(row);
    final painter = slot.painter;
    return EngineTiles(
      lineage: lineage ?? painter.lineage ?? BrushFrameKey.noCel,
      surface: painter.shownSurface,
      placement: row.placement,
      opacity: row.opacity,
      blendMode: row.blendMode,
      effects: row.effects,
      tint: row.tint,
      held: _heldOver(slot),
    );
  }

  /// What a hand holds over [slot]'s row: each float its painter draws over
  /// it ([BitmapSurfacePainter.floatsOver]), by the tiles it holds, in the
  /// row's own pixels.
  List<EngineHeld> _heldOver(_SurfaceSlot slot) => [
    for (final (:preview, :canvasToRow) in slot.painter.floatsOver(slot.shown))
      for (final held in preview.heldTiles) _engineHeldOf(held, canvasToRow),
  ];
}

/// [held] as the engine lays it over its row, which [canvasToRow] takes the
/// space of its preview into — none where the two are one.
EngineHeld _engineHeldOf(HeldTiles held, Matrix4? canvasToRow) {
  final (:tiles, :dx, :dy, :laying) = held;
  final rowToPreview = (canvasToRow == null
          ? Matrix4.identity()
          : Matrix4.inverted(canvasToRow))
      .storage;
  return EngineHeld(
    // A float's tiles are no cel's: kept by the tile, as long as it lives.
    lineage: BrushFrameKey.noCel,
    tiles: tiles,
    toHeld: GuideTransform(
      rowToPreview[0],
      rowToPreview[1],
      rowToPreview[4],
      rowToPreview[5],
      rowToPreview[12] - dx,
      rowToPreview[13] - dy,
    ),
    laying: laying,
  );
}
