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
  // `size`, and a rect's or a layout's room went past it. The point's half
  // is built with the other values, at the end — its scan saw a point only
  // when its arms swapped two bare names, and `Offset(at, rect.top)` went
  // past it.
  const painterTurns = ['extentAlong(', 'extentAcross(', 'offsetAlong('];

  test('premise: the home has the three painter twins', () {
    final text = File(home).readAsStringSync();
    for (final turn in painterTurns) {
      expect(text, contains(turn), reason: '$turn is what painters reach for');
    }
  });

  // ── The parts (card one-axis-part-of-an-offset-is-one-function) ────────
  //
  // READING one part of a pair by the axis — `horizontal ? delta.dx :
  // delta.dy` of a movement or a point, `horizontal ? rect.width :
  // rect.height` of a box — was written by hand on thirty-eight lines in
  // twenty files (2026-10-17): thirty of an offset, which nothing in the
  // home said, and eight of an extent that [extentAlong] already did. An
  // EDGE of a rect — `horizontal ? rect.left : rect.top` — on twenty-four
  // more in nine (card values-built-by-the-axis-are-one-function, the same
  // day). The home says each once — [partAlong], [partAcross],
  // [extentAlong], [extentAcross], [startAlong], [endAlong], [startAcross],
  // [endAcross] — and this is a ban, with no ledger.

  /// The axis asked by name just before the `?`: `horizontal`, `_vertical`,
  /// `axis == Axis.horizontal`, `across`, `along`. ⚠️By name, because a pick
  /// of a pair's part need not be by the axis — `a.width > a.height ?
  /// a.width : a.height` is the longer side, and it stays.
  const axisAsked =
      r'(?:\w*(?:[Hh]orizontal|[Vv]ertical)|across|along)\s*\?\s*';
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
    // An edge of a rect: `? r.left : r.top`, and the other three.
    byTheAxis(
      r'([\w.()!]+?)\.(?:left\s*:\s*\1\.top|top\s*:\s*\1\.left'
      r'|right\s*:\s*\1\.bottom|bottom\s*:\s*\1\.right)\b',
    ),
  ];

  /// Lines of [source] that [scans] match — its comments aside, so a
  /// decision that quotes the old spelling is not one.
  List<int> linesMatching(List<RegExp> scans, String source) {
    final code = source.replaceAll(RegExp(r'//[^\n]*'), '');
    int lineOf(int index) =>
        '\n'.allMatches(code.substring(0, index)).length + 1;
    return [
      for (final scan in scans)
        for (final m in scan.allMatches(code)) lineOf(m.start),
    ]..sort();
  }

  List<int> handReadsIn(String source) => linesMatching(readByHand, source);

  test('premise: the scan sees the home read each part once', () {
    // partAlong, partAcross, extentAlong, extentAcross and the four edges —
    // and nothing else.
    expect(handReadsIn(File(home).readAsStringSync()), hasLength(8));
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
      'final a0 = horizontal ? box.left : box.top;',
      'final a1 = horizontal ? box.right : box.bottom;',
      'final c0 = horizontal ? box.top : box.left;',
      'final c1 = horizontal ? box.bottom : box.right;',
      // A test's, by a flag named for the axis it runs along.
      'final across = (along ? end.dy : end.dx).floor();',
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
      reason:
          'reach for partAlong / partAcross / extentAlong / extentAcross / '
          'startAlong / endAlong / startAcross / endAcross',
    );
  });

  /// ⛔**NOR A TEST** (card axis-offset-read-inline-copies): a test that
  /// reads a part by hand is the same turn spelled once more, and it reads
  /// the old way the day the home learns a new one. 🔬On master `4520fe717`
  /// the tests read twenty-seven by hand, in eleven files — two of them by
  /// a flag named `along`, which the scan learned to hear with them.
  test('no test reads a part by hand either', () {
    final offenders = <String>[
      for (final file in dartFilesUnder('test'))
        // It spells the old reads out, to show the scan sees them.
        if (!file.path.endsWith('one_axis_turn_test.dart'))
          for (final line in handReadsIn(file.readAsStringSync()))
            '${file.path}:$line',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'reach for partAlong / partAcross / extentAlong / extentAcross / '
          'startAlong / endAlong / startAcross / endAcross',
    );
  });

  // ── The builds (card values-built-by-the-axis-are-one-function) ────────
  //
  // BUILDING a value by the axis — `horizontal ? Offset(a, b) : Offset(b,
  // a)`, a size, a rect, a box moved each way, the alignment a strip's run
  // sets off from — was written by hand on thirty-nine lines in sixteen
  // files (2026-10-17). The home builds each once: [offsetAlong],
  // [sizeAlong], [rectAlong], [centerStartAlong], [centerEndAlong] — and
  // this is a ban, with no ledger.
  //
  // The three drags that fold the edge pan into the hand's travel came
  // last, the same day: a law moves only behind a test that pins it, and
  // nothing pinned the sheet's half of their pan until the edge-pan tests
  // ran on both surfaces.
  //
  // ⛔A margin (`EdgeInsets`) and a `BoxConstraints` are not here: two
  // each, in shapes that differ, and a third has to show they are one
  // algorithm before they are made one (the card's own ⛔).

  /// One build in each arm of a pick by the axis, the `:` arm's on the same
  /// line or a later one — its arguments as deep as one call.
  const arguments = r'\((?:[^()]|\([^()]*\))*\)';
  RegExp builtEachWay(String build) => byTheAxis(
    '(?:const\\s+)?$build$arguments\\s*:\\s*(?:const\\s+)?$build\\(',
  );
  final builtByHand = [
    builtEachWay(r'\bOffset'),
    builtEachWay(r'\bSize'),
    builtEachWay(r'\bRect\.fromLT(?:RB|WH)'),
    // One point or box moved each way: `? p.translate(a, 0) :
    // p.translate(0, a)`, `? r.shift(Offset(…)) : r.shift(…)`.
    byTheAxis(
      '([\\w.()!]+?)\\.(translate|shift)$arguments\\s*:\\s*\\1\\.\\2\\(',
    ),
    // Where a run sets off, or ends: `? Alignment.centerLeft :
    // Alignment.topCenter`, and back.
    byTheAxis(
      r'Alignment\.(?:centerLeft\s*:\s*Alignment\.topCenter'
      r'|topCenter\s*:\s*Alignment\.centerLeft'
      r'|centerRight\s*:\s*Alignment\.bottomCenter'
      r'|bottomCenter\s*:\s*Alignment\.centerRight)\b',
    ),
  ];

  List<int> handBuildsIn(String source) => linesMatching(builtByHand, source);

  test('premise: the scan sees the home build each value once', () {
    // offsetAlong, sizeAlong, rectAlong, centerStartAlong, centerEndAlong.
    expect(handBuildsIn(File(home).readAsStringSync()), hasLength(5));
  });

  test('premise: the scan sees every build the card took out', () {
    // Lines as they stood on 2026-10-17, one of each shape.
    const built = [
      'horizontal ? Offset(at, rect.top) : Offset(rect.left, at),',
      'return cells.axis == Axis.horizontal\n'
          '    ? Offset(localPosition.dx.floorToDouble() + 0.5, '
          'localPosition.dy)\n'
          '    : Offset(localPosition.dx, '
          'localPosition.dy.floorToDouble() + 0.5);',
      '_horizontal ? Size(_windowExtent, 0) : Size(0, _windowExtent),',
      'horizontal\n'
          '    ? Rect.fromLTWH(\n'
          '        start,\n'
          '        size.height - readyBarThickness,\n'
          '        extent,\n'
          '        readyBarThickness,\n'
          '      )\n'
          '    : Rect.fromLTWH(',
      'horizontal\n'
          '    ? Rect.fromLTRB(start, 0, end, size.height)\n'
          '    : Rect.fromLTRB(0, start, size.width, end),',
      'final center = horizontal\n'
          '    ? place.center.translate(-originMain, 0)\n'
          '    : place.center.translate(0, -originMain);',
      'final box = horizontal\n'
          '    ? line.box.shift(Offset(-originMain, 0))\n'
          '    : line.box.shift(Offset(0, -originMain));',
      'begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,',
      'alignment: widget.axis == Axis.horizontal\n'
          '    ? Alignment.centerRight\n'
          '    : Alignment.bottomCenter,',
    ];
    for (final line in built) {
      expect(handBuildsIn(line), hasLength(1), reason: line);
    }
    expect(
      handBuildsIn('pressed ? Offset(0, step) : Offset(0, -step)'),
      isEmpty,
      reason: 'a pick that is not by the axis builds two values, not one',
    );
  });

  test('no file but the home builds a value by hand', () {
    final offenders = <String>[
      for (final file in dartFilesUnder('lib'))
        if (libPath(file) != home)
          for (final line in handBuildsIn(file.readAsStringSync()))
            '${libPath(file)}:$line',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'reach for offsetAlong / sizeAlong / rectAlong / centerStartAlong '
          '/ centerEndAlong',
    );
  });

  // ── The axis itself (card values-built-by-the-axis-are-one-function) ───
  //
  // The axis ACROSS a strip — `horizontal ? Axis.vertical :
  // Axis.horizontal` — was picked by hand on five lines in four files, and
  // one more picked the very axis it asked of (2026-10-17). Flutter says
  // the first once ([flipAxis]); the second is the axis. A ban.
  final pickedByHand = [
    // Asked of an axis, answered with one: the other, or the same.
    RegExp(
      r'Axis\.(?:horizontal|vertical)\s*\?\s*'
      r'Axis\.(?:horizontal|vertical)\s*:\s*Axis\.(?:horizontal|vertical)\b',
    ),
    // Asked of a flag named for the axis, answered with the OTHER one. The
    // same one is a flag turned into an axis, which is not a turn.
    RegExp(
      r'(?<![\w.])(?:\w*[Hh]orizontal\s*\?\s*Axis\.vertical\s*:\s*'
      r'Axis\.horizontal|\w*[Vv]ertical\s*\?\s*Axis\.horizontal\s*:\s*'
      r'Axis\.vertical)\b',
    ),
  ];

  List<int> axesPickedIn(String source) => linesMatching(pickedByHand, source);

  test('premise: the scan sees every axis the card took out', () {
    // Lines as they stood on 2026-10-17, one of each shape.
    const picked = [
      'axis: axis == Axis.horizontal ? Axis.vertical : Axis.horizontal,',
      'widget.axis == Axis.vertical ? Axis.horizontal : Axis.vertical;',
      'direction: axis == Axis.horizontal ? Axis.horizontal : Axis.vertical,',
      'axis: horizontal ? Axis.vertical : Axis.horizontal,',
    ];
    for (final line in picked) {
      expect(axesPickedIn(line), hasLength(1), reason: line);
    }
    const turnedInto = [
      // A flag, or an orientation, made the axis it names — not a turn.
      'vertical ? Axis.vertical : Axis.horizontal;',
      'widget.orientation == TimelineOrientation.horizontal\n'
          '    ? Axis.horizontal\n'
          '    : Axis.vertical;',
    ];
    for (final line in turnedInto) {
      expect(axesPickedIn(line), isEmpty, reason: line);
    }
  });

  test('no file picks an axis by hand', () {
    final offenders = <String>[
      for (final file in dartFilesUnder('lib'))
        for (final line in axesPickedIn(file.readAsStringSync()))
          '${libPath(file)}:$line',
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'reach for flipAxis, or for the axis itself',
    );
  });
}
