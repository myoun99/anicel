import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/menu/project_open_door.dart';
import 'package:anicel/src/ui/open_projects.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/project_scratch_folder.dart';
import '../../helpers/wait_window.dart';
import '../../services/import/clip_test_builder.dart';

/// F-370 (유저 2026-10-16: 「줄이 너무 한줄로되있어서 알기힘듬. 좀 더
/// 알기쉽게 줄 나누거나 해서 항목화하도록」): what a converted file could not
/// bring over is listed by what was said of it — each thing said once, open,
/// over every name it was said of, one line each — and what was said of no
/// one thing is a line of the sentence's own. All of it: the notice was the
/// first six warnings one after another.
void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('qa_left_behind_');
    deleteAfterSessionEnds(folder);
  });

  /// A .clip whose root holds a text layer for each of [names], bottom to
  /// top — and whose chain then names a layer the file does not hold.
  String clipOf(List<String> names) {
    final database = clipDatabaseBytes(folder, (db) {
      db
        ..execute(clipSchema)
        ..execute(
          'INSERT INTO Canvas(MainId, CanvasWidth, CanvasHeight, '
          'CanvasRootFolder) VALUES (1, 64, 32, 1)',
        )
        ..execute(
          'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder, '
          "LayerFirstChildIndex) VALUES (1, '', 256, 1, 2)",
        );
      for (var i = 0; i < names.length; i += 1) {
        db.execute(
          'INSERT INTO Layer(MainId, LayerName, LayerType, LayerFolder, '
          'LayerNextIndex) VALUES (?, ?, 800, 0, ?)',
          [2 + i, names[i], 3 + i],
        );
      }
    });
    final path = '${folder.path}${Platform.pathSeparator}scene.clip';
    File(path).writeAsBytesSync(clipFileBytes(database: database));
    return path;
  }

  testWidgets('🎯each reason once, over every name it was said of — and what '
      'was said of no one thing under the sentence', (tester) async {
    final path = clipOf([
      for (var i = 1; i <= 7; i += 1) 'words $i',
      // A text layer is named by its text.
      'first line\n\nsecond line',
    ]);
    final projects = OpenProjects(
      first: createDefaultProject(),
      openSession: (project) => EditorSessionManager(initialProject: project),
      letGo: (session) => session.dispose(),
    );
    addTearDown(projects.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ProjectOpenDoor(projects).open(context, (
                path: path,
                folderBookmark: null,
                placed: false,
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await pumpPastTheWaitWindow(tester);
    await tester.pumpAndSettle();

    final notice = find.byKey(
      const ValueKey<String>('clip-import-warnings-notice'),
    );
    Finder inNotice(String text) =>
        find.descendant(of: notice, matching: find.text(text));
    expect(
      inNotice(
        [
          AppText.strings.imLeftBehind,
          'Part of the file could not be followed: a layer chain names '
              'layer 10, which is not there',
        ].join('\n'),
      ),
      findsOneWidget,
    );
    expect(
      inNotice('This kind of layer is not supported. (8)'),
      findsOneWidget,
    );
    expect(
      [
        for (var i = 1; i <= 7; i += 1)
          if (inNotice('words $i').evaluate().length != 1) i,
      ],
      isEmpty,
      reason: 'every name, open, each on a line of its own',
    );
    expect(inNotice('first line…'), findsOneWidget);
    expect(
      find.descendant(
        of: notice,
        matching: find.textContaining('not supported'),
      ),
      findsOneWidget,
      reason: 'the reason said once, not once a name',
    );

    for (final session in projects.sessions) {
      session.playbackRig.prerenderScheduler.cancel();
    }
  });
}
