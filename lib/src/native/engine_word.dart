import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/painting.dart';
import 'package:gpu_engine/gpu_engine.dart';

import '../ui/text/canvas_letter_shapes.dart' show canvasLetterClustersAt;
import '../ui/theme/app_theme.dart' show AppTypography;

/// A run of a word's clusters in one style, as the GPU engine is handed it
/// ([GpuWord.run]): [size] 64ths of a px, [weight] a `FontWeight`'s value.
typedef EngineWordRun = ({
  int size,
  int weight,
  bool italic,
  List<GpuCluster> clusters,
});

/// A WORD AS THE GPU ENGINE SETS IT for its bake (`word_bake.dart`): each
/// grapheme cluster where its painter would paint it — the box's left,
/// the letter gaps its layout gave included, and the baseline Flutter
/// paints its line on ([_paintedBaseline]) —, in runs of one size, weight
/// and slant, and the faces its style goes down ([families]). Read off the
/// painter in the paint that asks for the bake and kept as plain values,
/// the painter being that paint's.
final class EngineWord {
  const EngineWord._(this.runs, this.families);

  final List<EngineWordRun> runs;

  /// The bundled families its letters go down, in order, each by its
  /// place among [AppTypography.canvasLetterFaces]
  /// ([EngineFaces.inOrder]).
  final List<int> families;

  /// [painter]'s word, laid out, as a raster [pixelsAPx] pixels a px of
  /// its layout takes it. Throws [UnsupportedError] for what the engine is
  /// not handed: a span that is no text, a face the app does not bundle
  /// ([_familiesOf]), a paint past the letters' outlines
  /// ([_refuseWhatIsNotHanded]), and a word whose spans go down two orders
  /// of faces — a bake sets one word in one.
  static EngineWord of(TextPainter painter, {required double pixelsAPx}) {
    final leaves = _leavesOf(painter.text!);
    final families = _familiesOf(leaves.first.style);
    for (final (:style, end: _) in leaves) {
      _refuseWhatIsNotHanded(style);
      if (!listEquals(_familiesOf(style), families)) {
        throw UnsupportedError('a word set in two orders of faces');
      }
    }
    final set = [
      for (final line in canvasLetterClustersAt(painter, Offset.zero))
        for (final (:cluster, :start) in line)
          (
            style: leaves.firstWhere((leaf) => leaf.end > start).style,
            cluster: _placed(
              cluster.text,
              cluster.left,
              _paintedBaseline(cluster.baseline, pixelsAPx),
            ),
          ),
    ];
    // 🔬A WORD LAID SHORT ends in its ellipsis where its kept letters end:
    // the layout gives the letters it dropped no box, and the last one it
    // kept a box that runs on over the ellipsis (measured 2026-11-08:
    // 「ことばのかず」 at 12 px in 40 — 「と」's box 10.7 to 34.0, the line
    // 21.96 wide). ⚠️Mine: in the style of the letter before it.
    if (painter.ellipsis case final ellipsis?
        when painter.didExceedMaxLines && set.isNotEmpty) {
      final line = painter.computeLineMetrics().last;
      set.add((
        style: set.last.style,
        cluster: _placed(
          ellipsis,
          line.left + line.width,
          _paintedBaseline(line.baseline, pixelsAPx),
        ),
      ));
    }
    final runs = <EngineWordRun>[];
    for (final (:style, :cluster) in set) {
      final size = _inSixtyFourths(
        painter.textScaler.scale(style.fontSize ?? kDefaultFontSize),
      );
      final weight = (style.fontWeight ?? FontWeight.normal).value;
      final italic = style.fontStyle == FontStyle.italic;
      final last = runs.lastOrNull;
      if (last != null &&
          (last.size, last.weight, last.italic) == (size, weight, italic)) {
        last.clusters.add(cluster);
      } else {
        runs.add((
          size: size,
          weight: weight,
          italic: italic,
          clusters: [cluster],
        ));
      }
    }
    return EngineWord._(runs, families);
  }

  /// Hands [word] these runs.
  void handTo(GpuWord word) {
    for (final (:size, :weight, :italic, :clusters) in runs) {
      word.run(size: size, weight: weight, italic: italic, clusters: clusters);
    }
  }
}

/// Each text of [span]'s tree, by where it ends in the painter's text, in
/// the style it is set in — its own over the ones it is nested in, as the
/// engine reads a span's (`TextStyle.merge`).
List<({int end, TextStyle style})> _leavesOf(InlineSpan span) {
  final leaves = <({int end, TextStyle style})>[];
  var end = 0;
  void walk(InlineSpan span, TextStyle inherited) {
    if (span is! TextSpan) {
      throw UnsupportedError('a word the engine sets is text alone: $span');
    }
    final style = inherited.merge(span.style);
    if (span.text case final text?) {
      end += text.length;
      leaves.add((end: end, style: style));
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      walk(child, style);
    }
  }

  walk(span, const TextStyle());
  return leaves;
}

/// The bundled families [style] goes down, in its order, each once and by
/// its place among [AppTypography.canvasLetterFaces] — the cel number's
/// law (`engine_letters.dart`), asked the same of a word. Throws
/// [UnsupportedError] for a family the app does not bundle, as letters
/// named in a face of their own are refused there: Flutter sets them in it
/// where the machine has it, and the engine is handed no other. A style
/// that names none is set in the bundled ones, in the canvas letters'
/// order, as letters with no face of their own are there — the app speaks
/// in one face (「앱은 한 글꼴」, 유저 2026-08-28).
List<int> _familiesOf(TextStyle style) {
  final named = {?style.fontFamily, ...?style.fontFamilyFallback};
  if (named.isEmpty) {
    return [for (final (place, _) in _bundled.indexed) place];
  }
  return [
    for (final family in named)
      switch (_bundled.indexOf(family)) {
        -1 => throw UnsupportedError(
          'letters in a face the engine is not handed: $family',
        ),
        final place => place,
      },
  ];
}

/// Throws [UnsupportedError] where [style] paints what the engine's bake
/// does not — it sets the letters' outlines alone, and a word painted with
/// more is painted as it always was.
void _refuseWhatIsNotHanded(TextStyle style) {
  final more = [
    if (style.fontFeatures?.isNotEmpty ?? false) 'font features',
    if (style.fontVariations?.isNotEmpty ?? false) 'font variations',
    if (style.decoration case final line? when line != TextDecoration.none)
      'a decoration',
    if (style.shadows?.isNotEmpty ?? false) 'shadows',
    if (style.foreground != null) 'a paint of its own',
    if (style.background != null || style.backgroundColor != null)
      'a background',
  ];
  if (more.isNotEmpty) {
    throw UnsupportedError('a word set with ${more.join(', ')}');
  }
}

final List<String> _bundled = [
  for (final face in AppTypography.canvasLetterFaces) face.family,
];

int _inSixtyFourths(double length) => (length * 64).round();

/// THE BASELINE FLUTTER PAINTS A LINE ON, whose layout says [baseline], in
/// a raster [pixelsAPx] pixels a px: a whole px of the layout — the
/// paragraph sets a line's letters at `floor(baseline + 0.5)` — and then a
/// whole pixel of the raster, the rasteriser setting an upright line's
/// glyphs on whole rows whatever fraction of one its baseline falls on.
/// The engine sets an outline where it is told to the 64th of a px, so a
/// word told its layout's baseline stood off Flutter's by the fraction
/// those two drop.
///
/// 🔬2026-11-15, the app's face on Impeller (`flutter test
/// --enable-impeller`):
/// - The foot of 「H」 · 「E」 · 「1」 in Flutter's bake, 12–24 px × ratio
///   1–2 (90 bakes): its last inked row ends on this baseline in every
///   bake of type 18 pixels and under, and one row under it in every one
///   of 19.5 and more. The engine's own raster of those letters ends
///   0.024 to 0.025 of the type's size under the baseline it is told —
///   half a pixel from there up: the face draws them so, Flutter's
///   hinting takes that to a whole row, and the engine draws it as it is.
/// - Nine words × 9–20 px × ratio 1–2 (315 bakes) beside Flutter's bake
///   of the same word, down the line: told the layout's baseline the
///   engine's stood −0.93 to +0.91 px off it, the median 0.35 either way,
///   and 73 inked the same rows; on this one −0.40 to +0.51, 0.07, and
///   162. On a whole px alone −0.56 to +0.51, 0.09, 151 — the raster's
///   pixel is what a ratio of 1.25 · 1.5 · 1.75 adds. (The tester's own
///   renderer: each of those the same to 0.1 px.)
///
/// ⚠️A LINE BEGINS ON A WHOLE PX: the paragraph rounds a line's own
/// baseline and adds it to where the line begins, and this rounds the sum.
/// The two are one while every line above is a whole number of px tall,
/// as lines of text alone are.
double _paintedBaseline(double baseline, double pixelsAPx) =>
    ((baseline + 0.5).floorToDouble() * pixelsAPx + 0.5).floorToDouble() /
    pixelsAPx;

/// [text] with its box's left at [left] and its line's baseline at
/// [baseline], px of the layout, as the engine is handed a cluster.
GpuCluster _placed(String text, double left, double baseline) => (
  text: text,
  x: _inSixtyFourths(left),
  y: _inSixtyFourths(baseline),
);
