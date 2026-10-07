@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

/// 🚨EVERY WRITER OF A CUT LAYOUT CARRIES THE TRANSITION ROWS.
///
/// 🗣️유저 2026-08-10: 「움직일때만 앵커로서 앞 컷에 앵커」. A cut moves
/// through a trim, a gap, a delete, a reorder, a new cut, a duplicate, an
/// import — and until F-227-ol-follows not one of them carried the O.L drawn
/// across its boundary, so every move left the O.L behind. The carrying
/// lives in the commands that write the layout (`TransitionsRideTheCuts`),
/// not in their doors; this holds the next writer to it.
///
/// ⚠️It reads the repository's layout verbs, and the ONE INSERTION's two
/// writes on a project (`projectWithCutInserted` · `projectWithCutTakenOut`)
/// — since 2026-10-08 a new cut goes in by one `updateProject`, the linked
/// cut's command with it, so the insertion and that command are seen by
/// those two names. A command that writes the layout some OTHER way inside
/// an `updateProject` is not seen here;
/// `a_layout_command_carries_the_transitions_test` drives the ones there
/// are.
void main() {
  test('a file that writes a cut layout — by the repository\'s verbs or by '
      'the one insertion — carries the transitions', () {
    final writers = <String>[];
    final bare = <String>[];
    for (final entity in dartFilesUnder('lib')) {
      final path = entity.path.replaceAll(r'\', '/');
      if (path.endsWith('lib/src/services/project_repository.dart')) {
        // The verbs themselves.
        continue;
      }
      final source = entity.readAsStringSync();
      if (!_layoutWrite.hasMatch(source)) {
        continue;
      }
      writers.add(path);
      if (!source.contains('TransitionsRideTheCuts')) {
        bare.add(path);
      }
    }
    expect(
      writers.length,
      greaterThanOrEqualTo(6),
      reason: 'LIVENESS — the scan reads the writers it is about',
    );
    expect(
      writers,
      containsAll(<Matcher>[
        endsWith('lib/src/services/commands/cut_insertion.dart'),
        endsWith('lib/src/services/commands/create_linked_cut_command.dart'),
      ]),
      reason: 'the insertion and the linked cut are writers by NAME — a '
          'count would not say which ones it lost',
    );
    expect(
      bare,
      isEmpty,
      reason:
          'a command that moves cuts carries every track\'s transition row '
          'with them (TransitionsRideTheCuts) — run its move through carry '
          'and its undo through carryBack',
    );
  });
}

/// A write that changes where cuts stand on a track: a repository verb, or
/// one of the insertion's two writes on a project.
final _layoutWrite = RegExp(
  r'\b_?repository\.(insertCut|removeCut|setCutOrder|reorderCut|'
  r'updateCutDuration|updateCutLeadingGap|addCut)\(|'
  r'\bprojectWithCut(Inserted|TakenOut)\(',
);
