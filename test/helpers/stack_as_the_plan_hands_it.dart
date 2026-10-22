import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';

/// [nodes] as the plan hands a stack to the editing view
/// ([composeOverTheirBackdrops]): a row or a folder in an advanced blend is
/// composed over what lies below it in its scope, and paints normal itself.
///
/// The view only ever draws such a tree — a row left in multiply would be
/// asked for a paint blend no advanced mode has
/// (`LayerBlendMode.paintBlendMode`) — so a test that builds a stack by hand
/// hands it over this way, as the plan would.
List<CompositeNode<CanvasStackRow>> stackAsThePlanHandsIt(
  List<CompositeNode<CanvasStackRow>> nodes,
) => composeOverTheirBackdrops(
  nodes,
  blendOf: (row) => switch (row) {
    CanvasLayerImageRequest(:final blendMode) => blendMode,
    CanvasActiveLayerRow(:final blendMode) => blendMode,
  },
  paintedNormal: (row) => switch (row) {
    final CanvasLayerImageRequest image => CanvasLayerImageRequest(
      frameKey: image.frameKey,
      opacity: image.opacity,
      placement: image.placement,
      tint: image.tint,
      effects: image.effects,
    ),
    final CanvasActiveLayerRow live => CanvasActiveLayerRow(
      opacity: live.opacity,
      frameKey: live.frameKey,
      placement: live.placement,
      effects: live.effects,
    ),
  },
);
