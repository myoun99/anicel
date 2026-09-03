// HomePage widget tests — the timeline toolbar and its cells.
// Split from widget_test.dart (2026-09-04) so the suite runs across
// isolates; the shared probes live in helpers/home_page_probes.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';

import 'helpers/home_page_probes.dart';

void main() {
  testWidgets('timeline action toolbar hosts cell action controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    final toolbar = find.byKey(
      const ValueKey<String>('timeline-action-toolbar'),
    );

    expect(toolbar, findsOneWidget);
    expect(
      find.descendant(
        of: toolbar,
        matching: find.byKey(const ValueKey<String>('new-frame-button')),
      ),
      findsOneWidget,
    );
    expectTimelineActionTooltips();
    await expectTimelineActionKeys(tester);
    // Two groups now (R-toolbar round): layer commands (split add + Layer ▾)
    // and the frame trio + Frame ▾; the copy/edit/exposure groups folded
    // into the flyouts or retired.
    expect(
      find.byKey(const ValueKey<String>('timeline-toolbar-layer-group')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-toolbar-frame-group')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-toolbar-exposure-group')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-menu-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-frame-menu-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('cut-menu-button')),
      findsOneWidget,
    );
  });

  testWidgets('initial layer starts with a blank exposure at frame 1', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    expectCellText('default-layer-1', 0, 'X');
    expect(
      find.byKey(const ValueKey<String>('timeline-row-cells-default-layer-2')),
      findsNothing,
    );
    // Paper-sheet style: only the FIRST cell of the empty run reads X.
    expectNoCellText('default-layer-1', 1, 'X');
    expect(rowPainter('default-layer-1').cellModelAt(0).semanticsLabel, isNull);
  });

  testWidgets(
    'selected cell state updates for blank, drawing, name, and mark',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());

      expectActiveLayerName('A');
      expectCurrentFrame(tester, 1);
      // Empty (X) cells carry no semantics label.
      expect(selectedCellStateLabel(tester), isNull);

      final newFrameButton = find.byKey(
        const ValueKey<String>('new-frame-button'),
      );
      await tester.ensureVisible(newFrameButton);
      await tester.pumpAndSettle();
      await tester.tap(newFrameButton);
      await tester.pumpAndSettle();

      expect(selectedCellStateLabel(tester), 'drawing start');

      await tapToolbarButton(
        tester,
        const ValueKey<String>('shared-edit-button'),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('rename-frame-text-field')),
        'A1',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('rename-frame-ok-button')),
      );
      await tester.pumpAndSettle();

      expect(selectedCellStateLabel(tester), 'drawing start A1');

      // Marks live on held/empty cells (never on a drawing start): hold the
      // block one frame longer, then mark the held cell.
      await dragBlockEndGrip(tester, 'default-layer-1', 0, 1);
      await tapHomeTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-default-layer-1-1'),
      );
      await tapToolbarButton(
        tester,
        const ValueKey<String>('toggle-mark-button'),
      );

      expect(selectedCellStateLabel(tester), 'inbetween mark');
    },
  );

  testWidgets('selection status and toolbar state distinguish held cells', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    // delete/rename live in the Frame ▾ flyout now; enablement reads open
    // the menu themselves.
    expect(
      await isActionButtonEnabled(
        tester,
        const ValueKey<String>('shared-delete-button'),
      ),
      isFalse,
    );

    await tapHomeTimelineCell(
      tester,
      const ValueKey<String>('timeline-cell-default-layer-1-1'),
    );
    expectCurrentFrame(tester, 2);
    expect(selectedCellStateLabel(tester), isNull);
    expect(
      await isActionButtonEnabled(
        tester,
        const ValueKey<String>('shared-delete-button'),
      ),
      isFalse,
    );

    await tapHomeTimelineCell(
      tester,
      const ValueKey<String>('timeline-cell-default-layer-1-0'),
    );
    final newFrameButton = find.byKey(
      const ValueKey<String>('new-frame-button'),
    );
    await tester.ensureVisible(newFrameButton);
    await tester.pumpAndSettle();
    await tester.tap(newFrameButton);
    await tester.pumpAndSettle();
    expect(
      await isActionButtonEnabled(
        tester,
        const ValueKey<String>('shared-delete-button'),
      ),
      isTrue,
    );

    // Hold the block across frames 1-3, then cut the hold at frame 3.
    await dragBlockEndGrip(tester, 'default-layer-1', 0, 2);
    await tapHomeTimelineCell(
      tester,
      const ValueKey<String>('timeline-cell-default-layer-1-2'),
    );
    final blankButton = find.byKey(
      const ValueKey<String>('blank-exposure-button'),
    );
    await tester.ensureVisible(blankButton);
    await tester.pumpAndSettle();
    await tester.tap(blankButton);
    await tester.pumpAndSettle();
    expectCellText('default-layer-1', 2, 'X');

    await tapHomeTimelineCell(
      tester,
      const ValueKey<String>('timeline-cell-default-layer-1-1'),
    );
    expect(selectedCellStateLabel(tester), 'held exposure');
    // UI-R17 #1: held cells delete their COVERING block — the head-only
    // rule is gone.
    expect(
      await isActionButtonEnabled(
        tester,
        const ValueKey<String>('shared-delete-button'),
      ),
      isTrue,
    );
    expect(
      await isActionButtonEnabled(
        tester,
        const ValueKey<String>('shared-edit-button'),
      ),
      isTrue,
    );
  });

  testWidgets(
    'mark button toggles a held-cell dot without changing the drawing start',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());

      final markButton = find.byKey(
        const ValueKey<String>('toggle-mark-button'),
      );
      expect(markButton, findsOneWidget);
      expect(find.byTooltip('Mark ●'), findsOneWidget);

      // Dots are block-owned (UI-R9 #8): an empty cell offers no toggle.
      expect(
        await isActionButtonEnabled(
          tester,
          const ValueKey<String>('toggle-mark-button'),
        ),
        isFalse,
      );

      // Author a 2-frame block and stand on its held cell.
      await tapToolbarButton(
        tester,
        const ValueKey<String>('new-frame-button'),
      );
      await dragBlockEndGrip(tester, 'default-layer-1', 0, 1);
      await tapHomeTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-default-layer-1-1'),
      );

      await tester.ensureVisible(markButton);
      await tester.pumpAndSettle();
      await tester.tap(markButton);
      await tester.pumpAndSettle();

      expectCellText('default-layer-1', 1, '●');
      expect(
        anyCellSemanticsLabel('default-layer-1', 'inbetween mark'),
        isTrue,
      );
      // The drawing start is untouched.
      expectCellText('default-layer-1', 0, '○');

      await tester.ensureVisible(markButton);
      await tester.pumpAndSettle();
      await tester.tap(markButton);
      await tester.pumpAndSettle();

      expectNoCellText('default-layer-1', 1, '●');
      expect(
        anyCellSemanticsLabel('default-layer-1', 'inbetween mark'),
        isFalse,
      );
    },
  );

  testWidgets(
    'new frame replaces selected layer blank exposure with drawing start',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());
      await addLayer(tester);
      await tapHomeTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-default-layer-1-0'),
      );

      final newFrameButton = find.byKey(
        const ValueKey<String>('new-frame-button'),
      );
      await tester.ensureVisible(newFrameButton);
      await tester.pumpAndSettle();

      await tester.tap(newFrameButton);
      await tester.pumpAndSettle();

      expectCellText('default-layer-1', 0, '○');
      expectCellText('default-layer-2', 0, 'X');
      expect(anyCellSemanticsLabel('default-layer-1', 'drawing start'), isTrue);
      expect(
        anyCellSemanticsLabel('default-layer-1', 'inbetween mark'),
        isFalse,
      );
    },
  );

  testWidgets(
    'frame editing toolbar buttons, rename dialog, and delete cell work',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());

      final newFrameButton = find.byKey(
        const ValueKey<String>('new-frame-button'),
      );
      final markButton = find.byKey(
        const ValueKey<String>('toggle-mark-button'),
      );

      expect(
        await isActionButtonEnabled(
          tester,
          const ValueKey<String>('shared-edit-button'),
        ),
        isFalse,
      );
      expect(
        await isActionButtonEnabled(
          tester,
          const ValueKey<String>('shared-delete-button'),
        ),
        isFalse,
      );

      await tester.ensureVisible(newFrameButton);
      await tester.pumpAndSettle();
      await tester.tap(newFrameButton);
      await tester.pumpAndSettle();

      expect(
        await isActionButtonEnabled(
          tester,
          const ValueKey<String>('shared-edit-button'),
        ),
        isTrue,
      );
      await tapToolbarButton(
        tester,
        const ValueKey<String>('shared-edit-button'),
      );

      expect(
        find.byKey(const ValueKey<String>('rename-frame-dialog')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('rename-frame-text-field')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('rename-frame-text-field')),
        'A1',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('rename-frame-ok-button')),
      );
      await tester.pumpAndSettle();
      expectCellText('default-layer-1', 0, 'A1');

      // Marks live on held/empty cells only; on a drawing start the mark
      // button is disabled under the unified model.
      expect(
        await isActionButtonEnabled(
          tester,
          const ValueKey<String>('toggle-mark-button'),
        ),
        isFalse,
      );
      expect(markButton, findsOneWidget);

      expect(
        await isActionButtonEnabled(
          tester,
          const ValueKey<String>('shared-delete-button'),
        ),
        isTrue,
      );
      await tapToolbarButton(
        tester,
        const ValueKey<String>('shared-delete-button'),
      );
      expectNoCellText('default-layer-1', 0, 'A1');
      expectNoCellText('default-layer-1', 0, '●');
      expect(
        await isActionButtonEnabled(
          tester,
          const ValueKey<String>('shared-edit-button'),
        ),
        isFalse,
      );
      expect(
        await isActionButtonEnabled(
          tester,
          const ValueKey<String>('shared-delete-button'),
        ),
        isFalse,
      );
    },
  );
}
