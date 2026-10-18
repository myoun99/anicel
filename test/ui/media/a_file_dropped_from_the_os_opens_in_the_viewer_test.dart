import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/input/os_file_drop.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/widgets/drop_entrance_frame.dart';
import '../../helpers/os_file_drop.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

/// 🗣️F-378 (유저 2026-10-17): 「윈도우등 os에서 드래그앤 드롭으로 파일을
/// 뷰어패널에 떨어트리면 바로 뷰어패널에서 열리도록. 서브뷰어던
/// 메인뷰어던」.
///
/// Dropped as the OS hands it over ([osDrop]): the window's one drop target
/// finds the place under the point. Anywhere else a drop goes through the
/// one door (`a_dropped_project_opens_through_the_open_door_test`).
void main() {
  late Directory folder;

  setUp(() => folder = Directory.systemTemp.createTempSync('qa_viewer_drop_'));
  tearDown(() => deleteTempQuietly(folder));

  String spelled(String path) => path.replaceAll(r'\', '/');

  Future<String> picture(WidgetTester tester, String name) async =>
      spelled((await tester.runAsync(() => writeSolidPng(folder, name)))!);

  const mainViewer = EditorWorkspace.mediaViewerTabId;
  const subViewer = EditorWorkspace.mediaViewerSubTabId;

  /// The app with both viewers on screen: the main one on the floor, the
  /// sub viewer open on its rail.
  Future<void> pumpViewers(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    for (final key in [
      'top-strip-floor-$mainViewer',
      'rail-group-${EditorWorkspace.railGroupId(right: true, slot: 5)}',
    ]) {
      await tester.tap(find.byKey(ValueKey<String>(key)));
      await tester.pumpAndSettle();
    }
  }

  Finder panelOf(String viewer) =>
      find.byKey(ValueKey<String>('$viewer-panel'));

  /// A point where [viewer] is on top. ⚠️Not the main viewer's middle:
  /// the floor's lower half lies under the floating timeline, and a drop
  /// there is the timeline's (measured 2026-10-18 — the middle is the
  /// floating region's resize edge).
  Offset onScreenIn(WidgetTester tester, String viewer) =>
      tester.getRect(panelOf(viewer)).topCenter.translate(0, 100);

  /// The file [viewer] has open.
  String? openIn(WidgetTester tester, String viewer) => tester
      .widget<MediaViewerTabHost>(
        find.byWidgetPredicate(
          (widget) => widget is MediaViewerTabHost && widget.viewerId == viewer,
        ),
      )
      .request
      .value
      ?.path;

  /// Whether [viewer] is lit as a place a drop is over: its frame drawn.
  bool litIn(WidgetTester tester, String viewer) => find
      .descendant(
        of: find.descendant(
          of: find.ancestor(
            of: panelOf(viewer),
            matching: find.byType(OsFileDropEntrance),
          ),
          matching: find.byType(DropEntranceFrame),
        ),
        matching: find.byType(DecoratedBox),
      )
      .evaluate()
      .isNotEmpty;

  testWidgets('🎯a picture dropped on either viewer opens in THAT one — and '
      'the import window never comes up', (tester) async {
    final pose = await picture(tester, 'pose.png');
    final layout = await picture(tester, 'layout.png');
    await pumpViewers(tester);

    await osDrop(tester, [pose], at: onScreenIn(tester, mainViewer));
    await settleLoadedPages(tester);
    expect(openIn(tester, mainViewer), pose);
    expect(openIn(tester, subViewer), isNull);

    await osDrop(tester, [layout], at: onScreenIn(tester, subViewer));
    await settleLoadedPages(tester);
    expect(openIn(tester, subViewer), layout);
    expect(
      openIn(tester, mainViewer),
      pose,
      reason: 'the other viewer keeps what it has open',
    );
    expect(find.byType(ImportDialog), findsNothing);
  });

  // A project file: the door opens one in a tab of its own and says nothing
  // of 「unsupported」 — so the notice can only be the viewer's.
  testWidgets('a file the viewer does not open is refused as its 「파일 열기」 '
      'refuses one — and nothing goes through the door', (tester) async {
    final project = spelled('${folder.path}/Cut 12.anicel');
    File(project).writeAsStringSync('x');
    await pumpViewers(tester);

    await osDrop(tester, [project], at: onScreenIn(tester, mainViewer));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('unsupported-file-notice')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('open-progress-dialog')),
      findsNothing,
    );
    expect(openIn(tester, mainViewer), isNull);
    expect(find.byType(ImportDialog), findsNothing);
  });

  testWidgets('a drag from the OS lights the viewer it is over — that one '
      'alone — and none once it has gone or been let go', (tester) async {
    final pose = await picture(tester, 'pose.png');
    await pumpViewers(tester);
    expect(litIn(tester, mainViewer), isFalse);

    await osDragOver(tester, onScreenIn(tester, mainViewer));
    expect(litIn(tester, mainViewer), isTrue);
    expect(litIn(tester, subViewer), isFalse);

    await osDragMovesTo(tester, onScreenIn(tester, subViewer));
    expect(litIn(tester, mainViewer), isFalse);
    expect(litIn(tester, subViewer), isTrue);

    await osDragLeaves(tester);
    expect(litIn(tester, subViewer), isFalse);

    await osDrop(tester, [pose], at: onScreenIn(tester, subViewer));
    expect(litIn(tester, subViewer), isFalse, reason: 'let go, it is out');
    await settleLoadedPages(tester);
  });
}
