import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/draw_space.dart';
import '../../core/lru.dart';
import '../../models/composite_tree.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/rgba_image_bytes.dart';
import 'colour_key_shader.dart';
import 'display_resample.dart';
import 'layer_blend_shader.dart';
import '../../services/composite_effect_paint.dart';
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

/// The grid [bounds] rasterises on at [rasterScale], or null when there is
/// nothing to draw.
///
/// 📐The image grid is the LOCAL space at [rasterScale] snapped OUTWARD, and
/// [SubtreeRasterPlan.destination] is exactly `pixels / scale`. A src/dst pair
/// that disagreed by a fraction would resample the sub-tree a second time.
///
/// [within] cuts the image to the part of [bounds] that can land — what the
/// canvas still shows — on the same grid: the scale is still the whole
/// [bounds]' and the grid is counted from the origin, so a part samples
/// where the whole would.
SubtreeRasterPlan? _planSubtreeRaster({
  required Rect bounds,
  required double rasterScale,
  int maxPixelSide = maxSubtreeRasterSide,
  Rect within = Rect.largest,
}) {
  // 🚨THE SNAP IS PART OF THE CAP. Clamping the scale alone left the cap off
  // by one: `side * scale` landed exactly on the cap and then the OUTWARD
  // snap widened it, so the image came back one pixel over the limit it was
  // clamped to. The snap can add up to a whole device pixel at each edge, so
  // the room for both has to come out of the scale.
  //
  // A view so magnified the sub-tree alone overflows the cap shrinks the
  // way the display buffer does one level up — the same [scaleFittingSide],
  // now literally.
  final scale = scaleFittingSide(
    scale: rasterScale,
    bounds: bounds.size,
    maxSide: (maxPixelSide - 2).toDouble(),
  );
  final destination = rectOutwardOnGrid(bounds.intersect(within), scale);
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
/// a whole one is kept ([HeldSubtreeRasters]).
void drawSubtreeAsImage({
  required Canvas canvas,
  required Rect bounds,
  required double rasterScale,
  int maxPixelSide = maxSubtreeRasterSide,
  required void Function(Canvas into, double rasterScale) paintSubtree,
  required void Function(BlitSubtree blit) compose,
  List<CompositeEffectStep> steps = const [],
  SubtreeHold? held,
}) {
  final plan = _planSubtreeRaster(
    bounds: bounds,
    rasterScale: rasterScale,
    maxPixelSide: maxPixelSide,
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
  final recorder = ui.PictureRecorder();
  paintSubtree(plan.recordInto(recorder), plan.scale);
  _finishSubtreeRaster(
    canvas: canvas,
    recorder: recorder,
    plan: plan,
    compose: compose,
    steps: steps,
    held: held,
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
    return destination.expandToInclude(plan.destination) == destination
        ? whole
        : null;
  }

  /// Whether a picture of [bounds] at [rasterScale] is held to be cut from,
  /// or one drawn of it now — with no steps on it — would be kept: where
  /// neither, a picture of what could be drawn in place is drawn for
  /// nothing.
  bool findsOrKeeps(Rect bounds, double rasterScale) {
    final plan = _planSubtreeRaster(bounds: bounds, rasterScale: rasterScale);
    return plan != null &&
        (covering(plan) != null ||
            keeps &&
                !plan.magnifies &&
                _shelf._fits(
                  estimatedImageBytes(plan.pixelWidth, plan.pixelHeight),
                ));
  }
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
/// one ([bytes]) — 🗣️유저 2026-10-27 (Q2 = c) 「그리는 행 아래 · 위를 한 장씩
/// 묶어 든다」. ⛔Not one: what lies below is drawn first as a frame is
/// laid, and the nodes over it kept after would push it out first. One
/// raster past its shelf is not kept at all: it is drawn as it was before.
final class HeldSubtreeRasters {
  HeldSubtreeRasters({
    required int Function() bytes,
    int Function() bytesBelow = _none,
  }) : _nodes = _HeldShelf(bytes),
       _below = _HeldShelf(bytesBelow);

  final _HeldShelf _nodes;
  final _HeldShelf _below;

  static int _none() => 0;

  /// How many rasters are held.
  int get length => _nodes._held.length + _below._held.length;

  /// What the rasters held weigh ([estimatedImageBytes]).
  int get heldBytes => _nodes._held.held + _below._held.held;

  /// Lets go of every raster held.
  void clear() {
    _nodes._clear();
    _below._clear();
  }
}

/// One shelf of [HeldSubtreeRasters]: the least recently used let go of
/// first, past [_bytes].
final class _HeldShelf {
  _HeldShelf(int Function() bytes)
    : _bytes = bytes,
      _held = Lru(
        limit: bytes,
        costOf: _bytesOf,
        letGo: (_, held) => _letGo(held),
      );

  final int Function() _bytes;
  final Lru<Object, HeldSubtreeRaster> _held;

  bool _fits(int bytes) => bytes <= _bytes();

  /// Keeps [drawn] for [key] in handles of its own — the caller lets go of
  /// its own — where it fits.
  void _keep(Object key, HeldSubtreeRaster drawn) {
    if (!_fits(_bytesOf(drawn))) {
      return;
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
      _letGo(replaced);
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

  static void _letGo(HeldSubtreeRaster held) {
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
  SubtreeHold? held,
}) => drawSubtreeAsImage(
  canvas: canvas,
  bounds: bounds,
  rasterScale: rasterScale,
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
    final recorder = ui.PictureRecorder();
    _shadeTheGrid(Canvas(recorder), plan, shader);
    composed = rasterPicture(recorder, plan.pixelWidth, plan.pixelHeight);
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

/// Turns a finished recording into the image, hands [compose] a blit for it,
/// and owns its lifetime.
/// Runs [steps] over [source], returning a NEW image the caller owns, or
/// [source] itself when there is nothing to do.
///
/// 🚨EACH STEP IS ITS OWN RASTER, AT THE IDENTITY. A colour key is a fragment
/// shader, and a shader reads `FlutterFragCoord()` — the position in the
/// space it is drawn into. Folding one into a draw that sits under a
/// transform would make it read through that transform. Rasterising the step
/// by itself, 1:1 into a rect at the origin, is what makes the shader's own
/// coordinates mean what it thinks they mean.
///
/// A step's key and its painted effects share ONE raster: a `ui.Paint`
/// applies its shader, then its colour filter, then its image filter, so
/// "key, then blur" needs no second pass.
ui.Image applyEffectSteps({
  required ui.Image source,
  required List<CompositeEffectStep> steps,
  required int pixelWidth,
  required int pixelHeight,
  required double imageScale,
}) {
  var image = source;
  for (final step in steps) {
    final stepRecorder = ui.PictureRecorder();
    final into = Canvas(stepRecorder);
    final paint = Paint();
    final key = step.key;
    ui.FragmentShader? shader;
    if (key != null) {
      shader = ColourKeyShader.shaderFor(
        source: image,
        key: key,
        width: pixelWidth.toDouble(),
        height: pixelHeight.toDouble(),
      );
      paint.shader = shader;
    }
    // ⛔Resolved HERE, in the IMAGE's own space. A step rasters at the
    // identity — there is no CTM to map a sigma through — so the chain
    // arrives pre-multiplied by however many image pixels a canvas pixel is.
    resolveCompositeEffectPaint(
      step.then,
      space: imageScale == 1
          ? DrawSpace.canvas
          : DrawSpace.preScaled(imageScale),
    ).applyTo(paint);
    final rect = Rect.fromLTWH(
      0,
      0,
      pixelWidth.toDouble(),
      pixelHeight.toDouble(),
    );
    if (shader == null) {
      // 1:1 by construction — src and dst are the same rect, at the
      // identity. A filter here would resample a blit that is already
      // aligned.
      paint.filterQuality = FilterQuality.none;
      into.drawImageRect(image, rect, rect, paint);
    } else {
      // With a shader the image IS the shader's source, so the draw is a
      // plain rect over it.
      into.drawRect(rect, paint);
    }
    // ⚠️`toImageSync` throws, and a throw here used to keep BOTH the picture
    // and the shader — this loop runs once per effect step, so a failure part
    // way along a chain leaked every step it had already built. The picture's
    // release is [rasterPicture]'s; the shader's is this frame's own.
    final ui.Image next;
    try {
      next = rasterPicture(stepRecorder, pixelWidth, pixelHeight);
    } finally {
      shader?.dispose();
    }
    if (!identical(image, source)) {
      image.dispose();
    }
    image = next;
  }
  return image;
}

void _finishSubtreeRaster({
  required Canvas canvas,
  required ui.PictureRecorder recorder,
  required SubtreeRasterPlan plan,
  required void Function(BlitSubtree blit) compose,
  List<CompositeEffectStep> steps = const [],
  SubtreeHold? held,
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
    pixelWidth: plan.pixelWidth,
    pixelHeight: plan.pixelHeight,
    // The sub-tree raster IS at plan.scale, so image pixels per canvas pixel
    // is that number — the one place where the raster's target scale and the
    // image's own resolution are the same thing by construction.
    imageScale: plan.scale,
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
    if (held != null && held.keeps && !plan.magnifies) {
      held._shelf._keep(held.key, (plan: plan, raster: raster, image: image));
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
ui.Image steppedForChain({
  required ui.Image image,
  required CompositeEffectPlan plan,
  required double canvasExtent,
}) {
  if (plan.isSingleDraw) {
    return image;
  }
  return applyEffectSteps(
    source: image,
    steps: plan.preSteps,
    pixelWidth: image.width,
    pixelHeight: image.height,
    imageScale: canvasExtent <= 0 ? 1 : image.width / canvasExtent,
  );
}
