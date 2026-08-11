import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/recent_projects.dart';
import 'package:anicel/src/services/persistence/recent_projects_store.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

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
    try {
      folder.deleteSync(recursive: true);
    } on Object {
      // A leaked handle on Windows must not fail the suite.
    }
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

  testWidgets('an empty history shows no Recent section at all', (
    tester,
  ) async {
    // Absent rather than empty-and-disabled: a heading over nothing is a row
    // that only ever says no.
    await openProjectMenu(tester);
    expect(find.text(AppText.strings.recentProjectsTitle), findsNothing);
  });

  testWidgets('remembered projects appear as rows under a heading', (
    tester,
  ) async {
    final a = writeProject('Cut 12.anicel');
    final b = writeProject('Cut 13.anicel');
    seed(const RecentProjects()
        .withOpened(RecentProject(path: a))
        .withOpened(RecentProject(path: b)));

    await openProjectMenu(tester);

    expect(find.text(AppText.strings.recentProjectsTitle), findsOneWidget);
    expect(find.byKey(ValueKey<String>('menu-recent-$b')), findsOneWidget);
    expect(find.byKey(ValueKey<String>('menu-recent-$a')), findsOneWidget);
    // The row says the file name, not the whole path.
    expect(find.text('Cut 13.anicel'), findsOneWidget);
  });

  testWidgets('a row that lost its folder wears the reconnect label', (
    tester,
  ) async {
    final a = writeProject('Cut 12.anicel');
    seed(const RecentProjects()
        .withOpened(RecentProject(path: a))
        .withReconnectNeeded(a));

    await openProjectMenu(tester);

    // Kept, not dropped: the user still knows which project they meant.
    expect(find.byKey(ValueKey<String>('menu-recent-$a')), findsOneWidget);
    expect(
      find.text('Cut 12.anicel — ${AppText.strings.recentReconnect}'),
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

    await openProjectMenu(tester);
    // `tap` FAILS when the key is absent, so this line is the assertion that
    // matters: deleting `..._recentEntries(context)` from the popover — the
    // mutation that previously survived the whole suite — cannot get past it.
    await tester.tap(find.byKey(ValueKey<String>('menu-recent-$path')));
    await tester.pumpAndSettle();

    // And it took the file-exists branch rather than the reconnect one. The
    // stub is not a real archive so the open itself fails, but WHICH path it
    // walked is the thing worth pinning: the sibling test below proves a
    // missing file lands in the other branch, so the pair separates them.
    expect(AppRecent.projects.value.entries.single.needsReconnect, isFalse);
  });

  testWidgets('a remembered project that is gone offers the folder picker', (
    tester,
  ) async {
    // No bookmark — the desktop and Android shape. Before the reconnect fix
    // this branch showed "not found" and left the row permanently labelled
    // Reconnect with nothing behind it.
    final missing = '${folder.path.replaceAll('\\', '/')}/Gone.anicel';
    seed(const RecentProjects().withOpened(
      RecentProject(path: missing),
    ));
    var pickerAsked = false;
    FolderPicker.debugFolderPicker = ({String? initialDirectory}) async {
      pickerAsked = true;
      return const FolderGrant.cancelled();
    };

    await openProjectMenu(tester);
    await tester.tap(find.byKey(ValueKey<String>('menu-recent-$missing')));
    await tester.pumpAndSettle();

    expect(pickerAsked, isTrue, reason: 'the Reconnect label must be honoured');
    expect(
      AppRecent.projects.value.entries.single.needsReconnect,
      isTrue,
      reason: 'and the row is flagged, not deleted',
    );
  });
}
