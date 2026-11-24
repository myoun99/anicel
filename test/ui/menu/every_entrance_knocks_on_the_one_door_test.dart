import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/media_viewer_bookmark.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/rail_group_button.dart';

/// F-282 (유저 2026-10-09): every entrance a file comes in through, pressed
/// the way a person presses it, reaches the ONE door — the menu's 「파일
/// 열기…」 and 「폴더 열기」, the media panel's ＋, the viewer's 「미디어에
/// 등록」. The door's own sorting is `the_one_door_test.dart`'s; this is
/// the wiring: what each entrance hands it, and whether the window it opens
/// registers (a pool's door) or places.
void main() {
  late Directory folder;

  setUp(() => folder = Directory.systemTemp.createTempSync('qa_entrances_'));
  tearDown(() => deleteTempQuietly(folder));

  String spelled(String path) => path.replaceAll(r'\', '/');

  Future<void> pumpApp(
    WidgetTester tester, {
    MediaViewerBookmarks viewing = const {},
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          initialProject: createDefaultProject().copyWith(
            mediaViewerBookmarks: viewing,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Presses [key] and waits for the import window it opens — its picture
  /// landed, so the preview's spinner is down and the frames settle.
  Future<void> tapToTheWindow(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    final opened = await settleAsync(
      tester,
      () => find.byType(ImportDialog).evaluate().isNotEmpty,
    );
    expect(opened, isTrue, reason: 'the import window opened');
    await settleLoadedPages(tester);
  }

  /// The file picker answers [grants], as the platform's would.
  void pickerAnswers(List<FolderGrant> grants) {
    FolderPicker.debugFilePicker =
        ({
          required List<XTypeGroup> acceptedTypeGroups,
          required bool allowMultiple,
        }) async => grants;
  }

  FolderGrant granted(String path) =>
      FolderGrant.granted(path: path, kind: GrantKind.file);

  Future<String> picture(WidgetTester tester, String name) async =>
      spelled((await tester.runAsync(() => writeSolidPng(folder, name)))!);

  /// The import window the door opened.
  ImportDialog window(WidgetTester tester) =>
      tester.widget<ImportDialog>(find.byType(ImportDialog));

  List<String?> handed(WidgetTester tester) => [
    for (final grant in window(tester).picked) grant.path,
  ];

  testWidgets('「파일 열기」 hands the pick to the door — a picture comes in '
      'through a window that places', (tester) async {
    final png = await picture(tester, 'A1.png');
    await pumpApp(tester);
    pickerAnswers([granted(png)]);

    await tapKey(tester, 'top-strip-project-button');
    await tapToTheWindow(tester, 'menu-file-open');

    expect(handed(tester), [png]);
    expect(window(tester).poolOnly, isFalse);
    expect(
      find.byKey(const ValueKey<String>('import-row-A1.png')),
      findsOneWidget,
      reason: 'the window lists what it was handed, from its first frame',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('import-source-line')))
          .data,
      png,
      reason: 'its top line names what was opened',
    );
  });

  testWidgets('「폴더 열기」 hands the folder over — a cut folder, into the '
      'window', (tester) async {
    final cut = Directory('${folder.path}/upn_02_063_lo')..createSync();
    await pumpApp(tester);
    FolderPicker.debugFolderPicker = ({initialDirectory}) async =>
        FolderGrant.granted(path: spelled(cut.path));

    await tapKey(tester, 'top-strip-project-button');
    await tapToTheWindow(tester, 'menu-file-open-folder');

    expect(handed(tester), [spelled(cut.path)]);
    expect(window(tester).picked.single.kind, GrantKind.folder);
  });

  testWidgets('🎯the media panel\'s ＋ picks FIRST, and the window it opens '
      'registers', (tester) async {
    final png = await picture(tester, 'BG.png');
    await pumpApp(tester);
    pickerAnswers([granted(png)]);

    await tapKey(
      tester,
      railGroupButtonKey(EditorWorkspace.railGroupId(right: true, slot: 3)),
    );
    await tapToTheWindow(tester, 'media-import-button');

    expect(handed(tester), [png]);
    expect(window(tester).poolOnly, isTrue);
  });

  testWidgets('a file the ＋ is handed that nothing opens is named — and no '
      'window opens on it', (tester) async {
    final notes = spelled('${folder.path}/notes.docx');
    File(notes).writeAsStringSync('x');
    await pumpApp(tester);
    pickerAnswers([granted(notes)]);

    await tapKey(
      tester,
      railGroupButtonKey(EditorWorkspace.railGroupId(right: true, slot: 3)),
    );
    await tapKey(tester, 'media-import-button');

    expect(
      find.byKey(const ValueKey<String>('unsupported-file-notice')),
      findsOneWidget,
    );
    await tapKey(tester, 'app-notice-close');
    expect(find.byType(ImportDialog), findsNothing);
  });

  testWidgets('the viewer\'s 「미디어에 등록」 goes through the door too — into '
      'a window that registers (F-282-Q4)', (tester) async {
    final png = await picture(tester, 'pose.png');
    await pumpApp(
      tester,
      viewing: {
        EditorWorkspace.mediaViewerTabId: MediaViewerBookmark(
          path: png,
          kind: MediaAssetKind.image,
        ),
      },
    );

    final floor = find.byKey(
      const ValueKey<String>(
        'top-strip-floor-${EditorWorkspace.mediaViewerTabId}',
      ),
    );
    await tester.tap(floor);
    // The viewer opens on the picture it was showing — the spinner stands
    // until that page lands. The main viewer's bar holds the button itself
    // (the sub viewer's folds it into its settings list).
    await settleLoadedPages(tester);
    await tapToTheWindow(tester, 'media-viewer-register-asset-button');

    expect(handed(tester), [png]);
    expect(window(tester).poolOnly, isTrue);
  });

  // 🗣️H81 (유저 2026-11-24): 「애초에 임포트창 떠있을때 밖 누르면 창닫혀서
  // 추가임포트못해. 그러니 동일한 코드로 부르도록. 파일 폴더 둘다두는게
  // 좋을듯」.
  group('the window\'s 「파일 추가」 · 「폴더 추가」 (H81)', () {
    Future<void> openOn(WidgetTester tester, String png) async {
      await pumpApp(tester);
      pickerAnswers([granted(png)]);
      await tapKey(tester, 'top-strip-project-button');
      await tapToTheWindow(tester, 'menu-file-open');
    }

    testWidgets('🚨both stand from the window\'s first frame', (tester) async {
      await openOn(tester, await picture(tester, 'A1.png'));

      for (final key in ['import-add-files', 'import-add-folder']) {
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget);
      }
    });

    testWidgets('🚨「파일 추가」 is 「파일 열기」\'s pick, and what it brings '
        'joins the window that stands — no second window', (tester) async {
      final a1 = await picture(tester, 'A1.png');
      final other = Directory('${folder.path}/other')..createSync();
      final b1 = spelled(
        (await tester.runAsync(() => writeSolidPng(other, 'B1.png')))!,
      );
      await openOn(tester, a1);
      pickerAnswers([granted(b1)]);

      await tapKey(tester, 'import-add-files');
      await settleLoadedPages(tester);

      expect(find.byType(ImportDialog), findsOneWidget);
      for (final name in ['A1.png', 'B1.png']) {
        expect(
          find.byKey(ValueKey<String>('import-row-$name')),
          findsOneWidget,
          reason: '$name is listed in the one window',
        );
      }
    });

    testWidgets('a picture added beside one of its run joins its row', (
      tester,
    ) async {
      final a1 = await picture(tester, 'A1.png');
      final other = Directory('${folder.path}/other')..createSync();
      final a2 = spelled(
        (await tester.runAsync(() => writeSolidPng(other, 'A2.png')))!,
      );
      await openOn(tester, a1);
      pickerAnswers([granted(a2)]);

      await tapKey(tester, 'import-add-files');
      await settleLoadedPages(tester);

      expect(
        find.byKey(const ValueKey<String>('import-row-A2.png')),
        findsNothing,
        reason: 'A2 is A1\'s row\'s',
      );
    });

    testWidgets('「폴더 추가」 is 「폴더 열기」\'s pick, into the window that '
        'stands', (tester) async {
      final cut = Directory('${folder.path}/upn_02_063_lo')..createSync();
      await openOn(tester, await picture(tester, 'A1.png'));
      FolderPicker.debugFolderPicker = ({initialDirectory}) async =>
          FolderGrant.granted(path: spelled(cut.path));

      await tapKey(tester, 'import-add-folder');
      await settleLoadedPages(tester);

      expect(find.byType(ImportDialog), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('import-source-line')),
            )
            .data,
        spelled(cut.path),
        reason: 'a folder is the import, as one opened with files is',
      );
    });
  });
}
