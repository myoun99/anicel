part of '../canvas_layer_stack_view.dart';

/// The canvas's screen on the engine (screen-on-the-engine c6): a frame's
/// rows folded into the engine's ([EngineRow]) and laid by the one
/// translator ([planCompositeTree]) onto the frame the engine keeps
/// ([GpuScreen]) — the world a frame's picture holds, the page and every
/// row's content ([StackedFrame.extent]) — and shown through the view's
/// camera onto a target: a [ScreenTexture]'s next ([ScreenTexture.present]).
///
/// 🚨★★★ONE PICTURE AT THE FRAME'S OWN RESOLUTION, RESAMPLED ONCE, AT EVERY
/// ZOOM: 유저 (D7-2-Q2, 2026-10-24) 「배율이 어떻든 항상 원본 한장 … 100%랑
/// 통일하되, 그런 문제는 통일한 이후 극한으로 해결하고싶어」, 10-25
/// 「원본기준으로 해서 쓸데없는 소재 없애고 거기서 극한 최적화 해야지」;
/// F-215 「on하든off하든 바뀌는게 없어야」. So no row is asked how it looks
/// at this zoom, and ink parked on the pasteboard composes with the rest
/// (유저 2026-08-15 「페이스트보드도 룰러할때 보이게」).
///
/// ↩️The stack composed into one buffer of the view at the frame's
/// resolution (2026-08-16), and past a side of 8192 fell to a walk of its
/// rows on the screen, the safety net 유저 asked for in place of anything
/// more (2026-09-16: 「안전망만 존재하면 문제없고」), until the engine kept a
/// frame in tiles: it has no such side.
final class EngineStackScreen {
  /// A screen of [composite]'s, laying cel numbers in [letters].
  EngineStackScreen(this._composite, this._letters);

  final GpuComposite _composite;
  final EngineLetters _letters;

  GpuScreen? _screen;

  /// The world pixels [_screen] keeps.
  Rect _kept = Rect.zero;

  /// The mask the range a fill holds is marked under.
  late final EngineRangeMask _range = EngineRangeMask(_composite);

  /// Lays [frame] onto the kept frame over the world pixels [changed] —
  /// all of it the first time, and when the world the frame holds is not
  /// the one kept: a stroke past the page grows it. Where it changed is
  /// the caller's to say ([StackedFrame.movedSince]); null is everywhere.
  /// Its chains' puts are held in [holds], if any.
  void compose(
    StackedFrame frame, {
    Rect? changed,
    EngineChainHolds? holds,
  }) => _laid(
    frame,
    holds,
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
    EngineChainHolds? holds,
  }) {
    final under = film._screen;
    if (under == null) {
      compose(frame, holds: holds);
      return;
    }
    _laid(
      frame,
      holds,
      (screen, pool, plan, _) =>
          screen.composeOver(under, pool, plan, _edgesOf(fresh)),
    );
  }

  /// [frame]'s rows planned ([_planned]) and handed to [lay] with the kept
  /// frame — made again over the world the frame holds where it is not the
  /// one kept. Its chains' puts are held in [holds], if any.
  ///
  /// Throws [FrameKernelsToCome], nothing laid, where the frame has an
  /// effect chain and the chains' kernels are not compiled yet.
  void _laid(
    StackedFrame frame,
    EngineChainHolds? holds,
    void Function(GpuScreen screen, GpuPool pool, GpuPlan plan, Rect world)
    lay,
  ) {
    final stages = FxPluginStages.recording;
    _planned(
      frame,
      _composite,
      _letters,
      maskOf: _range.of,
      holds: holds,
      run: (pool, plan, world) {
        if (stages != null && stages.aRoundComesAfter) {
          // On no screen: a round with a plug-in's step still to run lays
          // what the next one reads, and the screen stays on what it holds
          // (🗣️I-132-Q34 a).
          final nowhere = GpuScreen(_composite, _edgesOf(world));
          try {
            lay(nowhere, pool, plan, world);
          } finally {
            nowhere.free();
          }
        } else {
          lay(_screenOver(world), pool, plan, world);
        }
      },
    );
    _range.settle();
  }

  /// The screen kept, made again where it is not of [world].
  GpuScreen _screenOver(Rect world) {
    if (_screen case final screen? when world == _kept) {
      return screen;
    }
    _screen?.free();
    _kept = world;
    return _screen = GpuScreen(_composite, _edgesOf(world));
  }

  /// The kept frame through [viewport] at [devicePixelRatio] onto [target]
  /// of [size] texels, columns by rows, one a device pixel — the camera a
  /// view's content stands under ([applyViewportTransform]), its pan snapped
  /// to whole device pixels — waiting for the GPU ([GpuScreen.show]).
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

  /// What a frame over the world [extent] will keep: a tile for each it
  /// meets, before any halving a screen reads ([GpuScreen.bytes]).
  static int bytesOver(Rect extent) {
    if (extent.isEmpty) {
      return gpuTileBytes;
    }
    int span(double from, double to) =>
        floorDiv(to.ceil() - 1, gpuTileSide) -
        floorDiv(from.floor(), gpuTileSide) +
        1;
    return span(extent.left, extent.right) *
        span(extent.top, extent.bottom) *
        gpuTileBytes;
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
}

/// [rect], of whole pixels, as the engine's edges: [left, top, right,
/// bottom).
(int, int, int, int) _edgesOf(Rect rect) => (
  rect.left.floor(),
  rect.top.floor(),
  rect.right.ceil(),
  rect.bottom.ceil(),
);

/// The picture a fill pressed on [frame] reads, over the pixels [box] of
/// the space its seed is in — the canvas, or [space], the artwork of a row
/// posed on it: [frame]'s rows as a screen lays them ([_planned]) — blends,
/// folders, effects and letters as they show (🗣️유저
/// gpu-canonical-store-Q1, 2026-11-06: 「화면과 똑같은 그림을 읽는다」), on
/// no paper where the frame's page paints none (🗣️I-163-Q6, 2026-11-05:
/// 「지금 합성에서 종이만 뺀다」) — kept on the GPU for every press that
/// floods it and freed by whoever asked. Its chains' puts are held in
/// [holds], if any, as a screen's are.
///
/// 🚨★★★THE PICTURE LIES IN THE SEED'S SPACE (I-36, 🗣️유저 2026-09-24:
/// 「이 과정에서 법 다른거 통일」 — one law for the fill on a posed row and
/// off one): the seed and the dab of a posed row are in its artwork, so
/// what shows is carried there whole — one read of the canvas's picture
/// through the pose, as a row posed on the canvas is read — and the
/// region a flood finds is the one its colour lands on. ↩️Each row was
/// carried into the seed's space by itself and summed there
/// (`LazyCanvasRasterRgb`, till 2026-11-12), which no folder's chain or
/// blend could follow.
///
/// ⚠️A plug-in's steps are drawn as if off: a press waits for no round of
/// them ([FxPluginStages.recordedThrough]).
///
/// Throws [FrameKernelsToCome], nothing read, where the frame has an effect
/// chain and the chains' kernels are not compiled yet.
GpuFloodPicture fillPictureOf(
  StackedFrame frame,
  GpuComposite composite,
  EngineLetters letters,
  DirtyRegion box, {
  GuideTransform? space,
  EngineChainHolds? holds,
}) {
  final extent = (
    box.left,
    box.top,
    box.rightExclusive,
    box.bottomExclusive,
  );
  return _planned(
    frame,
    composite,
    letters,
    // A frame read for a fill is its cels as they are stored: no hand is on
    // it, so no row of it holds a range.
    maskOf: (_) => throw StateError('a frame a fill reads holds no range'),
    holds: holds,
    run: (pool, plan, world) => switch (space) {
      null => GpuFloodPicture(composite, pool, plan, extent),
      // Nothing shows past the world the frame holds — its page and every
      // row's content —, however far the pose lands the box.
      final space => GpuFloodPicture.posed(
        composite,
        pool,
        plan,
        extent,
        toCanvas: gpuRowInverse(space),
        within: _edgesOf(world),
      ),
    },
  );
}

/// [frame]'s rows planned by the one translator ([planCompositeTree]) on
/// the ledger's tiles and handed to [run] with the pool those are on and
/// the world the frame holds — its page and every row's content: [run]'s
/// answer. The range a fill holds on a row is marked under the mask
/// [maskOf] gives its cover, and each node's chain is held in [holds], if
/// any, as what the node shows ([_FrameReading._pictureOf]) on this paper
/// ([_holding]) — and what its plug-ins' steps make kept past it where
/// those are the pen's frame's ([EngineChainHolds.ofThePensFrame]).
///
/// 🚨ONE PLANNING: what a screen keeps ([EngineStackScreen._laid]) and what
/// a fill reads ([fillPictureOf]) are the same rows by the same law.
///
/// Throws [FrameKernelsToCome], nothing run, where the frame has an effect
/// chain and the chains' kernels are not compiled yet.
T _planned<T>(
  StackedFrame frame,
  GpuComposite composite,
  EngineLetters letters, {
  required GpuMask Function(FloodFillRegion cover) maskOf,
  required EngineChainHolds? holds,
  required T Function(GpuPool pool, GpuPlan plan, Rect world) run,
}) {
  final pass = _FrameReading(frame._painter);
  // A frame of nothing keeps one pixel of nothing: shown through any
  // camera, it shows nothing.
  final world = switch (pass.frameExtent()) {
    final extent when extent.isEmpty => const Rect.fromLTWH(0, 0, 1, 1),
    final extent => extent,
  };
  final stages = FxPluginStages.recording;
  final ledger = EngineTileLedger.instance;
  final paper = frame._painter.canvasSize.canvasRect;
  final origins =
      Map<CompositeNode<EngineRow>, CompositeNode<_PaintRow>>.identity();
  return ledger.held((hold) {
    final plan = GpuPlan();
    try {
      planCompositeTree(
        plan,
        mapCompositeLeaves<_PaintRow, EngineRow>(
          pass._rootNodes,
          (row) => pass._engineRowOf(row, maskOf),
          told: holds == null ? null : (node, to) => origins[to] = node,
        ),
        hold: hold,
        paper: paper,
        letters: letters,
        holding: _holding(holds, pass, origins, paper),
        plugins: stages == null
            ? null
            : (
                steps: stages,
                engine: composite.engine,
                ofThePensFrame: holds?.ofThePensFrame ?? false,
              ),
      );
      // Not run while its chains' kernels are still to be compiled: the
      // run would compile them here, the app stopped meanwhile.
      FrameKernelsToCome.throwIfNamedBy(plan, composite);
      return run(ledger.pool, plan, world);
    } finally {
      plan.free();
      holds?.settle();
    }
  });
}

/// The holding of the chains [pass] plans ([ChainHolding]): a node's, on
/// [paper], under what the node it came from shows ([origins]) — none for
/// one that shows a row drawn live ([_FrameReading._pictureOf]).
ChainHolding? _holding(
  EngineChainHolds? holds,
  _FrameReading pass,
  Map<CompositeNode<EngineRow>, CompositeNode<_PaintRow>> origins,
  Rect paper,
) => switch (holds) {
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

extension on _FrameReading {
  /// [row] as the engine lays it: the paper a solid over the page, a
  /// surface row its slot ([_slotOf]) — its tiles as its painter shows
  /// them, a live stroke's in their place ([BitmapSurfacePainter
  /// .shownSurface]), kept under its cel's lineage, what a hand holds over
  /// them ([_heldOver]) and the range a fill holds
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

  /// The range a fill holds on [slot]'s row, marked over the row
  /// ([FillRangeMark]) — none where it holds none.
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
  /// row's own pixels — under the row's own opacity and effects, as what it
  /// lands as (유저 확정 A: 「프리뷰는 원래 그런거」: a half-opacity row
  /// previews a transform at half opacity).
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
