import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// 유저 2026-10-16 (frame-picture-indicator-Q1 b): 「a + 그 셀이 있는 타임라인
/// 칸에도 빨간 표시」 — both rows that draw a cel's block, the open
/// timeline's and the one folded over the artwork, ask the session which
/// cels could not be read. Each builds its own source of what a cel holds,
/// so each is pinned.
void main() {
  /// A new project in the app — row A born with its cel on the first frame.
  Future<EditorSessionManager> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: newUntitledProject())),
    );
    await tester.pumpAndSettle();
    return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
  }

  /// Row A and the cel its block on the first frame shows.
  (Layer, BrushFrameKey) rowAOf(EditorSessionManager session) {
    final cut = session.requireActiveCut;
    final row = cut.layers.firstWhere(
      (layer) => layer.kind == LayerKind.animation,
    );
    return (
      row,
      session.brushFrameKeyForCut(cut, row.id, row.timeline[0]!.frameId!),
    );
  }

  Color blockAt0(WidgetTester tester, Finder within, Layer row) => tester
      .widgetList<CustomPaint>(
        find.descendant(of: within, matching: find.byType(CustomPaint)),
      )
      .map((paint) => paint.painter)
      .whereType<TimelineRowCellsPainter>()
      .firstWhere((painter) => painter.layer.id == row.id)
      .resolvedCellStyleFor(0)
      .background;

  /// The cel noted as the cache keeps one whose reading threw — red where
  /// [within]'s row draws its block, and not before.
  void expectRedOnceNoted(
    WidgetTester tester,
    EditorSessionManager session,
    Finder within,
  ) {
    final (row, cel) = rowAOf(session);
    expect(
      blockAt0(tester, within, row),
      isNot(timelineUnreadableCelPaperColor),
      reason: '⛔CONTROL: nothing has failed to read it',
    );

    session.renderCaches.layerFrameImageCache.unreadable.note(cel);

    expect(blockAt0(tester, within, row), timelineUnreadableCelPaperColor);
  }

  testWidgets('🚨the timeline\'s row', (tester) async {
    final session = await pumpApp(tester);

    expectRedOnceNoted(tester, session, find.byType(TimelineTabHost));
  });

  testWidgets('🚨the row folded over the artwork', (tester) async {
    final session = await pumpApp(tester);
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('floating-bottom-collapse')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byType(CollapsedRowOverlay),
      findsOneWidget,
      reason: '⛔premise: the panel is folded',
    );

    expectRedOnceNoted(tester, session, find.byType(CollapsedRowOverlay));
  });
}
