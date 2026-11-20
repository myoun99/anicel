import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/command.dart' show Command;
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

  /// 🗣️F-615: an open session lands through 확정's own door first — behind
  /// the wait window where it lands on many cels — and the document steps
  /// once that is down. ↩️The history manager's hook landed it inside the
  /// press, on the UI thread, whatever it landed on.
  for (final undo in [true, false]) {
    test('${undo ? 'an undo' : 'a redo'} waits for the session to land',
        () async {
      final canvas = CanvasSelectionCommands();
      final text = CelTextCommands();
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(() {
        session.dispose();
        text.dispose();
        canvas.dispose();
      });
      VoidCallback? landed;
      canvas.bind(
        session,
        hasSelection: () => false,
        deselect: () {},
        landPendingMoveThen: (then) => landed = then,
      );
      final verbs = HistoryVerbs(
        selection: canvas,
        traces: CanvasTraces([canvas]),
        text: text,
        session: session,
        contactIsDown: () => false,
        behindTheWaitWindow: (_, step) async => step(),
      );
      final history = session.historyManager;
      history.execute(_Mark());
      if (!undo) {
        history.undo();
      }
      final stepsBefore = (history.canUndo, history.canRedo);

      undo ? verbs.undo() : verbs.redo();

      expect(landed, isNotNull, reason: 'the press asked the door first');
      expect(
        (history.canUndo, history.canRedo),
        stepsBefore,
        reason: 'and took no step while the session was still landing',
      );
      landed!();
      expect(
        (history.canUndo, history.canRedo),
        undo ? (false, true) : (true, false),
        reason: 'the step it was pressed for, once the door was down',
      );
    });
  }
}

class _Mark implements Command {
  @override
  String get description => 'mark';

  @override
  void execute() {}

  @override
  void undo() {}
}
