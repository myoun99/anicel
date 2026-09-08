part of '../brush_canvas_panel.dart';

/// The SELECTION SEAT — what the panel does with the selection layer:
/// recording its changes into history, answering the idle region, a
/// lift, clipping a stroke to it, and the tiles a committed region still
/// owes — as its own object.
///
/// 🚨A collaborator carved out of `_BrushCanvasPanelState` (the audit's SRP
/// cut, 2026-09-02). Measured before cutting: three State members shared.
/// It reaches the State through `_state`.
class _CanvasPanelSelection {
  _CanvasPanelSelection(this._state);

  final _BrushCanvasPanelState _state;

  /// One undoable selection step (R11-⑧) — the layer's marquee commits and
  /// the channel's layer-less Ctrl+D both land here, so a selection change
  /// is recorded the same way whatever tool is armed. Null while this
  /// panel has no history host (focused tests apply directly).
  void Function(CanvasSelectionRegion? before, CanvasSelectionRegion? after)?
  get recordSelectionChange {
    final history = _state.widget.historyManager;
    final commands = _state.widget.selectionCommands;
    if (history == null || commands == null) {
      return null;
    }
    return (before, after) => history.execute(
      SelectionShapeHistoryCommand(
        channel: commands,
        before: before,
        after: after,
      ),
    );
  }

  void bindSelectionHistoryRecorder() {
    _state.widget.selectionCommands?.regionHistoryRecorder =
        recordSelectionChange;
  }

  void handleSelectionChannelChanged() {
    if (!_state.mounted) {
      return;
    }
    // The channel pings on EVERY selection mutation, including each step
    // of a marquee/move drag. Those all happen with a selection tool
    // armed, where the mounted layer draws and this panel has nothing to
    // redraw — so the guard keeps the notify structure (R27 #7/#20) out
    // of the drag loop and only rebuilds when the ants this panel owns
    // actually change.
    final next = idleSelectionRegion;
    if (next == _state._paintedIdleRegion) {
      return;
    }
    _state._rebuild(_state._syncIdleAnts);
  }

  /// The region to paint when no selection layer is mounted (null while
  /// one is — it draws its own, session state included).
  CanvasSelectionRegion? get idleSelectionRegion {
    if (canvasToolSelects(_state.widget.brushToolState.tool)) {
      return null;
    }
    return _state.widget.selectionCommands?.region;
  }

  int _liftTokenSeq = 0;

  /// WHICH tiles the committed surface holds under this canvas rect have
  /// no decoded image yet — the tiles the selection layer keeps its float
  /// over until they arrive. Empty means the base can paint the lot.
  ///
  /// A coordinate with NO tile counts as ready: the surface has nothing to
  /// draw there, so waiting on it would wait forever.
  ///
  /// ⚠️ The set, not a bool. The base becomes paintable 32 tiles a paint,
  /// so a single yes/no made the float cover the whole landing until the
  /// last tile arrived — double-compositing every partial-alpha pixel
  /// under it, and, when the float could not paint, showing the user the
  /// convergence itself, tile by tile.
  Set<TileCoord> committedRegionPendingTiles(DirtyRegion landing) {
    final coordinator = _state.widget._editableCoordinator;
    if (coordinator == null) {
      return const <TileCoord>{};
    }
    final surface = coordinator.currentSurfaceOf(coordinator.activeFrameKey);
    final size = surface.tileSize;
    final cache = BitmapTileImageCache.instance;
    // ⚠️ tileAt, NOT `surface.tiles[...]`. `tiles` is
    // `Map.unmodifiable(_tiles)` — a getter that COPIES the cel's whole
    // tile map on every call — so indexing it inside this walk made one
    // predicate O(coords × tiles) entry copies instead of O(coords) hash
    // lookups. Measured on the real surface at the 8192² the canvas dialog
    // allows (1024 tiles): 82.7 ms per walk against 28 µs, and the walk
    // that finds everything ready is by definition the complete one, so
    // that stall landed on the release frame of every confirm.
    var pending = const <TileCoord>{};
    for (final coord in tileCoordsIn(landing.tileRange(tileSize: size))) {
      final tile = surface.tileAt(coord);
      // `displayImageFor`, not `imageFor`: the question this predicate
      // asks is "can the base paint here", and a stand-in composed from
      // the very picture the hold would show is an answer to it. Reading
      // truth only would keep the float clipped over coordinates the
      // canvas is already drawing correctly — the same coordinate
      // source-over'd twice, which is how partial-alpha edges came out
      // darker on a wide landing.
      if (tile != null && cache.displayImageFor(tile) == null) {
        if (identical(pending, const <TileCoord>{})) {
          pending = <TileCoord>{};
        }
        pending.add(coord);
      }
    }
    return pending;
  }

  /// shape covers no pixels.
  ///
  /// [wholeTiles] names the coordinates the lift took ENTIRELY — the ones
  /// left with nothing behind — paired with the tiles that held them
  /// before. The float that is about to be built from this stamp holds,
  /// at those coordinates, exactly those pixels, so it can borrow them
  /// and paint on its first frame instead of waiting a decode round with
  /// four tiles' worth of fallback. Coordinates the lift only partly took
  /// are deliberately absent: see [BitmapTileImageCache.seedScope].
  ({int liftToken, BrushDab stampDab, Map<TileCoord, BitmapTile> wholeTiles})?
  handleSelectionLift(CanvasSelectionRegion region) {
    final coordinator = _state.widget._editableCoordinator;
    if (coordinator == null) {
      return null;
    }
    final preLift = coordinator.currentSurfaceOf(coordinator.activeFrameKey);
    final lift = buildSelectionLiftDabs(
      region: region,
      surface: preLift,
      liftId: '${DateTime.now().microsecondsSinceEpoch}',
      options:
          _state.widget.selectionMaskOptions?.value ??
          SelectionMaskOptions.none,
    );
    if (lift == null) {
      return null;
    }
    final outcome = coordinator.commitSourceStroke(
      sourceDabs: [lift.eraseDab],
      cacheInvalidationSink: _state.widget.cacheInvalidationSink,
    );
    if (outcome == null) {
      return null;
    }
    final token = ++_liftTokenSeq;
    // ⚠️READ THE POST-ERASE SURFACE FIRST, because the anchor is measured
    // against it: an [UndoSurfaceSnapshot] owes only the tiles the live
    // surface no longer holds, and here that is exactly the set the erase
    // rebuilt. Everything else the anchor names is a tile the cel still
    // has, and holding it costs nothing.
    final after = coordinator.currentSurfaceOf(coordinator.activeFrameKey);
    final held = UndoSurfaceSnapshot(
      key: coordinator.activeFrameKey,
      snapshot: preLift,
      sharedWith: after,
    );
    // ⛔THE TOOL KEEPS THE LIFETIME, THE STORE KEEPS THE DISCIPLINE — one
    // object, held by both. Without this the pixels are outside every
    // budget for as long as the box stays open; see the store's own
    // paragraph on [BrushFrameStore.holdLiftedPixels].
    coordinator.frameStore.holdLiftedPixels(token, held);
    _state._lift._liftAnchors[token] = (
      pixels: held,
      // The selection as the session finds it — captured at the same instant
      // as the pixels, so undo can put both back exactly as they were.
      region: _state.widget.selectionCommands?.region,
    );
    _state._rebuild(() {});
    final whole = <TileCoord, BitmapTile>{};
    // ⚠️ The LIFT'S tile range, not the whole cel. This walked
    // `preLift.tiles.entries` — one whole-map copy, then a full 256 KB
    // read per emptied tile — over every tile the cel had, including all
    // the ones the erase could not possibly have touched. A coordinate
    // outside the region's bounds cannot have been emptied by it, so the
    // answer is the same and the work is the lift's size instead of the
    // drawing's.
    final size = preLift.tileSize;
    // Coverage, not the tight fold: the sweep has to reach every tile the
    // erase could have touched, and only an ADDING step can widen that.
    final bounds = region.coverageBounds;
    final range = tileRangeCovering(
      left: bounds.left,
      top: bounds.top,
      right: bounds.right,
      bottom: bounds.bottom,
      tileSize: size,
    );
    for (final coord in tileCoordsIn(range)) {
      final before = preLift.tileAt(coord);
      if (before == null) {
        continue;
      }
      // Untouched by the erase => structural sharing hands back the SAME
      // object, and a coordinate the lift did not take cannot be one it
      // took whole. Free, and it skips the byte scan entirely.
      final left = after.tileAt(coord);
      if (identical(left, before)) {
        continue;
      }
      // Emptied by the erase => the lift took this coordinate whole. The
      // erase does not drop emptied tiles, so the test is the alpha, not
      // the tile's absence. `isFullyTransparent` walks the tile's own
      // view; `tile.pixels` would be a 256 KB defensive COPY per call.
      if (left == null || left.isFullyTransparent) {
        whole[coord] = before;
      }
    }
    // The base must stop answering for what the lift took. Its bucket
    // still holds the pre-erase tiles at these coordinates, so without
    // this it redraws the artwork in its ORIGINAL place while the float
    // draws it in the new one — two copies at the start, and on the
    // confirm frame a picture that is in the old place and absent from
    // the new one.
    //
    // Only the coordinates the lift took WHOLE: there the truth is
    // emptiness, so drawing nothing is right. A partially lifted
    // coordinate keeps its entry, because its surviving pixels are still
    // better than none.
    //
    // ⚠️ This was written once before and reverted, on the word of a test
    // that counted INK rather than looking at where it was. The base's
    // displaced copy is ink too, so removing it read as losing coverage.
    // The oracle asks about position now, and says the opposite.
    final activeKey = coordinator.activeFrameKey;
    BitmapTileImageCache.instance.invalidateCoords((
      activeKey.layerId,
      activeKey.frameId,
    ), whole.keys);
    return (liftToken: token, stampDab: lift.stampDab, wholeTiles: whole);
  }

  /// R26 #18 ("선택하고 그리면 선택 내부만 그려진다"): a stroke that lands
  /// with a live selection is CLIPPED to it before it reaches the commit.
  ///
  /// The clip runs on the stroke's own straight-alpha buffer, where alpha
  /// 0 is every commit kernel's "leave the destination alone" input — so
  /// one pass covers brush, eraser, fill and every brush blend mode with
  /// no per-mode branches. Null return = the whole stroke fell outside
  /// the selection and there is nothing to commit.
  BrushStrokeCommitData? clipStrokeToSelection(BrushStrokeCommitData data) {
    final region = _state.widget.selectionCommands?.region;
    if (region == null) {
      return data;
    }
    if (data.promotedTiles != null) {
      // The stroke was pre-blended THROUGH the selection mask (R28): the
      // promoted tiles are already clipped, and re-deriving them here
      // would throw away the finished pixels to rasterize the dabs again.
      // An empty list means the whole stroke fell outside the selection.
      return data.promotedTiles!.isEmpty ? null : data;
    }
    var pixels = data.strokePixels;
    var bounds = data.strokeBounds;
    if (pixels == null || bounds == null) {
      // No live raster (programmatic strokes, a redo replaying dabs):
      // rasterize the coverage first so the clip has bytes to work on.
      final rasterized = rasterizeStrokeForClipping(
        dabs: data.sourceDabs,
        canvasSize: _state.widget.canvasSize,
        tileSize: _state.widget._editableCoordinator == null
            ? BitmapSurface(canvasSize: _state.widget.canvasSize).tileSize
            : _state.widget._editableCoordinator!
                  .currentSurfaceOf(
                    _state.widget._editableCoordinator!.activeFrameKey,
                  )
                  .tileSize,
      );
      if (rasterized == null) {
        return null;
      }
      pixels = rasterized.pixels;
      bounds = rasterized.bounds;
    }
    final clipped = clipStrokePixelsToSelection(
      pixels: pixels,
      bounds: bounds,
      region: region,
    );
    if (clipped == null) {
      return null;
    }
    return BrushStrokeCommitData(
      sourceDabs: data.sourceDabs,
      strokePixels: clipped.pixels,
      strokeBounds: clipped.bounds,
      blendMode: data.blendMode,
      strokeOpacity: data.strokeOpacity,
    );
  }
}
