import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/draw_space.dart';
import '../../models/composite_tree.dart';
import '../../models/layer_effect.dart' show ResolvedLayerEffect;
import '../../models/layer_id.dart';
import 'colour_key_shader.dart';
import 'directional_blur_shader.dart';
import 'iris_blur_shader.dart';
import 'display_resample.dart';
import 'fx_plugin_stages.dart';
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
/// ⛔The arithmetic lives HERE and only here. What a caller asks is how big
/// a group's buffer is ([subtreeBufferBounds]) and `drawSubtreeAsImage`; the
/// plan and the blit are the machinery underneath and belong to this file
/// alone.
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
/// [cell] is the grid what [compose] blits with reads the raster by
/// ([rasterCellFor]).
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
  final recorder = ui.PictureRecorder();
  paintSubtree(plan.recordInto(recorder), plan.scale);
  _finishSubtreeRaster(
    canvas: canvas,
    recorder: recorder,
    plan: plan,
    compose: compose,
    steps: steps,
    paper: paper,
    rows: rows,
  );
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
          .cutAndBlurred(paper: paper, blur: blur.filter)
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
      // 🚨THE LAYER IS AS LARGE AS WHAT IS DRAWN INTO IT: nothing, `src`,
      // over the whole raster first, so a layer over a cut paper is the
      // raster's.
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
  RowPainter? rows,
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
