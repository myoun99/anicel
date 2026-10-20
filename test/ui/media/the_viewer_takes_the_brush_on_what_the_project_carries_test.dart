import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart'
    show CanvasTouchDragAction;
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/viewer_ink_keys.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart'
    show surfacePixelRgba;
import 'package:anicel/src/services/persistence/app_memory_settings.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/sheet_canvas_panel.dart' show sheetRunsTool;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/media/viewer_ink.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart'
    show SheetInkLayer, SheetInkWindow;

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

  /// The viewer on [path] with its slot's switch — [allowed] before the
  /// file opens — settled on the page.
  Future<({MediaViewerSlot slot, ViewerInkController ink})> view(
    WidgetTester tester,
    EditorSessionManager session,
    String path, {
    bool allowed = false,
    ValueNotifier<BrushToolState>? inHand,
  }) async {
    AppMemory.settings.value = AppMemorySettings(
      allowanceBytes: session.deviceCacheBudgets.total,
    );
    addTearDown(() => AppMemory.settings.value = const AppMemorySettings());
    final slot = MediaViewerSlot();
    addTearDown(slot.dispose);
    slot.brushAllowed.value = allowed;
    final tool =
        inHand ?? ValueNotifier<BrushToolState>(BrushToolState.defaults);
    if (inHand == null) {
      addTearDown(tool.dispose);
    }
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
              viewportController: slot.viewport,
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

  testWidgets('the brush cursor stands only while the page takes ink — the '
      'panel then runs the tool and leaves the finger to the slot, as a '
      'sheet\'s does — and the switch going off under a pen lets the stroke '
      'go', (tester) async {
    final (:session, :path) = await carrying(
      tester,
      directory,
      writeCarriedPicture,
    );
    final (:slot, ink: _) = await view(tester, session, path);
    BrushCanvasPanel panel() =>
        tester.widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel));
    bool cursors() => panel().toolCursorsEnabled;
    expect(cursors(), isFalse, reason: 'nothing to draw on, no tip');
    expect(
      (panel().runsTheSelectedTool, panel().oneFingerAction),
      (false, CanvasTouchDragAction.navigate),
      reason: 'with no cut armed a press and a finger move the page (I-14)',
    );

    slot.brushAllowed.value = true;
    await tester.pump();
    expect(cursors(), isTrue);
    expect(
      (panel().runsTheSelectedTool, panel().oneFingerAction),
      (true, null),
      reason: 'a sheet\'s answers while it draws (SheetCanvasPanel)',
    );

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
    // The viewer's switch was left on, on another file.
    final (:slot, ink: _) = await view(
      tester,
      session,
      pooled.path,
      allowed: true,
    );

    final button = tester.appIconButton(brushSwitch());
    expect(button.onPressed, isNull, reason: 'it cannot write on this file');
    expect(
      button.isSelected,
      isFalse,
      reason: 'the switch says what is true on THIS file',
    );
    expect(find.byType(ViewerInkOverlay), findsNothing);
    expect(slot.brushAllowed.value, isTrue, reason: 'and keeps the viewer\'s');
  });

  testWidgets('while the page takes ink a drag is the brush\'s — a mouse\'s '
      'and a finger\'s alike — and the wheel waits for the pen', (
    tester,
  ) async {
    final (:session, :path) = await carrying(
      tester,
      directory,
      writeCarriedPicture,
    );
    final (:slot, :ink) = await view(tester, session, path, allowed: true);
    final overlay = tester.widget<ViewerInkOverlay>(
      find.byType(ViewerInkOverlay),
    );
    final window = overlay.windows.single;
    final plane = window.plane! as CanvasSize;
    final origin = tester.getTopLeft(find.byType(ViewerInkOverlay));
    final rect = window.screenRect(overlay.viewport);
    final view0 = slot.viewport.value;

    Future<void> drag(Offset from, PointerDeviceKind kind) async {
      final gesture = await tester.startGesture(from, kind: kind);
      await tester.pump();
      for (var step = 1; step <= 4; step += 1) {
        await gesture.moveTo(from + Offset(step * 6.0, step * 4.0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
    }

    await drag(
      origin + rect.topLeft + const Offset(4, 4),
      PointerDeviceKind.mouse,
    );
    expect(ink.hasInkFor(plane, window.key), isTrue, reason: 'the mouse drew');
    expect(slot.viewport.value, view0, reason: 'and moved no view');
    session.historyManager.undo();

    await drag(origin + rect.center, PointerDeviceKind.touch);
    expect(ink.hasInkFor(plane, window.key), isTrue, reason: 'the finger drew');
    expect(slot.viewport.value, view0, reason: 'and moved no view');

    final pen = await tester.startGesture(origin + rect.center, pointer: 9);
    await tester.pump();
    await pen.moveTo(origin + rect.center + const Offset(6, 4));
    await tester.pump();
    final wheel = TestPointer(21, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(wheel.hover(origin + rect.center));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, -40)));
    await tester.pump();
    expect(
      slot.viewport.value,
      view0,
      reason: 'a stroke holds the view, as on a sheet',
    );
    await pen.up();
    await tester.pump();
  });

  testWidgets('a hold the pen raised is let go when the switch goes off — '
      'after the frame, as a sheet lets go', (tester) async {
    final (:session, :path) = await carrying(
      tester,
      directory,
      writeCarriedPicture,
    );
    final (:slot, ink: _) = await view(tester, session, path, allowed: true);
    final hold =
        tester
                .widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel))
                .contentStrokeActive!
            as ValueNotifier<bool>;
    hold.value = true; // the pen is down on the page's ink
    await tester.pump();
    expect(session.brushInputActive.value, isTrue, reason: '⛔전제');

    slot.brushAllowed.value = false; // …and the brush goes off under it
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(hold.value, isFalse, reason: 'nothing else will lift this pen');
    expect(session.brushInputActive.value, isFalse);
  });

  // 🗣️F-420 (유저 2026-10-20): 「캔버스 베이스패널에서 브러시허용일때,
  // 도형도구 선택되있는데 브러시가 그려짐. 선택한 도구가 작동하게하도록」 —
  // a sheet's law (`a_sheet_runs_the_tool_in_hand_test`), and the page takes
  // ink as a sheet does.
  group('F-420: the page runs the tool in hand', () {
    /// Whether [window]'s ink holds anything at document point [doc].
    bool inkAt(WidgetTester tester, SheetInkWindow window, Offset doc) {
      final surface = tester
          .widget<SheetInkLayer>(find.byType(SheetInkLayer))
          .sessionStateFor(window)
          .canvasState
          .currentSurface;
      final pixel = window.placement.pixelOf(doc);
      return (surfacePixelRgba(
                surface,
                pixel.dx.floor(),
                pixel.dy.floor(),
              ) ??
              0) !=
          0;
    }

    /// Document point [doc] on the screen.
    Offset onScreen(WidgetTester tester, Offset doc) {
      final view = tester
          .widget<ViewerInkOverlay>(find.byType(ViewerInkOverlay))
          .viewport;
      return tester.getTopLeft(find.byType(ViewerInkOverlay)) +
          Offset(
            view.panX + view.zoom * doc.dx,
            view.panY + view.zoom * doc.dy,
          );
    }

    Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
      final gesture = await tester.startGesture(
        onScreen(tester, from),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      for (var step = 1; step <= 6; step += 1) {
        await gesture.moveTo(
          onScreen(tester, Offset.lerp(from, to, step / 6)!),
        );
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
    }

    testWidgets('🎯a drag of the shape tool draws its box on the page, not '
        'the brush\'s line along the drag — ONE undo', (tester) async {
      final (:session, :path) = await carrying(
        tester,
        directory,
        (dir) => writeSolidPng(dir, 'ref.png', width: 400, height: 300),
      );
      final tool = ValueNotifier<BrushToolState>(
        BrushToolState.defaults.copyWith(tool: CanvasTool.shape, size: 4),
      );
      addTearDown(tool.dispose);
      await view(tester, session, path, allowed: true, inHand: tool);
      final window = tester
          .widget<ViewerInkOverlay>(find.byType(ViewerInkOverlay))
          .windows
          .single;
      final rect = window.documentRect;
      final from = rect.center - Offset(rect.width / 4, rect.height / 4);
      final to = rect.center + Offset(rect.width / 4, rect.height / 4);
      final steps = session.historyManager.undoCount;

      await drag(tester, from, to);

      expect(
        (
          corner: inkAt(tester, window, Offset(from.dx, to.dy)),
          middle: inkAt(tester, window, rect.center),
        ),
        (corner: true, middle: false),
        reason:
            'the box\'s corner, which the drag never passed, is drawn — and '
            'the middle, which the brush\'s line along the drag would cross, '
            'is not',
      );
      expect(session.historyManager.undoCount, steps + 1);
      session.undo();
      await tester.pump();
      expect(inkAt(tester, window, Offset(from.dx, to.dy)), isFalse);
    });

    testWidgets('every tool: one a sheet runs is the panel\'s, the armed cut '
        'runs as with the ink off, and under any other a press and a finger '
        'move the page, under no tip, and lay nothing', (tester) async {
      final (:session, :path) = await carrying(
        tester,
        directory,
        writeCarriedPicture,
      );
      final tool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
      addTearDown(tool.dispose);
      final (slot: _, :ink) = await view(
        tester,
        session,
        path,
        allowed: true,
        inHand: tool,
      );
      BrushCanvasPanel panel() =>
          tester.widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel));
      final window = tester
          .widget<ViewerInkOverlay>(find.byType(ViewerInkOverlay))
          .windows
          .single;
      final plane = window.plane! as CanvasSize;
      final rect = window.documentRect;

      for (final each in CanvasTool.values) {
        tool.value = tool.value.copyWith(tool: each);
        await tester.pump();
        final runs = sheetRunsTool(each);
        final cuts = armedCutShape(tool.value) != null;
        expect(
          (
            tool: panel().brushToolState?.value.tool,
            runs: panel().runsTheSelectedTool,
            finger: panel().oneFingerAction,
            tip: panel().toolCursorsEnabled,
          ),
          (
            tool: runs || cuts ? each : null,
            runs: runs || cuts,
            finger: runs ? null : CanvasTouchDragAction.navigate,
            tip: runs,
          ),
          reason: each.name,
        );
        if (!runs && !cuts) {
          final inside = rect.deflate(1);
          await drag(tester, inside.topLeft, inside.bottomRight);
          expect(ink.hasInkFor(plane, window.key), isFalse, reason: each.name);
        }
      }
    });
  });
}
