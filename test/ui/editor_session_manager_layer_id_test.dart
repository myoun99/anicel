import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// Layer ids have to be unique across the project a session is editing, and
/// the session mints them from a counter that starts at 1.
///
/// 🚩The bug this file was written for (feedback #30, a friend's working
/// file): the counter is SESSION state and the project arrives from disk, so
/// a project already holding `default-layer-2` gets a second one the moment
/// a layer is added. It surfaced as a red screen —
/// `Column(…) has multiple children with key
/// [<'timeline-rail-row-default-layer-2-row'>]` — but the duplicate key is
/// the symptom. The assertion here is on the ids, because that is the fact
/// that is wrong; a test on the widget key would go green the day someone
/// makes the rail tolerate collisions.
///
/// A new project cannot reproduce it: its ids and its counter come from the
/// same session. Reopening is the whole fixture.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qa-layer-id');
  });

  tearDown(() => directory.delete(recursive: true));

  List<LayerId> everyLayerId(EditorSessionManager session) => [
    for (final track in session.repository.requireProject().tracks)
      for (final cut in track.cuts)
        for (final layer in cut.layers) layer.id,
  ];

  void expectNoDuplicateIds(EditorSessionManager session, {String? reason}) {
    final ids = everyLayerId(session);
    expect(
      ids.length,
      ids.toSet().length,
      reason: reason ?? 'duplicate layer id in ${ids.map((i) => i.value)}',
    );
  }

  test('a layer added to a REOPENED project does not reuse an id the file '
      'already carries', () async {
    final path = '${directory.path}/scene.anicel';

    final first = EditorSessionManager(initialProject: createDefaultProject());
    first.addLayer();
    first.addLayer();
    first.addLayer();
    expectNoDuplicateIds(first, reason: 'precondition: one session is fine');
    final savedIds = everyLayerId(first).map((id) => id.value).toSet();
    expect(
      savedIds,
      contains('default-layer-2'),
      reason: 'fixture: the file must carry an id the fresh counter will '
          'reach, or reopening proves nothing',
    );
    await first.saveProjectToFile(path);
    first.dispose();

    // A NEW session: its counter starts at 1 again, knowing nothing about
    // the ids in the file it is about to open.
    final second = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(second.dispose);
    await second.openProjectFromFile(path);
    expectNoDuplicateIds(second, reason: 'precondition: the file is sound');

    second.addLayer();
    expectNoDuplicateIds(second);
  });

  test('the ids a reopened project mints keep climbing past the file', () async {
    final path = '${directory.path}/scene.anicel';

    final first = EditorSessionManager(initialProject: createDefaultProject());
    first.addLayer();
    first.addLayer();
    await first.saveProjectToFile(path);
    first.dispose();

    final second = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(second.dispose);
    await second.openProjectFromFile(path);
    // Several in a row: a fix that only skips the FIRST collision leaves the
    // second add colliding again.
    second.addLayer();
    second.addLayer();
    second.addLayer();
    expectNoDuplicateIds(second);
  });
}
