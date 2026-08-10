import '../models/layer_effect.dart' show LayerEffect, resolveLayerEffectsAt;
import 'canvas/composite_effect_paint.dart'
    show CompositeEffectPaint, resolveCompositeEffectPaint;

/// The V row's EFFECT chain as paint state, for every route that draws a cut.
///
/// This file was `storyboard_cut_fade_policy.dart` and held the V row's whole
/// transform: the canonical fade shape the block-edge handles wrote, the pose
/// resolution, the cut-window projection and the camera↔canvas pose remap. All
/// of it went with the transform teardown — a track's pose was AE precomp for
/// stacking one track on the stage, and its fade is F.I/F.O spans on the
/// transition row now, where the span's length IS the ramp.
///
/// What survived is the effect chain, so the file says that instead.

/// The V track's EFFECT chain as paint state at GLOBAL [frameIndex] — the
/// filter that lands on the whole composited cut, resolved the one way for
/// every route that draws one (the editing track stack, playback, export).
///
/// [rasterScale] follows [resolveCompositeEffectPaint]'s contract: 1 wherever
/// the cut is drawn into CANVAS space (a blur radius is canvas pixels and
/// Skia maps the sigma through the CTM), and the raster ratio where a route
/// draws pre-scaled pixels 1:1.
///
/// [enabled] is the V row's fx master ([Track.fxEnabled]): off bypasses the
/// chain. It has nothing else left to bypass.
CompositeEffectPaint trackEffectPaintAt(
  List<LayerEffect> effects,
  int frameIndex, {
  bool enabled = true,
  double rasterScale = 1,
}) {
  if (!enabled || effects.isEmpty) {
    return CompositeEffectPaint.none;
  }
  return resolveCompositeEffectPaint(
    resolveLayerEffectsAt(effects: effects, frameIndex: frameIndex),
    rasterScale: rasterScale,
  );
}
