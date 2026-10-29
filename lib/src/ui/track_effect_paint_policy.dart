import '../models/composite_tree.dart';
import '../models/layer_blend_mode.dart';
import '../models/layer_effect.dart'
    show LayerEffect, ResolvedLayerEffect, resolveLayerEffectsAt;

/// The V row's EFFECT chain, for every route that draws a cut.
///
/// This file was `storyboard_cut_fade_policy.dart` and held the V row's whole
/// transform: the canonical fade shape the block-edge handles wrote, the pose
/// resolution, the cut-window projection and the camera↔canvas pose remap. All
/// of it went with the transform teardown — a track's pose was AE precomp for
/// stacking one track on the stage, and its fade is F.I/F.O spans on the
/// transition row now, where the span's length IS the ramp.
///
/// What survived is the effect chain, so the file says that instead.

/// The V track's chain SAMPLED at GLOBAL [frameIndex] — the effects that land
/// on the whole composited cut, resolved the one way for every route that
/// draws one (the editing track stack, playback, export).
///
/// 🚨★★★A CHAIN, NOT A PAINT — and that was the bug this replaced.
///
/// This used to hand back a `CompositeEffectPaint`, resolved here. A colour
/// key has no paint form (it is a threshold, and a threshold has no colour
/// matrix), so the resolver REFUSES one — by assert. A track chain with a
/// colour key in it therefore threw, exactly as the live layer's did until
/// #1314. It was unreachable only while the fx menu added to the active
/// layer alone; "no caller" is not a design, and the menu reaches the V row
/// now (layer-menu-strings-outlive-their-entries-Q1).
///
/// ⛔SO THE HALVES ARE TAKEN AT THE DRAW, like every other row. A layer row
/// hands `List<ResolvedLayerEffect>` to `drawPosedLayerImage`, which builds
/// the plan where it knows the raster it is drawing into. A track row now
/// does the same thing, which is also why `rasterScale` left this file: it
/// was never this function's to know.
///
/// [enabled] is the V row's fx master ([Track.fxEnabled]): off bypasses the
/// chain. It has nothing else left to bypass.
List<ResolvedLayerEffect> trackEffectsAt(
  List<LayerEffect> effects,
  int frameIndex, {
  bool enabled = true,
}) {
  if (!enabled || effects.isEmpty) {
    return const <ResolvedLayerEffect>[];
  }
  return resolveLayerEffectsAt(effects: effects, frameIndex: frameIndex);
}

/// [cutNodes] under the V row's chain [effects] ([trackEffectsAt]) — one
/// group around the cut's picture, composed by the folder's own buffer law,
/// so the chain lands on the picture and never on the paper or on what is
/// laid over it. Every route that draws a cut wraps it here: the canvas,
/// playback and the parked track stack (`EditingCanvas.playedStackAt`), and
/// a film's frames.
///
/// ↩️A film filtered the cut's FINISHED picture instead (the painter's
/// `cutEffects`, a canvas-size frame's chain): the same chain, on an image
/// that was the canvas at full size — until the export drew the cut
/// through its camera as the canvas does (card video-export-speed-Q2).
List<CompositeNode<T>> underTheCutsFx<T>(
  List<CompositeNode<T>> cutNodes,
  List<ResolvedLayerEffect> effects,
) {
  if (effects.isEmpty || cutNodes.isEmpty) {
    return cutNodes;
  }
  return [
    CompositeGroup<T>(
      children: cutNodes,
      opacity: 1,
      blendMode: LayerBlendMode.normal,
      effects: effects,
    ),
  ];
}
