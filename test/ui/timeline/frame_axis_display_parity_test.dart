import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';

/// R9 P4 — the frame axis reads the same on every surface.
///
/// `#24`/`#23`: ONE rule for lane placement — further from the layer means
/// applied LATER. `#4`: the x-sheet rail thins its numbers on the shared
/// ladder instead of crowding them (the badge's own move is in
/// `timeline_run_duration_labels_test.dart`).
void main() {
  group('#23/#24 — lane direction is one rule', () {
    final owner = Layer(
      id: const LayerId('owner'),
      name: 'A',
      frames: const [],
      kind: LayerKind.animation,
    );

    List<PropertyLaneRow> lanes(Layer layer) => const [
      PropertyLaneRow(laneId: 'fx-blur', label: 'Blur', keyedFrames: {}),
      PropertyLaneRow(
        laneId: 'transform-position',
        label: 'Position',
        keyedFrames: {},
      ),
    ];

    String nameOf(TimelineDisplayRow row) =>
        row.isLane ? row.lane!.laneId : row.layer.name;

    test('the horizontal axis puts the lanes AFTER the layer, in pipeline '
        'order — the last-applied reads at the bottom', () {
      final rows = buildTimelineDisplayRows(
        layers: [owner],
        expandedLayerIds: {owner.id},
        lanesForLayer: lanes,
      );

      expect(rows.map(nameOf), ['A', 'fx-blur', 'transform-position']);
    });

    test('the x-sheet puts the same list BEFORE the layer, reversed — the '
        'last-applied reads furthest LEFT', () {
      final rows = buildTimelineDisplayRows(
        layers: [owner],
        expandedLayerIds: {owner.id},
        lanesForLayer: lanes,
        lanesPrecedeLayer: true,
      );

      expect(rows.map(nameOf), ['transform-position', 'fx-blur', 'A']);
    });

    test('the attach group stays unsplittable: the lanes move past its '
        'START, mirroring R26 #36 pushing them past its end', () {
      final below = Layer(
        id: const LayerId('below'),
        name: 'A-below',
        frames: const [],
        kind: LayerKind.animation,
        attachedToLayerId: owner.id,
      );
      final above = Layer(
        id: const LayerId('above'),
        name: 'A-above',
        frames: const [],
        kind: LayerKind.animation,
        attachedToLayerId: owner.id,
      );
      final stack = [below, owner, above];

      final horizontal = buildTimelineDisplayRows(
        layers: stack,
        expandedLayerIds: {owner.id},
        lanesForLayer: lanes,
      );
      expect(horizontal.map(nameOf), [
        'A-below',
        'A',
        'A-above',
        'fx-blur',
        'transform-position',
      ]);

      final sheet = buildTimelineDisplayRows(
        layers: stack,
        expandedLayerIds: {owner.id},
        lanesForLayer: lanes,
        lanesPrecedeLayer: true,
      );
      expect(sheet.map(nameOf), [
        'transform-position',
        'fx-blur',
        'A-below',
        'A',
        'A-above',
      ]);
    });

    test('two expanded layers keep their own lane runs', () {
      final second = Layer(
        id: const LayerId('second'),
        name: 'B',
        frames: const [],
        kind: LayerKind.animation,
      );

      final sheet = buildTimelineDisplayRows(
        layers: [owner, second],
        expandedLayerIds: {owner.id, second.id},
        lanesForLayer: lanes,
        lanesPrecedeLayer: true,
      );

      expect(sheet.map(nameOf), [
        'transform-position',
        'fx-blur',
        'A',
        'transform-position',
        'fx-blur',
        'B',
      ]);
    });
  });

  group('#4 — the x-sheet rail thins on the shared ladder', () {
    test('a wide row labels every frame; a squeezed one climbs the '
        'paper-timesheet ladder anchored at frame 1', () {
      // frameCellWidth is the frame ROW HEIGHT in the transposed metrics.
      const wide = TimelineGridMetrics(frameCellWidth: 36, layerRowHeight: 164);
      const tight = TimelineGridMetrics(frameCellWidth: 6, layerRowHeight: 164);

      expect(wide.frameLabelEveryFrames, 1);
      expect(tight.frameLabelEveryFrames, greaterThan(1));
      expect(
        (tight.frameLabelEveryFrames * 6).toDouble(),
        greaterThanOrEqualTo(40),
        reason: 'the ladder guarantees room for the glyph',
      );
    });
  });
}
