// HomePage widget tests — switching cuts keeps every surface scoped.
// Split from widget_test.dart (2026-09-04) so the suite runs across
// isolates; the shared probes live in helpers/home_page_probes.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart' show unnamedDrawingMark;
import 'package:anicel/main.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';

import 'ui/storyboard_cut_block_probe.dart';
import 'ui/timeline/timeline_row_chrome_probe.dart';

import 'helpers/home_page_probes.dart';

void main() {
  testWidgets('switches between existing sample cuts', (
    WidgetTester tester,
  ) async {
    // Two cuts have to be REACHABLE on the storyboard strip at once. The
    // floating region opens at 2/3 of the window now, so at the 800px test
    // default the second cut's block starts past the strip's right edge and
    // there is nothing on screen to tap.
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AnicelApp());
    await createSecondCut(tester);
    await switchToCut(tester, 'default-cut-1');

    await expectCutName(tester, 'default-cut-1', '1');
    await expectCutName(tester, 'cut-1', '2');
    await expectCutsNamed(tester, 'Cut 2', 0);
    await expectActiveCutName(tester, '1');
    expectActiveLayerName('A');
    expect(await activeCutIdOf(tester), const CutId('default-cut-1'));

    await tapStoryboardCutBlock(tester, 'cut-1');

    await expectActiveCutName(tester, '2');
    expectActiveLayerName('A');
    expect(find.text('B'), findsNothing);
    expect(find.text('A'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('timeline-row-cells-layer-1')),
      findsOneWidget,
    );
    expectCellText('layer-1', 0, 'X');
    expect(await activeCutIdOf(tester), const CutId('cut-1'));

    await tapStoryboardCutBlock(tester, 'default-cut-1');

    await expectActiveCutName(tester, '1');
    await expectCutName(tester, 'cut-1', '2');
    expectActiveLayerName('A');
    expect(await activeCutIdOf(tester), const CutId('default-cut-1'));
  });

  testWidgets('StoryboardPanel cut selection syncs active cut surfaces', (
    WidgetTester tester,
  ) async {
    // Same reason as 'switches between existing sample cuts': the second
    // cut's block has to be on screen to be tapped.
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AnicelApp());
    await createSecondCut(tester);
    await switchToCut(tester, 'default-cut-1');
    await showStoryboardPanel(tester);

    expect(
      find.byKey(const ValueKey<String>('storyboard-panel')),
      findsOneWidget,
    );
    await expectActiveCutName(tester, '1');
    expect(await activeCutIdOf(tester), const CutId('default-cut-1'));

    // The VISIBLE middle of the block — the rows scroll, so a block near
    // the right edge is drawn partly outside the panel's clip and its
    // geometric centre lands on whatever is beyond it.
    await tester.tapAt(
      cutBlockScreenRect(
        tester,
        'cut-1',
      ).intersect(tester.getRect(find.byType(StoryboardPanel))).center,
    );
    await tester.pumpAndSettle();

    await expectActiveCutName(tester, '2');
    expect(await activeCutIdOf(tester), const CutId('cut-1'));

    await showTimelinePanel(tester);

    expect(
      find.byKey(const ValueKey<String>('timeline-row-cells-layer-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-panel')),
      findsNothing,
    );
  });

  testWidgets('cut switching updates StoryboardPanel highlight', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await createSecondCut(tester);
    await showStoryboardPanel(tester);

    expect(await activeCutIdOf(tester), const CutId('cut-1'));

    await switchToCut(tester, 'default-cut-1');

    await expectActiveCutName(tester, '1');
    expect(await activeCutIdOf(tester), const CutId('default-cut-1'));
  });

  testWidgets('new frame after switching to Cut 2 stays scoped to Cut 2', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await createSecondCut(tester);

    await switchToCut(tester, 'cut-1');
    await expectActiveCutName(tester, '2');
    expectActiveLayerName('A');
    expectCellText('layer-1', 0, 'X');

    await tapHomeTimelineCell(
      tester,
      const ValueKey<String>('timeline-cell-layer-1-1'),
    );
    await tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));

    expectCellText('layer-1', 0, 'X');
    expectCellText('layer-1', 1, unnamedDrawingMark);
    expect(selectedCellStateLabel(tester), 'drawing start');

    await switchToCut(tester, 'default-cut-1');

    await expectActiveCutName(tester, '1');
    expectActiveLayerName('A');
    expectCellText('default-layer-1', 0, 'X');
    expectNoCellText('default-layer-1', 1, unnamedDrawingMark);

    await switchToCut(tester, 'cut-1');

    await expectActiveCutName(tester, '2');
    expectCellText('layer-1', 1, unnamedDrawingMark);
  });

  testWidgets(
    'blank and mark edits after switching to Cut 2 do not affect Cut 1',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());
      await createSecondCut(tester);

      await switchToCut(tester, 'cut-1');
      await tapHomeTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-layer-1-1'),
      );
      await tapToolbarButton(
        tester,
        const ValueKey<String>('new-frame-button'),
      );
      expectCellText('layer-1', 1, unnamedDrawingMark);

      // Grow the block to [1,4) so a held cell can take the dot, cut the
      // hold back at 3, then dot the held cell at 2 (dots are block-owned).
      await dragBlockEndGrip(tester, 'layer-1', 0, 2);
      await tapHomeTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-layer-1-3'),
      );
      await tapToolbarButton(
        tester,
        const ValueKey<String>('blank-exposure-button'),
      );
      expectCellText('layer-1', 3, 'X');

      await tapHomeTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-layer-1-2'),
      );
      await tapToolbarButton(
        tester,
        const ValueKey<String>('toggle-mark-button'),
      );
      expectCellText('layer-1', 2, '●');
      expect(selectedCellStateLabel(tester), 'inbetween mark');

      await switchToCut(tester, 'default-cut-1');

      await expectActiveCutName(tester, '1');
      // Cut 1's layer is untouched: one empty run whose first cell reads X.
      expectCellText('default-layer-1', 0, 'X');
      expectNoCellText('default-layer-1', 1, 'X');
      expectNoCellText('default-layer-1', 2, '●');
      expect(
        anyCellSemanticsLabel('default-layer-1', 'inbetween mark'),
        isFalse,
      );
    },
  );

  testWidgets('exposure edit after switching to Cut 2 stays on Cut 2 entry', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await createSecondCut(tester);

    await switchToCut(tester, 'cut-1');
    await tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));

    await dragBlockEndGrip(tester, 'layer-1', 0, 1);

    await tapHomeTimelineCell(
      tester,
      const ValueKey<String>('timeline-cell-layer-1-1'),
    );
    expect(selectedCellStateLabel(tester), 'held exposure');
    expectNoCellText('layer-1', 1, 'X');

    await switchToCut(tester, 'default-cut-1');

    expectActiveLayerName('A');
    // The fresh layer is all empty (X) cells; empty cells carry no
    // semantics label under the unified model.
    expect(selectedCellStateLabel(tester), isNull);
    expectCellText('default-layer-1', 0, 'X');
    expectNoCellText('default-layer-1', 1, unnamedDrawingMark);
  });

  testWidgets(
    'comma edge grips ripple blocks TVPaint-style with one undo per drag',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());

      // The drawing row sits at the bottom below the camera/CAM/SE fixture
      // rows; scroll it into view via its RAIL row (cell-level ensureVisible
      // would over-scroll the custom frame viewport and push frame 0 out of
      // the virtualized window).
      await tester.ensureVisible(
        find.byKey(
          const ValueKey<String>('timeline-layer-row-default-layer-1'),
        ),
      );
      await tester.pumpAndSettle();

      // Block A at index 0, block B at index 3 with an X gap between.
      await tapToolbarButton(
        tester,
        const ValueKey<String>('new-frame-button'),
      );
      await tapHomeTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-default-layer-1-3'),
      );
      await tapToolbarButton(
        tester,
        const ValueKey<String>('new-frame-button'),
      );

      // Grip ids are ORDINAL-based (block 0, block 1): a start-edge drag
      // moves the block's start index, and an index-derived identity would
      // change under the live drag.
      final gripIds = timelineRowChromeIds(tester, 'default-layer-1');
      expect(gripIds, contains('block-edge-grip-end-default-layer-1-0'));
      expect(gripIds, contains('block-edge-grip-start-default-layer-1-1'));

      // Lengthen A by 3: it consumes the X gap and pushes B from 3 to 4
      // with B's comma preserved (24px slim cells). R10: the slop is
      // TRAVEL, so the total is what counts — 19 + 53 = 72 = three cells.
      final gesture = await tester.startGesture(
        timelineRowChromeCenter(
          tester,
          'default-layer-1',
          'block-edge-grip-end-default-layer-1-0',
        ),
      );
      await gesture.moveBy(const Offset(19, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(53, 0));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();

      expectNoCellText('default-layer-1', 1, 'X');
      expectNoCellText('default-layer-1', 2, 'X');
      expectCellText('default-layer-1', 4, unnamedDrawingMark);

      // The whole drag is ONE undo step.
      await tapToolbarButton(tester, const ValueKey<String>('undo-button'));
      expectCellText('default-layer-1', 1, 'X');
      expectCellText('default-layer-1', 3, unnamedDrawingMark);

      // START-edge drag across several cells in ONE gesture: the live
      // preview moves the block's start every step, and the drag must
      // survive it (regression: start grips died after one step). B grows
      // backward through the gap until it touches A.
      final frontDrag = await tester.startGesture(
        timelineRowChromeCenter(
          tester,
          'default-layer-1',
          'block-edge-grip-start-default-layer-1-1',
        ),
      );
      await frontDrag.moveBy(const Offset(-19, 0));
      await tester.pump();
      await frontDrag.moveBy(const Offset(-24, 0));
      await tester.pumpAndSettle();
      await frontDrag.moveBy(const Offset(-24, 0));
      await tester.pumpAndSettle();
      await frontDrag.up();
      await tester.pumpAndSettle();

      expectCellText('default-layer-1', 1, unnamedDrawingMark);
      expectNoCellText('default-layer-1', 2, 'X');
      expectNoCellText('default-layer-1', 3, unnamedDrawingMark);
    },
  );

  testWidgets(
    'cut switching clears copied frame before cross-cut linked paste',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());
      await createSecondCut(tester);
      await switchToCut(tester, 'default-cut-1');

      await tapToolbarButton(
        tester,
        const ValueKey<String>('new-frame-button'),
      );
      await tapToolbarButton(
        tester,
        const ValueKey<String>('shared-copy-button'),
      );

      await switchToCut(tester, 'cut-1');

      await expectActiveCutName(tester, '2');
      expect(
        await isActionButtonEnabled(
          tester,
          const ValueKey<String>('shared-paste-linked-button'),
        ),
        isFalse,
      );

      await tapHomeTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-layer-1-1'),
      );

      expect(
        await isActionButtonEnabled(
          tester,
          const ValueKey<String>('shared-paste-linked-button'),
        ),
        isFalse,
      );
      expectNoCellText('layer-1', 1, unnamedDrawingMark);
    },
  );

  testWidgets('undo and redo smoke after cut switching keeps Cut 2 active', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await createSecondCut(tester);

    await switchToCut(tester, 'cut-1');
    await tapHomeTimelineCell(
      tester,
      const ValueKey<String>('timeline-cell-layer-1-1'),
    );
    await tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));
    expectCellText('layer-1', 1, unnamedDrawingMark);

    await tapUndoButton(tester);

    await expectActiveCutName(tester, '2');
    expectActiveLayerName('A');
    expectNoCellText('layer-1', 1, unnamedDrawingMark);

    await tapRedoButton(tester);

    await expectActiveCutName(tester, '2');
    expectCellText('layer-1', 1, unnamedDrawingMark);
  });
}
