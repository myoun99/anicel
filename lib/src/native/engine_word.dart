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
/// grapheme cluster where its painter's layout put it — the box's left and
/// its line's baseline, the letter gaps it gave included —, in runs of one
/// size, weight and slant, and the faces its style goes down
/// ([families]). Read off the painter in the paint that asks for the bake
/// and kept as plain values, the painter being that paint's.
final class EngineWord {
  const EngineWord._(this.runs, this.families);

  final List<EngineWordRun> runs;

  /// The bundled families its letters go down, in order ([EngineFaces]).
  final List<String> families;

  /// [painter]'s word, laid out. Throws [UnsupportedError] for what the
  /// engine is not handed: a span that is no text, and a word whose spans
  /// go down two orders of faces — a bake sets one word in one.
  static EngineWord of(TextPainter painter) {
    final leaves = _leavesOf(painter.text!);
    final families = _familiesOf(leaves.first.style);
    for (final (:style, end: _) in leaves) {
      if (!listEquals(_familiesOf(style), families)) {
        throw UnsupportedError('a word set in two orders of faces');
      }
    }
    final set = [
      for (final line in canvasLetterClustersAt(painter, Offset.zero))
        for (final (:cluster, :start) in line)
          (
            style: leaves.firstWhere((leaf) => leaf.end > start).style,
            cluster: _placed(cluster.text, cluster.left, cluster.baseline),
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
        cluster: _placed(ellipsis, line.left + line.width, line.baseline),
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

/// The bundled families [style] goes down, in its order, each once — a
/// family the app does not bundle passed over, as Flutter passes over one
/// it does not hold.
///
/// ⚠️Mine (2026-11-08): a style that names none of them is set in all of
/// them, in the canvas letters' order. Flutter would go on to the
/// machine's face, which the engine cannot see; the app speaks in one face
/// (「앱은 한 글꼴」, 유저 2026-08-28), and a canvas letter whose face this
/// device lacks is set in the bundled one (`canvasLetterTextStyle`).
List<String> _familiesOf(TextStyle style) {
  final named = <String>{
    for (final family in [?style.fontFamily, ...?style.fontFamilyFallback])
      if (_bundled.contains(family)) family,
  };
  return named.isEmpty ? _bundled : named.toList();
}

final List<String> _bundled = [
  for (final face in AppTypography.canvasLetterFaces) face.family,
];

int _inSixtyFourths(double length) => (length * 64).round();

/// [text] with its box's left at [left] and its line's baseline at
/// [baseline], px of the layout, as the engine is handed a cluster.
GpuCluster _placed(String text, double left, double baseline) => (
  text: text,
  x: _inSixtyFourths(left),
  y: _inSixtyFourths(baseline),
);
