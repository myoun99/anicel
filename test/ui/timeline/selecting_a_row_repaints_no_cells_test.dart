import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';
import 'package:anicel/src/ui/timeline/timeline_row_selection_bands.dart';

import '../../helpers/exposure_of.dart';
import '../../helpers/named_finders.dart';

/// 🚨THE SELECTION'S HALF OF THE PLAYBACK-PERFORMANCE INVARIANT.
///
/// `timeline_cursor_rebuild_test` pins the cursor: a playback tick repaints
/// the cursor layer and rulers only. This pins the other verb the user drags
/// with — SELECTING rows — and it is the one F-26 is about (유저: 「게다가
/// 렉도있고」 on the X-sheet's selection band).
///
/// The selection reaches the grid as a channel, as `frameCursor` does, and
/// the bands hear it ([TimelineRowSelectionBands]): selecting a row builds
/// no grid, and no cell painter is made again. ↩️It was a plain `Set` the
/// host handed down, and every step of a sweep built the whole panel
/// (a_row_sweep_step_repaints_only_its_bands_test has what that cost).
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
  // Four one-frame drawings on every row, on the LAYER: a row walks its
  // cells by where its layer's blocks change (I-22).
  List<Layer> twelveLayers() => [
        for (var i = 1; i <= 12; i++)
          Layer(
            id: LayerId('layer-$i'),
            name: 'L$i',
            frames: [
              Frame(id: const FrameId('cel'), duration: 1, strokes: const []),
            ],
            timeline: {
              for (var frame = 0; frame < 4; frame++)
                frame: const TimelineExposure.drawing(
                  FrameId('cel'),
                  length: 1,
                ),
            },
          ),
      ];

  const stateFor = exposureOf;

  Widget grid(
    List<Layer> layers,
    ValueNotifier<List<TimelineRowAddress>> selection,
    ValueNotifier<int> cursor, {
    int frameCount = 120,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: LayerTimelineGrid(
hooks: TimelineGridHooks(activeLayer: ValueNotifier(const LayerId('layer-1')),
frameCursor: cursor,
playbackFrameCount: frameCount,
exposureStateForLayer: stateFor,
rowSelection: selection,
onSelectLayer: (_) {},
onSelectFrame: (_) {},
onToggleLayerVisibility: (_) {},
onLayerOpacityChanged: (_, _) {},
onToggleLayerTimesheet: (_) {},
onLayerMarkSelected: (_, _) {},),
layers: layers,
),
        ),
      );

  List<CustomPaint> rowPaints(WidgetTester tester) => tester
      .widgetList<CustomPaint>(
        find.namedWhere((name) => name.startsWith('timeline-row-cells-')),
      )
      .toList();

  Finder bands() => find.descendant(
        of: find.byType(TimelineRowSelectionBands),
        matching: find.byType(DecoratedBox),
      );

  testWidgets('⛔premise: the axis MOVES when every row\'s cells change',
      (tester) async {
    final cursor = ValueNotifier<int>(2);
    addTearDown(cursor.dispose);
    final selection = ValueNotifier<List<TimelineRowAddress>>(const []);
    addTearDown(selection.dispose);
    await tester.pumpWidget(grid(twelveLayers(), selection, cursor));
    final before = [for (final p in rowPaints(tester)) p.painter];
    expect(before, hasLength(12));

    await tester.pumpWidget(
      grid(twelveLayers(), selection, cursor, frameCount: 200),
    );
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

  testWidgets('🚨selecting a row builds no grid and no cell painter — the '
      'bands draw it', (tester) async {
    final cursor = ValueNotifier<int>(2);
    addTearDown(cursor.dispose);
    final selection = ValueNotifier<List<TimelineRowAddress>>(const []);
    addTearDown(selection.dispose);
    final layers = twelveLayers();
    await tester.pumpWidget(grid(layers, selection, cursor));
    final before = [for (final p in rowPaints(tester)) p.painter];
    expect(bands(), findsNothing, reason: 'nothing is selected yet');

    final built = <Type>[];
    debugOnRebuildDirtyWidget = (element, _) =>
        built.add(element.widget.runtimeType);
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    selection.value = const [LayerRowAddress(LayerId('layer-3'))];
    await tester.pump();
    debugOnRebuildDirtyWidget = null;

    expect(
      bands(),
      findsOneWidget,
      reason: 'LIVENESS: the selection reached the bands',
    );
    expect(
      built,
      isNot(contains(LayerTimelineGrid)),
      reason: 'the selection is a channel the bands hear, not a field the '
          'grid is built again for',
    );
    final after = rowPaints(tester);
    expect(after, hasLength(12));
    var unchanged = 0;
    for (var i = 0; i < after.length && i < before.length; i++) {
      if (identical(after[i].painter, before[i])) unchanged++;
    }
    expect(unchanged, 12, reason: 'the wash belongs to the bands, not to '
        'twelve rows of cells');
  });

  testWidgets('⛔and the SELECTED row is not special — its cells are cells',
      (tester) async {
    // 🚨The one row you would expect to repaint. If the selection ever starts
    // drawing itself through the cell painter, this is where it shows up —
    // and it would put the band's cost on the grid's hot path.
    final cursor = ValueNotifier<int>(2);
    addTearDown(cursor.dispose);
    final selection = ValueNotifier<List<TimelineRowAddress>>(const []);
    addTearDown(selection.dispose);
    final layers = twelveLayers();
    await tester.pumpWidget(grid(layers, selection, cursor));
    final row3 = tester.widget<CustomPaint>(
      find.named('timeline-row-cells-layer-3'),
    );

    selection.value = const [LayerRowAddress(LayerId('layer-3'))];
    await tester.pump();

    expect(
      identical(
        tester
            .widget<CustomPaint>(
              find.named('timeline-row-cells-layer-3'),
            )
            .painter,
        row3.painter,
      ),
      isTrue,
    );
  });
}
