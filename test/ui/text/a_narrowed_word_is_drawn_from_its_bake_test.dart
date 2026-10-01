import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/text/word_bake.dart';
import 'package:anicel/src/ui/text/word_condensation.dart';

import '../../helpers/dart_sources.dart';

/// F-224 — a narrowed word is drawn from its bake.
///
/// 유저 2026-10-01: 「8%정도에서 대사 텍스트가 많으면 안보이는데, 약간 2치화된
/// 폰트느낌? 그래서 좀 부드러운 필터 건다거나 아무튼 더 잘 보이게」. Narrowed
/// through `canvas.scale` a glyph came out as specks on the engine; the
/// tiles' bake — rasterised big, averaged down on the CPU — came out smooth,
/// so a screen's narrowed word is drawn from that bake too.
///
/// The bake reads its pixels back off the engine, which answers in real
/// time: real time is let pass between the frames ([_pumpUntilABakeLands]).

/// A word in a red ink, laid out.
TextPainter _word(String text, {required double fontSize, double? maxWidth}) =>
    TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, color: const Color(0xFFD00000)),
      ),
      textDirection: TextDirection.ltr,
      maxLines: maxWidth == null ? null : 1,
      ellipsis: maxWidth == null ? null : '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);

class _WordPainter extends CustomPainter with RepaintOnWordBakes {
  _WordPainter(this.word, this.fit, this.painted);

  final TextPainter word;
  final WordFit fit;
  final ValueNotifier<int> painted;

  @override
  void paint(Canvas canvas, Size size) {
    painted.value += 1;
    paintFittedText(canvas, word, Offset.zero, fit);
  }

  @override
  bool shouldRepaint(_WordPainter oldDelegate) => false;
}

Future<void> _pumpUntilABakeLands(WidgetTester tester) async {
  final before = BakedWords.instance.landed.value;
  for (var i = 0; i < 400; i += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
    if (BakedWords.instance.landed.value != before) {
      return;
    }
  }
  fail('fixture: no bake landed');
}

/// The colour of the most inked pixel [paint] leaves on a [size] canvas.
Future<Color> _inkOf(void Function(Canvas) paint, Size size) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.ceil(), size.height.ceil());
  picture.dispose();
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  ))!;
  image.dispose();
  var most = 0;
  for (var i = 4; i < bytes.lengthInBytes; i += 4) {
    if (bytes.getUint8(i + 3) > bytes.getUint8(most + 3)) {
      most = i;
    }
  }
  return Color.fromARGB(
    bytes.getUint8(most + 3),
    bytes.getUint8(most),
    bytes.getUint8(most + 1),
    bytes.getUint8(most + 2),
  );
}

String _squash(String s) => s.replaceAll(RegExp(r'\s+'), '');

void main() {
  testWidgets('a word narrowed under the legible size is drawn from its '
      'bake once it lands, and only such a word', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    const fit = (x: 0.25, y: 1.0);
    // 24px narrowed to half is 12px tall in the narrow — what the
    // rasteriser draws well. Asked FIRST, so a bake of it would land first.
    final legible = _word('ことば', fontSize: 24);
    void paintLegible(Canvas canvas) =>
        paintFittedText(canvas, legible, Offset.zero, (x: 0.5, y: 1.0));
    expect(paintLegible, paints..paragraph());

    final word = _word('ことば', fontSize: 12);
    final painted = ValueNotifier(0);
    await tester.pumpWidget(
      Center(
        child: CustomPaint(
          size: const Size(40, 20),
          painter: _WordPainter(word, fit, painted),
        ),
      ),
    );
    final strip = find.byType(CustomPaint);
    expect(
      strip,
      paints..paragraph(),
      reason: 'before its bake lands it is painted as it always was',
    );
    expect(strip, paintsExactlyCountTimes(#drawImageRect, 0));

    final before = painted.value;
    await _pumpUntilABakeLands(tester);
    expect(
      painted.value,
      before + 1,
      reason: 'its painter paints again when the bake lands',
    );
    expect(strip, paints..drawImageRect());
    expect(strip, paintsExactlyCountTimes(#drawParagraph, 0));
    expect(
      (Canvas canvas) => paintFittedText(canvas, word, const Offset(3, 4), fit),
      paints..drawImageRect(
        destination: Rect.fromLTWH(
          3 - 1,
          4 - 1,
          word.width * fit.x + 2,
          word.height * fit.y + 2,
        ),
      ),
      reason:
          'the bake lands on the narrowed word\'s own box, its one-pixel '
          'margin around it — nothing moves when it lands',
    );

    expect(
      (Canvas canvas) =>
          paintFittedText(canvas, word, Offset.zero, (x: 0.5, y: 1.0)),
      paints..drawImageRect(),
      reason:
          'at a new narrowing it is drawn from the bake it has while its '
          'own is in flight — a zoom never falls back to the specks',
    );
    expect(
      (Canvas canvas) => paintFittedText(
        canvas,
        _word('ことば', fontSize: 12, maxWidth: 14),
        Offset.zero,
        fit,
      ),
      paints..paragraph(),
      reason: 'the word laid short, ellipsis and all, is not the word whole',
    );
    expect(
      paintLegible,
      paintsExactlyCountTimes(#drawImageRect, 0),
      reason: 'a word the rasteriser draws well is painted as it always was',
    );

    await tester.runAsync(() async {
      final ink = await _inkOf(
        (canvas) => paintFittedText(canvas, word, Offset.zero, fit),
        const Size(40, 20),
      );
      expect(ink.a, greaterThan(0.5), reason: 'fixture: the word is inked');
      // The bake itself is white ink: drawn bare, the word is white.
      const reason = 'the bake is drawn in the word\'s own ink';
      expect(
        ink.r,
        moreOrLessEquals(0xD0 / 255, epsilon: 0.05),
        reason: reason,
      );
      expect(ink.g, lessThan(0.05), reason: reason);
      expect(ink.b, lessThan(0.05), reason: reason);
    });
  });

  testWidgets('a word bakes one narrowing at a time — a zoom passes the '
      'rest on the bake it has', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final word = _word('せりふ', fontSize: 12);
    void Function(Canvas) paintAt(double x) =>
        (canvas) => paintFittedText(canvas, word, Offset.zero, (x: x, y: 1.0));
    // Two narrowings asked in one frame, the way a zoom asks them.
    expect(paintAt(0.25), paints..paragraph());
    expect(paintAt(0.5), paints..paragraph());
    await _pumpUntilABakeLands(tester);
    // The first narrowing's bake: a pixel a pixel, with its margin.
    final first = Rect.fromLTWH(
      0,
      0,
      (word.width * 0.25).ceil() + 2.0,
      word.height.ceil() + 2.0,
    );
    expect(
      paintAt(0.5),
      paints..drawImageRect(source: first),
      reason: 'the second narrowing waited for the first to land',
    );
  });

  group('down a column', () {
    // Upright, lying down, two digits standing as one, and a small kana
    // leaning off its centre.
    const text = 'リー12っ';
    const style = TextStyle(fontSize: 10, color: Color(0xFF000000));

    /// Where each glyph of the column lands, and narrowed how — the set
    /// glyph's box through the canvas's transform at the moment it is set.
    List<({String glyph, WordFit fit, Rect box})> setGlyphs(
      void Function(Canvas canvas, WordSetter setWord) paint,
    ) {
      final canvas = Canvas(ui.PictureRecorder());
      final set = <({String glyph, WordFit fit, Rect box})>[];
      paint(canvas, (canvas, painter, origin, fit) {
        set.add((
          glyph: (painter.text! as TextSpan).text!,
          fit: fit,
          box: MatrixUtils.transformRect(
            Matrix4.fromFloat64List(canvas.getTransform()),
            origin & Size(painter.width * fit.x, painter.height * fit.y),
          ),
        ));
      });
      return set;
    }

    double column(
      Canvas canvas,
      WordSetter setWord, {
      WordFit narrowing = wordFitsAsItIs,
    }) => paintVerticalText(
      canvas,
      text,
      style: style,
      centerX: 10,
      top: 0,
      mainExtent: 60,
      naturalCellExtent: 13,
      narrowing: narrowing,
      setWord: setWord,
    );

    test('each glyph is set at its share of the narrowing — a turned one '
        'across its own axes', () {
      final own = setGlyphs(column);
      final set = setGlyphs(
        (canvas, setWord) =>
            column(canvas, setWord, narrowing: (x: 0.5, y: 0.25)),
      );
      expect(set.map((g) => g.glyph), ['リ', 'ー', '12', 'っ']);
      for (var i = 0; i < set.length; i += 1) {
        final (:x, :y) = own[i].fit;
        final turned = set[i].glyph == 'ー';
        expect(
          set[i].fit,
          turned ? (x: x * 0.25, y: y * 0.5) : (x: x * 0.5, y: y * 0.25),
          reason: '${set[i].glyph}: its own fit, narrowed',
        );
      }
    });

    test('a narrowed column sets each glyph where the column scaled after '
        'drew it', () {
      const narrowing = (x: 0.5, y: 0.25);
      final scaled = setGlyphs((canvas, setWord) {
        canvas.scale(narrowing.x, narrowing.y);
        column(canvas, setWord);
      });
      final narrowed = setGlyphs(
        (canvas, setWord) => column(canvas, setWord, narrowing: narrowing),
      );
      expect(narrowed, hasLength(4), reason: 'fixture: four cells');
      for (var i = 0; i < narrowed.length; i += 1) {
        expect(
          narrowed[i].box,
          rectMoreOrLessEquals(scaled[i].box, epsilon: 1e-9),
          reason: '${narrowed[i].glyph} lands where it was drawn',
        );
      }
    });
  });

  test('paper alone sets its words scaled — every screen sets them from '
      'their bakes', () {
    // ⛔Paper cannot draw a word from its bake (`paintScaledText`); a
    // screen that took the paper's setter would speckle again (F-224).
    final scaled = [
      for (final file in dartFilesUnder('lib'))
        if (_squash(file.readAsStringSync()).contains(
          'setWord:paintScaledText',
        ))
          libPath(file),
    ];
    expect(scaled, isNotEmpty, reason: 'premise: the sheet sets its words');
    expect(
      scaled.where((path) => !path.startsWith('lib/src/ui/timesheet/')),
      isEmpty,
    );
  });

  test('every painter that sets a narrowed word paints again when its '
      'bake lands', () {
    // A CENSUS: the files that reach a narrowed word — set it themselves,
    // or hand it to the strips' placed words (`TimelineGlyphPlacement`,
    // `paintWindow`) or to the glyph on its ground. A file that starts to
    // reach one fails here until its painter repaints on the bakes and it
    // joins the list.
    const census = {
      'lib/src/ui/text/word_condensation.dart': null,
      'lib/src/ui/text/vertical_writing_text.dart': '_VerticalWritingPainter',
      'lib/src/ui/timeline/timeline_glyph_cache.dart': null,
      'lib/src/ui/canvas/flip_hud_overlay.dart': 'FlipHudPainter',
      'lib/src/ui/storyboard_cut_blocks_painter.dart':
          'StoryboardCutBlocksPainter',
      'lib/src/ui/timeline/collapsed_row_overlay.dart':
          '_CollapsedStripPainter',
      'lib/src/ui/timeline/dialogue_fit_text.dart': '_DialogueFitPainter',
      'lib/src/ui/timeline/timeline_block_word.dart': null,
      'lib/src/ui/timeline/timeline_frame_ruler_painter.dart':
          'TimelineFrameRulerPainter',
      'lib/src/ui/timeline/timeline_row_cells_painter.dart':
          'TimelineRowCellsPainter',
      'lib/src/ui/timeline/timeline_row_run_labels_painter.dart':
          'TimelineRowRunLabelsPainter',
      'lib/src/ui/timeline/timeline_ruler_playhead_writing.dart':
          'TimelineRulerPlayheadWritingPainter',
      'lib/src/ui/timeline/xsheet_timeline_grid.dart': 'XSheetFrameRailPainter',
    };
    final reaching = RegExp(
      'paintFittedText|paintWordCentredIn|paintTimelineGlyphOnGround|'
      r'TimelineGlyphPlacement|paintWindow\(',
    );
    final found = {
      for (final file in dartFilesUnder('lib'))
        if (reaching.hasMatch(file.readAsStringSync())) libPath(file),
    };
    expect(found, census.keys.toSet());
    for (final MapEntry(key: path, value: painter) in census.entries) {
      if (painter == null) {
        continue;
      }
      final declared = RegExp(
        'class${painter}extendsCustomPainterwith[^{]*RepaintOnWordBakes',
      );
      expect(
        _squash(File(path).readAsStringSync()),
        matches(declared),
        reason: '$painter repaints when a bake lands',
      );
    }
    expect(
      _squash(
        File('lib/src/ui/timeline/timeline_block_word.dart').readAsStringSync(),
      ),
      contains('BakedWords.instance.landed.addListener(markNeedsPaint)'),
      reason: 'the built word repaints when a bake lands',
    );
  });
}
