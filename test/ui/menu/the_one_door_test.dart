import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/dialogs/app_confirm_dialog.dart';
import 'package:anicel/src/ui/menu/opened_files_door.dart';
import 'package:anicel/src/ui/menu/project_open_door.dart' show ProjectPick;
import '../../helpers/temp_dir.dart';

/// F-282 (유저 2026-10-09): 「열기랑 임포트랑 되도록 하나로」 — every door
/// hands what it holds to ONE door, and one judgement says where each goes:
/// a project to a tab, media and a folder to the import window, a brush to
/// the library, a font to this device's fonts — and what nothing opens is
/// named. ↩️A drop let anything into the window, and the window registered
/// what it could not name as a picture.
void main() {
  late Directory folder;

  setUp(() => folder = Directory.systemTemp.createTempSync('qa_one_door_'));
  tearDown(() => deleteTempQuietly(folder));

  /// A file named [name] holding [bytes], handed over as a drop hands it.
  FolderGrant fileNamed(String name, [List<int> bytes = const [1, 2, 3]]) {
    final file = File('${folder.path}/$name')..writeAsBytesSync(bytes);
    return handedPath(file.path);
  }

  /// What the door did, in the order it did it.
  final done = <String>[];
  late List<FolderGrant> windowGot;
  late bool windowToPool;
  late List<ProjectPick> projectsGot;
  late Map<String, Uint8List> brushesGot;
  late List<Uint8List> fontsGot;

  OpenedFilesDoor door() {
    windowGot = [];
    windowToPool = false;
    projectsGot = [];
    brushesGot = {};
    fontsGot = [];
    return OpenedFilesDoor(
      openProjects: (picks) async {
        done.add('projects');
        projectsGot = picks;
      },
      importWindow: (picked, {required toPool}) async {
        done.add('window');
        windowGot = picked;
        windowToPool = toPool;
      },
      bringBrushes: (name, bytes) async {
        done.add('brushes');
        brushesGot[name] = bytes;
        return 'brushes from $name';
      },
      bringFont: (bytes) async {
        done.add('font');
        fontsGot.add(bytes);
        return 'a font';
      },
    );
  }

  /// [handed] through the door from inside a real Navigator, which its
  /// notices need — closing each notice as it comes.
  Future<void> knock(
    WidgetTester tester,
    List<FolderGrant> handed, {
    bool toPool = false,
    void Function()? onNotice,
  }) async {
    done.clear();
    final theDoor = door();
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await theDoor.open(context, handed, toPool: toPool);
                finished = true;
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    for (var round = 0; round < 10 && !finished; round += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      final close = find.byKey(const ValueKey<String>('app-notice-close'));
      if (close.evaluate().isNotEmpty) {
        onNotice?.call();
        done.add('notice');
        await tester.tap(close);
        await tester.pumpAndSettle();
      }
    }
    expect(finished, isTrue, reason: 'the door finished');
  }

  testWidgets('each kind goes where it goes — the libraries first, then '
      'the import window, and the projects once it has closed', (
    tester,
  ) async {
    final project = fileNamed('Cut 12.anicel');
    final picture = fileNamed('A1.png');
    final brush = fileNamed('Pack.abr', [7, 7]);
    final font = fileNamed('Face.otf', [9]);

    await knock(tester, [project, picture, brush, font]);

    expect(done, ['brushes', 'font', 'notice', 'window', 'projects']);
    expect([for (final grant in windowGot) grant.path], [picture.path]);
    expect([for (final pick in projectsGot) pick.path], [project.path]);
    expect(brushesGot.keys, ['Pack.abr']);
    expect(brushesGot['Pack.abr'], [7, 7]);
    expect(fontsGot.single, [9]);
  });

  testWidgets('what the libraries said is said once, together', (
    tester,
  ) async {
    String? message;
    await knock(
      tester,
      [fileNamed('Pack.abr'), fileNamed('Face.ttf')],
      onNotice: () => message = tester
          .widget<AppConfirmDialog>(find.byType(AppConfirmDialog))
          .message,
    );

    expect(message, 'brushes from Pack.abr\na font');
    expect(done.where((step) => step == 'notice'), hasLength(1));
  });

  testWidgets('🎯a file nothing opens is named — and goes nowhere, the '
      'import window least of all', (tester) async {
    List<String>? named;
    await knock(
      tester,
      [fileNamed('notes.txt'), fileNamed('A1.png')],
      onNotice: () => named ??= tester
          .widget<AppConfirmDialog>(find.byType(AppConfirmDialog))
          .details,
    );

    expect(
      named,
      ['${folder.path}/notes.txt'],
      reason: 'named as every pick names a refusal — a file by its path',
    );
    expect(
      find.byKey(const ValueKey<String>('unsupported-file-notice')),
      findsNothing,
    );
    expect([for (final grant in windowGot) grant.path], [
      '${folder.path}/A1.png',
    ], reason: 'what CAN come in still does');
    expect(done, ['notice', 'window']);
  });

  testWidgets('a folder is a cut folder — into the import window', (
    tester,
  ) async {
    final cut = Directory('${folder.path}/upn_02_063_lo')..createSync();

    await knock(tester, [handedPath(cut.path)]);

    expect([for (final grant in windowGot) grant.path], [cut.path]);
    expect(windowGot.single.kind, GrantKind.folder);
  });

  testWidgets('a pool\'s door says so to the window — the media panel\'s ＋ '
      'and the viewer\'s 「미디어에 등록」', (tester) async {
    await knock(tester, [fileNamed('take3.mov')], toPool: true);
    expect(windowToPool, isTrue);

    await knock(tester, [fileNamed('take3.mov')]);
    expect(windowToPool, isFalse);
  });

  testWidgets('a pick\'s project keeps its token on the way to the tab', (
    tester,
  ) async {
    await knock(tester, const [
      FolderGrant.granted(
        path: '/work/C-045/scene.tvpp',
        bookmark: 'BOOK==',
        kind: GrantKind.file,
      ),
    ]);

    expect(projectsGot.single.folderBookmark, 'BOOK==');
    expect(projectsGot.single.placed, isFalse);
  });

  testWidgets('nothing that can come in, nothing opened — and no window', (
    tester,
  ) async {
    await knock(tester, const []);
    expect(done, isEmpty);
  });
}
