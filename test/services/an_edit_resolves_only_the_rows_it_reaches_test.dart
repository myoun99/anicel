import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/tree_nodes.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';

/// 🔬F-620 (11-19, the Surface, S5_BA cut 352 · 68 rows): a ruler's bar
/// recounts its spans after every edit, laying every frame's tree anew,
/// and resolving each row of each frame was about 45% of that. An edit is
/// a new cut whose untouched rows are the very rows they were: the film
/// hands their own nodes on, and resolves anew each row whose own nodes
/// read what the edit touched — the row, a folder above it, the row it
/// clips with, the base it rides, the paper.
void main() {
  const frames = 4;

  Layer drawing(
    String id, {
    String? folder,
    List<LayerEffect> effects = const [],
    bool clips = false,
  }) => Layer(
    id: LayerId(id),
    name: id.toUpperCase(),
    frames: [Frame(id: FrameId('$id-1'), duration: 1, strokes: const [])],
    timeline: {
      0: TimelineExposure.drawing(FrameId('$id-1'), length: frames),
    },
    folderId: folder == null ? null : LayerId(folder),
    effects: effects,
    clipsToBelow: clips,
  );

  final number = LayerEffect(
    id: const EffectId('n'),
    kind: EffectKind.celNumber,
  );

  Cut cutOf(List<Layer> layers) => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    layers: layers,
    duration: frames,
    canvasSize: const CanvasSize(width: 40, height: 40),
  );

  /// [cut]'s film, every frame laid.
  List<List<CompositeNode<CutFrameCompositeRow>>> film(Cut cut) => [
    for (var at = 0; at < frames; at += 1) filmTreeOf(cut, at),
  ];

  /// [cut] with row [id] as [edit] makes it, every other row the very one.
  Cut edited(Cut cut, String id, Layer Function(Layer row) edit) =>
      cut.copyWith(
        layers: [
          for (final row in cut.layers)
            if (row.id == LayerId(id)) edit(row) else row,
        ],
      );

  /// Row [id]'s entry in each frame of [trees].
  List<CutFrameCompositeEntry> entriesOf(
    String id,
    List<List<CompositeNode<CutFrameCompositeRow>>> trees,
  ) => [
    for (final tree in trees)
      for (final node in preorderNodes(tree))
        if (node
            case CompositeLeaf(
              payload: final CutFrameCompositeEntry entry,
            ) when entry.layer.id == LayerId(id))
          entry,
  ];

  test('an edit of one row resolves it anew, and hands every other row on '
      'as it was', () {
    final held = cutOf([drawing('a'), drawing('b')]);
    final was = film(held);
    final before = debugFilmRowsResolved;

    final now = film(edited(held, 'a', (row) => row.copyWith(opacity: 0.5)));

    expect(
      debugFilmRowsResolved - before,
      frames,
      reason: 'a at each frame, b at none',
    );
    expect(entriesOf('a', now).map((entry) => entry.opacity), [
      for (var at = 0; at < frames; at += 1) 0.5,
    ]);
    final (wasB, nowB) = (entriesOf('b', was), entriesOf('b', now));
    expect(nowB, hasLength(frames));
    for (var at = 0; at < frames; at += 1) {
      expect(nowB[at], same(wasB[at]));
    }
  });

  test('a row under a folder that moves is resolved anew', () {
    final held = cutOf([
      drawing('b', folder: 'f'),
      createFolderLayer(id: const LayerId('f'), name: 'F'),
    ]);
    expect(entriesOf('b', film(held)).first.placement, isNull);

    final now = film(
      edited(
        held,
        'f',
        (folder) => folder.copyWith(
          transformTrack: TransformTrack(
            keyframes: {0: TransformPose(center: CanvasPoint(x: 30, y: 20))},
          ),
        ),
      ),
    );

    expect(entriesOf('b', now).first.placement, isNotNull);
  });

  test('a row a clip stops meeting is resolved anew — its number no longer '
      'one picture with it', () {
    final held = cutOf([
      drawing('b', effects: [number]),
      drawing('c', clips: true),
    ]);
    expect(
      film(held).first.single,
      isA<CompositeClip<CutFrameCompositeRow>>(),
      reason: '⛔CONTROL: c clips to b',
    );

    final now = film(
      edited(held, 'c', (row) => row.copyWith(clipsToBelow: false)),
    );

    expect(
      now.first.whereType<CompositeGroup<CutFrameCompositeRow>>(),
      isEmpty,
      reason: 'b and its number lie by themselves, wrapped in no picture',
    );
  });

  test('a row riding a base whose blocks move is resolved anew', () {
    final base = Layer(
      id: const LayerId('base'),
      name: 'BASE',
      frames: [
        for (final id in ['b1', 'b2'])
          Frame(id: FrameId(id), duration: 1, strokes: const []),
      ],
      timeline: {
        0: const TimelineExposure.drawing(FrameId('b1'), length: 2),
        2: const TimelineExposure.drawing(FrameId('b2'), length: 2),
      },
    );
    final rider = Layer(
      id: const LayerId('rider'),
      name: 'BASE +1',
      frames: [
        for (final id in ['a1', 'a2'])
          Frame(id: FrameId(id), duration: 1, strokes: const []),
      ],
      timeline: const {},
      attachedToLayerId: const LayerId('base'),
      attachedPlacement: AttachedPlacement.above,
      baseFrameLinks: {
        const FrameId('b1'): const FrameId('a1'),
        const FrameId('b2'): const FrameId('a2'),
      },
    );
    final held = cutOf([base, rider]);
    expect(
      entriesOf('rider', film(held)).first.frame.id,
      const FrameId('a1'),
    );

    final now = film(
      edited(
        held,
        'base',
        (row) => row.copyWith(
          timeline: {
            0: const TimelineExposure.drawing(FrameId('b2'), length: frames),
          },
        ),
      ),
    );

    expect(entriesOf('rider', now).first.frame.id, const FrameId('a2'));
  });

  test('every row is resolved anew on a paper of another size', () {
    final held = cutOf([
      drawing('b', effects: [number]),
    ]);
    CanvasPoint centerOf(Cut cut) => preorderNodes(filmTreeOf(cut, 0))
        .whereType<CompositeCelNumber<CutFrameCompositeRow>>()
        .single
        .letters
        .center;
    final was = centerOf(held);

    final now = centerOf(
      held.copyWith(canvasSize: const CanvasSize(width: 80, height: 40)),
    );

    expect(now, isNot(was));
  });
}
