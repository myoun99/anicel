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

  /// Where the kept frame was made again, lay by lay: what a show reads to
  /// draw again only what its target does not hold yet ([show]).
  final _Lays _lays = _Lays();

  /// Lays [frame] onto the kept frame over the world pixels [changed] —
  /// all of it the first time, and when the world the frame holds is not
  /// the one kept: a stroke past the page grows it. Where it changed is
  /// the caller's to say ([StackedFrame.movedSince]); null is everywhere.
  /// Its chains' puts are held in [holds], if any — for the canvas
  /// [standing] stands for, where it lays whole the frame that canvas
  /// stands on to draw ([EngineChainHolds.settleOnce]).
  ///
  /// Ends once the GPU has laid it, or fails by why it did not: the
  /// engine lays it with this isolate waiting for none of it
  /// ([GpuScreen.compose]).
  Future<void> compose(
    StackedFrame frame, {
    Rect? changed,
    EngineChainHolds? holds,
    Object? standing,
  }) {
    assert(standing == null || changed == null, 'a step is laid for none');
    return _laid(
      frame,
      holds,
      standing,
      changed,
      (screen, pool, plan, world) =>
          screen.compose(pool, plan, _edgesOf(changed ?? world)),
    );
  }

  /// Lays [frame] as [compose] does the first time, onto a screen nothing
  /// is laid on yet, but [over] the world pixels fresh alone: the rest is
  /// the film's kept frame, copied tile by tile as it is — a frame over the
  /// frame its ghosts lie on, which the tiles they do not reach show as it
  /// does. Over a film nothing is laid on, all of it; onto a screen laid
  /// on already, refused with the engine's reason. Ends as [compose] does,
  /// for the canvas [standing] stands for where it is the frame's picture
  /// laid anew, not a step patched into a copy.
  Future<void> composeOver(
    StackedFrame frame, {
    required ({EngineStackScreen film, Rect fresh}) over,
    EngineChainHolds? holds,
    Object? standing,
  }) {
    final under = over.film._screen;
    if (under == null) {
      return compose(frame, holds: holds, standing: standing);
    }
    return _laid(
      frame,
      holds,
      standing,
      // The first lay of a screen: all of it.
      null,
      (screen, pool, plan, _) =>
          screen.composeOver(under, pool, plan, _edgesOf(over.fresh)),
    );
  }

  /// [frame]'s rows planned ([_planned]) and handed to [lay] with the kept
  /// frame — made again over the world the frame holds where it is not the
  /// one kept: what [lay] ends by. Its chains' puts are held in [holds], if
  /// any, for the canvas [standing] stands for, if any. The kept frame is
  /// made again over the world pixels [changed], all of it where null
  /// ([_Lays.made]).
  ///
  /// Throws [FrameKernelsToCome], nothing laid, where the frame has an
  /// effect chain and the chains' kernels are not compiled yet.
  Future<void> _laid(
    StackedFrame frame,
    EngineChainHolds? holds,
    Object? standing,
    Rect? changed,
    Future<void> Function(
      GpuScreen screen,
      GpuPool pool,
      GpuPlan plan,
      Rect world,
    )
    lay,
  ) {
    final stages = FxPluginStages.recording;
    final laid = _planned(
      frame,
      _composite,
      _letters,
      maskOf: _range.of,
      holds: holds,
      standing: standing,
      run: (pool, plan, world) {
        if (stages != null && stages.aRoundComesAfter) {
          // On no screen: a round with a plug-in's step still to run lays
          // what the next one reads, and the screen stays on what it holds
          // (🗣️I-132-Q34 a).
          final nowhere = GpuScreen(_composite, _edgesOf(world));
          try {
            return lay(nowhere, pool, plan, world);
          } finally {
            nowhere.free();
          }
        }
        final kept = _screenOver(world);
        // Told as it is asked, whether or not the engine lays it. A lay
        // that fails leaves no canvas, and the next lays all of it
        // (`Screen::compose`): the pixels told changed made again, and
        // every other as it was — what a lay of them alone leaves. A
        // frame shown meanwhile is given up, its target holding nothing
        // known (`ScreenTexture.present`).
        _lays.made(changed);
        return lay(kept, pool, plan, world);
      },
      doneOf: (laid) => laid,
    );
    _range.settle();
    return laid;
  }

  /// The screen kept, made again where it is not of [world].
  GpuScreen _screenOver(Rect world) {
    if (_screen case final screen? when world == _kept) {
      return screen;
    }
    _screen?.free();
    _kept = world;
    // Another canvas: nothing a target holds is of it.
    _lays.made(null);
    return _screen = GpuScreen(_composite, _edgesOf(world));
  }

  /// The kept frame through [viewport] at [devicePixelRatio] onto [target]
  /// of [size] texels, columns by rows, one a device pixel — the camera a
  /// view's content stands under ([applyViewportTransform]), its pan snapped
  /// to whole device pixels — the view's corner on the texel [corner] of
  /// it, columns by rows: a target that holds room around its view stands
  /// the view inside (`_RenderFrameScreen`). Its work is handed to the
  /// engine, waited for by none ([GpuScreen.show]).
  ///
  /// 🚨DRAWN WHERE IT DIFFERS ALONE, where [target] still holds this
  /// screen's frame through this very camera ([GpuSurface.kept]): the texels
  /// that read a tile made again since ([_Lays.since]) — the kept frame
  /// differs nowhere else, a lay making again the tiles its rect meets,
  /// whole (`Screen::compose`) —, and nothing where none was. A stroke's
  /// step draws its dabs' tiles, not the screen. What the view holds alone
  /// (below) through any other camera, on a target that holds another's
  /// frame or none known, and past the lays kept apart.
  ///
  /// 🗣️유저 2026-11-21, on a Galaxy Tab (card
  /// the-galaxy-tab-canvas-went-slow-on-build-1095): 「캔버스조작, 즉
  /// 팬이나 줌이나 스트로크가 너무 느려졋어」, and nothing else of the app
  /// slow. ↩️Every frame drew every texel of its target — the box, its
  /// room to pan and what its sides' step spares: 1536×3072 for a window
  /// of 1080×2424, read off an emulator (2026-11-22) —, each by a thread
  /// of the composite's walk, a stroke's step as a zoom's.
  ///
  /// 🚨MOVED WHERE THE CAMERA IS ITS OWN PANNED BY WHOLE TEXELS ([_movedBy]):
  /// the frame [target] holds is moved by them ([GpuComposite.move]) and
  /// what the pan uncovers is drawn, with what differs as above — the
  /// frame then the one drawn whole through this camera, byte for byte.
  /// 🗣️유저 2026-11-23, build 1099's photographs of that tablet:
  /// 「처음은 100미만 팬,줌」 — 🔬a frame past the margin a pan's screen
  /// spares drew all of its 3584×2560 texels again at × 0.63, 43 ms of its
  /// GPU (rust/src/kernels/composite/moved.rs has the rest).
  ///
  /// 🚨THROUGH ANOTHER CAMERA, WHAT THE VIEW HOLDS ALONE ([holding]): the
  /// texels its box and the margin a pan spares lie on — the rest of
  /// [target] on the show after, through this camera or its own panned, as
  /// what it does not hold ([_outside]) — and what [target] holds is told
  /// on it ([heldIn]): a pan the frame drawn last serves stands it within
  /// that alone (`_RenderFrameScreen._servedByTheFrameDrawnLast`). Null, the
  /// whole of it — what a view of no room asks (`frame_shots.dart`).
  /// 🔬A zoom's frame draws its target whole at every step, and its cost is
  /// the texels it draws, every one alike, the camera's taps on a canvas
  /// drawn over (S5 cut 352, every row shown, × 0.85 on an RTX 4080: 1.6
  /// ms walking alone, 4.2 located, 10.7 with Blend's taps — 관제 ·
  /// 브러시/렌더링 2026-11-24, card the-galaxy-tab-canvas-went-slow-on-build-
  /// 1095): the Galaxy Tab's 2960 × 1848 with its margin is 6.77M of the
  /// 9.17M its 3584 × 2560 holds.
  void show(
    GpuSurface target,
    (int, int) size, {
    required CanvasViewport viewport,
    required double devicePixelRatio,
    (int, int) corner = (0, 0),
    (int, int, int, int)? holding,
  }) {
    final screen =
        _screen ??
        (throw StateError('a screen is shown before a frame is laid on it'));
    final scale = displayScaleOf(viewport.zoom, devicePixelRatio);
    final through = _throughOf(viewport, devicePixelRatio, corner, size);
    final (:inverse, :mode, size: _, at: _) = through;
    final (columns, rows) = size;
    final asked = _within(holding ?? (0, 0, columns, rows), size);
    // Read before the draw, which forgets it.
    final (:moved, :drawn, :held) = _toShow(target.kept, through, asked);
    if (moved != null) {
      _composite.move(target, moved);
    }
    for (final rect in drawn) {
      screen.show(target, inverse: inverse, sampling: mode, rect: rect);
    }
    // A move uncovers texels it draws: a show that drew none moved none.
    if (drawn.isNotEmpty) {
      // For the frame statistics ([ScreenAsked]).
      ScreenAsked.shown(_asked(moved, drawn, scale, mode));
    }
    target.kept = (of: this, lay: _lays.last, through: through, held: held);
  }

  /// The texels a target [kept] says it holds of a screen's frame
  /// ([GpuSurface.kept]), [left, top, right, bottom) — null where it says
  /// none: never shown on, or a frame given up on it.
  static (int, int, int, int)? heldIn(Object? kept) =>
      kept is _ShownOn ? kept.held : null;

  /// What a show onto a target holding what [kept] says does through the
  /// camera [through], [holding] the texels its view holds: the move of
  /// what the target holds — none where it holds nothing of this screen's
  /// that moves to this camera ([_movedBy]) —, the texels it draws then,
  /// [left, top, right, bottom) each, and those it holds after. [holding]
  /// alone, unless the target holds this screen's frame through this
  /// camera or its own panned; then what it does not hold once moved
  /// ([_outside]) — what a pan uncovers, and what a show through another
  /// camera left of it — and those that read a tile made again since: all
  /// of it held then, and nothing drawn where none of these is.
  ({
    (int, int)? moved,
    List<(int, int, int, int)> drawn,
    (int, int, int, int) held,
  })
  _toShow(Object? kept, _Through through, (int, int, int, int) holding) {
    final (columns, rows) = through.size;
    final (fromX, _, toX, _) = holding;
    final whole = (
      moved: null,
      drawn: [if (fromX < toX) holding],
      held: holding,
    );
    if (kept is! _ShownOn || !identical(kept.of, this)) {
      return whole;
    }
    final by = _movedBy(kept.through, through);
    final again = by == null ? null : _lays.since(kept.lay);
    if (by == null || again == null) {
      return whole;
    }
    final (dx, dy) = by;
    if (dx.abs() >= columns || dy.abs() >= rows) {
      return whole;
    }
    final changed = again.isEmpty
        ? null
        : _texelsReading(_tilesMet(again), through);
    final still = dx == 0 && dy == 0;
    final (left, top, right, bottom) = kept.held;
    final stillHeld = _within(
      (left + dx, top + dy, right + dx, bottom + dy),
      through.size,
    );
    return (
      moved: still ? null : by,
      drawn: [..._outside(stillHeld, through.size), ?changed],
      held: (0, 0, columns, rows),
    );
  }

  /// The ask of a show that moved what its target held by [moved], if at
  /// all, and drew [drawn], none empty, at the display's [scale] in [mode]
  /// ([ScreenAsked]): the box round what it drew, and how many texels its
  /// walks drew — the move's are copied, not drawn.
  static ScreenAsk _asked(
    (int, int)? moved,
    List<(int, int, int, int)> drawn,
    double scale,
    GpuSampling mode,
  ) {
    var (left, top, right, bottom) = drawn.first;
    var texels = 0;
    for (final (fromX, fromY, toX, toY) in drawn) {
      (left, top) = (fromX < left ? fromX : left, fromY < top ? fromY : top);
      (right, bottom) = (toX > right ? toX : right, toY > bottom ? toY : bottom);
      texels += (toX - fromX) * (toY - fromY);
    }
    return (
      columns: right - left,
      rows: bottom - top,
      texels: texels,
      moved: moved,
      scale: scale,
      mode: mode,
    );
  }

  /// What a frame over the world [extent] will keep: a tile for each it
  /// meets ([GpuScreen.bytes]).
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

  /// What [frame] will weigh laid afresh ([compose]) on [composite]: a
  /// tile for each the engine makes of it — of those its rows lay anything
  /// on in the world it holds, each the engine's pictures keep none for
  /// yet — by the engine's own count of the plan it lays
  /// ([GpuPlan.tilesMade]), weighed on its thread; [bytesOver] is every
  /// tile the world meets.
  ///
  /// Fails by [FrameKernelsToCome], nothing weighed, where [compose] would
  /// throw it.
  static Future<int> bytesToMake(
    StackedFrame frame,
    GpuComposite composite,
    EngineLetters letters,
  ) async {
    final tiles = await _planned(
      frame,
      composite,
      letters,
      // Weighed ahead, a frame is its cels as they are stored: no hand is
      // on it, so no row of it holds a range.
      maskOf: (_) => throw StateError('a frame weighed ahead holds no range'),
      holds: null,
      run: (pool, plan, world) => plan.tilesMade(pool, _edgesOf(world)),
    );
    return tiles * gpuTileBytes;
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

/// The camera a frame is shown through, as the engine is handed it
/// ([GpuScreen.show]): a texel to the canvas's pixel, the mode it is read
/// in, and the target's texels, columns by rows — and [at], the texel the
/// view's corner stands on less the pan's whole device pixels
/// ([_throughOf]).
typedef _Through = ({
  List<double> inverse,
  GpuSampling mode,
  (int, int) size,
  (int, int) at,
});

/// What a target keeps of a screen's frame ([GpuSurface.kept]): whose, as of
/// which lay of its ([_Lays.last]), through which camera, and over which of
/// its texels, [left, top, right, bottom) — what a show through another
/// camera drew ([EngineStackScreen.show]'s `holding`), or all of them.
typedef _ShownOn = ({
  EngineStackScreen of,
  int lay,
  _Through through,
  (int, int, int, int) held,
});

/// The steps of a pixel the engine reads a camera's entries in: Q.20, each
/// rounded to the nearest, halves away from zero
/// (rust/src/kernels/shared/resample.rs, `ResampleMap::new`) — 2^20.
const double _cameraSteps = 1048576;

/// [value] on the engine's grid of a camera's entries ([_cameraSteps]):
/// what the engine reads it as.
double _onTheGrid(double value) =>
    (value * _cameraSteps).roundToDouble() / _cameraSteps;

/// The camera through [viewport] at [devicePixelRatio] onto a target of
/// [size] texels, the view's corner on its texel [corner]
/// ([EngineStackScreen.show]).
///
/// 🚨ON THE ENGINE'S GRID, ITS PAN WHOLE TEXELS OF IT: every entry is one
/// the engine reads as it is ([_onTheGrid]), and what moves with the pan
/// moves by whole texels of the turn and the scale on that grid — [at],
/// the corner less the pan's whole device pixels (the snapped pan less its
/// phase, [renderSnappedViewport]), times them. So a camera panned by
/// whole device pixels reads at each texel exactly what its own did that
/// many texels back — the engine works a camera in integers, a texel's
/// middle linear in its column and row (resample.wgsl,
/// `resample_locate`) — and a frame moved by them ([GpuComposite.move]) is
/// the one drawn whole through it, byte for byte. ↩️Till 2026-11-23 the
/// engine rounded the camera's move apart from its turn and scale: a
/// camera panned read parts of a texel in millions off its own moved, and
/// no frame could be moved. ⚠️Where the canvas is read moves off where the
/// engine read the view's own camera till then by a part in two million of
/// a canvas pixel for each texel [at] lies from the target's first, at
/// most — 0.005 of one ten thousand texels off.
_Through _throughOf(
  CanvasViewport viewport,
  double devicePixelRatio,
  (int, int) corner,
  (int, int) size,
) {
  final snapped = renderSnappedViewport(viewport, devicePixelRatio);
  final camera = viewportInverseTransformMatrix(snapped).storage;
  // A texel is a device pixel, the camera's unit a logical one.
  final per = 1 / devicePixelRatio;
  final scale = displayScaleOf(viewport.zoom, devicePixelRatio);
  final phase = samplingPhaseFor(scale);
  final pannedX = (snapped.panX * devicePixelRatio - phase).round();
  final pannedY = (snapped.panY * devicePixelRatio - phase).round();
  // The view's pixel a texel is: the texel less the corner.
  final (cornerX, cornerY) = corner;
  final (atX, atY) = (cornerX + pannedX, cornerY + pannedY);
  final (a, b) = (camera[0] * per, camera[4] * per);
  final (c, d) = (camera[1] * per, camera[5] * per);
  // The camera's own move: what is left of it with the pan's whole
  // texels taken off.
  final ownX = _onTheGrid(camera[12] + a * pannedX + b * pannedY);
  final ownY = _onTheGrid(camera[13] + c * pannedX + d * pannedY);
  final [gridA, gridB, gridC, gridD] = [a, b, c, d].map(_onTheGrid).toList();
  return (
    inverse: [
      gridA,
      gridB,
      ownX - gridA * atX - gridB * atY,
      gridC,
      gridD,
      ownY - gridC * atX - gridD * atY,
    ],
    mode: gpuSamplingOf(filterQualityForDisplayScale(scale)),
    size: size,
    at: (atX, atY),
  );
}

/// By how many texels the camera [b] is [a] moved, where it is: every
/// texel of [b] reads what the one of [a] that many back did
/// ([_throughOf]) — (0, 0) where they are one camera, and null where some
/// texel of [b] reads what none of [a] does, a part of a texel off it or
/// turned or scaled. The mode is not asked — it is the scale's, which the
/// inverse holds.
(int, int)? _movedBy(_Through a, _Through b) {
  final [aa, ab, ac, ad, ae, af] = a.inverse;
  final [ba, bb, bc, bd, be, bf] = b.inverse;
  if (a.size != b.size || aa != ba || ab != bb || ad != bd || ae != be) {
    return null;
  }
  final (fromX, fromY) = a.at;
  final (toX, toY) = b.at;
  // Each camera's own move, exactly: every entry is on the grid.
  final ownAlike =
      ac + aa * fromX + ab * fromY == bc + ba * toX + bb * toY &&
      af + ad * fromX + ae * fromY == bf + bd * toX + be * toY;
  return ownAlike ? (toX - fromX, toY - fromY) : null;
}

/// [rect], [left, top, right, bottom), within a target of [size]: none of
/// it where they do not meet — an empty one at the target's corner.
(int, int, int, int) _within((int, int, int, int) rect, (int, int) size) {
  final (left, top, right, bottom) = rect;
  final (columns, rows) = size;
  final (fromX, fromY) = (left.clamp(0, columns), top.clamp(0, rows));
  final (toX, toY) = (right.clamp(fromX, columns), bottom.clamp(fromY, rows));
  return toX == fromX || toY == fromY ? (0, 0, 0, 0) : (fromX, fromY, toX, toY);
}

/// The texels of a target of [size] that hold nothing outside [held] —
/// within it ([_within]): a band of columns either side of it and one of
/// rows above and under it, less the columns' — [left, top, right, bottom)
/// each, none along a side it reaches; all of the target where [held] is
/// empty. A move of a target holding all of it holds what the texels moved
/// land on, so what it uncovers is this of that.
List<(int, int, int, int)> _outside(
  (int, int, int, int) held,
  (int, int) size,
) {
  final (columns, rows) = size;
  final (left, top, right, bottom) = held;
  if (left == right || top == bottom) {
    return [(0, 0, columns, rows)];
  }
  return [
    if (left > 0) (0, 0, left, rows),
    if (right < columns) (right, 0, columns, rows),
    if (top > 0) (left, 0, right, top),
    if (bottom < rows) (left, bottom, right, rows),
  ];
}

/// How many lays a canvas's screen holds apart ([_Lays]): what a target
/// falls behind by — two frames' lays, two textures being drawn on in
/// turn (`_AlternatedTextures`, every platform's since Android's window
/// went, 2026-11-23). One behind by more is
/// drawn whole ([_Lays.since]) — the bound costs a whole frame, never a
/// wrong one.
///
/// 🔬The Galaxy Tab's slowest frame of a pen at work laid 41–54 strokes'
/// steps, the frames between 5–14 (build 1099, 유저's photographs
/// 2026-11-23, card the-galaxy-tab-canvas-went-slow-on-build-1095): two
/// such frames are some 110 lays. ↩️Held eight deep (2026-11-22, a few
/// lays a frame on this PC), its window fell behind by more at every
/// slow frame of a stroke there: it was drawn whole — 3584×2560 texels,
/// 43 ms of that tablet's GPU —, the steps piled up meanwhile, and the
/// next was drawn whole again.
const int screenLaysKeptApart = 256;

/// WHERE A KEPT FRAME WAS MADE AGAIN, LAY BY LAY: each lay numbered from
/// one, the newest [_kept] of them held with the world pixels each made
/// again — null, all of them.
final class _Lays {
  static const int _kept = screenLaysKeptApart;

  final List<({int lay, Rect? where})> _newest = [];

  /// The lay made last, by number; none yet, 0.
  int get last => _last;
  int _last = 0;

  /// A lay made the kept frame again over the world pixels [where] — all
  /// of it where null.
  void made(Rect? where) {
    _last += 1;
    _newest.add((lay: _last, where: where));
    if (_newest.length > _kept) {
      _newest.removeAt(0);
    }
  }

  /// The world pixels made again by the lays after [lay]: empty where
  /// there was none, and null where it is not told — one of them made all
  /// of it again, or is held apart no more.
  Rect? since(int lay) {
    if (_newest.first.lay > lay + 1) {
      return null;
    }
    Rect? again;
    for (final made in _newest) {
      if (made.lay <= lay) {
        continue;
      }
      final where = made.where;
      if (where == null) {
        return null;
      }
      // A lay over no pixel made nothing again (`Screen::compose`).
      if (!where.isEmpty) {
        again = again?.expandToInclude(where) ?? where;
      }
    }
    return again ?? Rect.zero;
  }
}

/// The tiles of a kept frame the world pixels [where] meet, whole: what a
/// lay over them makes again (`Screen::compose`).
Rect _tilesMet(Rect where) {
  final side = gpuTileSide.toDouble();
  double down(double edge) => (edge / side).floorToDouble() * side;
  double up(double edge) => (edge / side).ceilToDouble() * side;
  return Rect.fromLTRB(
    down(where.left),
    down(where.top),
    up(where.right),
    up(where.bottom),
  );
}

/// The texels of a target shown [through] a camera whose read reaches the
/// canvas pixels [where] — [left, top, right, bottom), null where none
/// does: those a texel's middle lands within the mode's reach of
/// ([GpuSampling.reach]), found by the camera turned about — a canvas
/// pixel to the texel — as the box round where its corners land. A
/// camera that turns about to none is one the engine refuses
/// (`Screen::show`): its frame is given up, and no target is left
/// holding one through it to come here.
///
/// A texel is taken where any of it lies in that box, its middle or not:
/// the half a texel that spares is what the engine's own arithmetic may
/// differ from this by — it reads the camera rounded to Q.20 and lands a
/// middle on Q.16, a part of a texel in tens of thousands.
(int, int, int, int)? _texelsReading(Rect where, _Through through) {
  final (columns, rows) = through.size;
  final [a, b, c, d, e, f] = through.inverse;
  final turned = a * e - b * d;
  final read = where.inflate(through.mode.reach.toDouble());
  double acrossOf(double x, double y) =>
      (e * (x - c) - b * (y - f)) / turned;
  double downOf(double x, double y) => (a * (y - f) - d * (x - c)) / turned;
  final corners = [
    (read.left, read.top),
    (read.right, read.top),
    (read.left, read.bottom),
    (read.right, read.bottom),
  ];
  final across = [for (final (x, y) in corners) acrossOf(x, y)]..sort();
  final down = [for (final (x, y) in corners) downOf(x, y)]..sort();
  final left = across.first.floor().clamp(0, columns).toInt();
  final top = down.first.floor().clamp(0, rows).toInt();
  final right = across.last.ceil().clamp(0, columns).toInt();
  final bottom = down.last.ceil().clamp(0, rows).toInt();
  return left >= right || top >= bottom ? null : (left, top, right, bottom);
}

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
/// those are the pen's frame's ([EngineChainHolds.ofThePensFrame]). Those
/// are weighed — laid whole for the canvas [standing] stands for, if any
/// ([EngineChainHolds.settleOnce]) — once [run]'s work is done: when
/// [doneOf] its answer ends, where the engine runs it with no one waiting
/// ([GpuScreen.compose]) — as it is answered, with none.
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
  Future<void>? Function(T ran)? doneOf,
  Object? standing,
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
    final plan = GpuPlan(composite.engine);
    Future<void>? done;
    try {
      planCompositeTree(
        plan,
        mapCompositeLeaves<_PaintRow, EngineRow>(
          pass._rootNodes,
          (row) => pass._engineRowOf(row, maskOf, letters),
          told: holds == null ? null : (node, to) => origins[to] = node,
        ),
        hold: hold,
        paper: paper,
        letters: letters,
        holding: _holding(holds, composite.engine, pass, origins, paper),
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
      final ran = run(ledger.pool, plan, world);
      done = doneOf?.call(ran);
      return ran;
    } finally {
      plan.free();
      holds?.settleOnce(done, standing: standing);
    }
  });
}

/// The holding of the chains [pass] plans on [engine] ([ChainHolding]): a
/// node's, on [paper], under what the node it came from shows ([origins])
/// — none for one that shows a row drawn live
/// ([_FrameReading._pictureOf]).
///
/// Five, the engine among them, and not bundled to fit: [holds] are the
/// app's and outlive an engine, keeping a hold for the engine they are
/// asked of ([EngineChainHolds.heldOf]), and [engine] is the composite's
/// this frame is planned on — a hold is its engine's for its life, so
/// the two are named apart where a frame is planned and nowhere held
/// together (🗣️관제 2026-11-14 08:14: the reason stands here, the wide
/// signatures' ceiling where it stood).
ChainHolding? _holding(
  EngineChainHolds? holds,
  GpuEngine engine,
  _FrameReading pass,
  Map<CompositeNode<EngineRow>, CompositeNode<_PaintRow>> origins,
  Rect paper,
) => switch (holds) {
  null => null,
  final holds => (
    held: holds.heldOf(engine),
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
  /// on it, marked under the mask [maskOf] gives its cover ([_markOn]); a
  /// name tag its plate in [letters], laid as a row's picture is.
  EngineRow _engineRowOf(
    _PaintRow row,
    GpuMask Function(FloodFillRegion cover) maskOf,
    EngineLetters letters,
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
    // Normal, whatever the row's blend (🗣️F-387-Q5); its opacity and chain
    // its folder's ([nameTagRows]).
    _PaintNameTag(:final tag) => switch (letters.seNameTagPlate(
      tag,
      _painter.canvasSize,
    )) {
      final plate => EngineTiles(
        lineage: plate,
        surface: plate,
        placement: tag.placement,
      ),
    },
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
