import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart'
    show attachedMirrorCelId, cutWithReconciledAttachedMirrors;
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/import/import_warning.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/import/clip_document.dart';
import 'package:anicel/src/services/import/clip_import_planner.dart';
import 'package:anicel/src/services/import/clip_placement.dart';
import 'package:anicel/src/services/import/clip_track_clip.dart';
import 'package:anicel/src/services/import/media_import_planner.dart';

import 'clip_test_builder.dart';

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
    int? mainColour,
    bool effects = false,
    bool clipped = false,
    ClipLayerMask? mask,
    bool locked = false,
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
      mainColour: mainColour,
      effectsOn: effects,
      clipped: clipped,
      mask: mask,
      locked: locked,
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
    bool effects = false,
    bool clipped = false,
    ClipLayerMask? mask,
    bool locked = false,
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
      effectsOn: effects,
      clipped: clipped,
      mask: mask,
      locked: locked,
      children: children,
    );
  }

  ClipLayer animation(
    String name,
    List<ClipLayer> cels, {
    int composite = 2,
    bool effects = false,
    bool locked = false,
  }) => folder(
    name,
    cels,
    animation: true,
    composite: composite,
    effects: effects,
    locked: locked,
  );

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
    double resolution = 72,
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
        resolution: resolution,
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
        ('unsupportedLayerKind', 'p'),
        ('unsupportedLayerKind', 'f'),
        ('unsupportedLayerKind', 'o'),
        ('clipBlend', 'odd'),
      ],
    );
    expect(result.warnings[1], unsupportedLayerKind('p'));
    expect(names(cut), ['v', 'odd']);
    expect(row(cut, 'odd').blendMode, LayerBlendMode.normal);
    expect(result.bakes.single.source.name, 'odd');
  });

  // brush-fidelity-Q4 (유저 2026-10-17 「레이어까지 같이」): the four MoArt's
  // table names past the first fourteen came in as normal until a layer took
  // every mode the brush does.
  test('a layer in a mode the table names comes in as itself, unsaid', () {
    final result = plan(root([layer('tint', composite: 23)]), const []);
    expect(row(result.cuts.single, 'tint').blendMode, LayerBlendMode.hue);
    expect(result.warnings, isEmpty);
  });

  group('F-370: the paper with no row under it is the PROJECT\'s paper', () {
    const colour = 0xFF204060;
    ClipLayer paper(String name, {bool shown = true, int opacity = 256}) =>
        layer(
          name,
          kind: ClipLayerKind.paper,
          shown: shown,
          opacity: opacity,
          mainColour: colour,
        );

    List<(String, String?)> said(ClipImportPlan result) => [
      for (final warning in result.warnings)
        (warning.key, warning.values['name']),
    ];

    test('🎯its colour at its opacity, and said nowhere — what is left out '
        'stands under nothing, and a second paper is a kind not carried', () {
      final result = plan(
        root([
          // A layer of another kind that names a colour is no paper.
          layer('fill', kind: ClipLayerKind.fill, mainColour: 0xFF000000),
          paper('sheet', opacity: 100),
          paper('second'),
          layer('BG'),
        ]),
        [timeline(const [])],
      );

      expect(result.paper, const ProjectBackground.color(0x64204060));
      expect(said(result), [
        ('unsupportedLayerKind', 'fill'),
        ('unsupportedLayerKind', 'second'),
      ]);
      expect(names(result.cuts.single), ['BG']);
    });

    test('a hidden one is an ABSENT paper, its colour kept', () {
      final result = plan(
        root([paper('sheet', shown: false, opacity: 200), layer('BG')]),
        [timeline(const [])],
      );

      expect(
        result.paper,
        const ProjectBackground.color(0xC7204060, none: true),
      );
      expect(result.warnings, isEmpty);
    });

    test('⛔one with a row under it covers that row, and one in a folder '
        'takes its folder\'s look — neither is the project\'s, and both are '
        'said', () {
      final result = plan(
        root([
          folder('LO', [paper('inside')]),
          layer('BG'),
          paper('over'),
        ]),
        [timeline(const [])],
      );

      expect(result.paper, isNull);
      expect(said(result), [
        ('unsupportedLayerKind', 'inside'),
        ('unsupportedLayerKind', 'over'),
      ]);
    });

    test('a paper the file names no colour for is said, and leaves the '
        'project none', () {
      final result = plan(
        root([layer('p', kind: ClipLayerKind.paper), layer('BG')]),
        [timeline(const [])],
      );

      expect(result.paper, isNull);
      expect(said(result), [('unsupportedLayerKind', 'p')]);
    });
  });

  test('a kind not carried inside a cel is left out before it takes a place '
      '— the layers under it line up as if it were not there — and named by '
      'its folder and cel', () {
    final a = animation('A', [
      folder('1', [
        layer('line1'),
        layer('fill', kind: ClipLayerKind.fill),
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

    expect(names(cut), ['A', 'A'], reason: 'no row for the fill');
    expect(
      {for (final bake in result.bakes) bake.source.name: bake.frameId},
      {'line1': base.frames[0].id, 'line2': base.frames[1].id},
      reason: 'cel 1\'s top is the layer under the fill',
    );
    expect(result.warnings, contains(unsupportedLayerKind('A / 1')));
  });

  group('🎯F-370-Q3: a text layer comes in as the app\'s own texts (유저 '
      '10-17: 「이제 들인다(앱의 글자로)」)', () {
    ClipLayer letters(
      String name,
      String says, {
      int opacity = 256,
      ClipLayerMask? mask,
    }) {
      nextId += 1;
      return ClipLayer(
        id: nextId,
        name: name,
        kind: ClipLayerKind.lettering,
        visibility: 1,
        opacity: opacity,
        composite: 0,
        folderFlags: 0,
        isAnimationFolder: false,
        uuid: 'uuid$nextId',
        left: 0,
        top: 0,
        offsetX: 0,
        offsetY: 0,
        // A text layer's render is declared and never stored.
        render: null,
        original: null,
        originalTransform: null,
        texts: [(text: says, attributes: clipTextAttributesBytes())],
        mask: mask,
        children: const [],
      );
    }

    test('outside the cels: a row of its own, its cel its texts — set at '
        'the canvas\'s resolution, and nothing said of a kind not '
        'carried', () {
      final result = plan(
        root([layer('BG'), letters('words', 'Hi')]),
        [timeline(const [])],
        resolution: 144,
      );

      expect(names(result.cuts.single), ['BG', 'words']);
      final bake = result.bakes.singleWhere(
        (bake) => bake.source.name == 'words',
      );
      expect(bake.label, 'words');
      final content = bake.texts.single.content;
      expect(content.text, 'Hi');
      expect(
        content.spans.single.style.fontSize,
        24,
        reason: '12 points at 144 dpi',
      );
      expect(content.spans.single.style.color, 0xFF000000);
      expect(result.warnings, isEmpty);
    });

    test('in a cel: at the cel\'s opacity its letters are that faint, as '
        'every picture of a cel is baked (Q5) — and it is named by its '
        'folder and cel', () {
      final a = animation('A', [
        folder('1', [letters('words', 'Hi', opacity: 128)]),
      ]);
      final result = plan(root([a]), [
        timeline([
          keyed(a, [(0, '1')]),
        ]),
      ]);

      final bake = result.bakes.single;
      expect(bake.alpha, 0.5);
      expect(bake.texts.single.content.spans.single.style.color, 0x80000000);
      expect(bake.label, 'A / 1');
    });

    test('its mask is said — the app\'s texts have none, and no picture of '
        'its is baked through one', () {
      final mask = (
        source: ClipPictureSource(
          attribute: offscreenAttributeBytes(
            width: 4,
            height: 4,
            columns: 1,
            rows: 1,
            colourChannels: 0,
          ),
          blocksId: 'm',
        ),
        left: 0,
        top: 0,
      );
      final result = plan(
        root([letters('words', 'Hi', mask: mask)]),
        [timeline(const [])],
      );

      expect(result.warnings, [layerMaskNotApplied('words')]);
    });

    test('every other layer bakes no text', () {
      final result = plan(root([layer('BG')]), [timeline(const [])]);

      expect(result.bakes.single.texts, isEmpty);
    });
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

  test('what CLIP STUDIO draws over what comes in — an effect of its '
      'properties on, or a clip to the layer under it inside a cel — is '
      'said in every decoder\'s words: a layer or folder outside the cels '
      'by its own name, one in a cel (the cel\'s folder too) by its folder '
      'and cel, and one left out only as left out', () {
    final a = animation(
      'A',
      [
        folder('1', [layer('trace', effects: true), layer('line1')]),
        folder('2', [layer('line2', clipped: true)], effects: true),
      ],
      effects: true,
    );
    final result = plan(
      root([
        layer('tinted', effects: true),
        folder('LO', [layer('clipped', clipped: true)], effects: true),
        a,
        layer('f', kind: ClipLayerKind.fill, effects: true, clipped: true),
      ]),
      [
        timeline([
          keyed(a, [(0, '1'), (6, '2')]),
        ]),
      ],
    );

    expect(
      [
        for (final warning in result.warnings)
          (warning.key, warning.values['name']),
      ],
      [
        ('layerEffectsNotApplied', 'tinted'),
        ('layerEffectsNotApplied', 'LO'),
        ('layerEffectsNotApplied', 'A'),
        ('layerEffectsNotApplied', 'A / 1'),
        ('layerEffectsNotApplied', 'A / 2'),
        ('clippingNotApplied', 'A / 2'),
        ('clipCelLayers', 'A'),
        ('unsupportedLayerKind', 'f'),
      ],
    );
    expect(result.warnings.first, layerEffectsNotApplied('tinted'));
    expect(result.warnings[5], clippingNotApplied('A / 2'));
  });

  test('a layer and a folder outside every cel come in clipped to the layer '
      'under them as they were (I-92) — nothing to say', () {
    final result = plan(
      root([
        layer('base'),
        layer('shade', clipped: true),
        folder('glow', [layer('inside')], clipped: true),
        layer('free'),
      ]),
      [timeline(const [])],
    );
    final cut = result.cuts.single;

    expect(
      [
        for (final name in ['base', 'shade', 'glow', 'inside', 'free'])
          (name, row(cut, name).clipsToBelow),
      ],
      [
        ('base', false),
        ('shade', true),
        ('glow', true),
        ('inside', false),
        ('free', false),
      ],
    );
    expect(result.warnings, isEmpty);
  });

  group('🎯a layer mask that is on (보드 the-clip-import-leaves-masks-and-'
      'locks-unsaid)', () {
    ClipLayerMask maskOf({int colourChannels = 0, bool held = true}) => (
      source: held
          ? ClipPictureSource(
              attribute: offscreenAttributeBytes(
                width: 4,
                height: 4,
                columns: 1,
                rows: 1,
                colourChannels: colourChannels,
              ),
              blocksId: 'm',
            )
          : null,
      left: 0,
      top: 0,
    );

    test('is baked into its layer\'s picture, as Photoshop\'s is — said only '
        'where no picture is baked through it: a folder\'s, the cel '
        'folder\'s too, one the file holds no picture of, one that is not '
        'one byte a pixel', () {
      final inCel = layer('c', mask: maskOf());
      final a = animation('A', [
        folder('1', [inCel], mask: maskOf()),
      ]);
      final masked = layer('masked', mask: maskOf());
      final strokes = layer(
        'vectors',
        kind: ClipLayerKind.vector,
        drawn: false,
        vectorData: const ['strokes'],
        mask: maskOf(),
      );
      final lost = layer('lost', mask: maskOf(held: false));
      final colour = layer('colour', mask: maskOf(colourChannels: 4));
      final result = plan(
        root([
          masked,
          strokes,
          folder('LO', [layer('in')], mask: maskOf()),
          lost,
          colour,
          a,
        ]),
        [
          timeline([
            keyed(a, [(0, '1')]),
          ]),
        ],
      );

      expect(
        [
          for (final warning in result.warnings)
            (warning.key, warning.values['name']),
        ],
        [
          ('clipVector', 'vectors'),
          ('layerMaskNotApplied', 'LO'),
          ('layerMaskNotApplied', 'lost'),
          ('layerMaskNotApplied', 'colour'),
          ('layerMaskNotApplied', 'A / 1'),
          ('clipCelLayers', 'A'),
        ],
      );
      expect(result.warnings[1], layerMaskNotApplied('LO'));
      expect(
        [for (final bake in result.bakes) bake.source.name],
        ['masked', 'vectors', 'in', 'lost', 'colour', 'c'],
        reason: 'a mask said is a picture baked without it — never one lost',
      );
    });
  });

  test('a lock comes in as no row here has one — said in every decoder\'s '
      'word, a folder\'s and a cel\'s as much as a layer\'s; one left out '
      'is said only as left out', () {
    final a = animation('A', [
      folder('1', [layer('c', locked: true)]),
    ], locked: true);
    final result = plan(
      root([
        layer('held', locked: true),
        folder('LO', [layer('in')], locked: true),
        a,
        layer('f', kind: ClipLayerKind.fill, locked: true),
      ]),
      [
        timeline([
          keyed(a, [(0, '1')]),
        ]),
      ],
    );

    expect(
      [
        for (final warning in result.warnings)
          (warning.key, warning.values['name']),
      ],
      [
        ('lockNotImported', 'held'),
        ('lockNotImported', 'LO'),
        ('lockNotImported', 'A'),
        ('lockNotImported', 'A / 1'),
        ('clipCelLayers', 'A'),
        ('unsupportedLayerKind', 'f'),
      ],
    );
    expect(result.warnings.first, lockNotImported('held'));
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
    ClipLayer sound(String name, {bool shown = true, bool locked = false}) {
      nextId += 1;
      return ClipLayer(
        id: nextId,
        name: name,
        locked: locked,
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

    test('a locked sound comes in on an SE row, which has no lock — said, '
        'as every row that comes in is', () {
      final voice = sound('voice', locked: true);
      final result = plan(
        root([voice]),
        [
          timeline([
            plays(voice, [cue(voice)]),
          ]),
        ],
        sounds: takenOut(voice),
      );

      expect(seRow(result.cuts.single).name, 'voice');
      expect(result.warnings, [lockNotImported('voice')]);
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

  /// [values] on their frames, running straight from each to the next — a
  /// cubic whose slopes are each way's own average — or held from the keys
  /// in [held].
  ClipCurve ramp(Map<int, double> values, {Set<int> held = const {}}) {
    final keys = values.entries.toList();
    double average(int i) =>
        (keys[i + 1].value - keys[i].value) / (keys[i + 1].key - keys[i].key);
    return ClipCurve(
      [
        for (final MapEntry(:key, :value) in keys)
          (frame: key.toDouble(), value: value),
      ],
      [
        for (var i = 0; i + 1 < keys.length; i += 1)
          if (held.contains(keys[i].key))
            ClipWay.held
          else
            ClipCubic(leaving: average(i), arriving: average(i)),
      ],
    );
  }

  /// CLIP STUDIO's own way between two keys: slow out, slow in.
  ClipCurve eased(int from, double start, int to, double end) => ClipCurve(
    [(frame: from.toDouble(), value: start), (frame: to.toDouble(), value: end)],
    const [ClipCubic(leaving: 0, arriving: 0)],
  );

  /// A clip over [span] keying a layer's placement — [scale] on both axes.
  ClipMove move(
    ClipSpan span, {
    ClipCurve? x,
    ClipCurve? y,
    ClipCurve? scale,
    ClipCurve? scaleX,
    ClipCurve? scaleY,
    ClipCurve? degrees,
    ClipCurve? pivotX,
    ClipCurve? pivotY,
  }) => (
    span: span,
    x: x ?? ClipCurve.none,
    y: y ?? ClipCurve.none,
    scaleX: scaleX ?? scale ?? ClipCurve.none,
    scaleY: scaleY ?? scale ?? ClipCurve.none,
    degrees: degrees ?? ClipCurve.none,
    pivotX: pivotX ?? ClipCurve.none,
    pivotY: pivotY ?? ClipCurve.none,
  );

  /// [layer]'s track — a 2D camera folder's, unless [kind] says otherwise —
  /// a clip for each of [moves].
  MapEntry<String, ClipTrack> moving(
    ClipLayer layer,
    List<ClipMove> moves, {
    int kind = 2005,
  }) => MapEntry(
    layer.uuid,
    ClipTrack(
      kind: kind,
      pieces: [for (final move in moves) (span: move.span, cels: const [])],
      labels: const [],
      moves: moves,
    ),
  );

  /// Where [cut] paints, on its [frame], the point [q] of its [name] row's
  /// picture — the composite's own placement.
  CanvasPoint painted(Cut cut, String name, int frame, CanvasPoint q) =>
      layerPlacementAt(
        cut: cut,
        layer: row(cut, name),
        frameIndex: frame,
      )?.apply(q) ??
      q;

  /// The canvas point [placement] puts its own point ([u], [v]) on
  /// ([clipPlaced]) — what a camera of it sees there, and where a layer of
  /// it shows that point of its picture.
  CanvasPoint seen(ClipPlacement placement, double u, double v) {
    final (:x, :y) = clipPlaced(placement, u, v);
    return CanvasPoint(x: x, y: y);
  }

  void expectNear(CanvasPoint actual, CanvasPoint expected, double within) {
    expect(actual.x, closeTo(expected.x, within));
    expect(actual.y, closeTo(expected.y, within));
  }

  /// Who was said to move on a curve the import does not read.
  List<(String, Object?)> said(ClipImportPlan result) => [
    for (final warning in result.warnings)
      if (warning.key == 'clipCurve') (warning.key, warning.values['name']),
  ];

  group('🗣️a 2D camera folder is a folder whose transform moves what it '
      'holds, and the cut\'s camera stays the shooting frame (유저 10-13: '
      '「카메라인척하는 ae의 트랜스폼임 … 카메라폴더는 그냥 폴더에 트랜스폼 '
      '움직이는걸로 … 이름은 카메라폴더 이름 그대로」)', () {
    // The shooting frame: 200 × 100, its centre at (320, 180) on the paper —
    // its top-left at (220, 130).
    const frame = (width: 200, height: 100, centerX: 320.0, centerY: 180.0);
    final frameOrigin = CanvasPoint(x: 220, y: 130);
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

    test('with no frame, the camera\'s picture stands from the paper\'s '
        'corner', () {
      final camera = folder('camera', [layer('BG')], camera: placed());

      final track = row(
        plan(root([camera]), [timeline([])]).cuts.single,
        'camera',
      ).transformTrack;

      expect(
        track.position.keys.values.single.value,
        CanvasPoint(x: 100, y: 50),
      );
    });

    test('🎯a camera folder is a folder row of its own name, and the cut\'s '
        'camera stays the shooting frame however the folder moves — CLIP '
        'STUDIO\'s own camera is still (「진짜 존재하는 카메라는 고정되있음」)', () {
      final camera = folder('camera', [layer('BG')], camera: placed());

      final cut = plan(
        root([camera]),
        [
          timeline([
            moving(camera, [
              move((start: 0, end: 12), x: eased(0, 100, 11, 210)),
            ]),
          ]),
        ],
        frame: frame,
      ).cuts.single;

      expect(row(cut, 'camera').kind, LayerKind.folder);
      expect(row(cut, 'BG').folderId, row(cut, 'camera').id);
      expect(cut.camera.keyframes, {0: shootingFrame});
    });

    test('🎯what the folder holds is painted where the camera sees it: the '
        'canvas point the camera takes on its own point u stands on the '
        'frame\'s u — moved, scaled and turned as the camera is', () {
      // Twice the frame, a sixth of a turn, its pivot off the frame's centre
      // — every number of the placement at once.
      final rest = placed(x: 300, y: 210, scale: 2, degrees: 60, pivotX: 30);
      final camera = folder('camera', [layer('BG')], camera: rest);

      final cut = plan(root([camera]), [timeline([])], frame: frame).cuts.single;

      for (final (u, v) in [(0.0, 0.0), (200.0, 0.0), (30.0, 50.0), (50.0, 90.0)]) {
        expectNear(
          painted(cut, 'BG', 0, seen(rest, u, v)),
          CanvasPoint(x: frameOrigin.x + u, y: frameOrigin.y + v),
          1e-9,
        );
      }
    });

    test('🎯the folder\'s transform reads as the camera: the anchor on the '
        'point it is placed at, the position on the frame\'s point its pivot '
        'is, the scale its own undone, its turn the other way', () {
      final camera = folder(
        'camera',
        [layer('BG')],
        camera: placed(x: 300, y: 210, scale: 2, degrees: 60, pivotX: 30),
      );

      final track = row(
        plan(root([camera]), [timeline([])], frame: frame).cuts.single,
        'camera',
      ).transformTrack;

      expect(track.anchorPoint.keys.values.single.value, CanvasPoint(x: 300, y: 210));
      expect(track.position.keys.values.single.value, CanvasPoint(x: 250, y: 180));
      expect(track.scale.keys.values.single.value, CanvasPoint(x: 0.5, y: 0.5));
      expect(track.rotation.keys.values.single.value, -60);
    });

    test('🎯a clip moves what the folder holds as its keys do — CLIP STUDIO\'s '
        'own way slow out, slow in — and its keys stand where the clip\'s '
        'do', () {
      final rest = placed();
      final camera = folder('camera', [layer('BG')], camera: rest);
      final pan = eased(0, 100, 11, 210);

      final cut = plan(
        root([camera]),
        [
          timeline([
            moving(camera, [move((start: 0, end: 12), x: pan)]),
          ]),
        ],
        frame: frame,
      ).cuts.single;

      expect(row(cut, 'camera').transformTrack.anchorPoint.keys.keys, [0, 11]);
      for (final at in [0, 3, 6, 11]) {
        final looking = (
          scaleX: 1.0,
          scaleY: 1.0,
          degrees: 0.0,
          x: pan.at(at.toDouble())!,
          y: rest.y,
          pivotX: rest.pivotX,
          pivotY: rest.pivotY,
        );
        expectNear(
          painted(cut, 'BG', at, seen(looking, 40, 70)),
          CanvasPoint(x: frameOrigin.x + 40, y: frameOrigin.y + 70),
          0.25,
        );
      }
    });

    test('a clip that zooms and turns the camera zooms and turns what the '
        'folder holds, about the frame\'s point the camera\'s pivot is', () {
      final camera = folder('camera', [layer('BG')], camera: placed());

      final cut = plan(
        root([camera]),
        [
          timeline([
            moving(camera, [
              move(
                (start: 0, end: 12),
                scale: ramp({0: 1, 11: 2}),
                degrees: ramp({0: 0, 11: 90}),
              ),
            ]),
          ]),
        ],
        frame: frame,
      ).cuts.single;

      final looking = placed(scale: 1 + 6 / 11, degrees: 90 * 6 / 11);
      for (final (u, v) in [(0.0, 0.0), (180.0, 20.0)]) {
        expectNear(
          painted(cut, 'BG', 6, seen(looking, u, v)),
          CanvasPoint(x: frameOrigin.x + u, y: frameOrigin.y + v),
          0.5,
        );
      }
    });

    test('a key CLIP STUDIO holds holds here, and a value the clip keys '
        'nothing for stays where the camera rests', () {
      final camera = folder(
        'camera',
        [layer('BG')],
        camera: placed(y: 90, scale: 2, degrees: 30),
      );

      final track = row(
        plan(
          root([camera]),
          [
            timeline([
              moving(camera, [
                move((start: 0, end: 12), x: ramp({0: 100, 6: 160}, held: {0})),
              ]),
            ]),
          ],
          frame: frame,
        ).cuts.single,
        'camera',
      ).transformTrack;

      CanvasPoint anchorOn(int frame) =>
          resolveAnchorTrackAt(track.anchorPoint, frame)!;
      expect((anchorOn(3).x, anchorOn(6).x), (100, 160));
      expect(anchorOn(3).y, 90);
      expect(track.scale.keys.values.single.value, CanvasPoint(x: 0.5, y: 0.5));
      expect(track.rotation.keys.values.single.value, -30);
    });

    test('🎯between its clips CLIP STUDIO shows nothing of the folder — what '
        'it holds has no cel there — so no frame there asks the transform '
        'for anything: the clips\' own keys join over the gap', () {
      final camera = folder('camera', [
        animation('A', [layer('1')]),
      ], camera: placed());

      final cut = plan(
        root([camera]),
        [
          timeline([
            moving(camera, [
              move((start: 0, end: 6), x: ClipCurve.held(0, 100)),
              move((start: 10, end: 12), x: ClipCurve.held(10, 200)),
            ]),
            keyed(camera.children.single, [(0, '1')]),
          ]),
        ],
        frame: frame,
      ).cuts.single;

      final base = cut.layers.singleWhere(
        (layer) => layer.name == 'A' && layer.kind == LayerKind.animation,
      );
      expect(blocks(base), [(0, 6, '1'), (10, 2, '1')]);
      final anchor = row(cut, 'camera').transformTrack.anchorPoint;
      expect(anchor.keys.keys, [0, 10]);
      expect(anchor.keys[0]!.outgoing, KeyExit.hold);
    });

    test('where one clip ends and the next starts, the frame is the next '
        'clip\'s', () {
      final camera = folder('camera', [layer('BG')], camera: placed());

      final anchor = row(
        plan(
          root([camera]),
          [
            timeline([
              moving(camera, [
                move((start: 0, end: 6), x: ClipCurve.held(0, 100)),
                move((start: 6, end: 12), x: ClipCurve.held(6, 200)),
              ]),
            ]),
          ],
          frame: frame,
        ).cuts.single,
        'camera',
      ).transformTrack.anchorPoint;

      expect(resolveAnchorTrackAt(anchor, 6)!.x, 200);
    });

    test('a cut that never shows the folder holds it at its rest', () {
      final camera = folder('camera', [layer('BG')], camera: placed(x: 500));

      final track = row(
        plan(
          root([camera]),
          [
            timeline([
              moving(camera, [
                move((start: 20, end: 30), x: ClipCurve.held(20, 100)),
              ]),
            ]),
          ],
          frame: frame,
        ).cuts.single,
        'camera',
      ).transformTrack;

      expect(track.anchorPoint.keys.keys, [0]);
      expect(
        track.anchorPoint.keys.values.single.value,
        CanvasPoint(x: 500, y: 180),
      );
    });

    test('a clip of the track that keys nothing holds the folder at its '
        'rest — beside one that moves it', () {
      final camera = folder('camera', [layer('BG')], camera: placed(x: 400));

      final track = row(
        plan(
          root([camera]),
          [
            timeline([
              MapEntry(
                camera.uuid,
                ClipTrack(
                  kind: 2005,
                  pieces: const [
                    (span: (start: 0, end: 6), cels: []),
                    (span: (start: 6, end: 12), cels: []),
                  ],
                  labels: const [],
                  moves: [
                    move((start: 6, end: 12), x: ClipCurve.held(6, 100)),
                  ],
                ),
              ),
            ]),
          ],
          frame: frame,
        ).cuts.single,
        'camera',
      ).transformTrack;

      CanvasPoint anchorOn(int frame) =>
          resolveAnchorTrackAt(track.anchorPoint, frame)!;
      expect((anchorOn(3).x, anchorOn(9).x), (400, 100));
    });

    test('🎯every camera folder moves what it holds, each its own — and a '
        'folder outside them stands still', () {
      final first = folder('camera', [layer('A')], camera: placed(x: 300));
      final second = folder('camera 2', [layer('B')], camera: placed(x: 340));

      final result = plan(
        root([first, second, folder('plain', [layer('C')])]),
        [timeline([])],
        frame: frame,
      );
      final cut = result.cuts.single;

      expect([
        for (final name in ['camera', 'camera 2'])
          row(cut, name).transformTrack.anchorPoint.keys.values.single.value.x,
      ], [300, 340]);
      expect(row(cut, 'plain').transformTrack.isEmpty, isTrue);
      expect(said(result), isEmpty);
    });

    test('every timeline moves its own cut\'s folder — the 겸용 cuts share '
        'their rows, not the camera\'s moves', () {
      final camera = folder('camera', [layer('BG')], camera: placed());

      final cuts = plan(
        root([camera]),
        [
          timeline([
            moving(camera, [
              move((start: 0, end: 12), x: ClipCurve.held(0, 100)),
            ]),
          ]),
          timeline(name: 'c2', [
            moving(camera, [
              move((start: 0, end: 12), x: ClipCurve.held(0, 400)),
            ]),
          ]),
        ],
        frame: frame,
      ).cuts;

      expect([
        for (final cut in cuts)
          row(cut, 'camera').transformTrack.anchorPoint.keys.values.single
              .value.x,
      ], [100, 400]);
    });

    test('each lane is keyed where its own curves key it — the anchor where '
        'the point is, the position where the pivot is, the scale and the '
        'turn where theirs are (I-89 ⑦) — on the cut\'s own frames', () {
      final camera = folder('camera', [layer('BG')], camera: placed());
      // Every curve runs straight through a key of its own, so no key
      // stands anywhere the file keys none; the timeline starts on its
      // frame 10, the cut's 0.
      final pan = moving(camera, [
        (
          span: (start: 10, end: 23),
          x: ramp({10: 100, 14: 120, 22: 160}),
          y: ramp({10: 180, 15: 190, 22: 204}),
          pivotX: ramp({10: 100, 16: 106, 22: 112}),
          pivotY: ramp({10: 50, 17: 57, 22: 62}),
          scaleX: ramp({10: 1, 18: 1}),
          scaleY: ramp({10: 1, 18: 1}),
          degrees: ramp({10: 0, 19: 0}),
        ),
      ]);

      final track = row(
        plan(
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
        ).cuts.single,
        'camera',
      ).transformTrack;

      expect(track.anchorPoint.keys.keys, [0, 4, 5, 12]);
      expect(track.position.keys.keys, [0, 6, 7, 12]);
      expect(track.scale.keys.keys, [0, 8]);
      expect(track.rotation.keys.keys, [0, 9]);
    });

    test('keys on a curve the import does not read are said, once a '
        'folder', () {
      final camera = folder('camera', [layer('A')], camera: placed());
      final unread = ClipCurve(
        [(frame: 0, value: 0), (frame: 6, value: 10), (frame: 11, value: 20)],
        [ClipWay.straight, ClipWay.straight],
        unread: true,
      );

      final result = plan(
        root([camera]),
        [
          timeline([
            moving(camera, [move((start: 0, end: 12), x: unread)]),
          ]),
          timeline(name: 'c2', [
            moving(camera, [move((start: 0, end: 12), y: unread)]),
          ]),
        ],
        frame: frame,
      );

      expect(said(result), [('clipCurve', 'camera')]);
    });

    test('a camera whose numbers say nothing — no size, a turn that is no '
        'number — comes in unscaled and unturned, not refused', () {
      final camera = folder(
        'camera',
        [layer('BG')],
        camera: placed(scale: 0, degrees: double.nan),
      );

      final track = row(
        plan(root([camera]), [timeline([])], frame: frame).cuts.single,
        'camera',
      ).transformTrack;

      expect(track.scale.keys.values.single.value, CanvasPoint(x: 1, y: 1));
      expect(track.rotation.keys.values.single.value, 0);
    });
  });

  group('🗣️a layer a clip moves moves by its row\'s transform, as CLIP '
      'STUDIO places it (유저 10-14, test4: 「B (카메라 없이 레이어의 트랜스폼 '
      '키 움직임)」)', () {
    Layer celFolderRow(Cut cut, String name, LayerKind kind) => cut.layers
        .singleWhere((layer) => layer.name == name && layer.kind == kind);

    test('🎯what a layer\'s picture holds at u shows where CLIP STUDIO\'s '
        'placement puts u — the anchor on its pivot, the position on its '
        'point, the scale by axis and the turn as they are', () {
      final picture = layer('BG');
      // Moved, stretched one way and squeezed the other, turned, its pivot
      // off the canvas's centre — every number of the placement at once.
      const placement = (
        scaleX: 1.5,
        scaleY: 0.5,
        degrees: 30.0,
        x: 300.0,
        y: 200.0,
        pivotX: 280.0,
        pivotY: 170.0,
      );

      final cut = plan(
        root([picture]),
        [
          timeline([
            moving(picture, kind: 2001, [
              move(
                (start: 0, end: 12),
                x: ClipCurve.held(0, placement.x),
                y: ClipCurve.held(0, placement.y),
                scaleX: ClipCurve.held(0, placement.scaleX),
                scaleY: ClipCurve.held(0, placement.scaleY),
                degrees: ClipCurve.held(0, placement.degrees),
                pivotX: ClipCurve.held(0, placement.pivotX),
                pivotY: ClipCurve.held(0, placement.pivotY),
              ),
            ]),
          ]),
        ],
      ).cuts.single;

      final track = row(cut, 'BG').transformTrack;
      expect(
        track.anchorPoint.keys.values.single.value,
        CanvasPoint(x: 280, y: 170),
      );
      expect(
        track.position.keys.values.single.value,
        CanvasPoint(x: 300, y: 200),
      );
      expect(
        track.scale.keys.values.single.value,
        CanvasPoint(x: 1.5, y: 0.5),
      );
      expect(track.rotation.keys.values.single.value, 30);
      for (final (u, v) in [(0.0, 0.0), (280.0, 170.0), (640.0, 360.0)]) {
        expectNear(
          painted(cut, 'BG', 0, CanvasPoint(x: u, y: v)),
          seen(placement, u, v),
          1e-9,
        );
      }
    });

    test('🎯an animation folder a clip moves moves its folder row, and what '
        'its cels hold goes where CLIP STUDIO shows it, frame by frame — '
        'test4\'s keys: slow out and in, straight, held', () {
      final b = animation('B', [layer('1')]);
      ClipCurve keys(List<double> values) => ClipCurve(
        [
          for (final (i, frame) in [0, 9, 19, 29].indexed)
            (frame: frame.toDouble(), value: values[i]),
        ],
        [
          const ClipCubic(leaving: 0, arriving: 0),
          ClipWay.straight,
          ClipWay.held,
        ],
      );
      final x = keys([395, 344, 386, 483]);
      final y = keys([295, 355, 362, 311]);

      final cut = plan(
        root([b]),
        [
          timeline(end: 30, [
            MapEntry(
              b.uuid,
              ClipTrack(
                kind: 2000,
                pieces: const [
                  (span: (start: 0, end: 30), cels: [(frame: 0, cel: '1')]),
                ],
                labels: const [],
                moves: [
                  move(
                    (start: 0, end: 30),
                    x: x,
                    y: y,
                    pivotX: ClipCurve.held(0, 320),
                    pivotY: ClipCurve.held(0, 180),
                  ),
                ],
              ),
            ),
          ]),
        ],
      ).cuts.single;

      final folderRow = celFolderRow(cut, 'B', LayerKind.folder);
      final base = celFolderRow(cut, 'B', LayerKind.animation);
      expect(base.folderId, folderRow.id);
      expect(folderRow.transformTrack.position.keys.keys, [0, 9, 19, 29]);
      expect(base.transformTrack.isEmpty, isTrue, reason: 'the folder moves');
      for (var frame = 0; frame < 30; frame += 1) {
        final shown = (
          scaleX: 1.0,
          scaleY: 1.0,
          degrees: 0.0,
          x: x.at(frame.toDouble())!,
          y: y.at(frame.toDouble())!,
          pivotX: 320.0,
          pivotY: 180.0,
        );
        expectNear(
          layerPlacementAt(
            cut: cut,
            layer: base,
            frameIndex: frame,
          )!.apply(CanvasPoint(x: 100, y: 60)),
          seen(shown, 100, 60),
          1,
        );
      }
    });

    test('⛔CONTROL: a layer no clip moves keeps no transform — a cel folder '
        'whose clip shows its cels, a picture its timeline shows', () {
      final cels = animation('A', [layer('1')]);
      final picture = layer('BG');

      final cut = plan(
        root([picture, cels]),
        [
          timeline([
            keyed(cels, [(0, '1')]),
            shownOver(picture, [(start: 0, end: 12)]),
          ]),
        ],
      ).cuts.single;

      for (final layer in cut.layers) {
        expect(layer.transformTrack.isEmpty, isTrue, reason: layer.name);
      }
    });

    test('a cut whose timeline keys no move of the layer has it stand as it '
        'is drawn — the 겸용 cuts share the row, each its own moves, '
        'whichever of them keys one', () {
      final picture = layer('BG');
      final later = layer('FG');

      final cuts = plan(
        root([later, picture]),
        [
          timeline([
            moving(picture, kind: 2001, [
              move((start: 0, end: 12), x: ClipCurve.held(0, 330)),
            ]),
            shownOver(later, [(start: 0, end: 12)]),
          ]),
          timeline(name: 'c2', [
            shownOver(picture, [(start: 0, end: 12)]),
            moving(later, kind: 2001, [
              move((start: 0, end: 12), y: ClipCurve.held(0, 200)),
            ]),
          ]),
        ],
      ).cuts;

      expect(
        painted(cuts.first, 'BG', 0, CanvasPoint(x: 40, y: 50)),
        CanvasPoint(x: 50, y: 50),
        reason:
            'what the clip leaves out of the placement stands unmoved — its '
            'pivot where test4\'s layer kept it, the canvas\'s centre',
      );
      expect(row(cuts.last, 'BG').transformTrack.isEmpty, isTrue);
      expect(
        painted(cuts.last, 'FG', 0, CanvasPoint(x: 40, y: 50)),
        CanvasPoint(x: 40, y: 70),
        reason:
            'a layer only a later timeline moves moves there — along the one '
            'axis its clip keys, its point resting on the centre the other',
      );
      expect(row(cuts.first, 'FG').transformTrack.isEmpty, isTrue);
    });

    test('the scale is keyed where either of its curves is — a layer keys '
        'one an axis (ImageAspectScale), where a camera keys one', () {
      final picture = layer('BG');

      final track = row(
        plan(
          root([picture]),
          [
            timeline([
              moving(picture, kind: 2001, [
                move(
                  (start: 0, end: 12),
                  scaleX: ramp({0: 1.5, 11: 1.5}),
                  scaleY: ramp({0: 0.5, 6: 0.5, 11: 0.5}),
                ),
              ]),
            ]),
          ],
        ).cuts.single,
        'BG',
      ).transformTrack;

      expect(track.scale.keys.keys, [0, 6, 11]);
    });

    test('keys on a curve the import does not read are said for a layer as '
        'for a camera', () {
      final picture = layer('BG');
      final unread = ClipCurve(
        [(frame: 0, value: 0), (frame: 6, value: 10)],
        [ClipWay.straight],
        unread: true,
      );

      final result = plan(root([picture]), [
        timeline([
          moving(picture, kind: 2001, [
            move((start: 0, end: 12), x: unread),
          ]),
        ]),
      ]);

      expect(said(result), [('clipCurve', 'BG')]);
    });
  });
}
