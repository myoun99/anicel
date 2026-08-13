import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';

/// 🔑 THE WIRING — the part the user actually presses.
///
/// The window and the percentage are each tested where they live. What was
/// missing is the thing between them: that a manual save GOES THROUGH the
/// window at all, and that the contract the exit gate depends on — a bool
/// saying whether the file was written — tells the truth.
///
/// Every manual save in the app funnels through [saveProjectShowingProgress]
/// so this cannot be true of one button and false of another. That funnel
/// is why the exit path stopped throwing past its own return, so its
/// failure branch is a tested branch here rather than a hopeful one.
void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('qa-save-progress-ui-');
  });

  tearDown(() {
    try {
      directory.deleteSync(recursive: true);
    } on Object {
      // Windows handles.
    }
  });

  /// Runs [action] inside a real Navigator + ScaffoldMessenger, which the
  /// window and the error notice both need, and answers whether the window
  /// was ever on screen.
  ///
  /// ⚠️ `runAsync` and hand-rolled pumping, NOT `pumpAndSettle`. A real save
  /// crosses into an isolate, which needs real time that the fake clock
  /// never grants — and the window holds a turning spinner, which is an
  /// animation that never settles, so `pumpAndSettle` would time out even if
  /// the save could finish. Both halves of that are why this harness looks
  /// the way it does.
  Future<({bool? result, bool sawWindow})> runSave(
    WidgetTester tester,
    Future<bool> Function(BuildContext context) action,
  ) async {
    bool? result;
    var done = false;
    var sawWindow = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await action(context);
                done = true;
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('go'));
      // Polled rather than sampled once: a small project saves fast, and a
      // single look after a fixed number of pumps would be a race about
      // machine speed rather than about the window.
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (!done && DateTime.now().isBefore(deadline)) {
        await tester.pump();
        if (find
            .byKey(const ValueKey<String>('save-progress-dialog'))
            .evaluate()
            .isNotEmpty) {
          sawWindow = true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pump();
    await tester.pump();
    expect(done, isTrue, reason: 'the save never came back');
    return (result: result, sawWindow: sawWindow);
  }

  EditorSessionManager session() =>
      EditorSessionManager(initialProject: createDefaultProject());

  testWidgets('a manual save is seen happening, and says so when it lands', (
    tester,
  ) async {
    final s = session();
    final path = '${directory.path.replaceAll('\\', '/')}/scene.anicel';

    final run = await runSave(
      tester,
      (context) => saveProjectShowingProgress(context, s, path),
    );

    expect(
      run.sawWindow,
      isTrue,
      reason: 'the save ran with nothing in front of it',
    );
    expect(run.result, isTrue);
    expect(File(path).existsSync(), isTrue, reason: 'and it really wrote');
    expect(
      find.byKey(const ValueKey<String>('save-progress-dialog')),
      findsNothing,
      reason: 'the window does not outstay the save',
    );
  });

  testWidgets('🚨 a save that FAILS reports false and leaves no window up', (
    tester,
  ) async {
    // The contract the exit gate leans on. Before the funnel this path threw
    // straight over `return !hasUnsavedChanges`, so "save and quit" on a
    // failing disk neither saved nor said anything — and a modal that
    // outlived the failure would have hidden the notice as well.
    final blocker = File('${directory.path}/blocker')..createSync();
    final impossible = '${blocker.path.replaceAll('\\', '/')}/scene.anicel';
    final s = session();

    final run = await runSave(
      tester,
      (context) => saveProjectShowingProgress(context, s, impossible),
    );

    expect(run.result, isFalse);
    expect(
      find.byKey(const ValueKey<String>('save-progress-dialog')),
      findsNothing,
      reason: 'a failure that leaves the modal up is a spinner for ever',
    );
    expect(
      find.byType(SnackBar),
      findsOneWidget,
      reason: 'and the user is told, from a screen that can be seen again',
    );
  });

  testWidgets('the project is still dirty after a failed save', (tester) async {
    // What the exit gate actually reads. If a failed save left the session
    // looking clean, "save and quit" would quit.
    final blocker = File('${directory.path}/blocker2')..createSync();
    final s = session();
    s.createCut();
    expect(s.hasUnsavedChanges, isTrue);

    await runSave(
      tester,
      (context) => saveProjectShowingProgress(
        context,
        s,
        '${blocker.path.replaceAll('\\', '/')}/scene.anicel',
      ),
    );

    expect(
      s.hasUnsavedChanges,
      isTrue,
      reason: 'the work is not in a file, so the close must be called off',
    );
    // An edited session schedules work of its own; the binding checks for
    // stray timers before teardown runs, so it has to go down in the body.
    s.dispose();
    await tester.pump();
  });
}
