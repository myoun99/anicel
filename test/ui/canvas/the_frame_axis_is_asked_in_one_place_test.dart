import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F-28's law, guarded the only way that survives me: by making a second
/// copy fail rather than by trusting anyone to notice one.
///
/// 유저 2026-08-27: 「진짜 사본만드는거 몇번이나 금지했는데 … 나중에 사본
/// 만들고 제어못해서 결국 사본 남으면 진짜 용서안할게」.
///
/// 🚨The question — 「이 방향으로 한 칸 가면 프레임인가 행인가」 — is the frame
/// axis, and it is sideways on the timeline and downward on the X-sheet. It
/// had exactly one home and grew a second: #1216 taught the flip gesture to
/// read the sheet, the keyboard was never told, and the two disagreed for a
/// fortnight. Writing the answer down twice is how that happens, so the
/// answer may be written down once.
///
/// ⛔This scans SOURCE rather than behaviour on purpose. A behavioural test
/// passes just as happily with two copies that currently agree — and two
/// copies that currently agree is precisely the state this is about.
void main() {
  test('the frame axis is computed in ONE place — nothing else may compare '
      'against `framesRunVertically`', () {
    // The one home. Everything else asks it through `framesRunAlong`.
    const home = 'lib/src/ui/canvas/flip_hud_controller.dart';
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll(r'\', '/');
      if (path.endsWith(home)) {
        continue;
      }
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        final line = lines[i];
        if (!line.contains('framesRunVertically')) {
          continue;
        }
        // ⚠️A WRITE is not the offence — the workspace has to be able to say
        // which way this sheet runs. Re-deriving the ANSWER is.
        final trimmed = line.trim();
        final writes =
            trimmed.contains('framesRunVertically =') &&
            !trimmed.contains('==') &&
            !trimmed.contains('!=');
        if (writes) {
          continue;
        }
        offenders.add('$path:${i + 1}  $trimmed');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Something reads `framesRunVertically` to work the axis out for '
          'itself. Ask `flipHud.framesRunAlong(horizontal: …)` instead — the '
          'flip and the arrow keys disagreed for a fortnight because that '
          'answer was written down in two places, and two copies that agree '
          'today are the ones that stop agreeing later.\n'
          '${offenders.join('\n')}',
    );
  });
}
