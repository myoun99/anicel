import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/viewer_ink_keys.dart';
import 'package:anicel/src/services/persistence/app_memory_settings.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/media/viewer_ink.dart';

import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/carried_media_fixture.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

/// 🗣️I-114 (유저 2026-10-21): 「뷰어패널(서브던 메인이던) 새 기능. 다른
/// 캔버스 베이스패널의 브러시 허용이랑 똑같은 직접 그릴수있는기능 법
/// 통일해서 구현. 물론 그리는게 가능한 파일만 대응」 — and I-114-Q1:
/// 「품은 파일만」.
///
/// The viewer wears the sheets' brush switch at the head of its bar; on a
/// file the project carries it writes on the page through the ink windows
/// every sheet writes through, and on any other file it keeps its place,
/// off. (Which kinds a carried file may be — not a sound — is
/// [viewerInksOn]'s, pinned where it is cheapest.)
void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('anicel-viewer-ink');
  });

  tearDown(() => deleteTempQuietly(directory));

  Finder brushSwitch() => find.byKey(
    const ValueKey<String>('media-viewer-brush-toggle-button'),
  );

  Finder page() => find.byKey(const ValueKey<String>('media-viewer-page'));

  /// The viewer on [path] with its slot's switch, settled on the page.
  Future<({MediaViewerSlot slot, ViewerInkController ink})> view(
    WidgetTester tester,
    EditorSessionManager session,
    String path,
  ) async {
    AppMemory.settings.value = AppMemorySettings(
      allowanceBytes: session.deviceCacheBudgets.total,
    );
    addTearDown(() => AppMemory.settings.value = const AppMemorySettings());
    final slot = MediaViewerSlot();
    addTearDown(slot.dispose);
    final tool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(tool.dispose);
    final ink = ViewerInkController(
      store: session.renderCaches.viewerInkStore,
    );
    addTearDown(ink.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: slot.brushAllowed,
            builder: (context, allowed, _) => MediaViewerTabHost(
              viewerId: 'media-viewer',
              session: session,
              request: slot.request,
              position: slot.position,
              brushTool: tool,
              inkController: ink,
              brushAllowed: allowed,
              onBrushAllowedChanged: (value) => slot.brushAllowed.value = value,
            ),
          ),
        ),
      ),
    );
    slot.request.value = MediaViewerRequest(
      path: path,
      kind: MediaAssetKind.image,
    );
    await tester.pump();
    expect(
      await settleAsync(
        tester,
        () =>
            tester.any(page()) && session.renderCaches.viewerRasterBytes > 0,
      ),
      isTrue,
      reason: 'the page opened and was drawn',
    );
    return (slot: slot, ink: ink);
  }

  testWidgets('a carried picture takes the brush once the switch is on: a '
      'stroke lands on its page\'s ink, which stays printed with the brush '
      'off, and one undo clears it', (tester) async {
    final (:session, :path) = await carrying(
      tester,
      directory,
      writeCarriedPicture,
    );
    final carry = session.repository
        .requireProject()
        .mediaAssetByPath(path)!
        .carriedAs!;
    final (:slot, :ink) = await view(tester, session, path);

    expect(
      tester.appIconButton(brushSwitch()).isSelected,
      isFalse,
      reason: 'off by default, as every sheet starts',
    );
    expect(find.byType(ViewerInkOverlay), findsNothing);

    await tester.tap(brushSwitch());
    await tester.pump();
    expect(slot.brushAllowed.value, isTrue);
    expect(tester.appIconButton(brushSwitch()).isSelected, isTrue);

    final overlay = tester.widget<ViewerInkOverlay>(
      find.byType(ViewerInkOverlay),
    );
    final window = overlay.windows.single;
    expect(
      window.key,
      viewerInkPageKey(carry, 0),
      reason: 'the page of the file, by what the project carries it as',
    );
    final plane = window.plane! as CanvasSize;
    final origin = tester.getTopLeft(find.byType(ViewerInkOverlay));
    final rect = window.screenRect(overlay.viewport);

    expect(ink.hasInkFor(plane, window.key), isFalse);
    final gesture = await tester.startGesture(origin + rect.center, pointer: 7);
    await tester.pump();
    await gesture.moveTo(origin + rect.center + const Offset(6, 4));
    await tester.pump();
    expect(
      session.brushInputActive.value,
      isTrue,
      reason: 'a stroke holds the brush input, as a sheet\'s does',
    );
    await gesture.up();
    await tester.pump();
    expect(ink.hasInkFor(plane, window.key), isTrue);

    await tester.tap(brushSwitch());
    await tester.pump();
    expect(find.byType(ViewerInkOverlay), findsNothing);
    final printer = tester
        .widget<CustomPaint>(
          find.byKey(const ValueKey<String>('media-viewer-ink')),
        )
        .painter! as ViewerInkPainter;
    expect(
      [for (final shown in printer.windows) shown.key],
      [window.key],
      reason: 'the page\'s saved ink is printed over it',
    );
    expect(printer.liveInkKeys, isEmpty);

    session.historyManager.undo();
    expect(ink.hasInkFor(plane, window.key), isFalse);
  });

  testWidgets('the brush cursor stands only while the page takes ink, and '
      'the switch going off under a pen lets the stroke go', (tester) async {
    final (:session, :path) = await carrying(
      tester,
      directory,
      writeCarriedPicture,
    );
    final (:slot, ink: _) = await view(tester, session, path);
    bool cursors() => tester
        .widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel))
        .toolCursorsEnabled;
    expect(cursors(), isFalse, reason: 'nothing to draw on, no tip');

    slot.brushAllowed.value = true;
    await tester.pump();
    expect(cursors(), isTrue);

    final overlay = tester.widget<ViewerInkOverlay>(
      find.byType(ViewerInkOverlay),
    );
    final origin = tester.getTopLeft(find.byType(ViewerInkOverlay));
    final rect = overlay.windows.single.screenRect(overlay.viewport);
    final gesture = await tester.startGesture(origin + rect.center, pointer: 7);
    await tester.pump();
    await gesture.moveTo(origin + rect.center + const Offset(6, 4));
    await tester.pump();
    expect(session.brushInputActive.value, isTrue, reason: '⛔전제');

    slot.brushAllowed.value = false;
    await tester.pump();
    await tester.pump();
    expect(
      session.brushInputActive.value,
      isFalse,
      reason: 'the window is gone; the pen will never be lifted there',
    );
    expect(cursors(), isFalse);
    await gesture.up();
  });

  testWidgets('a picture the pool points at keeps the switch in its place, '
      'off — and nothing takes ink there', (tester) async {
    final (:session, path: _) = await carrying(
      tester,
      directory,
      writeCarriedPicture,
    );
    final loose = (await tester.runAsync(
      () => writeSolidPng(directory, 'loose.png', width: 8, height: 8),
    ))!;
    await tester.runAsync(
      () => session.mediaPool.importMediaFiles([loose], copyIntoProject: false),
    );
    final pooled = session.repository.requireProject().mediaAssetByPath(
      normalizedMediaPath(loose),
    )!;
    expect(pooled.carried, isFalse, reason: 'the premise: pointed at');
    final (:slot, ink: _) = await view(tester, session, pooled.path);

    final button = tester.appIconButton(brushSwitch());
    expect(button.onPressed, isNull, reason: 'it cannot write on this file');
    expect(button.isSelected, isFalse);

    slot.brushAllowed.value = true;
    await tester.pump();
    expect(find.byType(ViewerInkOverlay), findsNothing);
    expect(
      tester.appIconButton(brushSwitch()).isSelected,
      isFalse,
      reason: 'the switch says what is true on THIS file',
    );
  });
}
