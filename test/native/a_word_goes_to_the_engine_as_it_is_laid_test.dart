import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/native/engine_faces.dart';
import 'package:anicel/src/native/engine_word.dart';
import 'package:anicel/src/ui/theme/app_theme.dart'
    show AppTypography, buildAppTheme;
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineBlockNameFontSize, timelineBlockWordStyle;

import '../helpers/app_faces.dart';

/// A word goes to the GPU engine for its raster as Flutter would paint it
/// (`engine_word.dart`): each grapheme cluster at its box's left, on the
/// baseline Flutter paints its line on, in runs of one size, weight and
/// slant, down the faces its style names — where its letters stand is
/// Flutter's, and which glyphs they take and how they raster the engine's
/// (`kernels/letters/words/tests.rs`).

/// [painter]'s word as a raster [pixelsAPx] pixels a px takes it.
EngineWord _word(TextPainter painter, {double pixelsAPx = 1}) =>
    EngineWord.of(painter, pixelsAPx: pixelsAPx);

TextPainter _laid(
  InlineSpan text, {
  TextScaler scaler = TextScaler.noScaling,
  double? maxWidth,
}) => TextPainter(
  text: text,
  textDirection: TextDirection.ltr,
  textScaler: scaler,
  maxLines: maxWidth == null ? null : 1,
  ellipsis: maxWidth == null ? null : '…',
)..layout(maxWidth: maxWidth ?? double.infinity);

/// The Japanese UI's face.
final TextStyle _ja = TextStyle(
  fontFamily: AppTypography.familyFor(AppLanguage.ja),
  fontFamilyFallback: AppTypography.fallbackFor(AppLanguage.ja),
);

/// The Chinese UI's.
final TextStyle _zh = TextStyle(
  fontFamily: AppTypography.familyFor(AppLanguage.zhHans),
  fontFamilyFallback: AppTypography.fallbackFor(AppLanguage.zhHans),
);

final List<String> _bundled = [
  for (final face in AppTypography.canvasLetterFaces) face.family,
];

String _textOf(EngineWordRun run) => [
  for (final cluster in run.clusters) cluster.text,
].join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadTheAppFaces);

  test('each cluster goes where the layout put it along the line — its '
      'box\'s left, in 64ths of a px', () {
    final painter = _laid(
      TextSpan(text: 'カ3셀', style: _ja.copyWith(fontSize: 12)),
    );
    final lefts = [
      for (final at in [0, 1, 2])
        painter
            .getBoxesForSelection(
              TextSelection(baseOffset: at, extentOffset: at + 1),
            )
            .first
            .left,
    ];
    final run = _word(painter).runs.single;
    expect((run.size, run.weight, run.italic), (12 * 64, 400, false));
    expect(
      [for (final cluster in run.clusters) cluster.text],
      ['カ', '3', '셀'],
    );
    expect([for (final cluster in run.clusters) cluster.x], [
      for (final left in lefts) (left * 64).round(),
    ]);
    expect(lefts.toSet(), hasLength(3), reason: 'fixture: three places');
  });

  // 🔬Where Flutter's raster sets a line is measured at `_paintedBaseline`
  // (2026-11-15): told the layout's own baseline, the engine's word stood
  // up to 0.9 px off Flutter's down the line.
  test('a line\'s letters stand on the baseline Flutter paints it on — a '
      'whole px of the layout, then a whole pixel of the raster', () {
    /// The 64ths of a px the letters of a word in [size] px type are set
    /// down by, in a raster [pixelsAPx] pixels a px.
    int setAt(double size, double pixelsAPx) {
      final painter = _laid(
        TextSpan(text: 'A1', style: _ja.copyWith(fontSize: size)),
      );
      return {
        for (final cluster
            in _word(painter, pixelsAPx: pixelsAPx).runs.single.clusters)
          cluster.y,
      }.single;
    }

    double laidAt(double size) => _laid(
      TextSpan(text: 'A1', style: _ja.copyWith(fontSize: size)),
    ).computeLineMetrics().single.baseline;

    expect(laidAt(12), closeTo(10.56, 0.005), reason: 'fixture: past a half');
    expect(laidAt(13), closeTo(11.44, 0.005), reason: 'fixture: under one');
    // The 11th px either way, which is a whole pixel at 1, 2 and 3 a px.
    for (final pixelsAPx in [1.0, 2.0, 3.0]) {
      expect(setAt(12, pixelsAPx), 11 * 64, reason: '12 px at $pixelsAPx');
      expect(setAt(13, pixelsAPx), 11 * 64, reason: '13 px at $pixelsAPx');
    }
    // 11 px is 13.75 pixels at 1.25 a px — the 14th, 11.2 px.
    expect(setAt(12, 1.25), 717);
    // 16.5 at 1.5: a half goes down the line, to the 17th — 11.33 px.
    expect(setAt(12, 1.5), 725);
    // 19.25 at 1.75: the 19th, 10.86 px.
    expect(setAt(12, 1.75), 695);
    // A raster whole times over a ratio (`wordBakeScale`), 2.5 a px: 27.5
    // pixels, the 28th — 11.2 px.
    expect(setAt(12, 2.5), 717);
  });

  test('a later line\'s letters stand on its own painted baseline', () {
    final painter = _laid(
      TextSpan(text: 'A\n1', style: _ja.copyWith(fontSize: 12)),
    );
    final lines = painter.computeLineMetrics();
    expect(lines, hasLength(2), reason: 'fixture');
    expect(
      [for (final cluster in _word(painter).runs.single.clusters) cluster.y],
      [
        for (final line in lines) (line.baseline + 0.5).floor() * 64,
      ],
    );
    expect(
      lines[1].baseline,
      greaterThan(lines[0].baseline + 6),
      reason: 'LIVENESS: two baselines',
    );
  });

  test('a run is a stretch of one size, weight and slant — a span\'s own '
      'over the ones it is nested in, at the painter\'s scale', () {
    final painter = _laid(
      TextSpan(
        style: _ja.copyWith(fontSize: 10),
        children: const [
          TextSpan(text: 'ab'),
          TextSpan(
            text: 'c',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: 'd',
            style: TextStyle(fontStyle: FontStyle.italic, fontSize: 8),
          ),
        ],
      ),
      scaler: const TextScaler.linear(1.5),
    );
    expect(
      [
        for (final run in _word(painter).runs)
          (run.size, run.weight, run.italic, _textOf(run)),
      ],
      [
        (15 * 64, 400, false, 'ab'),
        (15 * 64, 700, false, 'c'),
        (12 * 64, 400, true, 'd'),
      ],
    );
  });

  // A frame grid's word whose letter gaps gave way is laid so
  // (`laidOutGlyph`'s tight span): the letters before the last in a span
  // of their own, set tighter.
  test('a word set tighter goes over in one run, its letters where their '
      'tighter gaps put them', () {
    TextPainter laid(double spacing) => _laid(
      TextSpan(
        style: _ja.copyWith(fontSize: 12),
        children: [
          TextSpan(
            text: 'カッ',
            style: TextStyle(letterSpacing: spacing),
          ),
          const TextSpan(text: 'ト'),
        ],
      ),
    );
    final painter = laid(-1.5);
    final tight = _word(painter).runs.single;
    expect(_textOf(tight), 'カット');
    expect(
      [for (final cluster in tight.clusters) cluster.x],
      [
        for (final at in [0, 1, 2])
          (painter
                      .getBoxesForSelection(
                        TextSelection(baseOffset: at, extentOffset: at + 1),
                      )
                      .first
                      .left *
                  64)
              .round(),
      ],
    );
    expect(
      tight.clusters.last.x,
      lessThan(_word(laid(0)).runs.single.clusters.last.x - 64),
      reason: 'LIVENESS: its last letter stands over a px nearer',
    );
  });

  test('a word laid short ends in its ellipsis, where its kept letters end',
      () {
    final painter = _laid(
      TextSpan(text: 'ことばのかず', style: _ja.copyWith(fontSize: 12)),
      maxWidth: 40,
    );
    expect(painter.didExceedMaxLines, isTrue, reason: 'fixture: laid short');
    final run = _word(painter).runs.single;
    final line = painter.computeLineMetrics().single;
    expect(_textOf(run), 'こと…');
    expect(run.clusters.last.x, ((line.left + line.width) * 64).round());
    expect(
      {for (final cluster in run.clusters) cluster.y},
      {11 * 64},
      reason: 'on the baseline its letters are painted on',
    );
    expect(line.baseline, closeTo(10.56, 0.005), reason: 'fixture');
    expect(
      _textOf(
        _word(
          _laid(TextSpan(text: 'こと', style: _ja), maxWidth: 400),
        ).runs.single,
      ),
      'こと',
      reason: 'a word laid whole in its room ends in its letters',
    );
  });

  test('a word goes down the bundled faces its style names, in its order, '
      'each once and by its place among them — and the app\'s, where it '
      'names none, as a cel number does', () {
    List<int> facesOf(TextStyle style) =>
        _word(_laid(TextSpan(text: 'a', style: style))).families;
    expect(facesOf(_ja), [0, 1, 2], reason: 'the Japanese UI: theirs (Q21)');
    expect(
      facesOf(_zh),
      [2, 0, 1],
      reason: 'the Chinese UI begins with Noto Sans SC',
    );
    expect(
      facesOf(
        TextStyle(
          fontFamily: _bundled[1],
          fontFamilyFallback: [_bundled[1], _bundled[0]],
        ),
      ),
      [1, 0],
      reason: 'a repeat is one',
    );
    expect(facesOf(const TextStyle()), [0, 1, 2]);
  });

  test('what the engine is not handed is refused', () {
    for (final style in [
      const TextStyle(fontFamily: 'Somebody Else\'s Face'),
      TextStyle(
        fontFamily: _bundled[0],
        fontFamilyFallback: const ['Somebody Else\'s Face'],
      ),
      _ja.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      _ja.copyWith(
        fontVariations: const [FontVariation.weight(500)],
      ),
      _ja.copyWith(decoration: TextDecoration.underline),
      _ja.copyWith(shadows: const [Shadow(blurRadius: 1)]),
      _ja.copyWith(foreground: Paint()),
      _ja.copyWith(backgroundColor: const Color(0xFFFFFFFF)),
    ]) {
      expect(
        () => _word(_laid(TextSpan(text: 'a', style: style))),
        throwsUnsupportedError,
        reason: '$style',
      );
    }
    expect(
      _word(
        _laid(
          TextSpan(
            text: 'a',
            style: _ja.copyWith(decoration: TextDecoration.none),
          ),
        ),
      ).runs,
      hasLength(1),
      reason: 'no line is no decoration',
    );
    final twoOrders = _laid(
      TextSpan(
        style: _ja,
        children: [
          const TextSpan(text: 'a'),
          TextSpan(text: 'b', style: _zh),
        ],
      ),
    );
    expect(() => _word(twoOrders), throwsUnsupportedError);
    final placeholder = TextPainter(
      text: TextSpan(
        style: _ja,
        children: const [
          TextSpan(text: 'a'),
          WidgetSpan(child: SizedBox(width: 4, height: 4)),
        ],
      ),
      textDirection: TextDirection.ltr,
    )
      ..setPlaceholderDimensions(const [
        PlaceholderDimensions(
          size: Size(4, 4),
          alignment: PlaceholderAlignment.middle,
        ),
      ])
      ..layout();
    expect(() => _word(placeholder), throwsUnsupportedError);
  });

  // ⛔A style the engine is not handed sends its word to Flutter's raster,
  // which a tile waits for (`bakeWordOnEngine`): were the app's own type
  // one, every word of every tile would wait again and nothing would say
  // so — each bake would still be made, a frame or more late.
  testWidgets('the type the app sets a block\'s word in — its theme\'s, as '
      'a row takes it — is the engine\'s to set', (tester) async {
    late TextStyle ambient;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Material(
          child: Builder(
            builder: (context) {
              ambient = DefaultTextStyle.of(context).style;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    for (final bold in [false, true]) {
      final style = timelineBlockWordStyle(
        ambient,
        ink: const Color(0xFF123456),
        fontSize: timelineBlockNameFontSize(ambient),
        bold: bold,
      );
      final word = _word(_laid(TextSpan(text: 'A1', style: style)));
      expect(
        word.families,
        unorderedEquals([0, 1, 2]),
        reason: 'the three bundled faces, in the UI\'s order',
      );
      expect(
        word.runs.single.weight,
        bold ? 700 : (ambient.fontWeight ?? FontWeight.normal).value,
      );
    }
  });

  test('the faces are there once the bundle\'s are read — an order of them '
      'made once, the bundled order the bundled faces', () async {
    expect(EngineFaces.areRead, isFalse, reason: 'premise: none asked yet');
    final bundled = await EngineFaces.bundled();
    expect(EngineFaces.areRead, isTrue);
    expect(EngineFaces.inOrder([0, 1, 2]), same(bundled));
    final ordered = EngineFaces.inOrder([2, 0, 1]);
    expect(ordered, isNot(same(bundled)));
    expect(EngineFaces.inOrder([2, 0, 1]), same(ordered));
    expect(EngineFaces.inOrder([1, 0]), isNot(same(ordered)));
  });
}
