import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';

/// T8: crossing a ROW boundary re-windows the scroll body and nothing else.
///
/// 🚨The cost this pins is not the widgets — it is the row MODEL above them.
/// The grid's `build` opens with `buildTimelineDisplayRows` over every layer
/// and every open lane, and the vertical axis used to answer a crossing with
/// `setState(() {})` on the State. So scrolling a tall stack rebuilt the
/// whole model once per row, to change which slice of it gets widgets. The
/// frame axis has not done that since UI-R9 #12a.
void main() {
  Layer layer(String id) => Layer(
    id: LayerId(id),
    name: id,
    frames: [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])],
    timeline: const {},
  );

  // Tall enough that most rows are outside a short viewport, so a crossing
  // genuinely changes the window rather than re-rendering the same slice.
  final layers = [for (var i = 0; i < 40; i++) layer('L$i')];

  Widget grid() => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 900,
        height: 240,
        child: LayerTimelineGrid(
          hooks: TimelineGridHooks(
            activeLayer: ValueNotifier(const LayerId('L0')),
            frameCursor: ValueNotifier<int>(0),
            playbackFrameCount: 12,
            exposureStateForLayer: (_, _) =>
                TimelineCellExposureState.uncovered,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
          ),
          layers: layers,
        ),
      ),
    ),
  );

  /// The widget the grid's `build` returns for the scrollbar area — the
  /// nearest thing ABOVE the window token.
  ///
  /// 🎯Identity is the witness, and it is exact: a `setState` on the grid
  /// runs `build` and every widget it returns is a NEW instance, while a
  /// token notification rebuilds only the subtree that subscribes. No
  /// counter to instrument, and nothing that a callback shared with the row
  /// widgets could confuse — measured that route first: `lanesForLayer` and
  /// `layerFxStateOf` are each called BOTH from the row model and from every
  /// row widget, so counting them cannot tell the two apart.
  Widget scrollArea(WidgetTester tester) => tester.widget(
    find.byKey(const ValueKey<String>('timeline-scrollbar-area')),
  );

  Future<void> wheelBy(WidgetTester tester, double dy) async {
    // ⛔A wheel, not a drag: a drag inside the rows is a row-reorder or a
    // cell-range gesture, and would prove something else entirely.
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final at = tester.getCenter(find.byType(LayerTimelineGrid));
    pointer.hover(at);
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pump();
  }

  testWidgets('a row crossing rebuilds the scroll body, NOT the grid', (
    tester,
  ) async {
    await tester.pumpWidget(grid());
    await tester.pumpAndSettle();

    final before = scrollArea(tester);
    final topBefore = find.text('L0').evaluate().isNotEmpty;
    expect(topBefore, isTrue, reason: 'the first row starts in view');

    // Well past one row, so the window certainly moves.
    await wheelBy(tester, timelineLayerRowHeight * 6);

    expect(
      find.text('L0').evaluate().isEmpty,
      isTrue,
      reason: 'the window really moved — otherwise this pin proves nothing',
    );
    expect(
      identical(scrollArea(tester), before),
      isTrue,
      reason:
          'the grid did not rebuild: the row model is untouched and only '
          'the body re-windowed',
    );
  });

  /// The rows built now, by name — in view or not.
  Set<String> built() => {
    for (final layer in layers)
      if (find.text(layer.name).evaluate().isNotEmpty) layer.name,
  };

  /// The rows a pointer reaches now, by name — in view.
  Set<String> inView() => {
    for (final layer in layers)
      if (find.text(layer.name).hitTestable().evaluate().isNotEmpty)
        layer.name,
  };

  /// The rows built wholly below the grid, by name — past the view, not a
  /// row the view's edge cuts.
  Set<String> builtBelow(WidgetTester tester) {
    final bottom = tester.getRect(find.byType(LayerTimelineGrid)).bottom;
    return {
      for (final name in built())
        if (tester.getTopLeft(find.text(name)).dy >= bottom) name,
    };
  }

  // 🗣️유저 2026-11-18 (a-timeline-wheel-notch-lays-out-the-rail-Q1 = B):
  // spare rows past the view, always — [timelineRowWindowMargin].
  testWidgets('the rows a notch brings in stand built before it, either '
      'way, and the frame the grid opens in builds them too', (tester) async {
    await tester.pumpWidget(grid());

    expect(
      builtBelow(tester),
      isNotEmpty,
      reason: 'the opening frame built rows past the view',
    );

    await tester.pumpAndSettle();
    // A notch at 100%, as Windows' wheel turns it — down, then back up.
    for (final notch in [100.0, -100.0]) {
      final before = built();
      final seen = inView();
      await wheelBy(tester, notch);
      final came = inView().difference(seen);
      expect(
        came,
        isNotEmpty,
        reason: 'the notch brought rows in — else this proves nothing',
      );
      expect(
        came.difference(before),
        isEmpty,
        reason: 'every row the notch $notch brought in was built before',
      );
    }
  });

  // 🗣️유저 2026-11-18 (a-timeline-wheel-notch-lays-out-the-rail-Q2 = 1,
  // 「칸 뒤 쉬는 프레임에 짓기」).
  testWidgets('a notch lays no row in its own frame, and the rows the '
      'window takes in come a row a frame after it', (tester) async {
    await tester.pumpWidget(grid());
    await tester.pumpAndSettle();
    var laid = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is ValueListenableBuilder<int>) {
        laid += 1;
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    final before = built();
    final seen = inView();
    await wheelBy(tester, 100);
    expect(
      inView().difference(seen),
      isNotEmpty,
      reason: '⛔전제: the notch brought rows in',
    );
    expect(laid, 0, reason: 'the notch\'s own frame laid no row');
    expect(built(), before);

    final arrivals = <int>[];
    var now = before;
    for (var frame = 0; frame < 12; frame += 1) {
      await tester.pump();
      final next = built();
      arrivals.add(next.difference(now).length);
      now = next;
    }
    debugOnRebuildDirtyWidget = null;
    expect(
      arrivals.every((count) => count <= 1),
      isTrue,
      reason: 'a row a frame: $arrivals',
    );
    expect(
      arrivals.where((count) => count == 1).length,
      greaterThan(1),
      reason: 'taken in over the frames after the notch: $arrivals',
    );
    expect(
      builtBelow(tester).length,
      greaterThanOrEqualTo(3),
      reason: 'and the window is a notch past the view again',
    );
  });

  testWidgets('sub-row movement re-windows nothing at all', (tester) async {
    await tester.pumpWidget(grid());
    await tester.pumpAndSettle();

    final before = scrollArea(tester);
    // A third of a row: the window's notch past the view absorbs it, so not
    // even the token should move.
    await wheelBy(tester, timelineLayerRowHeight / 3);

    expect(identical(scrollArea(tester), before), isTrue);
    expect(
      find.text('L0').evaluate().isNotEmpty,
      isTrue,
      reason: 'and the same rows are still the ones built',
    );
  });
}
