import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart'
    show attachedMirrorCelId, cutWithReconciledAttachedMirrors;
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/import/import_warning.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/camera_pose_resolver.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/import/clip_document.dart';
import 'package:anicel/src/services/import/clip_import_planner.dart';
import 'package:anicel/src/services/import/clip_placement.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';

/// The shape a CLIP STUDIO file opens as (보드 `csp-clip-import-analysis`,
/// the 10-07 「상담 끝」 memo): every timeline a 겸용 cut, folders as they
/// are, an animation folder a folder row over a base and the attach rows
/// its cels' other layers make — and the look kept by baking.
///
/// The documents are built here, layer by layer: the samples are work
/// files and stay out of the repository.
void main() {
  var nextId = 0;
  final picture = ClipPictureSource(attribute: Uint8List(1), blocksId: 'x');

  ClipLayer layer(
    String name, {
    bool shown = true,
    int opacity = 256,
    int composite = 0,
    bool drawn = true,
    ClipLayerKind kind = ClipLayerKind.raster,
    List<String> vectorData = const [],
  }) {
    nextId += 1;
    return ClipLayer(
      id: nextId,
      name: name,
      kind: kind,
      visibility: shown ? 1 : 0,
      opacity: opacity,
      composite: composite,
      folderFlags: 0,
      isAnimationFolder: false,
      uuid: 'uuid$nextId',
      left: 0,
      top: 0,
      offsetX: 0,
      offsetY: 0,
      render: drawn ? picture : null,
      original: null,
      originalTransform: null,
      vectorData: vectorData,
      children: const [],
    );
  }

  /// A folder; [children] bottom to top, as the file chains them.
  ClipLayer folder(
    String name,
    List<ClipLayer> children, {
    bool shown = true,
    int opacity = 256,
    int composite = 30,
    bool collapsed = false,
    bool animation = false,
    ClipPlacement? camera,
  }) {
    nextId += 1;
    return ClipLayer(
      id: nextId,
      name: name,
      kind: ClipLayerKind.folder,
      visibility: shown ? 1 : 0,
      opacity: opacity,
      composite: composite,
      folderFlags: collapsed ? 17 : 1,
      isAnimationFolder: animation,
      uuid: 'uuid$nextId',
      left: 0,
      top: 0,
      offsetX: 0,
      offsetY: 0,
      render: null,
      original: null,
      originalTransform: null,
      camera: camera,
      children: children,
    );
  }

  ClipLayer animation(String name, List<ClipLayer> cels, {int composite = 2}) =>
      folder(name, cels, animation: true, composite: composite);

  ClipLayer root(List<ClipLayer> children) {
    nextId += 1;
    return ClipLayer(
      id: nextId,
      name: '',
      kind: ClipLayerKind.root,
      visibility: 1,
      opacity: 256,
      composite: 0,
      folderFlags: 1,
      isAnimationFolder: false,
      uuid: 'uuid$nextId',
      left: 0,
      top: 0,
      offsetX: 0,
      offsetY: 0,
      render: null,
      original: null,
      originalTransform: null,
      children: children,
    );
  }

  /// [layer]'s track: one clip over [span] keying [keys] — (frame, cel).
  MapEntry<String, ClipTrack> keyed(
    ClipLayer layer,
    List<(int, String)> keys, {
    ClipSpan span = (start: 0, end: 12),
    List<int> labels = const [],
  }) => MapEntry(
    layer.uuid,
    ClipTrack(
      kind: 2000,
      pieces: [
        (
          span: span,
          cels: [for (final (frame, cel) in keys) (frame: frame, cel: cel)],
        ),
      ],
      labels: labels,
    ),
  );

  /// [layer]'s track showing it over [spans].
  MapEntry<String, ClipTrack> shownOver(
    ClipLayer layer,
    List<ClipSpan> spans,
  ) => MapEntry(
    layer.uuid,
    ClipTrack(
      kind: 2001,
      pieces: [for (final span in spans) (span: span, cels: const [])],
      labels: const [],
    ),
  );

  ClipTimeline timeline(
    List<MapEntry<String, ClipTrack>> tracks, {
    String name = 'c1',
    int end = 12,
    double fps = 24,
  }) => ClipTimeline(
    name: name,
    fps: fps,
    start: 0,
    end: end,
    tracks: Map.fromEntries(tracks),
  );

  ClipImportPlan plan(
    ClipLayer tree,
    List<ClipTimeline> timelines, {
    Map<String, String> sounds = const {},
    ClipFrame? frame,
  }) {
    var layers = 0;
    var frames = 0;
    var cuts = 0;
    return planClipImport(
      document: ClipDocument(
        width: 640,
        height: 360,
        root: tree,
        timelines: timelines,
        currentTimeline: 0,
        warnings: const [],
        frame: frame,
      ),
      name: 'file',
      trackId: const TrackId('track'),
      mint: ImportIdMint(
        nextLayerId: () => LayerId('layer-${layers += 1}'),
        nextFrameId: (_) => FrameId('frame-${frames += 1}'),
        nextCutId: () => CutId('cut-${cuts += 1}'),
      ),
      soundPaths: sounds,
    );
  }

  Layer row(Cut cut, String name) =>
      cut.layers.singleWhere((layer) => layer.name == name);

  /// The rows the file made, bottom first — the default cut's fixtures
  /// (direction, camera) left out.
  List<String> names(Cut cut) => [
    for (final layer in cut.layers)
      if (layer.kind != LayerKind.instruction &&
          layer.kind != LayerKind.camera)
        layer.name,
  ];

  /// [layer]'s blocks as (start, length, cel name).
  List<(int, int, String?)> blocks(Layer layer) => [
    for (final MapEntry(key: start, value: exposure)
        in layer.timeline.entries)
      if (!exposure.ghost)
        (start, exposure.length!, layer.frameById(exposure.frameId!)?.name),
  ];

  group('one timeline', () {
    test('🎯a folder stays a folder — nesting, eye, opacity, blend and the '
        'fold — and a layer outside the cels is an image row holding its '
        'one picture, named 1', () {
      final bg = layer('BG', opacity: 128, composite: 2);
      final process = folder(
        'LO',
        [bg],
        shown: false,
        opacity: 64,
        composite: 2,
        collapsed: true,
      );
      final result = plan(root([process]), [
        timeline([shownOver(bg, [(start: 0, end: 12)])]),
      ]);
      final cut = result.cuts.single;

      expect(names(cut), ['BG', 'LO']);
      final lo = row(cut, 'LO');
      expect(lo.kind, LayerKind.folder);
      expect(
        (lo.isVisible, lo.opacity, lo.blendMode, lo.collapsed),
        (false, 0.25, LayerBlendMode.multiply, true),
      );
      final image = row(cut, 'BG');
      expect(image.kind, LayerKind.image);
      expect(image.folderId, lo.id);
      expect((image.opacity, image.blendMode), (0.5, LayerBlendMode.multiply));
      expect(
        image.frames.single.name,
        '1',
        reason: 'named, so a 겸용 cut\'s edit is every cut\'s (F-98 · F-278) '
            '— and 1, not its layer\'s name (유저 10-09)',
      );
      expect(
        blocks(image),
        [(0, 1, '1')],
        reason: 'the image row\'s one cel and its hold (D22)',
      );
      expect(folderStructureProblem(cut.layers), isNull);
      expect(result.bakes.single.frameId, image.frames.single.id);
      expect(result.bakes.single.source, bg);
      expect(result.bakes.single.alpha, 1);
      expect(result.links.isEmpty, isTrue, reason: 'one cut links nothing');
      expect(result.fps, 24);
    });

    test('🎯an animation folder is a folder row over its base: one cel per '
        'CLIP STUDIO cel, named as there, held from its key to the next or '
        'its clip\'s end', () {
      final one = layer('1');
      final two = layer('2');
      final a = animation('A', [one, two], composite: 2);
      final result = plan(root([a]), [
        timeline([
          keyed(a, [(0, '1'), (3, '2'), (8, '1')], span: (start: 0, end: 10)),
        ]),
      ]);
      final cut = result.cuts.single;

      expect(names(cut), ['A', 'A'], reason: 'the base, then its folder');
      final [base, folderRow] = [
        for (final layer in cut.layers)
          if (layer.name == 'A') layer,
      ];
      expect(folderRow.kind, LayerKind.folder);
      expect(folderRow.blendMode, LayerBlendMode.multiply);
      expect(base.kind, LayerKind.animation);
      expect(base.folderId, folderRow.id);
      expect([for (final cel in base.frames) cel.name], ['1', '2']);
      expect(blocks(base), [(0, 3, '1'), (3, 5, '2'), (8, 2, '1')]);
      expect({for (final bake in result.bakes) bake.source}, {one, two});
      expect(folderStructureProblem(cut.layers), isNull);
    });

    test('🎯a cel that is a folder: its top visible layer is the base\'s '
        'picture, the ones under it attach rows below, synced — named '
        'A-1, A-2 from the top, as the app names a row it adds below a '
        'base (유저 10-09: 「그냥 우리방식대로 A라는 기준레이어랑 A-1 '
        '이런식으로」)', () {
      final line = layer('line');
      final colour = layer('colour');
      final shadow = layer('shadow');
      final cel1 = folder('1', [shadow, colour, line], composite: 0);
      final cel2 = layer('2');
      final a = animation('A', [cel1, cel2]);
      final result = plan(root([a]), [
        timeline([
          keyed(a, [(0, '1'), (6, '2')]),
        ]),
      ]);
      final cut = result.cuts.single;

      expect(names(cut), ['A-2', 'A-1', 'A', 'A']);
      final base = cut.layers.firstWhere((layer) => layer.name == 'A');
      final a1 = row(cut, 'A-1');
      final a2 = row(cut, 'A-2');
      for (final attach in [a1, a2]) {
        expect(attach.attachedToLayerId, base.id);
        expect(attach.attachedPlacement, AttachedPlacement.below);
        expect(attach.attachedMode, AttachedMode.synced);
        expect(attach.onTimesheet, isFalse);
        expect(attach.timeline, isEmpty, reason: 'a synced row has no lane');
        expect(attach.folderId, base.folderId);
        expect(attach.isVisible, isTrue);
      }
      final [baseOf1, baseOf2] = [for (final cel in base.frames) cel.id];
      expect(a1.baseFrameLinks, {
        baseOf1: attachedMirrorCelId(a1.id, baseOf1),
        baseOf2: attachedMirrorCelId(a1.id, baseOf2),
      });
      expect(
        identical(cutWithReconciledAttachedMirrors(cut), cut),
        isTrue,
        reason: 'the always-mirror shape is made here, not by a first write',
      );
      final into = {
        for (final bake in result.bakes) bake.source.name: bake.frameId,
      };
      expect(into, {
        'line': baseOf1,
        '2': baseOf2,
        'colour': attachedMirrorCelId(a1.id, baseOf1),
        'shadow': attachedMirrorCelId(a2.id, baseOf1),
      });
      expect(folderStructureProblem(cut.layers), isNull);
    });

    test('🎯hidden layers come too and line up like every other — by name or '
        'by place — only their eyes off; a line shown in one cel and hidden '
        'in another is two rows, as one that blends two ways is (유저 10-09: '
        '「숨긴레이어 이상한 규칙 만들지말고 그냥 눈만 끄게하면되는거야」) — and '
        'no folder the file never had (「이 숨김이라는 폴더는 뭐지?」)', () {
      final a = animation('A', [
        folder('1', [
          layer('under1'),
          layer('rough', shown: false),
          layer('line1'),
        ]),
        folder('2', [layer('under2'), layer('rough'), layer('line2')]),
        folder('3', [
          folder('old', [layer('older')], shown: false),
          layer('line3'),
        ]),
      ]);
      final result = plan(root([a]), [
        timeline([
          keyed(a, [(0, '1'), (4, '2'), (8, '3')]),
        ]),
      ]);
      final cut = result.cuts.single;
      final base = cut.layers.firstWhere((layer) => layer.name == 'A');

      /// The row cel [cel]'s layer [name] was baked into.
      String rowOfLayer(String cel, String name) {
        final frameId = result.bakes
            .singleWhere(
              (bake) => bake.source.name == name && bake.label == 'A / $cel',
            )
            .frameId;
        return cut.layers
            .singleWhere((layer) => layer.frameById(frameId) != null)
            .name;
      }

      expect(names(cut), ['A-4', 'A-3', 'A-2', 'A-1', 'A', 'A']);
      expect(
        [
          for (final name in ['A-1', 'A-2', 'A-3', 'A-4'])
            row(cut, name).isVisible,
        ],
        [false, true, false, true],
      );
      expect(
        [
          rowOfLayer('1', 'rough'),
          rowOfLayer('2', 'rough'),
          rowOfLayer('3', 'older'),
          rowOfLayer('1', 'under1'),
          rowOfLayer('2', 'under2'),
        ],
        ['A-1', 'A-2', 'A-3', 'A-4', 'A-4'],
        reason: 'one name, two eyes: two rows; a hidden layer keeps its place '
            'among the shown ones, and the shown ones under it keep theirs',
      );
      expect(
        [
          for (final layer in cut.layers)
            if (layer.kind == LayerKind.folder) layer.id,
        ],
        [base.folderId],
        reason: 'the animation folder is the one folder row',
      );
      for (final name in ['A-1', 'A-2', 'A-3', 'A-4']) {
        expect(row(cut, name).folderId, base.folderId);
        expect(row(cut, name).attachedToLayerId, base.id);
      }
      expect(folderStructureProblem(cut.layers), isNull);
    });

    test('🎯a layer whose name another cel\'s layer wears stands in that '
        'name\'s row, one whose name no other cel wears by its place from '
        'the top (유저 10-09: 「같은이름 있으면 같은행 없으면 전처럼 '
        '위치관계기준」) — and the rows keep every cel\'s own order', () {
      final a = animation('A', [
        folder('1', [layer('colour'), layer('shadow'), layer('line1')]),
        folder('2', [layer('colour'), layer('line2')]),
        folder('3', [
          layer('colour'),
          layer('shadow'),
          layer('extra'),
          layer('line3'),
        ]),
      ]);
      final result = plan(root([a]), [
        timeline([
          keyed(a, [(0, '1'), (4, '2'), (8, '3')]),
        ]),
      ]);
      final cut = result.cuts.single;
      final base = cut.layers.firstWhere((layer) => layer.name == 'A');
      final [cel1, cel2, cel3] = [for (final cel in base.frames) cel.id];

      /// The row cel [cel]'s layer [name] was baked into.
      String rowOfLayer(String cel, String name) {
        final frameId = result.bakes
            .singleWhere(
              (bake) => bake.source.name == name && bake.label == 'A / $cel',
            )
            .frameId;
        return cut.layers
            .singleWhere((layer) => layer.frameById(frameId) != null)
            .name;
      }

      expect(names(cut), ['A-3', 'A-2', 'A-1', 'A', 'A']);
      expect(
        [for (final cel in ['1', '3']) rowOfLayer(cel, 'shadow')],
        ['A-2', 'A-2'],
        reason: 'one row for the name two cels wear, at the second place '
            'in one and the third in the other',
      );
      expect(
        [for (final cel in ['1', '2', '3']) rowOfLayer(cel, 'colour')],
        ['A-3', 'A-3', 'A-3'],
      );
      expect(
        rowOfLayer('3', 'extra'),
        'A-1',
        reason: 'worn by one cel: by its place, above the rows under it',
      );
      expect(
        {
          for (final bake in result.bakes)
            if (bake.source.name.startsWith('line')) bake.frameId,
        },
        {cel1, cel2, cel3},
        reason: 'every cel\'s top layer is the base\'s, whatever its name',
      );
      expect(
        [for (final warning in result.warnings) warning.key],
        ['clipCelLayers'],
        reason: 'no cel\'s order crossed',
      );
    });

    test('cels that stack two names both ways cross one of them — and it is '
        'said', () {
      final a = animation('A', [
        folder('1', [layer('b'), layer('a'), layer('top1')]),
        folder('2', [layer('a'), layer('b'), layer('top2')]),
      ]);
      final result = plan(root([a]), [
        timeline([
          keyed(a, [(0, '1'), (6, '2')]),
        ]),
      ]);

      expect(names(result.cuts.single), ['A-2', 'A-1', 'A', 'A']);
      expect(
        [
          for (final warning in result.warnings)
            (warning.key, warning.values['count']),
        ],
        [('clipCelLayers', null), ('clipLineOrder', '1')],
      );
    });

    test('a cel\'s own order outranks where its rows stand on average — a '
        'name worn high in most cels still comes under what one cel stacks '
        'above it', () {
      final a = animation('A', [
        folder('1', [
          layer('b'),
          layer('a'),
          layer('u2'),
          layer('u1'),
          layer('top1'),
        ]),
        folder('2', [layer('b'), layer('top2')]),
        folder('3', [layer('b'), layer('top3')]),
      ]);
      final result = plan(root([a]), [
        timeline([
          keyed(a, [(0, '1'), (4, '2'), (8, '3')]),
        ]),
      ]);
      final cut = result.cuts.single;
      final rowOf = {
        for (final bake in result.bakes)
          if (bake.label == 'A / 1')
            bake.source.name: cut.layers
                .singleWhere((layer) => layer.frameById(bake.frameId) != null)
                .name,
      };

      expect(
        [for (final name in ['top1', 'u1', 'u2', 'a', 'b']) rowOf[name]],
        ['A', 'A-1', 'A-2', 'A-3', 'A-4'],
        reason: '「b」 stands second on average (cels 2 and 3) and fifth in '
            'cel 1 — its row comes under all that cel stacks above it',
      );
      expect(
        [for (final warning in result.warnings) warning.key],
        ['clipCelLayers'],
        reason: 'no cel\'s order crossed',
      );
    });

    test('an attach row\'s name passes over one the file itself uses — the '
        'first number no row wears, as the app names one (F-292)', () {
      final a = animation('A', [
        folder('1', [layer('under'), layer('line')]),
      ]);
      final result = plan(root([layer('A-1'), a]), [
        timeline([
          keyed(a, [(0, '1')]),
        ]),
      ]);

      expect(names(result.cuts.single), ['A-1', 'A-2', 'A', 'A']);
    });

    test('the base is every cel\'s top layer even where it is hidden — then '
        'its eye is off, and the layers under it come in with theirs', () {
      final a = animation('A', [
        folder('1', [layer('line1'), layer('rough1', shown: false)]),
        folder('2', [layer('line2'), layer('rough2', shown: false)]),
      ]);
      final result = plan(root([a]), [
        timeline([
          keyed(a, [(0, '1'), (6, '2')]),
        ]),
      ]);
      final cut = result.cuts.single;
      final base = cut.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation && layer.name == 'A',
      );

      expect(names(cut), ['A-1', 'A', 'A']);
      expect((base.isVisible, row(cut, 'A-1').isVisible), (false, true));
      expect(
        {
          for (final bake in result.bakes)
            if (bake.source.name.startsWith('rough')) bake.frameId,
        },
        {for (final cel in base.frames) cel.id},
      );
    });

    test('🎯every cel row stands at 100%, and each cel is baked at its OWN '
        'opacity (Q5: 「그림에 구워 넣는다(행은 100%)」 — 「낮은채로 '
        '구워버려서 더이상 진해지지 못하는거 받아들기게」)', () {
      final a = animation('A', [
        folder('1', [layer('rough1', opacity: 64), layer('line1')]),
        folder('2', [
          layer('rough2', opacity: 128),
          layer('line2', opacity: 128),
        ], opacity: 128),
        folder('3', [
          layer('rough3', opacity: 128, drawn: false),
          layer('line3'),
        ]),
      ]);
      final result = plan(root([a]), [
        timeline([
          keyed(a, [(0, '1'), (4, '2'), (8, '3')]),
        ]),
      ]);
      final cut = result.cuts.single;
      final alpha = {
        for (final bake in result.bakes) bake.source.name: bake.alpha,
      };

      expect(
        [
          for (final layer in cut.layers)
            if (layer.kind == LayerKind.animation) (layer.name, layer.opacity),
        ],
        [('A-1', 1), ('A', 1)],
        reason: 'the rows are at 100% — the faint cels stay faint by their '
            'pictures, not by a row that could be raised',
      );
      expect(alpha['line1'], 1);
      expect(
        alpha['line2'],
        0.25,
        reason: 'half in a folder at half — its cel folder\'s opacity counts',
      );
      expect(alpha['line3'], 1);
      expect(alpha['rough1'], 0.25, reason: 'a 25% rough is baked at 25%');
      expect(alpha['rough2'], 0.25);
      expect(
        alpha.containsKey('rough3'),
        isFalse,
        reason: 'a layer with no picture bakes nothing',
      );
    });

    /// The row each source layer's picture was baked into, by [result]'s
    /// cut.
    String rowOf(ClipImportPlan result, String source) {
      final frameId = result.bakes
          .singleWhere((bake) => bake.source.name == source)
          .frameId;
      return result.cuts.single.layers
          .singleWhere((layer) => layer.frameById(frameId) != null)
          .name;
    }

    test('🎯a line that blends two ways is two rows — the base takes the '
        'blend most cels stand in, even when the first cel blends the other '
        'way', () {
      final a = animation('A', [
        folder('1', [layer('s1'), layer('l1', composite: 2)], composite: 0),
        folder('2', [layer('s2', composite: 2), layer('l2')], composite: 0),
        folder('3', [layer('s3', composite: 2), layer('l3')], composite: 0),
        folder('4', [layer('s4', composite: 2), layer('l4')], composite: 0),
      ]);
      final result = plan(root([a]), [
        timeline([
          keyed(a, [(0, '1'), (3, '2'), (6, '3'), (9, '4')]),
        ]),
      ]);
      final cut = result.cuts.single;
      final base = cut.layers.firstWhere((layer) => layer.name == 'A');

      expect(names(cut), ['A-3', 'A-2', 'A-1', 'A', 'A']);
      expect(base.blendMode, LayerBlendMode.normal);
      expect(
        [for (final n in ['A-1', 'A-2', 'A-3']) row(cut, n).blendMode],
        [
          LayerBlendMode.multiply,
          LayerBlendMode.multiply,
          LayerBlendMode.normal,
        ],
        reason: 'from the top: the top line\'s other blend, then the second '
            'line by how many cels stand in each',
      );
      expect(
        [for (final s in ['l1', 'l2', 'l3', 'l4']) rowOf(result, s)],
        ['A-1', 'A', 'A', 'A'],
      );
      expect(
        [for (final s in ['s1', 's2', 's3', 's4']) rowOf(result, s)],
        ['A-3', 'A-2', 'A-2', 'A-2'],
      );
    });

    test('lines that stand in as many cels keep the order they came in — '
        'the one whose first cel comes first is the base', () {
      final a = animation('A', [
        layer('m', composite: 2),
        layer('n'),
      ]);
      final result = plan(root([a]), [
        timeline([
          keyed(a, [(0, 'm'), (6, 'n')]),
        ]),
      ]);

      expect(rowOf(result, 'm'), 'A');
      expect(rowOf(result, 'n'), 'A-1');
    });

    test('a folder inside a cel hands its blend to a layer alone in it; the '
        'cel\'s own folder only when the animation folder passes through', () {
      LayerBlendMode blendOf(ClipLayer animationFolder) {
        final result = plan(root([animationFolder]), [
          timeline([
            keyed(animationFolder, [(0, '1')]),
          ]),
        ]);
        return result.cuts.single.layers
            .firstWhere((layer) => layer.name == animationFolder.name)
            .blendMode;
      }

      expect(
        blendOf(
          animation('A', [
            folder('1', [
              folder('in', [layer('x')], composite: 8),
            ], composite: 2),
          ]),
        ),
        LayerBlendMode.screen,
        reason: 'the inner folder isolates; the cel folder meets an empty '
            'group inside the multiply animation folder',
      );
      expect(
        blendOf(
          animation('B', [
            folder('1', [layer('x')], composite: 2),
          ], composite: 30),
        ),
        LayerBlendMode.multiply,
        reason: 'through a passing folder the cel folder meets what lies '
            'below',
      );
      expect(
        blendOf(
          animation('C', [
            folder('1', [layer('x', composite: 2)]),
          ]),
        ),
        LayerBlendMode.multiply,
        reason: 'a passing cel folder leaves the layer its own blend',
      );
    });

    test('blocks stop at their clip\'s end and the folders\' above — a key '
        'before the clip shows from where the clip starts — and a label '
        'inside a block is its dot', () {
      final a = animation('A', [layer('1'), layer('2')]);
      final above = folder('LO', [a]);
      final result = plan(root([above]), [
        timeline(
          [
            MapEntry(
              a.uuid,
              const ClipTrack(
                kind: 2000,
                pieces: [
                  (
                    span: (start: 2, end: 6),
                    // The last key lies past the clip's end: it shows
                    // nothing, and the one before still stops at the end.
                    cels: [
                      (frame: 0, cel: '1'),
                      (frame: 4, cel: '2'),
                      (frame: 7, cel: '1'),
                    ],
                  ),
                  (span: (start: 8, end: 20), cels: [(frame: 8, cel: '1')]),
                ],
                labels: [3, 4, 9],
              ),
            ),
            shownOver(above, [(start: 0, end: 10)]),
          ],
          end: 24,
        ),
      ]);
      final base = result.cuts.single.layers.firstWhere(
        (layer) => layer.name == 'A' && layer.kind == LayerKind.animation,
      );

      expect(blocks(base), [(2, 2, '1'), (4, 2, '2'), (8, 2, '1')]);
      expect(
        [
          for (final exposure in base.timeline.values)
            exposure.breakdownOffsets,
        ],
        [
          [1],
          <int>[],
          [1],
        ],
        reason: 'the label on 「2」\'s head is that key — nothing more',
      );
    });

    test('a cel no timeline places is not imported, and said; a key naming '
        'no cel is said', () {
      final a = animation('A', [layer('1'), layer('2'), layer('3')]);
      final result = plan(root([a]), [
        timeline([
          keyed(a, [(0, '1'), (4, 'gone')]),
        ]),
      ]);
      final base = result.cuts.single.layers.firstWhere(
        (layer) => layer.kind == LayerKind.animation,
      );

      expect([for (final cel in base.frames) cel.name], ['1']);
      expect(result.bakes, hasLength(1));
      expect(
        [
          for (final warning in result.warnings)
            (warning.key, warning.values['count']),
        ],
        [('clipUnplaced', '2'), ('clipNoSuchCel', '1')],
      );
    });
  });

  group('every timeline a 겸용 cut', () {
    test('🎯one bank per row — the same cels, each cut its own ids and '
        'timing — linked row by row, camera too, the first cut canonical', () {
      final bg = layer('BG');
      final a = animation('A', [
        folder('1', [layer('under'), layer('top')]),
        layer('2'),
      ]);
      final result = plan(root([bg, a]), [
        timeline([
          keyed(a, [(0, '1'), (6, '2')]),
          shownOver(bg, [(start: 0, end: 12)]),
        ], name: 'one'),
        timeline(
          [
            keyed(a, [(0, '2')], span: (start: 0, end: 4)),
            shownOver(bg, const []),
          ],
          name: 'two',
          end: 4,
        ),
      ]);
      final [first, second] = result.cuts;

      expect((first.name, first.duration), ('one', 12));
      expect((second.name, second.duration), ('two', 4));
      for (final name in ['BG', 'A-1']) {
        expect(row(first, name).frames, row(second, name).frames);
        expect(row(first, name).id, isNot(row(second, name).id));
      }
      Layer baseOf(Cut cut) => cut.layers.singleWhere(
        (layer) => layer.name == 'A' && layer.kind == LayerKind.animation,
      );
      expect(blocks(baseOf(first)), [(0, 6, '1'), (6, 6, '2')]);
      expect(blocks(baseOf(second)), [(0, 4, '2')]);
      expect(
        row(second, 'BG').timeline,
        isEmpty,
        reason: 'not in that timeline: an empty row there',
      );
      expect(
        row(second, 'A-1').attachedToLayerId,
        baseOf(second).id,
        reason: 'each cut\'s attach rides its own base',
      );
      expect(
        row(second, 'A-1').baseFrameLinks,
        {
          for (final cel in baseOf(first).frames)
            cel.id: attachedMirrorCelId(row(first, 'A-1').id, cel.id),
        },
        reason: 'every cut mirrors a base cel with the canonical row\'s cel '
            '(F-278)',
      );
      expect(
        [for (final warning in result.warnings) warning.key],
        ['clipCelLayers'],
        reason: 'a row a timeline does not hold at all is not 「part of it」',
      );

      final rows = [
        for (final layer in first.layers)
          if (layer.kind != LayerKind.instruction) layer,
      ];
      expect(result.links.groups, hasLength(rows.length));
      for (final group in result.links.groups) {
        expect(group.canonical.cutId, first.id);
        expect([for (final member in group.members) member.cutId], [
          first.id,
          second.id,
        ]);
        expect(group.members.first.trackId, const TrackId('track'));
      }
      expect(
        result.links.groupOf(
          cutId: second.id,
          layerId: cameraLayerIdForCut(second.id),
        ),
        isNotNull,
        reason: 'a 겸용 cut\'s camera is linked (F-84)',
      );
      expect({for (final bake in result.bakes) bake.cutId}, {first.id});
      for (final cut in result.cuts) {
        expect(folderStructureProblem(cut.layers), isNull);
      }
    });

    test('rates that differ are said, and the first one is the project\'s',
        () {
      final result = plan(root([layer('BG')]), [
        timeline(const [], fps: 24),
        timeline(const [], fps: 30),
      ]);

      expect(result.fps, 24);
      expect(result.warnings.single.key, 'clipFps');
    });
  });

  test('a folder\'s clips are its layers\' clips — a picture in a folder '
      'the timeline does not show is an empty row there', () {
    final bg = layer('BG');
    final lo = folder('LO', [bg]);
    final result = plan(root([lo]), [
      timeline([
        shownOver(lo, const []),
        shownOver(bg, [(start: 0, end: 12)]),
      ]),
    ]);

    expect(row(result.cuts.single, 'BG').timeline, isEmpty);
    expect(result.warnings, isEmpty);
  });

  test('pass-through is a folder\'s word — a folder keeps it, a layer that '
      'carries it draws as normal', () {
    final result = plan(
      root([
        layer('thru', composite: 30),
        folder('F', [layer('x')]),
      ]),
      const [],
    );
    final cut = result.cuts.single;

    expect(row(cut, 'thru').blendMode, LayerBlendMode.normal);
    expect(row(cut, 'F').blendMode, LayerBlendMode.passThrough);
    expect(result.warnings, isEmpty);
  });

  test('a folder\'s blend with no equivalent is said once however many '
      'layers it holds, and a blend handed to layers that overlap is said', () {
    final a = animation('A', [
      folder('1', [
        folder('in', [layer('x'), layer('y')], composite: 5),
      ]),
      folder('2', [
        folder('in', [layer('z'), layer('w')], composite: 8),
      ]),
    ]);
    final result = plan(root([a]), [
      timeline([
        keyed(a, [(0, '1'), (6, '2')]),
      ]),
    ]);

    expect(
      [
        for (final warning in result.warnings)
          (warning.key, warning.values['count']),
      ],
      [('clipBlend', null), ('clipCelLayers', null), ('clipSpread', '1')],
      reason: 'cel 2\'s screen went to both its layers',
    );
  });

  test('a file with no timeline is one cut, named after the file, its '
      'pictures held through it', () {
    final result = plan(root([layer('BG')]), const []);
    final cut = result.cuts.single;

    expect((cut.name, cut.duration), ('file', defaultCutDuration));
    expect(blocks(row(cut, 'BG')), [(0, 1, '1')]);
    expect(result.fps, isNull);
  });

  group('🗣️a layer outside the cels shown on PART of a cut is an animation '
      'row (Q8: 「일부 구간만 보이는 레이어만 애니메이션 레이어로」)', () {
    test('🎯its one picture is placed where it shows and nowhere else — and '
        'there is nothing left to say', () {
      final bg = layer('BG');
      final result = plan(root([bg]), [
        timeline([
          shownOver(bg, [(start: 0, end: 4), (start: 8, end: 12)]),
        ]),
      ]);
      final shown = row(result.cuts.single, 'BG');

      expect(shown.kind, LayerKind.animation);
      expect(blocks(shown), [(0, 4, '1'), (8, 4, '1')]);
      expect(shown.frames, hasLength(1), reason: 'one picture, placed twice');
      expect(result.warnings, isEmpty);
      expect(
        result.bakes.single.frameId,
        shown.frames.single.id,
        reason: 'its picture is baked into that one cel',
      );
    });

    test('🎯the 겸용 cuts share the row: shown in part on ONE timeline, it is '
        'that row on every one — held through a cut it shows throughout, '
        'empty where it does not show', () {
      final bg = layer('BG');
      final result = plan(root([bg]), [
        timeline([
          shownOver(bg, [(start: 0, end: 6)]),
        ], name: 'c1'),
        timeline([
          shownOver(bg, [(start: 0, end: 12)]),
        ], name: 'c2'),
        timeline([shownOver(bg, const [])], name: 'c3'),
      ]);

      expect(
        [for (final cut in result.cuts) row(cut, 'BG').kind],
        [LayerKind.animation, LayerKind.animation, LayerKind.animation],
      );
      // Lists apart: a record holding a list compares it by identity.
      expect([for (final cut in result.cuts) blocks(row(cut, 'BG'))], [
        [(0, 6, '1')],
        [(0, 12, '1')],
        <(int, int, String?)>[],
      ]);
    });

    test('⛔CONTROL: shown throughout every cut it is in, it is the image row '
        'it always was', () {
      final bg = layer('BG');
      final result = plan(root([bg]), [
        timeline([
          shownOver(bg, [(start: 0, end: 12)]),
        ], name: 'c1'),
        timeline([shownOver(bg, const [])], name: 'c2'),
      ]);

      expect(
        [for (final cut in result.cuts) row(cut, 'BG').kind],
        [LayerKind.image, LayerKind.image],
      );
    });
  });

  test('🎯a kind of layer this app does not carry is left out, named in '
      'every decoder\'s one word (유저 10-09: 「이 레이어 종류는 … 지원되지 '
      '않습니다」); what comes in short is said too, and a layer whose track '
      'the timeline does not hold shows throughout', () {
    final result = plan(
      root([
        layer('v', kind: ClipLayerKind.vector, drawn: false),
        // Each declares a render, as the file's do: left out, nothing of
        // them is baked.
        layer('words', kind: ClipLayerKind.lettering),
        layer('p', kind: ClipLayerKind.paper),
        layer('f', kind: ClipLayerKind.fill),
        // A sound is no row of pictures — and its timeline plays nothing
        // of it here, so there is nothing to say (the sound's own group).
        layer('s', kind: ClipLayerKind.sound, drawn: false),
        layer('o', kind: ClipLayerKind.other),
        layer('odd', composite: 5),
      ]),
      [timeline(const [])],
    );
    final cut = result.cuts.single;

    expect(
      [
        for (final warning in result.warnings)
          (warning.key, warning.values['name']),
      ],
      [
        ('clipVector', 'v'),
        ('unsupportedLayerKind', 'words'),
        ('unsupportedLayerKind', 'p'),
        ('unsupportedLayerKind', 'f'),
        ('unsupportedLayerKind', 'o'),
        ('clipBlend', 'odd'),
      ],
    );
    expect(result.warnings[1], unsupportedLayerKind('words'));
    expect(names(cut), ['v', 'odd']);
    expect(row(cut, 'odd').blendMode, LayerBlendMode.normal);
    expect(result.bakes.single.source.name, 'odd');
  });

  test('a kind not carried inside a cel is left out before it takes a place '
      '— the layers under it line up as if it were not there — and named by '
      'its folder and cel', () {
    final a = animation('A', [
      folder('1', [
        layer('line1'),
        layer('words', kind: ClipLayerKind.lettering),
      ]),
      folder('2', [layer('line2')]),
    ]);
    final result = plan(root([a]), [
      timeline([
        keyed(a, [(0, '1'), (6, '2')]),
      ]),
    ]);
    final cut = result.cuts.single;
    final base = cut.layers.firstWhere(
      (layer) => layer.kind == LayerKind.animation,
    );

    expect(names(cut), ['A', 'A'], reason: 'no row for the text');
    expect(
      {for (final bake in result.bakes) bake.source.name: bake.frameId},
      {'line1': base.frames[0].id, 'line2': base.frames[1].id},
      reason: 'cel 1\'s top is the layer under the text',
    );
    expect(result.warnings, contains(unsupportedLayerKind('A / 1')));
  });

  test('a vector layer with strokes is baked like any picture — and what its '
      'round pen leaves out is said', () {
    final result = plan(
      root([
        layer(
          'lines',
          kind: ClipLayerKind.vector,
          drawn: false,
          vectorData: const ['strokes'],
        ),
      ]),
      [timeline(const [])],
    );

    expect([for (final warning in result.warnings) warning.key], [
      'clipVector',
    ]);
    expect(result.bakes.single.source.name, 'lines');
  });

  test('a cel holding folders says its layers\' names are not kept, and '
      'a folder value handed to layers that overlap is said', () {
    final a = animation('A', [
      folder('1', [layer('x'), layer('y')], opacity: 128),
      folder('2', [layer('z')], opacity: 128),
    ]);
    final result = plan(root([a]), [
      timeline([
        keyed(a, [(0, '1'), (6, '2')]),
      ]),
    ]);

    expect(
      [
        for (final warning in result.warnings)
          (warning.key, warning.values['count']),
      ],
      [('clipCelLayers', null), ('clipSpread', '1')],
      reason: 'cel 2 holds one layer — exact, nothing to say',
    );
  });

  group('🗣️a sound plays on its cut\'s SE rows (유저 10-09: 「소리도 가져오게 '
      '못하나? 단일파일안에있을거아냐」)', () {
    ClipLayer sound(String name, {bool shown = true}) {
      nextId += 1;
      return ClipLayer(
        id: nextId,
        name: name,
        kind: ClipLayerKind.sound,
        visibility: shown ? 1 : 0,
        opacity: 256,
        composite: 0,
        folderFlags: 0,
        isAnimationFolder: false,
        uuid: 'uuid$nextId',
        left: 0,
        top: 0,
        offsetX: 0,
        offsetY: 0,
        render: null,
        original: null,
        originalTransform: null,
        sounds: [
          (
            objectUuid: 'object$nextId',
            binaryId: 'chunk$nextId',
            name: '$name.mp3',
            extension: 'mp3',
          ),
        ],
        children: const [],
      );
    }

    ClipSoundCue cue(
      ClipLayer layer, {
      ClipSpan span = (start: 0, end: 12),
      int frame = 0,
      double startSeconds = 0,
      double speed = 1,
      double volume = 1,
      bool varies = false,
    }) => (
      span: span,
      player: layer.sounds.single.objectUuid,
      frame: frame,
      startSeconds: startSeconds,
      speed: speed,
      volume: volume,
      volumeVaries: varies,
    );

    MapEntry<String, ClipTrack> plays(
      ClipLayer layer,
      List<ClipSoundCue> cues,
    ) => MapEntry(
      layer.uuid,
      ClipTrack(
        kind: 4001,
        pieces: [for (final cue in cues) (span: cue.span, cels: const [])],
        labels: const [],
        sounds: cues,
      ),
    );

    Map<String, String> takenOut(ClipLayer layer) => {
      layer.sounds.single.objectUuid: 'C:/run/voice.mp3',
    };

    Layer seRow(Cut cut) =>
        cut.layers.singleWhere((layer) => layer.kind == LayerKind.se);

    test('🎯the sound starts where its clip\'s cue puts it, plays from the '
        'second the cue says, at its volume, to the clip\'s end — its own '
        'name, nothing said', () {
      final voice = sound('voice');
      final result = plan(
        root([voice]),
        [
          timeline([
            plays(voice, [
              cue(
                voice,
                span: (start: 0, end: 12),
                frame: 4,
                startSeconds: 0.5,
                volume: 0.8,
              ),
            ]),
          ]),
        ],
        sounds: takenOut(voice),
      );
      final row = seRow(result.cuts.single);

      expect((row.name, row.muted), ('voice', false));
      expect(blocks(row), [(4, 8, null)]);
      final clip = row.audioClips.single;
      expect(
        (clip.filePath, clip.frameId, clip.offsetFrames, clip.gain),
        ('C:/run/voice.mp3', row.frames.single.id, 12, 0.8),
        reason: 'half a second in at 24 fps',
      );
      expect(result.warnings, isEmpty);
      expect(result.bakes, isEmpty, reason: 'a sound has no picture to bake');
    });

    test('a cut that starts after the sound did plays it from where the cut '
        'meets it', () {
      final voice = sound('voice');
      final result = plan(
        root([voice]),
        [
          ClipTimeline(
            name: 'late',
            fps: 24,
            start: 10,
            end: 22,
            tracks: Map.fromEntries([
              plays(voice, [
                cue(voice, span: (start: 0, end: 20), frame: 2),
              ]),
            ]),
          ),
        ],
        sounds: takenOut(voice),
      );
      final row = seRow(result.cuts.single);

      expect(blocks(row), [(0, 10, null)]);
      expect(
        row.audioClips.single.offsetFrames,
        8,
        reason: 'the cut\'s head is the timeline\'s frame 10, 8 past the cue',
      );
    });

    test('every timeline its own SE row — none in one that does not play it '
        '— and a hidden sound layer is a MUTED row', () {
      final voice = sound('voice', shown: false);
      final result = plan(
        root([voice]),
        [
          timeline([
            plays(voice, [cue(voice, frame: 2)]),
          ], name: 'one'),
          timeline(const [], name: 'two'),
        ],
        sounds: takenOut(voice),
      );
      final [one, two] = result.cuts;

      expect(seRow(one).muted, isTrue);
      expect(two.layers.where((layer) => layer.kind == LayerKind.se), isEmpty);
      expect(
        result.links.groups.every(
          (group) => group.members.every(
            (member) => member.layerId != seRow(one).id,
          ),
        ),
        isTrue,
        reason: 'SE rows go to the track, not into the cuts\' links',
      );
    });

    test('what does not come over is said by the layer\'s name: a sound the '
        'file does not hold, another speed, a volume that moves', () {
      final lost = sound('lost');
      final fast = sound('fast');
      final swell = sound('swell');
      final result = plan(
        root([lost, fast, swell]),
        [
          timeline([
            plays(lost, [cue(lost)]),
            plays(fast, [cue(fast, speed: 2)]),
            plays(swell, [cue(swell, varies: true)]),
          ]),
        ],
        sounds: {...takenOut(fast), ...takenOut(swell)},
      );

      expect(
        [
          for (final warning in result.warnings)
            (warning.key, warning.values['name']),
        ],
        [
          ('clipSoundMissing', 'lost'),
          ('clipSoundSpeed', 'fast'),
          ('clipSoundVolume', 'swell'),
        ],
      );
      expect(
        [
          for (final layer in result.cuts.single.layers)
            if (layer.kind == LayerKind.se) layer.name,
        ],
        ['fast', 'swell'],
        reason: 'the lost one has nothing to play',
      );
    });
  });

  group('🗣️a cut is shot through its camera, the app\'s way (유저 10-09: '
      '「카메라는 우리방식이 제일 좋다고 생각하니 모아트는 참고만하고 '
      '우리방식대로」)', () {
    // The shooting frame: 200 × 100, its centre at (320, 180) on the paper.
    const frame = (width: 200, height: 100, centerX: 320.0, centerY: 180.0);
    final shootingFrame = CameraPose(center: CanvasPoint(x: 320, y: 180));

    /// A camera at [scale] times the frame, turned [degrees], its [pivotX] ·
    /// [pivotY] — the frame's centre unless said — placed at ([x], [y]).
    ClipPlacement placed({
      double x = 320,
      double y = 180,
      double scale = 1,
      double degrees = 0,
      double pivotX = 100,
      double pivotY = 50,
    }) => (
      scaleX: scale,
      scaleY: scale,
      degrees: degrees,
      x: x,
      y: y,
      pivotX: pivotX,
      pivotY: pivotY,
    );

    PropertyTrack<double> keys(Map<int, double> values, Set<int> held) =>
        PropertyTrack(
          keys: {
            for (final MapEntry(:key, :value) in values.entries)
              key: PropertyKey(
                value,
                outgoing: held.contains(key)
                    ? KeyExit.hold
                    : KeySide.linear,
              ),
          },
        );

    /// A clip over [span] keying the camera's point and scale; [held] keys
    /// hold to the next.
    ClipCameraMove move(
      ClipSpan span, {
      Map<int, double> x = const {},
      Map<int, double> y = const {},
      Map<int, double> scale = const {},
      Set<int> held = const {},
      bool unread = false,
    }) => (
      span: span,
      x: keys(x, held),
      y: keys(y, held),
      scale: keys(scale, held),
      degrees: PropertyTrack.empty(),
      pivotX: PropertyTrack.empty(),
      pivotY: PropertyTrack.empty(),
      unread: unread,
    );

    /// [camera]'s track: a clip for each of [moves].
    MapEntry<String, ClipTrack> moving(
      ClipLayer camera,
      List<ClipCameraMove> moves,
    ) => MapEntry(
      camera.uuid,
      ClipTrack(
        kind: 2005,
        pieces: [for (final move in moves) (span: move.span, cels: const [])],
        labels: const [],
        cameraMoves: moves,
      ),
    );

    /// The camera [cut] shows on its [frame], as the app plays it.
    CameraPose at(Cut cut, int frame) => resolveCameraPoseAt(
      camera: cut.camera,
      canvasSize: const CanvasSize(width: 640, height: 360),
      frameIndex: frame,
    );

    List<(String, Object?)> said(ClipImportPlan result) => [
      for (final warning in result.warnings)
        if (warning.key.startsWith('clipCamera'))
          (warning.key, warning.values['name']),
    ];

    test('🎯with no camera folder, every cut is shot through its shooting '
        'frame, still — one key at its centre', () {
      final result = plan(
        root([layer('BG')]),
        [timeline([]), timeline([], name: 'c2')],
        frame: frame,
      );

      for (final cut in result.cuts) {
        expect(cut.camera.keyframes, {0: shootingFrame});
      }
    });

    test('with no frame either, a cut keeps its own camera', () {
      final result = plan(root([layer('BG')]), [timeline([])]);

      expect(result.cuts.single.camera.isEmpty, isTrue);
    });

    test('🎯a camera the timeline does not move is the cut\'s camera at its '
        'rest — its picture the frame, placed as a picture is: the centre '
        'lands by its pivot and scale, and twice the frame is half the '
        'zoom — one key', () {
      final camera = folder(
        'camera',
        [layer('BG')],
        camera: placed(x: 300, y: 200, scale: 2, pivotX: 0, pivotY: 0),
      );

      final result = plan(root([camera]), [timeline([])], frame: frame);

      expect(result.cuts.single.camera.keyframes, {
        0: CameraPose(center: CanvasPoint(x: 500, y: 300), zoom: 0.5),
      });
    });

    test('🎯its turn is the picture\'s — clockwise on positive, the way the '
        'app\'s camera turns', () {
      final camera = folder(
        'camera',
        [layer('BG')],
        camera: placed(x: 300, y: 200, degrees: 90, pivotX: 0, pivotY: 0),
      );

      final pose = plan(
        root([camera]),
        [timeline([])],
        frame: frame,
      ).cuts.single.camera.keyframeAt(0)!;

      // The frame's centre, (100, 50) from the pivot, a quarter turn
      // clockwise on a canvas whose y runs down: (−50, 100).
      expect(pose.center.x, closeTo(250, 1e-9));
      expect(pose.center.y, closeTo(300, 1e-9));
      expect(pose.rotationDegrees, 90);
    });

    test('🎯a clip moves the cut\'s camera as its keys do — a straight pan '
        'is its two keys again', () {
      final camera = folder('camera', [layer('BG')], camera: placed());

      final cut = plan(
        root([camera]),
        [
          timeline([
            moving(camera, [
              move((start: 0, end: 12), x: {0: 100, 11: 210}),
            ]),
          ]),
        ],
        frame: frame,
      ).cuts.single;

      expect(cut.camera.keyframes, {
        0: CameraPose(center: CanvasPoint(x: 100, y: 180)),
        11: CameraPose(center: CanvasPoint(x: 210, y: 180)),
      });
    });

    test('each lane is keyed where its own curves key it — the point and '
        'the pivot place the frame, the scale zooms it, the turn turns it '
        '(I-89 ⑦) — on the cut\'s own frames', () {
      final camera = folder('camera', [layer('BG')], camera: placed());
      // Every curve runs straight through a key of its own, so no key
      // stands anywhere the file keys none; the timeline starts on its
      // frame 10, the cut's 0.
      PropertyTrack<double> straight(Map<int, double> values) =>
          keys(values, const {});
      final pan = moving(camera, [
        (
          span: (start: 10, end: 23),
          x: straight({10: 100, 14: 120, 22: 160}),
          y: straight({10: 180, 15: 190, 22: 204}),
          pivotX: straight({10: 100, 16: 106, 22: 112}),
          pivotY: straight({10: 50, 17: 57, 22: 62}),
          scale: straight({10: 1, 18: 1}),
          degrees: straight({10: 0, 19: 0}),
          unread: false,
        ),
      ]);

      final track = plan(
        root([camera]),
        [
          ClipTimeline(
            name: 'c1',
            fps: 24,
            start: 10,
            end: 23,
            tracks: Map.fromEntries([pan]),
          ),
        ],
        frame: frame,
      ).cuts.single.camera.track;

      expect(track.position.keys.keys, [0, 4, 5, 6, 7, 12]);
      expect(track.scale.keys.keys, [0, 8]);
      expect(track.rotation.keys.keys, [0, 9]);
    });

    test('a key CLIP STUDIO holds holds here, and a value the clip keys '
        'nothing for stays where the camera rests', () {
      final camera = folder(
        'camera',
        [layer('BG')],
        camera: placed(y: 90, scale: 2),
      );

      final cut = plan(
        root([camera]),
        [
          timeline([
            moving(camera, [
              move((start: 0, end: 12), x: {0: 100, 6: 160}, held: {0}),
            ]),
          ]),
        ],
        frame: frame,
      ).cuts.single;

      expect((at(cut, 3).center.x, at(cut, 6).center.x), (100, 160));
      expect((at(cut, 3).center.y, at(cut, 3).zoom), (90, 0.5));
    });

    test('🎯between its clips a cut is shot through the shooting frame — '
        'CLIP STUDIO shows nothing of the folder there', () {
      // Resting off the frame, so the frame is not the rest by chance.
      final camera = folder('camera', [layer('BG')], camera: placed(x: 500));

      final cut = plan(
        root([camera]),
        [
          timeline([
            moving(camera, [
              move((start: 0, end: 6), x: {0: 100}),
            ]),
          ]),
        ],
        frame: frame,
      ).cuts.single;

      expect(at(cut, 2).center.x, 100);
      expect(at(cut, 8), shootingFrame);
    });

    test('every timeline moves its own cut\'s camera — the 겸용 cuts share '
        'their rows, not their camera\'s moves', () {
      final camera = folder('camera', [layer('BG')], camera: placed());

      final cuts = plan(
        root([camera]),
        [
          timeline([
            moving(camera, [
              move((start: 0, end: 12), x: {0: 100}),
            ]),
          ]),
          timeline(name: 'c2', [
            moving(camera, [
              move((start: 0, end: 12), x: {0: 400}),
            ]),
          ]),
        ],
        frame: frame,
      ).cuts;

      expect([for (final cut in cuts) at(cut, 0).center.x], [100, 400]);
    });

    test('what the camera cannot bring is said: a second camera folder, and '
        'keys on a curve it does not read', () {
      final first = folder('camera', [layer('A')], camera: placed());
      final second = folder('camera 2', [layer('B')], camera: placed());

      final result = plan(
        root([first, second]),
        [
          timeline([
            moving(first, [move((start: 0, end: 12), unread: true)]),
          ]),
        ],
        frame: frame,
      );

      expect(said(result), [
        ('clipCameraExtra', 'camera 2'),
        ('clipCameraCurve', 'camera'),
      ]);
    });

    test('🎯what a cut shows outside the camera folder is said, once the '
        'camera leaves the frame — CLIP STUDIO\'s camera does not move it, '
        'the cut\'s does', () {
      final camera = folder('camera', [layer('A')], camera: placed(x: 400));

      final result = plan(
        root([layer('over'), layer('hidden', shown: false), camera]),
        [timeline([]), timeline([], name: 'c2')],
        frame: frame,
      );

      expect(said(result), [('clipCameraOutside', 'camera')]);
      expect(
        result.warnings.single.values['count'],
        '1',
        reason: 'the hidden one is not shown',
      );
    });

    test('⛔CONTROL: a camera that stays on the frame says nothing of what '
        'stands outside it', () {
      final camera = folder('camera', [layer('A')], camera: placed());

      final result = plan(
        root([layer('over'), camera]),
        [timeline([])],
        frame: frame,
      );

      expect(said(result), isEmpty);
    });
  });
}
