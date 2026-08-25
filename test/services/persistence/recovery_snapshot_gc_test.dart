import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_save_settings.dart';
import 'package:anicel/src/services/persistence/project_autosave_service.dart';

/// Q-recovery-gc (유저 08-26: 「30일좋고」): a snapshot whose project was
/// deleted or moved outside the app misses all three retirement moments,
/// so a launch-time sweep takes what nothing else ever will — and the
/// Preferences list is the by-hand door for everything younger.
void main() {
  late Directory recovery;

  setUp(() {
    recovery = Directory(AppSave.recoveryDirectory())
      ..createSync(recursive: true);
  });
  tearDown(() {
    try {
      recovery.deleteSync(recursive: true);
    } on Object {
      // Windows handles.
    }
  });

  File aged(String name, Duration age, {String bytes = 'overlay'}) {
    final file = File('${recovery.path}/$name')..writeAsStringSync(bytes);
    file.setLastModifiedSync(DateTime.now().subtract(age));
    return file;
  }

  test('the sweep takes only what 30 days abandoned — write temps '
      'included, young snapshots left alone', () {
    final old = aged('Old.anicel.aabbccdd.autosave', const Duration(days: 40));
    final oldTemp = aged(
      'Old.anicel.aabbccdd.autosave.tmp-123',
      const Duration(days: 40),
    );
    final young = aged('New.anicel.11223344.autosave', const Duration(days: 5));

    final swept = ProjectAutosaveService.sweepAbandonedRecovery();

    expect(swept, 2);
    expect(old.existsSync(), isFalse);
    expect(
      oldTemp.existsSync(),
      isFalse,
      reason: 'the post-rename temp sweep only runs on a later write of the '
          'SAME project, which an abandoned project never gets',
    );
    expect(young.existsSync(), isTrue);
  });

  test('an empty or absent folder sweeps to zero, quietly', () {
    expect(ProjectAutosaveService.sweepAbandonedRecovery(), 0);
    recovery.deleteSync(recursive: true);
    expect(ProjectAutosaveService.sweepAbandonedRecovery(), 0);
  });

  test('the list decodes names, resolves known paths, skips temps, and '
      'sorts newest first', () {
    const knownPath = '/drive/작업/scene.anicel';
    final knownSnapshot = File(AppSave.recoveryPathFor(knownPath))
      ..writeAsStringSync('known');
    knownSnapshot.setLastModifiedSync(
      DateTime.now().subtract(const Duration(days: 2)),
    );
    aged('Cut 12.anicel.deadbeef.autosave', const Duration(days: 9));
    aged('ignored.tmp-42', const Duration(days: 1));

    final rows = ProjectAutosaveService.listRecoverySnapshots(
      knownProjectPaths: const [knownPath],
    );

    expect(rows, hasLength(2), reason: 'the temp is a write, not a snapshot');
    expect(rows.first.projectPath, knownPath, reason: 'newest first');
    expect(rows.first.projectName, 'scene.anicel');
    expect(rows.first.bytes, 5);
    expect(
      rows.last.projectPath,
      isNull,
      reason: 'an orphan has only its decoded name — the file name holds a '
          'hash of the path, not the path',
    );
    expect(rows.last.projectName, 'Cut 12.anicel');
  });
}
