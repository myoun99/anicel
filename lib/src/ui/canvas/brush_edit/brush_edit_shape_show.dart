part of '../interactive_brush_edit_canvas_view.dart';

/// THE SHAPE WHILE IT IS DRAGGED — the shape tool's area or stroke laid a
/// share of each frame, shown when it is whole, and landed as it was shown
/// — as its own object.
///
/// 🗣️유저 답 I-69-Q4ⓒ (2026-10-08): 「윤곽선은 손을 따라오고, 실제 결과는
/// 따라 그린다」 — the outline follows the hand every frame and stays light;
/// under it the actual result is laid at the pace the device can manage,
/// once more at the hand's newest shape each time the last is done, and
/// what was showing when the hand lets go is what stays.
///
/// 🚨★★★WHOLE OR NOT AT ALL. A shape half laid is a wrong picture, and the
/// answer allows only a LATE one, so a shape is laid OFF SCREEN and put up
/// in one call when it is whole; until then the last whole one stays up.
/// An area is laid as the fill's result tiles — each piece by the fill's
/// own promotion ([promoteFillDabs]), on the cel with the pieces before it
/// — and put up as a fill's result is ([_BrushEditFill.showResult]). A
/// stroke of the brush is THE stroke, not one like it: opened, started,
/// advanced and rasterized by the stroke's own code ([_BrushEditStroke]),
/// its tiles pictured off screen ([ActiveStrokeOverlayModel.stageRegion])
/// and put up together ([ActiveStrokeOverlayModel.showStaged]).
///
/// 🚨★★★WHAT LANDS IS WHAT WAS SHOWN. Let go on the shape on screen and it
/// lands as it is — an area through the landing a fill takes
/// ([_BrushEditFill.landResult]), a stroke through the pen-up's own
/// ([_BrushEditPress.landActiveStroke]) — nothing laid twice, not a byte on
/// screen changed. A shape the hand moved on from is finished first, on the
/// spot.
///
/// ⚠️A frame lays for [shapeShowFrameShare] at most, and always at least
/// one step: the debug build is the bar for lag (유저 2026-09-26 「5배 느린
/// 빌드가 기준」), and one shape laid whole costs more than a frame — a
/// filled 2010×1510 ellipse is built and laid in 23–33 ms on the desktop's
/// VM, a 100px square of a 4px brush in 45–110 ms in the debug app (I-69-Q4)
/// — which in one go would take the outline the hand drags down with it.
class _BrushEditShapeShow implements ShapeShow {
  _BrushEditShapeShow(this._state);

  final _InteractiveBrushEditCanvasViewState _state;

  /// The dabs one step blends, and the tiles one step pictures — a step
  /// stays well inside a frame's share (an advance is a stretch of
  /// [_waypointSpan] at most). 🔬Measured on the desktop's VM (2026-10-09,
  /// a 2340×1654 cel on 128px tiles): a tile pictured 0.5–0.9ms, a dab
  /// blended 25µs at 4px and 85µs at 200px.
  static const int _dabsPerStep = 8;
  static const int _tilesPerStep = 1;

  // ── an area ──────────────────────────────────────────────────────────

  /// The area the hand asks for now.
  ShapeArea? _wanted;

  /// The area being laid, off screen.
  _ShapeLaying? _laying;

  /// The area on screen, whole.
  _ShapeLaying? _shown;

  // ── a stroke of the brush ────────────────────────────────────────────

  /// Whether the tool's stroke is open for this show
  /// ([_BrushEditStroke.openToolStroke]).
  bool _strokeOpen = false;

  /// The path the hand asks for now.
  _ToolPath? _wantedPath;

  /// The path being laid, off screen.
  _StrokeLaying? _strokeLaying;

  /// The path whose stroke is on screen AND whole in the live rasterizer —
  /// what a release on it lands. Null once a newer path is being laid: the
  /// rasterizer holds that one now, whatever the screen still shows.
  _ToolPath? _rasterHolds;

  bool _frameAsked = false;

  /// A cel this view can draw on: one there is, on a row that takes marks.
  bool get _canLay => _state.widget.editable && _state.widget.rowAcceptsStrokes;

  @override
  void show(ShapeArea area) {
    if (!_canLay) {
      return;
    }
    // The overlay shows one shape: an area asked for puts away a stroke.
    _dropTheStroke();
    _wanted = area;
    // A shape being laid has its frame asked already, and the same shape
    // asked again asks for nothing — not a frame: the stamp's ghost is
    // asked again on every rebuild of its panel.
    if (_laying == null && _shown?.area.shape != area.shape) {
      _laying = _begin(area);
      _askFrame();
    }
  }

  @override
  bool land(ShapeArea area) {
    _wanted = null;
    if (!_canLay) {
      drop();
      return false;
    }
    _dropTheStroke();
    final shown = _shown;
    final laying = _laying;
    final landing = shown != null && shown.area.shape == area.shape
        ? shown
        : laying != null && laying.area.shape == area.shape
        ? laying
        : _begin(area);
    while (landing.layNext()) {}
    _laying = null;
    _shown = null;
    if (landing.tiles.isEmpty) {
      _state._overlay.resetOverlay();
      return false;
    }
    final tiles = landing.tiles.values.toList();
    if (!identical(landing, shown)) {
      // The overlay's pictures stand for the tiles it shows, and the
      // landing hands them over: the one landing has to be what it shows.
      _state._fill.showResult(
        base: landing.base,
        blend: area.blend,
        tiles: tiles,
      );
    }
    _state._fill.landResult(
      tiles: tiles,
      dabs: landing.dabs,
      blend: area.blend,
      base: landing.base,
    );
    return true;
  }

  @override
  void showStroke(List<CanvasPoint> path, {double pressure = 1}) {
    if (!_canLay || path.length < 2) {
      return;
    }
    // The overlay shows one shape: a stroke asked for puts away an area.
    _dropTheArea();
    final wanted = (points: path, pressure: pressure);
    _wantedPath = wanted;
    if (_strokeLaying == null && !_samePath(_rasterHolds, wanted)) {
      _strokeLaying = _StrokeLaying(wanted);
    }
    _askFrame();
  }

  @override
  bool landStroke(List<CanvasPoint> path, {double pressure = 1}) {
    _dropTheArea();
    if (!_strokeOpen || !_canLay || path.length < 2) {
      // Nothing laid ahead: the path is laid and landed in one go — the
      // road that also asks for a cel where there is none.
      _dropTheStroke();
      return _state._pathStroke.strokeAlong(path, pressure: pressure);
    }
    final wanted = (points: path, pressure: pressure);
    if (!_samePath(_rasterHolds, wanted)) {
      final laying = _strokeLaying;
      final landing = laying != null && _samePath(laying.path, wanted)
          ? laying
          : _StrokeLaying(wanted);
      while (_stepStroke(landing)) {}
      _putUp(landing);
    }
    _forgetTheStroke();
    _state._stroke.flyToolStroke();
    return _state._press.landActiveStroke();
  }

  @override
  void drop() {
    _dropTheArea();
    _dropTheStroke();
  }

  /// The stroke's own reading ([_BrushEditPressure.pressureOf]) — device,
  /// driver stream and curve alike. ⚠️A press reads before a Pencil has
  /// measured, so on an iPad it is the force the contact pressed with:
  /// the stand-in a stroke waits past has nothing after it to wait for.
  @override
  double pressureOf(PointerDownEvent press) =>
      _state._pressure.pressureOf(press).pressure;

  void _dropTheArea() {
    _wanted = null;
    _laying = null;
    if (_shown != null) {
      _shown = null;
      _state._overlay.resetOverlay();
    }
  }

  /// The stroke this show opened goes, with nothing landed and nothing said
  /// — the host never heard of it ([_BrushEditStroke.openToolStroke]).
  void _dropTheStroke() {
    final open = _strokeOpen;
    _forgetTheStroke();
    if (open) {
      _state._stroke.clearStrokeInputState();
      _state._overlay.resetOverlay();
      // Native tiles back to the engine (R21).
      _state._liveRasterizer?.clear();
    }
  }

  void _forgetTheStroke() {
    _strokeOpen = false;
    _wantedPath = null;
    _strokeLaying = null;
    _rasterHolds = null;
  }

  _ShapeLaying _begin(ShapeArea area) => _ShapeLaying(
    area,
    base: _state.widget.celNow(),
    layerId: _state.widget.layerId,
    frameId: _state.widget.frameId,
  );

  void _askFrame() {
    if (_frameAsked) {
      return;
    }
    _frameAsked = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frameAsked = false;
      if (_state.mounted) {
        _layAFrame();
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _layAFrame() {
    final clock = Stopwatch()..start();
    _layAreaFrame(clock);
    _layStrokeFrame(clock);
  }

  void _layAreaFrame(Stopwatch clock) {
    final laying = _laying;
    if (laying == null) {
      return;
    }
    while (laying.layNext() && clock.elapsed < shapeShowFrameShare) {}
    if (!laying.done) {
      _askFrame();
      return;
    }
    _laying = null;
    _shown = laying;
    _state._fill.showResult(
      base: laying.base,
      blend: laying.area.blend,
      tiles: laying.tiles.values.toList(),
    );
    // 「앞의 것을 다 그리면 지금 손 위치로 한 번 더」.
    final wanted = _wanted;
    if (wanted != null && wanted.shape != laying.area.shape) {
      _laying = _begin(wanted);
      _askFrame();
    }
  }

  void _layStrokeFrame(Stopwatch clock) {
    final laying = _strokeLaying;
    if (laying == null) {
      return;
    }
    if (!_canLay) {
      _dropTheStroke();
      return;
    }
    while (_stepStroke(laying)) {
      if (clock.elapsed >= shapeShowFrameShare) {
        _askFrame();
        return;
      }
    }
    _strokeLaying = null;
    _putUp(laying);
    // 「앞의 것을 다 그리면 지금 손 위치로 한 번 더」.
    final wanted = _wantedPath;
    if (wanted != null && !_samePath(laying.path, wanted)) {
      _strokeLaying = _StrokeLaying(wanted);
      _askFrame();
    }
  }

  /// Takes [laying] one step on, and answers whether there is more to do —
  /// false once it is whole. A step is one of: the stroke started at the
  /// path's first point, a share of the dabs it made blended into the live
  /// rasterizer, the stroke taken to its next waypoint, or a share of its
  /// tiles pictured off screen.
  bool _stepStroke(_StrokeLaying laying) {
    final stroke = _state._stroke;
    final waypoints = laying.waypoints;
    if (laying.reached == 0) {
      if (!_strokeOpen) {
        stroke.openToolStroke();
        _strokeOpen = true;
      }
      // One path, one roll: the same shape laid again rolls the same
      // scatter and jitter — and lands as the shape laid in one go does.
      stroke.startToolStrokeAt(
        waypoints.first,
        dice: Object.hashAll(laying.path.points),
        pressure: laying.path.pressure,
      );
      _state._overlay._overlayModel.dropStaged();
      _rasterHolds = null;
      laying.reached = 1;
      return true;
    }
    final rasterizer = _state._liveRasterizer!;
    if (laying.fed.length < laying.made.length) {
      final from = laying.fed.length;
      laying.fed.addAll(
        laying.made.getRange(
          from,
          math.min(laying.made.length, from + _dabsPerStep),
        ),
      );
      final region = rasterizer.blendFrom(laying.fed, from: from);
      if (region != null) {
        laying.touched = laying.touched?.union(region) ?? region;
      }
      return true;
    }
    if (laying.reached < waypoints.length) {
      stroke.advanceStrokeTo(waypoints[laying.reached]);
      laying.reached += 1;
      // The stroke queued its dabs for the per-frame flush, which puts
      // tiles up as it blends them; this show is the flush for its stroke,
      // and puts them up whole.
      laying.made.addAll(_state._pendingOverlayDabs);
      _state._pendingOverlayDabs.clear();
      return true;
    }
    final overlay = _state._overlay._overlayModel;
    final coords = laying.coords ??= [
      ...?laying.touched?.toTileCoords(tileSize: overlay.tileSize),
    ];
    if (laying.pictured < coords.length) {
      final end = math.min(coords.length, laying.pictured + _tilesPerStep);
      if (!overlay.stageRegion(
        source: rasterizer,
        coords: coords.sublist(laying.pictured, end),
      )) {
        // This overlay pictures as it shows: [_putUp] does it all at once.
        laying.staged = false;
        laying.pictured = coords.length;
        return false;
      }
      laying.pictured = end;
      return laying.pictured < coords.length;
    }
    return false;
  }

  /// [laying], whole, in place of the stroke on screen.
  void _putUp(_StrokeLaying laying) {
    final overlay = _state._overlay._overlayModel..showStaged(laying.fed);
    final touched = laying.touched;
    if (!laying.staged && touched != null) {
      overlay.updateRegion(source: _state._liveRasterizer!, region: touched);
    }
    _rasterHolds = laying.path;
  }
}

/// One area being laid: its pieces asked for one at a time, each laid —
/// as the fill's result tiles — on the cel with the pieces before it.
class _ShapeLaying {
  _ShapeLaying(
    this.area, {
    required this.base,
    required this.layerId,
    required this.frameId,
  }) : _pieces = area.pieces().iterator,
       _laidOn = base;

  final ShapeArea area;

  /// The cel as the shape found it — what its tiles were made against.
  final BitmapSurface base;
  final LayerId layerId;
  final FrameId frameId;
  final Iterator<BrushDab> _pieces;

  /// [base] with every piece laid so far: the next piece is laid on it, so
  /// two pieces sharing a tile of the cel make one tile with both.
  BitmapSurface _laidOn;

  /// The pieces laid so far, as they were laid ([BrushDab.underBlend]).
  final List<BrushDab> dabs = [];

  /// The result so far, a tile per coordinate — the last piece's word on
  /// it, which holds every piece before.
  final Map<TileCoord, PromotedStrokeTile> tiles = {};

  /// Whether every piece is laid.
  bool done = false;

  /// Lays the next piece and answers true, or answers false when every
  /// piece is laid.
  bool layNext() {
    if (done) {
      return false;
    }
    if (!_pieces.moveNext()) {
      done = true;
      return false;
    }
    final dab = _pieces.current.underBlend(area.blend);
    dabs.add(dab);
    final laid = promoteFillDabs(
      surface: _laidOn,
      dabs: [dab],
      blendMode: area.blend,
      // Cut already, by whoever made the pieces ([ShapeArea]).
      selection: null,
      layerId: layerId,
      frameId: frameId,
    );
    if (laid.isNotEmpty) {
      for (final tile in laid) {
        tiles[tile.coord] = tile;
      }
      _laidOn = _laidOn.putMaterializedTiles([
        for (final tile in laid) (coord: tile.coord, tile: tile.tile),
      ]);
    }
    return true;
  }
}

/// One stroke being laid off screen ([_BrushEditShapeShow._stepStroke]).
/// A stroke the tool lays: its path, and the one pressure it is laid at
/// ([ShapeShow.showStroke]). The same path at another pressure is another
/// stroke.
typedef _ToolPath = ({List<CanvasPoint> points, double pressure});

/// Whether [a] is [b] — the same points, at the same pressure.
bool _samePath(_ToolPath? a, _ToolPath b) =>
    a != null && a.pressure == b.pressure && listEquals(a.points, b.points);

class _StrokeLaying {
  _StrokeLaying(this.path) : waypoints = _strokeWaypoints(path.points);

  final _ToolPath path;

  /// The points the stroke is taken through ([_strokeWaypoints]).
  final List<CanvasPoint> waypoints;

  /// How many of [waypoints] the stroke has been taken through — none
  /// until it is started at the first.
  int reached = 0;

  /// The dabs the stroke has made so far, in order.
  final List<BrushDab> made = [];

  /// The front of [made] handed to the rasterizer, which blends a list
  /// from an index: it grows a share at a time.
  final List<BrushDab> fed = [];

  /// Where the blended dabs reach.
  DirtyRegion? touched;

  /// The tiles to picture, once the stroke is made and blended.
  List<TileCoord>? coords;

  /// How many of [coords] are pictured.
  int pictured = 0;

  /// False where the overlay could not picture ahead.
  bool staged = true;
}
