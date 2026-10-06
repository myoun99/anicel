import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/frame_clipboard.dart';

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
/// ⚠️A row HOLDING its picture still takes no paste (the pins of that are
/// `image_layer_session_test.dart`'s), and what a BAND does with a picture
/// row is not decided here — it passes them over as it did.
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
    for (final (frame, shade) in [(0, 10), (2, 20)]) {
      s.selectFrameIndex(frame);
      s.createDrawingAtCurrentFrame();
      paint(s, cels, rowOf(s, cels).timeline[frame]!.frameId!, shade);
    }
    s.layerStack.addLayerOfKind(LayerKind.image);
    final picture = s.activeLayer!.id;
    s.selectFrameIndex(0);
    final held = shown(s, picture)!;
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
      [false, false],
      reason: 'holding its picture again, the row takes no second',
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
    s.clearAllSelections();
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
}
