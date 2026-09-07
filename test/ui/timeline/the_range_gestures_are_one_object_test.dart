import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_range_gesture.dart';
import 'package:anicel/src/ui/timeline/held_row_pin.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_range_gestures.dart';

/// The rail and the sheet hold the SAME range-gesture collaborator; the
/// only thing the rail adds is a pin for its row window. This pins what the
/// collaborator answers from the host it is handed, so neither grid can
/// fall a law behind the other again.
void main() {
  TimelineGridHooks hooks({
    TimelineFrameRangeHooks? rangeHooks,
    TimelineLaneRangeHooks? laneRange,
    int playbackFrameCount = 48,
  }) => TimelineGridHooks(
    activeLayerId: const LayerId('a'),
    frameCursor: ValueNotifier<int>(0),
    playbackFrameCount: playbackFrameCount,
    exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
    onSelectLayer: (_) {},
    onSelectFrame: (_) {},
    onToggleLayerVisibility: (_) {},
    onLayerOpacityChanged: (_, _) {},
    onToggleLayerTimesheet: (_) {},
    onLayerMarkSelected: (_, _) {},
    rangeHooks: rangeHooks,
    laneRange: laneRange,
  );

  TimelineFrameRangeHooks rangeHooks({
    ValueListenable<TimelineFrameRangeSelection?>? selection,
  }) => TimelineFrameRangeHooks(
    selection: selection ?? ValueNotifier<TimelineFrameRangeSelection?>(null),
    onSelectUpdate:
        (_, _, _, {headLayerId, headLaneId, spanRows = const []}) {},
    onClear: () {},
    move: TimelineRangeMoveCallbacks(
      onBegin: (_) => true,
      onUpdate: ({required frameDelta, targetLayerId}) {},
      onEnd: () {},
      onCancel: () {},
    ),
  );

  TimelineLaneRangeHooks laneHooks() => TimelineLaneRangeHooks(
    selection: ValueNotifier<TimelineLaneSelection?>(null),
    onSelectUpdate: (_, _, _, _, _, _) {},
    onTapAt: (_, _, _) {},
    onTapClear: () {},
    onMoveBegin: () => false,
    onMoveUpdate: (_) {},
    onMoveEnd: () {},
    onMoveCancel: () {},
  );

  List<TimelineDisplayRow> rows() => [
    TimelineDisplayRow.layer(
      Layer(id: const LayerId('a'), name: 'A', frames: const []),
      layerIndex: 0,
    ),
  ];

  test('the frame-range policy reads the host\'s playback and metrics', () {
    final gestures = TimelineGridRangeGestures(
      hooks: () => hooks(playbackFrameCount: 10),
      metrics: () => const TimelineGridMetrics(minimumVisibleFrameCells: 30),
      dragRows: rows,
      rangeMove: TimelineRangeMoveRowResolver(),
    );
    expect(gestures.frameRangePolicy.visibleFrameCount, 30);
    final longer = TimelineGridRangeGestures(
      hooks: () => hooks(playbackFrameCount: 100),
      metrics: () => const TimelineGridMetrics(minimumVisibleFrameCells: 30),
      dragRows: rows,
      rangeMove: TimelineRangeMoveRowResolver(),
    );
    expect(longer.frameRangePolicy.visibleFrameCount, 100);
  });

  test('no range hooks: no cells callbacks, but the resolver is still '
      'loaded with this pass\'s rows', () {
    final resolver = TimelineRangeMoveRowResolver();
    final gestures = TimelineGridRangeGestures(
      hooks: hooks,
      metrics: () => TimelineGridMetrics.defaults,
      dragRows: rows,
      rangeMove: resolver,
    );
    final passRows = rows();
    expect(gestures.rangeGestureFor(passRows), isNull);
    expect(resolver.rows, same(passRows));
    expect(resolver.session, isNull);
    expect(gestures.laneRangeFor(passRows), isNull);
  });

  test('range hooks wired: the cells callbacks come from the shared '
      'builder and the resolver carries the session', () {
    final resolver = TimelineRangeMoveRowResolver();
    final range = rangeHooks();
    final gestures = TimelineGridRangeGestures(
      hooks: () => hooks(rangeHooks: range, laneRange: laneHooks()),
      metrics: () => TimelineGridMetrics.defaults,
      dragRows: rows,
      rangeMove: resolver,
    );
    final callbacks = gestures.rangeGestureFor(rows());
    expect(callbacks, isNotNull);
    expect(resolver.session, same(range.move));
    expect(
      callbacks!.onMoveBegin(const LayerRowAddress(LayerId('a')), 0),
      isTrue,
    );
    expect(gestures.laneRangeFor(rows()), isNotNull);
  });

  test('a pin rides both families\' grips; no pin means no grip', () {
    final pin = HeldRowPin();
    final pinned = TimelineGridRangeGestures(
      hooks: () => hooks(rangeHooks: rangeHooks(), laneRange: laneHooks()),
      metrics: () => TimelineGridMetrics.defaults,
      dragRows: rows,
      rangeMove: TimelineRangeMoveRowResolver(),
      pin: pin,
    );
    const row = LayerRowAddress(LayerId('a'));
    const other = LayerRowAddress(LayerId('b'));
    pinned.rangeGestureFor(rows())!.onGripTaken!(row);
    expect(pin.held, row);
    pinned.laneRangeFor(rows())!.onGripTaken!(row);
    expect(pin.held, row);
    // ⛔RELEASE ONLY IF STILL MINE: a grip that has moved on must not be
    // cleared by whoever held it last.
    pinned.rangeGestureFor(rows())!.onGripReleased!(other);
    expect(pin.held, row, reason: 'another row\'s release is not mine');
    pinned.laneRangeFor(rows())!.onGripReleased!(row);
    expect(pin.held, isNull);

    final unpinned = TimelineGridRangeGestures(
      hooks: () => hooks(rangeHooks: rangeHooks(), laneRange: laneHooks()),
      metrics: () => TimelineGridMetrics.defaults,
      dragRows: rows,
      rangeMove: TimelineRangeMoveRowResolver(),
    );
    expect(unpinned.rangeGestureFor(rows())!.onGripTaken, isNull);
    expect(unpinned.rangeGestureFor(rows())!.onGripReleased, isNull);
    expect(unpinned.laneRangeFor(rows())!.onGripTaken, isNull);
    expect(unpinned.laneRangeFor(rows())!.onGripReleased, isNull);
  });
}
