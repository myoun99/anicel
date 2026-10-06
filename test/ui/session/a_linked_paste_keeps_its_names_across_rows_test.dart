import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_splice.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_run_behavior.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/frame_clipboard.dart';
import 'package:anicel/src/ui/session/independent_clip_mint.dart';

/// 🗣️I-71 (유저 2026-10-05):
///
/// ① 「싱크레이어의 프레임블록이라도 복사는 가능하도록. 물론 해당 레이어에
///    붙여넣기는 안되지만 다른 레이어에 붙여넣을수있게. 지금처럼 동작은 링크면
///    이름유지된채로 붙여넣고 독립이면 모두 이름 리셋」.
/// ② 「그 외에도 그냥 다른레이어에 붙여넣을때 독립붙여넣기밖에 안되는데,
///    링크붙여넣기 가능하게. 동작은 말한대로 이름 유지되는붙여넣기. 해당행동시
///    기존에 이름 존재한다면 링크시킬지 묻는것도 띄우고」.
///
/// A link is 「the same drawing exposed again」, and a drawing belongs to its
/// row — so across rows what is kept is the NAME (「같은 이름 = 같은 그림」).
/// ↩️The linked paste asked 「is that cel in THIS row」 and turned every
/// other row away (`paste_into_another_row_test`, 유저 #4's round).
///
/// 🧪Measured before (2026-10-06): a RANGE copied off a synced row banked an
/// empty clip — the copy read the stored row, and a synced row stores no
/// timeline — and its cut was lit and lifted nothing.
///
/// The window that asks is pinned where it is pressed
/// (`timeline/the_linked_paste_asks_before_it_joins_test`).
void main() {
  FrameClipboard clipboardOf(EditorSessionManager s) => s.clipboard;

  /// A picture at the cut's canvas size, its first bytes [shade].
  BitmapSurface ink(EditorSessionManager s, int shade) {
    const tile = 256;
    final pixels = Uint8List(tile * tile * 4)..fillRange(0, 16, shade);
    return BitmapSurface(
      canvasSize: s.requireActiveCut.canvasSize,
      tileSize: tile,
    ).putTiles([
      (
        coord: TileCoord(x: 0, y: 0),
        tile: BitmapTile(size: tile, pixels: pixels),
      ),
    ]);
  }

  Layer rowOf(EditorSessionManager s, LayerId id) =>
      s.requireActiveCut.layers.firstWhere((layer) => layer.id == id);

  void paint(EditorSessionManager s, LayerId row, FrameId cel, int shade) =>
      s.renderCaches.brushFrameStore.storeBakedSurface(
        s.brushFrameKeyForCut(s.requireActiveCut, row, cel),
        ink(s, shade),
      );

  int? shadeOf(EditorSessionManager s, LayerId row, FrameId cel) => s
      .renderCaches
      .brushFrameStore
      .bakedSurfaceOrNull(s.brushFrameKeyForCut(s.requireActiveCut, row, cel))
      ?.tiles
      .values
      .firstOrNull
      ?.pixels
      .first;

  /// What [row] stores at each frame it starts a block on: the drawing's
  /// name and its picture's shade.
  Map<int, (String?, int?)> blocksOf(EditorSessionManager s, LayerId row) {
    final layer = rowOf(s, row);
    return {
      for (final MapEntry(key: frame, value: exposure)
          in layer.timeline.entries)
        if (!exposure.ghost)
          frame: (
            layer.frameById(exposure.frameId!)?.name,
            shadeOf(s, row, exposure.frameId!),
          ),
    };
  }

  /// A base row holding X at 0 (shade 10) and Y at 2 (shade 20), its synced
  /// attach row above it with a drawing of its own under each (31 and 32),
  /// and an empty cel row.
  ({EditorSessionManager s, LayerId base, LayerId mirror, LayerId other})
  baseMirrorAndAnEmptyRow() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final base = s.activeLayer!.id;
    for (final (frame, name, shade) in [(0, 'X', 10), (2, 'Y', 20)]) {
      s.selectFrameIndex(frame);
      s.createDrawingAtCurrentFrame();
      expect(s.frameVerbs.renameSelectedFrame(name), isNull, reason: '⛔전제');
      paint(s, base, s.selectedFrame!.id, shade);
    }
    s.folders.addAttachedLayer(AttachedPlacement.above);
    final mirror = s.activeLayer!.id;
    for (final (frame, shade) in [(0, 31), (2, 32)]) {
      final baseCel = rowOf(s, base).timeline[frame]!.frameId!;
      paint(s, mirror, rowOf(s, mirror).baseFrameLinks[baseCel]!, shade);
    }
    s.selectLayer(base);
    s.layerStack.addLayerOfKind(LayerKind.animation);
    final other = s.activeLayer!.id;
    expect(rowOf(s, mirror).timeline, isEmpty, reason: '⛔전제: stores none');
    return (s: s, base: base, mirror: mirror, other: other);
  }

  /// Sweeps frames [0, 4) of [row] and copies them.
  void copyTheRunOf(EditorSessionManager s, LayerId row) {
    s.selectLayer(row);
    s.selectFrameIndex(0);
    s.updateFrameRangeSelectionDrag(layerId: row, anchorIndex: 0, headIndex: 3);
    expect(clipboardOf(s).canCopyFrameAtCurrentFrame, isTrue, reason: '⛔전제');
    clipboardOf(s).copyFrameAtCurrentFrame();
  }

  /// Stands on [row] at [frame] with nothing selected - a paste there goes
  /// IN at the playhead, where a selection would be replaced by it.
  void standOn(EditorSessionManager s, LayerId row, int frame) {
    s.clearFrameRangeSelection();
    s.selectLayer(row);
    s.selectFrameIndex(frame);
  }

  group('① a synced row\'s blocks are copied as the row shows them', () {
    test('a swept run pastes its blocks, with the row\'s own pictures — '
        'independent, every name reset', () {
      final (:s, base: _, :mirror, :other) = baseMirrorAndAnEmptyRow();
      copyTheRunOf(s, mirror);

      standOn(s, other, 0);
      expect(clipboardOf(s).canPasteIndependentFrameAtCurrentFrame, isTrue);
      clipboardOf(s).pasteIndependentFrameAtCurrentFrame();

      expect(blocksOf(s, other), {0: (null, 31), 2: (null, 32)});
    });

    test('…and linked, under the names the row PRINTS — its base\'s', () {
      final (:s, base: _, :mirror, :other) = baseMirrorAndAnEmptyRow();
      copyTheRunOf(s, mirror);

      standOn(s, other, 4);
      expect(clipboardOf(s).canPasteLinkedFrameAtCurrentFrame, isTrue);
      expect(clipboardOf(s).pasteLinkedFrameAtCurrentFrame(), isNull);

      expect(blocksOf(s, other), {4: ('X', 31), 6: ('Y', 32)});
    });

    test('the ghost of a hold on the row is no block of the run — the copy '
        'reads the row ghost-free, as the copy of every row does (F-134)', () {
      final (:s, :base, :mirror, :other) = baseMirrorAndAnEmptyRow();
      s.rangeMove.setRunEdgeBehavior(
        layerId: base,
        blockStartIndex: 2,
        side: TimelineRunEdgeSide.end,
        mode: TimelineRunEdgeMode.hold,
      );
      expect(
        coveringDrawingBlockAt(
          attachedRowAsShown(
            rowOf(s, mirror),
            s.requireActiveCut.layers,
          ).timeline,
          4,
        )?.entry.ghost,
        isTrue,
        reason: 'PREMISE: the row shows the ghost of the hold at 4',
      );
      s.selectLayer(mirror);
      s.selectFrameIndex(0);
      s.updateFrameRangeSelectionDrag(
        layerId: mirror,
        anchorIndex: 0,
        headIndex: 4,
      );
      clipboardOf(s).copyFrameAtCurrentFrame();

      standOn(s, other, 0);
      clipboardOf(s).pasteIndependentFrameAtCurrentFrame();

      expect(blocksOf(s, other), {0: (null, 31), 2: (null, 32)});
      // The hold is its BLOCK's and rode it here, so what stands past the
      // block is this row's own ghost of it — not a piece of the copied one.
      expect(
        [
          for (final MapEntry(key: frame, value: exposure)
              in rowOf(s, other).timeline.entries)
            if (exposure.ghost) frame,
        ],
        [3],
      );
    });

    test('stood on, one comma of the drawing shown', () {
      final (:s, base: _, :mirror, :other) = baseMirrorAndAnEmptyRow();
      standOn(s, mirror, 2);
      clipboardOf(s).copyFrameAtCurrentFrame();

      standOn(s, other, 5);
      clipboardOf(s).pasteLinkedFrameAtCurrentFrame();

      expect(blocksOf(s, other), {5: ('Y', 32)});
      expect(rowOf(s, other).timeline[5]?.length, 1);
    });

    test('the row itself takes no paste, and its blocks are not its own to '
        'cut — stood on or swept, the cut is dark and pressed changes '
        'nothing', () {
      final (:s, :base, :mirror, other: _) = baseMirrorAndAnEmptyRow();
      copyTheRunOf(s, mirror);
      final swept = s.frameRangeSelection.value;
      expect(swept, isNotNull, reason: '⛔전제');

      expect(clipboardOf(s).canPasteIndependentFrameAtCurrentFrame, isFalse);
      expect(clipboardOf(s).canPasteLinkedFrameAtCurrentFrame, isFalse);
      expect(clipboardOf(s).canCutRunAtCurrentFrame, isFalse, reason: 'swept');

      final steps = s.historyManager.undoCount;
      clipboardOf(s).cutRunAtCurrentFrame();
      expect(s.frameRangeSelection.value, swept, reason: 'not let go');
      expect(s.historyManager.undoCount, steps);
      expect(blocksOf(s, base), {0: ('X', 10), 2: ('Y', 20)});

      s.clearFrameRangeSelection();
      standOn(s, mirror, 0);
      expect(clipboardOf(s).canCutRunAtCurrentFrame, isFalse, reason: 'stood');
      expect(clipboardOf(s).canCopyFrameAtCurrentFrame, isTrue);
    });
  });

  group('② a linked paste onto another row keeps the names', () {
    test('each named drawing is born there wearing its name, with the '
        'picture copied — one undo', () {
      final (:s, :base, mirror: _, :other) = baseMirrorAndAnEmptyRow();
      copyTheRunOf(s, base);

      standOn(s, other, 6);
      final steps = s.historyManager.undoCount;
      expect(clipboardOf(s).pasteLinkedFrameAtCurrentFrame(), isNull);

      expect(blocksOf(s, other), {6: ('X', 10), 8: ('Y', 20)});
      expect(
        rowOf(s, other).timeline[6]?.frameId,
        isNot(rowOf(s, base).timeline[0]?.frameId),
        reason: 'a drawing of THIS row\'s own — a drawing belongs to its row',
      );
      expect(blocksOf(s, base), {0: ('X', 10), 2: ('Y', 20)});
      expect(s.historyManager.undoCount, steps + 1);

      s.undo();
      expect(blocksOf(s, other), isEmpty);
      expect(rowOf(s, other).frames, isEmpty);
    });

    test('a name the row already holds: nothing is written and what it '
        'would join comes back — joined, the blocks show the row\'s OWN '
        'drawings and the copied pictures are not brought', () {
      final (:s, :base, mirror: _, :other) = baseMirrorAndAnEmptyRow();
      copyTheRunOf(s, base);
      standOn(s, other, 6);
      clipboardOf(s).pasteLinkedFrameAtCurrentFrame();
      final held = [
        rowOf(s, other).timeline[6]!.frameId!,
        rowOf(s, other).timeline[8]!.frameId!,
      ];
      // The row's own X, drawn over since: a different picture than the copy.
      paint(s, other, held.first, 99);

      standOn(s, other, 12);
      expect(clipboardOf(s).canPasteLinkedFrameAtCurrentFrame, isTrue);
      final steps = s.historyManager.undoCount;
      final joins = clipboardOf(s).pasteLinkedFrameAtCurrentFrame();

      expect(joins, hasLength(1));
      expect(joins!.single.layerId, other);
      expect(joins.single.held, held);
      expect(
        blocksOf(s, other).keys,
        [6, 8],
        reason: 'asked first — nothing written',
      );
      expect(s.historyManager.undoCount, steps);

      expect(
        clipboardOf(s).pasteLinkedFrameAtCurrentFrame(joinTakenNames: true),
        isNull,
      );
      expect(blocksOf(s, other), {
        6: ('X', 99),
        8: ('Y', 20),
        12: ('X', 99),
        14: ('Y', 20),
      });
      expect(rowOf(s, other).timeline[12]?.frameId, held.first);
      expect(rowOf(s, other).timeline[14]?.frameId, held.last);
      expect(rowOf(s, other).frames, hasLength(2), reason: 'nothing born');
      expect(s.historyManager.undoCount, steps + 1);
    });

    test('a drawing of no name has none to keep — it lands as one of the '
        'row\'s own, unnamed, beside the named ones', () {
      final (:s, :base, mirror: _, :other) = baseMirrorAndAnEmptyRow();
      standOn(s, base, 1);
      s.createDrawingAtCurrentFrame();
      paint(s, base, s.selectedFrame!.id, 15);
      copyTheRunOf(s, base);

      standOn(s, other, 0);
      expect(clipboardOf(s).pasteLinkedFrameAtCurrentFrame(), isNull);

      expect(blocksOf(s, other), {0: ('X', 10), 1: (null, 15), 2: ('Y', 20)});
    });

    test('on the row it was copied from it is the same drawings, as it '
        'was', () {
      final (:s, :base, mirror: _, other: _) = baseMirrorAndAnEmptyRow();
      copyTheRunOf(s, base);

      standOn(s, base, 6);
      expect(clipboardOf(s).pasteLinkedFrameAtCurrentFrame(), isNull);

      expect(
        rowOf(s, base).timeline[6]?.frameId,
        rowOf(s, base).timeline[0]?.frameId,
      );
      expect(rowOf(s, base).frames, hasLength(2));
    });
  });

  group('the button is lit where the name has something to keep', () {
    test('a copy of unnamed drawings pastes independent only on another '
        'row — a linked paste would be that paste under another button', () {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final from = s.activeLayer!.id;
      s.selectFrameIndex(0);
      s.createDrawingAtCurrentFrame();
      s.layerStack.addLayerOfKind(LayerKind.animation);
      final to = s.activeLayer!.id;
      standOn(s, from, 0);
      clipboardOf(s).copyFrameAtCurrentFrame();

      standOn(s, to, 0);
      expect(clipboardOf(s).canPasteLinkedFrameAtCurrentFrame, isFalse);
      expect(clipboardOf(s).canPasteIndependentFrameAtCurrentFrame, isTrue);

      standOn(s, from, 4);
      expect(
        clipboardOf(s).canPasteLinkedFrameAtCurrentFrame,
        isTrue,
        reason: 'on its own row the same drawing is the link',
      );
    });

    test('a direction row wears no names, so a named copy links nothing '
        'there', () {
      final (:s, :base, mirror: _, other: _) = baseMirrorAndAnEmptyRow();
      copyTheRunOf(s, base);
      s.layerStack.addLayerOfKind(LayerKind.instruction);
      final direction = s.activeLayer!.id;
      expect(rowOf(s, direction).kind, LayerKind.instruction, reason: '⛔전제');

      standOn(s, direction, 0);
      expect(clipboardOf(s).canPasteLinkedFrameAtCurrentFrame, isFalse);
      expect(clipboardOf(s).canPasteIndependentFrameAtCurrentFrame, isTrue);
    });

    test('…and swept under a band with a row that does, it is given '
        'drawings of no name', () {
      final (:s, :base, mirror: _, :other) = baseMirrorAndAnEmptyRow();
      copyTheRunOf(s, base);
      s.layerStack.addLayerOfKind(LayerKind.instruction);
      final direction = s.activeLayer!.id;
      standOn(s, other, 0);
      s.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: other,
        startIndex: 0,
        endIndexExclusive: 4,
        layerIds: [other, direction],
      );

      expect(clipboardOf(s).pasteLinkedFrameAtCurrentFrame(), isNull);

      expect(blocksOf(s, other), {0: ('X', 10), 2: ('Y', 20)});
      expect(blocksOf(s, direction), {0: (null, 10), 2: (null, 20)});
    });

    test('only the names the pasted run SHOWS are asked about', () {
      final (:s, :base, mirror: _, other: _) = baseMirrorAndAnEmptyRow();
      final row = rowOf(s, base);
      final x = row.timeline[0]!.frameId!;
      // A run showing X alone, off a board that carries Y as well.
      final joins = drawingsHeldUnderTheNamesOf(row, (
        clip: TimelineClipRow.untimed(row.timeline[0]!),
        cels: row.frames,
      ));
      expect(row.frames, hasLength(2), reason: '⛔전제: X and Y');
      expect(joins, {x: x});
    });

    test('a row that takes no new drawing takes no linked paste either — a '
        'reference row\'s picture comes from the library', () {
      final (:s, :base, mirror: _, :other) = baseMirrorAndAnEmptyRow();
      copyTheRunOf(s, base);
      s.repository.updateLayer(
        layerId: other,
        update: (layer) => layer.copyWith(
          mediaReference: MediaReference(assetPath: 'media/a.png'),
        ),
      );

      standOn(s, other, 0);
      expect(rowOf(s, other).mediaReference, isNotNull, reason: '⛔전제');
      expect(clipboardOf(s).canPasteLinkedFrameAtCurrentFrame, isFalse);
      expect(clipboardOf(s).canPasteIndependentFrameAtCurrentFrame, isFalse);
    });

    test('an SE row\'s copy links nowhere (F-115)', () {
      final (:s, base: _, mirror: _, :other) = baseMirrorAndAnEmptyRow();
      s.layerStack.addLayerOfKind(LayerKind.se);
      final se = s.activeLayer!.id;
      standOn(s, se, 0);
      s.seEntries.createSeEntryAtCurrentFrame(
        name: 'X',
        seName: 'speaker',
        lengthFrames: 2,
      );
      standOn(s, se, 0);
      expect(s.activeLayer?.kind, LayerKind.se, reason: '⛔전제');
      expect(
        clipboardOf(s).canCopyFrameAtCurrentFrame,
        isTrue,
        reason: '⛔전제: an entry named X stands there',
      );
      clipboardOf(s).copyFrameAtCurrentFrame();

      standOn(s, other, 0);
      expect(clipboardOf(s).canPasteLinkedFrameAtCurrentFrame, isFalse);
      expect(clipboardOf(s).canPasteIndependentFrameAtCurrentFrame, isTrue);
    });
  });
}
