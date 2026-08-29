import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';

/// 🚨F-32 (유저): 「트랜지션·카메라 레이어만 **스크롤에 따라** 위치가
/// 어긋난다」.
///
/// 🧪Measured 2026-08-29: AT REST every kind agrees — rail row top and cells
/// row top are the same value for camera, transitions, instructions, SE and
/// drawing rows alike. So the drift is not in how a row is BUILT; it is in
/// what happens to it once the view is scrolled, which is exactly the word
/// the user used.
///
/// This drives the offset the way the app's own scrollbar does
/// (`controller.jumpTo`), because a drag on the rows is a RANGE SELECT since
/// the press-claim rounds — the reason the first probe could not reproduce
/// it at all.
///
/// ⛔EVERY kind, not just the two reported. A pair that only checks camera
/// and transition passes the day someone breaks the SE row instead, and
/// 「전 가족 × 전 인터랙션」 is the standing rule.
void main() {
  Layer layer(String id, LayerKind kind) => Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    frames: kind == LayerKind.animation
        ? [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])]
        : const [],
    timeline: const {},
  );

  /// One of every kind that owns a row, plus enough drawing rows underneath
  /// to make the view overflow.
  final layers = <Layer>[
    layer('cam', LayerKind.camera),
    layer('transitions', LayerKind.transition),
    layer('instructions', LayerKind.instruction),
    layer('se-1', LayerKind.se),
    for (var i = 0; i < 12; i += 1) layer('draw-$i', LayerKind.animation),
  ];

  Widget host() => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 1100,
        height: 264,
        child: LayerTimelineGrid(
          layers: layers,
          activeLayerId: const LayerId('draw-0'),
          frameCursor: ValueNotifier<int>(0),
          playbackFrameCount: 12,
          exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
          onSelectLayer: (_) {},
          onSelectFrame: (_) {},
          onAddLayer: () {},
          onToggleLayerVisibility: (_) {},
          onLayerOpacityChanged: (_, _) {},
          onToggleLayerTimesheet: (_) {},
          onLayerMarkSelected: (_, _) {},
        ),
      ),
    ),
  );

  ScrollController controllerOf(WidgetTester tester) => tester
      .widget<SingleChildScrollView>(
        find.byKey(const ValueKey<String>('timeline-vertical-scroll-viewport')),
      )
      .controller!;

  double railTop(WidgetTester tester, String id) => tester
      .getRect(find.byKey(ValueKey<String>('timeline-rail-row-$id-row')))
      .top;

  double cellsTop(WidgetTester tester, String id) => tester
      .getRect(find.byKey(ValueKey<String>('timeline-row-cells-$id')))
      .top;

  testWidgets('every row kind keeps its rail and its cells on ONE line, at '
      'rest and at every scroll offset', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final controller = controllerOf(tester);
    expect(
      controller.position.maxScrollExtent,
      greaterThan(0),
      reason: 'the fixture must overflow, or nothing can scroll at all',
    );

    // ⚠️Fractional offsets on purpose. A drift that is exactly one row
    // height hides at multiples of the row height, and the report is 2px —
    // the size of a rounding that only shows between device pixels.
    final offsets = <double>[
      0,
      1,
      2,
      13,
      controller.position.maxScrollExtent / 3,
      controller.position.maxScrollExtent / 2,
      controller.position.maxScrollExtent,
    ];

    // 🚨A green that compared nothing looks exactly like a green that
    // compared everything. Count the comparisons and demand them.
    var compared = 0;
    for (final offset in offsets) {
      controller.jumpTo(offset);
      await tester.pumpAndSettle();
      for (final row in layers) {
        final id = row.id.value;
        final rail = find.byKey(ValueKey<String>('timeline-rail-row-$id-row'));
        final cells = find.byKey(ValueKey<String>('timeline-row-cells-$id'));
        if (rail.evaluate().isEmpty || cells.evaluate().isEmpty) {
          // Scrolled out of the window — nothing to compare, and windowing
          // is not what this test is about.
          continue;
        }
        compared += 1;
        expect(
          cellsTop(tester, id),
          moreOrLessEquals(railTop(tester, id), epsilon: 0.01),
          reason:
              '$id (${row.kind.name}) drifted at offset $offset — this is '
              'F-32: 「트랜지션·카메라 레이어만 스크롤에 따라 위치가 '
              '어긋난다」',
        );
      }
    }
    expect(
      compared,
      greaterThanOrEqualTo(offsets.length * 4),
      reason:
          'every offset must have compared at least the four kinds the '
          'report names, or this test is measuring an empty window',
    );
  });
}
