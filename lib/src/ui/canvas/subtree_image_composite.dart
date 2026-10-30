import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/draw_space.dart';
import '../../core/lru.dart';
import '../../models/composite_tree.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_effect.dart' show ResolvedLayerEffect;
import '../../models/layer_id.dart';
import '../../models/rgba_image_bytes.dart';
import 'colour_key_shader.dart';
import 'directional_blur_shader.dart';
import 'iris_blur_shader.dart';
import 'display_resample.dart';
import 'fx_plugin_stages.dart';
import 'layer_blend_shader.dart';
import '../../services/composite_effect_paint.dart';
import '../../services/shaded_passes.dart';
import '../../services/layer_pose_matrix.dart'
    show LayerPlacement, placementMatrix;
import 'raster_picture.dart';
import '../text/cel_number_paint.dart' show celNumberExtent;

/// The largest side a sub-tree's own raster may have, in device pixels.
///
/// ⛔A THIRD 8192, on purpose — see the decision on `CanvasSizeDialog
/// .maxDimension`, which forbids merging constants that answer different
/// questions. That one says how big a DOCUMENT may be; `_maxBufferSide` in
/// canvas_layer_stack_view.dart caps the DISPLAY buffer and its remedy is to
/// fall back to the direct walk. This one caps a GROUP's raster and its
/// remedy is to clamp the scale — refusing here would be a second code path,
/// the one where a folder's effect silently does not apply.
///
/// It is one constant rather than one per route so the routes cannot
/// disagree about how big a folder may get.
const int maxSubtreeRasterSide = 8192;

/// [scale], shrunk just enough that [bounds]' long side lands within
/// [maxSide] device pixels — the UNIFORM shrink both cap sites apply.
///
/// One shrink of the whole thing, never a split into tiles: softer at the
/// worst magnifications, never seamed, and never a second code path an
/// effect could miss. The two callers differ only in which cap they hand
/// in (the display buffer's, or a group's minus its snap headroom), which
/// is a number, not a mode.
double scaleFittingSide({
  required double scale,
  required Size bounds,
  required double maxSide,
}) {
  final side = bounds.width > bounds.height ? bounds.width : bounds.height;
  return side * scale > maxSide ? maxSide / side : scale;
}

/// The CANVAS-SPACE rect a buffer for [node] covers: what of it lies
/// [within] what reads the buffer — the rect each of its rows stands for
/// ([extentOf]) under the row's own placement ([placementOf]), a folder's
/// or an adjustment's the union of its children's.
///
/// [within] is the view at the top, and under a folder that folder's own
/// buffer: a blur on the folder reads its buffer past the view, so what
/// lies inside it has to be there too. 🔬A blurred folder holding a
/// buffered one, cut to the view at every depth, put the frame's edge 56
/// levels off (2026-10-13, measured against the camera's old bound).
///
/// 🚨★★★ONE LAW FOR EVERY WALK (card export-folders-and-rows-at-their-extent,
/// 2026-10-13). ↩️The camera bounded a folder by the square that covers its
/// frame at any turn — 2.1× a 2340×1654 canvas, 8.2 Mpx a folder, a
/// convenience of R6a (07-30), nobody's decision — where the editing stack
/// bounded the same folder by what of it is in view. 🔬On the user's film,
/// with a kit that bounded it by the frame alone: a folder cut's picture
/// 129 → 79 ms of GPU, the run 151 → 124 s, the video's bytes the same.
///
/// [extentOf] is the rect a row STANDS FOR, not the part of it that holds
/// the ink: a folder's buffer — and so where its blur is worked out —
/// reaches as far as it did when every image was whole.
///
/// ⛔RECOMPUTED, NEVER ACCUMULATED. A rect that only ever grew would be the
/// high-water mark of everything you had done — the "sticky / containment
/// 매칭 버퍼 rect" the composite plan rejects by name.
Rect subtreeBufferBounds<T>(
  CompositeNode<T> node, {
  required Rect within,
  required Rect Function(T row) extentOf,
  required LayerPlacement? Function(T row) placementOf,
}) => within.intersect(_subtreeExtent(node, extentOf, placementOf));

Rect _subtreeExtent<T>(
  CompositeNode<T> node,
  Rect Function(T row) extentOf,
  LayerPlacement? Function(T row) placementOf,
) {
  switch (node) {
    case CompositeLeaf(:final payload):
      return _placed(extentOf(payload), placementOf(payload));
    // The letters where they stand on their row's paper, laid as it lies.
    case CompositeCelNumber(:final on, :final letters):
      return _placed(celNumberExtent(letters), placementOf(on.payload));
    // What clips is cut to the base: the base's rect is all of it.
    case CompositeClip(base: final of):
    case CompositeOpaque(:final of):
    // What it reads of a row is read, not drawn: its own rect is all.
    case CompositeReadsRows(node: final of):
      return _subtreeExtent(of, extentOf, placementOf);
    case CompositeGroup(:final children):
    case CompositeAdjustment(:final children):
    case CompositeBackdropBlend(:final children):
      var union = Rect.zero;
      for (final child in children) {
        final rect = _subtreeExtent(child, extentOf, placementOf);
        if (rect.isEmpty) {
          continue;
        }
        union = union.isEmpty ? rect : union.expandToInclude(rect);
      }
      return union;
  }
}

/// [extent] on a row's paper as the canvas holds it, the row lying at
/// [placement].
Rect _placed(Rect extent, LayerPlacement? placement) => placement == null
    ? extent
    : MatrixUtils.transformRect(placementMatrix(placement), extent);

/// The grid a sub-tree rasterises on, decided once and then obeyed.
///
/// ⛔The arithmetic lives HERE and only here. One walk composites a group
/// (`paintCompositeTree`) for the editing stack (playback's too, since
/// 2026-10-10) and the camera (which the export renders through) — ↩️two,
/// one each, until card one-walk-of-the-composite-tree. What it calls is
/// how big a group's buffer is ([subtreeBufferBounds]) and
/// `drawSubtreeAsImage`; the plan and the blit are the machinery underneath
/// and belong to this file alone.
@immutable
class SubtreeRasterPlan {
  const SubtreeRasterPlan({
    required this.bounds,
    required this.destination,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.scale,
    required this.rasterScale,
  });

  /// What the caller asked for. The blit clips to this.
  final Rect bounds;

  /// The rect the image is blitted into — [bounds] snapped OUTWARD to the
  /// raster grid, never [bounds] itself.
  final Rect destination;
  final int pixelWidth;
  final int pixelHeight;

  /// The scale actually used: [rasterScale], unless the cap had to clamp it.
  final double scale;

  /// The scale the walk asked for, kept so the blit can tell a 1:1 placement
  /// from a magnification without being told twice.
  final double rasterScale;

  /// Whether the cap clamped the scale, so the raster lands larger than its
  /// pixels — the one placement that is not 1:1, and the one a blit filters.
  bool get magnifies => scale != rasterScale;

  /// A canvas recording into [recorder] in the sub-tree's own space, so
  /// whatever paints into it does not know it is being rasterised — and
  /// bounded by the pixels it rasters, so a draw into it can ask what it
  /// can land on (`drawPosedLayerImage`, a picture in pieces).
  Canvas recordInto(ui.PictureRecorder recorder) =>
      Canvas(
          recorder,
          Rect.fromLTWH(0, 0, pixelWidth.toDouble(), pixelHeight.toDouble()),
        )
        ..scale(scale)
        ..translate(-destination.left, -destination.top);
}

/// Paints row [row] of the cut — one a chain reads, a camera lens blur's
/// blur map (🗣️I-132-Q16 a) — onto [into], in the space the raster that
/// reads it is recorded in, [rasterScale] of its pixels a unit there.
/// False, and nothing painted, for a row it does not hold: none.
typedef RowPainter =
    bool Function(Canvas into, LayerId row, double rasterScale);

/// Row [row] as [rows] paint it on [plan]'s grid — what a step rastered on
/// that grid reads of it; null where [rows] hold no such row.
ui.Image? _rowOnTheGrid(RowPainter rows, LayerId row, SubtreeRasterPlan plan) {
  final recorder = ui.PictureRecorder();
  if (!rows(plan.recordInto(recorder), row, plan.scale)) {
    recorder.endRecording().dispose();
    return null;
  }
  return rasterPicture(recorder, plan.pixelWidth, plan.pixelHeight);
}

/// What the last blit actually did, so a test can read the GEOMETRY rather
/// than infer it from pixels. The arithmetic here decides whether a group
/// resamples twice, and a scene where the difference happens to land on
/// transparent margin would report "same pixels" about a grid that had
/// already drifted.
///
/// ⚠️Written under `assert`, so it costs a release build nothing.
@visibleForTesting
SubtreeRasterPlan? debugLastSubtreeRaster;

/// How many sub-tree rasters have happened since a test zeroed it.
///
/// 🚨THE QUESTION A CACHE HAS TO ANSWER. Whether a group re-rasterised is
/// invisible in the pixels — a cache that worked and one that did not draw
/// the same picture — so counting is the only way to say which happened.
///
/// ⚠️Written under `assert`, so a release build pays nothing.
@visibleForTesting
int debugSubtreeRasterCount = 0;

/// 🚨★★★A SUB-TREE'S RASTER THAT A SPREADING CHAIN READS LIES ON THE
/// CANVAS'S GRID OF THIS MANY RASTER PIXELS — its corner and its size —
/// wherever the view cuts it (card nested-folder-buffers-read-past-the-view).
///
/// A blur reduces what it reads before it spreads it — to 1/2 … 1/16 by its
/// sigma, on a grid counted from that picture's own corner (Impeller's
/// Gaussian; 1/4 at a 40px blur). A raster cut where the view cuts it
/// started one pixel further at each one-pixel pan, and the reduction fell
/// on the ink another way each time. 🔬On the Windows app (2026-10-27, a
/// blurred folder by the view's edge while the row in it is drawn on):
/// 3–4/255 apart pan to pan in a probe, 190 → 211 in the verifier's — and,
/// cut by the view's top and bottom, 4–6/255 apart from the frame's own
/// picture everywhere, whose rasters nothing cuts. On this grid, counted
/// from the canvas's origin, each reduction lands where it would on the
/// whole: 0 apart, every pan, at the edge and inside, nested or not, the
/// row drawn on or a cel, and 0 from the frame's picture.
///
/// What it costs is at most a cell less one of transparent texels at each
/// edge — ⛔so only where a chain that spreads reads the raster
/// ([rasterCellFor]). One blitted 1:1 or read by a blend's shader is read
/// pixel for pixel, and on cells it only grew: an advanced blend's backdrop,
/// rastered three times a stroke step, went 17×13 → 32×32 pixels
/// (`a_blend_over_its_backdrop_rasterises_what_lands_test`).
const int blurReductionCell = 16;

/// The cells, in raster pixels, a raster lies on by what reads it: a chain
/// that spreads ([outsetPixels] past what it reads) reduces it by
/// [blurReductionCell]s, a blit or a shader reads it pixel for pixel.
int rasterCellFor(double outsetPixels) =>
    outsetPixels > 0 ? blurReductionCell : 1;

/// The grid [bounds] rasterises on at [rasterScale], or null when there is
/// nothing to draw.
///
/// 📐The image grid is the LOCAL space at [rasterScale] snapped OUTWARD to
/// whole cells of [cell] pixels ([rasterCellFor]), and
/// [SubtreeRasterPlan.destination] is exactly `pixels / scale`. A src/dst pair
/// that disagreed by a fraction would resample the sub-tree a second time.
///
/// [within] cuts the image to the part of [bounds] that can land — what the
/// canvas still shows — on the same grid: the scale is still the whole
/// [bounds]' and the grid is counted from the same point, so a part samples
/// where the whole would.
///
/// 🚨★★★THE GRID IS THE PIXELS OF WHAT IT IS LAID ON
/// (the-walk-family-cuts-the-rest-on-the-grid, 2026-10-30). Counted from the
/// origin of the space, it fell where the view's phase puts the canvas's
/// origin — inside a device pixel above 100% (F-83) — so the 1:1 blit
/// resampled every texel once more and blended the image's edge: 🔬a folder
/// on the walk at 125% (4×4 canvas) 18 of 256 pixels apart from the buffer,
/// a seam of its ink one pixel off and 16/255 of it past the page; 12 at
/// 150%, and at a ratio of 2, 10 and 12 of 1,024 at 125 and 150%. Counted
/// from where [onto]'s pixels have an edge ([pixelGridOriginAt] — the
/// raster lies on them 1:1, so its scale says where they are), the raster
/// is those pixels: what draws into it falls where it would on them, and
/// the blit lays each where it is. A cell's grid moves with the view's pan
/// as the origin did — a whole pixel for a whole pixel.
SubtreeRasterPlan? _planSubtreeRaster({
  required Rect bounds,
  required double rasterScale,
  int maxPixelSide = maxSubtreeRasterSide,
  Rect within = Rect.largest,
  int cell = 1,
  Canvas? onto,
}) {
  // 🚨THE SNAP IS PART OF THE CAP. Clamping the scale alone left the cap off
  // by one: `side * scale` landed exactly on the cap and then the OUTWARD
  // snap widened it, so the image came back one pixel over the limit it was
  // clamped to. The snap can add up to a cell less one at each edge, so
  // the room for both has to come out of the scale.
  //
  // A view so magnified the sub-tree alone overflows the cap shrinks the
  // way the display buffer does one level up — the same [scaleFittingSide],
  // now literally.
  assert(
    maxPixelSide > 2 * cell,
    'a cap holds a cell of room past the snap at each edge',
  );
  final scale = scaleFittingSide(
    scale: rasterScale,
    bounds: bounds.size,
    maxSide: (maxPixelSide - 2 * cell).toDouble(),
  );
  final destination = rectOutwardOnGrid(
    bounds.intersect(within),
    scale / cell,
    origin: onto == null ? Offset.zero : pixelGridOriginAt(onto, scale),
  );
  final width = (destination.width * scale).round();
  final height = (destination.height * scale).round();
  if (width <= 0 || height <= 0) {
    return null;
  }
  return SubtreeRasterPlan(
    bounds: bounds,
    destination: destination,
    pixelWidth: width,
    pixelHeight: height,
    scale: scale,
    rasterScale: rasterScale,
  );
}

/// Blits a rasterised sub-tree with [paint] — the paint that used to be a
/// `saveLayer`'s.
///
/// ⛔Does NOT dispose [image]: an adjustment blits the SAME raster twice, once
/// filtered and once not, and owning the lifetime here would have made the
/// second blit read freed pixels or the children rasterise twice.
///
/// ⛔NO CLIP TO THE BOUNDS, and that is not an oversight. A `saveLayer`'s
/// bounds do NOT cut a paint filter's spread — 🧪measured: a blurred layer
/// hinted at a 40×36 rect put 1150 device pixels outside it. Clipping here
/// looked like "reproducing the saveLayer" and was an invented rule that
/// changed pixels: it cost an adjustment crossfade 488 of them.
///
/// What bounds the UNfiltered content is the image itself, which is the
/// bounds snapped out to whole raster pixels — the same rounding-out Skia
/// does to a layer's offscreen. Same extent, same spread, same pixels.
///
/// ↩️🚨F-243: the image bounds unfiltered content only where the blend acts
/// in place. On the Windows app an image blitted in multiply or screen
/// stretched its border across everything the pass reached, so an
/// UNfiltered blit in such a blend was held to its destination
/// (`drawHeldToItsRect`) — until every advanced blend went over its
/// backdrop in the shader (a-blurred-folder-cut-by-the-view-moves-on-vulkan):
/// a blit's paint is a row's or a folder's, `srcOver` or `plus`, or the
/// composite's own `srcOver`.
void _blitSubtreeRaster({
  required Canvas canvas,
  required ui.Image image,
  required SubtreeRasterPlan plan,
  required Paint paint,
}) {
  // `none` because the blit is 1:1 by construction. It stops being 1:1 only
  // when the cap clamped the scale, and that is a magnification — the one
  // case that wants a filter.
  paint.filterQuality = plan.magnifies
      ? FilterQuality.low
      : FilterQuality.none;
  assert(() {
    debugLastSubtreeRaster = plan;
    return true;
  }());
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(
      0,
      0,
      plan.pixelWidth.toDouble(),
      plan.pixelHeight.toDouble(),
    ),
    plan.destination,
    paint,
  );
}

/// Draws the rasterised sub-tree with [paint].
///
/// [stepped] chooses WHICH raster. The default is the chain's steps applied,
/// which is what a group wants. An ADJUSTMENT needs both: its mix crossfades
/// between the scope and the scope WITH the chain on it, so the unfiltered
/// pass must not already be carrying the chain's colour keys — the mix could
/// then never fade them.
typedef BlitSubtree = void Function(Paint paint, {bool stepped});

/// 🚨★★★A SUB-TREE IS AN IMAGE — and it is the same pixels `saveLayer` made.
///
/// A folder used to composite through `canvas.saveLayer(bounds, paint)`. That
/// offscreen belongs to Skia: nobody can sample it, so a fragment shader on a
/// FOLDER is impossible and a per-group cache has nothing to keep. Rasterising
/// the sub-tree here makes a group the same kind of thing every other route
/// already hands around — an image — so ONE implementation of an effect can
/// attach at any depth instead of one for cels and another for folders.
///
/// [compose] receives a blit and decides the STRUCTURE around it: a group
/// blits once, an adjustment wraps a crossfade `saveLayer` around two. Passing
/// the structure in rather than a single paint is what lets an adjustment
/// rasterise its scope ONCE where two `saveLayer`s painted the children twice.
///
/// [held] is where the node's raster may already be, drawn whole, and where
/// a whole one is kept ([HeldSubtreeRasters]). [cell] is the grid what
/// [compose] blits with reads the raster by ([rasterCellFor]).
/// [paper] is where the paper lies in the space [bounds] is in — the edge a
/// blur among [steps] that repeats it reads past ([PaperEdgeEffect]): the
/// canvas, wherever a chain is laid, a row's own or a folder's
/// (I-132-Q14 a).
void drawSubtreeAsImage({
  required Canvas canvas,
  required Rect bounds,
  required double rasterScale,
  int maxPixelSide = maxSubtreeRasterSide,
  required void Function(Canvas into, double rasterScale) paintSubtree,
  required void Function(BlitSubtree blit) compose,
  List<CompositeEffectStep> steps = const [],
  required Rect paper,
  SubtreeHold? held,
  int cell = 1,
  RowPainter? rows,
}) {
  final plan = _planSubtreeRaster(
    bounds: bounds,
    rasterScale: rasterScale,
    maxPixelSide: maxPixelSide,
    cell: cell,
    onto: canvas,
  );
  if (plan == null) {
    return;
  }
  if (held?.covering(plan) case final whole?) {
    // The grid the whole lies on, cut to what is asked: it lands where a
    // raster of the part would, which samples on the whole's grid
    // ([_planSubtreeRaster]).
    final there = SubtreeRasterPlan(
      bounds: plan.bounds,
      destination: whole.plan.destination,
      pixelWidth: whole.plan.pixelWidth,
      pixelHeight: whole.plan.pixelHeight,
      scale: whole.plan.scale,
      rasterScale: whole.plan.rasterScale,
    );
    compose(
      (paint, {bool stepped = true}) => _blitSubtreeRaster(
        canvas: canvas,
        image: stepped ? whole.image : whole.raster,
        plan: there,
        paint: paint,
      ),
    );
    return;
  }
  final unrun = FxPluginStages.unrun;
  final recorder = ui.PictureRecorder();
  paintSubtree(plan.recordInto(recorder), plan.scale);
  _finishSubtreeRaster(
    canvas: canvas,
    recorder: recorder,
    plan: plan,
    compose: compose,
    steps: steps,
    paper: paper,
    held: held,
    rows: rows,
    unrunBefore: unrun,
  );
}

/// A node's sub-tree rastered WHOLE — its raster, the chain's steps on it,
/// and the grid they lie on — held for the next draw of the same node
/// ([HeldSubtreeRasters]).
typedef HeldSubtreeRaster = ({
  SubtreeRasterPlan plan,
  ui.Image raster,
  ui.Image image,
});

/// Where [drawSubtreeAsImage] finds a node's raster drawn whole, by [key] —
/// what the node draws — and, where [keeps], keeps the one it draws whole.
final class SubtreeHold {
  const SubtreeHold(
    this.rasters, {
    required this.key,
    required this.keeps,
    this.below = false,
  });

  final HeldSubtreeRasters rasters;

  /// What the node draws, its pixels' every input ([HeldSubtreeRasters]).
  final Object key;

  /// Whether the raster drawn here is the node's whole and may be kept.
  final bool keeps;

  /// Whether it is what lies below the row a pen draws into, held on a
  /// shelf of its own ([HeldSubtreeRasters]).
  final bool below;

  _HeldShelf get _shelf => below ? rasters._below : rasters._nodes;

  /// The raster held for [key] that [plan] can be cut from: drawn at the
  /// scale the walk is at — one held is never magnified ([_finishSubtreeRaster])
  /// — and covering it.
  HeldSubtreeRaster? covering(SubtreeRasterPlan plan) {
    final whole = _shelf._held.use(key);
    if (whole == null || whole.plan.rasterScale != plan.rasterScale) {
      return null;
    }
    final destination = whole.plan.destination;
    if (destination.expandToInclude(plan.destination) != destination) {
      return null;
    }
    rasters._drawn?.add(key);
    return whole;
  }

  /// Keeps [drawn], the node's whole, where its shelf has room for it.
  void _keep(HeldSubtreeRaster drawn) {
    if (_shelf._keep(key, drawn)) {
      rasters._drawn?.add(key);
    }
  }

  /// Whether a picture of [bounds] at [rasterScale] is held to be cut from.
  bool finds(Rect bounds, double rasterScale) {
    final plan = _planSubtreeRaster(bounds: bounds, rasterScale: rasterScale);
    return plan != null && covering(plan) != null;
  }

  /// Whether a picture of [bounds] at [rasterScale] is held to be cut from,
  /// or one drawn of it now — with no steps on it — would be kept: where
  /// neither, a picture of what could be drawn in place is drawn for
  /// nothing.
  bool findsOrKeeps(Rect bounds, double rasterScale) {
    final plan = _planSubtreeRaster(bounds: bounds, rasterScale: rasterScale);
    return plan != null && (covering(plan) != null || _wouldKeep(plan));
  }

  /// Whether no picture of [bounds] at [rasterScale] is held to be cut
  /// from, and one drawn of it now — with no steps on it — would be kept.
  bool keepsAnew(Rect bounds, double rasterScale) {
    final plan = _planSubtreeRaster(bounds: bounds, rasterScale: rasterScale);
    return plan != null && covering(plan) == null && _wouldKeep(plan);
  }

  bool _wouldKeep(SubtreeRasterPlan plan) =>
      keeps &&
      !plan.magnifies &&
      _shelf._fits(estimatedImageBytes(plan.pixelWidth, plan.pixelHeight));
}

/// 🚨★A NODE THAT DREW THE SAME PICTURE DOES NOT DRAW IT AGAIN — a folder, a
/// clip, an adjustment's scope: one picture of its sub-tree ([drawSubtreeAsImage]),
/// kept by what it draws where it was drawn whole, and cut from when the
/// same node is drawn again in part (card
/// paint-walk-redoes-the-same-work-each-step, 🔬2026-10-27: beside ten
/// folders at 50%, each a picture of its own, a stroke's every step drew
/// all ten again — a step on the screen p50 166ms against 85 with the
/// folders at 100%, Windows, profile).
///
/// Two shelves, each bounded on its own: what lies below the row a pen
/// draws into ([SubtreeHold.below], [bytesBelow]) and the nodes held one by
/// one ([bytes], each [eachAtMost]) — 🗣️유저 2026-10-27 (Q2 = c) 「그리는 행
/// 아래 · 위를 한 장씩 묶어 든다」. ⛔Not one: what lies below is drawn first
/// as a frame is laid, and the nodes over it kept after would push it out
/// first. One raster past its shelf is not kept at all: it is drawn as it
/// was before.
///
/// 🚨WHAT IS HELD IS THE NODES OF THE FRAME LAST DRAWN WHOLE TO HOLD THEM
/// ([holdOnly]) — 🗣️유저 2026-10-27 (Q3 = c): 「편집 중인 프레임의 위 폴더만
/// 들고 다른 프레임으로 가면 놓는다」.
final class HeldSubtreeRasters {
  HeldSubtreeRasters({
    required int Function() bytes,
    int Function()? eachAtMost,
    int Function() bytesBelow = _none,
  }) : _nodes = _HeldShelf(bytes, each: eachAtMost),
       _below = _HeldShelf(bytesBelow);

  final _HeldShelf _nodes;
  final _HeldShelf _below;

  static int _none() => 0;

  /// The nodes found or kept by the drawing [holdOnly] draws, while it does.
  Set<Object>? _drawn;

  /// How many rasters are held.
  int get length => _nodes._held.length + _below._held.length;

  /// What the rasters held weigh ([estimatedImageBytes]).
  int get heldBytes => _nodes._held.held + _below._held.held;

  /// What the rasters below a pen held weigh — the rest of [heldBytes] is
  /// the nodes held one by one.
  int get heldBelowBytes => _below._held.held;

  /// How many rasters held have been let go of — a node's drawn anew in its
  /// place aside: while it stands, every node a frame was drawn whole to
  /// hold, and kept, is held still.
  int get _lettings => _nodes.lettings + _below.lettings;

  /// 🚨THE FRAME WHOSE NODES WERE LAST DRAWN WHOLE TO BE HELD ([heldAllOf]),
  /// and how many held rasters had been let go of then: while both stand,
  /// every node of it that could be held is ([holdsAllOf]).
  ({Object of, int lettings})? _allOf;

  /// Notes that [of]'s frame was just drawn whole to hold its nodes
  /// ([holdOnly]).
  void heldAllOf(Object of) => _allOf = (of: of, lettings: _lettings);

  /// Whether [of]'s frame was drawn whole to hold its nodes, none held let
  /// go of since — drawn so again, it would hold nothing more.
  bool holdsAllOf(Object of) => _allOf == (of: of, lettings: _lettings);

  /// Draws [draw] — a frame drawn whole to hold its nodes — and lets go of
  /// every raster held that it neither found nor kept: those of the frame
  /// a canvas stood on before, and of what a frame held before it changed.
  void holdOnly(void Function() draw) {
    final drawn = _drawn = {};
    try {
      draw();
      _nodes._keepOnly(drawn);
      _below._keepOnly(drawn);
    } finally {
      _drawn = null;
    }
  }

  /// Counts what is held below a pen whose key [test] answers as found by
  /// the drawing [holdOnly] draws — what it leaves as it is held, undrawn
  /// (`BelowThePen.asHeld`).
  void keepHeldWhere(bool Function(Object key) test) =>
      _drawn?.addAll(_below._held.keys.where(test));

  /// Lets go of the least recently used rasters past each shelf's bound as
  /// it stands now — the line under it moved.
  void fit() {
    _nodes._held.fit();
    _below._held.fit();
  }

  /// Lets go of every raster held.
  void clear() {
    _nodes._clear();
    _below._clear();
  }
}

/// One shelf of [HeldSubtreeRasters]: the least recently used let go of
/// first, past [_bytes] — and none kept past [_each].
final class _HeldShelf {
  _HeldShelf(int Function() bytes, {int Function()? each})
    : _bytes = bytes,
      _each = each ?? bytes;

  final int Function() _bytes;
  final int Function() _each;
  late final Lru<Object, HeldSubtreeRaster> _held = Lru(
    limit: _bytes,
    costOf: _bytesOf,
    letGo: (_, held) => _letGo(held),
  );

  /// How many rasters this shelf has let go of — a node's drawn anew in its
  /// place aside ([HeldSubtreeRasters.lettings]).
  int lettings = 0;

  bool _fits(int bytes) => bytes <= _each() && bytes <= _bytes();

  /// Keeps [drawn] for [key] in handles of its own — the caller lets go of
  /// its own — where it fits; answers whether it did.
  bool _keep(Object key, HeldSubtreeRaster drawn) {
    if (!_fits(_bytesOf(drawn))) {
      return false;
    }
    final raster = drawn.raster.clone();
    final whole = (
      plan: drawn.plan,
      raster: raster,
      image: identical(drawn.image, drawn.raster)
          ? raster
          : drawn.image.clone(),
    );
    if (_held.keep(key, whole) case final replaced?) {
      _dispose(replaced);
    }
    return true;
  }

  /// Lets go of every raster held but [drawn]'s.
  void _keepOnly(Set<Object> drawn) {
    for (final key in [..._held.keys]) {
      if (!drawn.contains(key)) {
        _letGo(_held.take(key)!);
      }
    }
  }

  void _clear() {
    for (final held in _held.values) {
      _letGo(held);
    }
    _held.clear();
  }

  static int _bytesOf(HeldSubtreeRaster held) =>
      estimatedImageBytes(held.plan.pixelWidth, held.plan.pixelHeight) *
      (identical(held.image, held.raster) ? 1 : 2);

  void _letGo(HeldSubtreeRaster held) {
    lettings += 1;
    _dispose(held);
  }

  static void _dispose(HeldSubtreeRaster held) {
    if (!identical(held.image, held.raster)) {
      held.image.dispose();
    }
    held.raster.dispose();
  }
}

/// 🚨★★★A CLIPPING GROUP IS ONE PICTURE ([CompositeClip], I-92) — an image,
/// as a folder's is ([drawSubtreeAsImage]), so every walk that composites a
/// group composites a clip the same way.
///
/// Into it, [paintBase], and over it [paintScope] laid by the base's alpha
/// (`srcATop`); [paint] — the base's strength and blend — then lays the
/// picture once. [bounds] is the base's: what lands past it is cut away.
void drawClipAsImage({
  required Canvas canvas,
  required Rect bounds,
  required double rasterScale,
  required void Function(Canvas into, double rasterScale) paintBase,
  required void Function(Canvas into, double rasterScale) paintScope,
  required Paint paint,
  required Rect paper,
  SubtreeHold? held,
}) => drawSubtreeAsImage(
  canvas: canvas,
  bounds: bounds,
  rasterScale: rasterScale,
  paper: paper,
  paintSubtree: (into, scale) {
    paintBase(into, scale);
    into.saveLayer(bounds, Paint()..blendMode = BlendMode.srcATop);
    paintScope(into, scale);
    into.restore();
  },
  compose: (blit) => blit(paint),
  held: held,
);

/// A clip's base painted with its alpha made 1 ([CompositeOpaque]) — the
/// colour a row clipped to it blends with, where the base is half there
/// too. [bounds] holds the base; inside it, where the base is not, comes
/// out black, which the clip's `srcATop` then cuts away with the rest.
void drawOpaque({
  required Canvas canvas,
  required Rect bounds,
  required void Function(Canvas into) paintOf,
}) {
  canvas.saveLayer(
    bounds,
    Paint()..colorFilter = const ColorFilter.matrix(_opaqueMatrix),
  );
  paintOf(canvas);
  canvas.restore();
}

/// The colour as it is, the alpha 1 — the translation column is 0…255
/// (`color_matrix.dart`).
const List<double> _opaqueMatrix = <double>[
  // dart format off
  1, 0, 0, 0, 0,
  0, 1, 0, 0, 0,
  0, 0, 1, 0, 0,
  0, 0, 0, 0, 255,
  // dart format on
];

/// 🚨★★★A ROW IN AN ADVANCED BLEND IS COMPOSED OVER A PICTURE OF ITS
/// BACKDROP ([CompositeBackdropBlend], brush-fidelity-Q4).
///
/// A GPU blend reads what its target holds below it as it draws; for linear
/// burn, divide, darker colour … there is no GPU blend to do that, and the
/// GPU's own multiply, screen … each came with a defect of its own
/// (↩️they kept it until a-blurred-folder-cut-by-the-view-moves-on-vulkan,
/// [LayerBlendMode.needsItsBackdrop]). So both pictures are rasterised on
/// ONE grid — [paintBackdrop] (everything below the row in its scope) and
/// [paintSource] (the row itself, painting normal) — composed by
/// [LayerBlendShader] drawn on that grid, where a group's raster would be
/// blitted: it IS the backdrop and the row, composed, so it lands plain.
///
/// The arithmetic is [drawSubtreeAsImage]'s — the same plan — so a blend at
/// any depth sits on the grid a folder's buffer would.
///
/// ★Where the engine can, the backdrop is not rasterised at all but read in
/// the frame ([_composeInTheFrame]) — the same shader over the same two
/// pictures, the backdrop handed to it by the engine instead of by a raster
/// ([_readsInTheFrame] says where).
///
/// 🚨ONLY WHAT THE CANVAS STILL SHOWS IS RASTERISED: its clip, a stroke's
/// patch while one is drawn. 🔬Measured on the Windows app (10-22, a 2560
/// px window): with a shader-blended row over the layer being drawn on,
/// every step rasterised the row's whole buffer three times over — a frame
/// shown 49ms after its input against 12ms with the row normal, whatever
/// the brush's size.
///
/// ↩️A row that was its own image in one piece, laid texel for texel on the
/// grid, was handed to the shader as it was rather than rasterised
/// (`sourceAsIs`, 10-23), until no row was drawn as its own image
/// (one-picture-per-frame ②-5b-1).
void drawBlendOverBackdrop({
  required Canvas canvas,
  required Rect bounds,
  required double rasterScale,
  int maxPixelSide = maxSubtreeRasterSide,
  required void Function(Canvas into, double rasterScale) paintBackdrop,
  required void Function(Canvas into, double rasterScale) paintSource,
  required LayerBlendMode blendMode,
  Rect? shownWithin,
}) {
  final plan = _planSubtreeRaster(
    bounds: bounds,
    rasterScale: rasterScale,
    maxPixelSide: maxPixelSide,
    within: canvas.getLocalClipBounds(),
    onto: canvas,
  );
  if (plan == null) {
    return;
  }
  ui.Image rasterOf(void Function(Canvas into, double rasterScale) paint) {
    final recorder = ui.PictureRecorder();
    paint(plan.recordInto(recorder), plan.scale);
    assert(() {
      debugSubtreeRasterCount += 1;
      return true;
    }());
    return rasterPicture(recorder, plan.pixelWidth, plan.pixelHeight);
  }

  if (_readsInTheFrame(canvas, plan, shownWithin)) {
    _composeInTheFrame(
      canvas: canvas,
      plan: plan,
      rasterScale: rasterScale,
      paintBackdrop: paintBackdrop,
      source: rasterOf(paintSource),
      blendMode: blendMode,
    );
    return;
  }
  _composeInARaster(
    canvas: canvas,
    plan: plan,
    backdrop: rasterOf(paintBackdrop),
    source: () => rasterOf(paintSource),
    blendMode: blendMode,
  );
}

/// [backdrop], rasterised on [plan]'s grid, and the row [source] makes,
/// composed by [LayerBlendShader] drawn straight onto [canvas] on that grid
/// — the route where the frame cannot be read ([_readsInTheFrame]). It
/// disposes [backdrop].
///
/// 🗣️a-blurred-folder-cut-by-the-view-moves-on-vulkan-Q6 (유저 2026-10-23
/// 「이 카드에서 이어서 래스터 경로를 줄인다」): where the frame cannot be
/// read — Skia, a canvas seen flipped — every step rasterised the composite,
/// a third raster, only to blit it. ↩️🔬The shader reads `FlutterFragCoord()`
/// in the LOCAL space it is drawn in, on both renderers (10-23: under a
/// translate, a scale, a flip, a picture replayed elsewhere and a saveLayer,
/// Skia and Impeller alike). So drawn under [plan]'s grid — a raster pixel a
/// local unit — it reads the coordinates it read at the raster's identity,
/// and with its samplers nearest, as the 1:1 blit was, every device pixel
/// composes the two texels that blit would have shown it.
///
/// ⚠️A plan the cap clamped ([SubtreeRasterPlan.magnifies]) is still composed
/// in a raster and blitted: that blit filters the composite, and filtering
/// two pictures before they are composed is not the same bytes as filtering
/// what they composed.
void _composeInARaster({
  required Canvas canvas,
  required SubtreeRasterPlan plan,
  required ui.Image backdrop,
  required ui.Image Function() source,
  required LayerBlendMode blendMode,
}) {
  ui.Image? row;
  ui.FragmentShader? shader;
  ui.Image? composed;
  try {
    row = source();
    shader = LayerBlendShader.shaderFor(
      backdrop: backdrop,
      source: row,
      mode: blendMode,
      width: plan.pixelWidth.toDouble(),
      height: plan.pixelHeight.toDouble(),
    );
    if (!plan.magnifies) {
      assert(() {
        debugLastSubtreeRaster = plan;
        return true;
      }());
      canvas
        ..save()
        ..translate(plan.destination.left, plan.destination.top)
        ..scale(1 / plan.scale);
      _shadeTheGrid(canvas, plan, shader);
      canvas.restore();
      return;
    }
    assert(() {
      debugBlendsComposedInARaster += 1;
      return true;
    }());
    composed = shadedRaster(shader, plan.pixelWidth, plan.pixelHeight);
    _blitSubtreeRaster(
      canvas: canvas,
      image: composed,
      plan: plan,
      paint: Paint(),
    );
  } finally {
    // ⚠️Safe here, as in [_finishSubtreeRaster]: the draw put the shader and
    // the images into this frame's display list, which holds its own claim
    // from then on.
    composed?.dispose();
    shader?.dispose();
    row?.dispose();
    backdrop.dispose();
  }
}

/// How many blends were composed in a raster of their own and blitted
/// ([_composeInARaster]'s magnified plans) since a test zeroed it — the
/// third raster, invisible in the bytes.
///
/// ⚠️Written under `assert`, so a release build pays nothing.
@visibleForTesting
int debugBlendsComposedInARaster = 0;

/// [shader] over the whole of [plan]'s grid, in [into]'s space taken as that
/// grid — a raster pixel a unit — where the shader's own coordinates are the
/// images' ([LayerBlendShader]: `FlutterFragCoord()` over its size).
void _shadeTheGrid(Canvas into, SubtreeRasterPlan plan, ui.Shader shader) =>
    into.drawRect(
      Rect.fromLTWH(
        0,
        0,
        plan.pixelWidth.toDouble(),
        plan.pixelHeight.toDouble(),
      ),
      Paint()..shader = shader,
    );

/// Whether a blend is read in the frame where it can be
/// ([_composeInTheFrame]). Off, every blend rasterises its backdrop — the
/// route a test holds the frame's bytes against.
@visibleForTesting
bool debugBlendInTheFrame = true;

/// How many blends were read in the frame since a test zeroed it.
///
/// ⚠️Written under `assert`, so a release build pays nothing.
@visibleForTesting
int debugBlendsReadInTheFrame = 0;

/// Whether [canvas] can read [plan]'s backdrop in the frame: the engine has
/// a shader filter — Impeller; Skia has none, and throws — and the layer
/// the backdrop is drawn into lands whole on [plan]'s own grid.
///
/// 🚨The filter reads the layer as the engine CUTS it, to the clip it is
/// drawn under, and in the space it is drawn in. So the layer must lie
/// inside [shownWithin] — where the caller knows the recording is shown,
/// once, cut by nothing else (null: it may be replayed under another clip,
/// as a bake's recording is) — and under the canvas's clip, upright, on
/// whole device pixels. Anywhere else the source would be sampled off the
/// backdrop it is composed with.
bool _readsInTheFrame(
  Canvas canvas,
  SubtreeRasterPlan plan,
  Rect? shownWithin,
) {
  if (shownWithin == null ||
      !debugBlendInTheFrame ||
      !ui.ImageFilter.isShaderFilterSupported) {
    return false;
  }
  final m = canvas.getTransform();
  final upright =
      m[1] == 0 && m[3] == 0 && m[4] == 0 && m[7] == 0 && m[0] > 0 && m[5] > 0;
  if (!upright) {
    return false;
  }
  bool whole(double v) => (v - v.roundToDouble()).abs() < 1e-3;
  final d = plan.destination;
  final clip = canvas.getLocalClipBounds().intersect(shownWithin);
  return whole(d.left * m[0] + m[12]) &&
      whole(d.right * m[0] + m[12]) &&
      whole(d.top * m[5] + m[13]) &&
      whole(d.bottom * m[5] + m[13]) &&
      clip.left <= d.left + 1e-3 &&
      clip.top <= d.top + 1e-3 &&
      clip.right >= d.right - 1e-3 &&
      clip.bottom >= d.bottom - 1e-3;
}

/// [paintBackdrop] drawn into a layer whose filter IS the blend: the engine
/// hands that layer to [LayerBlendShader] as the backdrop, in the frame, and
/// [source] — rasterised on [plan]'s grid, which the layer lands on — is the
/// other picture. One raster where the backdrop's route makes three, and
/// none of them waits on the frame.
///
/// 🗣️a-blurred-folder-cut-by-the-view-moves-on-vulkan (유저 2026-10-22
/// 「골은 b」): the backdrop is read where the frame is drawn, the way the
/// GPU's own blend reads its target. 🔬On the Windows app (10-22, r12) a
/// stroke under a multiply row came to the screen 21.3ms after its input,
/// against 30.0 with the backdrop rasterised and 22.5 with the GPU's own
/// multiply; the whole canvas composed both ways was the same bytes. An
/// off-screen raster cost about 6.5ms of the raster thread whatever its
/// size (r10), which is what the backdrop's route paid three times a step.
void _composeInTheFrame({
  required Canvas canvas,
  required SubtreeRasterPlan plan,
  required double rasterScale,
  required void Function(Canvas into, double rasterScale) paintBackdrop,
  required ui.Image source,
  required LayerBlendMode blendMode,
}) {
  assert(() {
    debugBlendsReadInTheFrame += 1;
    debugLastSubtreeRaster = plan;
    return true;
  }());
  final shader = LayerBlendShader.filterFor(source: source, mode: blendMode);
  try {
    canvas
      ..saveLayer(
        plan.destination,
        Paint()..imageFilter = ui.ImageFilter.shader(shader),
      )
      ..clipRect(plan.destination)
      // 🚨THE LAYER IS AS LARGE AS WHAT IS DRAWN INTO IT, not as the bounds
      // it is saved with: 🔬on Impeller Vulkan (the test runner, 10-22) a
      // backdrop with nothing on its paper filled only part of the layer,
      // the engine handed the shader that part, and the source was read
      // shifted — a stroke in screen over one row laid a red ghost where
      // nothing was. Nothing, `src`, over the whole destination first.
      ..drawRect(
        plan.destination,
        Paint()
          ..blendMode = BlendMode.src
          ..color = const Color(0x00000000),
      );
    paintBackdrop(canvas, rasterScale);
    canvas.restore();
  } finally {
    // ⚠️Safe once the layer is recorded: the display list holds its own
    // claim on the filter and the image it samples.
    shader.dispose();
    source.dispose();
  }
}

/// Runs [steps] over [source], returning a NEW image the caller owns, or
/// [source] itself when there is nothing to do.
///
/// 🚨EVERY DRAW AT THE IDENTITY. A step's lead is fragment shaders, and a
/// shader reads `FlutterFragCoord()` — the position in the space it is drawn
/// into. Folding one into a draw that sits under a transform would make it
/// read through that transform. Laying the chain by itself, 1:1 into a rect
/// at the origin, is what makes the shader's own coordinates mean what it
/// thinks they mean. Every raster is [source]'s size.
///
/// 🚨AS FEW RASTERS AS THE DRAWS ALLOW (🗣️fx-made-light-by-one-law, 유저
/// 2026-10-29 「fx들 가볍게 하는 로직은 서로 최대한 법 통일하면서
/// 알아서해줘. 근본구조적으로」). A raster is what an effect pays for:
/// 🔬on the Surface Pro 11 one of 1920×1080 cost ~22ms and a layer inside
/// one ~1.5 (10-29, card effect-step-passes-each-pay-a-snapshot). So the
/// chain is laid as ONE picture ([_Laying]) and rastered only where a draw
/// must read the picture before it as an IMAGE: a colour key reads its run's
/// input beside it, a camera lens blur sums its rows in floats and gathers
/// out of them, a blur repeating the paper's edge cuts the paper out. Every
/// other draw — a pass along a way, a key, the painted effects a step ends
/// in — lies over the picture before it as a layer its shader filters
/// ([_LeadDraw.filtersALayer]), and the painted effects go on the draw under
/// them where its paint can take them: a `ui.Paint` applies its shader, then
/// its colour filter, then its image filter.
///
/// Where the engine has no shader filter (Skia) or a test switches it off
/// ([debugDrawsInOnePicture]), every lead draw is a raster of its own — the
/// route the picture is held against.
///
/// [paper] is where the paper lies in [source]'s pixels — the edge a blur
/// that repeats it reads past ([PaperEdgeEffect]). [rowOf] lays a row a
/// step reads ([effectReadsRow]) on [source]'s grid — null for none, and
/// none for every row where it is null: such a step reads no row.
ui.Image applyEffectSteps({
  required ui.Image source,
  required List<CompositeEffectStep> steps,
  required double imageScale,
  required Rect paper,
  ui.Image? Function(LayerId row)? rowOf,
}) {
  // ⛔The IMAGE's own space. A step rasters at the identity — there is no
  // CTM to map a sigma or a length through — so the chain arrives
  // pre-multiplied by however many image pixels a canvas pixel is.
  final space = imageScale == 1
      ? DrawSpace.canvas
      : DrawSpace.preScaled(imageScale);
  final layers =
      debugDrawsInOnePicture && ui.ImageFilter.isShaderFilterSupported;
  var laying = _Laying(source);
  try {
    for (final step in steps) {
      laying = _laidStep(
        laying,
        step,
        space: space,
        paper: paper,
        rowOf: rowOf,
        layers: layers,
      );
    }
    return laying.image();
  } catch (_) {
    laying.discard();
    rethrow;
  }
}

/// Whether a chain is laid as the layers of one picture where its draws let
/// it ([applyEffectSteps]). Off, every lead draw is a raster of its own —
/// the route a test holds the picture's bytes against.
@visibleForTesting
bool debugDrawsInOnePicture = true;

/// How many rasters effect chains took since a test zeroed it
/// ([applyEffectSteps]).
///
/// ⚠️Written under `assert`, so a release build pays nothing.
@visibleForTesting
int debugChainRasters = 0;

/// [laying] with [step] laid over it — its draws as layers where [layers]
/// and they let them be, rasters where they read an image.
_Laying _laidStep(
  _Laying laying,
  CompositeEffectStep step, {
  required DrawSpace space,
  required Rect paper,
  required ui.Image? Function(LayerId row)? rowOf,
  required bool layers,
}) {
  final then = resolveCompositeEffectPaint(step.then, space: space);
  final lead = step.lead;
  if (lead case PaperEdgeEffect(:final effect)) {
    if (paperEdgeBlurOf(effect, space) case final blur?) {
      return laying
          .cutAndBlurred(paper: paper, blur: blur)
          .then(then, layers: layers);
    }
  }
  if (lead case PluginEffect(:final effect)) {
    return laying
        .ranThrough(effect, scale: space.scale, paper: paper)
        .then(then, layers: layers);
  }
  // The row its lead reads, on the step's grid — alive until what reads it
  // is recorded.
  final read = switch (lead) {
    ShadedEffect(:final effect) => effectReadsRow(effect),
    _ => null,
  };
  final row = read == null ? null : rowOf?.call(read);
  final draws = _leadDraws(
    lead,
    space: space,
    paper: paper,
    rasterWidth: laying.source.width,
    row: row,
  );
  // What a draw reads beside the picture before it — a key run's input, a
  // gather's — is the step's input, as an image.
  final input = draws.any((draw) => draw.readsInput) ? laying.image() : null;
  var laid = laying;
  for (final draw in draws) {
    laid = layers && draw.filtersALayer
        // ⚠️The engine hands a layer's filter the layer as its first sampler
        // and its size as its first vec2, so the image the shader is made
        // with stands for nothing there but that size — the chain's.
        ? laid.under(draw.shade(laid.source, input ?? laid.source))
        : laid.drawnBy(draw, input: input);
  }
  laid
    ..keepUntilLaid(input)
    ..keepUntilLaid(row);
  return laid.then(then, layers: layers);
}

/// A picture a chain is laying ([applyEffectSteps]), the chain's [source]'s
/// size: an image, or what is drawn at its bottom and the filters laid over
/// it, the first innermost — recorded and rastered only when a draw must
/// read it as an image ([image]).
///
/// It owns every image it holds but [source], the caller's: each is released
/// once the picture that draws it is recorded — ⚠️safe from then on, as the
/// display list holds its own claim on what it draws.
class _Laying {
  _Laying(this.source) : _image = source, _paints = false;

  _Laying._drawn(
    this.source,
    void Function(Canvas into, Paint paint) bottom, {
    required bool paints,
  }) : _bottom = bottom,
       _paints = paints;

  /// The chain's input: every raster is its size.
  final ui.Image source;

  /// The picture where it is an image and nothing is laid over it.
  ui.Image? _image;

  /// What is drawn at the bottom of the picture, with [_paint].
  void Function(Canvas into, Paint paint)? _bottom;

  /// The bottom's paint — a fresh one for every picture.
  Paint _paint = Paint();

  /// Whether [_paint] can still take a step's painted effects: not once it
  /// holds them, nor where the bottom's own draw is filtered and cut
  /// ([cutAndBlurred]) — painted there they would come before its blur and
  /// inside its cut.
  bool _paints;

  /// The layers over the bottom, the first innermost.
  final List<ui.ImageFilter> _filters = [];

  final List<ui.FragmentShader> _shaders = [];
  final Set<ui.Image> _images = Set.identity();

  Rect get _rect =>
      Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble());

  /// The picture as an image: itself where it is one, else recorded and
  /// rastered — once; what it held is released.
  ui.Image image() {
    final held = _image;
    if (held != null) {
      return held;
    }
    final rect = _rect;
    final recorder = ui.PictureRecorder();
    final into = Canvas(recorder);
    for (final filter in _filters.reversed) {
      into.saveLayer(rect, Paint()..imageFilter = filter);
    }
    _bottom!(into, _paint);
    for (var layer = 0; layer < _filters.length; layer += 1) {
      into.restore();
    }
    try {
      final made = rasterPicture(recorder, source.width, source.height);
      assert(() {
        debugChainRasters += 1;
        return true;
      }());
      _image = made;
      return made;
    } finally {
      _release();
      _bottom = null;
      _paint = Paint();
      _filters.clear();
    }
  }

  /// [shader] laid over the picture as a layer it filters.
  _Laying under(ui.FragmentShader shader) {
    _shaders.add(shader);
    _onTheBottom();
    _filters.add(ui.ImageFilter.shader(shader));
    return this;
  }

  /// [draw] over the picture as an image — and [input], the step's, beside
  /// it — in a raster of its own where it holds numbers past a byte, else as
  /// the bottom of the next picture.
  _Laying drawnBy(_LeadDraw draw, {required ui.Image? input}) {
    final image = this.image();
    final shader = draw.shade(image, input ?? image);
    if (draw.inFloats) {
      try {
        final sums = shadedRaster(
          shader,
          source.width,
          source.height,
          inFloats: true,
        );
        assert(() {
          debugChainRasters += 1;
          return true;
        }());
        return _Laying(source).._image = sums;
      } finally {
        shader.dispose();
        if (!identical(image, input)) {
          _releaseImage(image);
        }
      }
    }
    final next = _Laying._drawn(
      source,
      (into, paint) => into.drawRect(_rect, paint..shader = shader),
      paints: true,
    ).._shaders.add(shader);
    if (!identical(image, input)) {
      next._images.add(image);
    }
    return next;
  }

  /// The picture through [effect]'s plugin, as the stages a waiting route
  /// records through make it ([FxPluginStages.ranOver]) — itself where
  /// there are none, or the plugin's picture is still to come.
  _Laying ranThrough(
    ResolvedLayerEffect effect, {
    required double scale,
    required Rect paper,
  }) {
    final image = this.image();
    final ran = FxPluginStages.ranOver(
      image,
      effect,
      scale: scale,
      paper: paper,
    );
    if (ran == null) {
      return this;
    }
    _releaseImage(image);
    return _Laying(source).._image = ran;
  }

  /// The paper cut out of the picture and drawn through [blur], as the
  /// bottom of the next picture — a Gaussian's Repeat Edge Pixels on the
  /// paper's edge (🗣️I-132-Q14 a, [PaperEdgeEffect]).
  ///
  /// 🔬[blur]'s clamp repeats the edge of the image it is drawn with, and
  /// paints past it: so the paper is cut out as an image of its own, on whole
  /// pixels, and what is drawn of it is cut to it.
  _Laying cutAndBlurred({required Rect paper, required ui.ImageFilter blur}) {
    final image = this.image();
    final rect = _rect;
    final cut = paperOnWholePixels(paper).intersect(rect);
    // Past the paper nothing is left: a cut that misses the raster draws it
    // empty. A raster the paper holds whole — a row inside its page, the
    // usual case — is its own cut.
    final sheet = cut.width <= 0 || cut.height <= 0
        ? null
        : cut == rect
        ? image
        : _cutOut(image, cut);
    final next = _Laying._drawn(source, (into, _) {
      // 🚨THE LAYER IS AS LARGE AS WHAT IS DRAWN INTO IT
      // ([_composeInTheFrame]): nothing, `src`, over the whole raster first,
      // so a layer over a cut paper is the raster's.
      into.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.src
          ..color = const Color(0x00000000),
      );
      if (sheet != null) {
        into
          ..save()
          ..clipRect(cut)
          ..drawImage(
            sheet,
            cut.topLeft,
            // 1:1 at the identity: the blur is all the sampling there is.
            Paint()
              ..imageFilter = blur
              ..filterQuality = FilterQuality.none,
          )
          ..restore();
      }
    }, paints: false);
    next._images.add(image);
    if (sheet != null) {
      next._images.add(sheet);
    }
    return next;
  }

  /// [then] over the picture: on the draw under it where its paint can take
  /// it, with the outermost layer's filter where one is laid, else as a layer
  /// of its own where [layers] — or a raster blitted through it.
  _Laying then(CompositeEffectPaint then, {required bool layers}) {
    final filter = then.filter;
    if (filter == null) {
      return this;
    }
    if (_filters.isNotEmpty) {
      _filters.last = then.after(_filters.last);
      return this;
    }
    if (_image != null || !_paints) {
      if (layers && _image == null) {
        _filters.add(filter);
        return this;
      }
      _onTheBottom(blitting: image());
    }
    then.applyTo(_paint);
    _paints = false;
    return this;
  }

  /// Keeps [image] alive until the picture is recorded — at once where it
  /// already is.
  void keepUntilLaid(ui.Image? image) {
    if (image == null || identical(image, _image)) {
      return;
    }
    if (_image != null) {
      _releaseImage(image);
      return;
    }
    _images.add(image);
  }

  /// Releases what it holds, its image too where that is not [source] —
  /// for a chain that throws part way along.
  void discard() {
    _release();
    final held = _image;
    if (held != null) {
      _releaseImage(held);
    }
  }

  /// Makes the picture's image — or [blitting] — the bottom it draws, where
  /// the picture is an image.
  void _onTheBottom({ui.Image? blitting}) {
    final image = blitting ?? _image;
    if (image == null) {
      return;
    }
    _image = null;
    _images.add(image);
    _bottom = (into, paint) => _blitWhole(into, image, paint);
    _paints = true;
  }

  void _release() {
    for (final shader in _shaders) {
      shader.dispose();
    }
    _shaders.clear();
    for (final image in _images) {
      _releaseImage(image);
    }
    _images.clear();
  }

  void _releaseImage(ui.Image image) {
    if (!identical(image, source)) {
      image.dispose();
    }
  }
}

/// One draw a lead makes: a shader over the picture the draw before it made
/// and the step's input.
typedef _LeadDraw = ({
  ui.FragmentShader Function(ui.Image image, ui.Image input) shade,

  /// Whether the shader can filter a layer that holds the picture before it:
  /// it reads that picture as its first sampler, over its size as its first
  /// vec2 (`uSize`), and lays a colour — what the engine binds where a
  /// shader is a layer's filter.
  bool filtersALayer,

  /// Whether it reads the step's input beside the picture before it — which
  /// the step then holds as an image.
  bool readsInput,

  /// Whether it holds numbers past a byte ([RowSumPass]) — laid in floats,
  /// in a raster of its own.
  bool inFloats,
});

/// The shaders [lead] draws at [space], with [paper] where the paper lies
/// there, over rasters [rasterWidth] wide — none for a step that only
/// paints, nor for a blur on the paper ([PaperEdgeEffect]) or a plugin
/// ([PluginEffect], `_Laying.ranThrough`) — [row] the
/// row it reads on their grid, null for none.
List<_LeadDraw> _leadDraws(
  EffectStepLead? lead, {
  required DrawSpace space,
  required Rect paper,
  required int rasterWidth,
  required ui.Image? row,
}) => switch (lead) {
  null || PaperEdgeEffect() || PluginEffect() => const [],
  KeyRun(:final keys) => [
    for (final key in keys)
      (
        shade: (image, input) => ColourKeyShader.shaderFor(
          source: image,
          original: input,
          key: key,
        ),
        filtersALayer: true,
        readsInput: true,
        inFloats: false,
      ),
  ],
  ShadedEffect(:final effect) => [
    for (final pass in shadedPassesOf(
      effect,
      space,
      paper: paper,
      rasterWidth: rasterWidth,
    ))
      _passDraw(pass, row: row),
  ],
};

/// The draw [pass] is, reading [row] where it reads a row.
///
/// ⛔A camera lens blur's passes are not layers: its row sums hold numbers
/// past a byte, and its gather reads them as its first sampler.
_LeadDraw _passDraw(ShadedPass pass, {required ui.Image? row}) =>
    switch (pass) {
  LineBoxPass() => (
    shade: (image, _) =>
        DirectionalBlurShader.shaderFor(source: image, pass: pass),
    filtersALayer: true,
    readsInput: false,
    inFloats: false,
  ),
  RowSumPass() => (
    shade: (image, _) => IrisBlurShader.rowSumFor(source: image, pass: pass),
    filtersALayer: false,
    readsInput: false,
    inFloats: true,
  ),
  IrisGatherPass() => (
    shade: (image, input) => IrisBlurShader.gatherFor(
      sums: image,
      input: input,
      // A blur map that is none here: the blur at its whole radius.
      pass: row == null ? pass.unmapped : pass,
      map: row,
    ),
    filtersALayer: false,
    readsInput: true,
    inFloats: false,
  ),
};

/// [rect] of [image], on whole pixels, as an image of its own.
ui.Image _cutOut(ui.Image image, Rect rect) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    image,
    rect,
    Rect.fromLTWH(0, 0, rect.width, rect.height),
    Paint()..filterQuality = FilterQuality.none,
  );
  return rasterPicture(recorder, rect.width.toInt(), rect.height.toInt());
}

/// [image] into [into] whole, with [paint]: 1:1 by construction — src and
/// dst are the same rect, at the identity. A filter here would resample a
/// blit that is already aligned.
void _blitWhole(Canvas into, ui.Image image, Paint paint) {
  final rect = Rect.fromLTWH(
    0,
    0,
    image.width.toDouble(),
    image.height.toDouble(),
  );
  into.drawImageRect(
    image,
    rect,
    rect,
    paint..filterQuality = FilterQuality.none,
  );
}

/// Turns a finished recording into the image, hands [compose] a blit for it,
/// and owns its lifetime.
void _finishSubtreeRaster({
  required Canvas canvas,
  required ui.PictureRecorder recorder,
  required SubtreeRasterPlan plan,
  required void Function(BlitSubtree blit) compose,
  List<CompositeEffectStep> steps = const [],
  required Rect paper,
  SubtreeHold? held,
  RowPainter? rows,
  required int unrunBefore,
}) {
  assert(() {
    debugSubtreeRasterCount += 1;
    return true;
  }());
  final raster = rasterPicture(recorder, plan.pixelWidth, plan.pixelHeight);
  // ⛔BOTH stay alive until the compose is done. A crossfade blits the raw
  // scope and the stepped one in the same structure, and disposing the raw
  // one here would have left the unfiltered pass reading freed pixels.
  final image = applyEffectSteps(
    source: raster,
    steps: steps,
    // The sub-tree raster IS at plan.scale, so image pixels per canvas pixel
    // is that number — the one place where the raster's target scale and the
    // image's own resolution are the same thing by construction.
    imageScale: plan.scale,
    // Where the raster's corner lies, as it was recorded ([recordInto]).
    paper: _rectInPixels(
      paper,
      origin: plan.destination.topLeft,
      scale: plan.scale,
    ),
    rowOf: rows == null ? null : (row) => _rowOnTheGrid(rows, row, plan),
  );
  try {
    compose(
      (paint, {bool stepped = true}) => _blitSubtreeRaster(
        canvas: canvas,
        image: stepped ? image : raster,
        plan: plan,
        paint: paint,
      ),
    );
  } finally {
    // ⛔Not with a plugin's step in it drawn as if off ([FxPluginStages.
    // unrun]): the next round of the recording that missed it would cut
    // from this and never meet the step again.
    if (held != null &&
        held.keeps &&
        !plan.magnifies &&
        FxPluginStages.unrun == unrunBefore) {
      held._keep((plan: plan, raster: raster, image: image));
    }
    // ⚠️Safe HERE and nowhere earlier: the draws put the image into this
    // frame's display list and the engine holds its own claim from that
    // moment. What `dispose` releases is this handle, not the pixels the
    // list is going to replay.
    if (!identical(image, raster)) {
      image.dispose();
    }
    raster.dispose();
  }
}

/// Runs [plan]'s key steps over [image], which spans [canvasExtent] CANVAS
/// pixels across. Returns [image] itself when the chain is one draw, so the
/// caller disposes only what it got back and only when it differs.
///
/// 🚨★★★TWO SCALES, TWO QUESTIONS — and one parameter used to answer both.
///
/// A chain's blur radii are CANVAS pixels. Turning them into something a draw
/// can use takes two different numbers, and they are not the same number:
///
/// • **The PAINT's** scale is the space the DRAW lands in. A route drawing
///   under a canvas-space CTM leaves it 1 and lets Skia map the sigma through
///   the matrix; the playback cache draws into a raster-space canvas and
///   passes that raster's scale.
/// • **The STEPS'** scale is the IMAGE's own resolution — image pixels per
///   canvas pixel — because a step rasters the image at its own size, at the
///   identity, where there is no matrix to map anything.
///
/// They coincide wherever the image and the draw share a space, which is why
/// one `rasterScale` looked like enough for a long time. ⛔It is not, and the
/// track chain is where that showed: the playback PAINTER draws a Half or
/// Quarter cache up to canvas space, so its image is at one scale and its
/// draw at another. 유저 2026-08-28 read the two-scale note and said it looked
/// like trouble — it was, and this is the shape of it: **한 플래그가 두
/// 질문에 답하면 그것도 발명이다**.
///
/// ⇒ SO THE STEP SCALE IS DERIVED HERE, from the image and the extent it
/// covers, and no call site restates it. The paint scale stays a parameter of
/// the resolve, because only the caller knows what space it draws into.
///
/// 🚨THIS ALSO FIXED A WRONG NUMBER. The export's frame path had `1` written
/// in by hand, which is right at full size and wrong for a storyboard
/// thumbnail — `outputSize` scales the render down, so a keyed track chain
/// would have blurred at the wrong strength there.
///
/// [extent] is the rect of canvas space [image] stands for, and [paper]
/// where the paper lies there — what a blur repeating its edge reads past
/// ([PaperEdgeEffect]) — and [rows] paint the rows a step reads in it.
ui.Image steppedForChain({
  required ui.Image image,
  required CompositeEffectPlan plan,
  required Rect extent,
  required Rect paper,
  RowPainter? rows,
}) {
  if (plan.isSingleDraw) {
    return image;
  }
  final imageScale = extent.width <= 0 ? 1.0 : image.width / extent.width;
  // [image]'s grid, as a raster the walk plans lies on its own.
  final grid = SubtreeRasterPlan(
    bounds: extent,
    destination: extent,
    pixelWidth: image.width,
    pixelHeight: image.height,
    scale: imageScale,
    rasterScale: imageScale,
  );
  return applyEffectSteps(
    source: image,
    steps: plan.preSteps,
    imageScale: imageScale,
    paper: _rectInPixels(paper, origin: extent.topLeft, scale: imageScale),
    rowOf: rows == null ? null : (row) => _rowOnTheGrid(rows, row, grid),
  );
}

/// Where [rect] lies in the pixels of an image whose corner stands at
/// [origin], [scale] of its pixels a unit.
Rect _rectInPixels(
  Rect rect, {
  required Offset origin,
  required double scale,
}) => Rect.fromLTRB(
  (rect.left - origin.dx) * scale,
  (rect.top - origin.dy) * scale,
  (rect.right - origin.dx) * scale,
  (rect.bottom - origin.dy) * scale,
);
