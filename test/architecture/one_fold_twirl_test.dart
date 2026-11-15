import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨★★ONE FOLD TWIRL, ANSWERED ONCE.
///
/// A folder folds its members; an attach base folds its attach rows
/// (UI-R20 #9), by halves since I-175. Three answers — is there a twirl, is
/// it open, what does it toggle — and both grids' headers used to derive
/// all three inline, each with its own `row.isFolder ? … : …`. Same three
/// ternaries in two files, plus a third half-copy in the rail row's memo
/// record.
///
/// [timelineGroupFoldFor] is the one place the three are answered — the
/// row's `groupFold` face and its `onToggleGroupFold`. This scan says
/// nobody re-derives them: a header that writes `groupFold:` from
/// `isFolder` has started the fourth copy.
void main() {
  const home = 'lib/src/ui/timeline/timeline_layer_controls_row.dart';
  final reDerivation = RegExp(
    r'\b(groupFold|onToggleGroupFold)\s*:[^,]*isFolder',
  );

  test('premise: the fold has its one home', () {
    expect(
      File(home).readAsStringSync(),
      contains('timelineGroupFoldFor('),
      reason: 'the scan below assumes the shared function lives here',
    );
  });

  test('no header derives the fold twirl from isFolder itself', () {
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib')) {
      final text = file.readAsStringSync();
      for (final m in reDerivation.allMatches(text)) {
        final line = text.substring(0, m.start).split('\n').length;
        offenders.add('${libPath(file)}:$line ${m.group(1)}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'ask timelineGroupFoldFor once and pass its three answers',
    );
  });
}
