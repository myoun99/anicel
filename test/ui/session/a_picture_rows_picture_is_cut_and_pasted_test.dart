import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/frame_clipboard.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

/// 🚨image-row-cut-paste (유저 2026-10-04): a picture row's picture leaves
/// and comes back through the clipboard, and a row standing empty takes a
/// picture from it — 「첫장만」 of a clip that holds several.
///
/// ↩️Both pastes and the cut were dark on every image row, by kind: 「an
/// IMAGE row holds ONE cel by definition」, and what is cut has to be able
/// to come back. F-98 gave the row an empty state (유저 2026-09-12 · 10-04:
/// 「이미지 레이어도 프레임이 없는 상태는 존재함」), and the doors that MAKE a
/// cel had asked it since (`rowTakesNewCels`) — the paste kept its own
/// spelling of that rule, one clause behind.
///
/// 🗣️F-593 (유저 2026-11-15): 「이미지 레이어에도 다른 블록의 그림
/// 복사한거 붙여넣기 가능하게. 어태치 싱크레이어에 붙여넣기 작동시키듯이
/// 그림교체방식으로. 규칙 최대한 어태치싱크때 규칙 따라서 통일」 — a row
/// HOLDING its picture takes a paste as a synced attach row does: the
/// clip's first hangs in its block, its cel, name and block kept, with a
/// selection or none, on its hold as on its block. A LINK lands a block,
/// so only where a band lifts the one it holds — 「그림이 있어도
/// 갈아끼운다」 (image-row-cut-paste-Q1). ↩️A paste needed that band too,
/// and laid the clip's first as a new cel.
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
      s.pixelEditing.coordinator!.restoreSurfaceSnapshot(
        s.brushFrameKeyForCut(s.requireActiveCut, row, cel),
        ink(s, shade),
      );

  int? shadeOf(EditorSessionManager s, LayerId row, FrameId cel) => s
      .pixelEditing
      .coordinator!
      .currentSurfaceOf(s.brushFrameKeyForCut(s.requireActiveCut, row, cel))
      .tiles
      .values
      .firstOrNull
      ?.pixels
      .first;

  /// The canvas a pixel verb works on — a paste that hangs a picture is one
  /// (F-545 · F-593: with none, nothing is lit).
  void standUpTheCanvas(EditorSessionManager s) {
    final cut = s.requireActiveCut;
    final first = cut.layers.firstWhere((row) => row.frames.isNotEmpty);
    s.pixelEditing.coordinator = BrushFrameEditingCoordinator(
      initialFrameKey: s.brushFrameKeyForCut(
        cut,
        first.id,
        first.frames.first.id,
      ),
      frameStore: s.renderCaches.brushFrameStore,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: cut.canvasSize,
        tileSize: 256,
      ),
      historyPolicy: const BrushHistoryPolicy(),
    );
  }

  /// The picture the row's lane shows.
  FrameId? shown(EditorSessionManager s, LayerId row) =>
      authoredBlockOf(rowOf(s, row))?.frameId;

  /// A cel row holding two drawings — X at 0 (shade 10), Y at 2 (shade 20)
  /// — and an image row holding its picture (shade 77), stood on at frame 0.
  ({EditorSessionManager s, LayerId cels, LayerId picture, FrameId held})
  celsAndAPictureRow() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cels = s.activeLayer!.id;
    for (final frame in [0, 2]) {
      s.selectFrameIndex(frame);
      s.createDrawingAtCurrentFrame();
    }
    s.layerStack.addLayerOfKind(LayerKind.image);
    final picture = s.activeLayer!.id;
    s.selectFrameIndex(0);
    final held = shown(s, picture)!;
    standUpTheCanvas(s);
    for (final (frame, shade) in [(0, 10), (2, 20)]) {
      paint(s, cels, rowOf(s, cels).timeline[frame]!.frameId!, shade);
    }
    paint(s, picture, held, 77);
    return (s: s, cels: cels, picture: picture, held: held);
  }

  /// The row holds ONE picture, laid as its held block (D22).
  void expectItsOneHeldPicture(EditorSessionManager s, LayerId row) {
    final layer = rowOf(s, row);
    expect(layer.frames, hasLength(1));
    expect(
      layer.timeline.values.where((entry) => !entry.ghost),
      hasLength(1),
    );
    expect(layer.timeline[0]?.length, 1);
    expect(layer.timeline[0]?.endEdge.mode, TimelineRunEdgeMode.hold);
  }

  test('잘라내기 takes the picture out — the row stands empty — and a linked '
      'paste, from any frame, brings the SAME cel back', () {
    final (:s, cels: _, :picture, :held) = celsAndAPictureRow();
    expect(clipboardOf(s).canCutRunAtCurrentFrame, isTrue);
    final steps = s.historyManager.undoCount;

    clipboardOf(s).cutRunAtCurrentFrame();

    expect(rowOf(s, picture).timeline, isEmpty);
    expect(rowOf(s, picture).frames, isEmpty);
    expect(s.historyManager.undoCount, steps + 1);

    s.selectFrameIndex(4);
    expect(s.canPasteLinkedFrameAtCurrentFrame, isTrue);
    s.pasteLinkedFrameAtCurrentFrame();

    expect(shown(s, picture), held, reason: 'the same cel, so the same ink');
    expectItsOneHeldPicture(s, picture);
    expect(shadeOf(s, picture, held), 77);
    expect(
      [
        s.canPasteLinkedFrameAtCurrentFrame,
        s.canPasteIndependentFrameAtCurrentFrame,
      ],
      [false, true],
      reason:
          'holding its picture again, the row takes no second block — and '
          'a paste hangs a picture in the one it holds (F-593)',
    );

    s.undo();
    expect(rowOf(s, picture).timeline, isEmpty, reason: 'one undo, the paste');
    // The cut was made standing on frame 0, and an undo pressed anywhere
    // else walks there first (I-41) — so stand there.
    s.selectFrameIndex(0);
    s.undo();
    expect(shown(s, picture), held, reason: 'and one, the cut');
  });

  // 🚨F-107 (유저 2026-09-12: 「불가능한 버튼 비활성화 … 그 외도 있나 확인」)
  // — measured before this pin: lit on the hold, the cut left the picture
  // where it was, copied it to the board and added an undo step.
  test('on the hold past its block the cut is dark, as the delete is — the '
      'copy is what is lit there — and pressed anyway it changes nothing', () {
    final (:s, cels: _, :picture, :held) = celsAndAPictureRow();
    s.selectFrameIndex(5);
    final steps = s.historyManager.undoCount;
    final board = clipboardOf(s).copiedFrameStatusText;

    expect(s.cells.canDeleteCellAtCurrentFrame, isFalse, reason: '⛔전제');
    expect(clipboardOf(s).canCutRunAtCurrentFrame, isFalse);
    expect(s.canCopyFrameAtCurrentFrame, isTrue);

    clipboardOf(s).cutRunAtCurrentFrame();

    expect(shown(s, picture), held);
    expect(s.historyManager.undoCount, steps);
    expect(clipboardOf(s).copiedFrameStatusText, board);
  });

  test('…and an independent paste gives it a cel of its own, with the '
      'picture', () {
    final (:s, cels: _, :picture, :held) = celsAndAPictureRow();
    clipboardOf(s).cutRunAtCurrentFrame();
    expect(s.canPasteIndependentFrameAtCurrentFrame, isTrue);

    s.pasteIndependentFrameAtCurrentFrame();

    final made = shown(s, picture);
    expect(made, isNotNull);
    expect(made, isNot(held));
    expectItsOneHeldPicture(s, picture);
    expect(shadeOf(s, picture, made!), 77);
  });

  test('an empty picture row takes the FIRST picture of a clip, and that '
      'one alone — 「첫장만」', () {
    final (:s, :cels, :picture, held: _) = celsAndAPictureRow();
    s.deleteSelectionSubject();
    expect(rowOf(s, picture).timeline, isEmpty, reason: '⛔전제: empty');
    // The whole run of the cel row: X, a gap, Y.
    s.selectLayer(cels);
    s.selectFrameIndex(0);
    s.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: cels,
      startIndex: 0,
      endIndexExclusive: 3,
    );
    s.copyFrameAtCurrentFrame();
    s.clearTimelineSelections();
    s.selectLayer(picture);
    s.selectFrameIndex(3);
    expect(s.canPasteIndependentFrameAtCurrentFrame, isTrue);

    s.pasteIndependentFrameAtCurrentFrame();

    expectItsOneHeldPicture(s, picture);
    expect(
      shadeOf(s, picture, shown(s, picture)!),
      10,
      reason: 'X, the first — Y stayed on the board',
    );
    expect(rowOf(s, cels).frames, hasLength(2), reason: 'the source is whole');
  });

  // 🗣️image-row-cut-paste-Q1 (유저 2026-10-07): 「밴드도 이미지 행을 다룬다 —
  // 그림이 있어도 갈아끼운다」. ↩️A band passed every picture row over: a
  // copy did not take its picture, a cut did not lift it, a paste did not
  // put one down.
  group('a BAND over a picture row', () {
    /// The band over [rows] from [start], stood on the first of them.
    void sweep(
      EditorSessionManager s,
      List<LayerId> rows, {
      int start = 0,
      int end = 3,
    }) {
      s.selectLayer(rows.first);
      s.selectFrameIndex(start);
      s.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: rows.first,
        startIndex: start,
        endIndexExclusive: end,
        layerIds: rows,
      );
    }

    test('잘라내기 lifts its picture with the cels — the row stands empty — '
        'and a linked paste of the band brings the SAME picture back', () {
      final (:s, :cels, :picture, :held) = celsAndAPictureRow();
      sweep(s, [cels, picture]);

      clipboardOf(s).cutRunAtCurrentFrame();

      expect(rowOf(s, picture).timeline, isEmpty);
      sweep(s, [cels, picture]);
      expect(s.canPasteLinkedFrameAtCurrentFrame, isTrue);
      s.pasteLinkedFrameAtCurrentFrame();

      expect(shown(s, picture), held, reason: 'the same cel, so the same ink');
      expectItsOneHeldPicture(s, picture);
      expect(shadeOf(s, picture, held), 77);
    });

    test('a paste over a picture row that HOLDS its picture hangs the '
        "clip's first in its block — the same cel — and one undo gives the "
        'old picture back', () {
      final (:s, :cels, :picture, :held) = celsAndAPictureRow();
      sweep(s, [cels]);
      s.copyFrameAtCurrentFrame();
      sweep(s, [cels, picture]);
      expect(s.canPasteIndependentFrameAtCurrentFrame, isTrue);

      s.pasteIndependentFrameAtCurrentFrame();

      expect(shown(s, picture), held, reason: 'F-593: no cel is laid there');
      expectItsOneHeldPicture(s, picture);
      expect(shadeOf(s, picture, held), 10, reason: 'X, the first');
      s.undo();
      expect(shown(s, picture), held);
      expect(shadeOf(s, picture, held), 77);
    });

    test('stood on the picture row, a band over its block lights both '
        'pastes — a link keeps the name — and one over the hold past it '
        'lifts nothing there, so a link has no room: a paste hangs the '
        'picture in the block the hold shows', () {
      final (:s, :cels, :picture, held: _) = celsAndAPictureRow();
      s.selectLayer(cels);
      s.selectFrameIndex(0);
      expect(s.frameVerbs.renameSelectedFrame('X'), isNull, reason: '⛔전제');
      s.copyFrameAtCurrentFrame();

      sweep(s, [picture], start: 2, end: 4);
      expect(
        [
          s.canPasteIndependentFrameAtCurrentFrame,
          s.canPasteLinkedFrameAtCurrentFrame,
        ],
        [true, false],
        reason:
            'the hold is not the block, as it is not to the delete — but a '
            'cursor on it stands on the picture it shows (F-140 · F-593)',
      );
      sweep(s, [picture], end: 2);
      expect(
        [
          s.canPasteIndependentFrameAtCurrentFrame,
          s.canPasteLinkedFrameAtCurrentFrame,
        ],
        [true, true],
      );

      s.pasteLinkedFrameAtCurrentFrame();

      expectItsOneHeldPicture(s, picture);
      final now = rowOf(s, picture).frameById(shown(s, picture)!);
      expect(now?.name, 'X');
      expect(shadeOf(s, picture, now!.id), 10);
    });

    test('the board pairs by PLACE in the band: a picture row hangs ITS row '
        'of the board in the block its hold shows, and mints nothing', () {
      final (:s, :cels, :picture, :held) = celsAndAPictureRow();
      s.layerStack.addLayerOfKind(LayerKind.animation);
      final other = s.activeLayer!.id;
      s.selectFrameIndex(0);
      s.createDrawingAtCurrentFrame();
      paint(s, other, rowOf(s, other).timeline[0]!.frameId!, 30);
      sweep(s, [cels, picture, other], end: 1);
      s.copyFrameAtCurrentFrame();
      paint(s, picture, held, 99);

      sweep(s, [cels, picture, other], start: 4, end: 5);
      s.pasteIndependentFrameAtCurrentFrame();

      expect(shown(s, picture), held, reason: 'its block, the same cel');
      expect(rowOf(s, picture).frames, hasLength(1), reason: 'none minted');
      expect(
        shadeOf(s, picture, held),
        77,
        reason: "its own row of the board — not the cel row's X, nor 30",
      );
      final landed = rowOf(s, other).timeline[4]?.frameId;
      expect(landed, isNotNull);
      expect(shadeOf(s, other, landed!), 30, reason: "its own row's drawing");
    });

    test('a link the band brings to a picture row lands nothing there, so '
        'it asks nothing of the names that row holds', () {
      final (:s, :cels, :picture, held: _) = celsAndAPictureRow();
      s.layerStack.addLayerOfKind(LayerKind.animation);
      final other = s.activeLayer!.id;
      s.selectFrameIndex(0);
      s.createDrawingAtCurrentFrame();
      for (final (row, name) in [(other, 'N'), (cels, 'X'), (picture, 'X')]) {
        s.selectLayer(row);
        s.selectFrameIndex(0);
        expect(s.frameVerbs.renameSelectedFrame(name), isNull, reason: '전제');
      }
      sweep(s, [other, cels], end: 1);
      s.copyFrameAtCurrentFrame();

      // The board's rows meet the band's in order: N on the cel row, which
      // holds no N, and X on the picture row, which holds an X — and has no
      // room for the block a link brings.
      sweep(s, [cels, picture], start: 4, end: 5);
      expect(s.canPasteLinkedFrameAtCurrentFrame, isTrue, reason: '전제');

      expect(
        clipboardOf(s).pasteLinkedFrameAtCurrentFrame(),
        isNull,
        reason: 'pasted — no join to ask about',
      );
      final linked = rowOf(s, cels).timeline[4]!.frameId!;
      expect(rowOf(s, cels).frameById(linked)?.name, 'N');
    });
  });

  // 🗣️F-593 (유저 2026-11-15): 「이미지 레이어에도 다른 블록의 그림 복사한거
  // 붙여넣기 가능하게. 어태치 싱크레이어에 붙여넣기 작동시키듯이
  // 그림교체방식으로」 — the synced row's law (`a_synced_row_takes_a_pasted_
  // picture_test.dart`), taken whole. ↩️With nothing selected a row holding
  // its picture took no paste at all.
  group('a picture row HOLDING its picture, nothing selected', () {
    /// X (shade 10) of the cel row on the board, stood on the picture row at
    /// [frame].
    void copyXOnto(
      EditorSessionManager s, {
      required LayerId cels,
      required LayerId picture,
      required int frame,
    }) {
      s.selectLayer(cels);
      s.selectFrameIndex(0);
      s.copyFrameAtCurrentFrame();
      s.selectLayer(picture);
      s.selectFrameIndex(frame);
    }

    test("a paste hangs the copy's picture in its block — its cel, its "
        'name and its block stay — in one undo step', () {
      final (:s, :cels, :picture, :held) = celsAndAPictureRow();
      expect(s.frameVerbs.renameSelectedFrame('BG'), isNull, reason: '⛔전제');
      copyXOnto(s, cels: cels, picture: picture, frame: 0);
      expect(s.canPasteIndependentFrameAtCurrentFrame, isTrue);
      final before = rowOf(s, picture);
      final steps = s.historyManager.undoCount;

      s.pasteIndependentFrameAtCurrentFrame();

      final now = rowOf(s, picture);
      expect(
        [for (final cel in now.frames) (cel.id, cel.name)],
        [(held, 'BG')],
      );
      expect(now.timeline, equals(before.timeline));
      expect(shadeOf(s, picture, held), 10);
      expect(s.historyManager.undoCount, steps + 1);
      s.undo();
      expect(shadeOf(s, picture, held), 77);
    });

    test('on its hold as on its block: a cursor there stands on the picture '
        'it shows (F-140, as on a synced row) — and a link, which lands a '
        'block, has no room', () {
      final (:s, :cels, :picture, :held) = celsAndAPictureRow();
      copyXOnto(s, cels: cels, picture: picture, frame: 5);
      expect(
        [
          s.canPasteIndependentFrameAtCurrentFrame,
          s.canPasteLinkedFrameAtCurrentFrame,
        ],
        [true, false],
      );

      s.pasteIndependentFrameAtCurrentFrame();

      expect(shown(s, picture), held);
      expectItsOneHeldPicture(s, picture);
      expect(shadeOf(s, picture, held), 10);
    });

    test('the drawings a paste lays down count the one it hangs there — '
        'what the wait window counts a paste by', () {
      final (:s, :cels, :picture, held: _) = celsAndAPictureRow();
      copyXOnto(s, cels: cels, picture: picture, frame: 0);

      expect(s.clipboard.drawingsPastedAt(s.clipboard.timelinePlace), [
        (picture, rowOf(s, cels).timeline[0]!.frameId!),
      ]);
    });

    test('a paste hangs a picture only where it lays no block: on a row it '
        'lays one, the new cel takes the picture as it is carried, once', () {
      final (:s, :cels, :picture, held: _) = celsAndAPictureRow();
      copyXOnto(s, cels: cels, picture: picture, frame: 0);
      s.pasteIndependentFrameAtCurrentFrame();
      expect(clipboardOf(s).debugPicturesHung, 1, reason: '전제: hung there');

      s.selectLayer(cels);
      s.selectFrameIndex(6);
      s.pasteIndependentFrameAtCurrentFrame();

      final laid = rowOf(s, cels).timeline[6]?.frameId;
      expect(laid, isNotNull, reason: '전제: a block laid');
      expect(shadeOf(s, cels, laid!), 10);
      expect(clipboardOf(s).debugPicturesHung, 1);
    });

    test('a copy of two pictures hangs the FIRST — 「첫장만」', () {
      final (:s, :cels, :picture, :held) = celsAndAPictureRow();
      s.selectLayer(cels);
      s.selectFrameIndex(0);
      s.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: cels,
        startIndex: 0,
        endIndexExclusive: 3,
      );
      s.copyFrameAtCurrentFrame();
      s.clearTimelineSelections();
      s.selectLayer(picture);
      s.selectFrameIndex(2);

      s.pasteIndependentFrameAtCurrentFrame();

      expect(shown(s, picture), held);
      expectItsOneHeldPicture(s, picture);
      expect(shadeOf(s, picture, held), 10, reason: 'X — Y stays on the board');
    });

    test("a band's keys land over the frames they span — none of the row's "
        'own keys past them moves, as none of its cells does', () {
      final (:s, :cels, :picture, held: _) = celsAndAPictureRow();
      for (final (row, frame) in [(cels, 0), (picture, 5)]) {
        s.laneVerbs.toggleLaneKeyAt(
          row,
          'position',
          frame,
          frameIsGlobal: false,
          description: 'key',
        );
      }
      s.standOnRow(LayerRowAddress(cels), frameIndex: 0);
      s.updateFrameRangeSelectionDrag(
        layerId: cels,
        anchorIndex: 0,
        headIndex: 1,
        spanRows: [LayerRowAddress(cels), LaneRowAddress(cels, 'position')],
      );
      final pill = TimelineToolbarPanelContext(s)..copyFrame();
      s.standOnRow(LayerRowAddress(picture), frameIndex: 0);
      expect(s.frameRangeSelection.value, isNull, reason: '⛔전제: no band');

      pill.pasteIndependentFrame();

      expect(
        rowOf(s, picture).transformTrack.position.keys.keys.toSet(),
        {0, 5},
      );
    });
  });
}
