import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/storyboard_timeline_layout.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

import 'helpers/vertical_text_finder.dart';
import 'ui/storyboard_cut_block_probe.dart';
import 'ui/timeline/timeline_cell_probe.dart';
import 'ui/timeline/timeline_row_chrome_probe.dart';
import 'ui/timeline/timeline_ruler_probe.dart';

import 'ui/flyout_test_helpers.dart'
    show readCommandEnabled, flyoutOwnerByItemKey;

Future<void> _tapToolbarButton(
  WidgetTester tester,
  ValueKey<String> key,
) async {
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

Future<void> _addLayer(WidgetTester tester) async {
  await _tapToolbarButton(
    tester,
    const ValueKey<String>('timeline-toolbar-add-layer-button'),
  );
}

Finder _timelineLayerRows() {
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> &&
        key.value.startsWith('timeline-layer-row-');
  });
}

Future<void> _tapTimelineCell(WidgetTester tester, ValueKey<String> key) async {
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
    await _showStoryboardPanel(tester);
  }
  final result = await act(
    tester.widget<StoryboardPanel>(find.byType(StoryboardPanel)),
  );
  if (wasHidden) {
    await _showTimelinePanel(tester);
  }
  return result;
}

Future<void> _switchToCut(WidgetTester tester, String cutId) async {
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

Future<void> _tapStoryboardCutBlock(WidgetTester tester, String cutId) async {
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
    await tester.tapAt(visible.center);
    await tester.pumpAndSettle();
  });
}

Future<void> _createSecondCut(WidgetTester tester) async {
  await _tapCutCommandButton(tester, const ValueKey<String>('new-cut-button'));
}

Future<void> _expectCutName(
  WidgetTester tester,
  String cutId,
  String text,
) async {
  await _withStoryboardPanel(tester, (panel) async {
    expect(requireCutBlock(tester, cutId).title, text);
  });
}

Future<void> _expectCutExists(
  WidgetTester tester,
  String cutId, {
  required bool exists,
}) async {
  await _withStoryboardPanel(tester, (panel) async {
    expect(cutBlock(tester, cutId), exists ? isNotNull : isNull);
  });
}

Future<void> _expectCutsNamed(
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

Future<void> _expectActiveCutName(WidgetTester tester, String name) async {
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
Future<void> _dragCutOnto(
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
TimelineRowCellsPainter _rowPainter(String layerId) {
  final element = find
      .byKey(ValueKey<String>('timeline-row-cells-$layerId'))
      .evaluate()
      .single;
  return (element.widget as CustomPaint).painter! as TimelineRowCellsPainter;
}

void _expectCellText(String layerId, int frameIndex, String text) {
  expect(_rowPainter(layerId).cellModelAt(frameIndex).glyph, text);
}

/// Whether any cell in [layerId]'s built window carries [label] — the
/// painted successor of `find.bySemanticsLabel` over drawing cells.
bool _anyCellSemanticsLabel(String layerId, String label) {
  final painter = _rowPainter(layerId);
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

void _expectNoCellText(String layerId, int frameIndex, String text) {
  expect(_rowPainter(layerId).cellModelAt(frameIndex).glyph, isNot(text));
}

Future<void> _renameCurrentFrame(WidgetTester tester, String name) async {
  await _tapToolbarButton(
    tester,
    const ValueKey<String>('rename-frame-button'),
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('rename-frame-text-field')),
    name,
  );
  await tester.tap(
    find.byKey(const ValueKey<String>('rename-frame-ok-button')),
  );
  await tester.pumpAndSettle();
}

Future<void> _openCutNoteDialog(WidgetTester tester) async {
  await _tapCutCommandButton(
    tester,
    const ValueKey<String>('edit-cut-note-button'),
  );
}

Future<void> _saveCutNote(WidgetTester tester, String note) async {
  await _openCutNoteDialog(tester);
  await tester.enterText(
    find.byKey(const ValueKey<String>('cut-note-text-field')),
    note,
  );
  await _tapCutNoteSaveButton(tester);
}

Future<void> _tapCutNoteSaveButton(WidgetTester tester) async {
  final saveButton = find.byKey(const ValueKey<String>('save-cut-note-button'));
  await tester.ensureVisible(saveButton);
  await tester.pumpAndSettle();
  await tester.tap(saveButton);
  await tester.pumpAndSettle();
  await _showTimelinePanel(tester);
}

Future<void> _tapCutNoteCancelButton(WidgetTester tester) async {
  final cancelButton = find.byKey(
    const ValueKey<String>('cancel-cut-note-button'),
  );
  await tester.ensureVisible(cancelButton);
  await tester.pumpAndSettle();
  await tester.tap(cancelButton);
  await tester.pumpAndSettle();
  await _showTimelinePanel(tester);
}

String _cutNoteFieldText(WidgetTester tester) {
  return tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('cut-note-text-field')),
          )
          .controller
          ?.text ??
      '';
}

Future<String> _currentCutNoteFromDialog(WidgetTester tester) async {
  await _openCutNoteDialog(tester);
  final note = _cutNoteFieldText(tester);
  await _tapCutNoteCancelButton(tester);
  return note;
}

Future<void> _renameActiveCut(WidgetTester tester, String name) async {
  await _tapCutCommandButton(
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
  await _showTimelinePanel(tester);
}

Future<void> _createSecondAuthoredFrame(WidgetTester tester) async {
  await _tapTimelineCell(
    tester,
    const ValueKey<String>('timeline-cell-default-layer-1-1'),
  );
  await _tapToolbarButton(
    tester,
    const ValueKey<String>('blank-exposure-button'),
  );
  await _tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));
}

String _statusText(WidgetTester tester, ValueKey<String> key) {
  final status = tester.widget<Text>(find.byKey(key));
  return status.data ?? '';
}

void _expectActiveLayerName(String name) {
  expect(
    find.descendant(
      of: find.byKey(const ValueKey<String>('timeline-selected-layer')),
      matching: find.text(name),
    ),
    findsOneWidget,
  );
}

void _expectCurrentFrame(WidgetTester tester, int frameNumber) {
  expect(
    _statusText(
      tester,
      const ValueKey<String>('timeline-current-frame-counter'),
    ),
    '$frameNumber',
  );
}

String? _selectedCellStateLabel(WidgetTester tester) {
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
        (widget.key as ValueKey<String>).value.startsWith(
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
        (widget.key as ValueKey<String>).value.startsWith('timeline-cell-'),
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

Future<void> _showStoryboardPanel(WidgetTester tester) async {
  await _tapToolbarButton(
    tester,
    const ValueKey<String>('timeline-mode-storyboard-button'),
  );
}

Future<void> _showTimelinePanel(WidgetTester tester) async {
  await _tapToolbarButton(
    tester,
    const ValueKey<String>('timeline-mode-timeline-button'),
  );
}

Future<bool> _isActionButtonEnabled(
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
    _ => _isDescendantIconButtonEnabled(tester, button),
  };
}

/// Exposure ± buttons are RETIRED (the block edge grips replaced them):
/// lengthen a block by dragging its end grip [frames] slim 24px cells. The
/// slop counts toward those cells (R10), so the moves below are sized from
/// the total.
Future<void> _dragBlockEndGrip(
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

bool _isDescendantIconButtonEnabled(WidgetTester tester, Finder button) {
  final iconButton = tester.widget<IconButton>(
    find.descendant(of: button, matching: find.byType(IconButton)),
  );
  return iconButton.onPressed != null;
}

IconData _layerKindIcon(WidgetTester tester, String layerId) {
  final finder = find.byKey(
    ValueKey<String>('timeline-layer-kind-icon-$layerId'),
  );
  return tester.widget<Icon>(finder).icon!;
}

Future<void> _expectCutOrder(WidgetTester tester, List<String> cutIds) async {
  await _withStoryboardPanel(tester, (panel) async {
    expect(
      buildStoryboardTimelineLayout(
        panel.project,
      ).map((entry) => entry.cutId.value).toList(),
      cutIds,
    );
  });
}

Future<CutId> _activeCutId(WidgetTester tester) {
  return _withStoryboardPanel(tester, (panel) async => panel.activeCutId!);
}

Future<void> _tapCutCommandButton(
  WidgetTester tester,
  ValueKey<String> key,
) async {
  // R-toolbar round: the cut command group rides BOTH tab toolbars, so no
  // mode switching is needed — the split new-cut button is direct and the
  // rest are Cut ▾ flyout items (the menu-aware helper handles both).
  await _tapToolbarButton(tester, key);
}

Future<void> _tapTopBarButton(WidgetTester tester, ValueKey<String> key) async {
  final button = find.byKey(key);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _tapUndoButton(WidgetTester tester) async {
  await _tapTopBarButton(tester, const ValueKey<String>('undo-button'));
}

Future<void> _tapRedoButton(WidgetTester tester) async {
  await _tapTopBarButton(tester, const ValueKey<String>('redo-button'));
}

void _expectTimelineActionTooltips() {
  // Direct icons only (R-toolbar round) — the rest moved into the Layer ▾ /
  // Frame ▾ flyouts, and the exposure ± buttons are GONE (edge grips).
  expect(find.byTooltip('Add'), findsOneWidget);
  expect(find.byTooltip('Blank / X'), findsOneWidget);
  expect(find.byTooltip('Mark ●'), findsOneWidget);
  expect(find.byTooltip('Decrease Exposure'), findsNothing);
  expect(find.byTooltip('Increase Exposure'), findsNothing);
}

Future<void> _expectTimelineActionKeys(WidgetTester tester) async {
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
  expect(
    find.byKey(const ValueKey<String>('copy-frame-button')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey<String>('paste-linked-frame-button')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey<String>('rename-frame-button')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey<String>('delete-cell-button')),
    findsOneWidget,
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
void _withTouchScroll() {
  AppInput.settings.value = const AppInputSettings(touchTimelineScroll: true);
  addTearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });
}

void main() {
  testWidgets('shows placeholder app shell', (WidgetTester tester) async {
    await tester.pumpWidget(const AnicelApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    // PEN-8 #1: the editor body sits inside a SafeArea so tablet OS
    // chrome (status bar, gesture areas) never overlaps the app.
    expect(find.byType(SafeArea), findsWidgets);
    // R26 #24: the app-name label is gone from the top strip.
    expect(find.text('Anicel'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('new-frame-button')),
      findsOneWidget,
    );
    expect(find.byTooltip('Add'), findsOneWidget);
    await _expectCutName(tester, 'default-cut-1', '1');
    await _expectActiveCutName(tester, '1');
    expect(find.text('New Drawing'), findsNothing);

    // Cut management rides the toolbar's cut group (R-toolbar round): a
    // split new-cut button plus the Cut ▾ flyout with the command set.
    expect(find.byTooltip('New cut'), findsOneWidget);
    final cutMenu = find.byKey(const ValueKey<String>('cut-menu-button'));
    await tester.ensureVisible(cutMenu);
    await tester.pumpAndSettle();
    await tester.tap(cutMenu);
    await tester.pumpAndSettle();
    for (final item in [
      'rename-cut-button',
      'edit-cut-note-button',
      'resize-cut-canvas-button',
      'duplicate-cut-button',
      'set-cut-thumbnail-button',
      'move-cut-left-button',
      'move-cut-right-button',
      'delete-cut-button',
    ]) {
      expect(find.byKey(ValueKey<String>(item)), findsOneWidget);
    }
    await tester.tapAt(const Offset(5, 400));
    await tester.pumpAndSettle();
  });

  testWidgets('default sample cut duration is 24 frames', (
    WidgetTester tester,
  ) async {
    _withTouchScroll();
    await tester.pumpWidget(const AnicelApp());

    // The bottom dock runs between the two vertical tool bars, so the
    // grid viewport is 88px narrower than the window — scroll far enough
    // for the cut's last frame header to materialize (24px slim cells:
    // don't overshoot past it either).
    await tester.drag(
      find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
      const Offset(-350, 0),
    );
    await tester.pumpAndSettle();

    expect(timelineHeaderInWindow(tester, 23), isTrue);
  });

  testWidgets('timeline frame axis: scrolling stays CLAMPED to the built '
      'cells; the ruler edge-drag alone extends it (UI-R12 #16)', (
    WidgetTester tester,
  ) async {
    _withTouchScroll();
    await tester.pumpWidget(const AnicelApp());

    // Painterized ruler (UI-R13 #1): headers past the base exist exactly
    // when the painter's window reaches past 48.
    bool beyondBaseHeaders() =>
        timelineRulerPainter(tester).frameEndIndexExclusive > 48;

    // Scroll gestures wall at the built extent (base 48 cells): however
    // far the viewport is flung, nothing past the base materializes and
    // the scrollbar range never grows from scrolling.
    for (var i = 0; i < 3; i += 1) {
      await tester.drag(
        find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
        const Offset(-1200, 0),
      );
      await tester.pumpAndSettle();
    }
    expect(beyondBaseHeaders(), isFalse);

    // The ruler edge-drag is THE way past the wall: a scrub held at the
    // right edge pans the axis (overshooting the built extent) and the
    // growth listener materializes the frames the view needs.
    final rulerRect = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-frame-ruler-scrub-area')),
    );
    final gesture = await tester.startGesture(
      Offset(rulerRect.right - 30, rulerRect.center.dy),
    );
    for (var i = 0; i < 12; i += 1) {
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(beyondBaseHeaders(), isTrue);
  });

  testWidgets('timeline zoom buttons rescale the frame axis', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    // 24 at 100% — the slim default (R-toolbar round); the painterized
    // ruler (UI-R13 #1) reports geometry/labels through its painter.
    double headerWidth() => timelineHeaderGlobalRect(tester, 0).width;
    expect(headerWidth(), 24);
    // Wide cells label every frame in-cell.
    expect(timelineHeaderModel(tester, 0).label, '1');

    Future<void> zoomTo(double pixelsPerFrame) async {
      tester
          .widget<FieldSlider>(
            find.byKey(const ValueKey<String>('timeline-zoom-slider')),
          )
          .onChanged!(pixelsPerFrame);
      await tester.pumpAndSettle();
    }

    await zoomTo(72);
    expect(headerWidth(), 72);

    // UI-R11 #11: the −/+ STEP buttons flanking the slider zoom without
    // dragging — multiplicative ×1.25 steps on the whole-px grid.
    await zoomTo(24);
    await _tapToolbarButton(
      tester,
      const ValueKey<String>('timeline-zoom-in-button'),
    );
    expect(headerWidth(), 30, reason: '24 × 1.25');
    await _tapToolbarButton(
      tester,
      const ValueKey<String>('timeline-zoom-out-button'),
    );
    await _tapToolbarButton(
      tester,
      const ValueKey<String>('timeline-zoom-out-button'),
    );
    expect(headerWidth(), 19, reason: '30 ÷ 1.25 ÷ 1.25');

    await zoomTo(12);
    expect(headerWidth(), 12);
    // Narrow cells move their labels to the every-Nth ladder: unlabeled
    // headers read '' off the painter model (frame 1 stays the anchor).
    expect(timelineHeaderModel(tester, 1).label, '');
    expect(timelineHeaderModel(tester, 0).label, isNotEmpty);
  });

  testWidgets('xsheet zoom rescales the frame row height', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await _tapToolbarButton(
      tester,
      const ValueKey<String>('timeline-orientation-toggle-button'),
    );

    // The rail is painterized (UI-R14 #1): row geometry probes off its
    // painter.
    //
    // R10 R6: a frame ROW is a frame CELL turned on its side, so the sheet
    // reads the slider 1:1 instead of scaling it by an old 36/24 ratio —
    // one slider position now means one frame extent on both surfaces.
    expect(xsheetFrameRowGlobalRect(tester, 0).height, timelineFrameCellWidth);

    tester
        .widget<FieldSlider>(
          find.byKey(const ValueKey<String>('timeline-zoom-slider')),
        )
        .onChanged!(72);
    await tester.pumpAndSettle();
    expect(xsheetFrameRowGlobalRect(tester, 0).height, 72);
  });

  testWidgets('the time display toggle switches the counter to seconds', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    String counterText() => tester
        .widget<Text>(
          find.byKey(const ValueKey<String>('timeline-current-frame-counter')),
        )
        .data!;
    expect(counterText(), '1');

    await _tapToolbarButton(
      tester,
      const ValueKey<String>('timeline-time-display-toggle-button'),
    );
    // Frame 1 at 24fps in conte notation — bare digits, the sheet's own
    // (feedback #12); this used to read `0+01`.
    expect(counterText(), '0+1');

    await _tapToolbarButton(
      tester,
      const ValueKey<String>('timeline-time-display-toggle-button'),
    );
    expect(counterText(), '1');
  });

  testWidgets('xsheet frame axis: scrolling stays CLAMPED to the built '
      'cells; the frame-rail edge-drag alone extends it (UI-R12 #16)', (
    WidgetTester tester,
  ) async {
    _withTouchScroll();
    await tester.pumpWidget(const AnicelApp());
    await _tapToolbarButton(
      tester,
      const ValueKey<String>('timeline-orientation-toggle-button'),
    );

    // Painterized rail (UI-R14 #1): rows past the base exist exactly
    // when the rail painter's window reaches past 48.
    bool beyondBaseRows() =>
        xsheetRailPainter(tester).frameEndIndexExclusive > 48;

    // Scroll gestures wall at the built extent (base 48 rows).
    for (var i = 0; i < 3; i += 1) {
      await tester.drag(
        find.byKey(const ValueKey<String>('xsheet-frame-vertical-viewport')),
        const Offset(0, -1200),
      );
      await tester.pumpAndSettle();
    }
    expect(beyondBaseRows(), isFalse);

    // The frame-rail edge-drag is THE way past the wall (UI-R12 #16).
    final railRect = tester.getRect(
      find.byKey(const ValueKey<String>('xsheet-frame-rail-scrub-area')),
    );
    final gesture = await tester.startGesture(
      Offset(railRect.center.dx, railRect.bottom - 30),
    );
    for (var i = 0; i < 12; i += 1) {
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(beyondBaseRows(), isTrue);
  });

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
    await _expectCutExists(tester, 'default-cut-1', exists: true);
    expect(find.byKey(const ValueKey<String>('undo-button')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('redo-button')), findsOneWidget);

    await _tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));
    _expectCellText('default-layer-1', 0, '○');

    await _tapUndoButton(tester);

    _expectCellText('default-layer-1', 0, 'X');
    _expectNoCellText('default-layer-1', 0, '○');

    await _tapRedoButton(tester);

    _expectCellText('default-layer-1', 0, '○');
  });

  testWidgets('dragging Cut 2 before Cut 1 keeps Cut 2 active', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await _createSecondCut(tester);

    await _switchToCut(tester, 'cut-1');
    await _expectActiveCutName(tester, '2');
    await _expectCutOrder(tester, ['default-cut-1', 'cut-1']);

    await _dragCutOnto(
      tester,
      sourceCutId: 'cut-1',
      targetCutId: 'default-cut-1',
    );

    await _expectCutOrder(tester, ['cut-1', 'default-cut-1']);
    await _expectActiveCutName(tester, '2');
    expect(await _activeCutId(tester), const CutId('cut-1'));
  });

  testWidgets('dragging Cut 1 after Cut 2 supports undo and redo', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await _createSecondCut(tester);
    await _switchToCut(tester, 'default-cut-1');

    await _expectActiveCutName(tester, '1');
    await _expectCutOrder(tester, ['default-cut-1', 'cut-1']);

    await _dragCutOnto(
      tester,
      sourceCutId: 'default-cut-1',
      targetCutId: 'cut-1',
    );

    await _expectCutOrder(tester, ['cut-1', 'default-cut-1']);
    await _expectActiveCutName(tester, '1');
    expect(await _activeCutId(tester), const CutId('default-cut-1'));

    await _tapUndoButton(tester);

    await _expectCutOrder(tester, ['default-cut-1', 'cut-1']);
    await _expectActiveCutName(tester, '1');
    expect(await _activeCutId(tester), const CutId('default-cut-1'));

    await _tapRedoButton(tester);

    await _expectCutOrder(tester, ['cut-1', 'default-cut-1']);
    await _expectActiveCutName(tester, '1');
    expect(await _activeCutId(tester), const CutId('default-cut-1'));
  });

  testWidgets('move cut buttons reorder active cut left with undo and redo', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await _createSecondCut(tester);

    await _switchToCut(tester, 'cut-1');
    await _expectActiveCutName(tester, '2');
    await _expectCutOrder(tester, ['default-cut-1', 'cut-1']);

    await _tapCutCommandButton(
      tester,
      const ValueKey<String>('move-cut-left-button'),
    );

    await _expectCutOrder(tester, ['cut-1', 'default-cut-1']);
    await _expectActiveCutName(tester, '2');
    expect(await _activeCutId(tester), const CutId('cut-1'));

    await _tapUndoButton(tester);

    await _expectCutOrder(tester, ['default-cut-1', 'cut-1']);
    await _expectActiveCutName(tester, '2');

    await _tapRedoButton(tester);

    await _expectCutOrder(tester, ['cut-1', 'default-cut-1']);
    await _expectActiveCutName(tester, '2');
  });

  testWidgets('move cut buttons reorder active cut right with undo and redo', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await _createSecondCut(tester);
    await _switchToCut(tester, 'default-cut-1');

    await _expectActiveCutName(tester, '1');
    await _expectCutOrder(tester, ['default-cut-1', 'cut-1']);

    await _tapCutCommandButton(
      tester,
      const ValueKey<String>('move-cut-right-button'),
    );

    await _expectCutOrder(tester, ['cut-1', 'default-cut-1']);
    await _expectActiveCutName(tester, '1');
    expect(await _activeCutId(tester), const CutId('default-cut-1'));

    await _tapUndoButton(tester);

    await _expectCutOrder(tester, ['default-cut-1', 'cut-1']);
    await _expectActiveCutName(tester, '1');

    await _tapRedoButton(tester);

    await _expectCutOrder(tester, ['cut-1', 'default-cut-1']);
    await _expectActiveCutName(tester, '1');
  });

  testWidgets('move cut buttons are disabled at cut list edges', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await _createSecondCut(tester);
    await _switchToCut(tester, 'default-cut-1');
    // The move buttons live in the storyboard panel's toolbar.
    await _showStoryboardPanel(tester);

    expect(
      await _isActionButtonEnabled(
        tester,
        const ValueKey<String>('move-cut-left-button'),
      ),
      isFalse,
    );
    expect(
      await _isActionButtonEnabled(
        tester,
        const ValueKey<String>('move-cut-right-button'),
      ),
      isTrue,
    );

    await _switchToCut(tester, 'cut-1');

    expect(
      await _isActionButtonEnabled(
        tester,
        const ValueKey<String>('move-cut-left-button'),
      ),
      isTrue,
    );
    expect(
      await _isActionButtonEnabled(
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

    await _expectCutExists(tester, 'cut-1', exists: false);

    await _tapCutCommandButton(
      tester,
      const ValueKey<String>('new-cut-button'),
    );

    await _expectCutName(tester, 'cut-1', '2');
    await _expectCutExists(tester, 'cut-1', exists: true);
    await _expectActiveCutName(tester, '2');
    await _expectCutName(tester, 'default-cut-1', '1');
    await _expectCutsNamed(tester, 'Cut 2', 0);
  });

  testWidgets('duplicates the active cut from the cut list command', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await _expectCutExists(tester, 'cut-1', exists: false);

    await _tapCutCommandButton(
      tester,
      const ValueKey<String>('duplicate-cut-button'),
    );

    await _expectCutName(tester, 'default-cut-1', '1');
    await _expectCutName(tester, 'cut-1', '1 Copy');
    await _expectCutsNamed(tester, 'Cut 2', 0);
    await _expectCutExists(tester, 'default-cut-1', exists: true);
    await _expectCutExists(tester, 'cut-1', exists: true);
    await _expectActiveCutName(tester, '1 Copy');
    expect(find.byTooltip('Linked Cut'), findsNothing);
  });

  testWidgets('deletes the active cut from the cut list command', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await _createSecondCut(tester);
    await _switchToCut(tester, 'default-cut-1');

    await _expectCutName(tester, 'default-cut-1', '1');
    await _expectCutName(tester, 'cut-1', '2');

    await _tapCutCommandButton(
      tester,
      const ValueKey<String>('delete-cut-button'),
    );

    await _expectCutExists(tester, 'default-cut-1', exists: false);
    await _expectCutExists(tester, 'default-cut-1', exists: false);
    await _expectCutExists(tester, 'cut-1', exists: true);
    await _expectActiveCutName(tester, '2');
  });

  testWidgets('R28 #14: deleting the last cut EMPTIES the track — the app '
      'stands in the no-active-cut state instead of conjuring a stand-in', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await _tapCutCommandButton(
      tester,
      const ValueKey<String>('delete-cut-button'),
    );

    await _expectCutExists(tester, 'default-cut-1', exists: false);
    await _expectCutExists(tester, 'cut-1', exists: false);
    // The shell survives with nothing active — the same state a storyboard
    // gap parks in.
    expect(tester.takeException(), isNull);
  });

  testWidgets('long multi-line cut note remains editable and savable', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    const longNote = '''Line 1
Line 2
Line 3
Line 4
Line 5
Line 6
Line 7
Line 8''';

    await _openCutNoteDialog(tester);
    expect(
      find.byKey(const ValueKey<String>('cut-note-text-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('save-cut-note-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('cancel-cut-note-button')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('cut-note-text-field')),
      longNote,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('cancel-cut-note-button')),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('save-cut-note-button')),
    );
    await _tapCutNoteSaveButton(tester);

    expect(await _currentCutNoteFromDialog(tester), longNote);
    await _expectActiveCutName(tester, '1');
  });

  testWidgets('different cuts keep separate cut notes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await _createSecondCut(tester);
    await _switchToCut(tester, 'default-cut-1');

    await _saveCutNote(tester, 'Cut 1 note');
    expect(await _currentCutNoteFromDialog(tester), 'Cut 1 note');

    await _switchToCut(tester, 'cut-1');
    expect(await _currentCutNoteFromDialog(tester), '');

    await _saveCutNote(tester, 'Cut 2 note');
    expect(await _currentCutNoteFromDialog(tester), 'Cut 2 note');

    await _switchToCut(tester, 'default-cut-1');
    expect(await _currentCutNoteFromDialog(tester), 'Cut 1 note');
  });

  testWidgets('undo and redo update the correct cut note', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await _createSecondCut(tester);
    await _switchToCut(tester, 'default-cut-1');

    await _saveCutNote(tester, 'Cut 1 note');

    await _switchToCut(tester, 'cut-1');
    await _saveCutNote(tester, 'Cut 2 old note');
    await _saveCutNote(tester, 'Cut 2 new note');
    expect(await _currentCutNoteFromDialog(tester), 'Cut 2 new note');
    await _expectActiveCutName(tester, '2');
    expect(await _activeCutId(tester), const CutId('cut-1'));

    await _tapUndoButton(tester);

    expect(await _currentCutNoteFromDialog(tester), 'Cut 2 old note');
    await _expectActiveCutName(tester, '2');
    expect(await _activeCutId(tester), const CutId('cut-1'));

    await _switchToCut(tester, 'default-cut-1');
    expect(await _currentCutNoteFromDialog(tester), 'Cut 1 note');

    await _switchToCut(tester, 'cut-1');
    await _tapRedoButton(tester);

    expect(await _currentCutNoteFromDialog(tester), 'Cut 2 new note');
    await _expectActiveCutName(tester, '2');
    expect(await _activeCutId(tester), const CutId('cut-1'));

    await _switchToCut(tester, 'default-cut-1');
    expect(await _currentCutNoteFromDialog(tester), 'Cut 1 note');
  });

  testWidgets('edit cut note button opens dialog with current note', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await _saveCutNote(tester, 'Old note');
    await _openCutNoteDialog(tester);

    expect(find.text('Edit cut note'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('cut-note-text-field')),
      findsOneWidget,
    );
    expect(_cutNoteFieldText(tester), 'Old note');
    expect(
      find.byKey(const ValueKey<String>('save-cut-note-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('cancel-cut-note-button')),
      findsOneWidget,
    );

    await _tapCutNoteCancelButton(tester);
  });

  testWidgets(
    'saving cut note supports undo and redo without changing active cut',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());

      await _saveCutNote(tester, 'Old note');
      expect(await _currentCutNoteFromDialog(tester), 'Old note');
      await _expectActiveCutName(tester, '1');
      expect(await _activeCutId(tester), const CutId('default-cut-1'));

      await _saveCutNote(tester, 'New note');

      expect(find.text('Edit cut note'), findsNothing);
      expect(await _currentCutNoteFromDialog(tester), 'New note');
      await _expectActiveCutName(tester, '1');
      expect(await _activeCutId(tester), const CutId('default-cut-1'));

      await _tapUndoButton(tester);

      expect(await _currentCutNoteFromDialog(tester), 'Old note');
      await _expectActiveCutName(tester, '1');
      expect(await _activeCutId(tester), const CutId('default-cut-1'));

      await _tapRedoButton(tester);

      expect(await _currentCutNoteFromDialog(tester), 'New note');
      await _expectActiveCutName(tester, '1');
      expect(await _activeCutId(tester), const CutId('default-cut-1'));
    },
  );

  testWidgets(
    'canceling cut note dialog does not change note or create history',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());

      await _openCutNoteDialog(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('cut-note-text-field')),
        'Canceled note',
      );
      await _tapCutNoteCancelButton(tester);

      expect(find.text('Edit cut note'), findsNothing);
      expect(await _currentCutNoteFromDialog(tester), '');
      await _expectActiveCutName(tester, '1');
      expect(
        await _isActionButtonEnabled(
          tester,
          const ValueKey<String>('undo-button'),
        ),
        isFalse,
      );
    },
  );

  testWidgets('saving unchanged cut note skips history entry', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await _openCutNoteDialog(tester);
    expect(_cutNoteFieldText(tester), '');
    await _tapCutNoteSaveButton(tester);

    expect(find.text('Edit cut note'), findsNothing);
    expect(await _currentCutNoteFromDialog(tester), '');
    expect(
      await _isActionButtonEnabled(
        tester,
        const ValueKey<String>('undo-button'),
      ),
      isFalse,
    );
    await _expectActiveCutName(tester, '1');
  });

  testWidgets('opens and cancels rename cut dialog without mutation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await _tapCutCommandButton(
      tester,
      const ValueKey<String>('rename-cut-button'),
    );

    expect(
      find.byKey(const ValueKey<String>('rename-cut-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('rename-cut-text-field')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('rename-cut-text-field')),
          )
          .controller
          ?.text,
      '1',
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('rename-cut-text-field')),
      'Canceled Cut',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('rename-cut-cancel-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('rename-cut-dialog')),
      findsNothing,
    );
    await _expectCutName(tester, 'default-cut-1', '1');
    await _expectCutsNamed(tester, 'Canceled Cut', 0);
    await _expectActiveCutName(tester, '1');
  });

  testWidgets('renames active cut and supports undo and redo', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await _renameActiveCut(tester, 'Scene A');

    await _expectCutName(tester, 'default-cut-1', 'Scene A');
    await _expectCutsNamed(tester, '1', 0);
    await _expectActiveCutName(tester, 'Scene A');
    expect(await _activeCutId(tester), const CutId('default-cut-1'));

    await _tapUndoButton(tester);

    await _expectCutName(tester, 'default-cut-1', '1');
    await _expectCutsNamed(tester, 'Scene A', 0);
    await _expectActiveCutName(tester, '1');
    expect(await _activeCutId(tester), const CutId('default-cut-1'));

    await _tapRedoButton(tester);

    await _expectCutName(tester, 'default-cut-1', 'Scene A');
    await _expectCutsNamed(tester, '1', 0);
    await _expectActiveCutName(tester, 'Scene A');
    expect(await _activeCutId(tester), const CutId('default-cut-1'));
  });

  testWidgets('ignores empty rename cut input', (WidgetTester tester) async {
    await tester.pumpWidget(const AnicelApp());

    await _renameActiveCut(tester, '   ');

    await _expectCutName(tester, 'default-cut-1', '1');
    await _expectActiveCutName(tester, '1');
    final undoButton = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('undo-button')),
    );
    expect(undoButton.onPressed, isNull);
  });

  testWidgets('allows duplicate cut names without merging cuts', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await _createSecondCut(tester);

    await _renameActiveCut(tester, '1');

    await _expectCutsNamed(tester, '1', 2);
    await _expectCutExists(tester, 'default-cut-1', exists: true);
    await _expectCutExists(tester, 'cut-1', exists: true);
    await _expectActiveCutName(tester, '1');
    expect(find.textContaining('already'), findsNothing);
    expect(find.textContaining('duplicate'), findsNothing);
  });

  testWidgets('uses the sample cut resolved from the project by default', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await _expectCutName(tester, 'default-cut-1', '1');
    await _expectCutsNamed(tester, 'Cut 2', 0);
    _expectActiveLayerName('A');
    expect(find.text('B'), findsNothing);
    await _expectCutsNamed(tester, 'New Cut', 0);
    expect(find.text('A'), findsWidgets);
    _expectCellText('default-layer-1', 0, 'X');
    expect(
      find.byKey(const ValueKey<String>('timeline-row-cells-default-layer-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-row-cells-default-layer-2')),
      findsNothing,
    );
    await _expectActiveCutName(tester, '1');
  });

  testWidgets('initial timeline layer shows animation kind icon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    expect(
      find.byKey(
        const ValueKey<String>('timeline-layer-kind-icon-default-layer-1'),
      ),
      findsOneWidget,
    );
    expect(_layerKindIcon(tester, 'default-layer-1'), Icons.brush_outlined);
    expect(find.bySemanticsLabel('Animation layer'), findsOneWidget);
    expect(find.text('A'), findsWidgets);
  });

  testWidgets('Add Layer creates an animation kind icon for active B', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await _addLayer(tester);

    expect(
      find.byKey(
        const ValueKey<String>('timeline-layer-kind-icon-default-layer-2'),
      ),
      findsOneWidget,
    );
    expect(_layerKindIcon(tester, 'default-layer-2'), Icons.brush_outlined);
    _expectActiveLayerName('B');
    expect(find.bySemanticsLabel('Animation layer'), findsNWidgets(2));
  });

  testWidgets('storyboard toggle updates the active layer kind icon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    expect(_layerKindIcon(tester, 'default-layer-1'), Icons.brush_outlined);

    await _tapToolbarButton(
      tester,
      const ValueKey<String>('toggle-storyboard-layer-button'),
    );

    expect(
      _layerKindIcon(tester, 'default-layer-1'),
      Icons.auto_stories_outlined,
    );
    expect(find.bySemanticsLabel('Storyboard layer'), findsOneWidget);

    await _tapToolbarButton(
      tester,
      const ValueKey<String>('toggle-storyboard-layer-button'),
    );

    expect(_layerKindIcon(tester, 'default-layer-1'), Icons.brush_outlined);
    expect(find.bySemanticsLabel('Animation layer'), findsOneWidget);
  });

  testWidgets('multiple layers can show different layer kind icons', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await _addLayer(tester);

    await _tapToolbarButton(
      tester,
      const ValueKey<String>('toggle-storyboard-layer-button'),
    );

    expect(_layerKindIcon(tester, 'default-layer-1'), Icons.brush_outlined);
    expect(
      _layerKindIcon(tester, 'default-layer-2'),
      Icons.auto_stories_outlined,
    );
    expect(find.bySemanticsLabel('Animation layer'), findsOneWidget);
    expect(find.bySemanticsLabel('Storyboard layer'), findsOneWidget);
    expect(find.text('A'), findsWidgets);
    expect(find.text('B'), findsWidgets);

    final layerAName = find.byKey(
      const ValueKey<String>('timeline-layer-name-default-layer-1'),
    );
    await tester.ensureVisible(layerAName);
    await tester.pumpAndSettle();
    await tester.tap(layerAName);
    await tester.pumpAndSettle();

    _expectActiveLayerName('A');
  });

  testWidgets('pressing Add Layer creates B then C above active layers', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    _expectActiveLayerName('A');
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-row-default-layer-2')),
      findsNothing,
    );

    await _addLayer(tester);

    _expectActiveLayerName('B');
    expect(
      find.byKey(const ValueKey<String>('timeline-row-cells-default-layer-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-selected-layer')),
      findsOneWidget,
    );
    _expectCellText('default-layer-2', 0, 'X');

    var layerBTop = tester
        .getTopLeft(
          find.byKey(
            const ValueKey<String>('timeline-layer-row-default-layer-2'),
          ),
        )
        .dy;
    var layerATop = tester
        .getTopLeft(
          find.byKey(
            const ValueKey<String>('timeline-layer-row-default-layer-1'),
          ),
        )
        .dy;
    expect(layerBTop, lessThan(layerATop));

    await _addLayer(tester);

    _expectActiveLayerName('C');
    expect(
      find.byKey(const ValueKey<String>('timeline-row-cells-default-layer-3')),
      findsOneWidget,
    );
    _expectCellText('default-layer-3', 0, 'X');

    // The layer axis is virtualized and the drawing rows sit at the BOTTOM
    // of the display order — scroll them into the window before measuring.
    final verticalScrollable = find
        .descendant(
          of: find.byKey(
            const ValueKey<String>('timeline-vertical-scroll-viewport'),
          ),
          matching: find.byType(Scrollable),
        )
        .first;
    final verticalPosition = tester
        .state<ScrollableState>(verticalScrollable)
        .position;
    verticalPosition.jumpTo(verticalPosition.maxScrollExtent);
    await tester.pumpAndSettle();

    final layerCTop = tester
        .getTopLeft(
          find.byKey(
            const ValueKey<String>('timeline-layer-row-default-layer-3'),
          ),
        )
        .dy;
    layerBTop = tester
        .getTopLeft(
          find.byKey(
            const ValueKey<String>('timeline-layer-row-default-layer-2'),
          ),
        )
        .dy;
    layerATop = tester
        .getTopLeft(
          find.byKey(
            const ValueKey<String>('timeline-layer-row-default-layer-1'),
          ),
        )
        .dy;

    expect(layerCTop, lessThan(layerBTop));
    expect(layerBTop, lessThan(layerATop));
    expect(
      find.byKey(
        const ValueKey<String>('timeline-layer-kind-icon-default-layer-3'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('XSheet keeps raw layer order after adding B and C', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await _addLayer(tester);
    await _addLayer(tester);
    await _tapToolbarButton(
      tester,
      const ValueKey<String>('timeline-orientation-toggle-button'),
    );

    final layerALeft = tester
        .getTopLeft(
          find.byKey(
            const ValueKey<String>('xsheet-layer-header-default-layer-1'),
          ),
        )
        .dx;
    final layerBLeft = tester
        .getTopLeft(
          find.byKey(
            const ValueKey<String>('xsheet-layer-header-default-layer-2'),
          ),
        )
        .dx;
    final layerCLeft = tester
        .getTopLeft(
          find.byKey(
            const ValueKey<String>('xsheet-layer-header-default-layer-3'),
          ),
        )
        .dx;

    expect(layerALeft, lessThan(layerBLeft));
    expect(layerBLeft, lessThan(layerCLeft));
    expect(
      find.byKey(const ValueKey<String>('xsheet-row-cells-default-layer-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('xsheet-row-cells-default-layer-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('xsheet-row-cells-default-layer-3')),
      findsOneWidget,
    );

    await tapTimelineCell(tester, 'default-layer-1', 0, prefix: 'xsheet');
    await tester.pumpAndSettle();
    // R10 R6: the selected column's name is vertical writing now.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('xsheet-selected-layer')),
        matching: findVerticalText('A'),
      ),
      findsOneWidget,
    );
  });

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
    await _createSecondCut(tester);
    await _switchToCut(tester, 'default-cut-1');

    await _expectCutName(tester, 'default-cut-1', '1');
    await _expectCutName(tester, 'cut-1', '2');
    await _expectCutsNamed(tester, 'Cut 2', 0);
    await _expectActiveCutName(tester, '1');
    _expectActiveLayerName('A');
    expect(await _activeCutId(tester), const CutId('default-cut-1'));

    await _tapStoryboardCutBlock(tester, 'cut-1');

    await _expectActiveCutName(tester, '2');
    _expectActiveLayerName('A');
    expect(find.text('B'), findsNothing);
    expect(find.text('A'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('timeline-row-cells-layer-1')),
      findsOneWidget,
    );
    _expectCellText('layer-1', 0, 'X');
    expect(await _activeCutId(tester), const CutId('cut-1'));

    await _tapStoryboardCutBlock(tester, 'default-cut-1');

    await _expectActiveCutName(tester, '1');
    await _expectCutName(tester, 'cut-1', '2');
    _expectActiveLayerName('A');
    expect(await _activeCutId(tester), const CutId('default-cut-1'));
  });

  testWidgets('StoryboardPanel cut selection syncs active cut surfaces', (
    WidgetTester tester,
  ) async {
    // Same reason as 'switches between existing sample cuts': the second
    // cut's block has to be on screen to be tapped.
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const AnicelApp());
    await _createSecondCut(tester);
    await _switchToCut(tester, 'default-cut-1');
    await _showStoryboardPanel(tester);

    expect(
      find.byKey(const ValueKey<String>('storyboard-panel')),
      findsOneWidget,
    );
    await _expectActiveCutName(tester, '1');
    expect(await _activeCutId(tester), const CutId('default-cut-1'));

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

    await _expectActiveCutName(tester, '2');
    expect(await _activeCutId(tester), const CutId('cut-1'));

    await _showTimelinePanel(tester);

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
    await _createSecondCut(tester);
    await _showStoryboardPanel(tester);

    expect(await _activeCutId(tester), const CutId('cut-1'));

    await _switchToCut(tester, 'default-cut-1');

    await _expectActiveCutName(tester, '1');
    expect(await _activeCutId(tester), const CutId('default-cut-1'));
  });

  testWidgets('new frame after switching to Cut 2 stays scoped to Cut 2', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await _createSecondCut(tester);

    await _switchToCut(tester, 'cut-1');
    await _expectActiveCutName(tester, '2');
    _expectActiveLayerName('A');
    _expectCellText('layer-1', 0, 'X');

    await _tapTimelineCell(
      tester,
      const ValueKey<String>('timeline-cell-layer-1-1'),
    );
    await _tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));

    _expectCellText('layer-1', 0, 'X');
    _expectCellText('layer-1', 1, '○');
    expect(_selectedCellStateLabel(tester), 'drawing start');

    await _switchToCut(tester, 'default-cut-1');

    await _expectActiveCutName(tester, '1');
    _expectActiveLayerName('A');
    _expectCellText('default-layer-1', 0, 'X');
    _expectNoCellText('default-layer-1', 1, '○');

    await _switchToCut(tester, 'cut-1');

    await _expectActiveCutName(tester, '2');
    _expectCellText('layer-1', 1, '○');
  });

  testWidgets(
    'blank and mark edits after switching to Cut 2 do not affect Cut 1',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());
      await _createSecondCut(tester);

      await _switchToCut(tester, 'cut-1');
      await _tapTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-layer-1-1'),
      );
      await _tapToolbarButton(
        tester,
        const ValueKey<String>('new-frame-button'),
      );
      _expectCellText('layer-1', 1, '○');

      // Grow the block to [1,4) so a held cell can take the dot, cut the
      // hold back at 3, then dot the held cell at 2 (dots are block-owned).
      await _dragBlockEndGrip(tester, 'layer-1', 0, 2);
      await _tapTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-layer-1-3'),
      );
      await _tapToolbarButton(
        tester,
        const ValueKey<String>('blank-exposure-button'),
      );
      _expectCellText('layer-1', 3, 'X');

      await _tapTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-layer-1-2'),
      );
      await _tapToolbarButton(
        tester,
        const ValueKey<String>('toggle-mark-button'),
      );
      _expectCellText('layer-1', 2, '●');
      expect(_selectedCellStateLabel(tester), 'inbetween mark');

      await _switchToCut(tester, 'default-cut-1');

      await _expectActiveCutName(tester, '1');
      // Cut 1's layer is untouched: one empty run whose first cell reads X.
      _expectCellText('default-layer-1', 0, 'X');
      _expectNoCellText('default-layer-1', 1, 'X');
      _expectNoCellText('default-layer-1', 2, '●');
      expect(
        _anyCellSemanticsLabel('default-layer-1', 'inbetween mark'),
        isFalse,
      );
    },
  );

  testWidgets('exposure edit after switching to Cut 2 stays on Cut 2 entry', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await _createSecondCut(tester);

    await _switchToCut(tester, 'cut-1');
    await _tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));

    await _dragBlockEndGrip(tester, 'layer-1', 0, 1);

    await _tapTimelineCell(
      tester,
      const ValueKey<String>('timeline-cell-layer-1-1'),
    );
    expect(_selectedCellStateLabel(tester), 'held exposure');
    _expectNoCellText('layer-1', 1, 'X');

    await _switchToCut(tester, 'default-cut-1');

    _expectActiveLayerName('A');
    // The fresh layer is all empty (X) cells; empty cells carry no
    // semantics label under the unified model.
    expect(_selectedCellStateLabel(tester), isNull);
    _expectCellText('default-layer-1', 0, 'X');
    _expectNoCellText('default-layer-1', 1, '○');
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
      await _tapToolbarButton(
        tester,
        const ValueKey<String>('new-frame-button'),
      );
      await _tapTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-default-layer-1-3'),
      );
      await _tapToolbarButton(
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

      _expectNoCellText('default-layer-1', 1, 'X');
      _expectNoCellText('default-layer-1', 2, 'X');
      _expectCellText('default-layer-1', 4, '○');

      // The whole drag is ONE undo step.
      await _tapToolbarButton(tester, const ValueKey<String>('undo-button'));
      _expectCellText('default-layer-1', 1, 'X');
      _expectCellText('default-layer-1', 3, '○');

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

      _expectCellText('default-layer-1', 1, '○');
      _expectNoCellText('default-layer-1', 2, 'X');
      _expectNoCellText('default-layer-1', 3, '○');
    },
  );

  testWidgets(
    'cut switching clears copied frame before cross-cut linked paste',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());
      await _createSecondCut(tester);
      await _switchToCut(tester, 'default-cut-1');

      await _tapToolbarButton(
        tester,
        const ValueKey<String>('new-frame-button'),
      );
      await _tapToolbarButton(
        tester,
        const ValueKey<String>('copy-frame-button'),
      );

      await _switchToCut(tester, 'cut-1');

      await _expectActiveCutName(tester, '2');
      expect(
        await _isActionButtonEnabled(
          tester,
          const ValueKey<String>('paste-linked-frame-button'),
        ),
        isFalse,
      );

      await _tapTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-layer-1-1'),
      );

      expect(
        await _isActionButtonEnabled(
          tester,
          const ValueKey<String>('paste-linked-frame-button'),
        ),
        isFalse,
      );
      _expectNoCellText('layer-1', 1, '○');
    },
  );

  testWidgets('undo and redo smoke after cut switching keeps Cut 2 active', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await _createSecondCut(tester);

    await _switchToCut(tester, 'cut-1');
    await _tapTimelineCell(
      tester,
      const ValueKey<String>('timeline-cell-layer-1-1'),
    );
    await _tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));
    _expectCellText('layer-1', 1, '○');

    await _tapUndoButton(tester);

    await _expectActiveCutName(tester, '2');
    _expectActiveLayerName('A');
    _expectNoCellText('layer-1', 1, '○');

    await _tapRedoButton(tester);

    await _expectActiveCutName(tester, '2');
    _expectCellText('layer-1', 1, '○');
  });

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
    _expectTimelineActionTooltips();
    await _expectTimelineActionKeys(tester);
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

    _expectCellText('default-layer-1', 0, 'X');
    expect(
      find.byKey(const ValueKey<String>('timeline-row-cells-default-layer-2')),
      findsNothing,
    );
    // Paper-sheet style: only the FIRST cell of the empty run reads X.
    _expectNoCellText('default-layer-1', 1, 'X');
    expect(
      _rowPainter('default-layer-1').cellModelAt(0).semanticsLabel,
      isNull,
    );
  });

  testWidgets(
    'selected cell state updates for blank, drawing, name, and mark',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());

      _expectActiveLayerName('A');
      _expectCurrentFrame(tester, 1);
      // Empty (X) cells carry no semantics label.
      expect(_selectedCellStateLabel(tester), isNull);

      final newFrameButton = find.byKey(
        const ValueKey<String>('new-frame-button'),
      );
      await tester.ensureVisible(newFrameButton);
      await tester.pumpAndSettle();
      await tester.tap(newFrameButton);
      await tester.pumpAndSettle();

      expect(_selectedCellStateLabel(tester), 'drawing start');

      await _tapToolbarButton(
        tester,
        const ValueKey<String>('rename-frame-button'),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('rename-frame-text-field')),
        'A1',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('rename-frame-ok-button')),
      );
      await tester.pumpAndSettle();

      expect(_selectedCellStateLabel(tester), 'drawing start A1');

      // Marks live on held/empty cells (never on a drawing start): hold the
      // block one frame longer, then mark the held cell.
      await _dragBlockEndGrip(tester, 'default-layer-1', 0, 1);
      await _tapTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-default-layer-1-1'),
      );
      await _tapToolbarButton(
        tester,
        const ValueKey<String>('toggle-mark-button'),
      );

      expect(_selectedCellStateLabel(tester), 'inbetween mark');
    },
  );

  testWidgets('selection status and toolbar state distinguish held cells', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    // delete/rename live in the Frame ▾ flyout now; enablement reads open
    // the menu themselves.
    expect(
      await _isActionButtonEnabled(
        tester,
        const ValueKey<String>('delete-cell-button'),
      ),
      isFalse,
    );

    await _tapTimelineCell(
      tester,
      const ValueKey<String>('timeline-cell-default-layer-1-1'),
    );
    _expectCurrentFrame(tester, 2);
    expect(_selectedCellStateLabel(tester), isNull);
    expect(
      await _isActionButtonEnabled(
        tester,
        const ValueKey<String>('delete-cell-button'),
      ),
      isFalse,
    );

    await _tapTimelineCell(
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
      await _isActionButtonEnabled(
        tester,
        const ValueKey<String>('delete-cell-button'),
      ),
      isTrue,
    );

    // Hold the block across frames 1-3, then cut the hold at frame 3.
    await _dragBlockEndGrip(tester, 'default-layer-1', 0, 2);
    await _tapTimelineCell(
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
    _expectCellText('default-layer-1', 2, 'X');

    await _tapTimelineCell(
      tester,
      const ValueKey<String>('timeline-cell-default-layer-1-1'),
    );
    expect(_selectedCellStateLabel(tester), 'held exposure');
    // UI-R17 #1: held cells delete their COVERING block — the head-only
    // rule is gone.
    expect(
      await _isActionButtonEnabled(
        tester,
        const ValueKey<String>('delete-cell-button'),
      ),
      isTrue,
    );
    expect(
      await _isActionButtonEnabled(
        tester,
        const ValueKey<String>('rename-frame-button'),
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
        await _isActionButtonEnabled(
          tester,
          const ValueKey<String>('toggle-mark-button'),
        ),
        isFalse,
      );

      // Author a 2-frame block and stand on its held cell.
      await _tapToolbarButton(
        tester,
        const ValueKey<String>('new-frame-button'),
      );
      await _dragBlockEndGrip(tester, 'default-layer-1', 0, 1);
      await _tapTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-default-layer-1-1'),
      );

      await tester.ensureVisible(markButton);
      await tester.pumpAndSettle();
      await tester.tap(markButton);
      await tester.pumpAndSettle();

      _expectCellText('default-layer-1', 1, '●');
      expect(
        _anyCellSemanticsLabel('default-layer-1', 'inbetween mark'),
        isTrue,
      );
      // The drawing start is untouched.
      _expectCellText('default-layer-1', 0, '○');

      await tester.ensureVisible(markButton);
      await tester.pumpAndSettle();
      await tester.tap(markButton);
      await tester.pumpAndSettle();

      _expectNoCellText('default-layer-1', 1, '●');
      expect(
        _anyCellSemanticsLabel('default-layer-1', 'inbetween mark'),
        isFalse,
      );
    },
  );

  testWidgets(
    'new frame replaces selected layer blank exposure with drawing start',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());
      await _addLayer(tester);
      await _tapTimelineCell(
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

      _expectCellText('default-layer-1', 0, '○');
      _expectCellText('default-layer-2', 0, 'X');
      expect(
        _anyCellSemanticsLabel('default-layer-1', 'drawing start'),
        isTrue,
      );
      expect(
        _anyCellSemanticsLabel('default-layer-1', 'inbetween mark'),
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
        await _isActionButtonEnabled(
          tester,
          const ValueKey<String>('rename-frame-button'),
        ),
        isFalse,
      );
      expect(
        await _isActionButtonEnabled(
          tester,
          const ValueKey<String>('delete-cell-button'),
        ),
        isFalse,
      );

      await tester.ensureVisible(newFrameButton);
      await tester.pumpAndSettle();
      await tester.tap(newFrameButton);
      await tester.pumpAndSettle();

      expect(
        await _isActionButtonEnabled(
          tester,
          const ValueKey<String>('rename-frame-button'),
        ),
        isTrue,
      );
      await _tapToolbarButton(
        tester,
        const ValueKey<String>('rename-frame-button'),
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
      _expectCellText('default-layer-1', 0, 'A1');

      // Marks live on held/empty cells only; on a drawing start the mark
      // button is disabled under the unified model.
      expect(
        await _isActionButtonEnabled(
          tester,
          const ValueKey<String>('toggle-mark-button'),
        ),
        isFalse,
      );
      expect(markButton, findsOneWidget);

      expect(
        await _isActionButtonEnabled(
          tester,
          const ValueKey<String>('delete-cell-button'),
        ),
        isTrue,
      );
      await _tapToolbarButton(
        tester,
        const ValueKey<String>('delete-cell-button'),
      );
      _expectNoCellText('default-layer-1', 0, 'A1');
      _expectNoCellText('default-layer-1', 0, '●');
      expect(
        await _isActionButtonEnabled(
          tester,
          const ValueKey<String>('rename-frame-button'),
        ),
        isFalse,
      );
      expect(
        await _isActionButtonEnabled(
          tester,
          const ValueKey<String>('delete-cell-button'),
        ),
        isFalse,
      );
    },
  );

  testWidgets('rename to empty clears frame name', (WidgetTester tester) async {
    await tester.pumpWidget(const AnicelApp());

    await _tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));
    await _renameCurrentFrame(tester, 'A1');
    _expectCellText('default-layer-1', 0, 'A1');

    await _renameCurrentFrame(tester, '   ');

    _expectCellText('default-layer-1', 0, '○');
  });

  testWidgets('conflicting frame name dialog cancel leaves frames unchanged', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await _tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));
    await _renameCurrentFrame(tester, 'A1');
    await _createSecondAuthoredFrame(tester);

    await _renameCurrentFrame(tester, 'A1');

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

    _expectCellText('default-layer-1', 0, 'A1');
    _expectCellText('default-layer-1', 1, '○');
  });

  testWidgets('conflicting frame name link merges into existing material', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    await _tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));
    await _renameCurrentFrame(tester, 'A1');
    await _createSecondAuthoredFrame(tester);

    await _renameCurrentFrame(tester, 'A1');
    await tester.tap(
      find.byKey(const ValueKey<String>('frame-name-conflict-link-button')),
    );
    await tester.pumpAndSettle();

    _expectCellText('default-layer-1', 0, 'A1');
    _expectCellText('default-layer-1', 1, 'A1');
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
    await _tapToolbarButton(
      tester,
      const ValueKey<String>('rename-frame-button'),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('rename-frame-text-field')),
      'Cancelled',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('rename-frame-cancel-button')),
    );
    await tester.pumpAndSettle();
    _expectCellText('default-layer-1', 0, '○');
    expect(find.text('Cancelled'), findsNothing);
  });

  testWidgets('linked frame copy and paste buttons link authored exposures', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    // Copy/paste-linked live in the Frame ▾ flyout (R-toolbar round);
    // enablement reads open the menu themselves.
    expect(
      await _isActionButtonEnabled(
        tester,
        const ValueKey<String>('copy-frame-button'),
      ),
      isFalse,
    );
    expect(
      await _isActionButtonEnabled(
        tester,
        const ValueKey<String>('paste-linked-frame-button'),
      ),
      isFalse,
    );

    await _tapToolbarButton(tester, const ValueKey<String>('new-frame-button'));

    expect(
      await _isActionButtonEnabled(
        tester,
        const ValueKey<String>('copy-frame-button'),
      ),
      isTrue,
    );

    await _tapToolbarButton(
      tester,
      const ValueKey<String>('copy-frame-button'),
    );
    expect(
      await _isActionButtonEnabled(
        tester,
        const ValueKey<String>('paste-linked-frame-button'),
      ),
      isTrue,
    );

    await _tapTimelineCell(
      tester,
      const ValueKey<String>('timeline-cell-default-layer-1-1'),
    );

    await _tapToolbarButton(
      tester,
      const ValueKey<String>('paste-linked-frame-button'),
    );

    _expectCellText('default-layer-1', 0, '○');
    _expectCellText('default-layer-1', 1, '○');
  });

  testWidgets(
    'linked paste on a dot-held cell: the drawing wins and the cut-off '
    'dot drops',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());

      await _tapToolbarButton(
        tester,
        const ValueKey<String>('new-frame-button'),
      );
      await _tapToolbarButton(
        tester,
        const ValueKey<String>('copy-frame-button'),
      );
      await _addLayer(tester);

      await _tapTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-default-layer-2-0'),
      );
      expect(
        await _isActionButtonEnabled(
          tester,
          const ValueKey<String>('paste-linked-frame-button'),
        ),
        isFalse,
      );

      // Grow the block to [0,2) and dot its held cell.
      await _tapTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-default-layer-1-0'),
      );
      await _dragBlockEndGrip(tester, 'default-layer-1', 0, 1);
      await _tapTimelineCell(
        tester,
        const ValueKey<String>('timeline-cell-default-layer-1-1'),
      );
      await _tapToolbarButton(
        tester,
        const ValueKey<String>('toggle-mark-button'),
      );
      _expectCellText('default-layer-1', 1, '●');

      // The paste authors a drawing start on the dot's cell: the covering
      // block shrinks to [0,1) and the cut-off dot goes with it.
      await _tapToolbarButton(
        tester,
        const ValueKey<String>('paste-linked-frame-button'),
      );

      _expectNoCellText('default-layer-1', 1, '●');
      _expectCellText('default-layer-1', 1, '○');
      expect(_selectedCellStateLabel(tester), 'drawing start');
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
    expect(await _isActionButtonEnabled(tester, copyKey), isTrue);
    expect(await _isActionButtonEnabled(tester, pasteKey), isFalse);

    await _tapToolbarButton(tester, copyKey);

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-layer-menu-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Paste layer (A)'), findsOneWidget);
    await tester.tapAt(const Offset(5, 400));
    await tester.pumpAndSettle();
    expect(await _isActionButtonEnabled(tester, pasteKey), isTrue);
  });

  testWidgets(
    'Paste Layer creates another A, selects it, and undo/redo works',
    (WidgetTester tester) async {
      await tester.pumpWidget(const AnicelApp());

      await _tapToolbarButton(
        tester,
        const ValueKey<String>('copy-layer-button'),
      );
      await _tapToolbarButton(
        tester,
        const ValueKey<String>('paste-layer-button'),
      );

      expect(find.text('A'), findsWidgets);
      // Two drawing rows plus the always-present S1·S2/CAM 1/camera rows.
      expect(_timelineLayerRows(), findsNWidgets(6));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('timeline-selected-layer')),
          matching: find.text('A'),
        ),
        findsOneWidget,
      );

      await _tapToolbarButton(tester, const ValueKey<String>('undo-button'));
      expect(_timelineLayerRows(), findsNWidgets(5));

      await _tapToolbarButton(tester, const ValueKey<String>('redo-button'));
      expect(_timelineLayerRows(), findsNWidgets(6));
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

    await _tapToolbarButton(
      tester,
      const ValueKey<String>('copy-layer-button'),
    );
    await _tapToolbarButton(
      tester,
      const ValueKey<String>('paste-layer-button'),
    );
    await _tapToolbarButton(
      tester,
      const ValueKey<String>('rename-layer-button'),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('rename-layer-text-field')),
      'Pasted',
    );
    await _tapToolbarButton(
      tester,
      const ValueKey<String>('rename-layer-ok-button'),
    );

    expect(find.text('Pasted'), findsWidgets);

    await _tapToolbarButton(
      tester,
      const ValueKey<String>('delete-layer-button'),
    );
    await _tapToolbarButton(
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
        await _isActionButtonEnabled(
          tester,
          const ValueKey<String>('duplicate-layer-button'),
        ),
        isTrue,
      );

      await _tapToolbarButton(
        tester,
        const ValueKey<String>('duplicate-layer-button'),
      );

      expect(find.text('A'), findsWidgets);
      // Two drawing rows plus the always-present S1·S2/CAM 1/camera rows.
      expect(_timelineLayerRows(), findsNWidgets(6));
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

    await _tapToolbarButton(
      tester,
      const ValueKey<String>('duplicate-layer-button'),
    );
    await _tapToolbarButton(
      tester,
      const ValueKey<String>('rename-layer-button'),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('rename-layer-text-field')),
      'Dup',
    );
    await _tapToolbarButton(
      tester,
      const ValueKey<String>('rename-layer-ok-button'),
    );

    expect(find.text('Dup'), findsWidgets);

    await _tapToolbarButton(
      tester,
      const ValueKey<String>('delete-layer-button'),
    );
    await _tapToolbarButton(
      tester,
      const ValueKey<String>('delete-layer-confirm-button'),
    );

    expect(find.text('Dup'), findsNothing);
  });
}
