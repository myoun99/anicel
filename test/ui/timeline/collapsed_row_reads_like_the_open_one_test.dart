import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';

/// 🚨T16ⓐ′ — the folded row is the OPEN row seen through glass, not a look
/// of its own.
///
/// 유저 확정 2026-08-14: 「반투명 = **오버레이 루트 하나, 70%**」.
///
/// ⛔It used to be two alphas inside the cells painter — `0x66` on a block's
/// body, `0x9E` on its edge — carried over verbatim from the strip painter
/// that owned the drawing before. Two numbers is an opacity SCHEME: parts of
/// the row faded by different amounts, so it could never read as a dimmer
/// copy of the open row, which is the only thing it is meant to be.
///
/// And 🚨the missing grid lines were never erased by chromeless mode. Every
/// plain per-cell border is `Colors.transparent` on purpose
/// (`timeline_cell_style`: 「the GRID OVERLAY owns every plain per-cell line
/// now」), so a row that does not mount the overlay simply has no lines. The
/// cut-end shading rides in the same painter, so one mount returns both —
/// and that shading is information rather than chrome (유저 확정 08-10),
/// which is why a folded row wants it too.
Future<void> _pumpFolded(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1500, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: createDefaultProject())),
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -420),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('floating-bottom-collapse')),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the whole row fades by ONE value', (tester) async {
    await _pumpFolded(tester);
    final overlay = find.byType(CollapsedRowOverlay);
    expect(overlay, findsOneWidget);

    final opacities = tester
        .widgetList<Opacity>(
          find.descendant(of: overlay, matching: find.byType(Opacity)),
        )
        .map((widget) => widget.opacity)
        .toList();

    expect(
      opacities,
      contains(collapsedRowOverlayOpacity),
      reason: 'the root carries the row\'s translucency',
    );
    expect(
      collapsedRowOverlayOpacity,
      0.7,
      reason: '유저 확정: 70% — pinned by number because the whole point is '
          'that there is exactly one of it',
    );
  });

  testWidgets('the grid lines and the cut-end shading are mounted', (
    tester,
  ) async {
    await _pumpFolded(tester);

    final lines = find.descendant(
      of: find.byType(CollapsedRowOverlay),
      matching: find.byKey(const ValueKey<String>('collapsed-beat-lines')),
    );
    expect(
      lines,
      findsOneWidget,
      reason: 'not mounting this painter is the ONLY reason the folded row '
          'had no lines — the per-cell borders are transparent by design',
    );

    final painter =
        tester.widget<CustomPaint>(lines).painter! as TimelineBeatLinesPainter;
    final overlay = tester.widget<CollapsedRowOverlay>(
      find.byType(CollapsedRowOverlay),
    );
    expect(
      painter.crossCellExtent,
      overlay.height,
      reason: 'the lines span the row they are drawn on, not the grid\'s row '
          'height — a folded row is one row tall and measures as one',
    );
    expect(
      overlay.height,
      CollapsedRowOverlay.defaultHeight,
      reason: 'D15: the height is THE ROW\'s now, and a timeline layer row\'s '
          'answer is this number — the constant stopped being the law and '
          'became one row\'s answer to it',
    );
  });
}
