import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/draw_space.dart';
import 'colour_key_shader.dart';
import '../../services/composite_effect_paint.dart';
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
/// It is one constant rather than one per route so the three walks cannot
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

/// The grid a sub-tree rasterises on, decided once and then obeyed.
///
/// ⛔The arithmetic lives HERE and only here. Three walks composite a group —
/// the editing stack, the playback cache and the camera (which the export
/// renders through) — and one of them is async, so they cannot share a single
/// function body. What they share is `drawSubtreeAsImage` and its async twin,
/// which differ by one `await` and nothing that decides a pixel; the plan and
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

  /// Put a recorder's canvas into the sub-tree's own space, so whatever paints
  /// into it does not know it is being rasterised.
  void applyTo(Canvas into) {
    into.scale(scale);
    into.translate(-destination.left, -destination.top);
  }
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
SubtreeRasterPlan? _planSubtreeRaster({
  required Rect bounds,
  required double rasterScale,
  int maxPixelSide = maxSubtreeRasterSide,
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
  final destination = Rect.fromLTRB(
    (bounds.left * scale).floorToDouble() / scale,
    (bounds.top * scale).floorToDouble() / scale,
    (bounds.right * scale).ceilToDouble() / scale,
    (bounds.bottom * scale).ceilToDouble() / scale,
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
///
/// This is the SYNCHRONOUS form. A walk that awaits its children calls
/// [drawSubtreeAsImageAsync]; the two differ by one `await` and share every
/// line that decides a pixel.
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
  final into = Canvas(recorder);
  plan.applyTo(into);
  paintSubtree(into, plan.scale);
  _finishSubtreeRaster(
    canvas: canvas,
    recorder: recorder,
    plan: plan,
    compose: compose,
    steps: steps,
  );
}

/// The [drawSubtreeAsImage] a walk that awaits its children can use.
Future<void> drawSubtreeAsImageAsync({
  required Canvas canvas,
  required Rect bounds,
  required double rasterScale,
  int maxPixelSide = maxSubtreeRasterSide,
  required Future<void> Function(Canvas into, double rasterScale) paintSubtree,
  required void Function(BlitSubtree blit) compose,
  List<CompositeEffectStep> steps = const [],
}) async {
  final plan = _planSubtreeRaster(
    bounds: bounds,
    rasterScale: rasterScale,
    maxPixelSide: maxPixelSide,
  );
  if (plan == null) {
    return;
  }
  final recorder = ui.PictureRecorder();
  final into = Canvas(recorder);
  plan.applyTo(into);
  await paintSubtree(into, plan.scale);
  _finishSubtreeRaster(
    canvas: canvas,
    recorder: recorder,
    plan: plan,
    compose: compose,
    steps: steps,
  );
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
