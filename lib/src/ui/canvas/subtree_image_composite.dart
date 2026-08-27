import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'colour_key_shader.dart';
import 'composite_effect_paint.dart';

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

/// The grid a sub-tree rasterises on, decided once and then obeyed.
///
/// ⛔The arithmetic lives HERE and only here. Three walks composite a group —
/// the editing stack, the playback cache and the camera (which the export
/// renders through) — and one of them is async, so they cannot share a single
/// function body. They share this instead: a plan, and the blit that consumes
/// it. What differs between them is the six mechanical lines that drive a
/// `PictureRecorder`, and nothing that decides a pixel.
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
SubtreeRasterPlan? planSubtreeRaster({
  required Rect bounds,
  required double rasterScale,
  required int maxPixelSide,
}) {
  var scale = rasterScale;
  final side = bounds.width > bounds.height ? bounds.width : bounds.height;
  // 🚨THE SNAP IS PART OF THE CAP. Clamping the scale alone left the cap off
  // by one: `side * scale` landed exactly on the cap and then the OUTWARD
  // snap widened it, so the image came back one pixel over the limit it was
  // clamped to. The snap can add up to a whole device pixel at each edge, so
  // the room for both has to come out of the scale.
  final headroom = maxPixelSide - 2;
  if (side * scale > headroom) {
    // A view so magnified the sub-tree alone overflows the cap: shrink, the
    // way the display buffer does one level up. Still one uniform resample —
    // softer, never seamed, and never a second code path an effect could
    // miss.
    scale = headroom / side;
  }
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
void blitSubtreeRaster({
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
  required int maxPixelSide,
  required void Function(Canvas into, double rasterScale) paintSubtree,
  required void Function(BlitSubtree blit) compose,
  List<CompositeEffectStep> steps = const [],
}) {
  final plan = planSubtreeRaster(
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
  finishSubtreeRaster(
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
  required int maxPixelSide,
  required Future<void> Function(Canvas into, double rasterScale) paintSubtree,
  required void Function(BlitSubtree blit) compose,
  List<CompositeEffectStep> steps = const [],
}) async {
  final plan = planSubtreeRaster(
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
  finishSubtreeRaster(
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
  required double rasterScale,
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
    // ⛔Resolved HERE, at the raster's own scale. A blur's radii are canvas
    // pixels and this raster is device pixels, so the step that owns them is
    // the only place that knows the ratio.
    resolveCompositeEffectPaint(
      step.then,
      rasterScale: rasterScale,
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
    final stepPicture = stepRecorder.endRecording();
    final next = stepPicture.toImageSync(pixelWidth, pixelHeight);
    stepPicture.dispose();
    shader?.dispose();
    if (!identical(image, source)) {
      image.dispose();
    }
    image = next;
  }
  return image;
}

void finishSubtreeRaster({
  required Canvas canvas,
  required ui.PictureRecorder recorder,
  required SubtreeRasterPlan plan,
  required void Function(BlitSubtree blit) compose,
  List<CompositeEffectStep> steps = const [],
}) {
  final picture = recorder.endRecording();
  assert(() {
    debugSubtreeRasterCount += 1;
    return true;
  }());
  final raster = picture.toImageSync(plan.pixelWidth, plan.pixelHeight);
  picture.dispose();
  // ⛔BOTH stay alive until the compose is done. A crossfade blits the raw
  // scope and the stepped one in the same structure, and disposing the raw
  // one here would have left the unfiltered pass reading freed pixels.
  final image = applyEffectSteps(
    source: raster,
    steps: steps,
    pixelWidth: plan.pixelWidth,
    pixelHeight: plan.pixelHeight,
    rasterScale: plan.scale,
  );
  try {
    compose(
      (paint, {bool stepped = true}) => blitSubtreeRaster(
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
