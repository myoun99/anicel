import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_grid_stack.dart';

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
/// now」), so a row that does not mount the grid simply has no lines.
///
/// ⚠️This header used to add that 「the cut-end shading rides in the same
/// painter, so one mount returns both」. It never did: the line painter has
/// no wash, and nothing here pinned one — the claim only rode along in the
/// test's name. The wash is the overlay's own layer now, over the row, and
/// `collapsed_row_overlay_test` pins it.
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

  testWidgets('the grid sheet is mounted UNDER the row, on no ground', (
    tester,
  ) async {
    await _pumpFolded(tester);

    final sheet = find.descendant(
      of: find.byType(CollapsedRowOverlay),
      matching: find.byKey(const ValueKey<String>('collapsed-grid-sheet')),
    );
    expect(
      sheet,
      findsOneWidget,
      reason: 'not mounting the grid is the ONLY reason the folded row had '
          'no lines — the per-cell borders are transparent by design',
    );

    // I-44: under the row, as in the open panel — it used to be laid OVER
    // the row here, while the row drew its own lines as well. It is the open
    // grid's own stack that lays it now, in the slot under the rows (D32,
    // `timeline_frame_grid_stack_test`), with where the film stops over them.
    final stack = tester.widget<TimelineFrameGridStack>(
      find.ancestor(of: sheet, matching: find.byType(TimelineFrameGridStack)),
    );
    expect(stack.gridSheet, tester.widget(sheet));

    // The row lies over the ARTWORK: no ground to paint rows on, so no row
    // is coloured and no seam is ruled; the lines stay the law's raw ink.
    final painter = tester
        .widget<CustomPaint>(
          find.descendant(of: sheet, matching: find.byType(CustomPaint)),
        )
        .painter! as TimelineGridSheetPainter;
    expect(painter.ground, isNull);
    expect(painter.rows, TimelineGridRows.none);

    final overlay = tester.widget<CollapsedRowOverlay>(
      find.byType(CollapsedRowOverlay),
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
