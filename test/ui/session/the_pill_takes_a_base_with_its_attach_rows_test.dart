import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/layer_clipboard.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';
import '../../helpers/a_folder_made_by_hand.dart';
import '../../helpers/draw_on_current_frame.dart';

/// 🗣️F-535 (유저 2026-11-01): 「폴더 잘라내기 가능한거처럼 어태치레이어도
/// 어태치레이어거나 기준레이어던 잘라내기 가능하게. 기준레이어 잘라내면
/// 삭제가 내부도 삭제하려하듯이 내부 어태치레이어들도 잘라냄. 법 통일」.
///
/// The board takes what a delete takes (F-532), and a base's delete takes
/// its attach rows. They land riding the row their base landed as, on its
/// cels; an attach row whose base is not in hand lands as a row of its own,
/// wearing the timing it wore.
void main() {
  LayerClipboard rowsOf(EditorSessionManager s) => s.layerClipboard;

  TimelineToolbarPanelContext pill(EditorSessionManager s) =>
      TimelineToolbarPanelContext(s);

  void select(EditorSessionManager s, List<LayerId> ids) =>
      s.rowSelection.value = [for (final id in ids) LayerRowAddress(id)];

  /// A, B and C from the bottom, and on B a drawing with a drawn rider above
  /// it and an empty one below it. Stood on C.
  ({
    EditorSessionManager s,
    LayerId a,
    LayerId b,
    LayerId c,
    LayerId above,
    LayerId below,
  })
  riders() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final a = s.activeLayerId!;
    s.layerStack.addLayerOfKind(LayerKind.animation);
    final b = s.activeLayerId!;
    drawOnCurrentFrame(s);
    s.folders.addAttachedLayer(AttachedPlacement.above);
    final above = s.activeLayerId!;
    drawOnCurrentFrame(s);
    s.selectLayer(b);
    s.folders.addAttachedLayer(AttachedPlacement.below);
    final below = s.activeLayerId!;
    s.selectLayer(above);
    s.layerStack.addLayerOfKind(LayerKind.animation);
    final c = s.activeLayerId!;
    return (s: s, a: a, b: b, c: c, above: above, below: below);
  }

  List<Layer> rows(EditorSessionManager s) => [
    for (final layer in s.requireActiveCut.layers)
      if (layer.kind == LayerKind.animation) layer,
  ];

  /// The row of the cut called [name], the one above when two are.
  Layer named(EditorSessionManager s, String name) =>
      rows(s).lastWhere((row) => row.name == name);

  group('🎯the cut of a base takes its attach rows', () {
    test('they go as ONE step and the paste puts them back riding it', () {
      final r = riders();
      final aboveName = r.s.requireActiveCut.layers.byId(r.above)!.name;
      final belowName = r.s.requireActiveCut.layers.byId(r.below)!.name;
      final order = [for (final row in rows(r.s)) row.name];
      select(r.s, [r.b]);
      final steps = r.s.historyManager.undoCount;

      expect(pill(r.s).canCutRun, isTrue);
      pill(r.s).cutRun();

      expect(rows(r.s).map((row) => row.name), ['A', 'C']);
      expect(r.s.historyManager.undoCount, steps + 1, reason: 'ONE step');

      r.s.selectLayer(r.a);
      pill(r.s).pasteIndependentFrame();

      expect(rows(r.s).map((row) => row.name), order);
      final base = named(r.s, 'B');
      final above = named(r.s, aboveName);
      final below = named(r.s, belowName);
      expect(above.attachedToLayerId, base.id);
      expect(above.attachedPlacement, AttachedPlacement.above);
      expect(below.attachedToLayerId, base.id);
      expect(below.attachedPlacement, AttachedPlacement.below);
    });

    test('a synced row\'s links name the cels both rows landed with', () {
      final r = riders();
      final aboveName = r.s.requireActiveCut.layers.byId(r.above)!.name;
      select(r.s, [r.b]);
      pill(r.s).cutRun();

      r.s.selectLayer(r.a);
      pill(r.s).pasteIndependentFrame();

      final base = named(r.s, 'B');
      final above = named(r.s, aboveName);
      expect(above.attachedMode, AttachedMode.synced);
      expect(above.timeline, isEmpty, reason: 'the base\'s timing is its own');
      expect(above.baseFrameLinks, isNotEmpty, reason: '⛔전제');
      expect(above.baseFrameLinks.keys, [
        for (final exposure in base.timeline.values) exposure.frameId,
      ]);
      expect(
        above.baseFrameLinks.values.toSet(),
        above.frames.map((frame) => frame.id).toSet(),
      );
    });

    test('their pictures come along, each under the cel it landed with', () {
      final r = riders();
      final aboveName = r.s.requireActiveCut.layers.byId(r.above)!.name;
      List<Object?> picturesOf(Layer row) => [
        for (final cel in row.frames)
          r.s.renderCaches.brushFrameStore.bakedSurfaceOrNull(
            r.s.brushFrameKeyForCut(r.s.requireActiveCut, row.id, cel.id),
          ),
      ];
      final base = picturesOf(named(r.s, 'B'));
      final above = picturesOf(named(r.s, aboveName));
      expect(above.nonNulls, isNotEmpty, reason: '⛔전제');
      select(r.s, [r.b]);
      pill(r.s).cutRun();

      r.s.selectLayer(r.a);
      pill(r.s).pasteIndependentFrame();

      expect(picturesOf(named(r.s, 'B')), base);
      expect(picturesOf(named(r.s, aboveName)), above);
    });

    test('one undo of the cut brings them back on their base', () {
      final r = riders();
      final before = r.s.requireActiveCut.layers;
      select(r.s, [r.b]);

      pill(r.s).cutRun();
      r.s.undo();

      expect(r.s.requireActiveCut.layers, before);
    });

    test('the base and its rows selected together are the base: each goes '
        'once', () {
      final r = riders();
      select(r.s, [r.above, r.b, r.below]);

      pill(r.s).cutRun();

      expect(rows(r.s).map((row) => row.name), ['A', 'C']);
      expect(rowsOf(r.s).canPasteRows, isTrue);
    });

    test('a free attach row lands free, on the timing of its own', () {
      final r = riders();
      r.s.selectLayer(r.b);
      r.s.folders.addAttachedLayer(
        AttachedPlacement.above,
        mode: AttachedMode.free,
      );
      final free = r.s.activeLayer!;
      r.s.createDrawingAtCurrentFrame();
      final timing = r.s.requireActiveCut.layers.byId(free.id)!.timeline.keys;
      expect(timing, isNotEmpty, reason: '⛔전제');
      select(r.s, [r.b]);
      pill(r.s).cutRun();

      r.s.selectLayer(r.a);
      pill(r.s).pasteIndependentFrame();

      final landed = named(r.s, free.name);
      expect(landed.attachedToLayerId, named(r.s, 'B').id);
      expect(landed.attachedMode, AttachedMode.free);
      expect(landed.timeline.keys, timing);
      expect(landed.baseFrameLinks, isEmpty);
    });

    test('its organizer folder comes with it and holds its rows again', () {
      final r = riders();
      r.s.selectLayer(r.above);
      final organizer = groupTheActiveAttachIntoAFolder(r.s);
      final organizerName = r.s.requireActiveCut.layers.byId(organizer)!.name;
      final aboveName = r.s.requireActiveCut.layers.byId(r.above)!.name;
      select(r.s, [r.b]);

      pill(r.s).cutRun();

      expect(r.s.requireActiveCut.layers.byId(organizer), isNull);
      r.s.selectLayer(r.a);
      pill(r.s).pasteIndependentFrame();

      final layers = r.s.requireActiveCut.layers;
      expect(folderStructureProblem(layers), isNull);
      final folder = layers.singleWhere((row) => row.name == organizerName);
      final above = named(r.s, aboveName);
      expect(above.folderId, folder.id);
      expect(above.attachedToLayerId, named(r.s, 'B').id);
      expect(attachOrganizerBaseOf(folder, layers), named(r.s, 'B').id);
      expect(folder.kind, LayerKind.folder);
    });

    test('an organizer alone goes with its rows, and lands a plain folder of '
        'plain rows', () {
      final r = riders();
      r.s.selectLayer(r.above);
      final organizer = groupTheActiveAttachIntoAFolder(r.s);
      final organizerName = r.s.requireActiveCut.layers.byId(organizer)!.name;
      final aboveName = r.s.requireActiveCut.layers.byId(r.above)!.name;
      select(r.s, [organizer]);

      expect(pill(r.s).canCutRun, isTrue);
      pill(r.s).cutRun();

      expect(r.s.requireActiveCut.layers.byId(r.above), isNull);
      expect(r.s.requireActiveCut.layers.byId(r.b), isNotNull);

      r.s.selectLayer(r.c);
      pill(r.s).pasteIndependentFrame();

      final layers = r.s.requireActiveCut.layers;
      expect(folderStructureProblem(layers), isNull);
      final folder = layers.singleWhere((row) => row.name == organizerName);
      final above = named(r.s, aboveName);
      expect(folder.kind, LayerKind.folder);
      expect(folder.attachedToLayerId, isNull);
      expect(above.folderId, folder.id);
      expect(above.attachedToLayerId, isNull);
    });
  });

  group('🎯a base in a folder', () {
    test('landing among the folder\'s rows, its attach row lands in there too',
        () {
      final r = riders();
      r.s.selectLayer(r.a);
      final folder = groupTheActiveRowIntoAFolder(r.s);
      select(r.s, [r.b]);
      pill(r.s).copyFrame();

      r.s.selectLayer(r.a);
      pill(r.s).pasteIndependentFrame();

      final layers = r.s.requireActiveCut.layers;
      expect(folderStructureProblem(layers), isNull);
      final riding = layers.where((row) => row.folderId == folder).toList();
      expect(riding.where(isAttachedLayer), hasLength(2));
    });
  });

  test('🗣️F-532-Q2: a linked paste of a base brings its organizer once', () {
    final r = riders();
    r.s.selectLayer(r.above);
    groupTheActiveAttachIntoAFolder(r.s);
    int folders() => r.s.requireActiveCut.layers
        .where((row) => row.kind == LayerKind.folder)
        .length;
    expect(folders(), 1, reason: '⛔전제');
    select(r.s, [r.b]);
    pill(r.s).copyFrame();

    r.s.selectLayer(r.c);
    pill(r.s).pasteLinkedFrame();

    expect(folders(), 2);
  });

  test('an attach row keeps the kind it was, landing alone', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.layerStack.addLayerOfKind(LayerKind.image);
    final base = s.activeLayerId!;
    s.folders.addAttachedLayer(AttachedPlacement.above);
    final rider = s.activeLayerId!;
    expect(
      s.requireActiveCut.layers.byId(rider)!.kind,
      LayerKind.image,
      reason: '⛔전제',
    );
    select(s, [rider]);
    pill(s).copyFrame();

    s.selectLayer(base);
    pill(s).pasteIndependentFrame();

    final images = [
      for (final layer in s.requireActiveCut.layers)
        if (layer.kind == LayerKind.image) layer,
    ];
    expect(images, hasLength(3));
  });

  group('🎯a conte row and what rides it', () {
    ({EditorSessionManager s, LayerId conte, LayerId other}) conted() {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final other = s.activeLayerId!;
      s.layerStack.addLayerOfKind(LayerKind.storyboard);
      final conte = s.activeLayerId!;
      s.createDrawingAtCurrentFrame();
      s.folders.addAttachedLayer(AttachedPlacement.above);
      return (s: s, conte: conte, other: other);
    }

    List<Layer> ofConte(EditorSessionManager s) => [
      for (final layer in s.requireActiveCut.layers)
        if (layer.kind == LayerKind.storyboard) layer,
    ];

    test('cut together, the rider rides the new row, still of its kind', () {
      final r = conted();
      select(r.s, [r.conte]);

      pill(r.s).cutRun();

      expect(ofConte(r.s), isEmpty, reason: '⛔전제');
      r.s.selectLayer(r.other);
      pill(r.s).pasteIndependentFrame();

      final conte = ofConte(r.s);
      expect(conte, hasLength(2));
      expect(conte.last.attachedToLayerId, conte.first.id);
      expect(conte.first.attachedToLayerId, isNull);
    });

    test('where the cut has its conte row the base stays out, and the rider '
        'lands alone without claiming that row\'s place', () {
      final r = conted();
      select(r.s, [r.conte]);
      pill(r.s).copyFrame();

      r.s.selectLayer(r.other);
      pill(r.s).pasteIndependentFrame();

      expect(ofConte(r.s), hasLength(2), reason: 'the row and its rider');
      expect(rows(r.s), hasLength(2));
      expect(rows(r.s).last.attachedToLayerId, isNull);
    });

    test('alone in a cut with no conte row, it does not become that row', () {
      final r = conted();
      final rider = r.s.activeLayerId!;
      select(r.s, [rider]);
      pill(r.s).copyFrame();
      r.s.layerVerbs.deleteLayers([r.conte], step: 'Delete');
      expect(ofConte(r.s), isEmpty, reason: '⛔전제');

      r.s.selectLayer(r.other);
      pill(r.s).pasteIndependentFrame();

      expect(ofConte(r.s), isEmpty);
    });
  });

  group('🎯the cut of an attach row alone', () {
    test('it goes, the base stays, and it lands as a row of its own wearing '
        'the timing it wore', () {
      final r = riders();
      final name = r.s.requireActiveCut.layers.byId(r.above)!.name;
      final timing = rows(r.s)
          .firstWhere((row) => row.id == r.b)
          .timeline
          .keys
          .toList();
      select(r.s, [r.above]);

      expect(pill(r.s).canCutRun, isTrue);
      pill(r.s).cutRun();

      expect(r.s.requireActiveCut.layers.byId(r.above), isNull);
      expect(r.s.requireActiveCut.layers.byId(r.b), isNotNull);

      r.s.selectLayer(r.c);
      pill(r.s).pasteIndependentFrame();

      final landed = named(r.s, name);
      expect(landed.attachedToLayerId, isNull);
      expect(landed.baseFrameLinks, isEmpty);
      expect(landed.timeline.keys, timing);
      expect(
        landed.timeline.values.first.frameId,
        isIn([for (final frame in landed.frames) frame.id]),
      );
    });

    test('the copy takes it the same way, and the row stays', () {
      final r = riders();
      final name = r.s.requireActiveCut.layers.byId(r.above)!.name;
      select(r.s, [r.above]);
      expect(rowsOf(r.s).canCopySelectedRows, isTrue);

      pill(r.s).copyFrame();
      r.s.selectLayer(r.c);
      pill(r.s).pasteIndependentFrame();

      expect(r.s.requireActiveCut.layers.byId(r.above), isNotNull);
      expect(rows(r.s).where((row) => row.name == name), hasLength(2));
    });
  });

  test('the copy of a base takes its rows too, and leaves them', () {
    final r = riders();
    final count = rows(r.s).length;
    select(r.s, [r.b]);

    pill(r.s).copyFrame();
    r.s.selectLayer(r.c);
    pill(r.s).pasteIndependentFrame();

    expect(rows(r.s), hasLength(count + 3));
    expect(
      [for (final row in rows(r.s)) row.attachedToLayerId].nonNulls.toSet(),
      hasLength(2),
      reason: 'the copies ride the copy, not the row they came from',
    );
  });

  test('the camera is still no row a board holds', () {
    final r = riders();
    final camera = r.s.requireActiveCut.layers.firstWhere(
      (row) => row.kind == LayerKind.camera,
    );
    select(r.s, [camera.id]);

    expect(rowsOf(r.s).canCopySelectedRows, isFalse);
  });
}
