part of '../interactive_brush_edit_canvas_view.dart';

/// THE SHAPE WHILE IT IS DRAGGED — the shape tool's area laid a few pieces
/// a frame, shown when it is whole, and landed as it was shown — as its own
/// object.
///
/// 🗣️유저 답 I-69-Q4ⓒ (2026-10-08): 「윤곽선은 손을 따라오고, 실제 결과는
/// 따라 그린다」 — the outline follows the hand every frame and stays light;
/// under it the actual result is laid at the pace the device can manage,
/// once more at the hand's newest shape each time the last is done, and
/// what was showing when the hand lets go is what stays.
///
/// 🚨★★★WHOLE OR NOT AT ALL. A shape half laid is a wrong picture, and the
/// answer allows only a LATE one: the pieces are laid off screen — result
/// tiles made by the fill's own function ([promoteFillDabs]), each piece on
/// the cel with the pieces before it — and the overlay takes them in one
/// call when the last piece is laid ([_BrushEditFill.showResult]). Until
/// then the last whole shape stays up.
///
/// 🚨★★★WHAT LANDS IS WHAT WAS SHOWN. Let go on the shape on screen and its
/// tiles land as they are, through the landing a fill takes
/// ([_BrushEditFill.landResult]): nothing is laid twice and not a byte on
/// screen changes. A shape the hand moved on from is finished first, on
/// the spot.
///
/// ⚠️A frame lays for [shapeShowFrameShare] at most, and always at least
/// one piece: the debug build is the bar for lag (유저 2026-09-26 「5배 느린
/// 빌드가 기준」), and one shape laid whole costs more than a frame — a
/// filled 2010×1510 ellipse is built and laid in 23–33 ms on the desktop's
/// VM — which in one go would take the outline the hand drags down with it.
class _BrushEditShapeShow implements ShapeShow {
  _BrushEditShapeShow(this._state);

  final _InteractiveBrushEditCanvasViewState _state;

  /// The shape the hand asks for now.
  ShapeArea? _wanted;

  /// The shape being laid, off screen.
  _ShapeLaying? _laying;

  /// The shape on screen, whole.
  _ShapeLaying? _shown;

  bool _frameAsked = false;

  /// A cel this view can draw on: one there is, on a row that takes marks.
  bool get _canLay => _state.widget.editable && _state.widget.rowAcceptsStrokes;

  @override
  void show(ShapeArea area) {
    if (!_canLay) {
      return;
    }
    _wanted = area;
    if (_laying == null && _shown?.area.shape != area.shape) {
      _laying = _begin(area);
    }
    _askFrame();
  }

  @override
  bool land(ShapeArea area) {
    _wanted = null;
    if (!_canLay) {
      drop();
      return false;
    }
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
  void drop() {
    _wanted = null;
    _laying = null;
    if (_shown != null) {
      _shown = null;
      _state._overlay.resetOverlay();
    }
  }

  _ShapeLaying _begin(ShapeArea area) => _ShapeLaying(
    area,
    base: _state.widget.celNow(),
    selection: _state.widget.selectionRegion,
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
    final laying = _laying;
    if (laying == null) {
      return;
    }
    final clock = Stopwatch()..start();
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
}

/// One shape being laid: its pieces asked for one at a time, each laid —
/// as the fill's result tiles — on the cel with the pieces before it.
class _ShapeLaying {
  _ShapeLaying(
    this.area, {
    required this.base,
    required this.selection,
    required this.layerId,
    required this.frameId,
  }) : _pieces = area.pieces().iterator,
       _laidOn = base;

  final ShapeArea area;

  /// The cel as the shape found it — what its tiles were made against.
  final BitmapSurface base;
  final CanvasSelectionRegion? selection;
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
      selection: selection,
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
