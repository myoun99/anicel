import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart'
    show attachedMirrorCelId, cutWithReconciledAttachedMirrors;
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/import/clip_document.dart';
import 'package:anicel/src/services/import/clip_import_planner.dart';
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
      render: drawn ? picture : null,
      original: null,
      originalTransform: null,
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
      render: null,
      original: null,
      originalTransform: null,
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

  ClipImportPlan plan(ClipLayer tree, List<ClipTimeline> timelines) {
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
      ),
      name: 'file',
      hiddenFolderName: 'Hidden',
      trackId: const TrackId('track'),
      mint: ImportIdMint(
        nextLayerId: () => LayerId('layer-${layers += 1}'),
        nextFrameId: (_) => FrameId('frame-${frames += 1}'),
        nextCutId: () => CutId('cut-${cuts += 1}'),
      ),
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
        'one picture, named', () {
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
      expect(image.frames.single.name, 'BG', reason: 'F-98 · F-278');
      expect(
        blocks(image),
        [(0, 1, 'BG')],
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
        'A-2, A-3 from the top', () {
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

      expect(names(cut), ['A-3', 'A-2', 'A', 'A']);
      final base = cut.layers.firstWhere((layer) => layer.name == 'A');
      final a2 = row(cut, 'A-2');
      final a3 = row(cut, 'A-3');
      for (final attach in [a2, a3]) {
        expect(attach.attachedToLayerId, base.id);
        expect(attach.attachedPlacement, AttachedPlacement.below);
        expect(attach.attachedMode, AttachedMode.synced);
        expect(attach.onTimesheet, isFalse);
        expect(attach.timeline, isEmpty, reason: 'a synced row has no lane');
        expect(attach.folderId, base.folderId);
      }
      final [baseOf1, baseOf2] = [for (final cel in base.frames) cel.id];
      expect(a2.baseFrameLinks, {
        baseOf1: attachedMirrorCelId(a2.id, baseOf1),
        baseOf2: attachedMirrorCelId(a2.id, baseOf2),
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
        'colour': attachedMirrorCelId(a2.id, baseOf1),
        'shadow': attachedMirrorCelId(a3.id, baseOf1),
      });
      expect(folderStructureProblem(cut.layers), isNull);
    });

    test('🎯hidden layers come too — attach rows of their own count, in a '
        'folder whose eye is off and that is folded; the rows inside keep '
        'theirs on', () {
      final rough = layer('rough', shown: false);
      final inked = layer('inked');
      final hiddenFolder = folder('old', [layer('older')], shown: false);
      final cel = folder('1', [rough, hiddenFolder, inked], composite: 0);
      final a = animation('A', [cel]);
      final result = plan(root([a]), [
        timeline([
          keyed(a, [(0, '1')]),
        ]),
      ]);
      final cut = result.cuts.single;

      expect(names(cut), ['A-3', 'A-2', 'Hidden', 'A', 'A']);
      final organizer = row(cut, 'Hidden');
      expect(
        (organizer.isVisible, organizer.collapsed),
        (false, true),
        reason: 'its eye off and folded',
      );
      final base = cut.layers.firstWhere((layer) => layer.name == 'A');
      expect(attachOrganizerBaseOf(organizer, cut.layers), base.id);
      for (final name in ['A-2', 'A-3']) {
        expect(row(cut, name).folderId, organizer.id);
        expect(row(cut, name).isVisible, isTrue);
      }
      final into = {
        for (final bake in result.bakes) bake.source.name: bake.frameId,
      };
      final cel1 = base.frames.single.id;
      expect(into['inked'], cel1);
      expect(
        into['older'],
        attachedMirrorCelId(row(cut, 'A-2').id, cel1),
        reason: 'hidden by its folder, the top of the hidden ones',
      );
      expect(into['rough'], attachedMirrorCelId(row(cut, 'A-3').id, cel1));
      expect(folderStructureProblem(cut.layers), isNull);
    });

    test('🎯a row is as strong as its strongest picture, and a fainter '
        'cel is baked fainter — a row whose cels agree bakes nothing', () {
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
        cut.layers.firstWhere((layer) => layer.name == 'A').opacity,
        1,
        reason: 'line1 and line3 stand at 100%',
      );
      expect(alpha['line1'], 1);
      expect(
        alpha['line2'],
        0.25,
        reason: 'half in a folder at half — its cel folder\'s opacity counts',
      );
      expect(alpha['line3'], 1);
      expect(
        row(cut, 'A-2').opacity,
        0.25,
        reason: 'the strongest PICTURE — rough3 at 50% has none',
      );
      expect(alpha['rough1'], 1);
      expect(alpha['rough2'], 1);
      expect(alpha.containsKey('rough3'), isFalse);
    });

    test('🎯a line that blends two ways is two rows — the base takes the '
        'blend most cels stand in', () {
      final a = animation('A', [
        folder('1', [layer('s1', composite: 2), layer('l1')], composite: 0),
        folder('2', [layer('s2'), layer('l2')], composite: 0),
        folder('3', [layer('s3', composite: 2), layer('l3', composite: 2)]),
        folder('4', [layer('s4', composite: 2), layer('l4')], composite: 0),
      ]);
      final result = plan(root([a]), [
        timeline([
          keyed(a, [(0, '1'), (3, '2'), (6, '3'), (9, '4')]),
        ]),
      ]);
      final cut = result.cuts.single;
      final base = cut.layers.firstWhere((layer) => layer.name == 'A');
      String rowOf(String source) {
        final frameId = result.bakes
            .singleWhere((bake) => bake.source.name == source)
            .frameId;
        return cut.layers
            .singleWhere((layer) => layer.frameById(frameId) != null)
            .name;
      }

      expect(names(cut), ['A-4', 'A-3', 'A-2', 'A', 'A']);
      expect(base.blendMode, LayerBlendMode.normal);
      expect(
        [for (final n in ['A-2', 'A-3', 'A-4']) row(cut, n).blendMode],
        [
          LayerBlendMode.multiply,
          LayerBlendMode.multiply,
          LayerBlendMode.normal,
        ],
        reason: 'from the top: the top line\'s multiply, then the second '
            'line by how many cels stand in each',
      );
      expect(
        [for (final s in ['l1', 'l2', 'l3', 'l4']) rowOf(s)],
        ['A', 'A', 'A-2', 'A'],
      );
      expect(
        [for (final s in ['s1', 's2', 's3', 's4']) rowOf(s)],
        ['A-3', 'A-4', 'A-3', 'A-3'],
      );
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
                    cels: [(frame: 0, cel: '1'), (frame: 4, cel: '2')],
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
      for (final name in ['BG', 'A-2']) {
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
        row(second, 'A-2').attachedToLayerId,
        baseOf(second).id,
        reason: 'each cut\'s attach rides its own base',
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

  test('a file with no timeline is one cut, named after the file, its '
      'pictures held through it', () {
    final result = plan(root([layer('BG')]), const []);
    final cut = result.cuts.single;

    expect((cut.name, cut.duration), ('file', defaultCutDuration));
    expect(blocks(row(cut, 'BG')), [(0, 1, 'BG')]);
    expect(result.fps, isNull);
  });

  test('a layer outside the cels shown on part of a timeline is said — an '
      'image row holds its picture throughout (Q8 asks what it becomes)', () {
    final bg = layer('BG');
    final result = plan(root([bg]), [
      timeline([
        shownOver(bg, [(start: 0, end: 6)]),
      ]),
    ]);

    expect(blocks(row(result.cuts.single, 'BG')), [(0, 1, 'BG')]);
    expect(
      [for (final warning in result.warnings) warning.key],
      ['clipShownInPart'],
    );
    expect(result.warnings.single.values, {'name': 'BG', 'cut': 'c1'});
  });

  test('what has no place here is said by name, and a layer whose track the '
      'timeline does not hold shows throughout', () {
    final text = layer('words', kind: ClipLayerKind.lettering, drawn: false);
    final result = plan(
      root([
        layer('v', kind: ClipLayerKind.vector, drawn: false),
        text,
        layer('p', kind: ClipLayerKind.paper, drawn: false),
        layer('f', kind: ClipLayerKind.fill, drawn: false),
        layer('s', kind: ClipLayerKind.sound, drawn: false),
        layer('o', kind: ClipLayerKind.other, drawn: false),
        layer('odd', composite: 5),
      ]),
      [timeline(const [])],
    );
    final cut = result.cuts.single;

    expect(
      [for (final warning in result.warnings) warning.key],
      [
        'clipVector',
        'clipText',
        'clipPaper',
        'clipFill',
        'clipSound',
        'clipUnknownLayer',
        'clipBlend',
      ],
    );
    expect(names(cut), ['v', 'words', 'p', 'f', 'o', 'odd']);
    expect(blocks(row(cut, 'words')), [(0, 1, 'words')]);
    expect(row(cut, 'odd').blendMode, LayerBlendMode.normal);
    expect(result.bakes.single.source.name, 'odd');
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
}
