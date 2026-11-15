import 'dart:math' as math;
import 'dart:typed_data';

import 'package:gpu_engine/gpu_engine.dart'
    show GpuColour, GpuFloodPicture, GpuMask, GpuPaint;

import '../core/floor_math.dart';
import '../models/dirty_region.dart';
import '../models/bitmap_surface.dart' show defaultCelTileSize;
import '../models/brush_dab.dart';
import '../models/brush_tip_shape.dart';
import '../models/canvas_point.dart';
import '../models/canvas_size.dart';
import '../models/drawing_guide.dart';
import '../models/pasteboard_bounds.dart';
import '../models/tiles_covering.dart';
import '../native/app_gpu_engine.dart' show appGpuComposite;
import '../native/engine_floods.dart';
import '../native/engine_selection_masks.dart';
import '../native/engine_stamp_pictures.dart';
import '../core/dev_profile.dart';
import 'canvas_read_source.dart';
import 'canvas_selection_region.dart';
import 'fill_gradient.dart';
import 'guide_geometry.dart';
import 'layer_pose_matrix.dart';
import 'pixel_run_contours.dart';
import 'selection_clip.dart';

/// P6 fill options — the Tool Settings panel's knobs (R11-④).
class FloodFillOptions {
  const FloodFillOptions({
    this.tolerance = 32,
    this.expandPx = 1,
    this.antiAlias = true,
    this.gapClosePx = 0,
    this.extendBeyondCanvas = false,
    this.source = CanvasReadSource.display,
    this.continuous = false,
    this.gradient = const FillGradientOptions(),
  });

  /// The fill's gradient (I-160, 유저 2026-11-04: 「채우기도구안에서
  /// 도구 설정안에서 구현」) — on, a press picks the range and the next lays
  /// a gradient across it ([FillGradientOptions]).
  final FillGradientOptions gradient;

  /// 「연속 채우기」 (I-160, 유저 2026-11-04): a press held across the canvas
  /// takes in every region it passes over — one range, marked as one and
  /// laid as one at the lift ([FillRange.joining]) — instead of moving its
  /// range to wherever it is.
  ///
  /// 🗣️I-160-Q6 b 「지나간 칸 전부」: any region the press passes, whatever
  /// its colour — line art included, as Krita's 「Fill Regions of Any
  /// Color」 does. CSP's help says only that a drag fills 「連続する複数の閉じた
  /// 領域」 at once.
  final bool continuous;

  /// Which layers the flood reads (I-36) — the eyedropper's question and
  /// answers ([CanvasReadSource]). The default is the user's first mode,
  /// 「참조(보이는거 전부)」.
  final CanvasReadSource source;

  /// Max per-channel distance from the seed color that still fills.
  final int tolerance;

  /// Region growth in pixels AFTER the fill — closes the classic hairline
  /// gap between the fill and anti-aliased ink edges.
  final int expandPx;

  /// One soft pass over the mask edge.
  final bool antiAlias;

  /// Close-gap fill (R20-C1, the CSP "틈 닫기"): barriers act as if
  /// thickened by this radius, so the fill cannot leak through line-art
  /// gaps narrower than ~2× this value; the region then grows back to
  /// the REAL barriers. 0 = off.
  final int gapClosePx;

  /// Pasteboard fill: the fill boundary moves from the canvas rect to a
  /// finite apron around it (see [pasteboardFillMarginCap]) so regions
  /// crossing the canvas edge fill too. A flood that reaches the apron's
  /// outer wall means the region is NOT closed — the fill aborts and the
  /// caller reports the leak instead of flooding the surround
  /// (the raster equivalent of Flash's closed-shape rule).
  final bool extendBeyondCanvas;

  FloodFillOptions copyWith({
    int? tolerance,
    int? expandPx,
    bool? antiAlias,
    int? gapClosePx,
    bool? extendBeyondCanvas,
    CanvasReadSource? source,
    bool? continuous,
    FillGradientOptions? gradient,
  }) {
    return FloodFillOptions(
      tolerance: tolerance ?? this.tolerance,
      expandPx: expandPx ?? this.expandPx,
      antiAlias: antiAlias ?? this.antiAlias,
      gapClosePx: gapClosePx ?? this.gapClosePx,
      extendBeyondCanvas: extendBeyondCanvas ?? this.extendBeyondCanvas,
      source: source ?? this.source,
      continuous: continuous ?? this.continuous,
      gradient: gradient ?? this.gradient,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FloodFillOptions &&
      other.tolerance == tolerance &&
      other.expandPx == expandPx &&
      other.antiAlias == antiAlias &&
      other.gapClosePx == gapClosePx &&
      other.extendBeyondCanvas == extendBeyondCanvas &&
      other.source == source &&
      other.continuous == continuous &&
      other.gradient == gradient;

  @override
  int get hashCode => Object.hash(
    tolerance,
    expandPx,
    antiAlias,
    gapClosePx,
    extendBeyondCanvas,
    source,
    continuous,
    gradient,
  );
}

/// The extended fill's apron width per side: as far as the pasteboard
/// reaches past the paper ([PasteboardReach.pastEdgeOf], I-109), capped so
/// the picture a fill reads stays allocatable (a full 3×3 pasteboard
/// picture of an 8K canvas would be gigabytes). Canvases at or under the
/// cap get the
/// exact pasteboard as their fill wall; larger ones get a generous apron
/// — either way the wall is FINITE, which is what makes leak detection
/// and "no infinite flood" structural.
const int pasteboardFillMarginCap = 1024;

int _pasteboardFillMargin(int canvasDimension, PasteboardReach reach) =>
    math.min(reach.pastEdgeOf(canvasDimension), pasteboardFillMarginCap);

/// The filled region as a coverage mask in canvas coordinates.
class FloodFillRegion {
  const FloodFillRegion({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.mask,
  });

  final int left;
  final int top;
  final int width;
  final int height;

  /// Row-major coverage bytes (width × height), 0..255.
  final Uint8List mask;
}

/// How far past its coverage a fill's finish reaches: [FloodFillOptions.
/// expandPx] generations of growth — and, with the anti-alias, one pixel
/// more: the fill's ramp spreads ONE PIXEL OUTWARD past its own edge (the
/// engine's soften, unclamped — mask.wgsl), so a box a fill is finished in
/// holds that pixel on every side.
///
/// 🗣️유저 답 the-fill-ramp-is-cut-at-its-box-Q1 (10-09): 「상자를 한 칸 넓혀
/// 어디서나 번지게」. ↩️The box was the coverage grown by the expand alone,
/// and a ramp that met its edge was cut there — the shape tool's 4px
/// horizontal line read `86 · 100 · 100 · 86 · 14%`, the spread on one side
/// only, and the bucket's lost it at the last cells of what it filled.
int fillFinishReach(FloodFillOptions options) =>
    options.expandPx + (options.antiAlias ? 1 : 0);

/// An AREA laid as stamp pieces ([_dabsOf]): every pixel [region]
/// covers, painted [color] whatever is under it and whoever asked — the
/// fill tool's shape fill (유저 확정: 올가미 채우기는 A — 내부에 뭐가 있든
/// 채운다), and what the shape tool lays without the brush: its fill and
/// its plain line (I-69). Under a symmetry guide [region] is every copy
/// together. Empty when the region covers no pixel at all.
///
/// It shares the flood's tail rather than resembling it. Once there is a
/// coverage mask the two are the same problem, so the expand and
/// anti-alias passes are the bucket's — which is why "AA follows the fill"
/// (유저 확정) needed no new rasterizer: the bucket's AA has always been a
/// post-pass over a binary mask, and a region's mask is binary too.
/// ONE SPELLING OF THOSE PASSES: the engine's (rust/src/kernels/mask,
/// `MaskPasses::fill`), which finishes the bucket's flood
/// (`Flood::finish`) and an area ([EngineSelectionMasks.area]) alike.
/// ↩️From 2026-11-12, when the bucket's finish moved to the engine, till
/// 2026-11-15 an area was finished here by a second spelling in Dart
/// (`dilateMask4` · `softenMaskBoundary`, a window a piece), which a test
/// held to the kernel's (board
/// `an-areas-finish-is-a-second-spelling-of-the-floods`).
///
/// What it does NOT share is the front: no picture, no seed, no
/// tolerance. An area never looks at the picture, so it never pays to
/// composite one — this is markedly cheaper than a flood, not a variant of
/// it.
///
/// 🚨★★★IT IS FINISHED ONLY WHERE IT REACHES (board
/// `an-area-dab-costs-its-box`, 2026-10-09). It was finished as ONE SHEET
/// over its whole box — the coverage box grown by the expand — so its cost
/// followed the box and not the paint: a 4px diagonal across a 2010×1510
/// box built 17–34 ms and an 11.5 MB stamp, and its landing staged every
/// tile of the box, the same as filling the box solid (the VM on the
/// desktop). Now the rows come as RUNS first
/// ([CanvasSelectionRegion.pixelRunsFor] — no byte per pixel), the runs
/// say which tiles the finished area reaches ([_tilesReached]), and the
/// engine finishes it over those alone, each piece's coverage cut for it
/// there ([_AreaOnEngine]).
///
/// ⛔NO PIECE IS READ BACK (🗣️캔버스 베이스 2026-11-15 09:46, 관제's to
/// overturn): a fill's pieces are the engine's mask stamps ([_pieceDab]),
/// so coverage read down to be cut here and handed up again would be a
/// trip from the GPU to the CPU and back. The engine cuts each piece's
/// plane where it finished the sheet, and the piece is laid of that: no
/// wait, no read.
///
/// ⛔WHAT LANDS IS THE SHEET'S BYTES. The finish reads the hard mask no
/// farther than its passes reach — `expandPx` 4-neighbour generations,
/// then one soften — so the tiles within that reach of the coverage hold
/// every pixel it leaves any of, and finished over those alone each is
/// what the whole sheet finished there (`MaskPasses::fill`). The sheet
/// itself holds all the finish reaches ([fillFinishReach]), the ramp past
/// the expand included, so nothing of the area is cut at it.
List<BrushDab> buildRegionFillDabs({
  required CanvasSelectionRegion region,
  required int color,
  double opacity = 1.0,
  FloodFillOptions options = const FloodFillOptions(),
}) => regionFillPieces(
  region: region,
  color: color,
  opacity: opacity,
  options: options,
).toList();

/// [buildRegionFillDabs]'s pieces one at a time — what lets a shape being
/// dragged be laid a few pieces a frame and shown when it is whole
/// (I-69-Q4ⓒ). Every pass over it makes its pieces afresh; their coverage
/// is the engine's, asked for all together the first time one is laid
/// ([_AreaOnEngine]).
Iterable<BrushDab> regionFillPieces({
  required CanvasSelectionRegion region,
  required int color,
  double opacity = 1.0,
  FloodFillOptions options = const FloodFillOptions(),
}) sync* {
  final area = _areaOf(region, options);
  if (area == null) {
    return;
  }
  final (:hard, :sheet, :reach) = area;
  final runs = _runsOf(
    sheet,
    covered: _tilesReached(hard, sheet: sheet, reach: reach),
  ).toList();
  final onEngine = _AreaOnEngine(
    region: region,
    sheet: _pixelsOf(sheet),
    options: options,
    parts: [for (final run in runs) run.box],
  );
  yield* _dabsOf([
    for (final (at, run) in runs.indexed)
      _Piece(run, (_) => onEngine.masks[at]),
  ], (color: color, gradient: null, opacity: opacity));
}

/// The RANGE a drawn outline covers (I-160: 「올가미같은것도 올가미로 범위고르고
/// 그 다음 드래그」) — [region] finished as [regionFillPieces] finishes it,
/// held as the bucket's flood is held ([FillRange]), so the press after it
/// lays its gradient through the bucket's own code. Null when it covers no
/// pixel.
///
/// ⚠️Finished over its whole sheet at once and read back, which
/// [regionFillPieces] will not do (board `an-area-dab-costs-its-box`): a
/// range is read whole — its mark, and a gradient over every pixel of it —
/// as the bucket's flood is, which costs its box too. Waits for the GPU.
FillRange? regionFillRange({
  required CanvasSelectionRegion region,
  double opacity = 1.0,
  FloodFillOptions options = const FloodFillOptions(),
}) {
  final area = _areaOf(region, options);
  // Nothing the finish passes can grow: they only ever spread coverage.
  if (area == null || area.hard.rows.every((runs) => runs.isEmpty)) {
    return null;
  }
  final sheet = _pixelsOf(area.sheet);
  final whole = _areaMasks(region, sheet, options, over: [sheet]).single;
  final Uint8List mask;
  try {
    mask = whole.read();
  } finally {
    whole.free();
  }
  return FillRange.over(
    FloodFillRegion(
      left: sheet.left,
      top: sheet.top,
      width: sheet.width,
      height: sheet.height,
      mask: mask,
    ),
    opacity: opacity,
  );
}

/// [region]'s hard coverage and the sheet it is finished as: the coverage
/// box, with room for all the finish reaches — the expand AND the ramp
/// past it. Null when the box is empty.
({_HardRuns hard, DirtyRegion sheet, int reach})? _areaOf(
  CanvasSelectionRegion region,
  FloodFillOptions options,
) {
  final bounds = region.coverageBounds;
  final left = bounds.left.floor();
  final top = bounds.top.floor();
  final width = bounds.right.ceil() - left;
  final height = bounds.bottom.ceil() - top;
  if (width <= 0 || height <= 0) {
    return null;
  }
  final rows = region.pixelRunsFor(
    left: left,
    top: top,
    width: width,
    height: height,
  );
  final reach = fillFinishReach(options);
  return (
    hard: (rows: rows, left: left, top: top),
    sheet: DirtyRegion(
      left: left - reach,
      top: top - reach,
      rightExclusive: left + width + reach,
      bottomExclusive: top + height + reach,
    ),
    reach: reach,
  );
}

/// A region's hard coverage as rows of runs: row `r` is the canvas row
/// `top + r`, its `[start, end, …]` columns counted from `left`
/// ([CanvasSelectionRegion.pixelRunsFor]).
typedef _HardRuns = ({List<List<int>> rows, int left, int top});

/// A box of canvas pixels.
typedef _Pixels = ({int left, int top, int width, int height});

/// [box]'s pixels.
_Pixels _pixelsOf(DirtyRegion box) => (
  left: box.left,
  top: box.top,
  width: box.rightExclusive - box.left,
  height: box.bottomExclusive - box.top,
);

/// [region] finished over [sheet] as [options] say — the expand's
/// generations, then the anti-alias — [over] those parts of it alone, and
/// cut into a mask for each, on the engine ([EngineSelectionMasks.area]).
List<GpuMask> _areaMasks(
  CanvasSelectionRegion region,
  _Pixels sheet,
  FloodFillOptions options, {
  required List<_Pixels> over,
}) => EngineSelectionMasks.area(
  region.spelled,
  box: sheet,
  expand: options.expandPx,
  antiAlias: options.antiAlias,
  parts: over,
);

/// An area's pieces' coverage on the engine ([_areaMasks] over [parts]):
/// asked for once, all together, the first time one is read on the engine
/// the app has, and kept as long as this is — which every piece laid of it
/// holds.
final class _AreaOnEngine {
  _AreaOnEngine({
    required this.region,
    required this.sheet,
    required this.options,
    required this.parts,
  });

  final CanvasSelectionRegion region;
  final _Pixels sheet;
  final FloodFillOptions options;
  final List<_Pixels> parts;

  /// A mask a part, in [parts]' order.
  List<GpuMask> get masks => EngineSelectionMasks.keptFor(
    this,
    () => _areaMasks(region, sheet, options, over: parts),
  );
}

/// The grid an area is cut on: the cel's own tiles. It decides only how
/// the area is cut, never a byte of what lands — a piece lands 1:1 wherever
/// it is — and on the cel's grid each piece stages exactly the tiles it
/// covers when it lands, a run of them along one tile row. A surface on
/// another grid lands the same bytes.
const int _pieceSize = defaultCelTileSize;

/// Which of [sheet]'s tiles the finished area reaches: a tile that holds a
/// pixel within [reach] of a covered one, the steps along the rows and
/// along the columns counted together. A generation of the expand takes in
/// a pixel's four neighbours and the soften one more, so the finish leaves
/// something of every pixel that near and of no other. The rest finish to
/// nothing, and are never finished.
///
/// ⛔EXACT, and it has to be: no byte of a piece comes back to say the
/// piece was empty ([buildRegionFillDabs]), so a tile named here that held
/// nothing would be laid as a stamp of nothing — staged, and kept by the
/// history — and one missed would be a hole. ↩️Till 2026-11-15 it named
/// every tile within [reach] along the rows AND along the columns, a
/// square's corners more than the finish reaches, and the bytes finished
/// here said which of those were empty.
bool Function(TileSpan piece) _tilesReached(
  _HardRuns hard, {
  required DirtyRegion sheet,
  required int reach,
}) {
  final range = sheet.tileRange(tileSize: _pieceSize);
  final columns = range.lastX - range.firstX + 1;
  final grid = Uint8List(columns * (range.lastY - range.firstY + 1));
  for (var row = 0; row < hard.rows.length; row += 1) {
    final runs = hard.rows[row];
    if (runs.isEmpty) {
      continue;
    }
    final y = hard.top + row;
    final firstY = floorDiv(y - reach, _pieceSize);
    final lastY = floorDiv(y + reach, _pieceSize);
    for (var tileY = firstY; tileY <= lastY; tileY += 1) {
      // What is left of the reach along the row, once it has gone up or
      // down to this row of tiles.
      final top = tileY * _pieceSize;
      final bottom = top + _pieceSize - 1;
      final away = y < top ? top - y : (y > bottom ? y - bottom : 0);
      final along = reach - away;
      final tileRow = (tileY - range.firstY) * columns - range.firstX;
      for (var r = 0; r + 1 < runs.length; r += 2) {
        final x0 = hard.left + runs[r] - along;
        final x1 = hard.left + runs[r + 1] - 1 + along;
        grid.fillRange(
          tileRow + floorDiv(x0, _pieceSize),
          tileRow + floorDiv(x1, _pieceSize) + 1,
          1,
        );
      }
    }
  }
  return (piece) =>
      grid[(piece.coord.y - range.firstY) * columns +
          (piece.coord.x - range.firstX)] !=
      0;
}

/// 🚨★★★WHAT A FILL HELD DOWN WILL COVER, BEFORE A COLOUR IS LAID (I-160 ·
/// I-160-Q2 a, 유저 2026-11-04 「바꾼다 — 누르는 동안 미리보기, 떼면 채움」):
/// the flood from a point, kept so the press can show where it reaches and
/// the lift can land it without flooding again.
///
/// In the space the seed was in ([fillRangeAt]'s `space`). Null from
/// [fillRangeAt] when nothing was flooded at all — the seed off the box
/// the fill reads.
final class FillRange {
  FillRange._({
    required this.region,
    required List<FloodFillRegion> reached,
    required double opacity,
    void Function()? onOpenRegion,
  }) : _reached = reached,
       _opacity = opacity,
       _onOpenRegion = onOpenRegion;

  /// The range of [region], already flooded and closed — laid at [opacity].
  FillRange.over(FloodFillRegion region, {double opacity = 1.0})
    : this._(region: region, reached: [region], opacity: opacity);

  /// What the fill lands on: every closed copy's region in one — null when
  /// each copy flooded to the apron's wall ([open]).
  final FloodFillRegion? region;

  /// Every copy the flood reached, closed or open — what [covers] reads, so
  /// a press moving over a region that refuses to fill does not flood it
  /// again at each step.
  final List<FloodFillRegion> _reached;

  final double _opacity;
  final void Function()? _onOpenRegion;

  /// The pieces of [region] made so far, and what makes the rest
  /// ([_pieces]).
  final List<_Piece> _made = [];
  Iterator<_Piece>? _making;

  /// [region]'s pieces ([_runsOf]), each made once — and its coverage
  /// moved to the engine once — however often the range is laid: a
  /// gradient dragged over it lays it at every frame under new ends, and
  /// its commit lays it once more. An ask reads what the asks before made
  /// and makes on from where they stopped, so it is still laid a share at
  /// a time where a share is asked.
  Iterable<_Piece> _pieces(FloodFillRegion finished) sync* {
    for (var at = 0; ; at += 1) {
      if (at == _made.length) {
        final making = _making ??=
            _runsOf(
                  _boxOf(finished),
                  covered: (tile) => _covers(finished, tile),
                )
                .map(
                  (run) => _Piece.ofBytes(run, _bytesOver(finished, run.box)),
                )
                .iterator;
        if (!making.moveNext()) {
          return;
        }
        _made.add(making.current);
      }
      yield _made[at];
    }
  }

  /// Whether nothing fills because the region is not closed — an EXTENDED
  /// fill's flood reached the apron wall.
  bool get open => region == null;

  /// Whether a flood from [point] would flood what this one did: a pixel
  /// this range's flood covered, in the seed's space.
  bool covers(CanvasPoint point) {
    final x = point.x.floor();
    final y = point.y.floor();
    for (final part in _reached) {
      final column = x - part.left;
      final row = y - part.top;
      if (column >= 0 &&
          row >= 0 &&
          column < part.width &&
          row < part.height &&
          part.mask[row * part.width + column] > 0) {
        return true;
      }
    }
    return false;
  }

  /// This range and [next] as one — what a continuous fill holds as its
  /// press passes from region to region ([FloodFillOptions.continuous]).
  ///
  /// Each region is judged as it was flooded, as a symmetry's copies are
  /// ([fillRangeAt]): an open one adds nothing to lay, and the notice is
  /// said only when every region was open. The closed ones merge through the
  /// copies' one merge ([_unionRegions]) — one mask per join, which a press
  /// whose mark changes at each join pays anyway.
  FillRange joining(FillRange next) => FillRange._(
    region: _unionRegions([?region, ?next.region]),
    reached: [..._reached, ...next._reached],
    opacity: _opacity,
    onOpenRegion: _onOpenRegion,
  );

  /// The range laid in [color] as stamp pieces ([_dabsOf]) — empty for
  /// an [open] range, which says so ([fillRangeAt]'s `onOpenRegion`): it is
  /// where the fill would have landed that nothing does.
  List<BrushDab> dabsIn(int color) => _laid(color: color).toList();

  /// The range laid under [gradient] (I-160) — the stamp pieces [dabsIn]
  /// lays, each pixel the gradient's colour at its centre. Asked afresh at
  /// each frame a gradient is dragged, and laid a share of a frame at a
  /// time where a share is asked ([ShapeArea]'s `pieces`) — the pieces
  /// themselves made once ([_pieces]): a new frame is the gradient's ends.
  Iterable<BrushDab> piecesUnder(FillGradient gradient) =>
      _laid(color: gradient.startColor, gradient: gradient);

  Iterable<BrushDab> _laid({required int color, FillGradient? gradient}) {
    final finished = region;
    if (finished == null) {
      _onOpenRegion?.call();
      return const [];
    }
    return _dabsOf(
      _pieces(finished),
      (color: color, gradient: gradient, opacity: _opacity),
    );
  }

  /// Every pixel the fill would write into, inside [within] where a
  /// selection cuts it, in the seed's space — read in one pass as the two
  /// marks of it ([FillRangeCover]). Null for an [open] range.
  FillRangeCover? coveredWithin(SelectionClip? within) {
    final finished = region;
    if (finished == null) {
      return null;
    }
    final width = finished.width;
    final mask = within == null ? finished.mask : _within(finished, within);
    final cover = Uint8List(mask.length);
    // Four bytes at a time where the four are one answer — all ink inside a
    // run, all empty outside one — and a byte at a time where they are not
    // (🔬I-160: a 4K range read a byte each was 25 ms of rows). Only where
    // the mask's words line up.
    final words = mask.offsetInBytes % 4 == 0
        ? (
            mask: mask.buffer.asUint32List(
              mask.offsetInBytes,
              mask.length ~/ 4,
            ),
            cover: cover.buffer.asUint32List(0, mask.length ~/ 4),
          )
        : null;
    final rows = _RowsCovered(
      width: width,
      mask: mask,
      cover: cover,
      words: words,
    );
    final outline = pixelRunContours(
      [for (var y = 0; y < finished.height; y += 1) rows.from(y * width)],
      left: finished.left,
      top: finished.top,
      width: width,
    );
    return (
      outline: outline,
      cover: FloodFillRegion(
        left: finished.left,
        top: finished.top,
        width: width,
        height: finished.height,
        mask: cover,
      ),
    );
  }
}

/// [finished]'s pixels [within] takes any of, whole, and none elsewhere —
/// cut on the engine under the mask the selection made there
/// ([SelectionClip.maskOnEngine]), as the fill lands under it.
///
/// ↩️Till 2026-11-14 the CPU read the selection over the range's box at
/// every region a held press reached (`SelectionClip.maskFor`, its grow,
/// feather and anti-alias run there) and cut the range here a byte at a
/// time.
Uint8List _within(FloodFillRegion finished, SelectionClip within) {
  final box = (
    left: finished.left,
    top: finished.top,
    width: finished.width,
    height: finished.height,
  );
  final meets = within.mayCover(
    DirtyRegion.fromXYWH(
      x: box.left,
      y: box.top,
      width: box.width,
      height: box.height,
    ),
  );
  if (!meets) {
    return Uint8List(finished.mask.length);
  }
  return EngineSelectionMasks.cut(
    finished.mask,
    box: box,
    by: within.maskOnEngine(),
  );
}

/// The rows of a fill's [mask] read for what they cover
/// ([FillRange.coveredWithin]), each covered pixel marked in [cover].
final class _RowsCovered {
  _RowsCovered({
    required this.width,
    required this.mask,
    required this.cover,
    required this.words,
  });

  final int width;
  final Uint8List mask;
  final Uint8List cover;
  final ({Uint32List mask, Uint32List cover})? words;

  /// The covered runs of the row that starts at [offset] in the mask.
  List<int> from(int offset) {
    final wordsNow = words;
    final runs = <int>[];
    var inside = false;
    var x = 0;
    while (x < width) {
      final at = offset + x;
      if (wordsNow != null && at & 3 == 0 && x + 4 <= width) {
        final word = wordsNow.mask[at >> 2];
        if (inside ? word == 0xFFFFFFFF : word == 0) {
          wordsNow.cover[at >> 2] = word;
          x += 4;
          continue;
        }
      }
      final covered = mask[at] > 0;
      if (covered) {
        cover[at] = 255;
      }
      if (covered != inside) {
        runs.add(x);
        inside = covered;
      }
      x += 1;
    }
    if (inside) {
      runs.add(width);
    }
    return runs;
  }
}

/// The pixels a fill held down would write into ([FillRange.coveredWithin])
/// as each mark of them reads them: their [outline] on the pixel grid
/// ([pixelRunContours]) — the walk's — and their [cover], 255 on each and 0
/// elsewhere over the range's box — the engine's (flip lane ⓐ-3).
typedef FillRangeCover = ({
  PixelContours outline,
  FloodFillRegion cover,
});

/// What a canvas asks for the fill's range at [point] — [fillRangeAt] with
/// the host's cut, frame and knobs — and every copy [symmetry] makes of it.
typedef FillRangeAt =
    FillRange? Function(CanvasPoint point, SymmetryShape? symmetry);

/// The picture a fill reads over [box] of the space its seed is in: what
/// the screen shows there with the paper left out, kept on the engine
/// ([GpuFloodPicture]) — or null where there is none to read now. A canvas
/// makes it (`fillPictureOver`); [fillRangeAt] frees it.
typedef FillPictureOver = GpuFloodPicture? Function(DirtyRegion box);

/// The flood a fill from [point] makes — the picture its canvas shows
/// ([pictureOver]), flooded on the engine (rust/src/kernels/flood) — as a
/// [FillRange] laid later, in [FillRange.dabsIn]'s colour at [opacity].
/// Null when nothing floods: the seed off the box the fill reads, or no
/// picture to read.
///
/// 🚨★★★THE FILL READS WHAT THE SCREEN SHOWS (🗣️유저
/// gpu-canonical-store-Q1, 2026-11-06: 「화면과 똑같은 그림을 읽는다」): the
/// engine's composite of the frame — blends, folders, effects and letters
/// as they show — and the flood, its finish and its gap close run there
/// too. ↩️It read a raster of its own, the layers summed by a rule of its
/// own (source-over at each one's opacity, no blend or effect) tile by
/// tile as the flood reached them, in C or, with no engine, in Dart
/// (`LazyCanvasRasterRgb` · `floodFillRegion`, till 2026-11-12): what a
/// fill walled on was not always what was on screen.
///
/// The box is the canvas, or — with the fill past the canvas on — a finite
/// apron around it ([pasteboardFillMarginCap]), in the space [point] is
/// in: [space], the ARTWORK of the layer the dab lands on when it is posed
/// (the draw-through wrap hands the seed over in it), null for the canvas.
///
/// [symmetry] makes the tap fill every copy of the seed, unioned into the
/// same one region — see below for why the stroke path's dab replication
/// is the wrong tool here.
///
/// [onOpenRegion] is told when an open range is laid ([FillRange.dabsIn]),
/// not here: a press that rests on an open region has filled nothing yet.
FillRange? fillRangeAt({
  required CanvasSize canvasSize,
  required FillPictureOver pictureOver,
  required CanvasPoint point,
  double opacity = 1.0,
  FloodFillOptions options = const FloodFillOptions(),
  LayerPlacement? space,
  SymmetryShape? symmetry,
  void Function()? onOpenRegion,
  PasteboardReach pasteboardReach = PasteboardReach.whole,
}) {
  // With no pasteboard (I-109) there is nothing past the paper to fill
  // into: the fill is the canvas's, as it is with the apron off — a region
  // at the paper's edge is not refused as open.
  final extended =
      options.extendBeyondCanvas && pasteboardReach != PasteboardReach.none;
  // Extended (pasteboard) fills widen the box by a finite apron, into
  // negative world space; the default box IS the canvas.
  final marginX = extended
      ? _pasteboardFillMargin(canvasSize.width, pasteboardReach)
      : 0;
  final marginY = extended
      ? _pasteboardFillMargin(canvasSize.height, pasteboardReach)
      : 0;
  final box = DirtyRegion.fromLTBR(
    left: -marginX,
    top: -marginY,
    rightExclusive: canvasSize.width + marginX,
    bottomExclusive: canvasSize.height + marginY,
  );
  // A symmetry guide fills every copy of the SEED, not every copy of the
  // finished region: the mirrored region is whatever the picture encloses
  // over there, which is the whole point of drawing under a symmetry.
  //
  // ⛔The stroke path's `replicateDabs` cannot do this job. A fill arrives
  // as ONE `stamp` (an RGBA image) and the stamp blend ignores angle, so a
  // replicated fill dab would paste an UN-mirrored copy of *this* region on
  // the other side. Reflecting the seed and flooding again is the only
  // thing that reads the other side's own outline.
  //
  // The picture is made ONCE and every flood reads it, so N copies cost N
  // floods and not N composites — and every copy sees the same untouched
  // picture, which is what makes the result independent of seed order.
  //
  // [symmetry] is the CANVAS's and [point] is in [space]: the copies are
  // the canvas's, read through the seed's placement like a stroke's.
  final seeds = [
    for (final seed
        in symmetry == null
            ? [point]
            : [
                for (final copy in symmetryCopiesIn(
                  guideSpaceOf(space),
                  symmetry,
                ))
                  copy.apply(point),
              ])
      // A seed that simply landed outside the box answers nothing in
      // silence, exactly as it did before symmetry existed.
      if (box.containsPixel(x: seed.x.floor(), y: seed.y.floor()))
        (x: seed.x.floor(), y: seed.y.floor()),
  ];
  if (seeds.isEmpty) {
    return null;
  }
  final picture = labProbe('fill.picture', () => pictureOver(box));
  if (picture == null) {
    return null;
  }
  final parts = <FloodFillRegion>[];
  final reached = <FloodFillRegion>[];
  try {
    for (final (:x, :y) in seeds) {
      // Finished as one sheet where the picture lies — every piece is cut
      // from that one mask.
      final (:left, :top, :width, :height, :mask) = labProbe(
        'fill.flood',
        () => EngineFloods.kernels.fill(
          picture,
          x,
          y,
          tolerance: options.tolerance,
          gap: options.gapClosePx,
          expand: options.expandPx,
          antiAlias: options.antiAlias,
        ),
      );
      final part = FloodFillRegion(
        left: left,
        top: top,
        width: width,
        height: height,
        mask: mask,
      );
      reached.add(part);
      if (extended) {
        // Leak detection: a flood that reached the apron's outer wall
        // means the region is OPEN (nothing bounded it before the wall).
        // Refuse the fill — the raster analogue of Flash refusing to fill
        // an unclosed shape.
        //
        // Judged per COPY: one copy landing in open space says nothing
        // about the others, and dropping the whole fill because a mirror
        // missed would make the symmetry's own copies veto the seed's.
        final hitTheWall =
            left <= box.left ||
            top <= box.top ||
            left + width >= box.rightExclusive ||
            top + height >= box.bottomExclusive;
        if (hitTheWall) {
          continue;
        }
      }
      parts.add(part);
    }
  } finally {
    picture.free();
  }
  // The notice is the OPEN-region one only when a flood actually hit the
  // wall.
  if (reached.isEmpty) {
    return null;
  }
  return FillRange._(
    region: _unionRegions(parts),
    reached: reached,
    opacity: opacity,
    onOpenRegion: onOpenRegion,
  );
}

/// The regions a fill flooded, merged into the single region the stamp path
/// expects — coverage per pixel is the MAX of the parts, not their sum, so
/// two copies that overlap stay one flat fill instead of a darker seam.
///
/// One allocation for the whole merge: the union rect is measured first and
/// every part is blitted into it. Folding pairwise instead would re-allocate
/// a growing mask per copy, which on a large canvas is the fill's whole
/// budget spent on garbage.
///
/// A lone part is returned UNTOUCHED — the no-symmetry path, which is nearly
/// every fill, must not pay a copy of the mask to pass through here.
FloodFillRegion? _unionRegions(List<FloodFillRegion> parts) {
  if (parts.isEmpty) {
    return null;
  }
  if (parts.length == 1) {
    return parts.first;
  }
  var left = parts.first.left;
  var top = parts.first.top;
  var right = parts.first.left + parts.first.width;
  var bottom = parts.first.top + parts.first.height;
  for (final part in parts.skip(1)) {
    left = math.min(left, part.left);
    top = math.min(top, part.top);
    right = math.max(right, part.left + part.width);
    bottom = math.max(bottom, part.top + part.height);
  }
  final width = right - left;
  final height = bottom - top;
  final mask = Uint8List(width * height);
  for (final part in parts) {
    for (var y = 0; y < part.height; y += 1) {
      final source = y * part.width;
      final target = (part.top - top + y) * width + (part.left - left);
      for (var x = 0; x < part.width; x += 1) {
        final coverage = part.mask[source + x];
        if (coverage > mask[target + x]) {
          mask[target + x] = coverage;
        }
      }
    }
  }
  return FloodFillRegion(
    left: left,
    top: top,
    width: width,
    height: height,
    mask: mask,
  );
}

/// How a fill's stamp pieces are painted: in [color] — or under a
/// [gradient] (I-160), each pixel the gradient's colour at its centre — at
/// [opacity].
typedef _Paint = ({int color, FillGradient? gradient, double opacity});

/// A run of a fill's cel tiles along one tile row that its finished mask
/// covers at all ([_runsOf]): the pixels it covers, and its first tile's
/// place on the grid.
typedef _Run = ({_Pixels box, int column, int row});

/// A piece of a fill — a [_Run] of its tiles: the mask over `[left,
/// left+width) × [top, top+height)`, the run's first tile at ([column],
/// [row]), and its coverage where the engine holds it ([onEngine]).
final class _Piece {
  /// [run], whose coverage on the engine [_coverage] answers each time it
  /// is asked: an area's is the engine's from the start, cut where it was
  /// finished ([_AreaOnEngine]).
  _Piece(_Run run, this._coverage)
    : left = run.box.left,
      top = run.box.top,
      width = run.box.width,
      height = run.box.height,
      column = run.column,
      row = run.row;

  /// [run] of a mask the CPU holds — a flood's range, read whole for its
  /// mark ([FillRange]): [coverage], the mask's bytes over the run, moved
  /// to the engine the first time the piece is asked there, however often
  /// it is laid after ([EngineSelectionMasks.keptFor]).
  _Piece.ofBytes(_Run run, Uint8List coverage)
    : this(
        run,
        (piece) => EngineSelectionMasks.keptFor(
          piece,
          () => GpuMask(
            appGpuComposite,
            coverage,
            x: piece.left,
            y: piece.top,
            width: piece.width,
            height: piece.height,
          ),
        ),
      );

  final int left;
  final int top;
  final int width;
  final int height;
  final int column;
  final int row;
  final GpuMask Function(_Piece piece) _coverage;

  /// Its coverage on the engine the app has.
  GpuMask onEngine() => _coverage(this);
}

/// A finished coverage mask cut into STAMP PIECES: one for each run of cel
/// tiles of [box] that the mask covers at all, along a tile row, in
/// row-major order. [covered] says whether the mask covers any pixel of a
/// tile. Empty when no tile has a covered pixel.
///
/// 🚨★★★EVERY MASK A FILL LAYS IS CUT HERE — the bucket's flood and an
/// area alike (board `an-area-dab-costs-its-box`, 2026-10-09). A piece lands
/// 1:1 on its own pixels and the pieces share none, so every pixel that
/// shows is what one stamp over the whole box landed, through every route
/// a stamp takes (the blend, the erase, the selection's fold, 뒤에 그리기).
/// What they do not carry is the box's empty tiles: one stamp was the box's
/// width × height × 4 bytes however little of it was paint, its landing
/// staged every tile of the box, and the history held it all.
/// ⚠️Only bytes nobody sees can part: under alpha 0 a soft edge keeps the
/// colour it was painted with, and a composite of the whole stroke (a
/// blend, 뒤에 그리기) clears that wherever it passes — the one stamp passed
/// over its whole box, a piece passes over itself.
///
/// ⚠️A RUN, NOT A TILE, and it was measured — on the C stamp batch a piece
/// landed through then (gone 2026-11-12): a stamp landed in one native
/// call that fanned its tiles out across a worker pool, and the call had a
/// price of its own. A piece a tile filled the 2010×1510 ellipse in 173
/// calls and landed it in 28 ms where the one stamp had taken 12 (the VM on
/// the desktop); a run of the row's covered tiles takes one call per run,
/// and a thin line still carries only the tiles it crosses.
Iterable<_Run> _runsOf(
  DirtyRegion box, {
  required bool Function(TileSpan tile) covered,
}) sync* {
  final run = <TileSpan>[];
  _Run cut() {
    final first = run.first;
    final piece = (
      box: (
        left: first.left,
        top: first.top,
        width: run.last.rightExclusive - first.left,
        height: first.bottomExclusive - first.top,
      ),
      column: first.coord.x,
      row: first.coord.y,
    );
    run.clear();
    return piece;
  }

  for (final tile in tileSpansOf(box, tileSize: _pieceSize)) {
    if (run.isNotEmpty && run.last.coord.y != tile.coord.y) {
      yield cut();
    }
    if (covered(tile)) {
      run.add(tile);
    } else if (run.isNotEmpty) {
      yield cut();
    }
  }
  if (run.isNotEmpty) {
    yield cut();
  }
}

/// The box [region] lies in.
DirtyRegion _boxOf(FloodFillRegion region) => DirtyRegion(
  left: region.left,
  top: region.top,
  rightExclusive: region.left + region.width,
  bottomExclusive: region.top + region.height,
);

/// How many fills have been laid as dabs ([_dabsOf]) since the app began.
var _fillsLaid = 0;

/// [pieces] laid as [paint] says, a stamp dab each.
Iterable<BrushDab> _dabsOf(Iterable<_Piece> pieces, _Paint paint) sync* {
  // ⚠️ONE id per fill, and a piece's first tile in it. A stamp is equal to
  // another by id, size and bytes — two solid pieces sharing an id would be
  // one stamp to any set of them (the 확정 slot counts its stamps' sizes as
  // a set). ⛔And a fill's pieces have no bytes here to tell them apart
  // ([_pieceDab]): two fills laid within one microsecond must not share
  // one, so the count of fills is in it too.
  final id = 'fill-${DateTime.now().microsecondsSinceEpoch}-$_fillsLaid';
  _fillsLaid += 1;
  final onEngine = paint.gradient?.onEngine ?? GpuColour(paint.color);
  var sequence = 0;
  for (final piece in pieces) {
    yield _pieceDab(
      piece,
      paint: onEngine,
      color: paint.color,
      opacity: paint.opacity,
      id: '$id-${piece.column}.${piece.row}',
      sequence: sequence,
    );
    sequence += 1;
  }
}

/// [piece] handed over as a stamp dab landing on its own pixels, its
/// coverage laid under [paint] by the engine
/// ([EngineStampPictures.ofMask]).
///
/// The fill lands as a STAMP (R15-⑥), drawn 1:1 by the stamp blend path.
/// The old square-padded tip-mask dab re-sampled the giant mask bilinearly
/// per pixel at every materialization — a multi-second slice on large
/// fills — and the stamp is byte-exact by construction.
///
/// ↩️Till 2026-11-15 the CPU painted each piece a pixel at a time and
/// handed the picture up — under a gradient at every frame it was dragged
/// (board `a-gradient-fill-preview-paints-its-range-on-the-cpu-every-
/// frame`). 🗣️브러시/렌더링 2026-11-15 08:30: the plain fill goes by the
/// same door — 「CPU 가 RGBA 를 안 만드는 길이 하나가 된다」 — so no byte of
/// a piece's picture is made here, and nothing reads one.
BrushDab _pieceDab(
  _Piece piece, {
  required GpuPaint paint,
  required int color,
  required double opacity,
  required String id,
  required int sequence,
}) {
  final _Piece(:left, :top, :width, :height) = piece;
  return BrushDab(
    // Centred on the piece: a stamp lands at its centre less half its size
    // ([BrushStampImage.landingRect]), which is the piece's own corner.
    center: CanvasPoint(x: left + width / 2, y: top + height / 2),
    color: color,
    size: math.max(width, height).toDouble(),
    opacity: opacity,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: sequence,
    stamp: EngineStampPictures.ofMask(
      id: id,
      width: width,
      height: height,
      coverage: piece.onEngine,
      whole: false,
      paint: paint,
      rgba: () => throw StateError(
        'a fill piece is painted on the engine; its picture is never made '
        'here',
      ),
    ),
  );
}

/// Whether [finished] covers any pixel of [tile].
bool _covers(FloodFillRegion finished, TileSpan tile) {
  final width = tile.rightExclusive - tile.left;
  for (var y = tile.top; y < tile.bottomExclusive; y += 1) {
    final from =
        (y - finished.top) * finished.width + (tile.left - finished.left);
    for (var at = from; at < from + width; at += 1) {
      if (finished.mask[at] != 0) {
        return true;
      }
    }
  }
  return false;
}

/// [finished]'s bytes over [box], row after row.
Uint8List _bytesOver(FloodFillRegion finished, _Pixels box) {
  final bytes = Uint8List(box.width * box.height);
  for (var y = 0; y < box.height; y += 1) {
    final from =
        (box.top + y - finished.top) * finished.width +
        (box.left - finished.left);
    bytes.setRange(y * box.width, (y + 1) * box.width, finished.mask, from);
  }
  return bytes;
}
