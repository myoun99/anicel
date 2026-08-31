import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';

/// 🚨THE SELECTION'S HALF OF THE PLAYBACK-PERFORMANCE INVARIANT.
///
/// `timeline_cursor_rebuild_test` pins the cursor: a playback tick repaints
/// the cursor layer and rulers only. This pins the other verb the user drags
/// with — SELECTING rows — and it is the one F-26 is about (유저: 「게다가
/// 렉도있고」 on the X-sheet's selection band).
///
/// ⚠️`selectedRows` is a plain `Set` field, not a listenable like
/// `frameCursor`, so the host rebuilds the whole grid when it changes. That
/// asymmetry is what made this worth measuring: it LOOKS like every row must
/// repaint. It does not — the wash is the rail's and the band's, and the cell
/// painters are memoised per row.
///
/// 🚨★★★THE AXIS PREMISE IS PART OF THE TEST, and it is not decoration.
/// 🧪Measured while writing this: TWO of my first three instrument checks
/// reported 「nothing moved」 and both were worthless.
///   · changing a value a CLOSURE reads — the widget cannot see it, so of
///     course nothing rebuilt.
///   · adding a LAYER — that does not touch the other rows' own inputs, so
///     it measures memoisation, not the axis.
/// Only a field that changes every row's cells (the frame count) proves the
/// axis can move at all. ⛔Without it, 「12/12 unchanged」 is 「빈 것을 쟀다」
/// wearing a number.
void main() {
  List<Layer> twelveLayers() => [
        for (var i = 1; i <= 12; i++)
          Layer(id: LayerId('layer-$i'), name: 'L$i', frames: const []),
      ];

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) =>
      frameIndex < 4
          ? TimelineCellExposureState.drawingStart
          : TimelineCellExposureState.uncovered;

  Widget grid(
    List<Layer> layers,
    Set<TimelineRowAddress> selected,
    ValueNotifier<int> cursor, {
    int frameCount = 120,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: LayerTimelineGrid(
            layers: layers,
            activeLayerId: const LayerId('layer-1'),
            frameCursor: cursor,
            playbackFrameCount: frameCount,
            exposureStateForLayer: stateFor,
            selectedRows: selected,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
          ),
        ),
      );

  List<CustomPaint> rowPaints(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byWidgetPredicate((w) =>
          w is CustomPaint &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>)
              .value
              .startsWith('timeline-row-cells-')))
      .toList();

  testWidgets('⛔premise: the axis MOVES when every row\'s cells change',
      (tester) async {
    final cursor = ValueNotifier<int>(2);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(grid(twelveLayers(), const {}, cursor));
    final before = [for (final p in rowPaints(tester)) p.painter];
    expect(before, hasLength(12));

    await tester
        .pumpWidget(grid(twelveLayers(), const {}, cursor, frameCount: 200));
    final after = rowPaints(tester);
    var unchanged = 0;
    for (var i = 0; i < after.length && i < before.length; i++) {
      if (identical(after[i].painter, before[i])) unchanged++;
    }
    expect(
      unchanged,
      0,
      reason: '🚨if this is not zero, painter identity says nothing and every '
          'assertion below is measuring an empty thing',
    );
  });

  testWidgets('🚨selecting a row rebuilds no cell painter and repaints none',
      (tester) async {
    final cursor = ValueNotifier<int>(2);
    addTearDown(cursor.dispose);
    final layers = twelveLayers();
    await tester.pumpWidget(grid(layers, const {}, cursor));
    final before = [for (final p in rowPaints(tester)) p.painter];

    await tester.pumpWidget(grid(
      layers,
      {const LayerRowAddress(LayerId('layer-3'))},
      cursor,
    ));

    final after = rowPaints(tester);
    expect(after, hasLength(12));
    var unchanged = 0;
    var wouldRepaint = 0;
    for (var i = 0; i < after.length && i < before.length; i++) {
      if (identical(after[i].painter, before[i])) {
        unchanged++;
      } else if (after[i].painter!.shouldRepaint(before[i]!)) {
        wouldRepaint++;
      }
    }
    expect(
      unchanged,
      12,
      reason: '⛔`selectedRows` is a plain field, so the grid DOES rebuild — '
          'the cells must still come through untouched. The wash belongs to '
          'the rail and the band, not to twelve rows of cells',
    );
    expect(wouldRepaint, 0);
  });

  testWidgets('⛔and the SELECTED row is not special — its cells are cells',
      (tester) async {
    // 🚨The one row you would expect to repaint. If the selection ever starts
    // drawing itself through the cell painter, this is where it shows up —
    // and it would put the band's cost on the grid's hot path.
    final cursor = ValueNotifier<int>(2);
    addTearDown(cursor.dispose);
    final layers = twelveLayers();
    await tester.pumpWidget(grid(layers, const {}, cursor));
    final row3 = tester.widget<CustomPaint>(
      find.byKey(const ValueKey<String>('timeline-row-cells-layer-3')),
    );

    await tester.pumpWidget(grid(
      layers,
      {const LayerRowAddress(LayerId('layer-3'))},
      cursor,
    ));

    expect(
      identical(
        tester
            .widget<CustomPaint>(
              find.byKey(
                  const ValueKey<String>('timeline-row-cells-layer-3')),
            )
            .painter,
        row3.painter,
      ),
      isTrue,
    );
  });
}
