import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 🚨★★THE SWEEPABLE COLUMNS ARE ONE LIST.
///
/// 유저 2026-08-29: 「버튼이면 다 가능하도록」·「로직적으로 다른규칙 두지말고
/// 통일」. The rail and the x-sheet each built their own list of the five
/// columns a bulk-drag can paint, over different subjects, and they drifted:
/// the rail read the twirl state a frame stale, the sheet could not sweep a
/// lane group's fx. `timelineSwipeColumns` is the one list; a grid that
/// calls the geometry ([railSwipeColumns]) with a list of its own has
/// started the second copy again.
///
/// The storyboard's rail sweeps its OWN row kind (StoryboardRailRow) and is
/// listed — a ledger line, not a licence.
void main() {
  const home = 'lib/src/ui/timeline/timeline_swipe_columns.dart';
  const ledger = <String>{'lib/src/ui/storyboard_panel.dart'};

  Iterable<File> dartFilesUnder(String dir) sync* {
    for (final entity in Directory(dir).listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) yield entity;
    }
  }

  String rel(File f) {
    final p = f.path.replaceAll(r'\', '/');
    return p.substring(p.indexOf('lib/'));
  }

  /// Lines that CALL the geometry (not its declaration, not a doc link).
  List<int> callsIn(File file) {
    final lines = file.readAsLinesSync();
    return [
      for (var i = 0; i < lines.length; i++)
        if (RegExp(r'\brailSwipeColumns<\w+>\(').hasMatch(lines[i]) &&
            !lines[i].trimLeft().startsWith('//') &&
            !lines[i].contains('railSwipeColumns<TRow>('))
          i + 1,
    ];
  }

  test('premise: the home calls the geometry once', () {
    expect(callsIn(File(home)), hasLength(1));
  });

  test('no grid builds a swipe list of its own', () {
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib')) {
      final path = rel(file);
      if (path == home || ledger.contains(path)) continue;
      for (final line in callsIn(file)) {
        offenders.add('$path:$line');
      }
    }
    expect(offenders, isEmpty, reason: 'ask timelineSwipeColumns');
  });

  test('both grids delegate to the one list', () {
    for (final path in [
      'lib/src/ui/timeline/layer_timeline_grid.dart',
      'lib/src/ui/timeline/xsheet_timeline_grid.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains('timelineSwipeColumns('),
        reason: '$path sweeps through the shared list',
      );
    }
  });
}
