import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart'
    show attachedMirrorCelId;
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte_key.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_folder.dart' show createFolderLayer;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_run_behavior.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
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

  Cut cutOf(List<Layer> layers, {String id = 'c'}) => Cut(
    id: CutId(id),
    name: id,
    duration: 24,
    canvasSize: const CanvasSize(width: 64, height: 36),
    layers: layers,
  );

  /// [cuts] on one track, each of [links] — `cut/row` — ONE layer seen
  /// from each cut it names, the first holding its cels.
  Project projectOf(List<Cut> cuts, List<List<String>> links) => Project(
    id: const ProjectId('p'),
    name: 'p',
    createdAt: DateTime.utc(2026),
    tracks: [Track(id: const TrackId('t'), name: 't', cuts: cuts)],
    linkRegistry: LayerLinkRegistry(
      groups: [
        for (final (index, members) in links.indexed)
          LayerLinkGroup(
            id: 'link-${index + 1}',
            members: [
              for (final member in members)
                LayerLinkMember(
                  trackId: const TrackId('t'),
                  cutId: CutId(member.split('/').first),
                  layerId: LayerId(member.split('/').last),
                ),
            ],
          ),
      ],
    ),
  );

  /// What MERGE makes of [cut]'s rows [ids] — the cuts [elsewhere] beside
  /// it, the rows of each of [links] one layer ([projectOf]) — its pictures
  /// drawn over the wall [reach] stands, the canvas itself unless a test
  /// says otherwise, each cel's ink where [inks] lays it by `row/cel` (none
  /// elsewhere).
  LayerMergePlan? merge(
    Cut cut,
    List<String> ids, {
    List<Cut> elsewhere = const [],
    List<List<String>> links = const [],
    PasteboardReach reach = PasteboardReach.none,
    Map<String, ({int left, int top, int rightExclusive, int bottomExclusive})>
        inks = const {},
  }) {
    final takings = takeRowsToMergeAcross(
      project: projectOf([cut, ...elsewhere], links),
      cutId: cut.id,
      selected: {for (final id in ids) LayerId(id)},
    );
    var minted = 0;
    return takings == null
        ? null
        : planLayerMerge(
            takings,
            readsOf: (_) => (
              revisionOf: (_, _) => 0,
              inkOf: (row, cel) => inks['${row.value}/${cel.value}'],
            ),
            mintFrameId: (_) => FrameId('m${minted++}'),
            reach: reach,
          );
  }

  /// `start: (length, cel name)` of every block [layer] stands.
  Map<int, (int, String?)> blocksOf(Layer layer) => {
    for (final MapEntry(:key, :value) in layer.timeline.entries)
      key: (value.length!, layer.frameById(value.frameId!)?.name),
  };

  /// The row [id] of [layers].
  Layer rowOf(List<Layer> layers, String id) =>
      layers.firstWhere((row) => row.id.value == id);

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
      expect([for (final row in plan.layers) row.id.value], ['under', 'a']);
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
      expect([for (final row in plan.layers) row.id.value], ['F']);
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
      expect([for (final row in plan.layers) row.id.value], ['F']);
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
      final rider = rowOf(plan.layers, 'r');
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

      final rider = rowOf(plan.layers, 'r');
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
      expect(rowOf(plan.layers, 'r').frames, hasLength(1));
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

      final rider = rowOf(plan.layers, 'r');
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

      expect([for (final row in plan.layers) row.id.value], ['a', 'over']);
      expect(rowOf(plan.layers, 'over').attachedToLayerId, const LayerId('a'));
      expect(plan.changes, isEmpty, reason: 'it covers no picture it did not');
    });

    /// 🗣️I-78-Q13 (유저 2026-10-28): 「위쪽 어태치 그대로 결과 행 위에 붙는다
    /// (+경고)」.
    test('🎯the base\'s group is led around the result wherever the base '
        'stood, and a rider led over a picture is warned of', () {
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

      expect([for (final row in plan.layers) row.id.value], ['a', 'r']);
      expect(rowOf(plan.layers, 'r').attachedToLayerId, const LayerId('a'));
      expect(plan.changes, {LayerMergeChange.riderOver});
    });

    test('one riding below is led under it, warned of where it goes under '
        'a picture', () {
      final base = row('base', {0: '1'});
      final cut = cutOf([
        row('c', {0: 'C1'}),
        synced('r', base).copyWith(attachedPlacement: AttachedPlacement.below),
        base,
        row('a', {0: 'A1'}),
      ]);
      final plan = merge(cut, ['a', 'base', 'c'])!;

      expect([for (final row in plan.layers) row.id.value], ['r', 'a']);
      expect(plan.changes, {LayerMergeChange.riderUnder});
      expect(
        merge(cut, ['a', 'base'])!.changes,
        isEmpty,
        reason: 'no picture it took stood under it',
      );
    });

    test('one led out of its base\'s folder stands in the result\'s', () {
      final base = row('base', {0: '1'}, inside: 'F');
      final plan = merge(
        cutOf([
          base,
          synced('r', base).copyWith(folderId: const LayerId('F')),
          createFolderLayer(id: const LayerId('F'), name: 'F'),
          row('a', {0: 'A1'}),
        ]),
        ['a', 'base'],
      )!;

      expect([for (final row in plan.layers) row.id.value], ['F', 'a', 'r']);
      expect(rowOf(plan.layers, 'r').folderId, isNull);
    });

    test('the folder that gathers a group\'s riders is led with them, '
        'holding them still', () {
      final base = row('a', {0: '1'});
      final plan = merge(
        cutOf([
          row('b', {0: 'B1'}),
          base,
          synced('r', base).copyWith(folderId: const LayerId('O')),
          createFolderLayer(id: const LayerId('O'), name: 'O'),
        ]),
        ['a', 'b'],
      )!;

      expect([for (final row in plan.layers) row.id.value], ['a', 'r', 'O']);
      expect(rowOf(plan.layers, 'r').folderId, const LayerId('O'));
    });

    test('the topmost taken from inside that folder stands in it, as any '
        'topmost row does, and the folder is the result\'s now', () {
      final base = row('base', {0: '1'});
      Layer gathered(String id) =>
          synced(id, base).copyWith(folderId: const LayerId('O'));
      final plan = merge(
        cutOf([
          base,
          gathered('r'),
          gathered('s'),
          createFolderLayer(id: const LayerId('O'), name: 'O'),
        ]),
        ['base', 'r'],
      )!;

      expect([for (final row in plan.layers) row.id.value], ['r', 's', 'O']);
      expect([for (final row in plan.layers) row.folderId?.value], [
        'O',
        'O',
        null,
      ]);
    });

    /// 🗣️I-78-Q14 (유저 2026-10-28): 「보이던 그대로 같이 굽는다」.
    test('🎯one chosen without its base is baked wearing it, and stands just '
        'outside the group when it is the topmost', () {
      final base = row('base', {0: '1'}, lastLength: 4);
      final plan = merge(
        cutOf([
          row('c', {0: 'C1'}),
          row('b', {0: 'B1'}),
          base,
          synced('r', base),
          synced('s', base),
        ]),
        ['b', 'c', 'r'],
      )!;

      expect(plan.result.id, const LayerId('r'));
      expect(plan.result.attachedToLayerId, isNull);
      expect(blocksOf(plan.result), {0: (2, 'R1'), 2: (2, 'R1-2')});
      expect([for (final row in plan.layers) row.id.value], [
        'base',
        's',
        'r',
      ]);
      expect(
        [
          for (final row in bakedOf(plan).layers) (row.id.value, row.isVisible),
        ],
        [('c', true), ('b', true), ('base', false), ('r', true)],
      );
      expect(plan.changes, isEmpty);
    });

    test('one riding below stands just under the group, over the rows left '
        'under it', () {
      final base = row('base', {0: '1'});
      Layer under(String id) => synced(
        id,
        base,
      ).copyWith(attachedPlacement: AttachedPlacement.below);
      final plan = merge(
        cutOf([
          row('c', {0: 'C1'}),
          row('k', {0: 'K1'}),
          under('r'),
          under('s'),
          base,
        ]),
        ['c', 'r'],
      )!;

      expect([for (final row in plan.layers) row.id.value], [
        'k',
        'r',
        's',
        'base',
      ]);
    });

    test('the folder that gathered it stays where it stood, and the result '
        'stands past the group as it stood, in the base\'s folder', () {
      final base = row('base', {0: '1'});
      final plan = merge(
        cutOf([
          row('c', {0: 'C1'}),
          base,
          synced('r', base).copyWith(folderId: const LayerId('O')),
          createFolderLayer(id: const LayerId('O'), name: 'O'),
        ]),
        ['c', 'r'],
      )!;

      expect([for (final row in plan.layers) row.id.value], [
        'base',
        'O',
        'r',
      ]);
      expect(plan.result.folderId, isNull);
    });

    test('one taken below the topmost row goes as any row does', () {
      final base = row('base', {0: '1'});
      final plan = merge(
        cutOf([base, synced('r', base), row('a', {0: 'A1'})]),
        ['a', 'r'],
      )!;

      expect([for (final row in plan.layers) row.id.value], ['base', 'a']);
      expect(blocksOf(plan.result), {0: (2, 'A1')});
    });

    test('a base one of whose riders this round passes over is passed over '
        'too: the rider would be baked anew', () {
      final base = row('base', {0: '1'});
      final rider = synced('r', base);
      final plan = merge(
        cutOf([row('c', {0: 'C1'}), row('b', {0: 'B1'}), base, rider]),
        ['base', 'b', 'c'],
        // A 겸용 attach row: its cels are its group's (④b).
        elsewhere: [
          cutOf(id: 'd', [
            base.copyWith(id: const LayerId('base2')),
            rider.copyWith(
              id: const LayerId('r2'),
              attachedToLayerId: const LayerId('base2'),
            ),
          ]),
        ],
        links: [
          ['c/r', 'd/r2'],
        ],
      )!;

      expect(plan.result.id, const LayerId('b'));
      expect([for (final row in plan.layers) row.id.value], ['b', 'base', 'r']);
    });
  });

  /// 🗣️I-78-Q9 (유저 2026-10-28): 「이어진 컷에서도 같이 병합한다」 · Q12
  /// 「컷마다 그 컷의 순서 · 타이밍대로 합친다」.
  group('a 겸용 row merges in every cut it is in', () {
    /// [row] as it is seen from another cut: [id], its cels its own.
    Layer self(Layer row, String id, {Map<int, TimelineExposure>? timeline}) =>
        row.copyWith(id: LayerId(id), timeline: timeline);

    test('🎯each cut merges the rows of its own that are the ones taken — '
        'one alone too — and the results are ONE layer: one name, one bank '
        'of cels, one row of the link table', () {
      final b = row('b', {0: 'B1'});
      final plan = merge(
        cutOf([row('c', {0: 'C1'}), b, row('a', {0: 'A1'})]),
        ['a', 'b', 'c'],
        elsewhere: [
          cutOf(id: 'd', [row('x', {0: 'X1'}), self(b, 'b2')]),
        ],
        links: [
          ['c/b', 'd/b2'],
        ],
      )!;

      expect([for (final row in plan.layers) row.id.value], ['a']);
      final (:cut, :layers) = plan.others.single;
      expect(cut.id, const CutId('d'));
      expect([for (final row in layers) row.id.value], ['x', 'b2']);
      final there = rowOf(layers, 'b2');
      expect(there.name, 'a', reason: 'a 겸용 layer wears one name');
      expect(there.frames, plan.result.frames, reason: 'one bank');
      expect(blocksOf(there), {0: (2, 'B1')}, reason: 'its own picture');
      expect(plan.links.groups, [
        LayerLinkGroup(
          id: 'link-1',
          members: const [
            LayerLinkMember(
              trackId: TrackId('t'),
              cutId: CutId('c'),
              layerId: LayerId('a'),
            ),
            LayerLinkMember(
              trackId: TrackId('t'),
              cutId: CutId('d'),
              layerId: LayerId('b2'),
            ),
          ],
        ),
      ], reason: 'the group the rows taken stood in gone with them');
    });

    test('the same picture in two cuts is one cel; another picture is a cel '
        'of its own', () {
      final a = row('a', {0: 'A1'});
      final b = row('b', {0: 'B1'});
      final plan = merge(
        cutOf([b, a]),
        ['a', 'b'],
        elsewhere: [
          cutOf(id: 'd', [
            self(b, 'b2'),
            self(
              a,
              'a2',
              timeline: {
                0: const TimelineExposure.drawing(FrameId('a-A1'), length: 1),
              },
            ),
          ]),
        ],
        links: [
          ['c/a', 'd/a2'],
          ['c/b', 'd/b2'],
        ],
      )!;

      final there = rowOf(plan.others.single.layers, 'a2');
      expect(blocksOf(plan.result), {0: (2, 'A1')});
      expect(blocksOf(there), {0: (1, 'A1'), 1: (1, 'B1')});
      expect([for (final cel in plan.result.frames) cel.name], ['A1', 'B1']);
      expect(there.frames, plan.result.frames);
      expect(plan.pictures, hasLength(2), reason: 'each cel drawn once');
    });

    test('a cut stands its result where its own topmost row stood, and the '
        'results keep their cels where the link table keeps them now', () {
      final a = row('a', {0: 'A1'});
      final b = row('b', {0: 'B1'});
      final plan = merge(
        cutOf([b, a]),
        ['a', 'b'],
        elsewhere: [
          cutOf(id: 'd', [self(a, 'a2'), row('y', {0: 'Y1'}), self(b, 'b2')]),
        ],
        links: [
          ['d/a2', 'c/a'],
          ['c/b', 'd/b2'],
        ],
      )!;

      expect([for (final row in plan.others.single.layers) row.id.value], [
        'y',
        'a2',
      ], reason: 'where b2 stood, keeping the id the cels are kept under');
      expect(
        plan.links.groups.single.members.first.layerId,
        const LayerId('a2'),
      );
    });

    test('a row with a self in its own cut stays, and the others merge', () {
      final b = row('b', {0: 'B1'});
      final plan = merge(
        cutOf([row('x', {0: 'X1'}), b, self(b, 'bb'), row('a', {0: 'A1'})]),
        ['a', 'b', 'x'],
        links: [
          ['c/b', 'c/bb'],
        ],
      )!;

      expect([for (final row in plan.layers) row.id.value], ['b', 'bb', 'a']);
      expect(plan.others, isEmpty);
      expect(plan.links.groups, hasLength(1));
    });

    test('where it reaches across cuts, a row an attach row rides stays (④b)',
        () {
      final a = row('a', {0: 'A1'});
      final base = row('base', {0: '1'});
      final plan = merge(
        cutOf([row('x', {0: 'X1'}), base, synced('r', base), a]),
        ['a', 'base', 'x'],
        elsewhere: [
          cutOf(id: 'd', [self(a, 'a2')]),
        ],
        links: [
          ['c/a', 'd/a2'],
        ],
      )!;

      expect([for (final row in plan.layers) row.id.value], [
        'base',
        'r',
        'a',
      ]);
      expect([for (final row in plan.others.single.layers) row.id.value], [
        'a2',
      ]);
    });

    test('a folder whose self elsewhere holds a row another cut keeps stays '
        'whole, and the others merge', () {
      Layer inF2(Layer row, String id) =>
          self(row, id).copyWith(folderId: const LayerId('F2'));
      final m = row('m', {0: 'M1'}, inside: 'F');
      final v = row('v', {0: 'V1'});

      final plan = merge(
        cutOf([
          m,
          createFolderLayer(id: const LayerId('F'), name: 'F'),
          v,
          row('w', {0: 'W1'}),
          row('u', {0: 'U1'}),
        ]),
        ['F', 'w', 'u'],
        elsewhere: [
          cutOf(id: 'd', [
            inF2(m, 'm2'),
            inF2(v, 'v2'),
            createFolderLayer(id: const LayerId('F2'), name: 'F'),
          ]),
        ],
        links: [
          ['c/F', 'd/F2'],
          ['c/m', 'd/m2'],
          ['c/v', 'd/v2'],
        ],
      )!;

      expect([for (final row in plan.layers) row.id.value], [
        'm',
        'F',
        'v',
        'u',
      ]);
      expect(plan.others, isEmpty);
    });

    test('a row whose self a cut cannot merge stays — a folder holding no '
        'picture there', () {
      final b = row('b', {0: 'B1'});
      final plan = merge(
        cutOf([
          row('m', {0: 'M1'}, inside: 'F'),
          createFolderLayer(id: const LayerId('F'), name: 'F'),
          b,
          row('a', {0: 'A1'}),
        ]),
        ['F', 'b', 'a'],
        elsewhere: [
          cutOf(id: 'd', [
            createFolderLayer(id: const LayerId('F2'), name: 'F'),
            self(b, 'b2'),
          ]),
        ],
        links: [
          ['c/F', 'd/F2'],
          ['c/b', 'd/b2'],
        ],
      )!;

      expect([for (final row in plan.layers) row.id.value], ['m', 'F', 'a']);
      expect([for (final row in plan.others.single.layers) row.id.value], [
        'F2',
        'b2',
      ]);
    });

    test('where it reaches across cuts, a row whose self there an attach row '
        'rides stays (④b)', () {
      final a = row('a', {0: 'A1'});
      final there = self(a, 'a2');
      final plan = merge(
        cutOf([row('c', {0: 'C1'}), row('b', {0: 'B1'}), a]),
        ['a', 'b', 'c'],
        elsewhere: [
          cutOf(id: 'd', [there, synced('r2', there)]),
        ],
        links: [
          ['c/a', 'd/a2'],
        ],
      )!;

      expect([for (final row in plan.layers) row.id.value], ['b', 'a']);
      expect(plan.others, isEmpty);
    });

    test('a picture another cut shows past the wall is warned of, as one of '
        'the cut pressed is (Q19)', () {
      final b = row('b', {0: 'B1'});
      // b's cel as cut d shows it, inked past the canvas's left edge.
      const past = (left: -8, top: 0, rightExclusive: 8, bottomExclusive: 8);
      for (final (inks, changes) in [
        (const <String, Never>{}, <LayerMergeChange>{}),
        (const {'b2/b-B1': past}, {LayerMergeChange.wall}),
      ]) {
        expect(
          merge(
            cutOf([row('c', {0: 'C1'}), b, row('a', {0: 'A1'})]),
            ['a', 'b', 'c'],
            elsewhere: [
              cutOf(id: 'd', [row('x', {0: 'X1'}), self(b, 'b2')]),
            ],
            links: [
              ['c/b', 'd/b2'],
            ],
            inks: inks,
          )!.changes,
          changes,
        );
      }
    });
  });

  /// 🗣️I-78-Q20 (유저 2026-10-30): 「트랙의 모든 컷에서 같이 병합」 — the
  /// option's 「콘티가 있는 컷마다 그 컷의 두 행을 그 컷의 타이밍대로 보이던
  /// 그대로 합친다 … 결과는 트랙 구조에서 맨 위 행 자리에 서고 모든 컷이 같은
  /// 구조를 유지 … 콘티 행과 보통 행이 섞이면 콘티 행은 건너뛴다」.
  group("the conte's rows merge in every cut of its track (Q20)", () {
    /// A cut's conte [id]: its panel `1` over frames 0–1, `2` over 2–3.
    Layer conte(String id) =>
        row(id, {0: '1', 2: '2'}, kind: LayerKind.storyboard);

    /// [id] riding [base] as the track's conte row [key] — synced, its cel
    /// `R<n>` showing wherever [base]'s `<n>` does — filed [inside].
    Layer onIt(String id, Layer base, String key, {String? inside}) =>
        synced(id, base).copyWith(
          kind: LayerKind.storyboard,
          conteKey: ConteKey(key),
          folderId: inside == null ? null : LayerId(inside),
        );

    /// The mirror of [conteCel] the result kept under [row] holds.
    FrameId mirror(String row, String conteCel) =>
        attachedMirrorCelId(LayerId(row), FrameId(conteCel));

    test('🎯chosen alone, they merge in every cut that has the conte — '
        "each cut's own, by its own timing — and the result rides the conte "
        "as the topmost one's row of the track, following its panels", () {
      final s = conte('s');
      final t = conte('t');
      final plan = merge(
        cutOf([s, onIt('k1', s, 'K1'), onIt('k2', s, 'K2')]),
        ['k1', 'k2'],
        elsewhere: [
          cutOf(id: 'd', [t, onIt('j1', t, 'K1'), onIt('j2', t, 'K2')]),
        ],
      )!;

      final result = plan.result;
      expect([for (final row in plan.layers) row.id.value], ['s', 'k2']);
      expect(
        [result.attachedToLayerId, result.conteKey, result.kind],
        [s.id, const ConteKey('K2'), LayerKind.storyboard],
      );
      expect(result.attachedMode, AttachedMode.synced);
      expect(result.timeline, isEmpty, reason: 'its timing the conte\'s');
      expect(result.baseFrameLinks, {
        const FrameId('s-1'): mirror('k2', 's-1'),
        const FrameId('s-2'): mirror('k2', 's-2'),
      });
      expect([for (final cel in result.frames) cel.name], ['R1', 'R2']);
      final (:cut, :layers) = plan.others.single;
      expect(cut.id, const CutId('d'));
      expect([for (final row in layers) row.id.value], ['t', 'j2']);
      final there = rowOf(layers, 'j2');
      expect(
        [there.attachedToLayerId, there.conteKey, there.name],
        [t.id, const ConteKey('K2'), 'k2'],
      );
      expect(there.baseFrameLinks, {
        const FrameId('t-1'): mirror('j2', 't-1'),
        const FrameId('t-2'): mirror('j2', 't-2'),
      }, reason: 'its own cels — the cuts are no 겸용 pair');
      expect(
        plan.links.groups,
        isEmpty,
        reason: "a track's conte rows are no link (conteHeadTargets)",
      );
      expect([
        for (final picture in plan.pictures)
          '${picture.into.id.value}/${picture.rowId.value}',
      ], ['c/k2', 'c/k2', 'd/j2', 'd/j2']);
    });

    test('one keeping a timing of its own leaves the result one of its own — '
        'a cel wherever what they show changes', () {
      final s = conte('s');
      final plan = merge(
        cutOf([
          s,
          row('k1', {0: 'F1'}, lastLength: 4, kind: LayerKind.storyboard)
              .copyWith(
                attachedToLayerId: s.id,
                attachedMode: AttachedMode.free,
                conteKey: const ConteKey('K1'),
              ),
          onIt('k2', s, 'K2'),
        ]),
        ['k1', 'k2'],
      )!;

      expect(plan.result.attachedMode, AttachedMode.free);
      expect(plan.result.baseFrameLinks, isEmpty);
      expect(blocksOf(plan.result), {0: (2, 'R1'), 2: (2, 'R2')});
    });

    test('what the conte lays over them — its keys, its fx — is not baked: '
        'the result wears it after, riding it as they did', () {
      final s = conte('s').copyWith(
        transformTrack: TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>.empty().withKey(
            0,
            CanvasPoint(x: 8, y: 0),
          ),
        ),
        effects: [
          LayerEffect(
            id: const EffectId('fx'),
            kind: EffectKind.brightnessContrast,
          ),
        ],
      );
      final plan = merge(
        cutOf([s, onIt('k1', s, 'K1'), onIt('k2', s, 'K2')]),
        ['k1', 'k2'],
      )!;

      final worn = rowOf(bakedOf(plan).layers, 's');
      expect(
        [worn.isVisible, worn.transformTrack.isEmpty, worn.effects],
        [false, isTrue, isEmpty],
      );
      expect(rowOf(plan.layers, 's'), s, reason: 'the conte as it was');
    });

    test('⛔chosen with rows of the cut\'s own, they are passed over — and '
        'with one row of its own, nothing merges', () {
      final s = conte('s');
      final layers = [
        s,
        onIt('k1', s, 'K1'),
        onIt('k2', s, 'K2'),
        row('n1', {0: 'N1'}),
        row('n2', {0: 'N2'}),
      ];

      final plan = merge(cutOf(layers), ['n1', 'n2', 'k1', 'k2'])!;
      expect([for (final row in plan.layers) row.id.value], [
        's',
        'k1',
        'k2',
        'n2',
      ]);
      expect(merge(cutOf(layers), ['n1', 'k1', 'k2']), isNull);
    });

    test('the conte itself chosen with them is passed over — no row of the '
        "cut's own a merge takes while a row rides it", () {
      final s = conte('s');
      final plan = merge(
        cutOf([s, onIt('k1', s, 'K1'), onIt('k2', s, 'K2')]),
        ['s', 'k1', 'k2'],
      )!;

      expect([for (final row in plan.layers) row.id.value], ['s', 'k2']);
    });

    /// The track's 공정 folder `KP` [id], named [name].
    Layer filing(String id, {String name = 'Lines'}) => createFolderLayer(
      id: LayerId(id),
      name: name,
    ).copyWith(conteKey: const ConteKey('KP'));

    test('a 공정 folder taken is the row (Q5) — wearing its name, kept in '
        "every cut as the topmost picture row's row of the track: a folder "
        'filing nothing, the structure forgets', () {
      final s = conte('s');
      final t = conte('t');
      final plan = merge(
        cutOf([
          s,
          onIt('k1', s, 'K1', inside: 'P'),
          onIt('k2', s, 'K2', inside: 'P'),
          filing('P'),
        ]),
        ['P'],
        elsewhere: [
          cutOf(id: 'd', [
            t,
            onIt('j1', t, 'K1', inside: 'Q'),
            onIt('j2', t, 'K2', inside: 'Q'),
            filing('Q'),
          ]),
        ],
      )!;

      expect([for (final row in plan.layers) row.id.value], ['s', 'k2']);
      expect([for (final row in plan.others.single.layers) row.id.value], [
        't',
        'j2',
      ]);
      expect(
        [
          plan.result.name,
          plan.result.conteKey,
          plan.result.kind,
          plan.result.folderId,
        ],
        ['Lines', const ConteKey('K2'), LayerKind.storyboard, null],
      );
    });

    test('chosen inside a 공정 folder, under the conte, the result stays '
        'filed there and rides under it', () {
      final s = conte('s');
      Layer under(String id, String key) => onIt(
        id,
        s,
        key,
        inside: 'P',
      ).copyWith(attachedPlacement: AttachedPlacement.below);
      final plan = merge(
        cutOf([under('k1', 'K1'), under('k2', 'K2'), filing('P'), s]),
        ['k1', 'k2'],
      )!;

      expect([for (final row in plan.layers) row.id.value], ['k2', 'P', 's']);
      expect(
        [plan.result.folderId, plan.result.attachedPlacement],
        [const LayerId('P'), AttachedPlacement.below],
      );
    });

    test("a 겸용 pair's 공정 folder: each cut's result is its keeper's self "
        'there, the cels kept where the table keeps the keeper\'s', () {
      final s = conte('s');
      final k1 = onIt('k1', s, 'K1', inside: 'P');
      final k2 = onIt('k2', s, 'K2', inside: 'P');
      Layer self(Layer row, String id) => row.copyWith(
        id: LayerId(id),
        folderId: row.folderId == null ? null : const LayerId('P2'),
        attachedToLayerId: row.attachedToLayerId == null
            ? null
            : const LayerId('s2'),
      );
      final plan = merge(
        cutOf([s, k1, k2, filing('P')]),
        ['P'],
        elsewhere: [
          cutOf(id: 'd', [
            self(s, 's2'),
            self(k1, 'k1d'),
            self(k2, 'k2d'),
            filing('P2'),
          ]),
        ],
        links: [
          ['c/s', 'd/s2'],
          ['c/k1', 'd/k1d'],
          ['d/k2d', 'c/k2'],
          ['c/P', 'd/P2'],
        ],
      )!;

      expect([for (final row in plan.others.single.layers) row.id.value], [
        's2',
        'k2d',
      ]);
      expect(plan.links.groups.last.members, const [
        LayerLinkMember(
          trackId: TrackId('t'),
          cutId: CutId('d'),
          layerId: LayerId('k2d'),
        ),
        LayerLinkMember(
          trackId: TrackId('t'),
          cutId: CutId('c'),
          layerId: LayerId('k2'),
        ),
      ]);
    });

    test('a pair linked by another of its rows: the cut the keeper has no '
        "self in keeps its own keeper's id, not its folder's", () {
      final s = conte('s');
      final t = conte('t');
      final plan = merge(
        cutOf([
          s,
          onIt('k1', s, 'K1', inside: 'P'),
          onIt('k2', s, 'K2', inside: 'P'),
          filing('P'),
        ]),
        ['P'],
        elsewhere: [
          cutOf(id: 'd', [
            t,
            onIt('j1', t, 'K1', inside: 'Q'),
            onIt('j2', t, 'K2', inside: 'Q'),
            filing('Q'),
          ]),
        ],
        links: [
          ['c/k1', 'd/j1'],
        ],
      )!;

      expect([for (final row in plan.others.single.layers) row.id.value], [
        't',
        'j2',
      ]);
      expect(
        [
          for (final member in plan.links.groups.single.members)
            '${member.cutId.value}/${member.layerId.value}',
        ],
        ['c/k2', 'd/j2'],
      );
    });

    test('two 겸용 pairs on the track merge as two layers — each a row of '
        'the link table of its own', () {
      Cut pair(String cut, String conteId, String prefix) {
        final base = conte(conteId);
        return cutOf(id: cut, [
          base,
          onIt('${prefix}1', base, 'K1'),
          onIt('${prefix}2', base, 'K2'),
        ]);
      }

      final plan = merge(
        pair('c', 's', 'k'),
        ['k1', 'k2'],
        elsewhere: [
          pair('d', 's', 'k').copyWith(
            layers: [
              for (final row in pair('d', 's', 'k').layers)
                row.copyWith(
                  id: LayerId('${row.id.value}d'),
                  attachedToLayerId: row.attachedToLayerId == null
                      ? null
                      : const LayerId('sd'),
                ),
            ],
          ),
          pair('e', 'u', 'm'),
          pair('f', 'u', 'm').copyWith(
            layers: [
              for (final row in pair('f', 'u', 'm').layers)
                row.copyWith(
                  id: LayerId('${row.id.value}f'),
                  attachedToLayerId: row.attachedToLayerId == null
                      ? null
                      : const LayerId('uf'),
                ),
            ],
          ),
        ],
        links: [
          for (final (one, other, rows) in const [
            ('c', 'd', ['s', 'k1', 'k2']),
            ('e', 'f', ['u', 'm1', 'm2']),
          ])
            for (final row in rows) ['$one/$row', '$other/$row$other'],
        ],
      )!;

      expect(plan.links.groups, hasLength(4), reason: "the contes' kept");
      expect({for (final group in plan.links.groups) group.id}, hasLength(4));
      expect(
        [
          for (final group in plan.links.groups.skip(2))
            [for (final member in group.members) member.layerId.value],
        ],
        [
          ['k2', 'k2d'],
          ['m2', 'm2f'],
        ],
      );
    });

    test("🎯a 겸용 pair's cuts merge as ONE layer — one bank, one row of the "
        'link table — and a cut of the track no pair links, as its own', () {
      final s = conte('s');
      final k1 = onIt('k1', s, 'K1');
      final k2 = onIt('k2', s, 'K2');
      Layer self(Layer row, String id) => row.copyWith(
        id: LayerId(id),
        attachedToLayerId: row.attachedToLayerId == null
            ? null
            : const LayerId('s2'),
      );
      final u = conte('u');
      final plan = merge(
        cutOf([s, k1, k2]),
        ['k1', 'k2'],
        elsewhere: [
          cutOf(id: 'd', [self(s, 's2'), self(k1, 'k1d'), self(k2, 'k2d')]),
          cutOf(id: 'e', [u, onIt('m1', u, 'K1'), onIt('m2', u, 'K2')]),
        ],
        links: [
          ['c/s', 'd/s2'],
          ['c/k1', 'd/k1d'],
          ['c/k2', 'd/k2d'],
        ],
      )!;

      Layer resultIn(String cut, String id) => rowOf(
        plan.others.firstWhere((other) => other.cut.id == CutId(cut)).layers,
        id,
      );
      expect(resultIn('d', 'k2d').frames, plan.result.frames);
      expect(resultIn('d', 'k2d').baseFrameLinks, plan.result.baseFrameLinks);
      expect(resultIn('e', 'm2').baseFrameLinks, {
        const FrameId('u-1'): mirror('m2', 'u-1'),
        const FrameId('u-2'): mirror('m2', 'u-2'),
      });
      expect(plan.links.groups.last.members, const [
        LayerLinkMember(
          trackId: TrackId('t'),
          cutId: CutId('c'),
          layerId: LayerId('k2'),
        ),
        LayerLinkMember(
          trackId: TrackId('t'),
          cutId: CutId('d'),
          layerId: LayerId('k2d'),
        ),
      ]);
      expect(plan.links.groups, hasLength(2), reason: "the contes' kept");
      expect([
        for (final picture in plan.pictures)
          '${picture.into.id.value}/${picture.rowId.value}',
      ], ['c/k2', 'c/k2', 'e/m2', 'e/m2']);
    });

    test('a panel shown as two pictures leaves the result a timing of its '
        'own — a cel of the conte has one mirror', () {
      final s = conte('s');
      final plan = merge(
        cutOf([
          s,
          onIt('k1', s, 'K1', inside: 'P'),
          onIt('k2', s, 'K2', inside: 'P'),
          createFolderLayer(id: const LayerId('P'), name: 'P').copyWith(
            conteKey: const ConteKey('KP'),
            transformTrack: TransformTrack.empty().copyWith(
              position: PropertyTrack<CanvasPoint>.empty()
                  .withKey(0, CanvasPoint(x: 0, y: 0))
                  .withKey(1, CanvasPoint(x: 8, y: 0)),
            ),
          ),
        ]),
        ['P'],
      )!;

      expect(plan.result.attachedMode, AttachedMode.free);
      expect(blocksOf(plan.result), {
        0: (1, 'R1'),
        1: (1, 'R1-2'),
        2: (2, 'R2'),
      });
    });

    test('…and one picture shown over two panels does too', () {
      final s = conte('s');
      Layer onBoth(String id, String key) => onIt(id, s, key).copyWith(
        baseFrameLinks: {
          const FrameId('s-1'): FrameId('$id-1'),
          const FrameId('s-2'): FrameId('$id-1'),
        },
      );
      final plan = merge(
        cutOf([s, onBoth('k1', 'K1'), onBoth('k2', 'K2')]),
        ['k1', 'k2'],
      )!;

      expect(plan.result.attachedMode, AttachedMode.free);
      expect(blocksOf(plan.result), {0: (4, 'R1')});
    });
  });

  /// 🗣️I-78-Q15 (유저 2026-10-28): 「참조도 그대로 병합한다」.
  group('a reference row is baked as it shows', () {
    /// A reference row showing a [width] × [height] file at the canvas's
    /// centre at [scale], moved by [moves] — its pixels laid [laidAt], at
    /// the centre unless a test says otherwise.
    Layer still(
      int width,
      int height, {
      double scale = 1,
      TransformTrack? moves,
      CanvasPoint? laidAt,
    }) {
      final centre = CanvasPoint(x: 32, y: 18);
      return row(
        'still',
        {0: 'P1'},
        kind: LayerKind.image,
        transformTrack: moves,
      ).copyWith(
        mediaReference: MediaReference(
          assetPath: 'paper.png',
          pose: TransformPose(center: centre, scaleX: scale, scaleY: scale),
          laid: TransformPose(center: laidAt ?? centre),
          pictureSize: CanvasSize(width: width, height: height),
        ),
      );
    }
    Cut around(Layer still) =>
        cutOf([row('b', {0: 'B1'}), still, row('a', {0: 'A1'})]);

    test('🎯and where its file lies past the wall, what lies there is '
        'warned of', () {
      final plan = merge(around(still(640, 360)), ['a', 'b', 'still'])!;

      expect([for (final row in plan.layers) row.id.value], ['a']);
      expect([for (final layer in bakedOf(plan).layers) layer.id.value], [
        'b',
        'still',
        'a',
      ]);
      expect(plan.changes, {LayerMergeChange.wall});
    });

    test('one laid inside the wall, to its edges, is not', () {
      final plan = merge(around(still(64, 36)), ['a', 'still'])!;

      expect(plan.changes, isEmpty);
    });

    test('the wall is the one its pictures are drawn over: a file past the '
        'canvas that the pasteboard holds is not', () {
      final cut = around(still(96, 54));

      expect(merge(cut, ['a', 'still'])!.changes, {LayerMergeChange.wall});
      expect(
        merge(cut, ['a', 'still'], reach: PasteboardReach.whole)!.changes,
        isEmpty,
      );
    });

    test('it is read where the row shows the file: laid past the wall and '
        'shown inside it, nothing is cut; laid inside and moved past it by '
        'the row\'s keys, what lies there is', () {
      final moved = TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty().withKey(
          0,
          CanvasPoint(x: 64, y: 18),
        ),
      );

      for (final shownInside in [
        still(640, 360, scale: 0.1),
        still(64, 36, laidAt: CanvasPoint(x: 632, y: 18)),
      ]) {
        expect(merge(around(shownInside), ['a', 'still'])!.changes, isEmpty);
      }
      expect(
        merge(around(still(64, 36, moves: moved)), ['a', 'still'])!.changes,
        {LayerMergeChange.wall},
      );
    });

    test('one not shown at a frame the merge draws cuts nothing', () {
      final unshown = still(640, 360).copyWith(timeline: const {});

      expect(merge(around(unshown), ['a', 'b', 'still'])!.changes, isEmpty);
    });

    test('a base worn hidden shows no file to cut', () {
      final base = still(640, 360);
      final plan = merge(
        cutOf([row('c', {0: 'C1'}), base, synced('r', base)]),
        ['c', 'r'],
      )!;

      expect(plan.changes, isEmpty);
    });
  });

  /// 🗣️I-78-Q19 (유저 2026-10-28): 「보통 그림도 같은 경고」.
  group('a drawing is warned of at the wall as a reference is', () {
    /// A position keyed [dx] to the right of the canvas's centre.
    TransformTrack movedBy(double dx) => TransformTrack.empty().copyWith(
      position: PropertyTrack<CanvasPoint>.empty().withKey(
        0,
        CanvasPoint(x: 32 + dx, y: 18),
      ),
    );

    /// `a`'s cel `A1` inked up to the canvas's right edge, `A2` past it.
    const inks = {
      'a/a-A1': (left: 48, top: 0, rightExclusive: 64, bottomExclusive: 36),
      'a/a-A2': (left: 56, top: 0, rightExclusive: 72, bottomExclusive: 16),
    };

    test('🎯one its keys move past the wall is cut there; one inside it, to '
        'its edges, is not', () {
      for (final (moves, changes) in [
        (null, <LayerMergeChange>{}),
        (movedBy(16), {LayerMergeChange.wall}),
      ]) {
        final cut = cutOf([
          row('b', {0: 'B1'}),
          row('a', {0: 'A1'}, transformTrack: moves),
        ]);

        expect(
          merge(cut, ['a', 'b'], inks: inks)!.changes,
          changes,
          reason: 'moved: ${moves != null}',
        );
      }
    });

    test('a folder moving it moves it as its own keys do — but one the '
        'result stays in moves the result after, and cuts nothing', () {
      final folder = createFolderLayer(
        id: const LayerId('F'),
        name: 'F',
      ).copyWith(transformTrack: movedBy(16));
      final a = row('a', {0: 'A1'}, inside: 'F');
      final b = row('b', {0: 'B1'});

      for (final (stands, layers, changes) in [
        ('over F', [a, folder, b], {LayerMergeChange.wall}),
        ('in F', [b, a, folder], {LayerMergeChange.folder}),
      ]) {
        expect(
          merge(cutOf(layers), ['a', 'b'], inks: inks)!.changes,
          changes,
          reason: 'the result stands $stands',
        );
      }
    });

    test('the ink is the cel\'s the row shows at the frame drawn', () {
      final cut = cutOf([
        row('b', {0: 'B1'}),
        row('a', {0: 'A1', 1: 'A2'}),
      ]);

      expect(merge(cut, ['a', 'b'], inks: inks)!.changes, {
        LayerMergeChange.wall,
      });
    });

    test('what the pasteboard holds past the canvas is not cut', () {
      final cut = cutOf([
        row('b', {0: 'B1'}),
        row('a', {0: 'A1'}, transformTrack: movedBy(16)),
      ]);

      expect(
        merge(
          cut,
          ['a', 'b'],
          inks: inks,
          reach: PasteboardReach.whole,
        )!.changes,
        isEmpty,
      );
    });
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

      final merged = rowOf(plan.layers, 'a');
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

      expect(blocksOf(rowOf(some.layers, 'a')), {0: (4, 'A1-2'), 4: (2, 'A1')});
      expect([for (final cel in rowOf(some.layers, 'a').frames) cel.id.value], [
        'a-A1',
        'm0',
      ]);
      expect(blocksOf(rowOf(all.layers, 'a')), {0: (6, 'A1')});
      expect(laidOf(all.pictures.single), ['a-A2', 'a-A1']);
    });

    test('the run keeps its outer edges: on each side the mode of the '
        'carrier nearest it — one standing inside its run too, as a hold set '
        'before frames were glued on past it does — and a bound one of them '
        'claimed', () {
      Layer mergedOf(Layer row, List<int> starts) =>
          rowOf(mergeBlocks(cutOf([row]), {'a': starts})!.layers, 'a');

      // Two runs, the frame at 4 between them.
      final held = mergedOf(
        marked(
          'a',
          {0: (2, 'A1'), 2: (2, 'A2'), 5: (2, 'A3'), 7: (2, 'A4')},
          starting: {2: holdMark, 5: repeatMark},
          ending: {0: holdMark, 5: repeatMark},
        ),
        [0, 2, 5, 7],
      );
      final bounded = mergedOf(
        marked(
          'a',
          {0: (2, 'A1'), 2: (2, 'A2'), 4: (2, 'A3')},
          ending: {2: boundMark, 4: repeatMark},
        ),
        [0, 2],
      );

      expect((held.timeline[0]!.startEdge, held.timeline[0]!.endEdge), (
        holdMark,
        repeatMark,
      ));
      expect(
        (bounded.timeline[0]!.endEdge, bounded.timeline[4]!.endEdge),
        (boundMark, repeatMark),
        reason: 'A3\'s repeat still starts at the block A2 became',
      );
    });

    test('a cel that goes takes its sounds with it (REC1-A)', () {
      final plan = mergeBlocks(
        cutOf([
          row('a', {0: 'A1', 2: 'A2', 4: 'A3'}).copyWith(
            audioClips: [
              for (final cel in ['A1', 'A3'])
                AudioClip(filePath: 'take.wav', frameId: FrameId('a-$cel')),
            ],
          ),
        ]),
        {
          'a': [0, 2],
        },
      )!;

      expect(
        [
          for (final clip in rowOf(plan.layers, 'a').audioClips)
            clip.frameId.value,
        ],
        ['a-A3'],
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
      expect(blocksOf(rowOf(plan.layers, 'b')), {0: (4, 'B1')});
      expect(blocksOf(rowOf(plan.layers, 'c')), blocksOf(cut.layers.first));
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

      final rider = rowOf(plan.layers, 'r');
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

    test('a synced one showing nothing over the run — its link there to a '
        'cel it no longer has — is drawn of nothing, and its cels the merge '
        'did not unlink stay', () {
      final base = row('a', {0: '1', 2: '2', 4: '3'});
      final plan = mergeBlocks(
        cutOf([
          base,
          synced('r', base).copyWith(
            baseFrameLinks: {
              const FrameId('a-1'): const FrameId('r-gone'),
              const FrameId('a-3'): const FrameId('r-3'),
            },
          ),
        ]),
        {
          'a': [0, 2],
        },
      )!;

      expect([for (final picture in plan.pictures) picture.rowId.value], [
        'a',
      ]);
      expect([for (final cel in rowOf(plan.layers, 'r').frames) cel.id.value], [
        'r-1',
        'r-2',
        'r-3',
        'attach-mirror-r-m0',
      ]);
    });

    test('a cel of its that a cel the base keeps still shows stays, and the '
        'new mirror wears its name\'s tail', () {
      final base = row('a', {0: '1', 2: '2', 4: '3'});
      final plan = mergeBlocks(
        cutOf([
          base,
          synced('r', base).copyWith(
            baseFrameLinks: {
              const FrameId('a-1'): const FrameId('r-1'),
              const FrameId('a-2'): const FrameId('r-2'),
              const FrameId('a-3'): const FrameId('r-1'),
            },
          ),
        ]),
        {
          'a': [0, 2],
        },
      )!;

      expect(
        [
          for (final cel in rowOf(plan.layers, 'r').frames)
            (cel.id.value, cel.name),
        ],
        [('r-1', 'R1'), ('r-3', 'R3'), ('attach-mirror-r-m0', 'R1-2')],
      );
    });
  });
}
