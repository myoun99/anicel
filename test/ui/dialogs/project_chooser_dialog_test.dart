import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/dialogs/project_chooser_dialog.dart';

/// PICK-3: the window that answers "which project", once the OS has answered
/// "which folder".
///
/// The user's own account of their working folders is why the multi-project
/// case is tested first and hardest: 「물론 여러개 들어가있을때가 많아」. This
/// is the open dialog on iPad and macOS in practice, not a rare branch.
void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('qa_chooser_');
  });
  tearDown(() {
    try {
      folder.deleteSync(recursive: true);
    } on Object {
      // A leaked handle on Windows must not fail the suite.
    }
  });

  /// Writes a project file and stamps its modification time, so ordering is
  /// asserted against something the test controls rather than against how
  /// fast the machine happened to run.
  File writeProject(String name, {required DateTime modified}) {
    final file = File('${folder.path}/$name')..writeAsStringSync('x');
    file.setLastModifiedSync(modified);
    return file;
  }

  group('listing a folder', () {
    test('finds .anicel files and ignores everything else', () {
      writeProject('a.anicel', modified: DateTime(2026, 1, 1));
      File('${folder.path}/notes.txt').writeAsStringSync('x');
      Directory('${folder.path}/a.assets').createSync();

      final entries = anicelProjectsIn(folder.path);
      expect(entries.map((e) => e.name), ['a.anicel']);
    });

    test('the extension match is case-insensitive', () {
      writeProject('Shot.ANICEL', modified: DateTime(2026, 1, 1));
      expect(anicelProjectsIn(folder.path), hasLength(1));
    });

    test('newest modified comes first', () {
      // The one the user wants is nearly always the one they touched last,
      // which is the whole reason the rows carry a date.
      writeProject('old.anicel', modified: DateTime(2026, 1, 1));
      writeProject('newest.anicel', modified: DateTime(2026, 8, 11));
      writeProject('middle.anicel', modified: DateTime(2026, 5, 5));

      expect(anicelProjectsIn(folder.path).map((e) => e.name), [
        'newest.anicel',
        'middle.anicel',
        'old.anicel',
      ]);
    });

    test('a folder that is not there lists nothing rather than throwing', () {
      expect(anicelProjectsIn('${folder.path}/gone'), isEmpty);
    });
  });

  group('the chooser window', () {
    Future<String?> pumpChooser(
      WidgetTester tester,
      List<ProjectEntry> entries,
    ) async {
      String? chosen;
      var returned = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  chosen = await showProjectChooser(context, entries: entries);
                  returned = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      if (returned) {
        return chosen;
      }
      return null;
    }

    ProjectEntry entry(String name, DateTime modified) => ProjectEntry(
      path: '/projects/$name',
      name: name,
      modified: modified,
    );

    testWidgets('one project opens without showing the window', (tester) async {
      // Confirming a choice with no alternative only ever costs a tap.
      final chosen = await pumpChooser(tester, [
        entry('only.anicel', DateTime(2026, 8, 11)),
      ]);
      expect(chosen, '/projects/only.anicel');
      expect(find.byKey(const ValueKey<String>('project-chooser-dialog')),
          findsNothing);
    });

    testWidgets('several projects list with their dates', (tester) async {
      await pumpChooser(tester, [
        entry('newest.anicel', DateTime(2026, 8, 11, 14, 3)),
        entry('older.anicel', DateTime(2026, 1, 2, 9, 30)),
      ]);
      expect(find.byKey(const ValueKey<String>('project-chooser-dialog')),
          findsOneWidget);
      expect(find.text('newest.anicel'), findsOneWidget);
      expect(find.text('older.anicel'), findsOneWidget);
      expect(find.text('2026-08-11 14:03'), findsOneWidget);
      expect(find.text('2026-01-02 09:30'), findsOneWidget);
    });

    testWidgets('tapping a row opens that project', (tester) async {
      // A real tap rather than calling the callback: the row IS the button,
      // and a test that pokes the handler would survive the row losing its
      // gesture entirely.
      String? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  chosen = await showProjectChooser(
                    context,
                    entries: [
                      entry('a.anicel', DateTime(2026, 8, 11)),
                      entry('b.anicel', DateTime(2026, 8, 10)),
                    ],
                  );
                },
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
      String? chosen = 'unset';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  chosen = await showProjectChooser(context, entries: const []);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('project-chooser-empty')),
          findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('project-chooser-cancel')),
      );
      await tester.pumpAndSettle();
      expect(chosen, isNull);
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
