import '../../core/tree_nodes.dart';
import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/composite_tree.dart';
import '../../models/cut_id.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_effect.dart';
import '../../services/cut_frame_composite_plan.dart'
    show CutFrameCompositeLayer;
import '../../services/layer_pose_matrix.dart' show LayerPlacement;
import '../../services/playback/cut_frame_composite_signature.dart';
import '../canvas/canvas_layer_stack_view.dart';
import 'frame_picture_store.dart' show FrameDrawing;

/// 🚨★★★WHAT A FRAME'S ONE PICTURE IS KEYED BY: THE TREE A SCREEN STACKS
/// FOR IT (one-picture-per-frame ②-1, D7-2-Q3=a).
///
/// The tree is the one the screen draws ([CanvasLayerStackView.nodes] —
/// the cut's own under the V row's fx, the track's SE rows, a drag in
/// flight, a movie where its file stands), each row reduced to what
/// changes its pixels, signed by the walk the plan's tree is signed by
/// ([CutFrameCompositeSignature.of]); and the page it is drawn on. ⛔Not the
/// plan's signature: the plan's tree knows none of what the screen stacks
/// round the cut, and a key that misses an input does not read stale — it
/// MERGES two pictures into one.
///
/// [cutId] says whose cels the rows are: every row of a stack is a cel of
/// the cut it stacks (`brushFrameKeyForCut`), and two cuts may hold cels of
/// one id — a duplicated cut — each at its own revision.
final class FramePictureKey {
  const FramePictureKey._({
    required this.cutId,
    required this.page,
    required this.signature,
  });

  final CutId cutId;
  final FramePage page;
  final CutFrameCompositeSignature signature;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FramePictureKey &&
          other.cutId == cutId &&
          other.page == page &&
          other.signature == signature;

  @override
  int get hashCode => Object.hash(cutId, page, signature);

  @override
  String toString() =>
      'FramePictureKey(cutId: $cutId, page: $page, signature: $signature)';
}

/// The key of the picture [nodes] — a stack of [cutId]'s, drawn on
/// [page] — draw ([FramePictureKey]); [revisionOf] is a cel's stored
/// revision.
///
/// ★The canvas standing on a frame and a run playing it ask ONE key: the
/// row a pen stands on is the cel it shows, as it is everywhere else
/// ([_stackedCelOf]).
FramePictureKey framePictureKeyOf(
  List<CompositeNode<CanvasStackRow>> nodes, {
  required CutId cutId,
  required FramePage page,
  required int Function(BrushFrameKey cel) revisionOf,
}) => FramePictureKey._(
  cutId: cutId,
  page: page,
  signature: CutFrameCompositeSignature.of(
    mapCompositeLeaves(nodes, (row) {
      final stacked = _stackedCelOf(row);
      return stacked == null
          ? null
          : CompositeLayerSignature(
              layerId: stacked.cel.layerId,
              frameId: stacked.cel.frameId,
              opacity: stacked.opacity,
              sourceRevision: revisionOf(stacked.cel),
              blendMode: stacked.blendMode,
              placement: stacked.placement,
              effects: stacked.effects,
            );
    }),
    canvasSize: page.canvasSize,
  ),
);

/// The picture [nodes] draw on [page], every row from its cel's stored
/// surface ([surfaceOf]; null where the cel has none) — by the canvas's own
/// body ([frameDrawingOf]), so it is what the canvas shows of them.
FrameDrawing stackedFrameDrawingOf(
  List<CompositeNode<CanvasStackRow>> nodes, {
  required FramePage page,
  required BitmapSurface? Function(BrushFrameKey cel) surfaceOf,
}) => frameDrawingOf(
  mapCompositeLeaves(nodes, (row) {
    final stacked = _stackedCelOf(row);
    final surface = stacked == null ? null : surfaceOf(stacked.cel);
    return stacked == null || surface == null
        ? null
        : CutFrameCompositeLayer(
            surface: surface,
            opacity: stacked.opacity,
            blendMode: stacked.blendMode,
            placement: stacked.placement,
            effects: stacked.effects,
          );
  }),
  page: page,
);

/// Every cel [nodes] — a stack of a frame's — draw, bottom to top: the cels
/// its key is signed by and its drawing reads ([_stackedCelOf]).
Iterable<BrushFrameKey> stackedCelsOf(
  List<CompositeNode<CanvasStackRow>> nodes,
) sync* {
  for (final node in preorderNodes(nodes)) {
    if (node case CompositeLeaf(:final payload)) {
      final stacked = _stackedCelOf(payload);
      if (stacked != null) {
        yield stacked.cel;
      }
    }
  }
}

/// [nodes] with only the rows whose cel the picture is [drawn] of — a row
/// left out dropped as [mapCompositeLeaves] drops one, by the reading the
/// key and the drawing take ([_stackedCelOf]), so a picture keyed by what
/// is left is the picture drawn of it.
List<CompositeNode<CanvasStackRow>> stackOfDrawnCels(
  List<CompositeNode<CanvasStackRow>> nodes, {
  required bool Function(BrushFrameKey cel) drawn,
}) => mapCompositeLeaves(nodes, (row) {
  final stacked = _stackedCelOf(row);
  return stacked == null || drawn(stacked.cel) ? row : null;
});

/// A row of a stack as a frame's picture takes it: the cel it draws, and
/// how.
typedef _StackedCel = ({
  BrushFrameKey cel,
  double opacity,
  LayerBlendMode blendMode,
  LayerPlacement? placement,
  List<ResolvedLayerEffect> effects,
});

/// [row] as [_StackedCel] — the ONE reading the key and the drawing both
/// take, so a row the key leaves out is a row the picture does not draw.
///
/// The row a pen stands on reads its cel's STORED pixels and revision, as
/// every other row does — a stroke still in hand is not stored, and the
/// picture is of what is. Standing on nothing exposed it has no cel, and
/// drops — as [mapCompositeLeaves] drops it, with a folder it leaves
/// empty.
///
/// ⛔A TINTED ROW IS AN ONION GHOST, which a stack lays round the frame
/// for the one canvas that edits it (`stackNodesWithGhosts`) and is no
/// part of the frame's picture (one-picture-per-frame-Q1). Handed one, this
/// says so rather than keying a picture the ghost is not drawn in.
_StackedCel? _stackedCelOf(CanvasStackRow row) => switch (row) {
  CanvasLayerImageRequest(tint: _?) => throw StateError(
    'An onion ghost is no part of a frame\'s picture.',
  ),
  CanvasLayerImageRequest(
    :final frameKey,
    :final opacity,
    :final blendMode,
    :final placement,
    :final effects,
  ) =>
    (
      cel: frameKey,
      opacity: opacity,
      blendMode: blendMode,
      placement: placement,
      effects: effects,
    ),
  CanvasActiveLayerRow(
    frameKey: final cel?,
    :final opacity,
    :final blendMode,
    :final placement,
    :final effects,
  ) =>
    (
      cel: cel,
      opacity: opacity,
      blendMode: blendMode,
      placement: placement,
      effects: effects,
    ),
  CanvasActiveLayerRow() => null,
};
