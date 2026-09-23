import 'package:flutter_test/flutter_test.dart';
import '../../helpers/dart_sources.dart';

/// 🚨T4's own lesson, made un-reopenable.
///
/// `EditorSessionManager.standOnRow` says it in its doc: *「a wrapper is a
/// PLACE and every new door has to be told about it; a verb cannot be walked
/// around. Every surface that means 「여기 서라」 says it here」*. That is
/// exactly what went wrong twice — the law hung off the timeline host's
/// `onSelectLayer` wrapper and missed the doors calling the session directly
/// (T4), and then the ARROW-key step called `selectLayer` and missed it again
/// (F-13, 2026-08-27).
///
/// Twice is a pattern, and a pattern that keeps returning is not fixed by
/// fixing the third door. So the doors are counted here: anything outside the
/// session that moves the active row goes through the verb, or is written
/// down below with the reason it does not.
///
/// ⛔A behaviour test cannot do this job — it can only assert about doors
/// that already exist, and the failure mode is the door added NEXT week.
void main() {
  /// The verb and the state it drives live here; inside them `selectLayer`
  /// is the implementation, not a way around it.
  const owners = {
    'lib/src/ui/editor_session_manager.dart',
    'lib/src/controllers/layer_controller.dart',
  };

  /// ⚠️THE LEDGER. Each entry is a door that moves the active row WITHOUT
  /// the standing law, and each carries the reason it is not standing. Add
  /// a line only with a reason someone can be named for — 「~는 제외한다」
  /// with no author is a bug (CLAUDE.md).
  const allowed = <String, String>{
    // ↩️The attach group fold stood here (UI-R24 #4: the rail itself moved
    // the active row to the BASE). F-81 moved that hand-off into the
    // session's fold law, so the door is gone and so is its pass.
  };

  test('every door that moves the active row stands through the verb', () {
    final offenders = <String>[];

    for (final entity in dartFilesUnder('lib')) {
      final path = entity.path.replaceAll(r'\', '/');
      final relative = path.substring(path.indexOf('lib/'));
      if (owners.contains(relative)) {
        continue;
      }
      // A SESSION COLLABORATOR IS THE SESSION, split by file. It used to be
      // a `part of` the session library and the skip below said exactly
      // that; G0 (2026-09-06) made the collaborators libraries that take
      // the roles they need by constructor. The object graph did not move —
      // the same drags carry the same calls the verb makes on its own way
      // down — so the boundary this test draws is unchanged: it is doors
      // OUTSIDE the session that must stand through the verb.
      if (relative.startsWith('lib/src/ui/session/')) {
        continue;
      }
      final lines = entity.readAsLinesSync();
      if (lines.isNotEmpty &&
          lines.first.startsWith('part of ') &&
          owners.any((o) => lines.first.contains(o.split('/').last))) {
        continue;
      }
      var hits = 0;
      final where = <String>[];
      for (var i = 0; i < lines.length; i += 1) {
        // A CALL — `session.selectLayer(…)`. The declaration in the
        // controller reads `void selectLayer(`, which has no dot.
        if (!lines[i].contains('.selectLayer(')) {
          continue;
        }
        hits += 1;
        where.add('$relative:${i + 1}  ${lines[i].trim()}');
      }
      if (hits == 0) {
        continue;
      }
      final excuse = allowed[relative];
      if (excuse == null) {
        offenders.addAll(where);
      } else if (hits > 1) {
        // ⚠️The ledger excuses a door, not a file. A second call appearing
        // in an excused file is a new door wearing the old one's pass.
        offenders.addAll([
          'the ledger excuses ONE call in $relative and there are now $hits:',
          ...where,
        ]);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Something moves the active row without standing on it. 유저 '
          '2026-08-13: 「선택된게 풀리는거, 어떤 행이든 액티브 바꾸면 '
          '풀리도록」 — call `session.standOnRow(row)`, which is that law\'s '
          'house, or add the door to the ledger at the top of this file with '
          'the reason it is not standing.\n'
          '${offenders.join('\n')}',
    );
  });
}
