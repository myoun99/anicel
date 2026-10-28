import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';

/// 🗣️onion-ghosts-in-place-Q1 = a (유저 2026-10-26 「제자리는 a말한거야」):
/// laid IN PLACE, a row's onion ghosts lie directly under its own drawing —
/// in its folder, cut by its clip — so the rows above cover them, as in
/// TVPaint and Clip Studio. The plan places them, as it places the row a pen
/// is on: a row that shows no cel at the frame keeps its place for them.
///
/// Read off the tree the plan resolves ([resolveCutFrameCompositeTree]); a
/// ghost reads `~row`.
void main() {
  const canvasSize = CanvasSize(width: 4, height: 4);

  Layer drawing(
    String id, {
    String? folder,
    bool clips = false,
    LayerBlendMode blend = LayerBlendMode.normal,
    int from = 0,
  }) => Layer(
    id: LayerId(id),
    name: id.toUpperCase(),
    frames: [Frame(id: FrameId('frame-$id'), duration: 1, strokes: const [])],
    timeline: {from: TimelineExposure.drawing(FrameId('frame-$id'), length: 4)},
    folderId: folder == null ? null : LayerId(folder),
    clipsToBelow: clips,
    blendMode: blend,
  );

  Layer folderRow(String id, {double opacity = 1}) => createFolderLayer(
    id: LayerId(id),
    name: id.toUpperCase(),
  ).copyWith(opacity: opacity);

  Cut cutOf(List<Layer> layers) => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    layers: layers,
    duration: 24,
    canvasSize: canvasSize,
  );

  /// [layers]' tree at frame 0, two ghosts for each row in [onion].
  String treeOf(List<Layer> layers, {Set<String> onion = const {}}) => shapes(
    resolveCutFrameCompositeTree(
      cut: cutOf(layers),
      frameIndex: 0,
      ghostsOf: (row) => [
        if (onion.contains(row.id.value))
          for (final peg in [1, 2])
            CutFrameCompositeGhost(
              layer: row,
              frameId: FrameId('ghost-${row.id.value}-$peg'),
              opacity: 0.4,
            ),
      ],
    ),
  );

  test('a row\'s ghosts lie directly under it, each of its own, under '
      'every row above it', () {
    expect(
      treeOf([
        drawing('a'),
        drawing('b'),
        drawing('c'),
      ], onion: {'b', 'c'}),
      'a ~b ~b b ~c ~c c',
    );
  });

  test('no ghost, no change: the tree a route that lays none resolves', () {
    final layers = [drawing('a'), drawing('b')];
    expect(
      treeOf(layers),
      shapes(resolveCutFrameCompositeTree(cut: cutOf(layers), frameIndex: 0)),
    );
  });

  test('a row that shows no cel at the frame keeps its place for its '
      'ghosts', () {
    expect(
      treeOf([
        drawing('a'),
        drawing('b', from: 2),
        drawing('c'),
      ], onion: {'b'}),
      'a ~b ~b c',
    );
  });

  test('a clip base\'s ghosts are no base: where it shows no cel, what '
      'clips to it paints nothing, its ghosts beside', () {
    expect(
      treeOf([drawing('a', from: 2), drawing('b', clips: true)], onion: {'a'}),
      '~a ~a',
    );
  });

  test('in a folder that composes on its own, inside it — its strength '
      'and effects are theirs too', () {
    expect(
      treeOf([
        drawing('a', folder: 'f'),
        drawing('b', folder: 'f'),
        folderRow('f', opacity: 0.5),
      ], onion: {'b'}),
      'group(a ~b ~b b)',
    );
  });

  test('a clip base\'s ghosts lie under its clipping group — in the base '
      'they would widen the cut', () {
    expect(
      treeOf([drawing('a'), drawing('b', clips: true)], onion: {'a'}),
      '~a ~a clip(a | b)',
    );
  });

  test('a clipped row\'s ghosts are cut by its base, under it', () {
    expect(
      treeOf([drawing('a'), drawing('b', clips: true)], onion: {'b'}),
      'clip(a | ~b ~b b)',
    );
  });

  test('a row in a folder that is a clip base: its ghosts lie under the '
      'clipping group, out of the folder', () {
    expect(
      treeOf([
        drawing('a', folder: 'f'),
        folderRow('f'),
        drawing('b', clips: true),
      ], onion: {'a'}),
      '~a ~a clip(group(a) | b)',
    );
  });

  test('a row in an advanced blend lays over its ghosts as over the rest of '
      'its backdrop', () {
    expect(
      treeOf([
        drawing('a'),
        drawing('b', blend: LayerBlendMode.multiply),
      ], onion: {'b'}),
      'blend(a ~b ~b | b)',
    );
  });
}

/// [nodes] read bottom → top: a row by its id, a ghost `~` its row's.
String shapes(List<CompositeNode<CutFrameCompositeRow>> nodes) =>
    nodes.map(_shapeOf).join(' ');

String _shapeOf(CompositeNode<CutFrameCompositeRow> node) => switch (node) {
  CompositeLeaf(payload: CutFrameCompositeEntry(:final layer)) =>
    layer.id.value,
  CompositeLeaf(payload: CutFrameCompositeLiveRow(:final layer)) =>
    '${layer.id.value}*',
  CompositeLeaf(payload: CutFrameCompositeGhost(:final layer)) =>
    '~${layer.id.value}',
  CompositeGroup(:final children) => 'group(${shapes(children)})',
  CompositeAdjustment(:final children) => 'adjust(${shapes(children)})',
  CompositeBackdropBlend(:final backdrop, :final source) =>
    'blend(${shapes(backdrop)} | ${_shapeOf(source)})',
  CompositeClip(:final base, :final scope) =>
    'clip(${_shapeOf(base)} | ${shapes(scope)})',
  CompositeOpaque(:final of) => 'opaque(${_shapeOf(of)})',
  CompositeCelNumber(:final on) => _shapeOf(on),
};
