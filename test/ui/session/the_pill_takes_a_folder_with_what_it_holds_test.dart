import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/layer_clipboard.dart';
import 'package:anicel/src/ui/session/layer_verbs.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

/// 🗣️F-532 (유저 2026-11-01): 「레이어에서 폴더도 잘라내기 가능하게. 폴더
/// 삭제랑 동일하게 내부에도 적용되서 내부 다 잘라냄」.
///
/// What a folder's delete takes is F-305's; a cut banks what it lifts
/// (결정 14 ②ⓐ), so the board holds the folder with what it holds and a
/// paste puts it back as it stood. The pill's copy and cut are one pair
/// (I-123), so the copy takes a folder too.
///
/// The collaborators are held BY THEIR OWN TYPES so the mutation runner
/// names this file as their witness.
void main() {
  LayerClipboard rowsOf(EditorSessionManager s) => s.layerClipboard;
  LayerVerbs layersOf(EditorSessionManager s) => s.layerVerbs;

  TimelineToolbarPanelContext pill(EditorSessionManager s) =>
      TimelineToolbarPanelContext(s);

  const track = TrackId('f532-track');
  const firstCut = CutId('c1');
  const secondCut = CutId('c2');

  Layer row(
    String id, {
    String? inside,
    LayerKind kind = LayerKind.animation,
  }) =>
      Layer(
        id: LayerId(id),
        name: id,
        kind: kind,
        folderId: inside == null ? null : LayerId(inside),
        frames: const [],
        timeline: const {},
      );

  LayerLinkGroup linkOf(String id, String first, String second) =>
      LayerLinkGroup(
        id: id,
        members: [
          LayerLinkMember(
            trackId: track,
            cutId: firstCut,
            layerId: LayerId(first),
          ),
          LayerLinkMember(
            trackId: track,
            cutId: secondCut,
            layerId: LayerId(second),
          ),
        ],
      );

  Cut cutOf(CutId id, List<Layer> layers) => Cut(
    id: id,
    name: id.value,
    duration: 24,
    canvasSize: const CanvasSize(width: 320, height: 180),
    layers: layers,
  );

  EditorSessionManager sessionOf(
    List<Layer> layers, {
    List<Layer>? sibling,
    LayerLinkRegistry? links,
  }) {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('f532'),
        name: 'F-532',
        createdAt: DateTime.utc(2026, 11, 1),
        tracks: [
          Track(
            id: track,
            name: 'Video',
            cuts: [
              cutOf(firstCut, layers),
              if (sibling != null) cutOf(secondCut, sibling),
            ],
          ),
        ],
        linkRegistry: links,
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  /// Bottom → top:
  ///
  ///     over
  ///     F ─┬─ G ─── c
  ///        ├─ b
  ///        └─ a
  ///     under
  List<Layer> nested() => [
    row('under'),
    row('a', inside: 'F'),
    row('b', inside: 'F'),
    row('c', inside: 'G'),
    row('G', inside: 'F', kind: LayerKind.folder),
    row('F', kind: LayerKind.folder),
    row('over'),
  ];

  /// [layers], bottom → top, as `name` or `name<folder's name`.
  List<String> read(List<Layer> layers) => [
    for (final layer in layers)
      switch (layer.folderId) {
        final folder? => '${layer.name}<${layers.byId(folder)!.name}',
        null => layer.name,
      },
  ];

  List<String> stack(EditorSessionManager s) {
    final layers = s.requireActiveCut.layers;
    expect(folderStructureProblem(layers), isNull, reason: 'well formed');
    return read(layers);
  }

  void select(EditorSessionManager s, List<String> ids) =>
      s.rowSelection.value = [
        for (final id in ids) LayerRowAddress(LayerId(id)),
      ];

  group('🎯the cut takes a folder and all it holds', () {
    test('it goes as ONE step, and the paste puts it back as it stood', () {
      final s = sessionOf(nested());
      select(s, ['F']);
      final steps = s.historyManager.undoCount;

      expect(pill(s).canCutRun, isTrue);
      pill(s).cutRun();

      expect(stack(s), ['under', 'over']);
      expect(s.historyManager.undoCount, steps + 1, reason: 'ONE step');
      expect(rowsOf(s).hasLayerClipboard, isTrue);

      s.selectLayer(const LayerId('over'));
      pill(s).pasteIndependentFrame();

      expect(stack(s), [
        'under',
        'over',
        'a<F',
        'b<F',
        'c<G',
        'G<F',
        'F',
      ]);
    });

    test('one undo brings it all back where it stood', () {
      final s = sessionOf(nested());
      select(s, ['F']);
      final before = stack(s);

      pill(s).cutRun();
      s.undo();

      expect(stack(s), before);
    });

    test('the paste is one undo too, and the hand still holds it', () {
      final s = sessionOf(nested());
      select(s, ['F']);
      pill(s).cutRun();
      s.selectLayer(const LayerId('over'));
      pill(s).pasteIndependentFrame();

      s.undo();

      expect(stack(s), ['under', 'over']);
      expect(pill(s).canPasteIndependentFrame, isTrue);
    });

    test('a folder and rows it holds, selected together, are the folder: '
        'each row goes once and lands once', () {
      final s = sessionOf(nested());
      select(s, ['b', 'F', 'c', 'G']);

      pill(s).cutRun();

      expect(stack(s), ['under', 'over']);
      s.selectLayer(const LayerId('under'));
      pill(s).pasteIndependentFrame();
      expect(stack(s), [
        'under',
        'a<F',
        'b<F',
        'c<G',
        'G<F',
        'F',
        'over',
      ]);
    });

    test('a folder inside a folder goes alone with what it holds', () {
      final s = sessionOf(nested());
      select(s, ['G']);

      pill(s).cutRun();

      expect(stack(s), ['under', 'a<F', 'b<F', 'F', 'over']);
      s.selectLayer(const LayerId('over'));
      pill(s).pasteIndependentFrame();
      expect(stack(s), ['under', 'a<F', 'b<F', 'F', 'over', 'c<G', 'G']);
    });

    test('a row beside the folder goes with it and they land as they '
        'stood', () {
      final s = sessionOf(nested());
      select(s, ['F', 'under']);

      pill(s).cutRun();

      expect(stack(s), ['over']);
      s.selectLayer(const LayerId('over'));
      pill(s).pasteIndependentFrame();
      expect(stack(s), [
        'over',
        'under',
        'a<F',
        'b<F',
        'c<G',
        'G<F',
        'F',
      ]);
    });

    test('an empty folder goes and lands empty', () {
      final s = sessionOf([
        row('under'),
        row('E', kind: LayerKind.folder),
        row('over'),
      ]);
      select(s, ['E']);

      pill(s).cutRun();

      expect(stack(s), ['under', 'over']);
      pill(s).pasteIndependentFrame();
      expect(stack(s), contains('E'));
    });
  });

  group('a cut banks exactly what it lifts (결정 14 ②ⓐ)', () {
    test('a row the delete refuses stays out of the hand and out of the '
        'folder that went', () {
      final s = sessionOf([
        row('note', inside: 'F', kind: LayerKind.instruction),
        row('a', inside: 'F'),
        row('F', kind: LayerKind.folder),
        row('over'),
      ]);
      select(s, ['F']);

      pill(s).cutRun();

      expect(stack(s), ['note', 'over'], reason: 'the last instruction row');
      s.selectLayer(const LayerId('over'));
      pill(s).pasteIndependentFrame();
      expect(stack(s), ['note', 'over', 'a<F', 'F']);
    });

    test('🗣️F-532-Q1: a folder holding an attach row goes with it, and the '
        'row rides its base again', () {
      final s = sessionOf(nested());
      s.selectLayer(const LayerId('a'));
      s.folders.addAttachedLayer(AttachedPlacement.above);
      final riderName = s.activeLayer!.name;
      select(s, ['F']);

      pill(s).cutRun();

      expect(stack(s), ['under', 'over']);
      s.selectLayer(const LayerId('over'));
      pill(s).pasteIndependentFrame();

      final rows = s.requireActiveCut.layers;
      final rider = rows.singleWhere((row) => row.name == riderName);
      final base = rows.singleWhere((row) => row.name == 'a');
      expect(rider.attachedToLayerId, base.id);
      expect(rider.folderId, base.folderId);
      expect(stack(s), ['under', 'over', 'a<F', '$riderName<F', ...[
        'b<F',
        'c<G',
        'G<F',
        'F',
      ]]);
    });

    test('a row a board cannot hold stays, let out of the folder as a delete '
        'lets it out', () {
      final s = sessionOf([
        row('cam', inside: 'F', kind: LayerKind.camera),
        row('a', inside: 'F'),
        row('F', kind: LayerKind.folder),
        row('over'),
      ]);
      select(s, ['F']);

      pill(s).cutRun();

      expect(stack(s), ['cam', 'over']);
    });
  });

  group('the copy takes what the cut takes', () {
    test('a folder alone is rows to the pill: it leaves the frame axis, and '
        'the paste lands a second folder over its rows', () {
      final s = sessionOf(nested());
      select(s, ['G']);
      expect(rowsOf(s).canCopySelectedRows, isTrue);

      pill(s).copyFrame();

      expect(stack(s), read(nested()), reason: 'the copy leaves it standing');
      s.selectLayer(const LayerId('over'));
      pill(s).pasteIndependentFrame();
      expect(stack(s), [...read(nested()), 'c<G', 'G']);
    });

    test('an adjustment row it holds comes with it', () {
      final s = sessionOf([
        row('a', inside: 'F'),
        row('fx', inside: 'F', kind: LayerKind.adjustment),
        row('F', kind: LayerKind.folder),
        row('over'),
      ]);
      select(s, ['F']);

      pill(s).cutRun();

      expect(stack(s), ['over']);
      pill(s).pasteIndependentFrame();
      expect(stack(s), ['over', 'a<F', 'fx<F', 'F']);
    });

    test('a duplicate still has no folder to copy', () {
      final s = sessionOf(nested());
      select(s, ['F']);

      expect(layersOf(s).duplicatableSelectedLayerIds(), isEmpty);
    });
  });

  group('a pasted row belongs where it is put down', () {
    test('🎯among a folder\'s rows it is the folder\'s', () {
      final s = sessionOf(nested());
      select(s, ['under']);
      pill(s).copyFrame();

      s.selectLayer(const LayerId('a'));
      pill(s).pasteIndependentFrame();

      expect(stack(s).sublist(0, 3), ['under', 'a<F', 'under<F']);
    });

    test('a folder put down among a folder\'s rows nests there', () {
      final s = sessionOf(nested());
      select(s, ['G']);
      pill(s).copyFrame();

      s.selectLayer(const LayerId('a'));
      pill(s).pasteIndependentFrame();

      expect(stack(s).sublist(1, 4), ['a<F', 'c<G', 'G<F']);
    });

    test('on a base it lands past the whole attach group', () {
      final s = sessionOf([row('under'), row('base'), row('over')]);
      s.selectLayer(const LayerId('base'));
      s.folders.addAttachedLayer(AttachedPlacement.above);
      final rider = s.activeLayerId!;
      select(s, ['under']);
      pill(s).copyFrame();

      s.selectLayer(const LayerId('base'));
      pill(s).pasteIndependentFrame();

      final ids = [for (final layer in s.requireActiveCut.layers) layer.id];
      expect(ids.indexOf(rider), ids.indexOf(const LayerId('base')) + 1);
    });
  });

  group('🗣️F-532-Q2: the linked paste lands the folder too', () {
    test('its rows are linked copies, in a folder of their own', () {
      final s = sessionOf(nested());
      select(s, ['G']);
      pill(s).copyFrame();

      s.selectLayer(const LayerId('over'));
      expect(pill(s).canPasteLinkedFrame, isTrue);
      pill(s).pasteLinkedFrame();

      expect(stack(s), [...read(nested()), 'c<G', 'G']);
      expect(
        s.repository.requireProject().linkRegistry.groupOf(
          cutId: firstCut,
          layerId: const LayerId('c'),
        ),
        isNotNull,
        reason: 'the row is linked to its copy',
      );
    });

    test('nested, as it stood, and one undo takes it back', () {
      final s = sessionOf(nested());
      select(s, ['F']);
      pill(s).copyFrame();

      s.selectLayer(const LayerId('over'));
      pill(s).pasteLinkedFrame();

      expect(stack(s), [
        ...read(nested()),
        'a<F',
        'b<F',
        'c<G',
        'G<F',
        'F',
      ]);
      s.undo();
      expect(stack(s), read(nested()));
    });

    test('in a 겸용 cut the copies stand in the sibling\'s folder', () {
      final s = sessionOf(
        [row('base'), row('a', inside: 'F'), row('F', kind: LayerKind.folder)],
        sibling: [
          row('mirror'),
          row('a2', inside: 'F2'),
          row('F2', kind: LayerKind.folder),
        ],
        links: LayerLinkRegistry(
          groups: [
            linkOf('g0', 'base', 'mirror'),
            linkOf('g1', 'a', 'a2'),
            linkOf('g2', 'F', 'F2'),
          ],
        ),
      );
      select(s, ['F']);
      pill(s).copyFrame();

      s.selectLayer(const LayerId('base'));
      pill(s).pasteLinkedFrame();

      final sibling = s.repository
          .requireProject()
          .tracks
          .single
          .cuts
          .last
          .layers;
      expect(folderStructureProblem(sibling), isNull);
      expect(read(sibling), ['mirror', 'a2<F', 'F', 'a2<F2', 'F2']);
    });
  });

  test('🗣️F-535: in a 겸용 cut the sibling\'s attach row rides the sibling\'s '
      'copy of the base', () {
    Layer rider(String id, String base) =>
        row(id).copyWith(attachedToLayerId: LayerId(base));
    final s = sessionOf(
      [row('base'), rider('on', 'base')],
      sibling: [row('mirror'), rider('on2', 'mirror')],
      links: LayerLinkRegistry(
        groups: [linkOf('g0', 'base', 'mirror'), linkOf('g1', 'on', 'on2')],
      ),
    );
    select(s, ['base']);
    pill(s).copyFrame();

    s.selectLayer(const LayerId('base'));
    pill(s).pasteIndependentFrame();

    final sibling = s.repository
        .requireProject()
        .tracks
        .single
        .cuts
        .last
        .layers;
    expect(sibling, hasLength(4));
    expect(sibling[2].attachedToLayerId, isNull);
    expect(sibling[3].attachedToLayerId, sibling[2].id);
  });

  test('in a 겸용 cut the sibling gets the folder over its rows too', () {
    final s = sessionOf(
      [row('base'), row('a', inside: 'F'), row('F', kind: LayerKind.folder)],
      sibling: [row('mirror')],
      links: LayerLinkRegistry(groups: [linkOf('g', 'base', 'mirror')]),
    );
    select(s, ['F']);
    pill(s).copyFrame();

    s.selectLayer(const LayerId('base'));
    pill(s).pasteIndependentFrame();

    final sibling = s.repository
        .requireProject()
        .tracks
        .single
        .cuts
        .last
        .layers;
    expect(folderStructureProblem(sibling), isNull);
    expect(read(sibling), ['mirror', 'a<F', 'F']);
  });
}
