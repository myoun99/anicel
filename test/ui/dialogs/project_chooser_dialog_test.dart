import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/recent_projects.dart';
import 'package:anicel/src/services/persistence/recent_projects_store.dart';
import 'package:anicel/src/ui/dialogs/project_chooser_dialog.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// PICK-3: the window that answers "which project", once the OS has answered
/// "which folder".
///
/// Two rules here REPLACED earlier ones, and both replacements are pinned
/// because the tests that pinned the old rules would otherwise have blocked
/// them: the window now opens whatever the folder holds (it used to skip
/// itself at exactly one project), and the default order is name ascending
/// (it used to be newest-modified first).
void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('qa_chooser_');
    AppRecent.projects.value = const RecentProjects();
    RecentProjectsStore().save(const RecentProjects());
  });
  tearDown(() {
    AppRecent.projects.value = const RecentProjects();
    RecentProjectsStore().save(const RecentProjects());
    try {
      folder.deleteSync(recursive: true);
    } on Object {
      // A leaked handle on Windows must not fail the suite.
    }
  });

  File writeProject(String name, {DateTime? modified, int bytes = 1}) {
    final file = File('${folder.path}/$name')
      ..writeAsStringSync('x' * bytes);
    if (modified != null) {
      file.setLastModifiedSync(modified);
    }
    return file;
  }

  ProjectEntry entry(
    String name, {
    DateTime? modified,
    int bytes = 1,
  }) => ProjectEntry(
    path: '/projects/$name',
    name: name,
    modified: modified ?? DateTime(2026),
    bytes: bytes,
  );

  group('listing a folder', () {
    test('finds .anicel files and ignores everything else', () {
      writeProject('a.anicel');
      File('${folder.path}/notes.txt').writeAsStringSync('x');
      Directory('${folder.path}/a.assets').createSync();

      expect(anicelProjectsIn(folder.path).map((e) => e.name), ['a.anicel']);
    });

    test('the extension match is case-insensitive', () {
      writeProject('Shot.ANICEL');
      expect(anicelProjectsIn(folder.path), hasLength(1));
    });

    test('carries the size, so the chooser can order by it', () {
      writeProject('a.anicel', bytes: 40);
      expect(anicelProjectsIn(folder.path).single.bytes, 40);
    });

    test('a folder that is not there lists nothing rather than throwing', () {
      expect(anicelProjectsIn('${folder.path}/gone'), isEmpty);
    });
  });

  group('natural name order', () {
    test('a number is compared by value, not by digit', () {
      // The whole point. Plain string order puts C-10 before C-9.
      expect(naturalCompare('C-9.anicel', 'C-10.anicel'), lessThan(0));
      expect(naturalCompare('C-10.anicel', 'C-9.anicel'), greaterThan(0));
    });

    test('zero padding does not change the order', () {
      expect(naturalCompare('C-009.anicel', 'C-010.anicel'), lessThan(0));
      expect(naturalCompare('C-09.anicel', 'C-9.anicel'), isNot(0));
    });

    test('multi-digit runs beyond one segment still order by value', () {
      expect(naturalCompare('S2 C-3', 'S10 C-3'), lessThan(0));
      expect(naturalCompare('S2 C-30', 'S2 C-4'), greaterThan(0));
    });

    test('letters order case-insensitively', () {
      expect(naturalCompare('apple', 'Banana'), lessThan(0));
      expect(naturalCompare('Apple', 'apple'), 0);
    });

    test('a prefix comes before the longer name', () {
      expect(naturalCompare('C-1', 'C-1 수정'), lessThan(0));
    });
  });

  group('sorting', () {
    test('name ascending is the order the chooser opens in', () {
      final sorted = sortProjectEntries(
        [entry('C-10.anicel'), entry('C-9.anicel'), entry('C-1.anicel')],
        key: ProjectSortKey.name,
        ascending: true,
      );
      expect(sorted.map((e) => e.name), [
        'C-1.anicel',
        'C-9.anicel',
        'C-10.anicel',
      ]);
    });

    test('descending reverses it', () {
      final sorted = sortProjectEntries(
        [entry('C-1.anicel'), entry('C-10.anicel'), entry('C-9.anicel')],
        key: ProjectSortKey.name,
        ascending: false,
      );
      expect(sorted.first.name, 'C-10.anicel');
    });

    test('by modified, and by size', () {
      final old = entry('old.anicel', modified: DateTime(2026, 1, 1), bytes: 9);
      final recent = entry(
        'new.anicel',
        modified: DateTime(2026, 8, 11),
        bytes: 2,
      );
      expect(
        sortProjectEntries(
          [old, recent],
          key: ProjectSortKey.modified,
          ascending: false,
        ).first.name,
        'new.anicel',
      );
      expect(
        sortProjectEntries(
          [old, recent],
          key: ProjectSortKey.size,
          ascending: true,
        ).first.name,
        'new.anicel',
      );
    });

    test('name breaks a tie, so equal dates do not shuffle between opens', () {
      final same = DateTime(2026, 8, 11);
      final sorted = sortProjectEntries(
        [
          entry('b.anicel', modified: same),
          entry('a.anicel', modified: same),
        ],
        key: ProjectSortKey.modified,
        ascending: true,
      );
      expect(sorted.map((e) => e.name), ['a.anicel', 'b.anicel']);
    });

    test('the input list is left alone', () {
      final input = [entry('b.anicel'), entry('a.anicel')];
      sortProjectEntries(input, key: ProjectSortKey.name, ascending: true);
      expect(input.map((e) => e.name), ['b.anicel', 'a.anicel']);
    });
  });

  group('the chooser window', () {
    Future<String?> pump(
      WidgetTester tester,
      List<ProjectEntry> entries, {
      String folderPath = '/drive/work/작업',
    }) async {
      String? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => chosen = await showProjectChooser(
                  context,
                  entries: entries,
                  folderPath: folderPath,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      return chosen;
    }

    testWidgets('opens even for a single project', (tester) async {
      // REPLACES 'one project opens without showing the window'. The skip was
      // the reason the flow felt unpredictable: what came back after picking a
      // folder depended on a count the user could not see.
      await pump(tester, [entry('only.anicel')]);
      expect(
        find.byKey(const ValueKey<String>('project-chooser-dialog')),
        findsOneWidget,
      );
      expect(find.text('only.anicel'), findsOneWidget);
    });

    testWidgets('names the folder it is listing', (tester) async {
      await pump(tester, [entry('a.anicel')], folderPath: '/드라이브/작품A/작업');
      expect(
        find.byKey(const ValueKey<String>('project-chooser-folder')),
        findsOneWidget,
      );
      expect(find.text('/드라이브/작품A/작업'), findsOneWidget);
    });

    testWidgets('opens in name order, not newest-first', (tester) async {
      // REPLACES 'newest modified comes first'.
      await pump(tester, [
        entry('C-10.anicel', modified: DateTime(2026, 8, 11)),
        entry('C-9.anicel', modified: DateTime(2026, 1, 1)),
      ]);
      final rows = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data);
      final names = rows.where((t) => t != null && t.endsWith('.anicel'));
      expect(names, ['C-9.anicel', 'C-10.anicel']);
    });

    testWidgets('tapping a row opens that project', (tester) async {
      String? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => chosen = await showProjectChooser(
                  context,
                  entries: [entry('a.anicel'), entry('b.anicel')],
                  folderPath: '/x',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('b.anicel'));
      await tester.pumpAndSettle();
      expect(chosen, '/projects/b.anicel');
    });

    testWidgets('an empty folder says so and returns nothing', (tester) async {
      final chosen = await pump(tester, const []);
      expect(
        find.byKey(const ValueKey<String>('project-chooser-empty')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('project-chooser-cancel')),
      );
      await tester.pumpAndSettle();
      expect(chosen, isNull);
    });

    testWidgets('the sort button states the current order', (tester) async {
      // The BUTTON carries it, not a mark in the menu — a selection is shown
      // with colour in this app and never with a checkmark, and the shared
      // flyout item has no colour affordance.
      await pump(tester, [entry('a.anicel')]);
      expect(find.text('${AppText.strings.sortByName} ↑'), findsOneWidget);
    });

    testWidgets('choosing another order reorders and is remembered', (
      tester,
    ) async {
      await pump(tester, [
        entry('a.anicel', modified: DateTime(2026, 1, 1)),
        entry('b.anicel', modified: DateTime(2026, 8, 11)),
      ]);
      await tester.tap(
        find.byKey(const ValueKey<String>('project-chooser-sort')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('project-chooser-sort-modified'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('${AppText.strings.sortByModified} ↑'), findsOneWidget);
      expect(
        AppRecent.projects.value.sortKey,
        ProjectSortKey.modified,
        reason: 'the choice is global and survives the window',
      );
      expect(RecentProjectsStore().load().sortKey, ProjectSortKey.modified);
    });

    testWidgets('the direction is remembered too', (tester) async {
      await pump(tester, [entry('a.anicel')]);
      await tester.tap(
        find.byKey(const ValueKey<String>('project-chooser-sort')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('project-chooser-sort-desc')),
      );
      await tester.pumpAndSettle();

      expect(find.text('${AppText.strings.sortByName} ↓'), findsOneWidget);
      expect(RecentProjectsStore().load().sortAscending, isFalse);
    });

    testWidgets('a remembered order is what the window opens in', (
      tester,
    ) async {
      AppRecent.projects.value = const RecentProjects(
        sortKey: ProjectSortKey.modified,
        sortAscending: false,
      );
      await pump(tester, [
        entry('a.anicel', modified: DateTime(2026, 1, 1)),
        entry('b.anicel', modified: DateTime(2026, 8, 11)),
      ]);
      final rows = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data);
      final names = rows.where((t) => t != null && t.endsWith('.anicel'));
      expect(names, ['b.anicel', 'a.anicel']);
    });

    testWidgets('rows are one line at the agreed height', (tester) async {
      await pump(tester, [entry('a.anicel')]);
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(
        (list.childrenDelegate as SliverChildBuilderDelegate).childCount,
        1,
      );
      expect(list.itemExtent, 40);
    });
  });

  group('the date column', () {
    test('pads to a fixed width so the column lines up', () {
      expect(
        formatProjectModified(DateTime(2026, 1, 2, 9, 5)),
        '2026-01-02 09:05',
      );
      expect(
        formatProjectModified(DateTime(2026, 12, 25, 23, 59)),
        '2026-12-25 23:59',
      );
    });
  });
}
