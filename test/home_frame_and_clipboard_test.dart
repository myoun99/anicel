// HomePage widget tests — frame names and the clipboard verbs.
// Split from widget_test.dart (2026-09-04) so the suite runs across
// isolates; the shared probes live in helpers/home_page_probes.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/models/timeline_row_address.dart';

import 'package:anicel/src/ui/editor_workspace.dart';

import 'helpers/home_page_probes.dart';

void main() {
  testWidgets('rename to empty clears frame name', (WidgetTester tester) async {
    await tester.pumpWidget(const AnicelApp());

    await tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));
    await renameCurrentFrame(tester, 'A1');
    expectCellText('default-layer-1', 0, 'A1');

    await renameCurrentFrame(tester, '   ');

    expectCellText('default-layer-1', 0, '○');
  });

  testWidgets('conflicting frame name dialog cancel leaves frames unchanged', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));
    await renameCurrentFrame(tester, 'A1');
    await createSecondAuthoredFrame(tester);

    await renameCurrentFrame(tester, 'A1');

    expect(
      find.byKey(const ValueKey<String>('frame-name-conflict-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('frame-name-conflict-cancel-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('frame-name-conflict-link-button')),
      findsOneWidget,
    );
    expect(find.text('Rename only'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('frame-name-conflict-cancel-button')),
    );
    await tester.pumpAndSettle();

    expectCellText('default-layer-1', 0, 'A1');
    expectCellText('default-layer-1', 1, '○');
  });

  testWidgets('conflicting frame name link merges into existing material', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));
    await renameCurrentFrame(tester, 'A1');
    await createSecondAuthoredFrame(tester);

    await renameCurrentFrame(tester, 'A1');
    await tester.tap(
      find.byKey(const ValueKey<String>('frame-name-conflict-link-button')),
    );
    await tester.pumpAndSettle();

    expectCellText('default-layer-1', 0, 'A1');
    expectCellText('default-layer-1', 1, 'A1');
    expect(find.text('Rename only'), findsNothing);
  });

  testWidgets('rename cancel leaves frame marker unchanged', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    final newFrameButton = find.byKey(
      const ValueKey<String>('new-frame-button'),
    );

    await tester.ensureVisible(newFrameButton);
    await tester.pumpAndSettle();
    await tester.tap(newFrameButton);
    await tester.pumpAndSettle();
    await tapToolbarButton(
      tester,
      const ValueKey<String>('shared-edit-button'),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('rename-frame-text-field')),
      'Cancelled',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('rename-frame-cancel-button')),
    );
    await tester.pumpAndSettle();
    expectCellText('default-layer-1', 0, '○');
    expect(find.text('Cancelled'), findsNothing);
  });

  testWidgets('linked frame copy and paste buttons link authored exposures', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    // Copy/paste-linked live in the Frame ▾ flyout (R-toolbar round);
    // enablement reads open the menu themselves.
    expect(
      await isActionButtonEnabled(
        tester,
        const ValueKey<String>('shared-copy-button'),
      ),
      isFalse,
    );
    expect(
      await isActionButtonEnabled(
        tester,
        const ValueKey<String>('shared-paste-linked-button'),
      ),
      isFalse,
    );

    await tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));

    expect(
      await isActionButtonEnabled(
        tester,
        const ValueKey<String>('shared-copy-button'),
      ),
      isTrue,
    );

    await tapToolbarButton(
      tester,
      const ValueKey<String>('shared-copy-button'),
    );
    expect(
      await isActionButtonEnabled(
        tester,
        const ValueKey<String>('shared-paste-linked-button'),
      ),
      isTrue,
    );

    await tapHomeTimelineCell(
      tester,
      const ValueKey<String>('timeline-cell-default-layer-1-1'),
    );

    await tapToolbarButton(
      tester,
      const ValueKey<String>('shared-paste-linked-button'),
    );

    expectCellText('default-layer-1', 0, '○');
    expectCellText('default-layer-1', 1, '○');
  });

  testWidgets(
    'linked paste on a dot-held cell: the drawing wins and the cut-off '
    'dot drops',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());

      await tapToolbarButton(
        tester,
        const ValueKey<String>('new-frame-button'),
      );
      await tapToolbarButton(
        tester,
        const ValueKey<String>('shared-copy-button'),
      );
      await addLayer(tester);

      await tapHomeTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-default-layer-2-0'),
      );
      expect(
        await isActionButtonEnabled(
          tester,
          const ValueKey<String>('shared-paste-linked-button'),
        ),
        isFalse,
      );

      // Grow the block to [0,2) and dot its held cell.
      await tapHomeTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-default-layer-1-0'),
      );
      await dragBlockEndGrip(tester, 'default-layer-1', 0, 1);
      await tapHomeTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-default-layer-1-1'),
      );
      await tapToolbarButton(
        tester,
        const ValueKey<String>('toggle-mark-button'),
      );
      expectCellText('default-layer-1', 1, '●');

      // The paste authors a drawing start on the dot's cell: the covering
      // block shrinks to [0,1) and the cut-off dot goes with it.
      await tapToolbarButton(
        tester,
        const ValueKey<String>('shared-paste-linked-button'),
      );

      expectNoCellText('default-layer-1', 1, '●');
      expectCellText('default-layer-1', 1, '○');
      expect(selectedCellStateLabel(tester), 'drawing start');
    },
  );

  testWidgets('Copy and Paste Layer buttons expose in-memory clipboard UI', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    const copyKey = ValueKey<String>('copy-layer-button');
    const pasteKey = ValueKey<String>('paste-layer-button');

    // Copy/paste live in the Layer ▾ flyout (R-toolbar round); the paste
    // item's LABEL carries the clipboard name.
    expect(await isActionButtonEnabled(tester, copyKey), isTrue);
    expect(await isActionButtonEnabled(tester, pasteKey), isFalse);

    await tapToolbarButton(tester, copyKey);

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-layer-menu-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Paste layer (A)'), findsOneWidget);
    await tester.tapAt(const Offset(5, 400));
    await tester.pumpAndSettle();
    expect(await isActionButtonEnabled(tester, pasteKey), isTrue);
  });

  testWidgets(
    'Paste Layer creates another A, selects it, and undo/redo works',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());

      await tapToolbarButton(
        tester,
        const ValueKey<String>('copy-layer-button'),
      );
      await tapToolbarButton(
        tester,
        const ValueKey<String>('paste-layer-button'),
      );

      expect(find.text('A'), findsWidgets);
      // Two drawing rows plus the always-present fixtures: S1·S2, CAM 1,
      // the camera, and the track's transition row.
      expect(timelineLayerRows(), findsNWidgets(7));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('timeline-selected-layer')),
          matching: find.text('A'),
        ),
        findsOneWidget,
      );

      await tapToolbarButton(tester, const ValueKey<String>('undo-button'));
      expect(timelineLayerRows(), findsNWidgets(6));

      await tapToolbarButton(tester, const ValueKey<String>('redo-button'));
      expect(timelineLayerRows(), findsNWidgets(7));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('timeline-selected-layer')),
          matching: find.text('A'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('pasted layer can be renamed and deleted', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await tapToolbarButton(tester, const ValueKey<String>('copy-layer-button'));
    await tapToolbarButton(
      tester,
      const ValueKey<String>('paste-layer-button'),
    );
    // T25: the loose rename is folded into the shared Edit Instance, whose
    // subject is the selection — so the row is named first, exactly as the
    // ONE delete already asks.
    {
      final session = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;
      session.rowSelectionVerbs.beginRowSelection(LayerRowAddress(session.activeLayerId!));
      await tester.pumpAndSettle();
    }
    await tapToolbarButton(
      tester,
      const ValueKey<String>('shared-edit-button'),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('rename-layer-text-field')),
      'Pasted',
    );
    await tapToolbarButton(
      tester,
      const ValueKey<String>('rename-layer-ok-button'),
    );

    expect(find.text('Pasted'), findsWidgets);

    // ⑰/F: the ONE delete asks what is selected, so the row is named first.
    // Standing on it is not naming it — ⑨ made those two states independent.
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.rowSelectionVerbs.beginRowSelection(LayerRowAddress(session.activeLayerId!));
    await tester.pumpAndSettle();
    await tapToolbarButton(
      tester,
      const ValueKey<String>('shared-delete-button'),
    );
    await tapToolbarButton(
      tester,
      const ValueKey<String>('delete-layer-confirm-button'),
    );

    expect(find.text('Pasted'), findsNothing);
  });

  testWidgets(
    'Duplicate Layer button duplicates active layer and selects copy',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());

      expect(
        await isActionButtonEnabled(
          tester,
          const ValueKey<String>('duplicate-layer-button'),
        ),
        isTrue,
      );

      await tapToolbarButton(
        tester,
        const ValueKey<String>('duplicate-layer-button'),
      );

      expect(find.text('A'), findsWidgets);
      // Two drawing rows plus the always-present fixtures: S1·S2, CAM 1,
      // the camera, and the track's transition row.
      expect(timelineLayerRows(), findsNWidgets(7));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('timeline-selected-layer')),
          matching: find.text('A'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('duplicated layer can be renamed and deleted', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await tapToolbarButton(
      tester,
      const ValueKey<String>('duplicate-layer-button'),
    );
    // T25: the loose rename is folded into the shared Edit Instance, whose
    // subject is the selection — so the row is named first, exactly as the
    // ONE delete already asks.
    {
      final session = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;
      session.rowSelectionVerbs.beginRowSelection(LayerRowAddress(session.activeLayerId!));
      await tester.pumpAndSettle();
    }
    await tapToolbarButton(
      tester,
      const ValueKey<String>('shared-edit-button'),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('rename-layer-text-field')),
      'Dup',
    );
    await tapToolbarButton(
      tester,
      const ValueKey<String>('rename-layer-ok-button'),
    );

    expect(find.text('Dup'), findsWidgets);

    // ⑰/F: name the row, then press the ONE delete.
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.rowSelectionVerbs.beginRowSelection(LayerRowAddress(session.activeLayerId!));
    await tester.pumpAndSettle();
    await tapToolbarButton(
      tester,
      const ValueKey<String>('shared-delete-button'),
    );
    await tapToolbarButton(
      tester,
      const ValueKey<String>('delete-layer-confirm-button'),
    );

    expect(find.text('Dup'), findsNothing);
  });
}
