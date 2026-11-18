import 'dart:typed_data';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/native/engine_faces.dart';
import 'package:anicel/src/native/engine_word.dart';
import 'package:anicel/src/ui/text/word_bake.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppTypography;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import '../../helpers/a_word_that_waits.dart';
import '../../helpers/app_faces.dart';
import '../../helpers/coverage_ink.dart';

/// 🗣️A FRAME GRID'S TILE WORD IS THE GPU ENGINE'S RASTER
/// (a-grid-row-paints-its-cells-on-a-canvas-beside-its-tiles-Q3 · Q4, 유저
/// 2026-11-15: 「(다) 글자도 엔진이 그 자리에서 굽는다」 · 「그대로 간다 — 격자
/// 칸 글자는 엔진이 굽는다」): [bakeWordOnEngine] makes a word's bake within
/// the call, where Flutter's raster ([bakeWordCoverage]) is read back and a
/// paint waited a frame or more for every word it had never seen.
///
/// The engine rasters; the box, the times over and the average are the
/// bake's own, one for both rasters — so what is held here is that the
/// engine is handed the word as that bake takes its raster: un-narrowed, a
/// whole number of times over, one final pixel of margin round it, each
/// letter where Flutter's layout put it.

TextPainter _laid(String text, TextStyle style) => TextPainter(
  text: TextSpan(text: text, style: style),
  textDirection: TextDirection.ltr,
)..layout();

/// The Japanese UI's face, and the Chinese UI's — which goes down the
/// bundled faces in another order.
final TextStyle _ja = TextStyle(
  fontFamily: AppTypography.familyFor(AppLanguage.ja),
  fontFamilyFallback: AppTypography.fallbackFor(AppLanguage.ja),
  color: const Color(0xFFFFFFFF),
);
final TextStyle _zh = TextStyle(
  fontFamily: AppTypography.familyFor(AppLanguage.zhHans),
  fontFamilyFallback: AppTypography.fallbackFor(AppLanguage.zhHans),
  color: const Color(0xFFFFFFFF),
);

/// [painter]'s word as the engine rasters it when asked directly: [scale]
/// pixels a px and [margin] pixels in, over [width] × [height] — in the
/// faces its style goes down, or in [order] of them.
Uint8List _rastered(
  TextPainter painter, {
  required double scale,
  required double margin,
  required int width,
  required int height,
  List<int>? order,
}) {
  final word = EngineWord.of(painter, pixelsAPx: scale);
  final set = GpuWord();
  try {
    word.handTo(set);
    return set.raster(
      EngineFaces.inOrder(order ?? word.families),
      [scale, 0, 0, scale, margin, margin],
      width: width,
      height: height,
    )!;
  } finally {
    set.free();
  }
}

BakedWordCoverage _baked(
  TextPainter painter,
  double dpr, {
  ({double x, double y}) fit = (x: 1, y: 1),
}) => bakeWordOnEngine(
  painter,
  fit: fit,
  dpr: dpr,
  fontSize: painter.text!.style!.fontSize,
)!;

CoverageInk _inkOf(BakedWordCoverage baked) =>
    coverageInkOf(baked.alpha, baked.width, baked.height);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadTheAppFaces);
  readTheEnginesFacesFirst();

  // 유저 2026-08-28: 「줌인하면 텍스트는 선명하게 보고싶다」 — the average of
  // one pixel is that pixel.
  test('a word the rasteriser draws well is the engine\'s raster of it byte '
      'for byte, in its box and a pixel round it', () {
    for (final size in [12.0, 13.0, 20.0]) {
      for (final dpr in [1.0, 1.5, 2.0]) {
        final painter = _laid('3aカ셀', _ja.copyWith(fontSize: size));
        final baked = _baked(painter, dpr);
        final width = (painter.width * dpr).ceil() + 2;
        final height = (painter.height * dpr).ceil() + 2;
        final why = '$size px at $dpr';
        expect((baked.width, baked.height), (width, height), reason: why);
        expect(
          (baked.logicalWidth, baked.logicalHeight),
          (painter.width, painter.height),
          reason: why,
        );
        expect(
          baked.alpha,
          _rastered(
            painter,
            scale: dpr,
            margin: 1,
            width: width,
            height: height,
          ),
          reason: why,
        );
        expect(baked.alpha.any((alpha) => alpha > 0), isTrue, reason: why);
      }
    }
  });

  // 🚨TINY TEXT IS RASTERISED BIG AND SHRUNK ([bakeWordCoverage]).
  test('a small word is rastered a whole number of times over and averaged '
      'into the box it would have had', () {
    for (final (size, times) in [(9.0, 2), (6.0, 2), (4.0, 3)]) {
      for (final dpr in [1.0, 1.5]) {
        final painter = _laid('12', _ja.copyWith(fontSize: size));
        final baked = _baked(painter, dpr);
        final width = (painter.width * dpr).ceil() + 2;
        final height = (painter.height * dpr).ceil() + 2;
        final why = '$size px at $dpr';
        expect(wordBakeScale(size), times, reason: 'fixture: $why');
        expect((baked.width, baked.height), (width, height), reason: why);
        final big = _rastered(
          painter,
          scale: dpr * times,
          margin: times.toDouble(),
          width: width * times,
          height: height * times,
        );
        expect(
          baked.alpha,
          boxFilterA8(big, width * times, height * times, width, height),
          reason: why,
        );
        expect(baked.alpha.any((alpha) => alpha > 0), isTrue, reason: why);
      }
    }
  });

  // F-297 (유저 2026-10-05): 「3a만 이상하게 중앙에서 위에존재하고」 — the
  // raster is never asked for a narrowed word, whoever rasters it.
  test('a word narrowed along its line stands on the rows its un-narrowed '
      'bake does', () {
    for (final size in [9.0, 12.0]) {
      for (final dpr in [1.0, 1.5, 2.0]) {
        final painter = _laid('3a', _ja.copyWith(fontSize: size));
        final whole = _inkOf(_baked(painter, dpr));
        for (final fx in [0.85, 0.7, 0.5]) {
          final narrow = _inkOf(_baked(painter, dpr, fit: (x: fx, y: 1)));
          final why = '$size px ×$fx at $dpr';
          expect(
            narrow.box,
            (
              width: (painter.width * fx * dpr).ceil() + 2,
              height: whole.box.height,
            ),
            reason: why,
          );
          expect(narrow.rows, whole.rows, reason: '$why: 「세로길이」');
          expect(narrow.cy, closeTo(whole.cy, 0.01), reason: why);
          expect(
            narrow.cx - 1,
            closeTo((whole.cx - 1) * fx, 0.1),
            reason: '$why: along, narrower',
          );
          expect(
            narrow.sum / (whole.sum * fx),
            closeTo(1, 0.02),
            reason: '$why: as much ink as that',
          );
        }
      }
    }
  });

  // 🔬What the two rasters differed by on 11-09 is at [bakeWordCoverage]'s
  // head (the engine draws the outline as it is, Flutter hints it); this
  // holds only that the engine set the SAME word in the same place — a
  // letter a cell off, a baseline flipped or a ratio left out is pixels
  // away, not a fraction of one.
  test('the engine sets each letter where Flutter laid it — its bake stands '
      'where Flutter\'s raster of the word does', () async {
    for (final size in [12.0, 20.0]) {
      for (final dpr in [1.0, 2.0]) {
        for (final text in ['3a', 'カット12', '셀A']) {
          final painter = _laid(text, _ja.copyWith(fontSize: size));
          final engine = _inkOf(_baked(painter, dpr));
          final flutter = (await bakeWordCoverage(
            painter,
            fit: (x: 1, y: 1),
            dpr: dpr,
            fontSize: size,
          ))!;
          final theirs = _inkOf(flutter);
          final why = '$text at $size px, $dpr';
          expect(engine.box, theirs.box, reason: why);
          expect(engine.cx, closeTo(theirs.cx, 1.0 * dpr), reason: why);
          expect(engine.cy, closeTo(theirs.cy, 1.6 * dpr), reason: why);
          expect(
            engine.sum / theirs.sum,
            inInclusiveRange(0.6, 1.6),
            reason: why,
          );
        }
      }
    }
  });

  test('a word goes down its own style\'s order of the bundled faces', () {
    // 「日」 is in BIZ UDPGothic and in Noto Sans SC, drawn two ways: the
    // Chinese UI's style begins with the second.
    final painter = _laid('日', _zh.copyWith(fontSize: 20));
    final baked = _baked(painter, 1);
    Uint8List inOrder(List<int> order) => _rastered(
      painter,
      scale: 1,
      margin: 1,
      width: baked.width,
      height: baked.height,
      order: order,
    );
    expect(
      EngineWord.of(painter, pixelsAPx: 1).families,
      [2, 0, 1],
      reason: 'fixture',
    );
    expect(baked.alpha, inOrder([2, 0, 1]));
    expect(baked.alpha, isNot(inOrder([0, 1, 2])), reason: 'LIVENESS');
  });

  test('a word of no size, or of no ink, is no bake or its box of nothing',
      () {
    expect(
      bakeWordOnEngine(
        _laid('', _ja.copyWith(fontSize: 12)),
        fit: (x: 1, y: 1),
        dpr: 1,
        fontSize: 12,
      ),
      isNull,
    );
    final space = _baked(_laid(' ', _ja.copyWith(fontSize: 12)), 1);
    expect(space.alpha, everyElement(0));
    expect(space.alpha, isNotEmpty);
  });

  // ⏳…-Q5: till the person says what such a word is to be, it is
  // Flutter's to raster, as every word of a tile was.
  test('a word that is not the engine\'s to set is refused, not set as '
      'empty boxes', () {
    Object? refusalOf(String text, TextStyle style) {
      try {
        bakeWordOnEngine(
          _laid(text, style.copyWith(fontSize: 12)),
          fit: (x: 1, y: 1),
          dpr: 1,
          fontSize: 12,
        );
        return null;
      } on UnsupportedError catch (refusal) {
        return refusal;
      }
    }

    expect(refusalOf('3a', _ja), isNull, reason: 'LIVENESS');
    expect(refusalOf('3$aLetterNoBundledFaceHas', _ja), isUnsupportedError);
    expect(refusalOf(aLetterNoBundledFaceHas, _ja), isUnsupportedError);
    expect(
      refusalOf('3a', _ja.copyWith(decoration: TextDecoration.underline)),
      isUnsupportedError,
    );
    expect(
      refusalOf('3a', const TextStyle(fontFamily: 'Somebody Else\'s Face')),
      isUnsupportedError,
    );
  });

  test('a word past the longest side the engine rasters over is no bake',
      () {
    // Some 30,000 px of layout: past 65,536 pixels at three a px.
    final painter = _laid('W' * 700, _ja.copyWith(fontSize: 60));
    expect(painter.width * 3, greaterThan(65536), reason: 'fixture');
    expect(painter.width, lessThan(65536), reason: 'fixture');
    BakedWordCoverage? at(double dpr) =>
        bakeWordOnEngine(painter, fit: (x: 1, y: 1), dpr: dpr, fontSize: 60);
    expect(at(3), isNull);
    expect(at(1), isNotNull, reason: 'LIVENESS: the same word, inside it');
  });
}
