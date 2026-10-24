import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';

/// The onion ghosts stand directly under the row drawn on, wherever it
/// stands in the tree ([stackNodesWithGhosts]) — and in a clipping group
/// (I-92) never IN its base: what the base holds is what the group is cut
/// by, so a ghost there would widen the cut. A row drawn on that clips
/// takes them in what clips, cut by the base as it is; a base drawn on
/// takes them under the whole group.
void main() {
  BrushFrameKey cel(String id) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(id),
    frameId: FrameId('$id-1'),
  );

  CompositeNode<CanvasStackRow> stored(String id) =>
      CompositeLeaf<CanvasStackRow>(
        CanvasLayerImageRequest(frameKey: cel(id), opacity: 1),
      );
  const drawnOn = CompositeLeaf<CanvasStackRow>(
    CanvasActiveLayerRow(opacity: 1),
  );
  final ghost = CanvasLayerImageRequest(frameKey: cel('ghost'), opacity: 1);

  /// What [node] holds, bottom-up: a stored row by its id, the row drawn
  /// on as `drawn`, the ghost as `ghost`, a clipping group as its base and
  /// what clips to it.
  Object said(CompositeNode<CanvasStackRow> node) => switch (node) {
    CompositeLeaf(payload: CanvasActiveLayerRow()) => 'drawn',
    CompositeLeaf(payload: final CanvasLayerImageRequest request) =>
      identical(request, ghost) ? 'ghost' : request.frameKey.layerId.value,
    CompositeClip(:final base, :final scope) => {
      'base': said(base),
      'clipped': [for (final node in scope) said(node)],
    },
    _ => throw StateError('$node is not in this fixture'),
  };

  List<Object> laid(List<CompositeNode<CanvasStackRow>> nodes) => [
    for (final node in stackNodesWithGhosts(nodes, [ghost])) said(node),
  ];

  test('a row drawn on that clips takes its ghosts in what clips, cut by '
      'the base as it is', () {
    expect(
      laid([
        CompositeClip<CanvasStackRow>(
          base: stored('a'),
          scope: [drawnOn],
          opacity: 1,
          blendMode: LayerBlendMode.normal,
        ),
      ]),
      [
        {
          'base': 'a',
          'clipped': ['ghost', 'drawn'],
        },
      ],
    );
  });

  test('a base drawn on takes its ghosts under the whole group', () {
    expect(
      laid([
        CompositeClip<CanvasStackRow>(
          base: drawnOn,
          scope: [stored('b')],
          opacity: 1,
          blendMode: LayerBlendMode.normal,
        ),
      ]),
      [
        'ghost',
        {
          'base': 'drawn',
          'clipped': ['b'],
        },
      ],
    );
  });
}
