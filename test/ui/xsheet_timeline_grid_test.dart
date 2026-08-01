import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_ruler_cursor_overlay.dart';

import '../helpers/vertical_text_finder.dart';
import 'timeline/timeline_cell_probe.dart';
import 'timeline/timeline_ruler_probe.dart';

/// Painted-cell glyph probe, X-sheet prefix (UI-R9 #12b).
String _xsheetGlyph(WidgetTester tester, String layerId, int frameIndex) =>
    timelineCellModel(tester, layerId, frameIndex, prefix: 'xsheet').glyph;

void main() {
  testWidgets('renders integrated layer controls in headers', (tester) async {
    await tester.pumpWidget(_grid());

    // R10 R6: column names read DOWN their 28px column now, so they are
    // vertical writing rather than `Text`.
    expect(findVerticalText('Layer 1'), findsOneWidget);
    expect(findVerticalText('Layer 2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('xsheet-add-layer-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('xsheet-layer-visibility-layer-1')),
      findsOneWidget,
    );
  });

  testWidgets('does not render a dedicated add layer grid column', (
    tester,
  ) async {
    await tester.pumpWidget(_grid());

    expect(
      find.byKey(const ValueKey<String>('xsheet-add-layer-button')),
      findsNothing,
    );
  });

  testWidgets('visibility button calls callback', (tester) async {
    LayerId? toggledLayerId;

    await tester.pumpWidget(
      _grid(onToggleLayerVisibility: (layerId) => toggledLayerId = layerId),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('xsheet-layer-visibility-layer-2')),
    );

    expect(toggledLayerId, const LayerId('layer-2'));
  });

  testWidgets('the sheet carries NO opacity slider — a 28px column cannot '
      'show one (R10 R6)', (tester) async {
    await tester.pumpWidget(_grid());

    // The column narrowed 164 → 28 when the header stood up, which leaves
    // the readout 11px: the number the slot exists to show can never be
    // read. The value lives on the timeline rail and in the layer panel,
    // and the legend beside this had already stood its master bar down for
    // the same reason.
    expect(
      find.byKey(const ValueKey<String>('xsheet-layer-opacity-layer-1')),
      findsNothing,
    );
  });

  testWidgets('timesheet toggle calls callback from the header', (
    tester,
  ) async {
    LayerId? toggledLayerId;

    await tester.pumpWidget(
      _grid(onToggleLayerTimesheet: (layerId) => toggledLayerId = layerId),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('xsheet-layer-timesheet-layer-2')),
    );

    expect(toggledLayerId, const LayerId('layer-2'));
  });

  testWidgets('mark chip popup reports the selected mark', (tester) async {
    LayerId? markedLayerId;
    LayerMark? selectedMark;

    await tester.pumpWidget(
      _grid(
        onLayerMarkSelected: (layerId, mark) {
          markedLayerId = layerId;
          selectedMark = mark;
        },
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('xsheet-layer-mark-layer-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('layer-mark-option-red')),
    );
    await tester.pumpAndSettle();

    expect(markedLayerId, const LayerId('layer-1'));
    expect(selectedMark, LayerMark.red);
  });

  testWidgets('frame rail shows the cached-range strip inside playback', (
    tester,
  ) async {
    await tester.pumpWidget(
      _grid(frameCount: 3, isFrameCached: (frameIndex) => frameIndex < 2),
    );

    // The strip lives on the rail's cursor OVERLAY now (cached-ness is
    // derived state — nothing raises an invalidation event — so it repaints
    // freely instead of riding the gated rail painter). The runs it would
    // draw are the probe surface.
    final overlay =
        tester
                .widget<CustomPaint>(
                  find.byKey(
                    const ValueKey<String>('xsheet-rail-cursor-overlay'),
                  ),
                )
                .painter!
            as TimelineRulerCursorOverlayPainter;

    // Frames 0-1 cached, 2 not — and frames past the playback range never
    // show the strip even when the resolver claims them cached.
    expect(overlay.cachedRuns(), [(startIndex: 0, endIndexExclusive: 2)]);
  });

  testWidgets('renders frame rows and cells', (tester) async {
    await tester.pumpWidget(_grid());

    expect(xsheetFrameRowInWindow(tester, 0), isTrue);
    expect(
      timelineCellInWindow(tester, 'layer-1', 0, prefix: 'xsheet'),
      isTrue,
    );
    expect(
      timelineCellInWindow(tester, 'layer-2', 0, prefix: 'xsheet'),
      isTrue,
    );
  });

  testWidgets('selecting a cell selects layer and frame', (tester) async {
    LayerId? selectedLayerId;
    int? selectedFrameIndex;

    await tester.pumpWidget(
      _grid(
        onSelectLayer: (layerId) => selectedLayerId = layerId,
        onSelectFrame: (frameIndex) => selectedFrameIndex = frameIndex,
      ),
    );

    await tapTimelineCell(tester, 'layer-1', 3, prefix: 'xsheet');

    expect(selectedLayerId, const LayerId('layer-1'));
    expect(selectedFrameIndex, 3);
  });

  testWidgets('selects layer from header', (tester) async {
    LayerId? selectedLayerId;

    await tester.pumpWidget(
      _grid(onSelectLayer: (layerId) => selectedLayerId = layerId),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('xsheet-layer-name-layer-2')),
    );

    expect(selectedLayerId, const LayerId('layer-2'));
  });

  testWidgets('shows drawing marker', (tester) async {
    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-2') && frameIndex == 2
            ? TimelineCellExposureState.drawingStart
            : TimelineCellExposureState.uncovered,
      ),
    );

    expect(_xsheetGlyph(tester, 'layer-2', 2), '○');
  });

  testWidgets('shows held exposure marker', (tester) async {
    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-2') && frameIndex == 2
            ? TimelineCellExposureState.held
            : TimelineCellExposureState.uncovered,
      ),
    );

    expect(
      timelineCellModel(tester, 'layer-2', 2, prefix: 'xsheet').semanticsLabel,
      'held exposure',
    );
  });

  testWidgets('only the first cell of an empty run shows the timesheet X', (
    tester,
  ) async {
    await tester.pumpWidget(_grid());

    expect(_xsheetGlyph(tester, 'layer-2', 0), 'X');
    expect(_xsheetGlyph(tester, 'layer-2', 2), '');
  });

  testWidgets('shows inbetween mark with priority over exposure marker', (
    tester,
  ) async {
    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-2') && frameIndex == 2
            ? TimelineCellExposureState.markHeld
            : TimelineCellExposureState.uncovered,
      ),
    );

    expect(_xsheetGlyph(tester, 'layer-2', 2), '●');
    expect(
      timelineCellModel(tester, 'layer-2', 2, prefix: 'xsheet').semanticsLabel,
      'inbetween mark',
    );
  });

  testWidgets('shows inbetween mark on blank held cell', (tester) async {
    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-2') && frameIndex == 2
            ? TimelineCellExposureState.markUncovered
            : TimelineCellExposureState.uncovered,
      ),
    );

    expect(_xsheetGlyph(tester, 'layer-2', 2), '●');
  });

  testWidgets('empty cells stay blank', (tester) async {
    await tester.pumpWidget(_grid());

    expect(_xsheetGlyph(tester, 'layer-1', 2), isNot('○'));
    expect(
      timelineCellModel(tester, 'layer-1', 2, prefix: 'xsheet').semanticsLabel,
      isNull,
    );
  });

  testWidgets('current frame row uses plain text', (tester) async {
    await tester.pumpWidget(_grid(currentFrameIndex: 3));

    expect(
      xsheetFrameRowModel(tester, 3).label,
      '4',
      reason: 'the plain one-based number, no playhead glyph',
    );
    // The current row reads by TINT, painted by the rail's cursor overlay
    // (the numbers themselves are cursor-independent now).
    expect(xsheetRailTintedFrame(tester), 3);
  });

  testWidgets('named drawing start displays name and mark has priority', (
    tester,
  ) async {
    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-2') && frameIndex == 2
            ? TimelineCellExposureState.drawingStart
            : TimelineCellExposureState.uncovered,
        frameNameForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-2') && frameIndex == 2
            ? 'A1'
            : null,
      ),
    );

    expect(_xsheetGlyph(tester, 'layer-2', 2), 'A1');

    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-2') && frameIndex == 2
            ? TimelineCellExposureState.markHeld
            : TimelineCellExposureState.uncovered,
        frameNameForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-2') && frameIndex == 2
            ? 'A1'
            : null,
      ),
    );

    expect(_xsheetGlyph(tester, 'layer-2', 2), '●');
  });

  testWidgets('marks only the active current cell as selected', (tester) async {
    await tester.pumpWidget(_grid(currentFrameIndex: 2));

    expect(
      find.byKey(const ValueKey<String>('xsheet-selected-cell')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('xsheet-selected-layer')),
      findsOneWidget,
    );
    expect(
      timelineCellInWindow(tester, 'layer-1', 2, prefix: 'xsheet'),
      isTrue,
    );
    expect(
      timelineCellInWindow(tester, 'layer-2', 2, prefix: 'xsheet'),
      isTrue,
    );
  });

  testWidgets('selected cell preserves symbol display priority', (
    tester,
  ) async {
    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-1') && frameIndex == 0
            ? TimelineCellExposureState.drawingStart
            : TimelineCellExposureState.uncovered,
      ),
    );
    expect(_xsheetGlyph(tester, 'layer-1', 0), '○');

    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-1') && frameIndex == 0
            ? TimelineCellExposureState.uncovered
            : TimelineCellExposureState.uncovered,
      ),
    );
    expect(_xsheetGlyph(tester, 'layer-1', 0), 'X');

    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-1') && frameIndex == 0
            ? TimelineCellExposureState.drawingStart
            : TimelineCellExposureState.uncovered,
        frameNameForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-1') && frameIndex == 0
            ? 'A1'
            : null,
      ),
    );
    expect(_xsheetGlyph(tester, 'layer-1', 0), 'A1');

    await tester.pumpWidget(
      _grid(
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-1') && frameIndex == 0
            ? TimelineCellExposureState.markHeld
            : TimelineCellExposureState.uncovered,
        frameNameForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-1') && frameIndex == 0
            ? 'A1'
            : null,
      ),
    );
    expect(_xsheetGlyph(tester, 'layer-1', 0), '●');
  });

  testWidgets('held exposure run renders as one vertical block', (
    tester,
  ) async {
    await tester.pumpWidget(
      _grid(
        frameCount: 4,
        exposureStateForLayer: (layer, frameIndex) {
          if (layer.id != const LayerId('layer-1')) {
            return TimelineCellExposureState.uncovered;
          }
          return switch (frameIndex) {
            0 => TimelineCellExposureState.drawingStart,
            1 || 2 => TimelineCellExposureState.held,
            _ => TimelineCellExposureState.uncovered,
          };
        },
      ),
    );

    final startRadius =
        _cellDecoration(tester, 'xsheet-cell-layer-1-0').borderRadius!
            as BorderRadius;
    expect(startRadius.topLeft, const Radius.circular(6));
    expect(startRadius.bottomLeft, Radius.zero);

    final midRadius =
        _cellDecoration(tester, 'xsheet-cell-layer-1-1').borderRadius
            as BorderRadius?;
    expect(midRadius, BorderRadius.zero);

    final endRadius =
        _cellDecoration(tester, 'xsheet-cell-layer-1-2').borderRadius!
            as BorderRadius;
    expect(endRadius.topLeft, Radius.zero);
    expect(endRadius.bottomLeft, const Radius.circular(6));
  });

  testWidgets('shows the shared playhead row tint at the current frame', (
    tester,
  ) async {
    await tester.pumpWidget(_grid(currentFrameIndex: 2));

    expect(
      find.byKey(const ValueKey<String>('timeline-playhead-column')),
      findsOneWidget,
    );
  });

  testWidgets('shows cut-end boundary lines past the playback range', (
    tester,
  ) async {
    await tester.pumpWidget(_grid(frameCount: 12));

    expect(
      find.byKey(const ValueKey<String>('timeline-cut-end-boundary')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timeline-cut-end-boundary-ruler')),
      findsOneWidget,
    );
  });

  testWidgets('outlines the selected exposure run', (tester) async {
    await tester.pumpWidget(
      _grid(
        frameCount: 4,
        exposureStateForLayer: (layer, frameIndex) =>
            layer.id == const LayerId('layer-1') && frameIndex == 0
            ? TimelineCellExposureState.drawingStart
            : TimelineCellExposureState.uncovered,
      ),
    );

    expect(
      find.byKey(
        const ValueKey<String>(
          'timeline-selected-exposure-range-outline-layer-1',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('virtualizes long cuts to the visible frame window', (
    tester,
  ) async {
    await tester.pumpWidget(_grid(frameCount: 500));

    expect(
      timelineCellInWindow(tester, 'layer-1', 0, prefix: 'xsheet'),
      isTrue,
    );
    expect(
      timelineCellInWindow(tester, 'layer-1', 499, prefix: 'xsheet'),
      isFalse,
    );
    expect(
      xsheetFrameRowInWindow(tester, 499),
      isFalse,
      reason: 'the painterized rail windows with the cells (UI-R14 #1)',
    );
  });

  testWidgets('dims frames beyond the playback range like the timeline', (
    tester,
  ) async {
    await tester.pumpWidget(_grid(frameCount: 12));

    // The visible window extends to the shared 24-frame minimum, so frames
    // past the 12-frame playback range render dimmed (on the inactive layer
    // to keep the active-layer tint out of the comparison).
    final inside = _cellDecoration(tester, 'xsheet-cell-layer-2-0').color;
    final outside = _cellDecoration(tester, 'xsheet-cell-layer-2-13').color;
    expect(outside, isNot(inside));
  });

  testWidgets('dragging the frame rail scrubs the current frame', (
    tester,
  ) async {
    final selected = <int>[];
    await tester.pumpWidget(_grid(onSelectFrame: selected.add));

    await tester.drag(
      find.byKey(const ValueKey<String>('xsheet-frame-rail-scrub-area')),
      const Offset(0, 80),
    );
    await tester.pumpAndSettle();

    expect(selected, isNotEmpty);
  });

  test('cell style keeps drawing cells neutral; blank cells paint NOTHING '
      '(the column underlay owns the paper, UI-R21 #2)', () {
    const colorScheme = ColorScheme.light();

    final drawingStart = timelineCellStyleColors(
      colorScheme: colorScheme,
      exposureState: TimelineCellExposureState.drawingStart,
      selected: false,
    );
    final heldDrawing = timelineCellStyleColors(
      colorScheme: colorScheme,
      exposureState: TimelineCellExposureState.held,
      selected: false,
    );
    final uncovered = timelineCellStyleColors(
      colorScheme: colorScheme,
      exposureState: TimelineCellExposureState.uncovered,
      selected: false,
    );
    final selectedDrawing = timelineCellStyleColors(
      colorScheme: colorScheme,
      exposureState: TimelineCellExposureState.held,
      selected: true,
    );

    expect(heldDrawing.background, timelineDrawingHeldColor);
    expect(drawingStart.background, timelineDrawingStartColor);
    expect(drawingStart.background, heldDrawing.background);
    // UI-R20 #7: the block head's dark silhouette is GONE — the start
    // seam sits on the same faint grid ink as the held seams.
    expect(drawingStart.border, heldDrawing.border);
    expect(uncovered.background, Colors.transparent);
    expect(selectedDrawing.border, timelineSelectedFrameBorderColor);
    expect(selectedDrawing.background, isNot(heldDrawing.background));
  });
}

BoxDecoration _cellDecoration(WidgetTester tester, String key) {
  // Painted cells (UI-R9 #12b): decoration reads resolve through the
  // painter probe.
  final cell = parseTimelineCellKey(key);
  return timelineCellDecoration(
    tester,
    cell.layerId,
    cell.frameIndex,
    prefix: 'xsheet',
  );
}

Widget _grid({
  int currentFrameIndex = 0,
  int frameCount = 12,
  TimelineCellExposureState Function(Layer layer, int frameIndex)?
  exposureStateForLayer,
  ValueChanged<LayerId>? onSelectLayer,
  ValueChanged<int>? onSelectFrame,
  VoidCallback? onAddLayer,
  ValueChanged<LayerId>? onToggleLayerVisibility,
  void Function(LayerId layerId, double opacity)? onLayerOpacityChanged,
  ValueChanged<LayerId>? onToggleLayerTimesheet,
  void Function(LayerId layerId, LayerMark mark)? onLayerMarkSelected,
  String? Function(Layer layer, int frameIndex)? frameNameForLayer,
  bool Function(int frameIndex)? isFrameCached,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 900,
        height: 600,
        child: XSheetTimelineGrid(
          layers: _layers,
          activeLayerId: const LayerId('layer-1'),
          frameCursor: ValueNotifier<int>(currentFrameIndex),
          frameCount: frameCount,
          exposureStateForLayer:
              exposureStateForLayer ??
              (_, _) => TimelineCellExposureState.uncovered,
          frameNameForLayer: frameNameForLayer,
          onSelectLayer: onSelectLayer ?? (_) {},
          onSelectFrame: onSelectFrame ?? (_) {},
          onAddLayer: onAddLayer ?? () {},
          onToggleLayerVisibility: onToggleLayerVisibility ?? (_) {},
          onLayerOpacityChanged: onLayerOpacityChanged ?? (_, _) {},
          onToggleLayerTimesheet: onToggleLayerTimesheet ?? (_) {},
          onLayerMarkSelected: onLayerMarkSelected ?? (_, _) {},
          isFrameCached: isFrameCached,
        ),
      ),
    ),
  );
}

final _layers = [
  Layer(
    id: const LayerId('layer-1'),
    name: 'Layer 1',
    frames: [
      Frame(id: const FrameId('frame-1'), duration: 1, strokes: const []),
    ],
  ),
  Layer(
    id: const LayerId('layer-2'),
    name: 'Layer 2',
    opacity: 0.5,
    frames: [
      Frame(id: const FrameId('frame-2'), duration: 1, strokes: const []),
    ],
  ),
];
