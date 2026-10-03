import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/pill_subject.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/cell_instances.dart';
import 'package:anicel/src/ui/session/cell_verbs.dart';
import 'package:anicel/src/ui/session/frame_verbs.dart';
import 'package:anicel/src/ui/session/layer_switch_verbs.dart';

/// 🚨F-278 · F-98 — A LINKED ROW'S PICTURES ARE ONE BANK, AND A PICTURE IS
/// SHARED BY ITS NAME: on an animation row, on an image row, and on the
/// synced attach rows that ride either.
///
/// 유저 2026-10-04 (F-278): 「이미지레이어의 싱크어태치레이어의 그림이
/// 링크컷끼리 공유안됨. 같은 프레임이름인데도. 물론 이름이 없으면 독립적인
/// 그림이니까 링크 안되는게 맞음. 다만 이름이 서로 같은 블록인데도 링크안됨.
/// 이 카드 작업하면서 이미지레이어도 프레임 없는상태. 프레임 삭제 가능하도록
/// 하라는 카드있을텐데 같이 작업」 · 「이미지레이어도 타임라인 링크독립버튼
/// 가능하도록. 작동하면 애니메이션레이어와 동일하게 이름이 사라짐. 독립적인
/// 개체로 돌아가는것」 · 「겸용컷 블렌드모드도 공유하도록 하자 … 보이기만
/// 독립적으로 하고」.
///
/// 유저 2026-09-12 (F-98): 「이미지 레이어도 프레임이 없는 상태는 존재함.
/// 생성하면 기본적으로 프레임 생성되는건 그대로지만 삭제가능하도록. 없는
/// 상태가 존재하도록 구조/근본적 변경. 그런부분은 일반 애니메이션레이어랑 법
/// 맞추면서 통일/재사용. 그리고 이미지 레이어는 이름이 없는 상태인데도
/// 겸용컷이랑 링크되는데, 그게아니라 애니메이션 레이어랑 똑같이 이름이
/// 같아야만 링크되도록. 이름 안정해지면 별개것임」.
///
/// The collaborators are held BY THEIR OWN TYPES so the mutation runner names
/// this file as their witness (it picks witnesses by import).
void main() {
  CellVerbs cellsOf(EditorSessionManager s) => s.cells;
  FrameVerbs framesOf(EditorSessionManager s) => s.frameVerbs;
  CellInstances instancesOf(EditorSessionManager s) => s.cellInstances;
  LayerSwitchVerbs switchesOf(EditorSessionManager s) => s.layerSwitches;

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  /// A picture at the CUT's canvas size — the store answers only that shape.
  BitmapSurface ink(CanvasSize canvasSize) {
    const tile = 256;
    final pixels = Uint8List(tile * tile * 4)..fillRange(0, 16, 255);
    return BitmapSurface(canvasSize: canvasSize, tileSize: tile).putTiles([
      (
        coord: TileCoord(x: 0, y: 0),
        tile: BitmapTile(size: tile, pixels: pixels),
      ),
    ]);
  }

  Cut cutOf(EditorSessionManager s, CutId cutId) =>
      s.activeTrack.cuts.firstWhere((cut) => cut.id == cutId);

  /// The STORED row — not the display clone a synced attach row is shown as.
  Layer rowIn(EditorSessionManager s, CutId cutId, LayerId layerId) =>
      cutOf(s, cutId).layers.firstWhere((layer) => layer.id == layerId);

  /// [row]'s member in [cutId] — the other row of its link group there.
  LayerId memberIn(
    EditorSessionManager s,
    CutId cutId, {
    required CutId of,
    required LayerId row,
  }) => s.repository
      .requireProject()
      .linkRegistry
      .groupOf(cutId: of, layerId: row)!
      .members
      .firstWhere((member) => member.cutId == cutId && member.layerId != row)
      .layerId;

  /// The cel the row's lane shows — its one block's on an image row.
  FrameId? shown(EditorSessionManager s, CutId cutId, LayerId layerId) =>
      authoredBlockOf(rowIn(s, cutId, layerId))?.frameId;

  /// The cel the attach row shows over its base's frame [frameIndex].
  FrameId? mirrored(
    EditorSessionManager s,
    CutId cutId, {
    required LayerId base,
    required LayerId attach,
    int frameIndex = 0,
  }) => attachedFrameIdAt(
    attached: rowIn(s, cutId, attach),
    base: rowIn(s, cutId, base),
    frameIndex: frameIndex,
  );

  /// A base row of [kind] holding a picture, active on frame 0. An image row
  /// is born with its picture; an animation row is given one.
  LayerId baseOf(EditorSessionManager s, LayerKind kind) {
    if (kind == LayerKind.image) {
      s.layerStack.addLayerOfKind(LayerKind.image);
    }
    final base = s.activeLayer!.id;
    s.selectFrameIndex(0);
    if (kind == LayerKind.animation) {
      s.createDrawingAtCurrentFrame();
    }
    return base;
  }

  /// A synced attach row riding [base] in the active cut.
  LayerId attachOn(EditorSessionManager s, LayerId base) {
    s.selectLayer(base);
    s.folders.addAttachedLayer(AttachedPlacement.above);
    final attach = s.layers
        .firstWhere((layer) => layer.attachedToLayerId == base)
        .id;
    s.selectLayer(base);
    s.selectFrameIndex(0);
    return attach;
  }

  /// Names the picture under the playhead on the active row [name] — and,
  /// when the bank already holds a picture of that name, joins it (the
  /// answer the rename's prompt takes for 「같은 이름 = 같은 그림」).
  void nameShownPicture(EditorSessionManager s, String name) {
    final conflict = framesOf(s).renameSelectedFrame(name);
    if (conflict != null) {
      framesOf(s).linkSelectedFrame(conflict);
    }
  }

  /// Stands on [row] of [cutId] at frame 0, with a picture there.
  void standOn(EditorSessionManager s, CutId cutId, LayerId row) {
    s.selectCut(cutId);
    s.selectLayer(row);
    s.selectFrameIndex(0);
    if (!rowHoldsABlock(rowIn(s, cutId, row))) {
      s.createDrawingAtCurrentFrame();
    }
  }

  void expectOnePictureOnBothAttachRows(
    EditorSessionManager s, {
    required CutId cut1,
    required LayerId base1,
    required LayerId attach1,
    required CutId cut2,
    required LayerId base2,
    required LayerId attach2,
  }) {
    expect(
      shown(s, cut1, base1),
      shown(s, cut2, base2),
      reason: '⛔전제: the two cuts show the SAME base picture',
    );
    final cel = mirrored(s, cut1, base: base1, attach: attach1);
    expect(cel, isNotNull, reason: '⛔전제: the attach row mirrors its base');
    expect(
      mirrored(s, cut2, base: base2, attach: attach2),
      cel,
      reason: '「이름이 서로 같은 블록인데도 링크안됨」 — one base picture, '
          'ONE attach picture, in whichever cut it is shown',
    );
    // The picture itself, not just its id: drawn in one cut, shown in the
    // other.
    final store = s.renderCaches.brushFrameStore;
    store.storeBakedSurface(
      s.brushFrameKeyForCut(cutOf(s, cut1), attach1, cel!),
      ink(cutOf(s, cut1).canvasSize),
    );
    expect(
      store
          .bakedSurfaceOrNull(
            s.brushFrameKeyForCut(cutOf(s, cut2), attach2, cel),
          )
          ?.tiles,
      isNotEmpty,
      reason: 'what is drawn on the attach row in one cut is what the other '
          'cut\'s attach row shows',
    );
  }

  for (final kind in [LayerKind.animation, LayerKind.image]) {
    group('F-278 — a synced attach row over ${kind.name}', () {
      test('ADDED to cuts already linked: both cuts mirror the base picture '
          'with one attach picture', () {
        final s = session();
        final base1 = baseOf(s, kind);
        final cut1 = s.requireActiveCut.id;
        nameShownPicture(s, '1');
        s.cutVerbs.createLinkedCutFromActiveCut();
        final cut2 = s.requireActiveCut.id;
        final base2 = memberIn(s, cut2, of: cut1, row: base1);
        standOn(s, cut2, base2);
        nameShownPicture(s, '1');

        s.selectCut(cut1);
        final attach1 = attachOn(s, base1);
        final attach2 = memberIn(s, cut2, of: cut1, row: attach1);

        expectOnePictureOnBothAttachRows(
          s,
          cut1: cut1,
          base1: base1,
          attach1: attach1,
          cut2: cut2,
          base2: base2,
          attach2: attach2,
        );
      });

      test('the base named AFTER the linked cut is made: the attach rows '
          'come to one picture when the bases do', () {
        final s = session();
        final base1 = baseOf(s, kind);
        final cut1 = s.requireActiveCut.id;
        final attach1 = attachOn(s, base1);
        s.cutVerbs.createLinkedCutFromActiveCut();
        final cut2 = s.requireActiveCut.id;
        final base2 = memberIn(s, cut2, of: cut1, row: base1);
        final attach2 = memberIn(s, cut2, of: cut1, row: attach1);

        standOn(s, cut1, base1);
        nameShownPicture(s, '1');
        standOn(s, cut2, base2);
        nameShownPicture(s, '1');

        expectOnePictureOnBothAttachRows(
          s,
          cut1: cut1,
          base1: base1,
          attach1: attach1,
          cut2: cut2,
          base2: base2,
          attach2: attach2,
        );
      });

      test('two cuts CONVERTED to linked cuts: the same-named base pictures '
          'become one, and so do their attach pictures', () {
        final s = session();
        final base1 = baseOf(s, kind);
        final cut1 = s.requireActiveCut.id;
        final attach1 = attachOn(s, base1);
        nameShownPicture(s, '1');
        // An INDEPENDENT copy of the cut: the same names, its own pictures.
        s.cutVerbs.duplicateActiveCut();
        final cut2 = s.activeTrack.cuts.firstWhere((cut) => cut.id != cut1).id;

        s.selectCut(cut1);
        s.cutVerbs.convertActiveCutToLinked(cut2);
        final base2 = memberIn(s, cut2, of: cut1, row: base1);
        final attach2 = memberIn(s, cut2, of: cut1, row: attach1);

        expectOnePictureOnBothAttachRows(
          s,
          cut1: cut1,
          base1: base1,
          attach1: attach1,
          cut2: cut2,
          base2: base2,
          attach2: attach2,
        );
      });
    });
  }

  test('a base picture that comes over from the OTHER cut brings the attach '
      'picture that cut already drew for it', () {
    final s = session();
    final base1 = baseOf(s, LayerKind.animation);
    final cut1 = s.requireActiveCut.id;
    final attach1 = attachOn(s, base1);
    nameShownPicture(s, '1');
    s.cutVerbs.duplicateActiveCut();
    final cut2 = s.activeTrack.cuts.firstWhere((cut) => cut.id != cut1).id;
    LayerId namesakeIn2(LayerId row) {
      final name = rowIn(s, cut1, row).name;
      return cutOf(s, cut2).layers.firstWhere((layer) => layer.name == name).id;
    }

    final base2 = namesakeIn2(base1);
    final attach2 = namesakeIn2(attach1);
    // Cut 2 alone draws 「2」 — and its attach picture — BEFORE the cuts link.
    s.selectCut(cut2);
    s.selectLayer(base2);
    s.selectFrameIndex(5);
    s.createDrawingAtCurrentFrame();
    nameShownPicture(s, '2');
    final drawn = mirrored(
      s,
      cut2,
      base: base2,
      attach: attach2,
      frameIndex: 5,
    )!;
    s.renderCaches.brushFrameStore.storeBakedSurface(
      s.brushFrameKeyForCut(cutOf(s, cut2), attach2, drawn),
      ink(cutOf(s, cut2).canvasSize),
    );

    s.selectCut(cut1);
    s.cutVerbs.convertActiveCutToLinked(cut2);
    // Cut 1 comes to show 「2」 too.
    s.selectLayer(base1);
    s.selectFrameIndex(5);
    s.createDrawingAtCurrentFrame();
    nameShownPicture(s, '2');
    expect(
      rowIn(s, cut1, base1).timeline[5]?.frameId,
      rowIn(s, cut2, base2).timeline[5]?.frameId,
      reason: '⛔전제: both cuts show the one 「2」',
    );

    expect(
      mirrored(s, cut1, base: base1, attach: attach1, frameIndex: 5),
      drawn,
      reason: 'the attach picture cut 2 drew — not a blank one of cut 1\'s own',
    );
    expect(
      s.renderCaches.brushFrameStore
          .bakedSurfaceOrNull(
            s.brushFrameKeyForCut(cutOf(s, cut1), attach1, drawn),
          )
          ?.tiles,
      isNotEmpty,
      reason: 'and cut 1 shows what was drawn on it',
    );
  });

  test('⛔「이름이 없으면 독립적인 그림이니까 링크 안되는게 맞음」 — two cuts '
      'showing DIFFERENT base pictures mirror them with different attach '
      'pictures', () {
    final s = session();
    final base1 = baseOf(s, LayerKind.image);
    final cut1 = s.requireActiveCut.id;
    final attach1 = attachOn(s, base1);
    s.cutVerbs.createLinkedCutFromActiveCut();
    final cut2 = s.requireActiveCut.id;
    final base2 = memberIn(s, cut2, of: cut1, row: base1);
    final attach2 = memberIn(s, cut2, of: cut1, row: attach1);

    expect(shown(s, cut2, base2), isNot(shown(s, cut1, base1)));
    final mirror1 = mirrored(s, cut1, base: base1, attach: attach1);
    final mirror2 = mirrored(s, cut2, base: base2, attach: attach2);
    expect(mirror1, isNotNull);
    expect(mirror2, isNotNull);
    expect(mirror2, isNot(mirror1));
  });

  group('F-98 — an image row is born with its picture, in every cut', () {
    test('겸용컷 생성: the new cut\'s row is born with a picture of ITS OWN — '
        'the unnamed picture of the source is not shared', () {
      final s = session();
      final row1 = baseOf(s, LayerKind.image);
      final cut1 = s.requireActiveCut.id;
      final picture1 = shown(s, cut1, row1)!;

      s.cutVerbs.createLinkedCutFromActiveCut();
      final cut2 = s.requireActiveCut.id;
      final row2 = memberIn(s, cut2, of: cut1, row: row1);

      final picture2 = shown(s, cut2, row2);
      expect(picture2, isNotNull, reason: '「생성하면 기본적으로 프레임 '
          '생성되는건 그대로」');
      expect(picture2, isNot(picture1), reason: '「이름 안정해지면 별개것임」');
      expect(shown(s, cut1, row1), picture1, reason: 'the source keeps its');
      for (final (cut, row) in [(cut1, row1), (cut2, row2)]) {
        expect(
          {for (final frame in rowIn(s, cut, row).frames) frame.id},
          {picture1, picture2},
          reason: 'one bank, every member holding both pictures',
        );
      }
    });

    test('⛔a synced attach row is born EMPTY there, whatever kind it took '
        'from its base — it mirrors, and stores no lane', () {
      final s = session();
      final base1 = baseOf(s, LayerKind.image);
      final cut1 = s.requireActiveCut.id;
      final attach1 = attachOn(s, base1);

      s.cutVerbs.createLinkedCutFromActiveCut();
      final cut2 = s.requireActiveCut.id;
      final attach2 = rowIn(
        s,
        cut2,
        memberIn(s, cut2, of: cut1, row: attach1),
      );

      expect(attach2.kind, LayerKind.image, reason: '⛔전제');
      expect(attach2.timeline, isEmpty);
      expect(
        attach2.frames.map((frame) => frame.id),
        everyElement(
          predicate<FrameId>(
            attach2.baseFrameLinks.containsValue,
            'a mirror of a base picture',
          ),
        ),
        reason: 'no panel of its own in its bank',
      );
    });

    test('a row ADDED to a cut with a 겸용 sibling: the sibling\'s row is '
        'born with a picture of its own', () {
      final s = session();
      final cut1 = s.requireActiveCut.id;
      s.cutVerbs.createLinkedCutFromActiveCut();
      final cut2 = s.requireActiveCut.id;

      s.selectCut(cut1);
      s.layerStack.addLayerOfKind(LayerKind.image);
      final row1 = s.activeLayer!.id;
      final row2 = memberIn(s, cut2, of: cut1, row: row1);

      final picture1 = shown(s, cut1, row1);
      final picture2 = shown(s, cut2, row2);
      expect(picture1, isNotNull);
      expect(picture2, isNotNull);
      expect(picture2, isNot(picture1), reason: '「이름 안정해지면 별개것임」');
      for (final (cut, row) in [(cut1, row1), (cut2, row2)]) {
        expect(
          {for (final frame in rowIn(s, cut, row).frames) frame.id},
          {picture1, picture2},
          reason: 'one bank, every member holding both pictures',
        );
      }

      s.undo();
      expect(cutOf(s, cut1).layers.any((layer) => layer.id == row1), isFalse);
      expect(cutOf(s, cut2).layers.any((layer) => layer.id == row2), isFalse);
    });

    test('겸용 변경: two UNNAMED pictures stay two — ↩️the image row\'s '
        'by-position match (2026-07-30) is gone', () {
      final s = session();
      final row1 = baseOf(s, LayerKind.image);
      final cut1 = s.requireActiveCut.id;
      s.cutVerbs.duplicateActiveCut();
      final cut2 = s.activeTrack.cuts.firstWhere((cut) => cut.id != cut1).id;
      final picture1 = shown(s, cut1, row1)!;

      s.selectCut(cut1);
      s.cutVerbs.convertActiveCutToLinked(cut2);
      final row2 = memberIn(s, cut2, of: cut1, row: row1);

      expect(shown(s, cut1, row1), picture1);
      expect(shown(s, cut2, row2), isNotNull);
      expect(shown(s, cut2, row2), isNot(picture1));
    });

    test('a frame NAMED like the other cut\'s picture IS that picture', () {
      final s = session();
      final row1 = baseOf(s, LayerKind.image);
      final cut1 = s.requireActiveCut.id;
      nameShownPicture(s, '1');
      final picture1 = shown(s, cut1, row1)!;
      s.cutVerbs.createLinkedCutFromActiveCut();
      final cut2 = s.requireActiveCut.id;
      final row2 = memberIn(s, cut2, of: cut1, row: row1);
      standOn(s, cut2, row2);
      expect(shown(s, cut2, row2), isNot(picture1), reason: '⛔전제');

      expect(
        framesOf(s).renameSelectedFrame('1'),
        picture1,
        reason: 'the name is taken in the bank the two rows share — the '
            'rename answers with the picture that holds it',
      );
      framesOf(s).linkSelectedFrame(picture1);

      expect(shown(s, cut2, row2), picture1);
      expect(shown(s, cut1, row1), picture1);
    });
  });

  group('F-98 — an image row can stand empty', () {
    /// An image row holding its picture, active on frame 0.
    ({EditorSessionManager s, CutId cut, LayerId row}) imageRow() {
      final s = session();
      final row = baseOf(s, LayerKind.image);
      return (s: s, cut: s.requireActiveCut.id, row: row);
    }

    test('its block deletes, the row STAYS empty through later writes, and '
        'one undo brings the picture back', () {
      final (:s, :cut, :row) = imageRow();
      final picture = shown(s, cut, row)!;
      expect(cellsOf(s).canDeleteCellAtCurrentFrame, isTrue);
      expect(s.deleteSubject, PillSubject.cells);

      s.deleteSelectionSubject();

      expect(rowIn(s, cut, row).timeline, isEmpty);
      expect(rowIn(s, cut, row).frames, isEmpty);
      // Any write runs the normalization that used to re-cover the row.
      s.layerVerbs.renameLayer(row, 'BG2');
      expect(rowIn(s, cut, row).name, 'BG2', reason: '⛔전제: a write ran');
      expect(rowIn(s, cut, row).timeline, isEmpty);

      s.undo();
      s.undo();
      expect(shown(s, cut, row), picture);
      expect(
        rowIn(s, cut, row).timeline.values.where((entry) => entry.ghost),
        isNotEmpty,
        reason: 'the picture is held over the cut again (D22)',
      );
    });

    test('⛔the hold past its block is not the block — the delete asks the '
        'block, as on every row that holds one', () {
      final (:s, cut: _, row: _) = imageRow();
      s.selectFrameIndex(3);
      expect(cellsOf(s).canDeleteCellAtCurrentFrame, isFalse);
    });

    test('an empty row takes a picture at ANY frame, laid as the row\'s one '
        'held block — and then takes no second', () {
      final (:s, :cut, :row) = imageRow();
      s.deleteSelectionSubject();
      s.selectFrameIndex(4);
      expect(framesOf(s).canCreateDrawingAtCurrentFrame, isTrue);

      s.createDrawingAtCurrentFrame();

      final block = rowIn(s, cut, row).timeline[0];
      expect(block?.isDrawing, isTrue);
      expect(block?.ghost, isFalse);
      expect(block?.length, 1);
      expect(block?.endEdge.mode, TimelineRunEdgeMode.hold);
      expect(
        rowIn(s, cut, row).timeline.values.where((entry) => !entry.ghost),
        hasLength(1),
      );
      expect(framesOf(s).canCreateDrawingAtCurrentFrame, isFalse);
      s.selectFrameIndex(0);
      expect(framesOf(s).canCreateDrawingAtCurrentFrame, isFalse);
    });

    test('a BAND makes it too — and makes nothing on a row holding its '
        'picture', () {
      final (:s, :cut, :row) = imageRow();
      final picture = shown(s, cut, row)!;
      void sweep() => s.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: row,
        startIndex: 2,
        endIndexExclusive: 6,
      );

      sweep();
      expect(instancesOf(s).createInstancesForSelection(), isTrue);
      expect(shown(s, cut, row), picture, reason: 'nothing to make');
      expect(rowIn(s, cut, row).frames, hasLength(1));

      s.frameRangeSelection.value = null;
      s.selectFrameIndex(0);
      s.deleteSelectionSubject();
      expect(rowIn(s, cut, row).timeline, isEmpty, reason: '⛔전제');

      sweep();
      expect(instancesOf(s).createInstancesForSelection(), isTrue);
      final made = shown(s, cut, row);
      expect(made, isNotNull);
      expect(made, isNot(picture));
      expect(rowIn(s, cut, row).timeline[0]?.frameId, made);
      expect(rowIn(s, cut, row).frames, hasLength(1));
    });

    test('⛔a band makes nothing on a REFERENCE row either — the press at '
        'the playhead refuses there, and the band gives the same answer', () {
      final s = session();
      final row = s.activeLayer!.id;
      final cut = s.requireActiveCut.id;
      s.repository.updateLayer(
        layerId: row,
        update: (layer) => layer.copyWith(
          mediaReference: MediaReference(assetPath: 'media/a.png'),
        ),
      );
      s.selectFrameIndex(2);
      expect(framesOf(s).canCreateDrawingAtCurrentFrame, isFalse);

      s.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: row,
        startIndex: 2,
        endIndexExclusive: 6,
      );
      instancesOf(s).createInstancesForSelection();

      expect(rowIn(s, cut, row).timeline, isEmpty);
      expect(rowIn(s, cut, row).frames, isEmpty);
    });

    test('a band over an image row and a cel row deletes BOTH blocks in one '
        'undo', () {
      final s = session();
      final cel = s.activeLayer!.id;
      s.selectFrameIndex(0);
      s.createDrawingAtCurrentFrame();
      final image = baseOf(s, LayerKind.image);
      final cut = s.requireActiveCut.id;
      // The picture row ALONE under a band: the gate answers for it.
      s.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: image,
        startIndex: 0,
        endIndexExclusive: 2,
      );
      expect(cellsOf(s).canDeleteCellForSelection, isTrue);

      s.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: image,
        layerIds: [cel, image],
        startIndex: 0,
        endIndexExclusive: 2,
      );
      final entries = s.historyManager.undoCount;

      s.deleteSelectionSubject();

      expect(rowIn(s, cut, image).timeline, isEmpty);
      expect(rowIn(s, cut, cel).timeline, isEmpty);
      expect(s.historyManager.undoCount, entries + 1, reason: 'ONE step');
      s.undo();
      expect(rowHoldsABlock(rowIn(s, cut, image)), isTrue);
      expect(rowHoldsABlock(rowIn(s, cut, cel)), isTrue);
    });

    test('⛔a row emptied in one 겸용 cut stays empty while its BANK holds '
        'the picture the other cut still shows', () {
      final s = session();
      final row1 = baseOf(s, LayerKind.image);
      final cut1 = s.requireActiveCut.id;
      nameShownPicture(s, '1');
      final picture = shown(s, cut1, row1)!;
      s.cutVerbs.createLinkedCutFromActiveCut();
      final cut2 = s.requireActiveCut.id;
      final row2 = memberIn(s, cut2, of: cut1, row: row1);
      standOn(s, cut2, row2);
      nameShownPicture(s, '1');
      expect(shown(s, cut2, row2), picture, reason: '⛔전제: one picture');

      s.deleteSelectionSubject();

      expect(rowIn(s, cut2, row2).timeline, isEmpty);
      expect(shown(s, cut1, row1), picture, reason: 'the other cut keeps it');
      expect(
        rowIn(s, cut2, row2).frames.map((frame) => frame.id),
        contains(picture),
        reason: '⛔전제: the bank is the group\'s — it still holds the picture',
      );
      s.layerVerbs.renameLayer(row2, 'BG2');
      expect(
        rowIn(s, cut2, row2).timeline,
        isEmpty,
        reason: 'the bank\'s picture is not put back on the row',
      );
      expect(
        framesOf(s).canCreateDrawingAtCurrentFrame,
        isTrue,
        reason: 'the ROW stands empty and takes a picture — what its bank '
            'holds is the group\'s',
      );
    });
  });

  group('링크 독립 on an image row', () {
    test('a picture another cut shows gets a copy of its own: unnamed, with '
        'the drawing, the other cut untouched — ONE undo', () {
      final s = session();
      final row1 = baseOf(s, LayerKind.image);
      final cut1 = s.requireActiveCut.id;
      nameShownPicture(s, '1');
      final picture = shown(s, cut1, row1)!;
      s.renderCaches.brushFrameStore.storeBakedSurface(
        s.brushFrameKeyForCut(cutOf(s, cut1), row1, picture),
        ink(cutOf(s, cut1).canvasSize),
      );
      s.cutVerbs.createLinkedCutFromActiveCut();
      final cut2 = s.requireActiveCut.id;
      final row2 = memberIn(s, cut2, of: cut1, row: row1);
      standOn(s, cut2, row2);
      nameShownPicture(s, '1');
      expect(shown(s, cut2, row2), picture, reason: '⛔전제: linked by name');

      expect(cellsOf(s).canUnlinkCells, isTrue);
      expect(s.unlinkSubject, PillSubject.cells);
      // A band over the picture means the same block — and it is the band
      // that presses.
      s.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: row2,
        startIndex: 0,
        endIndexExclusive: 2,
      );
      expect(s.unlinkSubject, PillSubject.cells);
      final entries = s.historyManager.undoCount;

      s.unlinkSelectionSubject();

      final copy = shown(s, cut2, row2);
      expect(copy, isNotNull);
      expect(copy, isNot(picture), reason: '「독립적인 개체로 돌아가는것」');
      final copied = rowIn(s, cut2, row2).frameById(copy!)!;
      expect(copied.name, isNull, reason: '「이름이 사라짐」');
      expect(
        s.renderCaches
            .brushSurfaceForLayerFrame(rowIn(s, cut2, row2), copied)
            ?.tiles,
        isNotEmpty,
        reason: 'the copy shows the same drawing',
      );
      expect(shown(s, cut1, row1), picture);
      expect(rowIn(s, cut1, row1).frameById(picture)?.name, '1');
      expect(s.historyManager.undoCount, entries + 1, reason: 'ONE step');

      s.undo();
      expect(shown(s, cut2, row2), picture, reason: 'one undo links it back');
    });

    test('⛔a picture nobody else shows is independent already', () {
      final s = session();
      baseOf(s, LayerKind.image);
      expect(cellsOf(s).canUnlinkCells, isFalse);
      expect(s.unlinkSubject, PillSubject.nothing);
    });
  });

  group('the blend is the link group\'s', () {
    /// A cel row in two 겸용 cuts.
    ({
      EditorSessionManager s,
      CutId cut1,
      LayerId row1,
      CutId cut2,
      LayerId row2,
    })
    linked() {
      final s = session();
      final row1 = baseOf(s, LayerKind.animation);
      final cut1 = s.requireActiveCut.id;
      s.cutVerbs.createLinkedCutFromActiveCut();
      final cut2 = s.requireActiveCut.id;
      return (
        s: s,
        cut1: cut1,
        row1: row1,
        cut2: cut2,
        row2: memberIn(s, cut2, of: cut1, row: row1),
      );
    }

    test('「겸용컷 블렌드모드도 공유」: set in one cut, it is every cut\'s — '
        'and one undo puts back each', () {
      final (:s, :cut1, :row1, :cut2, :row2) = linked();
      final entries = s.historyManager.undoCount;

      switchesOf(s).setLayerBlendMode(row2, LayerBlendMode.multiply);

      expect(rowIn(s, cut2, row2).blendMode, LayerBlendMode.multiply);
      expect(rowIn(s, cut1, row1).blendMode, LayerBlendMode.multiply);
      expect(s.historyManager.undoCount, entries + 1, reason: 'ONE step');

      s.undo();
      expect(rowIn(s, cut2, row2).blendMode, LayerBlendMode.normal);
      expect(rowIn(s, cut1, row1).blendMode, LayerBlendMode.normal);
    });

    test('the legend\'s bulk pick reaches the group too, in ONE undo', () {
      final (:s, :cut1, :row1, :cut2, :row2) = linked();
      final entries = s.historyManager.undoCount;

      switchesOf(s).setBlendModeForLayers({row2}, LayerBlendMode.screen);

      expect(rowIn(s, cut2, row2).blendMode, LayerBlendMode.screen);
      expect(rowIn(s, cut1, row1).blendMode, LayerBlendMode.screen);
      expect(s.historyManager.undoCount, entries + 1);
    });

    // 「보이기만 독립적으로」 — the eye and the static opacity staying each
    // use's own, and a row link-duplicated in the SAME cut following its
    // group's blend, are pinned in `editor_session_manager_link_test.dart`
    // (T9's own test).
  });
}
