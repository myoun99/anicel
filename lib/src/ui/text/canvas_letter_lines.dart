import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../models/font_face_facts.dart' show FontLines;
import '../../models/text_cel_style.dart';
import 'canvas_letter_faces.dart';
import 'canvas_letter_passes.dart';

/// A run of a text's letters, as its painter holds them: from [start] up to
/// [end], set in [letters].
typedef CanvasLetterRun = ({int start, int end, TextLetterStyle letters});

/// WHERE THE LINES OF A TEXT SET IN LINES STAND — under the letters
/// ([TextLetterStyle.underline]) and through them
/// ([TextLetterStyle.strikethrough]) — for the runs of [painter]'s letters,
/// [painter] being drawn with its corner at [at]: one line a run a line,
/// as long as the run's letters reach along it.
///
/// 🚨THE ENGINE DRAWS NONE OF THEM (`canvasLetterTextStyle` asks for no
/// decoration). Its own line is drawn a run of a FACE at a time, at that
/// face's numbers — so it stepped under the Hangul a face lacks — and in
/// the letters' colour whatever the pass: under an outline it was neither
/// outlined nor hard (measured on the device, 2026-10-18). Drawn here, a
/// line is the face's that was ASKED FOR ([CanvasLetterFaces.linesOf]) all
/// the way along, and the passes draw it as they draw the letters
/// ([CanvasLetterLines]).
///
/// ★Where it stands is the engine's own rule for that one face: centred on
/// the face's number from the baseline, as thick as the face says
/// ([FontLines]), and along the line as far as the letters reach — the
/// white space a line ends with hanging past it, as the engine leaves it
/// bare.
CanvasLetterLines canvasLetterLinesOf(
  TextPainter painter,
  Iterable<CanvasLetterRun> runs, {
  ui.Offset at = ui.Offset.zero,
}) => (CanvasLetterLinesBuilder()..addLinesOf(painter, runs, at: at)).build();

/// How far [run]'s letters reach along each line they are set on: from the
/// left of the first to the right of the last — and no further than the
/// line's own letters reach: the white space it ends with hangs past it.
List<({ui.LineMetrics line, double left, double right})> _reachOf(
  TextPainter painter,
  List<ui.LineMetrics> metrics,
  CanvasLetterRun run,
) {
  final reach = <int, ({double left, double right})>{};
  for (final box in painter.getBoxesForSelection(
    TextSelection(baseOffset: run.start, extentOffset: run.end),
    // As tall as its line, so it holds that line's baseline and no other's
    // whatever the lines' pitch (a box as tall as its letters reaches up
    // past the line above where the lines are set closer than that).
    boxHeightStyle: ui.BoxHeightStyle.max,
  )) {
    final line = _lineOf(metrics, box);
    if (line == null) {
      continue;
    }
    final right = math.min(box.right, line.left + line.width);
    if (right <= box.left) {
      continue;
    }
    final had = reach[line.lineNumber];
    reach[line.lineNumber] = had == null
        ? (left: box.left, right: right)
        : (
            left: math.min(had.left, box.left),
            right: math.max(had.right, right),
          );
  }
  return [
    for (final MapEntry(key: number, value: (:left, :right)) in reach.entries)
      (line: metrics[number], left: left, right: right),
  ];
}

/// The line [box] — as tall as its line — stands on: the first, down the
/// page, whose baseline is not above it, which is the one it holds.
ui.LineMetrics? _lineOf(List<ui.LineMetrics> metrics, ui.TextBox box) {
  for (final line in metrics) {
    if (box.top <= line.baseline) {
      return line;
    }
  }
  return null;
}

/// A line across, from [left] to [right], [thickness] thick about
/// [centre].
ui.Rect _across(
  double left,
  double right, {
  required double centre,
  required double thickness,
}) => ui.Rect.fromLTRB(
  left,
  centre - thickness / 2,
  right,
  centre + thickness / 2,
);

/// Gathers a text's lines, the one under its letters and the one through
/// them each on its own, and makes ONE line of two that carry on from each
/// other in letters every pass paints alike ([canvasLettersPaintAlike]).
///
/// ⚠️Not for neatness: two smoothed rects that meet between two pixels
/// each cover part of that column of pixels, and laid one over the other
/// the parts do not add up to the whole — a run that turns bold, or a
/// column's next letter, left a paler seam in the line. One rect has none.
class CanvasLetterLinesBuilder {
  final List<CanvasLetterLine> _under = [];
  final List<CanvasLetterLine> _through = [];

  /// [rect], a line under [letters].
  void under(TextLetterStyle letters, ui.Rect rect) =>
      _add(_under, letters, rect);

  /// [rect], a line through [letters].
  void through(TextLetterStyle letters, ui.Rect rect) =>
      _add(_through, letters, rect);

  /// The lines of [runs] of [painter]'s letters, [painter] being drawn with
  /// its corner at [at] ([canvasLetterLinesOf]).
  void addLinesOf(
    TextPainter painter,
    Iterable<CanvasLetterRun> runs, {
    ui.Offset at = ui.Offset.zero,
  }) {
    final metrics = painter.computeLineMetrics();
    for (final run in runs) {
      final letters = run.letters;
      if (!letters.underline && !letters.strikethrough) {
        continue;
      }
      final face = CanvasLetterFaces.current.linesOf(letters.fontFamily);
      for (final (:line, :left, :right) in _reachOf(painter, metrics, run)) {
        final baseline = line.baseline + at.dy;
        final size = letters.fontSize;
        if (letters.underline) {
          under(
            letters,
            _across(
              left + at.dx,
              right + at.dx,
              centre: baseline + face.underline * size,
              thickness: face.underlineThickness * size,
            ),
          );
        }
        if (letters.strikethrough) {
          through(
            letters,
            _across(
              left + at.dx,
              right + at.dx,
              centre: baseline - face.strikethrough * size,
              thickness: face.strikethroughThickness * size,
            ),
          );
        }
      }
    }
  }

  CanvasLetterLines build() => _under.isEmpty && _through.isEmpty
      ? CanvasLetterLines.none
      : CanvasLetterLines([..._under, ..._through]);

  static void _add(
    List<CanvasLetterLine> lines,
    TextLetterStyle letters,
    ui.Rect rect,
  ) {
    final last = lines.lastOrNull;
    if (last != null && canvasLettersPaintAlike(last.letters, letters)) {
      final joined = _carriedOn(last.rect, rect);
      if (joined != null) {
        lines.last = (letters: last.letters, rect: joined);
        return;
      }
    }
    lines.add((letters: letters, rect: rect));
  }
}

/// [a] and [b] as one rect, where [b] carries on from [a] — along a line,
/// as thick and as high, or down a column, as wide and where it stands —
/// and null where it does not.
ui.Rect? _carriedOn(ui.Rect a, ui.Rect b) {
  if (a.top == b.top && a.bottom == b.bottom && b.left == a.right) {
    return ui.Rect.fromLTRB(a.left, a.top, b.right, a.bottom);
  }
  if (a.left == b.left && a.right == b.right && b.top == a.bottom) {
    return ui.Rect.fromLTRB(a.left, a.top, a.right, b.bottom);
  }
  return null;
}
