import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The fields a `.anicel` carries beside the project travel as ONE value on
/// the read side, the way they already do on the write side.
///
/// The write side became one value in F-123 (`AnicelSessionFields`, seven
/// signatures collapsed to one). The read side kept three carriers — the
/// decoded document, the whole-archive parse and the open result — each
/// holding grants, fingerprints and the resume point as its own fields, so
/// a fourth session field meant five edits, and the whole-archive parse had
/// already dropped the resume point on the way (session-fields-read-side,
/// 2026-09-16).
///
/// This reads the three carriers' source: none of them may declare one of
/// the session fields on its own; each holds `session` instead.
void main() {
  test('the read-side carriers hold the session fields as one value', () {
    const carriers = {
      'lib/src/services/persistence/anicel_project_archive.dart': [
        'AnicelArchiveContents',
        'AnicelProjectDocument',
      ],
      'lib/src/services/persistence/anicel_file_service.dart': [
        'AnicelOpenResult',
      ],
    };
    // ⚠️Anywhere in the line and with or without an initializer — a field
    // declared as `final X resume = const {};`, or beside another on the
    // same line, is the same field. The first shape of this pattern wanted
    // the line to END in `resume;`, and a mutant with an initializer walked
    // through it (2026-09-16).
    final ownField = RegExp(
      r'\bfinal\s+[^;=]+\b(grants|mediaFingerprints|resume)\b\s*[=;]',
    );
    final offenders = <String>[];
    for (final entry in carriers.entries) {
      final source = File(entry.key).readAsStringSync();
      for (final carrier in entry.value) {
        final start = source.indexOf('class $carrier ');
        expect(start, greaterThanOrEqualTo(0), reason: '$carrier is gone');
        final end = source.indexOf('\n}', start);
        final body = source.substring(start, end);
        for (final line in body.split('\n')) {
          if (ownField.hasMatch(line)) {
            offenders.add('$carrier: ${line.trim()}');
          }
        }
        if (!body.contains('AnicelOpenedSessionFields session;')) {
          offenders.add('$carrier: no `session` value');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'a session field rides a carrier on its own — add it to '
          'AnicelOpenedSessionFields instead, once',
    );
  });
}
