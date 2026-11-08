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
  /// A screen of [composite]'s, laying cel numbers in [letters] and holding
  /// its chains' puts in [holds], if any.
  EngineStackScreen(this._composite, this._letters, {EngineChainHolds? holds})
    : _holds = holds;

  final GpuComposite _composite;
  final EngineLetters _letters;
  final EngineChainHolds? _holds;

  GpuScreen? _screen;

  /// The world pixels [_screen] keeps.
  Rect _kept = Rect.zero;

  /// The mask the range a fill holds is marked under.
  late final EngineRangeMask _range = EngineRangeMask(_composite);

  /// Lays [frame] onto the kept frame over the world pixels [changed] —
  /// all of it the first time, and when the world the frame holds is not
  /// the one kept: a stroke past the page grows it. Where it changed is
  /// the caller's to say ([StackedFrame.movedSince]); null is everywhere.
  void compose(StackedFrame frame, {Rect? changed}) => _laid(
    frame,
    (screen, pool, plan, world) =>
        screen.compose(pool, plan, _edgesOf(changed ?? world)),
  );

  /// Lays [frame] as [compose] does the first time, onto a screen nothing
  /// is laid on yet, but over the world pixels [fresh] alone: the rest is
  /// [film]'s kept frame, copied tile by tile as it is — a frame over the
  /// frame its ghosts lie on, which the tiles they do not reach show as it
  /// does. Over a film nothing is laid on, all of it; onto a screen laid
  /// on already, refused with the engine's reason.
  void composeOver(
    EngineStackScreen film,
    StackedFrame frame, {
    required Rect fresh,
  }) {
    final under = film._screen;
    if (under == null) {
      compose(frame);
      return;
    }
    _laid(
      frame,
      (screen, pool, plan, _) =>
          screen.composeOver(under, pool, plan, _edgesOf(fresh)),
    );
  }

  /// [frame]'s rows planned by the one translator and handed to [lay] with
  /// the kept frame — made again over the world the frame holds where it
  /// is not the one kept. Each node's chain is held as what the node shows
  /// ([_LayerStackPaintPass._pictureOf]) on this paper ([_holding]).
  void _laid(
    StackedFrame frame,
    void Function(GpuScreen screen, GpuPool pool, GpuPlan plan, Rect world)
    lay,
  ) {
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
    final paper = frame._painter.canvasSize.canvasRect;
    final origins =
        Map<CompositeNode<EngineRow>, CompositeNode<_PaintRow>>.identity();
    ledger.held((hold) {
      final plan = GpuPlan();
      try {
        planCompositeTree(
          plan,
          mapCompositeLeaves<_PaintRow, EngineRow>(
            pass._rootNodes,
            (row) => pass._engineRowOf(row, _range.of),
            told: _holds == null ? null : (node, to) => origins[to] = node,
          ),
          hold: hold,
          paper: paper,
          letters: _letters,
          holding: _holding(pass, origins, paper),
        );
        lay(screen!, ledger.pool, plan, world);
      } finally {
        plan.free();
        _holds?.settle();
      }
    });
    _range.settle();
  }

  /// The holding of the chains [pass] plans ([ChainHolding]): a node's, on
  /// [paper], under what the node it came from shows ([origins]) — none
  /// for one that shows a row drawn live ([_LayerStackPaintPass._pictureOf]).
  ChainHolding? _holding(
    _LayerStackPaintPass pass,
    Map<CompositeNode<EngineRow>, CompositeNode<_PaintRow>> origins,
    Rect paper,
  ) => switch (_holds) {
    null => null,
    final holds => (
      held: holds.held,
      idOf: (node) => switch (origins[node]) {
        final origin? => switch (pass._pictureOf(origin)) {
          final picture? => holds.idOf((picture: picture, paper: paper)),
          null => null,
        },
        null => null,
      },
    ),
  };

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

  /// The bytes the kept frame holds on the GPU ([GpuScreen.bytes]) — none
  /// before a frame is laid.
  int get bytes => _screen?.bytes ?? 0;

  /// Frees the kept frame; before its executor is.
  void free() {
    _screen?.free();
    _screen = null;
    _range.free();
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
  /// .shownSurface]), kept under its cel's lineage, what a hand holds over
  /// them where the walk draws it ([_heldOver]) and the range a fill holds
  /// on it, marked under the mask [maskOf] gives its cover ([_markOn]).
  EngineRow _engineRowOf(
    _PaintRow row,
    GpuMask Function(FloodFillRegion cover) maskOf,
  ) => switch (row) {
    _PaintPaper() => EngineSolid(
      argb: _painter.paperBackground.paintedArgb,
      rect: DirtyRegion.fromLTBR(
        left: _painter.canvasSize.canvasRect.left.floor(),
        top: _painter.canvasSize.canvasRect.top.floor(),
        rightExclusive: _painter.canvasSize.canvasRect.right.ceil(),
        bottomExclusive: _painter.canvasSize.canvasRect.bottom.ceil(),
      ),
    ),
    _PaintCelSurface(:final lineage) => _engineTilesOf(
      row,
      maskOf,
      lineage: lineage,
    ),
    final _SurfaceRow row => _engineTilesOf(row, maskOf),
  };

  EngineTiles _engineTilesOf(
    _SurfaceRow row,
    GpuMask Function(FloodFillRegion cover) maskOf, {
    Object? lineage,
  }) {
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
      mark: _markOn(slot, maskOf),
    );
  }

  /// The range a fill holds on [slot]'s row, as the walk marks it over the
  /// row ([FillRangeMark]) — none where it holds none.
  EngineMark? _markOn(
    _SurfaceSlot slot,
    GpuMask Function(FloodFillRegion cover) maskOf,
  ) => switch (slot.painter.overlayModel?.fillRange) {
    null => null,
    final range => EngineMark(
      mask: maskOf(range.cover),
      bounds: range.bounds,
      shift: range.shift,
    ),
  };

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
