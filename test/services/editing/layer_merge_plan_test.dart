import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
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
import 'package:anicel/src/models/timeline_run_behavior.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/editing/layer_merge_plan.dart';

import '../../helpers/run_edge_fixtures.dart';

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

  LayerMergePlan? merge(
    Cut cut,
    List<String> ids, {
    Set<String> linked = const {},
  }) {
    final taking = takeRowsToMerge(
      cut: cut,
      selected: {for (final id in ids) LayerId(id)},
      isLinked: (row) => linked.contains(row.id.value),
    );
    var minted = 0;
    return taking == null
        ? null
        : planLayerMerge(
            taking,
            revisionOf: (_, _) => 0,
            mintFrameId: (_) => FrameId('m${minted++}'),
          );
  }

  /// `start: (length, cel name)` of every block [layer] stands.
  Map<int, (int, String?)> blocksOf(Layer layer) => {
    for (final MapEntry(:key, :value) in layer.timeline.entries)
      key: (value.length!, layer.frameById(value.frameId!)?.name),
  };

  /// The cut the result's pictures are drawn from.
  Cut bakedOf(LayerMergePlan plan) => plan.pictures
      .firstWhere((picture) => picture.rowId == plan.result.id)
      .from;

  /// A SYNCED attach row named [id] riding [base], its cel `R<n>` showing
  /// wherever [base]'s cel `<n>` does.
  Layer synced(String id, Layer base) => Layer(
    id: LayerId(id),
    name: id,
    attachedToLayerId: base.id,
    timeline: const {},
    frames: [
      for (final cel in base.frames)
        Frame(
          id: FrameId('$id-${cel.name}'),
          duration: 1,
          name: 'R${cel.name}',
          strokes: const [],
        ),
    ],
    baseFrameLinks: {
      for (final cel in base.frames) cel.id: FrameId('$id-${cel.name}'),
    },
  );

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

      expect([for (final layer in bakedOf(plan).layers) layer.isVisible], [
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

    test('taken, it takes everything it holds — a folder inside it and that '
        'folder\'s rows with the rest', () {
      final plan = merge(
        cutOf([
          row('b', {0: 'B1'}, inside: 'G'),
          createFolderLayer(
            id: const LayerId('G'),
            name: 'G',
            parentId: const LayerId('F'),
          ),
          row('a', {0: 'A1'}, inside: 'F'),
          createFolderLayer(id: const LayerId('F'), name: 'F'),
        ]),
        ['F'],
      )!;

      expect(plan.result.id, const LayerId('F'));
      expect(plan.removed, [
        const LayerId('b'),
        const LayerId('G'),
        const LayerId('a'),
      ]);
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
          for (final layer in bakedOf(plan).layers)
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

  group('an attach row the merge does not take rides the result (Q8)', () {
    test('🎯a synced one takes a cel for each of the result\'s — named by '
        'the cel it showed there — and is drawn alone, wearing its base, '
        'the base itself hidden', () {
      final base = row('a', {0: '1', 4: '2'}, lastLength: 4);
      final plan = merge(
        cutOf([
          row('b', {0: 'B1', 2: 'B2'}, lastLength: 6),
          base,
          synced('r', base).copyWith(
            isVisible: false,
            opacity: 0.5,
            blendMode: LayerBlendMode.multiply,
            clipsToBelow: true,
          ),
        ]),
        ['a', 'b'],
      )!;

      expect(blocksOf(plan.result), {
        0: (2, '1'),
        2: (2, '1-2'),
        4: (4, '2'),
      });
      final rider = plan.riders.single;
      expect(rider.attachedToLayerId, const LayerId('a'));
      expect(rider.timeline, isEmpty, reason: 'it rides the result');
      expect(
        [rider.isVisible, rider.opacity, rider.blendMode, rider.clipsToBelow],
        [false, 0.5, LayerBlendMode.multiply, true],
        reason: 'what is its own stays on its row',
      );
      expect(
        [for (final cel in rider.frames) (cel.id.value, cel.name)],
        [
          ('attach-mirror-r-m0', 'R1'),
          ('attach-mirror-r-m1', 'R1-2'),
          ('attach-mirror-r-m2', 'R2'),
        ],
      );
      expect(rider.baseFrameLinks, {
        for (final cel in plan.result.frames)
          cel.id: FrameId('attach-mirror-r-${cel.id.value}'),
      });
      expect([for (final row in plan.layers) row.id.value], ['a', 'r']);
      final drawn = [
        for (final picture in plan.pictures)
          if (picture.rowId == rider.id) picture,
      ];
      expect([for (final picture in drawn) picture.frameIndex], [0, 2, 4]);
      expect(
        [
          for (final row in drawn.first.from.layers)
            (
              row.id.value,
              row.isVisible,
              row.opacity,
              row.blendMode,
              row.clipsToBelow,
            ),
        ],
        [
          ('a', false, 1.0, LayerBlendMode.normal, false),
          ('r', true, 1.0, LayerBlendMode.normal, false),
        ],
        reason: 'and is laid on the pictures as it was, so none of it is '
            'baked',
      );
    });

    test('a synced one\'s cel where it showed nothing is an empty cel, '
        'drawn of nothing', () {
      final base = row('a', {0: '1', 2: '2'});
      final plan = merge(
        cutOf([
          row('b', {0: 'B1'}, lastLength: 4),
          base,
          synced('r', base).copyWith(
            baseFrameLinks: {base.frames.first.id: const FrameId('r-1')},
          ),
        ]),
        ['a', 'b'],
      )!;

      final rider = plan.riders.single;
      expect([for (final cel in rider.frames) cel.name], ['R1', null]);
      expect(
        [
          for (final picture in plan.pictures)
            if (picture.rowId == rider.id) picture.frameIndex,
        ],
        [0],
      );
    });

    test('a base that shows nothing still holds a cel wherever its synced '
        'rider shows one', () {
      final base = row('a', {0: '1'}).copyWith(opacity: 0);
      final plan = merge(
        cutOf([row('b', {}), base, synced('r', base)]),
        ['a', 'b'],
      )!;

      expect(plan.result.frames, hasLength(1));
      expect(plan.riders.single.frames, hasLength(1));
    });

    test('a free one keeps its own timing, its cels parted wherever what '
        'it wore of its base changes', () {
      final moving = TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty()
            .withKey(1, CanvasPoint(x: 32, y: 18))
            .withKey(2, CanvasPoint(x: 40, y: 18)),
      );
      final base = row('a', {0: '1'}, lastLength: 4, transformTrack: moving);
      final free = row('r', {1: 'R1'}, kind: LayerKind.image).copyWith(
        attachedToLayerId: base.id,
        attachedMode: AttachedMode.free,
      );
      final plan = merge(
        cutOf([row('b', {0: 'B1'}, lastLength: 4), base, free]),
        ['a', 'b'],
      )!;

      final rider = plan.riders.single;
      expect(rider.attachedMode, AttachedMode.free);
      expect(rider.attachedToLayerId, const LayerId('a'));
      expect(blocksOf(rider), {1: (1, 'R1'), 2: (1, 'R1-2')});
      expect(rider.kind, LayerKind.animation, reason: 'an image no more');
    });

    test('one taken with its base is merged, and the other rides', () {
      final base = row('a', {0: '1'});
      final plan = merge(
        cutOf([synced('under', base), base, synced('over', base)]),
        ['a', 'under'],
      )!;

      expect(plan.removed, [const LayerId('under')]);
      expect([for (final rider in plan.riders) rider.id.value], ['over']);
    });

    test('until I-78-Q14 is answered, one chosen without its base is passed '
        'over', () {
      final base = row('base', {0: '1'});
      final plan = merge(
        cutOf([
          row('c', {0: 'C1'}),
          row('b', {0: 'B1'}),
          base,
          synced('r', base),
        ]),
        ['b', 'c', 'r'],
      )!;

      expect(plan.result.id, const LayerId('b'));
      expect(plan.removed, [const LayerId('c')]);
    });

    test('until I-78-Q13 is answered, a base whose rider is not taken goes '
        'only as the topmost row chosen', () {
      final base = row('base', {0: '1'});
      final plan = merge(
        cutOf([
          row('c', {0: 'C1'}),
          base,
          synced('r', base),
          row('a', {0: 'A1'}),
        ]),
        ['a', 'base', 'c'],
      )!;

      expect(plan.removed, [const LayerId('c')]);
      expect(plan.riders, isEmpty);
    });

    test('a base one of whose riders this round passes over is passed over '
        'too: the rider would be baked anew', () {
      final base = row('base', {0: '1'});
      final plan = merge(
        cutOf([
          row('c', {0: 'C1'}),
          row('b', {0: 'B1'}),
          base,
          synced('r', base),
        ]),
        ['base', 'b', 'c'],
        linked: {'r'},
      )!;

      expect(plan.result.id, const LayerId('b'));
      expect(plan.removed, [const LayerId('c')]);
    });
  });

  test('a 겸용 row is passed over: another cut shows its cels', () {
    final cut = cutOf([
      row('c', {0: 'C1'}),
      row('b', {0: 'B1'}),
      row('a', {0: 'A1'}),
    ]);

    final plan = merge(cut, ['a', 'b', 'c'], linked: {'b'})!;

    expect(plan.removed, [const LayerId('c')]);
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
    expect([for (final layer in bakedOf(plan).layers) layer.id.value], [
      'b',
      'a',
    ]);
  });

  /// 🗣️I-78-Q4 (유저 2026-10-07): 「한 행의 여러 블록을 레이어랑 같은 규칙으로
  /// 제일 왼쪽 블록에 합침 … 각 행이 판단해서 이건 병합이 가능한 상태서만
  /// 작동하도록」.
  group('a row\'s blocks a band holds (Q4)', () {
    /// What a press of MERGE makes of [cut]'s blocks at [starts], by row.
    BlockMergePlan? mergeBlocks(
      Cut cut,
      Map<String, List<int>> starts, {
      Set<String> linked = const {},
    }) {
      final taking = takeBlocksToMerge(
        cut: cut,
        blockStarts: {
          for (final MapEntry(:key, :value) in starts.entries)
            LayerId(key): value,
        },
        isLinked: (row) => linked.contains(row.id.value),
      );
      var minted = 0;
      return taking == null
          ? null
          : planBlockMerge(
              taking,
              mintFrameId: (_) => FrameId('m${minted++}'),
            );
    }

    Layer rowOf(BlockMergePlan plan, String id) =>
        plan.layers.firstWhere((row) => row.id.value == id);

    /// The cel each of [picture]'s layers holds, bottom → top.
    List<String> laidOf(BlockMergePicture picture) => [
      for (final layer in picture.layers)
        layer.layers.single.frames.single.id.value,
    ];

    /// [id]'s blocks `start: (length, cel name)`, each [marks] as given.
    Layer marked(
      String id,
      Map<int, (int, String)> blocks, {
      Map<int, TimelineRunEdgeMark> starting = const {},
      Map<int, TimelineRunEdgeMark> ending = const {},
    }) => row(id, {
      for (final MapEntry(:key, :value) in blocks.entries) key: value.$2,
    }).copyWith(
      timeline: {
        for (final MapEntry(:key, :value) in blocks.entries)
          key: TimelineExposure.drawing(
            FrameId('$id-${value.$2}'),
            length: value.$1,
            startEdge: starting[key] ?? TimelineRunEdgeMark.none,
            endEdge: ending[key] ?? TimelineRunEdgeMark.none,
          ),
      },
    );

    test('🎯they become one where the leftmost stood, over the run they '
        'make — the frames between them too — a new cel named as the '
        'leftmost is, laid of theirs with the leftmost on top', () {
      final plan = mergeBlocks(
        cutOf([
          marked('a', {0: (2, 'A1'), 4: (2, 'A2'), 6: (2, 'A3')}),
        ]),
        {
          'a': [4, 0],
        },
      )!;

      final merged = rowOf(plan, 'a');
      expect(blocksOf(merged), {0: (6, 'A1'), 6: (2, 'A3')});
      expect([for (final cel in merged.frames) cel.id.value], [
        'a-A3',
        'm0',
      ], reason: 'a cel only the run showed goes, as a delete takes it');
      final picture = plan.pictures.single;
      expect((picture.rowId, picture.frameId), (
        const LayerId('a'),
        const FrameId('m0'),
      ));
      expect(laidOf(picture), ['a-A2', 'a-A1']);
    });

    test('a cel shown past the run stays, and the new one wears its name\'s '
        'tail; a cel the run shows twice is laid once', () {
      final cut = cutOf([
        row('a', {0: 'A1', 2: 'A2', 4: 'A1'}),
      ]);

      final some = mergeBlocks(cut, {
        'a': [0, 2],
      })!;
      final all = mergeBlocks(cut, {
        'a': [0, 2, 4],
      })!;

      expect(blocksOf(rowOf(some, 'a')), {0: (4, 'A1-2'), 4: (2, 'A1')});
      expect([for (final cel in rowOf(some, 'a').frames) cel.id.value], [
        'a-A1',
        'm0',
      ]);
      expect(blocksOf(rowOf(all, 'a')), {0: (6, 'A1')});
      expect(laidOf(all.pictures.single), ['a-A2', 'a-A1']);
    });

    test('the run keeps its outer edges: on each side the mode of the '
        'carrier nearest it — a hold set before frames were glued on past '
        'it holds on — and a bound one of them claimed', () {
      Layer mergedOf(Layer row, List<int> starts) =>
          rowOf(mergeBlocks(cutOf([row]), {'a': starts})!, 'a');
      final blocks = {0: (2, 'A1'), 2: (2, 'A2'), 4: (2, 'A3')};

      final held = mergedOf(
        marked(
          'a',
          blocks,
          starting: {2: holdMark, 4: repeatMark},
          ending: {0: holdMark},
        ),
        [0, 2, 4],
      );
      final bounded = mergedOf(
        marked('a', blocks, ending: {2: boundMark, 4: repeatMark}),
        [0, 2],
      );

      expect((held.timeline[0]!.startEdge, held.timeline[0]!.endEdge), (
        holdMark,
        holdMark,
      ));
      expect(
        (bounded.timeline[0]!.endEdge, bounded.timeline[4]!.endEdge),
        (boundMark, repeatMark),
        reason: 'A3\'s repeat still starts at the block A2 became',
      );
    });

    test('each row merges on its own, and a row that cannot is passed '
        'over: one block, a 겸용 row, a synced attach row', () {
      final base = row('a', {0: 'A1', 2: 'A2'});
      final cut = cutOf([
        row('c', {0: 'C1', 2: 'C2'}),
        row('b', {0: 'B1', 2: 'B2'}),
        base,
        synced('r', base),
      ]);

      final plan = mergeBlocks(cut, {
        'a': [0, 2],
        'b': [0, 2],
        'c': [0, 2],
      }, linked: {'c'})!;

      expect([for (final row in plan.rows) row.id.value], ['b', 'a', 'r']);
      expect([for (final row in plan.layers) row.id.value], [
        'c',
        'b',
        'a',
        'r',
      ]);
      expect(blocksOf(rowOf(plan, 'b')), {0: (4, 'B1')});
      expect(blocksOf(rowOf(plan, 'c')), blocksOf(cut.layers.first));
      expect(
        mergeBlocks(cut, {
          'a': [2],
          'c': [0, 2],
          'r': [0, 2],
        }, linked: {'c'}),
        isNull,
      );
    });

    test('a synced attach row riding it merges along: a mirror of the new '
        'cel laid of its own, its mirrors of the cels that go gone', () {
      final base = row('a', {0: '1', 2: '2', 4: '3'});
      final plan = mergeBlocks(cutOf([base, synced('r', base)]), {
        'a': [0, 2],
      })!;

      final rider = rowOf(plan, 'r');
      expect(rider.baseFrameLinks, {
        const FrameId('a-3'): const FrameId('r-3'),
        const FrameId('m0'): const FrameId('attach-mirror-r-m0'),
      });
      expect([for (final cel in rider.frames) (cel.id.value, cel.name)], [
        ('r-3', 'R3'),
        ('attach-mirror-r-m0', 'R1'),
      ]);
      final drawn = plan.pictures.last;
      expect((drawn.rowId, drawn.frameId), (
        rider.id,
        const FrameId('attach-mirror-r-m0'),
      ));
      expect(laidOf(drawn), ['r-2', 'r-1']);
    });

    test('a synced one showing nothing over the run is drawn of nothing, '
        'and its cels the merge did not unlink stay', () {
      final base = row('a', {0: '1', 2: '2', 4: '3'});
      final plan = mergeBlocks(
        cutOf([
          base,
          synced('r', base).copyWith(
            baseFrameLinks: {const FrameId('a-3'): const FrameId('r-3')},
          ),
        ]),
        {
          'a': [0, 2],
        },
      )!;

      expect([for (final picture in plan.pictures) picture.rowId.value], [
        'a',
      ]);
      expect([for (final cel in rowOf(plan, 'r').frames) cel.id.value], [
        'r-1',
        'r-2',
        'r-3',
        'attach-mirror-r-m0',
      ]);
    });
  });
}
