import 'dart:io';

import 'package:file_selector/file_selector.dart' show XTypeGroup;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/recent_projects.dart';
import 'package:anicel/src/services/persistence/recent_projects_store.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import '../../helpers/temp_dir.dart';

/// PICK-4: the Recent projects rows in the Project popover.
///
/// Written because adversarial review proved the wiring was unpinned:
/// deleting `..._recentEntries(context)` from the popover broke no test,
/// even though the list, the store and the MRU arithmetic were all covered.
/// The arithmetic was tested and the thing the user actually touches was
/// not — which is the failure mode a green suite hides best.
void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('qa_recent_menu_');
    AppRecent.projects.value = const RecentProjects();
    RecentProjectsStore().save(const RecentProjects());
  });
  tearDown(() {
    AppRecent.projects.value = const RecentProjects();
    RecentProjectsStore().save(const RecentProjects());
    FolderPicker.debugFolderPicker = null;
    FolderPicker.debugFilePicker = null;
    FolderPicker.debugBookmarkResolver = null;
    deleteTempQuietly(folder);
  });

  /// Seeds through the STORE rather than the notifier, because
  /// `HomePage.initState` loads the store and would otherwise overwrite a
  /// notifier set here. Going through the file also pins that load, which
  /// nothing else covers. The store redirects itself to a per-process temp
  /// file under FLUTTER_TEST, so this never touches the real list.
  void seed(RecentProjects projects) {
    AppRecent.projects.value = projects;
    RecentProjectsStore().save(projects);
  }

  String writeProject(String name) {
    final path = '${folder.path.replaceAll('\\', '/')}/$name';
    File(path).writeAsStringSync('x');
    return path;
  }

  Future<void> openProjectMenu(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    final button = find.byKey(
      const ValueKey<String>('top-strip-project-button'),
    );
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  /// Opens the RECENT PROJECTS row's second level, with the Project popover
  /// already up.
  ///
  /// 🗣️유저 2026-09-16 (F-146): 「프로젝트버튼의 최근 프로젝트는 **최근
  /// 프로젝트라는 버튼안에** 넣고」 — the list used to be spilled straight
  /// into the Project popover under a heading. It is the submenu axis I-4
  /// built (hover-opened), so the rows need a mouse to be on the row.
  Future<void> hoverRecents(WidgetTester tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey<String>('menu-recent-projects')),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openRecents(WidgetTester tester) async {
    await openProjectMenu(tester);
    await hoverRecents(tester);
  }

  /// Taps a Recent row and lets the open RUN, answering whether the wait
  /// window was seen on the way.
  ///
  /// ⚠️`runAsync` and hand-rolled pumping, NOT `pumpAndSettle`: the window
  /// holds a turning spinner — an animation that never settles — and the
  /// read is real IO that only completes in real time. The same harness
  /// save_shows_progress_test uses, for the same two reasons. Polled until
  /// the window has come and gone, so a stub that fails to parse in a
  /// millisecond and a file that takes a second are judged alike.
  Future<bool> tapRecentAndLetItOpen(WidgetTester tester, String path) async {
    final window = find.byKey(const ValueKey<String>('open-progress-dialog'));
    var seen = false;
    await tester.runAsync(() async {
      await tester.tap(find.byKey(ValueKey<String>('menu-recent-$path')));
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump();
        final up = window.evaluate().isNotEmpty;
        seen = seen || up;
        if (seen && !up) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pumpAndSettle();
    return seen;
  }

  testWidgets('an empty history shows no Recent section at all', (
    tester,
  ) async {
    // Absent rather than empty-and-disabled: a heading over nothing is a row
    // that only ever says no.
    await openProjectMenu(tester);
    expect(find.text(AppText.strings.recentProjectsTitle), findsNothing);
  });
  testWidgets('remembered projects live inside the RECENT PROJECTS row', (
    tester,
  ) async {
    final a = writeProject('Cut 12.anicel');
    final b = writeProject('Cut 13.anicel');
    seed(const RecentProjects()
        .withOpened(RecentProject(path: a))
        .withOpened(RecentProject(path: b)));

    await openProjectMenu(tester);
    // 🗣️F-146: one row, and the list is behind it.
    expect(
      find.byKey(const ValueKey<String>('menu-recent-projects')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey<String>('menu-recent-$b')),
      findsNothing,
      reason: '두 번째 겹은 아직 화면에 없다 — 그게 겹이 둘인 이유다',
    );

    await hoverRecents(tester);

    expect(find.text(AppText.strings.recentProjectsTitle), findsOneWidget);
    expect(find.byKey(ValueKey<String>('menu-recent-$b')), findsOneWidget);
    expect(find.byKey(ValueKey<String>('menu-recent-$a')), findsOneWidget);
    // 🗣️유저 2026-09-16 (F-146): 「최근 연 프로젝트에 **.anicel 필요없으니까
    // 안보이게**」 — the row says what the user calls the work, and the
    // strip's own title has said exactly that all along.
    expect(find.text('Cut 13'), findsOneWidget);
    expect(find.text('Cut 13.anicel'), findsNothing);
  });

  testWidgets('the CLOCK is the row that opens the list, not every row in it', (
    tester,
  ) async {
    // 🗣️유저 2026-09-16 (F-146): 「시계아이콘?도 필요없고. **그걸 그냥 최근
    // 프로젝트라는 버튼에 아이콘으로서** 넣고」. A glyph repeated down every
    // row of a list of recent projects says only what the list already says.
    final a = writeProject('Cut 12.anicel');
    seed(const RecentProjects().withOpened(RecentProject(path: a)));

    await openRecents(tester);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('menu-recent-projects')),
        matching: find.byIcon(Icons.history_outlined),
      ),
      findsOneWidget,
      reason: '시계는 그 버튼의 아이콘이다',
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey<String>('menu-recent-$a')),
        matching: find.byIcon(Icons.history_outlined),
      ),
      findsNothing,
      reason: '⛔행마다 반복되는 글리프는 아무 말도 하지 않는다',
    );
  });

  testWidgets('a row that lost its folder wears the reconnect label', (
    tester,
  ) async {
    final a = writeProject('Cut 12.anicel');
    seed(const RecentProjects()
        .withOpened(RecentProject(path: a))
        .withReconnectNeeded(a));

    await openRecents(tester);

    // Kept, not dropped: the user still knows which project they meant.
    expect(find.byKey(ValueKey<String>('menu-recent-$a')), findsOneWidget);
    expect(
      find.text('Cut 12 — ${AppText.strings.recentReconnect}'),
      findsOneWidget,
    );
  });

  testWidgets('tapping a remembered project opens it', (tester) async {
    // The real widget, a real tap. The row IS the command; a test that
    // called the handler would survive the row losing its gesture.
    final path = writeProject('Cut 12.anicel');
    seed(const RecentProjects().withOpened(
      RecentProject(path: path),
    ));

    await openRecents(tester);
    // `tap` FAILS when the key is absent, so this line is the assertion that
    // matters: deleting `..._recentEntries(context)` from the popover — the
    // mutation that previously survived the whole suite — cannot get past it.
    await tapRecentAndLetItOpen(tester, path);

    // And it took the file-exists branch rather than the reconnect one. The
    // stub is not a real archive so the open itself fails, but WHICH path it
    // walked is the thing worth pinning: the sibling test below proves a
    // missing file lands in the other branch, so the pair separates them.
    expect(AppRecent.projects.value.entries.single.needsReconnect, isFalse);
  });

  testWidgets('the open stands behind the wait window from its first frame '
      '— a big project on a cloud drive is not instant (유저 2026-09-13)',
      (tester) async {
    // 🪦The window used to wait for a provider to make the open WAIT, and
    // a local pick stayed silent — so a 74MB project that took seconds
    // to read showed nothing, and「여는 중인지 아닌지 모르겠어」. The window
    // is built BEFORE the work starts, which is what makes one frame the
    // whole proof: it is on screen whether the file takes a second or a
    // millisecond.
    final path = writeProject('Cut 12.anicel');
    seed(const RecentProjects().withOpened(
      RecentProject(path: path),
    ));

    await openRecents(tester);
    expect(
      await tapRecentAndLetItOpen(tester, path),
      isTrue,
      reason: 'an open that says nothing cannot be told from nothing',
    );
    // The stub is not an archive, so the open failed and the window came
    // down with it — what stays is the file error, not the wait.
    expect(
      find.byKey(const ValueKey<String>('open-progress-dialog')),
      findsNothing,
    );
  });

  testWidgets('a remembered project that is gone offers the FILE picker', (
    tester,
  ) async {
    // No bookmark — the desktop and Android shape. Before the reconnect fix
    // this branch showed "not found" and left the row permanently labelled
    // Reconnect with nothing behind it. The picker is FILE mode now: the
    // folder-then-rejoin shape was the folder-as-permission-unit leftover,
    // and folder mode is the one Google Drive refuses on iOS — a reconnect
    // that dead-ended on the very provider file mode un-blocked.
    final missing = '${folder.path.replaceAll('\\', '/')}/Gone.anicel';
    seed(const RecentProjects().withOpened(
      RecentProject(path: missing),
    ));
    var pickerAsked = false;
    FolderPicker.debugFilePicker =
        ({
          required List<XTypeGroup> acceptedTypeGroups,
          required bool allowMultiple,
        }) async {
          pickerAsked = true;
          return const [FolderGrant.cancelled()];
        };

    await openRecents(tester);
    await tester.tap(find.byKey(ValueKey<String>('menu-recent-$missing')));
    await tester.pumpAndSettle();

    expect(pickerAsked, isTrue, reason: 'the Reconnect label must be honoured');
    expect(
      AppRecent.projects.value.entries.single.needsReconnect,
      isTrue,
      reason: 'and the row is flagged, not deleted',
    );
  });

  testWidgets('a FILE bookmark resolves to the project itself — no name '
      'join, no false reconnect', (tester) async {
    // Since PICK-6 both Open and Save As store FILE bookmarks, whose
    // resolved path IS the project. The old folder-dialect join built
    // '/…/Foo.anicel/Foo.anicel', failed the exists-check, and flagged
    // every Apple row "Reconnect" for ever — with the reconnect picker
    // being the one mode Google Drive refuses, a Drive project's row was
    // permanently dead. The resolved item's own name is the discriminator.
    final path = writeProject('Cut 12.anicel');
    seed(const RecentProjects().withOpened(
      RecentProject(path: path, folderBookmark: 'FILE-BOOK=='),
    ));
    FolderPicker.debugBookmarkResolver = (bookmark, kind) async =>
        FolderGrant.granted(
          path: path,
          bookmark: 'FRESH==',
          kind: GrantKind.file,
        );

    await openRecents(tester);
    await tapRecentAndLetItOpen(tester, path);

    expect(
      AppRecent.projects.value.entries.single.needsReconnect,
      isFalse,
      reason: 'the resolved FILE path is the project — joining the name '
          'onto it built a path that exists nowhere',
    );
  });

  testWidgets('a FOLDER bookmark still joins the file name', (tester) async {
    // The legacy dialect (pre-PICK-6 rows) keeps working: the resolved
    // item is the folder, so the project is name-joined inside it.
    final path = writeProject('Cut 12.anicel');
    seed(const RecentProjects().withOpened(
      RecentProject(path: path, folderBookmark: 'DIR-BOOK=='),
    ));
    FolderPicker.debugBookmarkResolver = (bookmark, kind) async =>
        FolderGrant.granted(
          path: folder.path.replaceAll('\\', '/'),
          bookmark: 'FRESH==',
        );

    await openRecents(tester);
    await tapRecentAndLetItOpen(tester, path);

    expect(AppRecent.projects.value.entries.single.needsReconnect, isFalse);
  });
}
