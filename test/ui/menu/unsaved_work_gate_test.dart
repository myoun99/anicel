import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/recent_projects.dart';
import 'package:anicel/src/services/persistence/recent_projects_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';

/// The one question both doors ask before a dirty session is torn down.
///
/// The window's close button had this gate; Open and the Recents rows —
/// which close the current project just as surely — did not, so one tap
/// on a recent row silently discarded every live edit. (After F-1 the
/// loss window is the whole autosave interval.) The gate is one shared
/// function now, with the exit tests' own `system-exit-*` keys, so the
/// matrix cell cannot re-open by one door forgetting.
void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('qa_unsaved_gate_');
  });
  tearDown(() {
    try {
      folder.deleteSync(recursive: true);
    } on Object {
      // A leaked handle on Windows must not fail the suite.
    }
  });

  Future<
    ({
      EditorSessionManager session,
      Future<bool> Function() ask,
    })
  >
  mounted(WidgetTester tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    return (
      session: session,
      ask: () => ensureUnsavedWorkSettled(context, session),
    );
  }

  testWidgets('a clean session passes with no question', (tester) async {
    final fixture = await mounted(tester);
    final settled = fixture.ask();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('system-exit-dialog')),
      findsNothing,
    );
    expect(await settled, isTrue);
  });

  testWidgets('a dirty session asks, and Cancel calls the whole thing off', (
    tester,
  ) async {
    final fixture = await mounted(tester);
    fixture.session.createCut();
    expect(fixture.session.hasUnsavedChanges, isTrue);

    final settled = fixture.ask();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('system-exit-dialog')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('system-exit-cancel')));
    await tester.pumpAndSettle();
    expect(await settled, isFalse);
    expect(
      fixture.session.hasUnsavedChanges,
      isTrue,
      reason: 'cancelling protects, it does not discard',
    );
  });

  testWidgets('discarding proceeds and retires the sidecar — 저장 안 하고 '
      '닫기 = 버리기 stays literal at this door too', (tester) async {
    final fixture = await mounted(tester);
    final path = '${folder.path.replaceAll('\\', '/')}/gate.anicel';
    await tester.runAsync(() => fixture.session.saveProjectToFile(path));
    fixture.session.createCut();
    await tester.runAsync(
      () => fixture.session.writeAutosaveSnapshot(
        fixture.session.autosaveSidecarPath!,
      ),
    );
    final sidecar = File(fixture.session.autosaveSidecarPath!);
    expect(sidecar.existsSync(), isTrue);

    final settled = fixture.ask();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('system-exit-close')));
    await tester.pumpAndSettle();

    expect(await settled, isTrue);
    expect(
      sidecar.existsSync(),
      isFalse,
      reason: 'a surviving sidecar must keep meaning "the app crashed"',
    );
  });

  testWidgets('the OPEN door is wired to the gate — a recents tap on a '
      'dirty session asks before discarding', (tester) async {
    // The WIRING, with real taps, because the function test above survives
    // the open flow simply not calling it — the exact hole this closes: a
    // one-tap recent open silently discarded the whole dirty session.
    final path = '${folder.path.replaceAll('\\', '/')}/Elsewhere.anicel';
    File(path).writeAsStringSync('stub — the gate fires before any open');
    final seeded = const RecentProjects().withOpened(
      RecentProject(path: path),
    );
    AppRecent.projects.value = seeded;
    RecentProjectsStore().save(seeded);
    addTearDown(() {
      AppRecent.projects.value = const RecentProjects();
      RecentProjectsStore().save(const RecentProjects());
    });

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump();
    // Any command dirties the session; the new-frame button is the
    // cheapest one on the toolbar (the exit-gate test's idiom).
    final newFrame = find.byKey(const ValueKey<String>('new-frame-button'));
    await tester.ensureVisible(newFrame);
    await tester.pumpAndSettle();
    await tester.tap(newFrame);
    await tester.pumpAndSettle();

    final projectButton = find.byKey(
      const ValueKey<String>('top-strip-project-button'),
    );
    await tester.ensureVisible(projectButton);
    await tester.pumpAndSettle();
    await tester.tap(projectButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>('menu-recent-$path')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('system-exit-dialog')),
      findsOneWidget,
      reason: 'opening another project closes this one as surely as the '
          'window\'s X — same question, same window',
    );
    await tester.tap(find.byKey(const ValueKey<String>('system-exit-cancel')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('recover-autosave-dialog')),
      findsNothing,
      reason: 'cancel stops the open before it starts',
    );
  });
}
