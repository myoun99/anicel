// The probes every HomePage widget test drives: the toolbar, the cut
// list, the cut note dialog, the timeline cells and their labels. Split
// out of widget_test.dart (2026-09-04) with that file, so the topics
// can run across isolates.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import 'package:anicel/src/ui/editor_workspace.dart';

import '../ui/storyboard_cut_block_probe.dart';
import '../ui/timeline/timeline_cell_probe.dart';
import '../ui/timeline/timeline_row_chrome_probe.dart';

import '../ui/flyout_test_helpers.dart'
    show flyoutOwnerByItemKey, readCommandEnabled;

Future<void> tapToolbarButton(WidgetTester tester, ValueKey<String> key) async {
  final owner = flyoutOwnerByItemKey[key.value];
  if (owner != null) {
    final menuButton = find.byKey(ValueKey<String>(owner));
    await tester.ensureVisible(menuButton);
    await tester.pumpAndSettle();
    await tester.tap(menuButton);
    await tester.pumpAndSettle();
  }
  final button = find.byKey(key);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> addLayer(WidgetTester tester) async {
  await tapToolbarButton(
    tester,
    const ValueKey<String>('timeline-toolbar-add-layer-button'),
  );
}

Finder timelineLayerRows() {
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> &&
        key.value.startsWith('timeline-layer-row-');
  });
}

Future<void> tapHomeTimelineCell(
  WidgetTester tester,
  ValueKey<String> key,
) async {
  // Painted drawing rows carry no per-cell widgets (UI-R9 #12b): resolve
  // the tap point through the painter probe; sparse rows (SE / camera /
  // instruction) still expose their cell keys.
  final cell = find.byKey(key);
  if (cell.evaluate().isNotEmpty) {
    await tester.ensureVisible(cell);
    await tester.pumpAndSettle();
    await tester.tap(cell);
    await tester.pumpAndSettle();
    return;
  }
  final parsed = parseTimelineCellKey(key.value);
  await tester.tapAt(
    timelineCellCenter(tester, parsed.layerId, parsed.frameIndex),
  );
  await tester.pumpAndSettle();
}

/// The top chips bar is retired: the storyboard panel is the cut oracle and
/// actuator now. It only exists in storyboard mode, so these helpers hop in,
/// act or read, and restore the timeline when they had to switch. Never call
/// them while a dialog is open — the mode toggle would tap the modal barrier.
Future<T> _withStoryboardPanel<T>(
  WidgetTester tester,
  Future<T> Function(StoryboardPanel panel) act,
) async {
  final wasHidden = find.byType(StoryboardPanel).evaluate().isEmpty;
  if (wasHidden) {
    await showStoryboardPanel(tester);
  }
  final result = await act(
    tester.widget<StoryboardPanel>(find.byType(StoryboardPanel)),
  );
  if (wasHidden) {
    await showTimelinePanel(tester);
  }
  return result;
}

Future<void> switchToCut(WidgetTester tester, String cutId) async {
  await _withStoryboardPanel(tester, (panel) async {
    final entries = buildStoryboardTimelineLayout(panel.project);
    expect(entries.map((entry) => entry.cutId.value), contains(cutId));
    final entry = entries.firstWhere((entry) => entry.cutId.value == cutId);

    // The cells press: a row and a frame INSIDE the cut — the seek behind
    // it is what makes that cut active.
    panel.onRowFramePress!(TrackRowAddress(entry.trackId), entry.startFrame);
    await tester.pumpAndSettle();
  });
}

Future<void> tapStoryboardCutBlock(WidgetTester tester, String cutId) async {
  await _withStoryboardPanel(tester, (panel) async {
    // The block's geometric centre is not always a point you can touch: the
    // rows scroll, so a block near the right edge is drawn partly outside
    // the panel's clip and its middle lands on whatever is beyond. Tap the
    // middle of the part that is actually ON SCREEN — which is what a hand
    // would do, and what stops this from depending on how wide the panel
    // happens to be.
    final block = cutBlockScreenRect(tester, cutId);
    final visible = block.intersect(
      tester.getRect(find.byType(StoryboardPanel)),
    );
    expect(
      visible.width,
      greaterThan(0),
      reason: 'no visible part of $cutId to tap',
    );
    // ⚠️A QUARTER IN, not the middle (H13, 2026-08-22). A layerless cut now
    // wears its create '+' whether or not it is the active one, and that
    // square is centred in the strip — so the geometric centre is a button,
    // and tapping it here would author a storyboard layer instead of
    // selecting. A hand aiming at "this cut" has the whole rest of the
    // block; this helper takes the same room.
    await tester.tapAt(
      Offset(visible.left + visible.width * 0.25, visible.center.dy),
    );
    await tester.pumpAndSettle();
  });
}

Future<void> createSecondCut(WidgetTester tester) async {
  await tapCutCommandButton(tester, const ValueKey<String>('new-cut-button'));
}

Future<void> expectCutName(
  WidgetTester tester,
  String cutId,
  String text,
) async {
  await _withStoryboardPanel(tester, (panel) async {
    expect(requireCutBlock(tester, cutId).title, text);
  });
}

Future<void> expectCutExists(
  WidgetTester tester,
  String cutId, {
  required bool exists,
}) async {
  await _withStoryboardPanel(tester, (panel) async {
    expect(cutBlock(tester, cutId), exists ? isNotNull : isNull);
  });
}

Future<void> expectCutsNamed(
  WidgetTester tester,
  String name,
  int count,
) async {
  await _withStoryboardPanel(tester, (panel) async {
    expect(
      cutBlocks(tester).where((block) => block.title == name).length,
      count,
    );
  });
}

Future<void> expectActiveCutName(WidgetTester tester, String name) async {
  await _withStoryboardPanel(tester, (panel) async {
    // The block highlight carries the active state (no ACTIVE badge);
    // the panel's activeCutId is the oracle for WHICH cut that is.
    expect(requireCutBlock(tester, panel.activeCutId!.value).title, name);
  });
}

/// Drags [sourceCutId] far enough to take [targetCutId]'s place.
///
/// Reordering is the MOVE drag reaching past a neighbour now, so this
/// drives the panel's move hooks with the frame delta that carries the
/// source's midpoint onto the target's. Dragging LEFT needs one frame more:
/// a midpoint exactly level with another still belongs to the cut that
/// already holds the rank.
Future<void> dragCutOnto(
  WidgetTester tester, {
  required String sourceCutId,
  required String targetCutId,
}) async {
  await _withStoryboardPanel(tester, (panel) async {
    final layout = buildStoryboardTimelineLayout(panel.project);
    final source = layout.singleWhere(
      (entry) => entry.cutId.value == sourceCutId,
    );
    final target = layout.singleWhere(
      (entry) => entry.cutId.value == targetCutId,
    );
    final delta = target.startFrame - source.startFrame;

    final cutMove = panel.cutMove!;
    expect(cutMove.onBegin(CutId(sourceCutId)), isTrue);
    cutMove.onUpdate(delta < 0 ? delta - 1 : delta);
    cutMove.onEnd();

    await tester.pumpAndSettle();
  });
}

// Painted drawing rows (UI-R9 #12b): the cell glyph reads off the painter
// probe — finder evaluation needs no tester, so these keep their
// tester-less signatures.
TimelineRowCellsPainter rowPainter(String layerId) {
  final element = find
      .byKey(ValueKey<String>('timeline-row-cells-$layerId'))
      .evaluate()
      .single;
  return (element.widget as CustomPaint).painter! as TimelineRowCellsPainter;
}

void expectCellText(String layerId, int frameIndex, String text) {
  expect(rowPainter(layerId).cellModelAt(frameIndex).glyph, text);
}

/// Whether any cell in [layerId]'s built window carries [label] — the
/// painted successor of `find.bySemanticsLabel` over drawing cells.
bool anyCellSemanticsLabel(String layerId, String label) {
  final painter = rowPainter(layerId);
  for (
    var frameIndex = painter.frameStartIndex;
    frameIndex < painter.frameEndIndexExclusive;
    frameIndex += 1
  ) {
    if (painter.cellModelAt(frameIndex).semanticsLabel == label) {
      return true;
    }
  }
  return false;
}

void expectNoCellText(String layerId, int frameIndex, String text) {
  expect(rowPainter(layerId).cellModelAt(frameIndex).glyph, isNot(text));
}

Future<void> renameCurrentFrame(WidgetTester tester, String name) async {
  await tapToolbarButton(tester, const ValueKey<String>('shared-edit-button'));
  await tester.enterText(
    find.byKey(const ValueKey<String>('rename-frame-text-field')),
    name,
  );
  await tester.tap(
    find.byKey(const ValueKey<String>('rename-frame-ok-button')),
  );
  await tester.pumpAndSettle();
}

Future<void> openCutNoteDialog(WidgetTester tester) async {
  await tapCutCommandButton(
    tester,
    const ValueKey<String>('edit-cut-note-button'),
  );
}

Future<void> saveCutNote(WidgetTester tester, String note) async {
  await openCutNoteDialog(tester);
  await tester.enterText(
    find.byKey(const ValueKey<String>('cut-note-text-field')),
    note,
  );
  await tapCutNoteSaveButton(tester);
}

Future<void> tapCutNoteSaveButton(WidgetTester tester) async {
  final saveButton = find.byKey(const ValueKey<String>('save-cut-note-button'));
  await tester.ensureVisible(saveButton);
  await tester.pumpAndSettle();
  await tester.tap(saveButton);
  await tester.pumpAndSettle();
  await showTimelinePanel(tester);
}

Future<void> tapCutNoteCancelButton(WidgetTester tester) async {
  final cancelButton = find.byKey(
    const ValueKey<String>('cancel-cut-note-button'),
  );
  await tester.ensureVisible(cancelButton);
  await tester.pumpAndSettle();
  await tester.tap(cancelButton);
  await tester.pumpAndSettle();
  await showTimelinePanel(tester);
}

String cutNoteFieldText(WidgetTester tester) {
  return tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('cut-note-text-field')),
          )
          .controller
          ?.text ??
      '';
}

Future<String> currentCutNoteFromDialog(WidgetTester tester) async {
  await openCutNoteDialog(tester);
  final note = cutNoteFieldText(tester);
  await tapCutNoteCancelButton(tester);
  return note;
}

Future<void> renameActiveCut(WidgetTester tester, String name) async {
  await tapCutCommandButton(
    tester,
    const ValueKey<String>('rename-cut-button'),
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('rename-cut-text-field')),
    name,
  );
  await tester.tap(
    find.byKey(const ValueKey<String>('rename-cut-confirm-button')),
  );
  await tester.pumpAndSettle();
  // The command left the app in storyboard mode (the dialog blocked the
  // automatic return); restore the timeline the tests assume.
  await showTimelinePanel(tester);
}

Future<void> createSecondAuthoredFrame(WidgetTester tester) async {
  await tapHomeTimelineCell(
    tester,
    const ValueKey<String>('timeline-cell-default-layer-1-1'),
  );
  await tapToolbarButton(
    tester,
    const ValueKey<String>('blank-exposure-button'),
  );
  await tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));
}

String statusText(WidgetTester tester, ValueKey<String> key) {
  final status = tester.widget<Text>(find.byKey(key));
  return status.data ?? '';
}

void expectActiveLayerName(String name) {
  expect(
    find.descendant(
      of: find.byKey(const ValueKey<String>('timeline-selected-layer')),
      matching: find.text(name),
    ),
    findsOneWidget,
  );
}

void expectCurrentFrame(WidgetTester tester, int frameNumber) {
  // The counter is two stacked lines (2026-08-10) — track-global above,
  // cut-local below. This is the timeline, where the top line is blank, so
  // the number under assertion is the LOCAL one.
  expect(
    statusText(tester, const ValueKey<String>('timeline-local-frame-counter')),
    '$frameNumber',
  );
}

String? selectedCellStateLabel(WidgetTester tester) {
  // The selection ring lives on the grid cursor layer, positioned exactly
  // over the selected cell — find the cell sharing its top-left and read
  // its marker semantics. Drawing rows are PAINTED (UI-R9 #12b): scan the
  // row painters' geometry first, then the sparse widget cells.
  final ringTopLeft = tester.getTopLeft(
    find.byKey(const ValueKey<String>('timeline-selected-cell')),
  );
  final paintedRows = find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith(
          'timeline-row-cells-',
        ),
  );
  for (final element in paintedRows.evaluate()) {
    final painter =
        (element.widget as CustomPaint).painter! as TimelineRowCellsPainter;
    final box = element.renderObject! as RenderBox;
    for (
      var frameIndex = painter.frameStartIndex;
      frameIndex < painter.frameEndIndexExclusive;
      frameIndex += 1
    ) {
      final topLeft = box.localToGlobal(
        painter.cellRectFor(frameIndex).topLeft,
      );
      if ((topLeft - ringTopLeft).distance < 0.5) {
        return painter.cellModelAt(frameIndex).semanticsLabel;
      }
    }
  }
  final cells = find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith('timeline-cell-'),
  );
  for (final element in cells.evaluate()) {
    final cellFinder = find.byKey(element.widget.key!);
    if (tester.getTopLeft(cellFinder) != ringTopLeft) {
      continue;
    }
    final texts = tester.widgetList<Text>(
      find.descendant(of: cellFinder, matching: find.byType(Text)),
    );
    return texts.isEmpty ? null : texts.first.semanticsLabel;
  }
  return null;
}

Future<void> showStoryboardPanel(WidgetTester tester) async {
  await tapToolbarButton(
    tester,
    const ValueKey<String>('timeline-mode-storyboard-button'),
  );
}

Future<void> showTimelinePanel(WidgetTester tester) async {
  await tapToolbarButton(
    tester,
    const ValueKey<String>('timeline-mode-timeline-button'),
  );
}

Future<bool> isActionButtonEnabled(
  WidgetTester tester,
  ValueKey<String> key,
) async {
  // Flyout-hosted commands (R-toolbar round) read their enablement off the
  // menu item; direct buttons keep the widget check.
  if (flyoutOwnerByItemKey.containsKey(key.value)) {
    return readCommandEnabled(tester, key);
  }
  final button = find.byKey(key);
  final widget = tester.widget(button);

  return switch (widget) {
    TextButton(:final onPressed) => onPressed != null,
    IconButton(:final onPressed) => onPressed != null,
    _ => isDescendantIconButtonEnabled(tester, button),
  };
}

/// Exposure ± buttons are RETIRED (the block edge grips replaced them):
/// lengthen a block by dragging its end grip [frames] slim 24px cells. The
/// slop counts toward those cells (R10), so the moves below are sized from
/// the total.
Future<void> dragBlockEndGrip(
  WidgetTester tester,
  String layerId,
  int blockOrdinal,
  int frames,
) async {
  // Scroll via the RAIL row — cell/grip-level ensureVisible would
  // over-scroll the custom frame viewport (the comma-grip test's note).
  //
  // The TOTAL travel is what decides the step (R10: the pixels spent
  // winning the arena are travel, not overhead), so the two moves are
  // sized together: 19 to clear the 18px slop, then the remainder of
  // `frames` 24px cells plus a small overshoot that keeps the rounding
  // away from the exact boundary. Sizing the second move alone is what
  // this helper used to do, and it silently grew every fixture by one
  // extra frame the moment the slop stopped being discarded.
  await tester.ensureVisible(
    find.byKey(ValueKey<String>('timeline-layer-row-$layerId')),
  );
  await tester.pumpAndSettle();
  final gesture = await tester.startGesture(
    timelineRowChromeCenter(
      tester,
      layerId,
      'block-edge-grip-end-$layerId-$blockOrdinal',
    ),
  );
  await gesture.moveBy(const Offset(19, 0));
  await tester.pump();
  await gesture.moveBy(Offset(frames * 24.0 + 11 - 19, 0));
  await tester.pumpAndSettle();
  await gesture.up();
  await tester.pumpAndSettle();
}

bool isDescendantIconButtonEnabled(WidgetTester tester, Finder button) {
  final iconButton = tester.widget<IconButton>(
    find.descendant(of: button, matching: find.byType(IconButton)),
  );
  return iconButton.onPressed != null;
}

IconData layerKindIcon(WidgetTester tester, String layerId) {
  final finder = find.byKey(
    ValueKey<String>('timeline-layer-kind-icon-$layerId'),
  );
  return tester.widget<Icon>(finder).icon!;
}

Future<void> expectCutOrder(WidgetTester tester, List<String> cutIds) async {
  await _withStoryboardPanel(tester, (panel) async {
    expect(
      buildStoryboardTimelineLayout(
        panel.project,
      ).map((entry) => entry.cutId.value).toList(),
      cutIds,
    );
  });
}

Future<CutId> activeCutIdOf(WidgetTester tester) {
  return _withStoryboardPanel(tester, (panel) async => panel.activeCutId!);
}

Future<void> tapCutCommandButton(
  WidgetTester tester,
  ValueKey<String> key,
) async {
  // R-toolbar round: the cut command group rides BOTH tab toolbars, so no
  // mode switching is needed — the split new-cut button is direct and the
  // rest are Cut ▾ flyout items (the menu-aware helper handles both).
  await tapToolbarButton(tester, key);
}

/// Deletes the active cut the way the app now can.
///
/// T24 retired `delete-cut-button`. The one shared delete reaches a cut
/// through a cut SELECTION, and that axis lives on the storyboard — which is
/// where cut editing belongs (유저 2026-08-13: 「컷 편집은 스토리보드
/// 패널에서 하는거고」). The two tests below are about what deleting a cut
/// DOES; the ENTRANCE is `shared_delete_pill_test`'s subject, so miming a
/// timeline door here would be a test of a button that no longer exists.
Future<void> deleteActiveCut(WidgetTester tester) async {
  tester
      .widget<EditorWorkspace>(find.byType(EditorWorkspace))
      .session
      .deleteActiveCut();
  await tester.pumpAndSettle();
}

Future<void> tapTopBarButton(WidgetTester tester, ValueKey<String> key) async {
  final button = find.byKey(key);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> tapUndoButton(WidgetTester tester) async {
  await tapTopBarButton(tester, const ValueKey<String>('undo-button'));
}

Future<void> tapRedoButton(WidgetTester tester) async {
  await tapTopBarButton(tester, const ValueKey<String>('redo-button'));
}

void expectTimelineActionTooltips() {
  // Direct icons only (R-toolbar round) — the rest moved into the Layer ▾ /
  // Frame ▾ flyouts, and the exposure ± buttons are GONE (edge grips).
  expect(find.byTooltip('Add'), findsOneWidget);
  expect(find.byTooltip('Blank / X'), findsOneWidget);
  expect(find.byTooltip('Mark ●'), findsOneWidget);
  expect(find.byTooltip('Decrease Exposure'), findsNothing);
  expect(find.byTooltip('Increase Exposure'), findsNothing);
}

Future<void> expectTimelineActionKeys(WidgetTester tester) async {
  expect(
    find.byKey(const ValueKey<String>('new-frame-button')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey<String>('blank-exposure-button')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey<String>('toggle-mark-button')),
    findsOneWidget,
  );
  // The frame commands live inside the Frame ▾ flyout now. The comma row
  // (UI-R17 #7) widened the toolbar, so scroll the menu button into view.
  final frameMenuButton = find.byKey(
    const ValueKey<String>('timeline-frame-menu-button'),
  );
  await tester.ensureVisible(frameMenuButton);
  await tester.pumpAndSettle();
  await tester.tap(frameMenuButton);
  await tester.pumpAndSettle();
  // D40: the whole-row select rides the frame menu.
  expect(
    find.byKey(const ValueKey<String>('select-row-span-button')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey<String>('shared-copy-button')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey<String>('shared-paste-linked-button')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey<String>('shared-edit-button')),
    findsOneWidget,
  );
  // T24: the frame menu's delete went the way the cut and layer ones did —
  // the shared pill's one delete falls through to the same verb.
  expect(
    find.byKey(const ValueKey<String>('delete-cell-button')),
    findsNothing,
  );
  // The exposure ± buttons are gone outright (edge grips replaced them).
  expect(
    find.byKey(const ValueKey<String>('decrease-exposure-button')),
    findsNothing,
  );
  expect(
    find.byKey(const ValueKey<String>('increase-exposure-button')),
    findsNothing,
  );
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

/// Frame-axis SCROLL tests run under the PRODUCT default (touch scrolls
/// the grids, UI-R22F): the corpus baseline is OFF (touch-as-pen) via
/// flutter_test_config, and under OFF a cell-area touch drag EDITS (the
/// eager pan claims it) instead of scrolling.
void withTouchScroll() {
  AppInput.settings.value = const AppInputSettings();
  addTearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });
}
