import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★유저 규칙 (F-2, 2026-08-24): 「텍스트가 쓸데없이 설명적인 부분이
/// 너무 많음. … 쓸데없는 텍스트 싹 다 삭제하고 그 중에서 필요해보이는건
/// 툴팁으로 넣도록」 — ⛔no explanatory copy under a control. Warnings are
/// the exception; a caption that describes what the control already says is
/// not one.
///
/// The settings rows answered this STRUCTURALLY: `SettingsSwitchRow` takes
/// `help` and has nowhere to put it but a tooltip, so the rule cannot be
/// broken by writing one more `subtitle:`. What is left is the export
/// dialog's own caption helper, which has no such shape — so it is counted
/// instead.
///
/// ⛔A CENSUS, NOT A WALL. The captions standing today stay; the number may
/// only go DOWN. A new one has to argue itself in, in the same commit —
/// which is the point, because a caption is always one line and nobody is
/// ever asked about one line.
void main() {
  test('explanatory captions under controls do not multiply', () {
    final offenders = <String>[];

    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
      final path = file.path.replaceAll(r'\', '/');
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        final line = lines[i];
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('///')) {
          continue;
        }
        // The declaration itself is the carrier, not a caption.
        if (trimmed.startsWith('Widget exportModuleNote(')) {
          continue;
        }
        if (trimmed.contains('exportModuleNote(')) {
          offenders.add('$path:${i + 1}  ${trimmed}');
        }
      }
    }

    expect(
      offenders.length,
      lessThanOrEqualTo(_knownCaptions),
      reason:
          'A caption was added under a control. The rule is: no explanatory '
          'copy — put it in a tooltip, or let the control say it. If this '
          'one is a WARNING (the exception), say so and raise '
          '_knownCaptions in the same commit.\n${offenders.join('\n')}',
    );
    expect(
      offenders.length,
      greaterThanOrEqualTo(_knownCaptions),
      reason:
          'A caption went away — lower _knownCaptions to '
          '${offenders.length} so the census keeps its grip.',
    );
  });
}

/// The captions standing when this gate landed (2026-09-04), all six in the
/// export dialog and its modules: the timesheet format, the conte format,
/// the envelope paper, the separate-files note, and two in the shared
/// modules.
///
/// ⛔NOT DELETED HERE ON PURPOSE. Which of them earn their line is the
/// user's call — the audit's job was to stop a seventh arriving unasked.
const int _knownCaptions = 6;
