import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_number_letters.dart';
import 'package:anicel/src/native/engine_frame_tools.dart';
import 'package:anicel/src/ui/text/cel_number_paint.dart';
import 'package:anicel/src/ui/text/text_cel_render.dart'
    show textCelLayoutsKept;

import '../../helpers/a_canvas_standing_on_a_frame.dart';

/// 🔬card paint-walk-redoes-the-same-work-each-step (2026-10-27): a stroke's
/// every step laid each numbered row's letters out twice — the buffer's
/// bounds and the letters themselves — though only their text, their colour
/// and the fonts there are decide the layout. Where the letters stand and
/// how large is the paint's own transform.
///
/// The oracle is the paragraph a paint DRAWS: letters laid out once are the
/// same paragraph at every paint.
class _Paragraphs implements ui.Canvas {
  final drawn = <ui.Paragraph>[];

  @override
  void drawParagraph(ui.Paragraph paragraph, ui.Offset offset) =>
      drawn.add(paragraph);

  @override
  int getSaveCount() => 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

List<ui.Paragraph> _drawnBy(void Function(ui.Canvas canvas) paint) {
  final canvas = _Paragraphs();
  paint(canvas);
  return canvas.drawn;
}

CelNumberLetters _letters(
  String text, {
  int color = 0xFF000000,
  CanvasPoint? center,
  CanvasPoint? scale,
}) => CelNumberLetters(
  text: text,
  color: color,
  center: center ?? CanvasPoint(x: 40, y: 30),
  scale: scale ?? CanvasPoint(x: 1, y: 1),
);

void main() {
  opensTheEnginesScreens();

  testWidgets('the same letters anywhere, at any size, are the one '
      'layout', (tester) async {
    final here = celNumberLayoutOf(_letters('A1'));

    expect(
      celNumberLayoutOf(
        _letters(
          'A1',
          center: CanvasPoint(x: 400, y: 300),
          scale: CanvasPoint(x: 2, y: 3),
        ),
      ),
      same(here),
      reason: '🚨the letters were laid out again where they stand elsewhere',
    );
    expect(
      celNumberBox(_letters('A1', center: CanvasPoint(x: 400, y: 300))),
      isNot(celNumberBox(_letters('A1'))),
      reason: '⛔전제: where they stand is still theirs',
    );
  });

  testWidgets('another text, another colour, or a font registered since is '
      'another layout', (tester) async {
    final here = celNumberLayoutOf(_letters('B2'));

    expect(
      celNumberLayoutOf(_letters('B3')),
      isNot(same(here)),
      reason: '🚨another text answered with these letters',
    );
    expect(
      celNumberLayoutOf(_letters('B2', color: 0xFFFF0000)),
      isNot(same(here)),
      reason: '🚨another colour answered with these letters',
    );

    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.system.name,
      SystemChannels.system.codec.encodeMessage(<String, Object?>{
        'type': 'fontsChange',
      }),
      (_) {},
    );

    expect(
      celNumberLayoutOf(_letters('B2')),
      isNot(same(here)),
      reason: '🚨letters laid out before the fonts changed outlived them',
    );
  });

  // A cel number's plate is the engine's letters' (cel-number-on-the-
  // engine-letters) — the same letters the same plate, another letter
  // another: the_engine_lays_a_tree_as_the_walk_paints_it_test. ↩️The app
  // kept one of its own too (`keptLetterPlate`), held to its bytes here,
  // till the Flutter chain went (the-flutter-fx-chain-is-a-second-chain).
  final paper = BitmapSurface(
    canvasSize: const CanvasSize(width: 200, height: 120),
    tileSize: defaultCelTileSize,
  );
  BitmapSurface plateOf(CelNumberLetters letters) =>
      appEngineFrameToolsOpen!.letters.celNumberPlate(letters, paper);

  testWidgets('a font registered since makes the plate again', (tester) async {
    final before = plateOf(_letters('D5'));
    expect(before.tiles, isNotEmpty, reason: 'LIVENESS: the letters were set');

    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.system.name,
      SystemChannels.system.codec.encodeMessage(<String, Object?>{
        'type': 'fontsChange',
      }),
      (_) {},
    );

    expect(
      plateOf(_letters('D5')),
      isNot(same(before)),
      reason: '🚨a plate rastered before the fonts changed outlived them',
    );
  });

  testWidgets('letters scaled to nothing make a plate of no tile', (
    tester,
  ) async {
    expect(
      plateOf(_letters('F7', scale: CanvasPoint(x: 0, y: 1))).tiles,
      isEmpty,
      reason: '🚨letters that cover no pixel were rastered',
    );
  });

  testWidgets('letters pushed out by as many others as are kept are let go '
      'of', (tester) async {
    final drawn = _drawnBy(
      (canvas) => celNumberLayoutOf(_letters('pushed out')).paint(canvas),
    );
    expect(drawn, isNotEmpty, reason: 'LIVENESS: the letters painted');
    expect(drawn.first.debugDisposed, isFalse, reason: 'held');

    // Whatever another test left behind is older, and goes first.
    for (var i = 0; i < textCelLayoutsKept; i += 1) {
      celNumberLayoutOf(_letters('other $i'));
    }

    expect(
      drawn.first.debugDisposed,
      isTrue,
      reason: '🚨a layout let go of kept its painters',
    );
  });
}
