// TOGGLING A LAYER'S TIMESHEET FLAG FLIPS IT, AND THE FLIP IS AN EDIT.
//
// A survivor of the mutation campaign (2026-09-03): the coordinator's
// no-op guard (`layer.onTimesheet == onTimesheet → return`) became `!=`,
// so a real flip returned early and only a no-op reached the history.
// Nothing noticed; this pins the flip and its undo through the session.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

void main() {
  test('the toggle flips the flag and undo puts it back', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final layerId = session.layers.first.id;
    bool onTimesheet() => requireLayerAnywhere(
      session.repository.requireProject(),
      layerId,
    ).onTimesheet;
    final before = onTimesheet();
    final undoDepthBefore = session.historyManager.canUndo;

    session.toggleLayerTimesheet(layerId);
    expect(onTimesheet(), !before, reason: 'the toggle flips the flag');
    expect(session.historyManager.canUndo, isTrue, reason: 'a flip is an edit');

    session.historyManager.undo();
    expect(onTimesheet(), before);
    expect(session.historyManager.canUndo, undoDepthBefore);
  });
}
