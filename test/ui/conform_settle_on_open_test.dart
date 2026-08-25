import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The conform cache settles ON PROJECT OPEN — the store lets go of its
/// disk-backed PCM and the collector prunes, in that order, so the prune
/// can never delete a file out from under a live streaming entry.
///
/// What a test can reach from here is the TRIGGER: an open must settle,
/// and deleting the `_settleConformCache` call kept every suite green
/// before this file. The order of the two lines inside it is pinned by
/// the decision comment alone — the collector's budget is the shipped
/// 2GB constant at this call site, so no test-sized fixture can make the
/// prune delete anything and the wrong order stays unobservable in a
/// test. (The constant itself is pinned in conform_cache_maintenance_test.)
void main() {
  test('opening a project settles the conform cache', () async {
    final directory = Directory.systemTemp.createTempSync('qa_settle_open_');
    addTearDown(() {
      try {
        directory.deleteSync(recursive: true);
      } on Object {
        // Windows handles.
      }
    });
    final spy = _ReleaseSpyStore();
    final s = EditorSessionManager(
      initialProject: createDefaultProject(),
      audioConformStore: spy,
    );
    addTearDown(s.dispose);
    final path = '${directory.path.replaceAll('\\', '/')}/scene.anicel';
    await s.saveProjectToFile(path);

    spy.releases = 0;
    await s.openProjectFromFile(path);

    expect(
      spy.releases,
      greaterThan(0),
      reason: 'the open is the one moment the cache bound is enforced — '
          'unhooked, the cache grows without limit for the whole session',
    );
  });
}

class _ReleaseSpyStore extends AudioConformStore {
  _ReleaseSpyStore()
      : super(
          resolveConformPath: (_) => null,
          runner: (request) async => const ConformResult(
            outcome: ConformOutcome.undecodable,
            error: 'test stub',
          ),
          log: (_) {},
        );

  int releases = 0;

  @override
  void releaseDiskBacked() {
    releases += 1;
    super.releaseDiskBacked();
  }
}
