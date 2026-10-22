import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/canvas_traces.dart';
import 'package:anicel/src/ui/brush/cel_text_commands.dart';
import 'package:anicel/src/ui/brush/history_verbs.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// What the doors that show ↶ ↷ hear. Which of them a press opens is the
/// app's to show (`the_keys_reach_a_trace_in_the_viewer_test.dart`) and the
/// order they are asked in is pinned on the source
/// (`undo_asks_the_open_thing_first_test.dart`).
void main() {
  test("a viewer's trace is heard by the doors that show ↶ ↷ (F-380)",
      () async {
    final canvas = CanvasSelectionCommands();
    final viewer = CanvasSelectionCommands();
    final text = CelTextCommands();
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(() {
      session.dispose();
      text.dispose();
      viewer.dispose();
      canvas.dispose();
    });
    final verbs = HistoryVerbs(
      selection: canvas,
      traces: CanvasTraces([canvas, viewer]),
      text: text,
      session: session,
      contactIsDown: () => false,
      behindTheWaitWindow: (_, step) async => step(),
    );
    // What the fixtures had on its way is told before anything is listened
    // for: a channel tells on a microtask.
    await Future<void>.delayed(Duration.zero);
    var told = false;
    verbs.changes.addListener(() => told = true);

    viewer.addPolygonPoint(CanvasPoint(x: 0, y: 0));
    await Future<void>.delayed(Duration.zero);

    expect(told, isTrue);
  });
}
