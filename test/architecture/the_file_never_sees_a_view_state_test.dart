import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★**THE FILE NEVER SEES A VIEW STATE** (F-153).
///
/// 🗣️유저 2026-09-18: 「활성레이어 솔로는 **저장시 저장안되도록**. 지금 솔로
/// on한상태로 저장하고 열면 **적용된채로 모드는 off**되있는 상태」 — answered
/// on `solo-and-the-saved-file` with 「**저장이 솔로 이전의 눈을 기록한다**」.
///
/// ⛔**A BEHAVIOUR TEST CANNOT COVER THIS.** The pin beside it
/// (`test/services/persistence/the_file_never_sees_the_solo_test.dart`)
/// drives the roads that exist; a NEW road that read the live project for
/// itself would pass it untouched. Which road reads the project is a
/// SOURCE fact, and the door has four roads that all end at one writer.
///
/// 🚨SO THE LEDGER IS THE TEST. Every member of the door that reads the
/// live project earns a line here saying whether it writes a file. A save
/// road that is not `_carryFor` is the bug this round was.
void main() {
  const door = 'lib/src/ui/session/project_file_door.dart';

  /// 🚨THE LEDGER. Measured 2026-09-23: two.
  const allowed = <String, String>{
    '_carryFor':
        'THE save road, and the ONLY one — it hands the project through '
        'VisibilitySolo.projectAsSavedWithoutSolo on the way into the '
        '_SaveCarry every road is given',
    'warmAudioConforms':
        'an OPEN-time read: it warms the waveform conforms off the audio '
        'paths and writes no file at all',
  };

  /// A member declaration at class level: two spaces of indent, a return
  /// type, a name, then its parameter list or body. Deliberately crude — a
  /// line it misreads shows up as a ledger mismatch, which is this test
  /// working.
  ///
  /// ⚠️The prefix must START on a word character. Letting it begin with
  /// `\s` let it swallow a body line's indent, and the first run read a
  /// CALL four levels in (`projectAudioSourcePaths`) as the member.
  final memberHead = RegExp(
    r'^  (?:[\w<>?][\w<>?,\s\[\]]* )?([_a-zA-Z]\w*)\s*[({]',
  );

  test('only the ledger reads the live project inside the .anicel door', () {
    final readers = <String>{};
    var member = '(outside any member)';
    for (final line in File(door).readAsLinesSync()) {
      final head = memberHead.firstMatch(line);
      if (head != null) {
        member = head.group(1)!;
      }
      if (line.contains('requireProject()')) {
        readers.add(member);
      }
    }

    expect(
      readers.toList()..sort(),
      allowed.keys.toList()..sort(),
      reason:
          '🚨유저: 「저장이 솔로 이전의 눈을 기록한다」. A save that reads '
          'the live project reads the SOLO\'s eyes. Take the project from '
          'the _SaveCarry, or add a line to the ledger saying why this '
          'member is not a write.',
    );
  });

  test('and the writer is handed that project, not the live one', () {
    final source = File(door).readAsStringSync();
    // The one call to AnicelFileService.save: its `project:` argument.
    final argument = RegExp(
      r'_anicelFileService\.save\(\s*\n\s*project: ([^,\n]+),',
    ).allMatches(source).map((m) => m.group(1)).toList();

    expect(
      argument,
      ['carry.project'],
      reason:
          'the carry is made once per save by _carryFor; anything else '
          'here is a second answer to 「which project is being written」',
    );
  });
}
