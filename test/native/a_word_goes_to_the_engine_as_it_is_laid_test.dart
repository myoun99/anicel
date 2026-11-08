import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/native/engine_faces.dart';
import 'package:anicel/src/native/engine_word.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppTypography;

import '../helpers/app_faces.dart';

/// A word goes to the GPU engine for its bake as Flutter laid it
/// (`engine_word.dart`): each grapheme cluster at its box's left and its
/// line's baseline, in runs of one size, weight and slant, down the faces
/// its style names — where its letters stand is the layout's, and which
/// glyphs they take and how they raster the engine's
/// (`kernels/letters/words/tests.rs`).

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

  test('each cluster goes where the layout put it — its box\'s left and its '
      'line\'s baseline, in 64ths of a px', () {
    final painter = _laid(
      TextSpan(text: 'カ3셀', style: _ja.copyWith(fontSize: 12)),
    );
    final baseline = painter.computeLineMetrics().single.baseline;
    final lefts = [
      for (final at in [0, 1, 2])
        painter
            .getBoxesForSelection(
              TextSelection(baseOffset: at, extentOffset: at + 1),
            )
            .first
            .left,
    ];
    final run = EngineWord.of(painter).runs.single;
    expect((run.size, run.weight, run.italic), (12 * 64, 400, false));
    expect(
      [for (final cluster in run.clusters) cluster.text],
      ['カ', '3', '셀'],
    );
    expect([for (final cluster in run.clusters) cluster.x], [
      for (final left in lefts) (left * 64).round(),
    ]);
    expect(lefts.toSet(), hasLength(3), reason: 'fixture: three places');
    expect({for (final cluster in run.clusters) cluster.y}, {
      (baseline * 64).round(),
    });
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
        for (final run in EngineWord.of(painter).runs)
          (run.size, run.weight, run.italic, _textOf(run)),
      ],
      [
        (15 * 64, 400, false, 'ab'),
        (15 * 64, 700, false, 'c'),
        (12 * 64, 400, true, 'd'),
      ],
    );
  });

  test('a word laid short ends in its ellipsis, where its kept letters end',
      () {
    final painter = _laid(
      TextSpan(text: 'ことばのかず', style: _ja.copyWith(fontSize: 12)),
      maxWidth: 40,
    );
    expect(painter.didExceedMaxLines, isTrue, reason: 'fixture: laid short');
    final run = EngineWord.of(painter).runs.single;
    final line = painter.computeLineMetrics().single;
    expect(_textOf(run), 'こと…');
    expect(run.clusters.last.x, ((line.left + line.width) * 64).round());
    expect(run.clusters.last.y, (line.baseline * 64).round());
    expect(
      _textOf(
        EngineWord.of(_laid(TextSpan(text: 'こと', style: _ja))).runs.single,
      ),
      'こと',
      reason: 'a word laid whole ends in its letters',
    );
  });

  test('a word goes down the bundled faces its style names, in its order, '
      'each once — and the app\'s, where it names none, as a cel number '
      'does', () {
    List<String> facesOf(TextStyle style) =>
        EngineWord.of(_laid(TextSpan(text: 'a', style: style))).families;
    expect(facesOf(_ja), _bundled, reason: 'the Japanese UI: theirs (Q21)');
    expect(facesOf(_zh), [
      _bundled[2],
      _bundled[0],
      _bundled[1],
    ], reason: 'the Chinese UI begins with Noto Sans SC');
    expect(
      facesOf(
        TextStyle(
          fontFamily: _bundled[1],
          fontFamilyFallback: [_bundled[1], _bundled[0]],
        ),
      ),
      [_bundled[1], _bundled[0]],
      reason: 'a repeat is one',
    );
    expect(facesOf(const TextStyle()), _bundled);
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
        () => EngineWord.of(_laid(TextSpan(text: 'a', style: style))),
        throwsUnsupportedError,
        reason: '$style',
      );
    }
    expect(
      EngineWord.of(
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
    expect(() => EngineWord.of(twoOrders), throwsUnsupportedError);
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
    expect(() => EngineWord.of(placeholder), throwsUnsupportedError);
  });

  test('faces in an order are made once, and the bundled order is the '
      'bundled faces', () async {
    final bundled = await EngineFaces.bundled();
    expect(await EngineFaces.inOrderOf(_bundled), same(bundled));
    final chinese = [_bundled[2], _bundled[0], _bundled[1]];
    final ordered = await EngineFaces.inOrderOf(chinese);
    expect(ordered, isNot(same(bundled)));
    expect(await EngineFaces.inOrderOf(chinese), same(ordered));
    await expectLater(
      EngineFaces.inOrderOf(['Somebody Else\'s Face']),
      throwsUnsupportedError,
    );
  });
}
