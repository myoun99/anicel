import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/fx_plugin_binding.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';

/// How a route reads each row's cel: its surface ([surfaces]), and
/// what runs the plugins the row's chain runs ([plugins]) — null for a
/// route that runs none.
typedef CelReading = ({
  LayerFrameSurfaceResolver surfaces,
  FxPluginBinding? plugins,
});

/// [resolveCutFrameCompositeTree] with each leaf's surface resolved;
/// entries whose frame has no artwork drop out, and a group left empty by
/// that drops with them (an empty buffer is a wasted saveLayer) — save one
/// a cel number is written on, which stands bare ([mapCompositeLeaves]).
///
/// [reading]: how each row's cel is read ([CelReading]). [ghostsOf]: each
/// row's ghosts, as [resolveCutFrameCompositeTree] places them.
List<CompositeNode<CutFrameCompositeLayer>> planCutFrameCompositeTree({
  required Cut cut,
  required int frameIndex,
  required CelReading reading,
  List<CutFrameCompositeGhost> Function(Layer row)? ghostsOf,
}) => _withSurfaces(
  resolveCutFrameCompositeTree(
    cut: cut,
    frameIndex: frameIndex,
    ghostsOf: ghostsOf,
  ),
  cut: cut,
  frameIndex: frameIndex,
  reading: reading,
);

/// [nodes] of [cut] with each leaf's surface read by [reading]
/// ([planCutFrameCompositeTree]), and every chain's plugins run as it says.
List<CompositeNode<CutFrameCompositeLayer>> _withSurfaces(
  List<CompositeNode<CutFrameCompositeRow>> nodes, {
  required Cut cut,
  required int frameIndex,
  required CelReading reading,
}) {
  List<ResolvedLayerEffect> boundAt(List<ResolvedLayerEffect> chain, int at) =>
      reading.plugins?.call(chain, cut: cut, frameIndex: at) ?? chain;
  List<ResolvedLayerEffect> bound(List<ResolvedLayerEffect> chain) =>
      boundAt(chain, frameIndex);
  // Laid as the canvas lays it (`EditingStackMap`): at its peg's strength
  // and tint, no pose, its chain run at the frame its peg reaches.
  CutFrameCompositeLayer? ghostOf(
    CutFrameCompositeGhost ghost,
    LayerFrameSurfaceResolver surfaceOf,
  ) {
    final cel = ghost.layer.frameById(ghost.frameId);
    final surface = cel == null ? null : surfaceOf(ghost.layer, cel);
    return surface == null
        ? null
        : CutFrameCompositeLayer(
            surface: surface,
            opacity: ghost.opacity,
            blendMode: ghost.blendMode,
            effects: boundAt(ghost.effects, ghost.frameIndex),
            tint: ghost.tint,
          );
  }

  CutFrameCompositeLayer? layerOf(
    CutFrameCompositeRow row,
    LayerFrameSurfaceResolver surfaceOf,
  ) => switch (row) {
    // ⛔THIS ROUTE HAS NO LIVE PIXELS. Only the editing stack asks the
    // tree for a live row, and only it owns the surface to fill the slot
    // with; every other route resolves surfaces from stored frames.
    // Reached here it would be a caller handing a live row to a route
    // that cannot draw it, so it contributes nothing rather than guessing.
    CutFrameCompositeLiveRow() => null,
    CutFrameCompositeGhost() => ghostOf(row, surfaceOf),
    CutFrameCompositeEntry() => switch (surfaceOf(row.layer, row.frame)) {
      final surface? => CutFrameCompositeLayer(
        surface: surface,
        opacity: row.opacity,
        blendMode: row.blendMode,
        placement: row.placement,
        effects: bound(row.effects),
      ),
      null => null,
    },
  };

  return List.unmodifiable(
    mapCompositeLeaves(
      nodes,
      (row) => layerOf(row, reading.surfaces),
      bare: (row) =>
          layerOf(row, (_, _) => BitmapSurface(canvasSize: cut.canvasSize)),
      chains: bound,
    ),
  );
}
