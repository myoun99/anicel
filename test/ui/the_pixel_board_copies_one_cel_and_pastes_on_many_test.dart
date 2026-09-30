import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/pixel_clipboard_verb.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// 🗣️I-55 (유저 2026-10-01): 픽셀 복사 · 픽셀 위 붙여넣기 · 픽셀 아래
/// 붙여넣기 in the 색 편집 list — 「픽셀복사는 화면 전체(현재 셀의 그림
/// 존재하는것들 …), 다만 선택도구로 선택한게 있으면 선택된곳만 복사 …
/// 프레임 복사랑 같은 클립보드 기억하는게아니야 … 붙여넣기는 위나 아래로
/// 나뉨 … 붙여넣기로 선택도구 있으면 선택부분에만, 없으면 기억된 전체 …
/// 여러 프레임 선택해서 동시 붙여넣기 가능. 다만 복사는 여러프레임
/// 선택해도 무시. 현재 그림만 복사임」.
void main() {
  // The one drawable row's timeline: three single cels, a cel HELD for two
  // frames (3–4), an EMPTY frame (5) and one more cel (6).
  const cels = ['c0', 'c1', 'c2', 'c3', 'c4'];
  const starts = {0: 'c0', 1: 'c1', 2: 'c2', 3: 'c3', 6: 'c4'};

  Project fixture() {
    final base = createDefaultProject();
    final track = base.tracks.first;
    final cut = track.cuts.first;
    final row = cut.layers.firstWhere(layerAcceptsBrushInput);
    return base.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            cut.copyWith(
              layers: [
                for (final layer in cut.layers)
                  if (layer.id == row.id)
                    layer.copyWith(
                      frames: [
                        for (final id in cels)
                          Frame(
                            id: FrameId(id),
                            duration: 1,
                            strokes: const [],
                          ),
                      ],
                      timeline: {
                        for (final MapEntry(key: at, value: id)
                            in starts.entries)
                          at: TimelineExposure.drawing(
                            FrameId(id),
                            length: id == 'c3' ? 2 : 1,
                          ),
                      },
                    )
                  else
                    layer,
              ],
            ),
          ],
        ),
      ],
    );
  }

  Layer row(EditorSessionManager session) =>
      session.layers.firstWhere((l) => l.frames.length == cels.length);

  Future<EditorSessionManager> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: fixture())),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.selectLayer(row(session).id);
    session.selectFrameIndex(0);
    await tester.pump();
    return session;
  }

  BrushFrameKey keyOf(EditorSessionManager session, String cel) =>
      session.brushFrameKeyForCut(
        session.requireActiveCut,
        row(session).id,
        FrameId(cel),
      );

  /// Paints [cel] with one colour inside [left, right) × [top, bottom),
  /// through the COORDINATOR — the surface the verbs read and write.
  void paint(
    EditorSessionManager session,
    String cel, {
    required int left,
    required int top,
    required int right,
    required int bottom,
    required List<int> rgba,
  }) {
    final key = keyOf(session, cel);
    final coordinator = session.pixelEditing.coordinator!;
    final base = coordinator.currentSurfaceOf(key);
    final size = base.tileSize;
    final pixels = Uint8List(size * size * 4);
    for (var y = top; y < bottom; y += 1) {
      for (var x = left; x < right; x += 1) {
        pixels.setRange((y * size + x) * 4, (y * size + x) * 4 + 4, rgba);
      }
    }
    coordinator.restoreSurfaceSnapshot(
      key,
      base.putTiles([
        (
          coord: TileCoord(x: 0, y: 0),
          tile: BitmapTile(size: size, pixels: pixels),
        ),
      ]),
    );
  }

  /// [cel]'s RGBA at (x, y) — zero where it holds no tile.
  List<int> pixel(EditorSessionManager session, String cel, int x, int y) {
    final tile = session.pixelEditing.coordinator!
        .currentSurfaceOf(keyOf(session, cel))
        .tileAt(TileCoord(x: 0, y: 0));
    if (tile == null) {
      return const [0, 0, 0, 0];
    }
    final at = tile.byteOffsetForPixel(x: x, y: y);
    return tile.pixels.sublist(at, at + 4);
  }

  const red = [255, 0, 0, 255];
  const blue = [0, 0, 255, 255];
  const clear = [0, 0, 0, 0];

  void selectAcross(EditorSessionManager session, int start, int end) {
    session.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: row(session).id,
      startIndex: start,
      endIndexExclusive: end,
    );
  }

  void marquee(EditorSessionManager session, CanvasSelectionRegion? region) {
    session.cells.pixelVerbCanvas = () => (
      region: region,
      argb: 0xFF000000,
      mask: SelectionMaskOptions.none,
    );
  }

  testWidgets('copy reads the cel you stand on — a frame range does not '
      'widen it (「복사는 여러프레임 선택해도 무시」)', (tester) async {
    final session = await pump(tester);
    paint(session, 'c0', left: 10, top: 10, right: 20, bottom: 20, rgba: red);
    paint(session, 'c1', left: 40, top: 40, right: 50, bottom: 50, rgba: blue);
    selectAcross(session, 0, 3);
    session.selectFrameIndex(1);
    await tester.pump();

    session.cells.runPixelClipboardVerb(PixelClipboardVerb.copy);
    final piece = session.appClipboard.pixels.piece!;

    expect(
      (piece.originLeft, piece.originTop),
      (40, 40),
      reason: 'the STANDING cel (c1) and nothing of c0, though the range '
          'covers both',
    );
    expect(piece.image.rgba.sublist(0, 4), blue);
  });

  testWidgets('paste above lays the board on every cel of the range, at the '
      'coordinates it came from, as ONE undo', (tester) async {
    final session = await pump(tester);
    paint(session, 'c0', left: 10, top: 10, right: 20, bottom: 20, rgba: red);
    session.cells.runPixelClipboardVerb(PixelClipboardVerb.copy);

    selectAcross(session, 1, 3);
    await tester.pump();
    session.cells.runPixelClipboardVerb(PixelClipboardVerb.pasteAbove);
    await tester.pump();

    expect(pixel(session, 'c1', 15, 15), red, reason: 'a blank cel takes it');
    expect(pixel(session, 'c2', 15, 15), red);
    expect(pixel(session, 'c1', 25, 25), clear, reason: 'only the piece');

    session.historyManager.undo();
    await tester.pump();
    expect(pixel(session, 'c1', 15, 15), clear, reason: 'one undo, all cels');
    expect(pixel(session, 'c2', 15, 15), clear);
  });

  testWidgets('above and below are composite ORDER — below keeps what the '
      'cel already has on top (「위/아래는 합성순서」)', (tester) async {
    final session = await pump(tester);
    paint(session, 'c0', left: 10, top: 10, right: 20, bottom: 20, rgba: red);
    session.cells.runPixelClipboardVerb(PixelClipboardVerb.copy);
    // c1 holds blue over the piece's left half.
    paint(session, 'c1', left: 10, top: 10, right: 15, bottom: 20, rgba: blue);

    session.selectFrameIndex(1);
    await tester.pump();
    session.cells.runPixelClipboardVerb(PixelClipboardVerb.pasteBelow);
    await tester.pump();
    expect(pixel(session, 'c1', 12, 12), blue, reason: 'below: blue stays');
    expect(pixel(session, 'c1', 17, 12), red, reason: 'and red fills in');

    session.historyManager.undo();
    await tester.pump();
    session.cells.runPixelClipboardVerb(PixelClipboardVerb.pasteAbove);
    await tester.pump();
    expect(pixel(session, 'c1', 12, 12), red, reason: 'above: red covers');
  });

  testWidgets('a selection confines BOTH halves — the copy reads inside it '
      'and the paste lands inside it', (tester) async {
    final session = await pump(tester);
    paint(session, 'c0', left: 10, top: 10, right: 30, bottom: 30, rgba: red);

    marquee(
      session,
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 10, top: 10, right: 20, bottom: 30),
      ),
    );
    session.cells.runPixelClipboardVerb(PixelClipboardVerb.copy);
    final piece = session.appClipboard.pixels.piece!;
    expect(piece.originLeft, 10);
    expect(
      piece.image.width,
      lessThan(20),
      reason: 'the left half only, not the whole 20×20 drawing',
    );

    // The paste, through a marquee that starts INSIDE the piece on both
    // axes — so a window read off the wrong corner would show.
    marquee(
      session,
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 14, top: 12, right: 20, bottom: 30),
      ),
    );
    session.selectFrameIndex(1);
    await tester.pump();
    session.cells.runPixelClipboardVerb(PixelClipboardVerb.pasteAbove);
    await tester.pump();
    expect(pixel(session, 'c1', 16, 15), red);
    expect(pixel(session, 'c1', 12, 15), clear, reason: 'left of the marquee');
    expect(pixel(session, 'c1', 16, 11), clear, reason: 'above the marquee');
  });

  testWidgets('both halves follow the marquee\'s FEATHER — the pixel verbs\' '
      'reading of a selection (유저 09-09 「선택의 aa 따르게」)', (tester) async {
    final session = await pump(tester);
    paint(session, 'c0', left: 10, top: 10, right: 40, bottom: 40, rgba: red);
    final box = CanvasSelectionRegion.shape(
      CanvasSelectionShape.rect(left: 10, top: 10, right: 30, bottom: 30),
    );
    void through(SelectionMaskOptions mask) =>
        session.cells.pixelVerbCanvas = () => (
          region: box,
          argb: 0xFF000000,
          mask: mask,
        );

    // COPY: the pixel just inside the marquee's right edge.
    through(const SelectionMaskOptions(featherPx: 6));
    session.cells.runPixelClipboardVerb(PixelClipboardVerb.copy);
    final soft = session.appClipboard.pixels.piece!;
    final edge = (15 * soft.image.width + (29 - soft.originLeft)) * 4 + 3;
    expect(
      soft.image.rgba[edge],
      lessThan(255),
      reason: 'a feathered copy takes the edge in part',
    );

    // PASTE: a hard board, laid through a feathered marquee.
    through(SelectionMaskOptions.none);
    session.cells.runPixelClipboardVerb(PixelClipboardVerb.copy);
    through(const SelectionMaskOptions(featherPx: 6));
    session.selectFrameIndex(1);
    await tester.pump();
    session.cells.runPixelClipboardVerb(PixelClipboardVerb.pasteAbove);
    await tester.pump();
    expect(pixel(session, 'c1', 20, 20)[3], 255, reason: 'deep inside');
    expect(
      pixel(session, 'c1', 29, 20)[3],
      allOf(greaterThan(0), lessThan(255)),
      reason: 'the edge lands in part',
    );
  });

  testWidgets('one landing per PHYSICAL cel, and no cel is made on an empty '
      'frame (08-12 C5 · C6)', (tester) async {
    final session = await pump(tester);
    // Half-transparent, so a second landing on the held cel would show.
    paint(
      session,
      'c0',
      left: 10,
      top: 10,
      right: 20,
      bottom: 20,
      rgba: const [255, 0, 0, 128],
    );
    session.cells.runPixelClipboardVerb(PixelClipboardVerb.copy);
    final exposuresBefore = Map.of(row(session).timeline);

    // 3–4 is ONE cel held twice; 5 is empty.
    selectAcross(session, 3, 6);
    await tester.pump();
    session.cells.runPixelClipboardVerb(PixelClipboardVerb.pasteAbove);
    await tester.pump();

    expect(
      pixel(session, 'c3', 15, 15)[3],
      128,
      reason: 'twice would have laid 128 over 128 — 「같은게 두개인곳에 '
          '붙여넣으면 한번만 발리도록」',
    );
    expect(
      row(session).timeline.keys.toSet(),
      exposuresBefore.keys.toSet(),
      reason: 'the empty frame stays empty — a pixel verb makes no cel',
    );
  });

  testWidgets('the board is its own: a frame copy neither reads nor clears '
      'it, and a paste does not use it up', (tester) async {
    final session = await pump(tester);
    paint(session, 'c0', left: 10, top: 10, right: 20, bottom: 20, rgba: red);
    session.cells.runPixelClipboardVerb(PixelClipboardVerb.copy);
    final held = session.appClipboard.pixels.piece;

    session.clipboard.copyFrameAtCurrentFrame();
    session.selectFrameIndex(1);
    await tester.pump();
    session.cells.runPixelClipboardVerb(PixelClipboardVerb.pasteAbove);
    await tester.pump();

    expect(
      session.appClipboard.pixels.piece,
      same(held),
      reason: '「프레임 복사한다고해서 픽셀복사 내역이 사라지지않아」 · '
          '「붙여넣는다고 들고있는거 삭제시키지않음」',
    );
  });

  testWidgets('each row dims on its own gate, and the 색 편집 head opens when '
      'any row can run', (tester) async {
    final session = await pump(tester);
    final cells = session.cells;
    // Standing on a blank cel with nothing on the board.
    session.selectFrameIndex(1);
    await tester.pump();
    expect(cells.canRunPixelClipboardVerb(PixelClipboardVerb.copy), isFalse);
    expect(
      cells.canRunPixelClipboardVerb(PixelClipboardVerb.pasteAbove),
      isFalse,
    );
    expect(cells.canOpenColourEdit, isFalse);

    paint(session, 'c0', left: 10, top: 10, right: 20, bottom: 20, rgba: red);
    session.selectFrameIndex(0);
    await tester.pump();
    cells.runPixelClipboardVerb(PixelClipboardVerb.copy);
    session.selectFrameIndex(1);
    await tester.pump();

    expect(cells.canRunPixelVerb, isFalse, reason: 'c1 holds no drawing');
    expect(
      cells.canRunPixelClipboardVerb(PixelClipboardVerb.pasteBelow),
      isTrue,
      reason: 'a blank cel is exactly where a paste goes',
    );
    expect(
      cells.canOpenColourEdit,
      isTrue,
      reason: 'the head opens when any row can run',
    );
  });

  testWidgets('the 색 편집 list shows the three rows after the four',
      (tester) async {
    final session = await pump(tester);
    paint(session, 'c0', left: 10, top: 10, right: 20, bottom: 20, rgba: red);
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('shared-colour-edit-button')).first,
    );
    await tester.pumpAndSettle();
    for (final key in [
      'shared-keep-colour-button',
      'shared-copy-pixels-button',
      'shared-paste-pixels-above-button',
      'shared-paste-pixels-below-button',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
    }
    expect(
      tester.getTopLeft(
        find.byKey(const ValueKey<String>('shared-copy-pixels-button')),
      ).dy,
      greaterThan(
        tester.getTopLeft(
          find.byKey(const ValueKey<String>('shared-keep-colour-button')),
        ).dy,
      ),
    );
    expect(session.appClipboard.pixels.piece, isNull);
  });
}
