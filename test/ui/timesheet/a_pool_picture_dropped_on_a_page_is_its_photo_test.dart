import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/sheet_photo_drops.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

/// 🗣️유저 I-97 (2026-10-15): a pool picture dropped on a timesheet's page
/// is a PHOTO kept in that page's ink — brush or no brush — and one undo
/// takes it back. With the brush on, the page's window shows it the moment
/// it lands (「보이는 중이랑 결과랑 절대로 다르면 안 되」).
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('timesheet_photo_');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  /// The timesheet of a pool holding a picture, its brush [on] or off;
  /// returns the picture's path.
  Future<(EditorSessionManager, TimesheetInkController, String)> pumpSheet(
    WidgetTester tester, {
    required bool on,
  }) async {
    final png = normalizedMediaPath(
      (await tester.runAsync(
        () => writeSolidPng(tempDir, 'photo.png', width: 40, height: 10),
      ))!,
    );
    final session = EditorSessionManager(
      initialProject: createDefaultProject().copyWith(
        mediaAssets: [
          MediaAsset(path: png, name: 'photo', kind: MediaAssetKind.image),
        ],
      ),
    );
    addTearDown(session.dispose);
    final ink = TimesheetInkController();
    addTearDown(ink.dispose);
    final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(brushTool.dispose);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimesheetTabHost(
            session: session,
            viewport: CanvasViewport(),
            onViewportChanged: (_) {},
            inkController: ink,
            brushToolState: brushTool,
            brushAllowed: on,
            onBrushAllowedChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (session, ink, png);
  }

  SheetInkWindow firstPage(WidgetTester tester) => sheetPhotoEntrance(
    tester,
  ).windows().whereType<SheetInkWindow>().firstWhere((w) => w.id == 'page-0');

  testWidgets('dropped on a page, the brush on, the picture is that page\'s '
      'photo and its window shows it at once — and one undo takes it off the '
      'page and the screen', (tester) async {
    final (session, ink, png) = await pumpSheet(tester, on: true);
    final page = firstPage(tester);
    expect(sheetPhotosShown(tester), isEmpty, reason: 'fixture');

    dropOnSheet(
      tester,
      png,
      sheetPaperOnScreen(tester, page.documentRect.center),
    );
    await settleAsync(tester, () => sheetPhotosOn(ink, page.key).isNotEmpty);
    await tester.pump();

    expect(sheetPhotosOn(ink, page.key), hasLength(1));
    expect(
      [for (final photo in sheetPhotosShown(tester)) photo.reference.assetPath],
      [png],
      reason: 'shown as it landed, as the brush view shows a stroke',
    );

    session.historyManager.undo();
    await tester.pump();
    expect(sheetPhotosOn(ink, page.key), isEmpty);
    expect(sheetPhotosShown(tester), isEmpty);
  });

  testWidgets('the brush off, the drop lands the same — a drop is no stray '
      'mark for the switch to guard', (tester) async {
    final (session, ink, png) = await pumpSheet(tester, on: false);
    final page = firstPage(tester);

    dropOnSheet(
      tester,
      png,
      sheetPaperOnScreen(tester, page.documentRect.center),
    );
    await settleAsync(tester, () => sheetPhotosOn(ink, page.key).isNotEmpty);

    expect(sheetPhotosOn(ink, page.key), hasLength(1));
    session.historyManager.undo();
    expect(sheetPhotosOn(ink, page.key), isEmpty, reason: 'one undo');
  });
}
