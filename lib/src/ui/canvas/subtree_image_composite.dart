import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/draw_space.dart';
import '../../models/composite_tree.dart';
import '../../models/layer_blend_mode.dart';
import 'colour_key_shader.dart';
import 'display_resample.dart';
import 'image_pieces.dart';
import 'layer_blend_shader.dart';
import '../../services/composite_effect_paint.dart';
import '../../services/layer_pose_matrix.dart'
    show LayerPlacement, placementMatrix;
import 'raster_picture.dart';

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
/// It is one constant rather than one per route so the walks cannot
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
      final extent = extentOf(payload);
      final placement = placementOf(payload);
      return placement == null
          ? extent
          : MatrixUtils.transformRect(placementMatrix(placement), extent);
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

/// The grid a sub-tree rasterises on, decided once and then obeyed.
///
/// ⛔The arithmetic lives HERE and only here. Two walks composite a group —
/// the editing stack (playback's too, since 2026-10-10) and the camera
/// (which the export renders through). What they share is how big a group's
/// buffer is ([subtreeBufferBounds]) and `drawSubtreeAsImage`; the plan and
/// the blit are the machinery underneath and belong to this file alone.
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
  paint.filterQuality = plan.scale == plan.rasterScale
      ? FilterQuality.none
      : FilterQuality.low;
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
void drawSubtreeAsImage({
  required Canvas canvas,
  required Rect bounds,
  required double rasterScale,
  int maxPixelSide = maxSubtreeRasterSide,
  required void Function(Canvas into, double rasterScale) paintSubtree,
  required void Function(BlitSubtree blit) compose,
  List<CompositeEffectStep> steps = const [],
}) {
  final plan = _planSubtreeRaster(
    bounds: bounds,
    rasterScale: rasterScale,
    maxPixelSide: maxPixelSide,
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
  );
}

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
/// [LayerBlendShader] at the identity, and the result blitted the way a
/// group's raster is: it IS the backdrop and the row, composed, so it lands
/// plain.
///
/// The arithmetic is [drawSubtreeAsImage]'s — the same plan, the same blit
/// — so a blend at any depth sits on the grid a folder's buffer would.
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
/// ★[sourceAsIs] is the row's own image where the caller has one that the
/// row is, painted normal — one piece, at full strength, with nothing on
/// it. Where it lands texel for texel on the grid the shader draws on, the
/// shader samples it there and the row is not rasterised at all
/// ([_laidAsItIs]); anywhere else [paintSource] rasterises it as before.
void drawBlendOverBackdrop({
  required Canvas canvas,
  required Rect bounds,
  required double rasterScale,
  int maxPixelSide = maxSubtreeRasterSide,
  required void Function(Canvas into, double rasterScale) paintBackdrop,
  required void Function(Canvas into, double rasterScale) paintSource,
  ImagePiece? sourceAsIs,
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

  final asItIs = _laidAsItIs(plan, sourceAsIs);
  _BlendSource source({required bool onTheGrid}) => asItIs != null && onTheGrid
      ? (image: sourceAsIs!.image, at: asItIs, owned: false)
      : (
          image: rasterOf(paintSource),
          at: LayerBlendShader.wholeDraw,
          owned: true,
        );

  if (_readsInTheFrame(canvas, plan, shownWithin)) {
    _composeInTheFrame(
      canvas: canvas,
      plan: plan,
      rasterScale: rasterScale,
      paintBackdrop: paintBackdrop,
      source: source(onTheGrid: _layerIsTheGrid(canvas, plan)),
      blendMode: blendMode,
    );
    return;
  }
  _composeInARaster(
    canvas: canvas,
    plan: plan,
    backdrop: rasterOf(paintBackdrop),
    source: () => source(onTheGrid: true),
    blendMode: blendMode,
  );
}

/// [backdrop], rasterised on [plan]'s grid, and the row [source] makes
/// composed in a raster of [plan]'s size ([_composedOverBackdrop]) and
/// blitted the way a group's raster is — the route where the frame cannot
/// be read ([_readsInTheFrame]). It disposes [backdrop].
void _composeInARaster({
  required Canvas canvas,
  required SubtreeRasterPlan plan,
  required ui.Image backdrop,
  required _BlendSource Function() source,
  required LayerBlendMode blendMode,
}) {
  _BlendSource? row;
  ui.Image? composed;
  try {
    row = source();
    composed = _composedOverBackdrop(
      backdrop: backdrop,
      source: row,
      blendMode: blendMode,
      plan: plan,
    );
    _blitSubtreeRaster(
      canvas: canvas,
      image: composed,
      plan: plan,
      paint: Paint(),
    );
  } finally {
    // ⚠️Safe here, as in [_finishSubtreeRaster]: the blit put the image into
    // this frame's display list, which holds its own claim from then on.
    composed?.dispose();
    if (row != null && row.owned) {
      row.image.dispose();
    }
    backdrop.dispose();
  }
}

/// The row a blend composes, as the shader is handed it: an image, where it
/// lies on the draw in the draw's own 0..1, and whether the draw made it
/// (a raster of the row) or only borrows it (the row's own image).
typedef _BlendSource = ({ui.Image image, Rect at, bool owned});

/// Whether a row's own image is handed to the shader as it is where it can
/// be ([drawBlendOverBackdrop]'s `sourceAsIs`). Off, every row is
/// rasterised — the route a test holds the bytes against.
@visibleForTesting
bool debugSourceAsIs = true;

/// Where [sourceAsIs] lies on [plan]'s grid in the draw's own 0..1, when it
/// lands there texel for texel ([landsTexelForTexel]) — a raster of it would
/// be its texels, copied, with nothing past its edge, so the shader samples
/// the image instead. Null anywhere else.
Rect? _laidAsItIs(SubtreeRasterPlan plan, ImagePiece? sourceAsIs) {
  // A grid the cap shrank is not the one the row's draw would have laid it
  // on (`texelScale` is the scale the walk asked for), so it is drawn.
  if (sourceAsIs == null ||
      !debugSourceAsIs ||
      plan.scale != plan.rasterScale) {
    return null;
  }
  final (:image, :worldRect) = sourceAsIs;
  if (!landsTexelForTexel(image, worldRect, plan.scale)) {
    return null;
  }
  final width = plan.pixelWidth.toDouble();
  final height = plan.pixelHeight.toDouble();
  return Rect.fromLTWH(
    ((worldRect.left - plan.destination.left) * plan.scale).roundToDouble() /
        width,
    ((worldRect.top - plan.destination.top) * plan.scale).roundToDouble() /
        height,
    image.width / width,
    image.height / height,
  );
}

/// Whether the layer read in the frame is [plan]'s own grid — a device
/// pixel a raster pixel — so a row laid texel for texel on the one is on
/// the other. Drawn on a screen past the raster's scale, the layer has more
/// pixels than the raster, and a row is rasterised on the raster's grid as
/// it was.
bool _layerIsTheGrid(Canvas canvas, SubtreeRasterPlan plan) {
  final m = canvas.getTransform();
  bool same(double v) => (v - plan.scale).abs() < 1e-6;
  return same(m[0]) && same(m[5]);
}

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
/// [source] — rasterised on [plan]'s grid, which the layer lands on, or the
/// row's own image laid texel for texel on it — is the other picture. One
/// raster where the backdrop's route makes three, or none, and none of them
/// waits on the frame.
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
  required _BlendSource source,
  required LayerBlendMode blendMode,
}) {
  assert(() {
    debugBlendsReadInTheFrame += 1;
    debugLastSubtreeRaster = plan;
    return true;
  }());
  final shader = LayerBlendShader.filterFor(
    source: source.image,
    mode: blendMode,
    sourceRect: source.at,
  );
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
    if (source.owned) {
      source.image.dispose();
    }
  }
}

/// [source] composed over [backdrop] through [blendMode], as one raster of
/// [plan]'s size — a step AT THE IDENTITY, as a colour key's is
/// ([applyEffectSteps]): the shader reads `FlutterFragCoord()`, so it draws
/// 1:1 into a rect at the origin, where its coordinates are the images'.
ui.Image _composedOverBackdrop({
  required ui.Image backdrop,
  required _BlendSource source,
  required LayerBlendMode blendMode,
  required SubtreeRasterPlan plan,
}) {
  final width = plan.pixelWidth.toDouble();
  final height = plan.pixelHeight.toDouble();
  final shader = LayerBlendShader.shaderFor(
    backdrop: backdrop,
    source: source.image,
    mode: blendMode,
    width: width,
    height: height,
    sourceRect: source.at,
  );
  try {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..shader = shader,
    );
    return rasterPicture(recorder, plan.pixelWidth, plan.pixelHeight);
  } finally {
    shader.dispose();
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
