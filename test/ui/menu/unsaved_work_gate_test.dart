import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/services/persistence/open_project_file.dart';
import 'package:anicel/src/services/persistence/recent_projects.dart';
import 'package:anicel/src/services/persistence/recent_projects_store.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import '../../helpers/temp_dir.dart';

/// The one question both doors ask before a session is torn down:
/// **will the work survive it?**
///
/// The window's close button had this gate; Open and the Recents rows —
/// which close the current project just as surely — did not, so one tap
/// on a recent row silently discarded every live edit. (After F-1 the
/// loss window is the whole autosave interval.) The gate is one shared
/// function now, with the exit tests' own `system-exit-*` keys, so the
/// matrix cell cannot re-open by one door forgetting.
///
/// 🚨And the question is no longer 「are there unsaved edits」: a saved
/// cel is a ref into the `.anicel`, so a session with nothing unsaved
/// still has drawings that only exist while it holds that file open.
/// The last two tests are that half.
void main() {
  late Directory folder;
  /// ONE mouse per test (see `editor_top_strip_test`): a second
  /// `addPointer` for the same device trips `MouseTracker`'s assertion.
  TestGesture? hoverMouse;

  /// F-146: the recents moved INSIDE a 「최근 프로젝트」 row, and the flyout's
  /// second level opens on hover.
  Future<void> hoverRecents(WidgetTester tester) async {
    final row = find.byKey(const ValueKey<String>('menu-recent-projects'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    if (hoverMouse == null) {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      hoverMouse = mouse;
      addTearDown(() async {
        await mouse.removePointer();
        hoverMouse = null;
      });
    }
    await hoverMouse!.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    await hoverMouse!.moveTo(tester.getCenter(row));
    await tester.pumpAndSettle();
  }


  setUp(() {
    folder = Directory.systemTemp.createTempSync('qa_unsaved_gate_');
  });
  tearDown(() => deleteTempQuietly(folder));

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
    fixture.session.cutVerbs.createCut();
    expect(fixture.session.projectFile.hasUnsavedChanges, isTrue);

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
      fixture.session.projectFile.hasUnsavedChanges,
      isTrue,
      reason: 'cancelling protects, it does not discard',
    );
  });

  testWidgets('discarding proceeds, and the session stands the autosave '
      'tick down on the way out', (tester) async {
    // 「저장 안 하고 닫기 = 버리기」 is the OFF position of the autosave
    // switch now, but the moment the user answers Close it has to hold: the
    // tear-down that follows delivers the same lifecycle callbacks any
    // close does, and a tick coming due in there would save the very work
    // just discarded.
    //
    // 🪦It asserted a deleted SIDECAR here. The retirement was the whole
    // body of this door's discard until 2026-09-08; the stand-down was
    // always the half that mattered, and it is all that is left.
    final fixture = await mounted(tester);
    final path = '${folder.path.replaceAll(r'\', '/')}/gate.anicel';
    await tester.runAsync(
      () => fixture.session.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson),
    );
    fixture.session.cutVerbs.createCut();
    expect(fixture.session.projectFile.autosaveShouldStandDown, isFalse);

    final settled = fixture.ask();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('system-exit-close')));
    await tester.pumpAndSettle();

    expect(await settled, isTrue);
    expect(
      fixture.session.projectFile.autosaveShouldStandDown,
      isTrue,
      reason: 'the exit lifecycle is still to come, and it must not save '
          'what the user just threw away',
    );
  });

  /// Drives [ask] through a REAL save: taps [buttonKey] on the gate window
  /// and pumps real time until the whole thing settles — the save crosses
  /// into an isolate and the progress window spins, so neither the fake
  /// clock nor pumpAndSettle can finish it (save_shows_progress_test's
  /// harness, folded in).
  Future<bool> settleThroughRealSave(
    WidgetTester tester,
    Future<bool> Function() ask,
    String buttonKey,
  ) async {
    late bool settled;
    var done = false;
    await tester.runAsync(() async {
      final future = ask().then((value) {
        settled = value;
        done = true;
      });
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey<String>(buttonKey)));
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (!done && DateTime.now().isBefore(deadline)) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await future;
    });
    await tester.pump();
    expect(done, isTrue, reason: 'the gate never came back');
    return settled;
  }

  testWidgets('Save inside the gate writes the file and lets the tear-down '
      'proceed', (tester) async {
    // The drive-through the presence tests never took: the gate's bool is
    // what the close reads, and a gate that answered true without the
    // bytes landing would quit past an unsaved project.
    final fixture = await mounted(tester);
    final path = '${folder.path.replaceAll('\\', '/')}/gate-save.anicel';
    await tester.runAsync(() => fixture.session.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson));
    final savedLength = File(path).lengthSync();
    fixture.session.cutVerbs.createCut();
    expect(fixture.session.projectFile.hasUnsavedChanges, isTrue);

    final settled = await settleThroughRealSave(
      tester,
      fixture.ask,
      'system-exit-save',
    );

    expect(settled, isTrue);
    expect(fixture.session.projectFile.hasUnsavedChanges, isFalse);
    expect(
      File(path).lengthSync(),
      greaterThan(savedLength),
      reason: 'the new cut is really in the file, not just flagged saved',
    );
    fixture.session.dispose();
    await tester.pump();
  });

  testWidgets('🚨 a save that FAILS inside the gate calls the close off', (
    tester,
  ) async {
    // The regression the funnel exists to prevent, asserted AT the gate:
    // "save and quit" on a failing disk must neither quit nor lie.
    final fixture = await mounted(tester);
    final path = '${folder.path.replaceAll('\\', '/')}/gate-fail.anicel';
    await tester.runAsync(() async {
      await fixture.session.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);
      // The project path turns into a DIRECTORY: every later write —
      // incremental append and the full rewrite's rename alike — refuses.
      // The session holds the file it saved; only a descriptor that died
      // with it would let the path change under us like this.
      OpenProjectFile.instance.release();
      File(path).deleteSync();
      Directory(path).createSync();
    });
    fixture.session.cutVerbs.createCut();

    final settled = await settleThroughRealSave(
      tester,
      fixture.ask,
      'system-exit-save',
    );

    expect(settled, isFalse, reason: 'nothing landed, so nothing may close');
    expect(
      fixture.session.projectFile.hasUnsavedChanges,
      isTrue,
      reason: 'the work is not in a file, so the close must be called off',
    );
    fixture.session.dispose();
    await tester.pump();
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
    await hoverRecents(tester);
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
    // 🪦This used to look for the recovery prompt's absence. The stub file
    // is the better witness and always was: it is not a `.anicel`, so an
    // open that started at all fails loudly, and cancel means it never did.
    expect(
      find.text(AppText.strings.commonNotice),
      findsNothing,
      reason: 'cancel stops the open before it starts — the stub at that '
          'path would raise a read error the moment anything tried',
    );
  });

  testWidgets('🚨 a CLEAN session whose FILE has vanished is caught too — '
      'closing is when those pixels really go', (tester) async {
    // The gate used to ask only「are there unsaved edits」, and a saved
    // project answers no. But a clean cel keeps only {path, offset,
    // length} — the .anicel IS the cold tier — so this session has
    // drawings that exist nowhere else in the process. It kept working
    // after the file went because the session holds it open; on POSIX
    // that handle is also the ONLY thing keeping the unlinked bytes
    // alive, and closing the app is what finally drops it.
    final fixture = await mounted(tester);
    final path = '${folder.path.replaceAll('\\', '/')}/vanishing.anicel';
    await tester.runAsync(
      () => fixture.session.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson),
    );
    expect(
      fixture.session.projectFile.hasUnsavedChanges,
      isFalse,
      reason: 'the point of this test is a session with NOTHING unsaved',
    );

    // What a POSIX delete leaves: the name gone, the session's descriptor
    // still reading the bytes. Windows refuses to delete a file the session
    // holds, so the test moves it and hands the session that descriptor.
    OpenProjectFile.instance.release();
    File(path).renameSync('$path.moved');
    OpenProjectFile.instance.debugHoldAs('$path.moved', path);
    expect(fixture.session.projectFile.hasVanished(), isTrue);

    final settled = fixture.ask();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('system-exit-dialog')),
      findsOneWidget,
      reason: 'letting this one out in silence is the loss itself',
    );
    expect(
      find.text(AppText.strings.closeProjectVanishedBody),
      findsOneWidget,
      reason: '「your changes are not saved」 is false here — there are '
          'none — and it names a loss the buttons could undo',
    );

    await tester.tap(find.byKey(const ValueKey<String>('system-exit-cancel')));
    await tester.pumpAndSettle();
    expect(await settled, isFalse);
  });

  testWidgets('an ordinary dirty session still gets the unsaved-changes '
      'wording, not the vanished one', (tester) async {
    // The other half of the pick: a message chooser that always answered
    // "vanished" would pass the test above and tell every closing user
    // their file is gone.
    final fixture = await mounted(tester);
    final path = '${folder.path.replaceAll('\\', '/')}/present.anicel';
    await tester.runAsync(
      () => fixture.session.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson),
    );
    fixture.session.cutVerbs.createCut();

    final settled = fixture.ask();
    await tester.pumpAndSettle();
    expect(find.text(AppText.strings.closeProjectBody), findsOneWidget);
    expect(find.text(AppText.strings.closeProjectVanishedBody), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('system-exit-cancel')));
    await tester.pumpAndSettle();
    expect(await settled, isFalse);
  });

  testWidgets('🚨 REOPENING the project you are ALREADY editing asks too — '
      'the reload discards the live edits either way', (tester) async {
    // 🪦**THIS DOOR HAD AN EXCEPTION UNTIL 2026-09-08.** Reopening the
    // current project skipped the gate on purpose: the reload threw the
    // live edits away on its own, and answering Recover on that reopen was
    // the ONE way back to them — so a gate in front of it would have
    // retired the very sidecar the reopen existed to reach. With no sidecar
    // to reach, the exception was a silent discard with nothing behind it.
    // 「Reload from disk」 is still reachable: answer Discard.
    final path = '${folder.path.replaceAll(r'\', '/')}/Cut 12.anicel';
    File(path).writeAsBytesSync(
      buildAnicelArchiveBytes(
        project: createDefaultProject().copyWith(name: 'Opened From Disk'),
        cels: const [],
      ),
    );
    final seeded = const RecentProjects().withOpened(RecentProject(path: path));
    AppRecent.projects.value = seeded;
    RecentProjectsStore().save(seeded);
    addTearDown(() {
      AppRecent.projects.value = const RecentProjects();
      RecentProjectsStore().save(const RecentProjects());
    });

    ProjectRepository? repository;
    await tester.pumpWidget(
      MaterialApp(home: HomePage(onRepositoryCreated: (r) => repository = r)),
    );
    await tester.pumpAndSettle();

    Future<void> tapRecent() async {
      final button = find.byKey(
        const ValueKey<String>('top-strip-project-button'),
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      await hoverRecents(tester);
      await tester.tap(find.byKey(ValueKey<String>('menu-recent-$path')));
      // Frames, not a settle: the open stands behind the wait window from
      // its first frame (2026-09-13), and a turning spinner never settles.
      // Two frames build whatever the tap raised — the window on the first
      // open, the gate on the second — and the loop below lends the real
      // loop for the read itself.
      await tester.pump();
      await tester.pump();
    }

    // The open hops to a background isolate, which the fake clock never
    // advances — lend the real loop until the repository holds the fixture.
    await tapRecent();
    for (var attempt = 0; attempt < 200; attempt += 1) {
      await tester.pump();
      if (repository?.currentProject?.name == 'Opened From Disk') {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
    }
    // The window lingers with its check for `appProgressDoneLinger`, and a
    // window still up would swallow the next tap. A settle does not end
    // the linger: once the check is up nothing schedules a frame, so
    // `pumpAndSettle` returns with the timer still pending. Both clocks
    // are advanced — the fake one when the open landed on a pump, real
    // time when it landed under `runAsync` — until the window is gone.
    final window = find.byKey(const ValueKey<String>('open-progress-dialog'));
    for (var attempt = 0;
        attempt < 40 && window.evaluate().isNotEmpty;
        attempt += 1) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
    }
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    expect(
      session.projectFile.path,
      path,
      reason: 'the rest of this test is meaningless without the first open',
    );

    session.cutVerbs.createCut();
    expect(session.projectFile.hasUnsavedChanges, isTrue);

    await tapRecent();

    expect(
      find.byKey(const ValueKey<String>('system-exit-dialog')),
      findsOneWidget,
      reason: 'the same file is still a reload, and a reload is a discard',
    );
  });
}
