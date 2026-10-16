import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨★★A BOX IS TURNED BY THE AXIS IN ONE PLACE.
///
/// The x-sheet is the timeline turned on its side, so every widget that
/// serves both orientations has to say "this much ALONG the strip, that much
/// ACROSS it". The spelling was `horizontal ? SizedBox(width: e) :
/// SizedBox(height: e)` — and the audit found it written by hand in a dozen
/// files, six times in one build, each pair a place for one side to lag the
/// other. `axis_turn.dart` says it once ([alongBox], [acrossBox],
/// [placedAlong], [stripAcross]).
///
/// This is a RATCHET, not a ban: the files that still turn a box by hand are
/// listed, the list only shrinks, and a file not on it that starts doing so
/// is red. Remove a file's line when its last pair goes.
void main() {
  const home = 'lib/src/ui/timeline/axis_turn.dart';
  const turns = ['alongBox(', 'acrossBox(', 'placedAlong(', 'stripAcross('];

  /// Files that still spell a turn by hand — a ternary on the axis whose
  /// next line opens a SizedBox or a Positioned. Only shrinks.
  const stillByHand = <String>{
    // Asymmetric: the vertical row boxes its cross extent, the horizontal
    // row takes its height from the parent list — not a turn.
    'lib/src/ui/timeline/timeline_frame_cells_row.dart',
  };

  final axisTest = RegExp(
    r'(horizontal|isVertical|vertical|axis == Axis\.(horizontal|vertical))\s*$',
  );
  final turnedBox = RegExp(r'^\s*\? (const )?(SizedBox|Positioned)\(');

  /// Lines where a box is turned by hand.
  List<int> handTurnsIn(File file) {
    final lines = file.readAsLinesSync();
    final hits = <int>[];
    for (var i = 1; i < lines.length; i++) {
      if (axisTest.hasMatch(lines[i - 1]) && turnedBox.hasMatch(lines[i])) {
        hits.add(i + 1);
      }
    }
    return hits;
  }

  test('premise: the home has the four turns', () {
    final text = File(home).readAsStringSync();
    for (final turn in turns) {
      expect(text, contains(turn), reason: '$turn is what callers reach for');
    }
  });

  test('premise: the scan sees a hand turn', () {
    // A regex that matched nothing would make the ratchet a formality.
    final seen = <String>{
      for (final file in dartFilesUnder('lib'))
        if (handTurnsIn(file).isNotEmpty) libPath(file),
    };
    expect(seen, isNotEmpty);
  });

  test('no file outside the ledger turns a box by hand', () {
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib')) {
      final path = libPath(file);
      if (path == home || stillByHand.contains(path)) continue;
      for (final line in handTurnsIn(file)) {
        offenders.add('$path:$line');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'reach for alongBox / acrossBox / placedAlong / stripAcross',
    );
  });

  test('the ledger holds no file that has stopped', () {
    final paid = <String>[
      for (final path in stillByHand)
        if (handTurnsIn(File(path)).isEmpty) path,
    ];
    expect(paid, isEmpty, reason: 'delete these lines from stillByHand');
    expect(stillByHand, hasLength(1));
  });

  // ── The painter twins (round 8, C9) ────────────────────────────────────
  //
  // A painter turns the SAME way: `horizontal ? size.width : size.height`
  // at the top of `paint`, and `horizontal ? Offset(a, b) : Offset(b, a)`
  // for every point. Fifteen sites in eight files spelled it; the home says
  // it once as [extentAlong], [extentAcross] and [offsetAlong]. The size's
  // half is read with the other parts now, below — its scan named only a
  // `size`, and a rect's or a layout's room went past it.
  const painterTurns = ['extentAlong(', 'extentAcross(', 'offsetAlong('];

  /// `? Offset(a, b) … : Offset(b, a)` — the point turned by hand, the
  /// `:` arm on the same line or the next.
  final turnedOffset = RegExp(
    r'\?\s*\(?Offset\((\w+), (\w+)\)\s*(?:\r?\n\s*)?:\s*\(?Offset\(\2, \1\)',
  );

  /// Files that still turn a point by hand. Only shrinks.
  const pointsStillByHand = <String>{
    // Drags whose VERTICAL scrolled offset has no pin yet
    // (every_frame_drag_follows_the_edge_test scans the wiring, not the
    // direction), and a law moves only behind a test that pins it.
    'lib/src/ui/timeline/timeline_frame_range_gesture.dart',
    'lib/src/ui/timeline/timeline_row_edit_chrome.dart',
    // Turned by an AxisDirection, not an Axis: `down` is the vertical arm
    // and every other direction — `up` included — the horizontal one.
    // Reading it through `axisDirectionToAxis` would move `up`, which is a
    // behaviour question for the scroll lane, not a spelling.
    'lib/src/ui/layout/device_grid_scroll_controller.dart',
  };

  /// Lines where a painter turns a point by hand.
  List<int> handPainterTurnsIn(File file) {
    final text = file.readAsStringSync();
    int lineOf(int index) =>
        '\n'.allMatches(text.substring(0, index)).length + 1;
    return [for (final m in turnedOffset.allMatches(text)) lineOf(m.start)];
  }

  test('premise: the home has the three painter twins', () {
    final text = File(home).readAsStringSync();
    for (final turn in painterTurns) {
      expect(text, contains(turn), reason: '$turn is what painters reach for');
    }
  });

  test('premise: the painter scan sees a hand turn', () {
    // The ledger's own files are the proof the regex matches something.
    for (final path in pointsStillByHand) {
      expect(handPainterTurnsIn(File(path)), isNotEmpty, reason: path);
    }
  });

  test('no file outside the ledger turns a point by hand', () {
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib')) {
      final path = libPath(file);
      if (path == home || pointsStillByHand.contains(path)) continue;
      for (final line in handPainterTurnsIn(file)) {
        offenders.add('$path:$line');
      }
    }
    expect(offenders, isEmpty, reason: 'reach for offsetAlong');
  });

  test('the point ledger holds no file that has stopped', () {
    final paid = <String>[
      for (final path in pointsStillByHand)
        if (handPainterTurnsIn(File(path)).isEmpty) path,
    ];
    expect(paid, isEmpty, reason: 'delete these lines from pointsStillByHand');
    expect(pointsStillByHand, hasLength(3));
  });

  // ── The parts (card one-axis-part-of-an-offset-is-one-function) ────────
  //
  // READING one part of a pair by the axis — `horizontal ? delta.dx :
  // delta.dy` of a movement or a point, `horizontal ? rect.width :
  // rect.height` of a box — was written by hand on thirty-eight lines in
  // twenty files (2026-10-17): thirty of an offset, which nothing in the
  // home said, and eight of an extent that [extentAlong] already did. The
  // home says each once — [partAlong], [partAcross], [extentAlong],
  // [extentAcross] — and this is a ban, with no ledger.

  /// The axis asked by name just before the `?`: `horizontal`, `_vertical`,
  /// `axis == Axis.horizontal`, `across`. ⚠️By name, because a pick of a
  /// pair's part need not be by the axis — `a.width > a.height ? a.width :
  /// a.height` is the longer side, and it stays.
  const axisAsked = r'(?:\w*(?:[Hh]orizontal|[Vv]ertical)|across)\s*\?\s*';
  RegExp byTheAxis(String part) => RegExp('$axisAsked$part');
  final readByHand = [
    // A part of an offset: `? p.dx : p.dy`, or the reverse.
    byTheAxis(r'([\w.()!]+?)\.d(?:x\s*:\s*\1\.dy|y\s*:\s*\1\.dx)\b'),
    // Both parts at once: `? (p.dx, p.dy) : (p.dy, p.dx)`.
    byTheAxis(
      r'\(\s*([\w.()!]+?)\.d[xy]\s*,\s*\1\.d[xy]\s*\)\s*:\s*\(\s*\1\.d[xy]',
    ),
    // An extent of a size, a rect, or the room a layout is given.
    byTheAxis(
      r'([\w.()!]+?)\.(?:width\s*:\s*\1\.height|height\s*:\s*\1\.width'
      r'|maxWidth\s*:\s*\1\.maxHeight|maxHeight\s*:\s*\1\.maxWidth)\b',
    ),
  ];

  /// Lines of [source] that read a part by hand — its comments aside, so a
  /// decision that quotes the old spelling is not one.
  List<int> handReadsIn(String source) {
    final code = source.replaceAll(RegExp(r'//[^\n]*'), '');
    int lineOf(int index) =>
        '\n'.allMatches(code.substring(0, index)).length + 1;
    return [
      for (final read in readByHand)
        for (final m in read.allMatches(code)) lineOf(m.start),
    ]..sort();
  }

  test('premise: the scan sees the home read each part once', () {
    // partAlong, partAcross, extentAlong, extentAcross — and nothing else.
    expect(handReadsIn(File(home).readAsStringSync()), hasLength(4));
  });

  test('premise: the scan sees every spelling the card took out', () {
    // Lines as they stood on 2026-10-17, one of each shape.
    const spelled = [
      '_moved += across == Axis.horizontal ? event.delta.dx : event.delta.dy;',
      'final main = widget.axis == Axis.horizontal\n'
          '    ? localPosition.dy\n'
          '    : localPosition.dx;',
      'rowAxis == Axis.vertical ? local.dy : local.dx,',
      ': columnValueText(across ? centre.dx : centre.dy);',
      'final (along, across) = axis == Axis.horizontal\n'
          '    ? (position.dx, position.dy)\n'
          '    : (position.dy, position.dx);',
      'final extent = horizontal ? rect.width : rect.height;',
      'onExtent(_vertical ? constraints.maxHeight : constraints.maxWidth);',
    ];
    for (final line in spelled) {
      expect(handReadsIn(line), hasLength(1), reason: line);
    }
    expect(
      handReadsIn('bounds.width > bounds.height ? bounds.width : '
          'bounds.height'),
      isEmpty,
      reason: 'the longer side is not read by the axis',
    );
  });

  test('no file but the home reads a part by hand', () {
    final offenders = <String>[
      for (final file in dartFilesUnder('lib'))
        if (libPath(file) != home)
          for (final line in handReadsIn(file.readAsStringSync()))
            '${libPath(file)}:$line',
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'reach for partAlong / partAcross / extentAlong / extentAcross',
    );
  });
}
