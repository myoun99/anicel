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

/// 🚨★★★WHAT A FRAME'S ONE PICTURE IS KEYED BY: THE TREE A SCREEN STACKS
/// FOR IT (one-picture-per-frame ②-1, D7-2-Q3=a).
///
/// The tree is the one the screen draws (`FramePictureView.nodes` —
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
    this.standingFor,
  });

  final CutId cutId;
  final FramePage page;
  final CutFrameCompositeSignature signature;

  /// The screen whose own picture of the frame this is — null for the
  /// frame's, the one every screen and run asks for.
  final Object? standingFor;

  /// 🚨[screen]'s own picture of this frame: what the frame stores, with
  /// what that screen's live rows show over it and no cel stores — a
  /// stamp's ghost, a stroke on its way (`FramePictureView`). Equal to no
  /// key another screen can ask for, so what only one screen shows is in
  /// no picture another reads. ↩️Patched under the frame's own key, a ghost
  /// the screen left with stayed in the frame's picture, shown wherever the
  /// frame was shown next (F-473, 유저 2026-10-26 「들고있다가 다른프레임
  /// 이동하면 남아있음 … 제대로 층 안나눈게 혹시 원인인가?」).
  FramePictureKey standingOn(Object screen) => FramePictureKey._(
    cutId: cutId,
    page: page,
    signature: signature,
    standingFor: screen,
  );

  /// The frame's own key — the one this stands on for a screen
  /// ([standingOn]), or this.
  FramePictureKey get ofTheFrame => standingFor == null
      ? this
      : FramePictureKey._(cutId: cutId, page: page, signature: signature);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FramePictureKey &&
          other.cutId == cutId &&
          other.page == page &&
          other.signature == signature &&
          identical(other.standingFor, standingFor);

  @override
  int get hashCode =>
      Object.hash(cutId, page, signature, identityHashCode(standingFor));

  @override
  String toString() =>
      'FramePictureKey(cutId: $cutId, page: $page, signature: $signature'
      '${standingFor == null ? '' : ', standing for $standingFor'})';
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
          : _signatureOf(stacked, revisionOf(stacked.cel));
    }),
    canvasSize: page.canvasSize,
  ),
);

/// [stacked] as a frame's picture is signed by it, its cel at [revision]
/// — the key's rows ([framePictureKeyOf]) and the drawing's
/// ([stackedFrameOf]), one reading.
CompositeLayerSignature _signatureOf(_StackedCel stacked, int revision) =>
    CompositeLayerSignature(
      layerId: stacked.cel.layerId,
      frameId: stacked.cel.frameId,
      opacity: stacked.opacity,
      sourceRevision: revision,
      blendMode: stacked.blendMode,
      placement: stacked.placement,
      effects: stacked.effects,
      tint: stacked.tint,
    );

/// [nodes] on [page] as the canvas's own body draws them ([StackedFrame]):
/// every row from its cel's stored surface ([surfaceOf]) — save, under
/// [live], the rows a canvas that stands holds live. A row with none that
/// a cel number is written on stands bare ([mapCompositeLeaves]).
///
/// Under [held], its nodes find the pictures they were drawn into before
/// ([HeldNodePictures]) — each row signed as the frame's key signs it, its
/// cel at the revision [held] reads ([framePictureKeyOf]).
StackedFrame stackedFrameOf(
  List<CompositeNode<CanvasStackRow>> nodes, {
  required FramePage page,
  required BitmapSurface? Function(BrushFrameKey cel) surfaceOf,
  ({LiveRows rows, LiftedRowPainters painters})? live,
  ({HeldNodePictures pictures, int Function(BrushFrameKey cel) revisionOf})?
  held,
}) {
  StoredRow? rowOf(
    CanvasStackRow row,
    BitmapSurface? Function(BrushFrameKey cel) surfaceOf,
  ) {
    final stacked = _stackedCelOf(row);
    final surface = stacked == null ? null : surfaceOf(stacked.cel);
    return stacked == null || surface == null
        ? null
        : (
            layer: CutFrameCompositeLayer(
              surface: surface,
              opacity: stacked.opacity,
              blendMode: stacked.blendMode,
              placement: stacked.placement,
              effects: stacked.effects,
            ),
            tint: stacked.tint,
            ghost: row is CanvasGhostImageRequest,
            signature: switch (held) {
              (:final revisionOf, pictures: _) => _signatureOf(
                stacked,
                revisionOf(stacked.cel),
              ),
              null => null,
            },
          );
  }

  return StackedFrame.of(
    nodes,
    page: page,
    storedRowOf: (row) => rowOf(row, surfaceOf),
    bareRowOf: (row) =>
        rowOf(row, (_) => BitmapSurface(canvasSize: page.canvasSize)),
    live: live,
    held: held?.pictures,
  );
}

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
/// is left is the picture drawn of it. One a cel number is written on
/// stands bare, as what the letters are written on alone: the key signs it
/// there, and a drawing that reads none of its cel lays it bare
/// ([stackedFrameOf]).
List<CompositeNode<CanvasStackRow>> stackOfDrawnCels(
  List<CompositeNode<CanvasStackRow>> nodes, {
  required bool Function(BrushFrameKey cel) drawn,
}) => mapCompositeLeaves(
  nodes,
  (row) {
    final stacked = _stackedCelOf(row);
    return stacked == null || drawn(stacked.cel) ? row : null;
  },
  bare: (row) => row,
);

/// A row of a stack as a frame's picture takes it: the cel it draws, and
/// how.
typedef _StackedCel = ({
  BrushFrameKey cel,
  double opacity,
  LayerBlendMode blendMode,
  LayerPlacement? placement,
  List<ResolvedLayerEffect> effects,
  int? tint,
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
/// AN ONION GHOST ([CanvasGhostImageRequest]) IS READ AS EVERY ROW IS, its
/// tint with the rest — in a picture of the ghosts alone laid over the
/// frame's (`_ghostsOver`; one-picture-per-frame-Q1 = a, 「한 장 위에
/// 얹는다」), or in the frame's own tree under its row's drawing
/// (onion-ghosts-in-place). ↩️A tinted row was refused here while the
/// ghosts were stacked from their rows' images at the display's level,
/// until those were the last per-zoom pictures kept (②-5b-1, 유저
/// 2026-10-25 「원본기준으로 해서 쓸데없는 소재 없애고 거기서 극한 최적화
/// 해야지」).
_StackedCel? _stackedCelOf(CanvasStackRow row) => switch (row) {
  CanvasLayerImageRequest(
    :final frameKey,
    :final opacity,
    :final blendMode,
    :final placement,
    :final effects,
    :final tint,
  ) =>
    (
      cel: frameKey,
      opacity: opacity,
      blendMode: blendMode,
      placement: placement,
      effects: effects,
      tint: tint,
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
      tint: null,
    ),
  CanvasActiveLayerRow() => null,
};
