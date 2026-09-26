// HomePage widget tests — the cut list: order, create, duplicate, delete.
// Split from widget_test.dart (2026-09-04) so the suite runs across
// isolates; the shared probes live in helpers/home_page_probes.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart' show unnamedDrawingMark;
import 'package:anicel/main.dart';
import 'package:anicel/src/models/cut_id.dart';

import 'helpers/home_page_probes.dart';

void main() {
  testWidgets('top row keeps cut switching and undo redo reachable', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    // The old top chips bar is retired; cut switching lives in the
    // storyboard panel now.
    expect(
      find.byKey(const ValueKey<String>('top-toolbar-scroll-view')),
      findsNothing,
    );
    await expectCutExists(tester, 'default-cut-1', exists: true);
    expect(find.byKey(const ValueKey<String>('undo-button')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('redo-button')), findsOneWidget);

    await tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));
    expectCellMark('default-layer-1', 0, unnamedDrawingMark);

    await tapUndoButton(tester);

    expectCellText('default-layer-1', 0, 'X');
    expectNoCellMark('default-layer-1', 0, unnamedDrawingMark);

    await tapRedoButton(tester);

    expectCellMark('default-layer-1', 0, unnamedDrawingMark);
  });

  testWidgets('dragging Cut 2 before Cut 1 keeps Cut 2 active', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    final second = await createSecondCut(tester);

    await switchToCut(tester, second);
    await expectActiveCutName(tester, '2');
    await expectCutOrder(tester, ['default-cut-1', second]);

    await dragCutOnto(
      tester,
      sourceCutId: second,
      targetCutId: 'default-cut-1',
    );

    await expectCutOrder(tester, [second, 'default-cut-1']);
    await expectActiveCutName(tester, '2');
    expect(await activeCutIdOf(tester), CutId(second));
  });

  testWidgets('dragging Cut 1 after Cut 2 supports undo and redo', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    final second = await createSecondCut(tester);
    await switchToCut(tester, 'default-cut-1');

    await expectActiveCutName(tester, '1');
    await expectCutOrder(tester, ['default-cut-1', second]);

    await dragCutOnto(
      tester,
      sourceCutId: 'default-cut-1',
      targetCutId: second,
    );

    await expectCutOrder(tester, [second, 'default-cut-1']);
    await expectActiveCutName(tester, '1');
    expect(await activeCutIdOf(tester), const CutId('default-cut-1'));

    await tapUndoButton(tester);

    await expectCutOrder(tester, ['default-cut-1', second]);
    await expectActiveCutName(tester, '1');
    expect(await activeCutIdOf(tester), const CutId('default-cut-1'));

    await tapRedoButton(tester);

    await expectCutOrder(tester, [second, 'default-cut-1']);
    await expectActiveCutName(tester, '1');
    expect(await activeCutIdOf(tester), const CutId('default-cut-1'));
  });

  testWidgets('move cut buttons reorder active cut left with undo and redo', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    final second = await createSecondCut(tester);

    await switchToCut(tester, second);
    await expectActiveCutName(tester, '2');
    await expectCutOrder(tester, ['default-cut-1', second]);

    await tapCutCommandButton(
      tester,
      const ValueKey<String>('move-cut-left-button'),
    );

    await expectCutOrder(tester, [second, 'default-cut-1']);
    await expectActiveCutName(tester, '2');
    expect(await activeCutIdOf(tester), CutId(second));

    await tapUndoButton(tester);

    await expectCutOrder(tester, ['default-cut-1', second]);
    await expectActiveCutName(tester, '2');

    await tapRedoButton(tester);

    await expectCutOrder(tester, [second, 'default-cut-1']);
    await expectActiveCutName(tester, '2');
  });

  testWidgets('move cut buttons reorder active cut right with undo and redo', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    final second = await createSecondCut(tester);
    await switchToCut(tester, 'default-cut-1');

    await expectActiveCutName(tester, '1');
    await expectCutOrder(tester, ['default-cut-1', second]);

    await tapCutCommandButton(
      tester,
      const ValueKey<String>('move-cut-right-button'),
    );

    await expectCutOrder(tester, [second, 'default-cut-1']);
    await expectActiveCutName(tester, '1');
    expect(await activeCutIdOf(tester), const CutId('default-cut-1'));

    await tapUndoButton(tester);

    await expectCutOrder(tester, ['default-cut-1', second]);
    await expectActiveCutName(tester, '1');

    await tapRedoButton(tester);

    await expectCutOrder(tester, [second, 'default-cut-1']);
    await expectActiveCutName(tester, '1');
  });

  testWidgets('move cut buttons are disabled at cut list edges', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    final second = await createSecondCut(tester);
    await switchToCut(tester, 'default-cut-1');
    // The move buttons live in the storyboard panel's toolbar.
    await showStoryboardPanel(tester);

    expect(
      await isActionButtonEnabled(
        tester,
        const ValueKey<String>('move-cut-left-button'),
      ),
      isFalse,
    );
    expect(
      await isActionButtonEnabled(
        tester,
        const ValueKey<String>('move-cut-right-button'),
      ),
      isTrue,
    );

    await switchToCut(tester, second);

    expect(
      await isActionButtonEnabled(
        tester,
        const ValueKey<String>('move-cut-left-button'),
      ),
      isTrue,
    );
    expect(
      await isActionButtonEnabled(
        tester,
        const ValueKey<String>('move-cut-right-button'),
      ),
      isFalse,
    );
  });

  testWidgets('creates a new cut from the cut list command', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await expectCutOrder(tester, ['default-cut-1']);

    await tapCutCommandButton(tester, const ValueKey<String>('new-cut-button'));

    final second = (await activeCutIdOf(tester)).value;
    await expectCutOrder(tester, ['default-cut-1', second]);
    await expectCutName(tester, second, '2');
    await expectActiveCutName(tester, '2');
    await expectCutName(tester, 'default-cut-1', '1');
    await expectCutsNamed(tester, 'Cut 2', 0);
  });

  testWidgets('duplicates the active cut from the cut list command', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await expectCutOrder(tester, ['default-cut-1']);

    await tapCutCommandButton(
      tester,
      const ValueKey<String>('duplicate-cut-button'),
    );

    final copy = (await activeCutIdOf(tester)).value;
    await expectCutName(tester, 'default-cut-1', '1');
    await expectCutName(tester, copy, '1 Copy');
    await expectCutsNamed(tester, 'Cut 2', 0);
    await expectCutExists(tester, 'default-cut-1', exists: true);
    await expectActiveCutName(tester, '1 Copy');
    expect(find.byTooltip('Linked Cut'), findsNothing);
  });

  testWidgets('deletes the active cut from the cut list command', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    final second = await createSecondCut(tester);
    await switchToCut(tester, 'default-cut-1');

    await expectCutName(tester, 'default-cut-1', '1');
    await expectCutName(tester, second, '2');

    await deleteActiveCut(tester);

    await expectCutExists(tester, 'default-cut-1', exists: false);
    await expectCutExists(tester, 'default-cut-1', exists: false);
    await expectCutExists(tester, second, exists: true);
    await expectActiveCutName(tester, '2');
  });

  testWidgets('R28 #14: deleting the last cut EMPTIES the track — the app '
      'stands in the no-active-cut state instead of conjuring a stand-in', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await deleteActiveCut(tester);

    await expectCutOrder(tester, const []);
    // The shell survives with nothing active — the same state a storyboard
    // gap parks in.
    expect(tester.takeException(), isNull);
  });
}
