import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
/// ⛔Deliberately narrow. Panel borders, dialog outlines and the lane
/// row's four-sided PLATE box also draw `outlineVariant` and are NOT
/// seams; forcing them through this law would be inventing a rule nobody
/// asked for.
void main() {
  test('the storyboard rail reads the seam law instead of respelling it', () {
    final file = File('lib/src/ui/storyboard_panel.dart');
    if (!file.existsSync()) {
      fail('${file.path} is missing — this test guards code it cannot find');
    }
    // The rail is a part of the storyboard LIBRARY (the audit's SRP cut,
    // 2026-09-02): the scan reads the State's file plus every part beside
    // it, so the per-row seam is found wherever the cut put it.
    final parts = Directory('lib/src/ui/storyboard');
    final source = [
      file.readAsStringSync(),
      if (parts.existsSync())
        for (final part in parts.listSync())
          if (part is File && part.path.endsWith('.dart'))
            part.readAsStringSync(),
    ].join('\n');

    final start = source.indexOf('Widget _stripRowLine(');
    expect(
      start,
      isNot(-1),
      reason:
          '_stripRowLine is the storyboard rail\'s per-row seam. If it was '
          'renamed or inlined, point this test at whatever draws that line '
          'now — do not delete the guard.',
    );

    // The body: from the signature to the first line that closes a method
    // at class indentation. Short and single-purpose, so this is enough.
    final bodyEnd = source.indexOf('\n  }', start);
    expect(bodyEnd, isNot(-1), reason: 'unterminated _stripRowLine body');
    final body = source.substring(start, bodyEnd);

    expect(
      body.contains('timelineGridRowSeamInk'),
      isTrue,
      reason:
          'The storyboard rail must READ the seam law. Spelling the same '
          'colour by hand looks identical today and diverges silently the '
          'first time the law changes.',
    );
    expect(
      body.contains('outlineVariant'),
      isFalse,
      reason:
          'Naming the seam colour directly is the copy this guard exists to '
          'stop — take it from timelineGridRowSeamInk.',
    );
  });
}
