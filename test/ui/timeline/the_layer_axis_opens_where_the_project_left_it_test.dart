import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

import '../../helpers/scrollable_of.dart';

/// 🚨★★★**THE LAYER AXIS OPENS WHERE THE PROJECT LEFT IT** (F-267).
///
/// 🗣️유저 2026-10-01: 「콘티패널,타임라인패널 스크롤상태 … 프로젝트 파일에
/// 기록해서 다시 열면 그대로 열리도록」. The frame axis has been kept above
/// the grids since F-143; the OTHER axis — the timeline's rows, the sheet's
/// columns — lived in a controller born at zero, so a project always opened
/// on its top rows whatever its file said.
///
/// ⛔ON THE FIRST FRAME, not after a settle. The rows are windowed, and a
/// window cut at the top for a scrollable born lower shows spacers there —
/// and the layout's own pull then hauls the rows back to the top.
void main() {
  Layer layer(String id) => Layer(
    id: LayerId(id),
    name: id,
    kind: LayerKind.animation,
    frames: [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])],
    timeline: const {},
  );

  final layers = <Layer>[for (var i = 0; i < 40; i += 1) layer('draw-$i')];

  Widget panel(
    TimelineOrientation orientation, {
    required ValueNotifier<int> cursor,
    ValueNotifier<double>? rows,
    ValueNotifier<double>? columns,
  }) => MaterialApp(
    home: Scaffold(
      body: TimelinePanel(
        layers: layers,
        activeLayerId: const LayerId('draw-0'),
        frameCursor: cursor,
        playbackFrameCount: 12,
        exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
        onSelectLayer: (_) {},
        onSelectFrame: (_) {},
        onAddLayer: () {},
        onToggleLayerVisibility: (_) {},
        onLayerOpacityChanged: (_, _) {},
        onToggleLayerTimesheet: (_) {},
        onLayerMarkSelected: (_, _) {},
        orientation: orientation,
        onOrientationChanged: (_) {},
        timelineLayerAxisOffset: rows,
        xsheetLayerAxisOffset: columns,
      ),
    ),
  );

  Future<ValueNotifier<int>> sized(WidgetTester tester) async {
    // Small on purpose: the rows and the columns must overflow.
    await tester.binding.setSurfaceSize(const Size(560, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    return cursor;
  }

  final rowsViewport = find.byKey(
    const ValueKey<String>('timeline-vertical-scroll-viewport'),
  );
  final columnsViewport = find.byKey(
    const ValueKey<String>('xsheet-layer-horizontal-viewport'),
  );

  /// The rows the rail has built right now — the window, by name.
  Set<String> builtRows() => {
    for (final element in find
        .byWidgetPredicate(
          (widget) => switch (widget.key) {
            ValueKey<String>(:final value) => value.startsWith(
              'timeline-layer-name-',
            ),
            _ => false,
          },
        )
        .evaluate())
      (element.widget.key! as ValueKey<String>).value,
  };

  testWidgets('🚨the timeline\'s rows are born where the project left them — '
      'and every scroll of them is what the project keeps', (tester) async {
    final cursor = await sized(tester);
    final kept = ValueNotifier<double>(0);
    addTearDown(kept.dispose);
    await tester.pumpWidget(
      panel(TimelineOrientation.horizontal, cursor: cursor, rows: kept),
    );
    await tester.pumpAndSettle();
    final scrolled = scrollableOf(tester, rowsViewport).controller!;
    expect(
      scrolled.position.maxScrollExtent,
      greaterThan(400),
      reason: '⛔전제: the rows really overflow',
    );
    scrolled.jumpTo(400);
    await tester.pumpAndSettle();
    expect(kept.value, 400, reason: 'a scroll of the rows is kept');
    final window = builtRows();
    expect(
      window,
      isNot(contains('timeline-layer-name-draw-0')),
      reason: '⛔전제: the rows are windowed — the top row is not built',
    );

    // A grid born again — the next open of the project, a tab coming back.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      panel(TimelineOrientation.horizontal, cursor: cursor, rows: kept),
    );

    expect(
      scrollableOf(tester, rowsViewport).controller!.offset,
      400,
      reason: '🚨born where it was left, on the first frame',
    );
    expect(
      builtRows(),
      window,
      reason: '🚨and the rows standing there are built — not spacers',
    );
    await tester.pumpAndSettle();
    expect(
      scrollableOf(tester, rowsViewport).controller!.offset,
      400,
      reason: 'nothing hauls it back to the top once the layout has run',
    );
  });

  testWidgets('🚨the sheet\'s columns are born where the project left them — '
      'and every scroll of them is what the project keeps', (tester) async {
    final cursor = await sized(tester);
    final kept = ValueNotifier<double>(0);
    addTearDown(kept.dispose);
    await tester.pumpWidget(
      panel(TimelineOrientation.vertical, cursor: cursor, columns: kept),
    );
    await tester.pumpAndSettle();
    final scrolled = scrollableOf(tester, columnsViewport).controller!;
    expect(
      scrolled.position.maxScrollExtent,
      greaterThan(200),
      reason: '⛔전제: the columns really overflow',
    );
    scrolled.jumpTo(200);
    await tester.pumpAndSettle();
    expect(kept.value, 200, reason: 'a scroll of the columns is kept');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      panel(TimelineOrientation.vertical, cursor: cursor, columns: kept),
    );

    expect(
      scrollableOf(tester, columnsViewport).controller!.offset,
      200,
      reason: '🚨born where it was left, on the first frame',
    );
  });
}
