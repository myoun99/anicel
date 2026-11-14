import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/a_fill_on_a_session.dart';
import '../../helpers/a_fill_on_the_engine.dart';
import '../../helpers/fill_pieces.dart';

/// 🚨THE FILL READS WHAT IS DRAWN, NOT THE PAPER (board F-416 — 유저
/// 2026-10-20: 「캔버스 용지색이 흰색이고, 레이어에 그린것도 흰색일때 … 캔버스
/// 전체를 칠해버리는거같음. 그림부분만 칠해야하는데」 · 「캔버스밖 채우기 체크하더라도
/// 그 경우 칠해지도록 … 페이스트보드쪽도 칠해지도록」).
///
/// White ink is the colour of the paper a new project has: a fill that read
/// the paper took the whole canvas on it, and with the fill past the canvas
/// on, the white shape running onto the pasteboard flooded to the wall and
/// was refused as open. Every case is asked as a canvas asks it
/// ([fillPressedOn]), on a project whose paper is white: what leaves the
/// paper out is the canvas's own door (`fillPictureOver`).
void main() {
  opensTheEnginesScreens();
  const canvasSize = CanvasSize(width: 8, height: 8);
  const ink = LayerId('ink');

  /// [inked] pixels opaque, grey [shade] (white by default) — off the
  /// canvas too.
  BitmapSurface inkOf(Set<(int, int)> inked, {int shade = 255}) =>
      celOfPixels(canvasSize, {
        for (final at in inked) at: [shade, shade, shade, 255],
      });

  Set<(int, int)> block(int left, int top, int right, int bottom) => {
    for (var y = top; y <= bottom; y += 1)
      for (var x = left; x <= right; x += 1) (x, y),
  };

  List<BrushDab> fill(
    BitmapSurface surface, {
    required CanvasPoint at,
    bool pastTheCanvas = false,
    bool pasteboardInUse = true,
    void Function()? onOpenRegion,
  }) {
    final session = sessionOfRows(
      [drawingRow('ink')],
      canvasSize: canvasSize,
      cels: {(ink, theCel): surface},
      standOn: ink,
      pasteboardInUse: pasteboardInUse,
    );
    expect(
      session.projectSettings.projectBackground,
      ProjectBackground.defaultBackground,
      reason: 'fixture premise: the paper is the white a project is born on',
    );
    return fillPressedOn(
          session,
          at,
          options: FloodFillOptions(
            expandPx: 0,
            antiAlias: false,
            extendBeyondCanvas: pastTheCanvas,
          ),
          onOpenRegion: onOpenRegion,
        )?.dabsIn(0xFF3366CC) ??
        const [];
  }

  test('a fill on white ink takes the ink, not the canvas around it', () {
    final dabs = fill(inkOf(block(2, 2, 5, 5)), at: CanvasPoint(x: 3, y: 3));

    expect(piecesBox(dabs), (left: 2, top: 2, width: 4, height: 4));
    expect(
      piecesAlphaAt(dabs, 0, 0),
      0,
      reason: '↩️the canvas around the ink read as the same white',
    );
  });

  test('a fill beside white ink takes the empty canvas, and leaves the '
      'ink', () {
    final dabs = fill(inkOf(block(2, 2, 5, 5)), at: CanvasPoint(x: 0, y: 0));

    expect(piecesAlphaAt(dabs, 0, 0), 255);
    expect(piecesAlphaAt(dabs, 7, 7), 255);
    expect(
      piecesAlphaAt(dabs, 3, 3),
      0,
      reason: 'the white ink is drawn: it walls the fill',
    );
  });

  test('🚨with the fill past the canvas on, a white shape running onto the '
      'pasteboard fills whole — its pasteboard part too', () {
    var refused = false;
    final dabs = fill(
      inkOf(block(-3, 2, 3, 5)),
      at: CanvasPoint(x: 1, y: 3),
      pastTheCanvas: true,
      onOpenRegion: () => refused = true,
    );

    expect(
      refused,
      isFalse,
      reason: '↩️the white shape flooded into the paper to the wall',
    );
    expect(piecesBox(dabs), (left: -3, top: 2, width: 7, height: 4));
    expect(piecesAlphaAt(dabs, -3, 2), 255, reason: 'on the pasteboard');
  });

  test('without it, the same shape fills inside the canvas only', () {
    final dabs = fill(inkOf(block(-3, 2, 3, 5)), at: CanvasPoint(x: 1, y: 3));

    expect(piecesBox(dabs), (left: 0, top: 2, width: 4, height: 4));
  });

  // I-109: the apron a fill past the canvas floods into reaches as far as
  // the PROJECT's pasteboard does — the canvas's door reads it of the
  // project (`fillRangeOn`).
  test('on a project that uses no pasteboard the fill past the canvas is '
      'the canvas\'s: the empty canvas fills to the paper\'s edge, where '
      'a project with one refuses it as open', () {
    var refused = false;
    final dabs = fill(
      inkOf(block(2, 2, 5, 5)),
      at: CanvasPoint(x: 0, y: 0),
      pastTheCanvas: true,
      pasteboardInUse: false,
      onOpenRegion: () => refused = true,
    );
    expect(refused, isFalse, reason: 'an apron the project has not');
    expect(piecesBox(dabs), (left: 0, top: 0, width: 8, height: 8));

    expect(
      fill(
        inkOf(block(2, 2, 5, 5)),
        at: CanvasPoint(x: 0, y: 0),
        pastTheCanvas: true,
        onOpenRegion: () => refused = true,
      ),
      isEmpty,
      reason: '⛔premise: with a pasteboard the same press floods to its wall',
    );
    expect(refused, isTrue);
  });

  test('black line art walls a fill: nothing drawn and black ink differ '
      'by their coverage alone', () {
    final outline = block(2, 2, 5, 5).difference(block(3, 3, 4, 4));
    final dabs = fill(
      inkOf(outline, shade: 0),
      at: CanvasPoint(x: 3, y: 3),
    );

    expect(
      piecesBox(dabs),
      (left: 3, top: 3, width: 2, height: 2),
      reason: '↩️an absent paper read as black: the fill ran through it',
    );
  });
}
