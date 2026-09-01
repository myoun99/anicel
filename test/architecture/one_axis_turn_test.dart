import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

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

  Iterable<File> dartFilesUnder(String dir) sync* {
    for (final entity in Directory(dir).listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) yield entity;
    }
  }

  String rel(File f) {
    final p = f.path.replaceAll(r'\', '/');
    return p.substring(p.indexOf('lib/'));
  }

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
        if (handTurnsIn(file).isNotEmpty) rel(file),
    };
    expect(seen, isNotEmpty);
  });

  test('no file outside the ledger turns a box by hand', () {
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib')) {
      final path = rel(file);
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
}
