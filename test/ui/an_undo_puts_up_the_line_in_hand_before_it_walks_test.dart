import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️a-gesture-at-the-history-cap-does-not-fold-Q1 (「동작하나에 1줄」): a
/// gesture's line is up from its first step's place — and an undo pressed
/// while it is still being written puts it up BEFORE it asks where the step
/// was made (I-41), so the step it takes is the gesture's, where the user
/// stands, not a walk to the edit below it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an undo with a line in hand takes the line back where the user '
      'stands — no walk to the edit made elsewhere', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final row = s.requireActiveCut.layers.first.id;
    bool onSheet() =>
        requireLayerAnywhere(s.repository.requireProject(), row).onTimesheet;
    s.selectFrameIndex(0);
    s.layerSwitches.toggleLayerTimesheet(row);
    final was = onSheet();
    s.selectFrameIndex(2);
    expect(s.currentFrameIndex, 2, reason: '⛔premise: standing elsewhere');
    final line = s.historyManager.gestures.line('Hold');
    line.write(() => s.layerSwitches.toggleLayerTimesheet(row));
    expect(onSheet(), !was, reason: '⛔premise: the line wrote');

    s.undo();

    expect(
      (onSheet(), s.currentFrameIndex),
      (was, 2),
      reason: 'the line taken back here',
    );
    line.close();
  });
}
