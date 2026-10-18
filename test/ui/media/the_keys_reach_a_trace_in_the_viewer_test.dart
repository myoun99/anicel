import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';

import '../../helpers/fake_pdf_document.dart';
import '../../helpers/key_chords.dart';

/// 🗣️F-380 (유저 2026-10-17): 「뷰어패널에서 잘라내기쓸때 개미행렬 라이브가
/// 안보임. 법 통일해서 보이도록」.
///
/// A polygon tapped out in a viewer answers the window's keys as one on the
/// canvas does: 확정 closes it, ↶ ↷ take a vertex back and put it back, and
/// Escape lets go of it — the verbs ask after the trace the user is in the
/// middle of (`CanvasTraces`), wherever it is. Before, they asked the
/// canvas's alone, and the trace in the viewer stood through all of them.
void main() {
  final reference = MediaAsset(
    path: 'C:/work/conte.pdf',
    name: 'conte',
    kind: MediaAssetKind.pdf,
  );

  setUp(() {
    PdfRenderService.debugOpenerOverride = (_) async =>
        FakePdfDocument(pageSizes: const [Size(1200, 900)]);
  });

  tearDown(PdfRenderService.debugResetForTests);

  final viewer = find.byKey(const ValueKey<String>('media-viewer-panel'));

  /// ⛔Not `pumpAndSettle`: the marching ants of an open trace never settle.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> openRail(WidgetTester tester, int slot) async {
    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'rail-group-${EditorWorkspace.railGroupId(right: true, slot: slot)}',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The app with [reference] open in the main viewer, the cut on the
  /// polygon in hand, and three vertices tapped out on the page: the
  /// viewer's channel.
  Future<CanvasSelectionCommands> tapOutATrace(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          initialProject: createDefaultProject().copyWith(
            mediaAssets: [reference],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('top-strip-floor-media-viewer')),
    );
    await tester.pumpAndSettle();
    // The media pool lives on right rail 3.
    await openRail(tester, 3);
    await tester.tap(
      find.byKey(ValueKey<String>('media-asset-menu-${reference.path}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('media-asset-menu-open')),
    );
    await tester.pumpAndSettle();

    final host = tester.widget<MediaViewerTabHost>(
      find.byWidgetPredicate(
        (widget) =>
            widget is MediaViewerTabHost &&
            widget.viewerId == EditorWorkspace.mediaViewerTabId,
      ),
    );
    expect(host.request.value?.path, reference.path, reason: '⛔fixture');
    final tool = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .brushTool!;
    tool.value = tool.value.copyWith(
      tool: CanvasTool.cut,
      cutShape: CanvasShapeKind.polygon,
    );
    await pumpFrames(tester);

    // About the middle of the viewer's top: docks float over its sides,
    // and the timeline over its lower half.
    final top = tester.getRect(viewer).topCenter;
    for (final vertex in const [
      Offset(-100, 100),
      Offset(100, 100),
      Offset(100, 220),
    ]) {
      await tester.tapAt(top + vertex, kind: PointerDeviceKind.mouse);
      await pumpFrames(tester);
    }
    final trace = host.selection!;
    expect(trace.polygonPoints, hasLength(3), reason: '⛔fixture: tapped out');
    return trace;
  }

  testWidgets('확정 closes it', (tester) async {
    final trace = await tapOutATrace(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpFrames(tester);

    expect(trace.hasOpenPolygon, isFalse);
  });

  testWidgets('↶ takes its last vertex back, and ↷ puts it back', (
    tester,
  ) async {
    final trace = await tapOutATrace(tester);

    await pressCtrl(tester, LogicalKeyboardKey.keyZ);
    await pumpFrames(tester);
    expect(trace.polygonPoints, hasLength(2));

    await pressCtrl(tester, LogicalKeyboardKey.keyY);
    await pumpFrames(tester);
    expect(trace.polygonPoints, hasLength(3));
  });

  testWidgets('Escape lets go of it', (tester) async {
    final trace = await tapOutATrace(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);

    expect(trace.hasOpenPolygon, isFalse);
  });
}
