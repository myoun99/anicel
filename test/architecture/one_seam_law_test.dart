import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/library_source.dart';

/// A ROW SEAM IS ONE LINE HOWEVER IT IS REACHED — AND A BEHAVIOUR TEST
/// CANNOT SAY SO.
///
/// `timelineGridRowSeamInk` names the seam once: `outlineVariant` at 1.0.
/// The storyboard rail used to spell it again — `BorderSide(outlineVariant)`,
/// whose default width is also 1.0. Same colour, same width, same pixels:
/// a golden, a pixel probe, a widget test comparing the two rails would
/// ALL have passed, and every one of them would have been measuring a
/// copy that merely happened to agree that day. Change the law's alpha or
/// its width and only the timeline moves.
///
/// 유저 F-18: 「스토리보드패널 타임라인이랑 그리드 다를거같은데 절대
/// 다르지 않도록 통일」. 「절대」 is a claim about the NEXT change, so the
/// test has to read the source, not the screen.
///
/// ↩️It read the storyboard rail's own `_stripRowLine`. I-44 took that
/// drawer away — every seam, in every panel, is drawn by the one grid sheet
/// now — so the guard reads "whatever draws that line now", as it asked:
/// the sheet's painter must take the seam from the law, and the storyboard
/// must mount the sheet rather than rule its rows again.
///
/// ⛔Deliberately narrow. Panel borders, dialog outlines and the lane
/// row's four-sided PLATE box also draw `outlineVariant` and are NOT
/// seams; forcing them through this law would be inventing a rule nobody
/// asked for.
void main() {
  test('the one grid sheet reads the seam law, and the storyboard mounts it '
      'instead of ruling its rows again', () {
    final law = File('lib/src/ui/timeline/timeline_beat_lines.dart');
    final storyboard = File('lib/src/ui/storyboard_panel.dart');
    for (final file in [law, storyboard]) {
      if (!file.existsSync()) {
        fail('${file.path} is missing — this test guards code it cannot find');
      }
    }

    final lawSource = law.readAsStringSync();
    final start = lawSource.indexOf('class TimelineGridSheetPainter');
    expect(
      start,
      isNot(-1),
      reason:
          'TimelineGridSheetPainter draws every row seam. If it was renamed, '
          'point this test at whatever draws that line now — do not delete '
          'the guard.',
    );
    // The class: from its head to the next top-level declaration.
    final classEnd = lawSource.indexOf('\n}', start);
    expect(classEnd, isNot(-1), reason: 'unterminated painter class');
    final body = lawSource.substring(start, classEnd);
    expect(
      body.contains('timelineGridRowSeamInk'),
      isTrue,
      reason:
          'The sheet must READ the seam law. Spelling the same colour by hand '
          'looks identical today and diverges silently the first time the '
          'law changes.',
    );
    expect(
      body.contains('outlineVariant'),
      isFalse,
      reason:
          'Naming the seam colour directly is the copy this guard exists to '
          'stop — take it from timelineGridRowSeamInk.',
    );

    // The storyboard LIBRARY (the file plus the parts it declares — the
    // audit's SRP cut put the rail rows in one): the sheet is mounted, and
    // no row carries a seam of its own again.
    final storyboardSource = librarySource(storyboard.path);
    expect(storyboardSource.contains('TimelineGridSheet('), isTrue);
    expect(
      storyboardSource.contains('timelineGridRowSeamInk'),
      isFalse,
      reason:
          'a storyboard that reads the seam ink is drawing a seam itself — '
          'the per-row line I-44 moved into the sheet',
    );
  });
}
