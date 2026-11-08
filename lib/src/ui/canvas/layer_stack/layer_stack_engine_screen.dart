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
            frame._painter._engineRowOf,
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

extension on _LayerStackPainter {
  /// [row] as the engine lays it: the paper a solid over the page, a
  /// surface row its tiles as its painter shows them — a live stroke's in
  /// their place ([BitmapSurfacePainter.shownSurface]) — kept under its
  /// cel's lineage.
  EngineRow _engineRowOf(_PaintRow row) => switch (row) {
    _PaintPaper() => EngineSolid(
      argb: paperBackground.paintedArgb,
      rect: DirtyRegion.fromLTBR(
        left: canvasSize.canvasRect.left.floor(),
        top: canvasSize.canvasRect.top.floor(),
        rightExclusive: canvasSize.canvasRect.right.ceil(),
        bottomExclusive: canvasSize.canvasRect.bottom.ceil(),
      ),
    ),
    _PaintActiveSurface() => _engineTilesOf(row, activeSurfacePainter!),
    _PaintLiftedSurface(:final lifted) => _engineTilesOf(row, lifted.surface),
    _PaintCelSurface(:final painter, :final lineage) => _engineTilesOf(
      row,
      painter,
      lineage: lineage,
    ),
  };

  EngineTiles _engineTilesOf(
    _SurfaceRow row,
    BitmapSurfacePainter painter, {
    Object? lineage,
  }) => EngineTiles(
    lineage: lineage ?? painter.lineage ?? BrushFrameKey.noCel,
    surface: painter.shownSurface,
    placement: row.placement,
    opacity: row.opacity,
    blendMode: row.blendMode,
    effects: row.effects,
    tint: row.tint,
  );
}
