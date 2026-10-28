import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_folder.dart' show createFolderLayer;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/editing/layer_merge_plan.dart';

/// 🗣️I-78 (유저 2026-10-06 · 10-07 · 10-28): MERGE makes the rows it takes
/// one row — a picture wherever what they show changes (Q3 · Q6), named by
/// the topmost cel shown there (Q10 · Q11), the folder becoming the row
/// when it alone is taken (Q5), hidden rows baked shown (Q7).
void main() {
  /// A row named [id] standing [blocks] — `start: cel name` — each cel held
  /// to the next block's start, the last one [lastLength] long.
  Layer row(
    String id,
    Map<int, String> blocks, {
    int lastLength = 2,
    LayerKind kind = LayerKind.animation,
    String? inside,
    bool isVisible = true,
    LayerBlendMode blendMode = LayerBlendMode.normal,
    TransformTrack? transformTrack,
  }) {
    final starts = blocks.keys.toList()..sort();
    final names = {...blocks.values};
    return Layer(
      id: LayerId(id),
      name: id,
      kind: kind,
      folderId: inside == null ? null : LayerId(inside),
      isVisible: isVisible,
      blendMode: blendMode,
      transformTrack: transformTrack,
      frames: [
        for (final name in names)
          Frame(
            id: FrameId('$id-$name'),
            duration: 1,
            name: name,
            strokes: const [],
          ),
      ],
      timeline: {
        for (final (index, start) in starts.indexed)
          start: TimelineExposure.drawing(
            FrameId('$id-${blocks[start]}'),
            length: index + 1 < starts.length
                ? starts[index + 1] - start
                : lastLength,
          ),
      },
    );
  }

  Cut cutOf(List<Layer> layers) => Cut(
    id: const CutId('c'),
    name: '1',
    duration: 24,
    canvasSize: const CanvasSize(width: 64, height: 36),
    layers: layers,
  );

  LayerMergePlan? merge(Cut cut, List<String> ids) {
    var minted = 0;
    return planLayerMerge(
      cut: cut,
      selected: {for (final id in ids) LayerId(id)},
      revisionOf: (_, _) => 0,
      mintFrameId: (_) => FrameId('m${minted++}'),
      isLinked: (_) => false,
    );
  }

  /// `start: (length, cel name)` of every block [layer] stands.
  Map<int, (int, String?)> blocksOf(Layer layer) => {
    for (final MapEntry(:key, :value) in layer.timeline.entries)
      key: (value.length!, layer.frameById(value.frameId!)?.name),
  };

  group('a picture wherever what the rows show changes', () {
    test('the topmost row\'s cel names it, and where the topmost shows '
        'nothing the one under it does (Q10 · Q11)', () {
      final plan = merge(
        cutOf([
          row('b', {0: 'B1'}, lastLength: 8),
          row('a', {0: 'A1'}, lastLength: 4),
        ]),
        ['a', 'b'],
      )!;

      expect(blocksOf(plan.result), {0: (4, 'A1'), 4: (4, 'B1')});
      expect([for (final p in plan.pictures) p.frameIndex], [0, 4]);
    });

    test('a cel the rows under it change beneath splits, the rest wearing '
        'its name\'s tail', () {
      final plan = merge(
        cutOf([
          row('b', {0: 'B1', 2: 'B2', 4: 'B3'}),
          row('a', {0: 'A1'}, lastLength: 6),
        ]),
        ['a', 'b'],
      )!;

      expect(blocksOf(plan.result), {
        0: (2, 'A1'),
        2: (2, 'A1-2'),
        4: (2, 'A1-3'),
      });
    });

    test('the same pictures shown again are the same cel', () {
      final plan = merge(
        cutOf([
          row('b', {0: 'B1'}, lastLength: 6),
          row('a', {0: 'A1', 2: 'A2', 4: 'A1'}),
        ]),
        ['a', 'b'],
      )!;

      expect(blocksOf(plan.result), {
        0: (2, 'A1'),
        2: (2, 'A2'),
        4: (2, 'A1'),
      });
      expect(
        plan.result.timeline[0]!.frameId,
        plan.result.timeline[4]!.frameId,
      );
      expect(plan.result.frames, hasLength(2));
    });

    test('a key that moves the row inside a hold parts it there — what '
        'shows is baked, never the keys (Q6)', () {
      final moving = TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty()
            .withKey(0, CanvasPoint(x: 0, y: 0))
            .withKey(2, CanvasPoint(x: 8, y: 0)),
      );
      final plan = merge(
        cutOf([
          row('b', {0: 'B1'}, lastLength: 4),
          row('a', {0: 'A1'}, lastLength: 4, transformTrack: moving),
        ]),
        ['a', 'b'],
      )!;

      expect(blocksOf(plan.result), {
        0: (1, 'A1'),
        1: (1, 'A1-2'),
        2: (2, 'A1-3'),
      }, reason: 'still from the last key on');
      expect(plan.result.transformTrack.isEmpty, isTrue);
    });

    test('a frame no row shows anything at is empty in the result too', () {
      final plan = merge(
        cutOf([
          row('b', {6: 'B1'}),
          row('a', {0: 'A1'}),
        ]),
        ['a', 'b'],
      )!;

      expect(blocksOf(plan.result), {0: (2, 'A1'), 6: (2, 'B1')});
    });
  });

  group('the row it makes', () {
    test('wears the topmost row\'s name and stands where it stood — the '
        'rows it took are gone, the rest stay where they were', () {
      final plan = merge(
        cutOf([
          row('under', {0: 'U1'}),
          row('c', {0: 'C1'}),
          row('b', {0: 'B1'}),
          row('a', {0: 'A1'}, blendMode: LayerBlendMode.multiply),
        ]),
        ['c', 'b', 'a'],
      )!;

      expect(plan.result.id, const LayerId('a'));
      expect(plan.removed, [const LayerId('c'), const LayerId('b')]);
      expect(plan.regrouped, isEmpty);
      expect(
        [plan.result.name, plan.result.blendMode, plan.result.isVisible],
        ['a', LayerBlendMode.normal, true],
      );
      expect(plan.changes, {LayerMergeChange.blend});
    });

    test('a hidden row is baked shown (Q7)', () {
      final plan = merge(
        cutOf([
          row('b', {0: 'B1'}, isVisible: false),
          row('a', {0: 'A1'}, isVisible: false),
        ]),
        ['a', 'b'],
      )!;

      expect([for (final layer in plan.baked.layers) layer.isVisible], [
        true,
        true,
      ]);
      expect(plan.result.isVisible, isTrue);
      expect(plan.pictures, hasLength(1));
    });

    test('an image that comes to hold more than one picture is a drawing '
        'row, and one that holds one stays an image', () {
      final two = merge(
        cutOf([
          row('b', {0: 'B1', 2: 'B2'}),
          row('a', {0: 'A1'}, lastLength: 4, kind: LayerKind.image),
        ]),
        ['a', 'b'],
      )!;
      final one = merge(
        cutOf([
          row('b', {0: 'B1'}),
          row('a', {0: 'A1'}, kind: LayerKind.image),
        ]),
        ['a', 'b'],
      )!;

      expect([two.result.kind, one.result.kind], [
        LayerKind.animation,
        LayerKind.image,
      ]);
    });

    test('one picture row alone, or rows that paint no drawing, merge '
        'nothing', () {
      final cut = cutOf([
        row('b', {0: 'B1'}),
        row('se', {0: 'S1'}, kind: LayerKind.se),
        row('a', {0: 'A1'}),
      ]);

      expect(merge(cut, ['a']), isNull);
      expect(merge(cut, ['a', 'se']), isNull);
    });
  });

  group('a folder', () {
    test('taken alone, it is everything under it as one row, and the '
        'folder becomes the row (Q5)', () {
      final plan = merge(
        cutOf([
          row('b', {0: 'B1'}, inside: 'F'),
          row('a', {0: 'A1'}, lastLength: 4, inside: 'F'),
          createFolderLayer(id: const LayerId('F'), name: 'Folder'),
        ]),
        ['F'],
      )!;

      expect(plan.result.id, const LayerId('F'));
      expect(plan.removed, [const LayerId('b'), const LayerId('a')]);
      expect(
        [plan.result.kind, plan.result.name, plan.result.folderId],
        [LayerKind.animation, 'Folder', null],
      );
      expect(blocksOf(plan.result), {0: (2, 'A1'), 2: (2, 'A1-2')});
    });

    test('a row it held that lays no picture stays, in the folder above',
        () {
      final plan = merge(
        cutOf([
          row('a', {0: 'A1'}, inside: 'F'),
          Layer(
            id: const LayerId('cam'),
            name: 'cam',
            kind: LayerKind.camera,
            folderId: const LayerId('F'),
            frames: const [],
          ),
          createFolderLayer(
            id: const LayerId('F'),
            name: 'F',
            parentId: const LayerId('P'),
          ),
          createFolderLayer(id: const LayerId('P'), name: 'P'),
        ]),
        ['F'],
      )!;

      expect(plan.removed, [const LayerId('a')]);
      expect(plan.regrouped, {const LayerId('cam'): const LayerId('P')});
    });

    test('the folder the result stands in lays its look over it after the '
        'merge, so it is not baked; a folder under that is', () {
      final outer = createFolderLayer(
        id: const LayerId('P'),
        name: 'P',
      ).copyWith(opacity: 0.5);
      final inner = createFolderLayer(
        id: const LayerId('G'),
        name: 'G',
        parentId: const LayerId('P'),
      );
      final plan = merge(
        cutOf([
          row('b', {0: 'B1'}, inside: 'G'),
          inner,
          row('a', {0: 'A1'}, inside: 'P'),
          outer,
        ]),
        ['a', 'b'],
      )!;

      expect(
        [
          for (final layer in plan.baked.layers)
            (layer.id.value, layer.folderId?.value),
        ],
        [('b', 'G'), ('G', null), ('a', null)],
      );
      expect(plan.result.folderId, const LayerId('P'));
      expect(plan.changes, isEmpty);
    });

    test('a row from outside the folder the result stands in is warned of '
        'when that folder lays a look', () {
      final plan = merge(
        cutOf([
          row('b', {0: 'B1'}),
          row('a', {0: 'A1'}, inside: 'P'),
          createFolderLayer(
            id: const LayerId('P'),
            name: 'P',
          ).copyWith(opacity: 0.5),
        ]),
        ['a', 'b'],
      )!;

      expect(plan.changes, {LayerMergeChange.folder});
    });
  });

  test('a row this round does not merge yet is passed over — an attach '
      'row, and the base it rides', () {
    final base = row('base', {0: 'X1'});
    final rider = Layer(
      id: const LayerId('rider'),
      name: 'rider',
      attachedToLayerId: const LayerId('base'),
      frames: const [],
    );
    final cut = cutOf([row('b', {0: 'B1'}), base, rider, row('a', {0: 'A1'})]);

    final plan = merge(cut, ['a', 'b', 'base', 'rider'])!;

    expect(plan.result.id, const LayerId('a'));
    expect(plan.removed, [const LayerId('b')]);
  });

  test('a reference row is passed over: its file lies past the wall, where '
      'no picture of the screen reaches', () {
    final still = row('still', {0: 'P1'}, kind: LayerKind.image).copyWith(
      mediaReference: MediaReference(
        assetPath: 'paper.png',
        pose: TransformPose(center: CanvasPoint(x: 32, y: 18)),
        pictureSize: const CanvasSize(width: 640, height: 360),
      ),
    );
    final cut = cutOf([row('b', {0: 'B1'}), still, row('a', {0: 'A1'})]);

    final plan = merge(cut, ['a', 'b', 'still'])!;

    expect(plan.removed, [const LayerId('b')]);
    expect([for (final layer in plan.baked.layers) layer.id.value], [
      'b',
      'a',
    ]);
  });
}
