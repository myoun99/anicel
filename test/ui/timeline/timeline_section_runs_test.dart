import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_section_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_section_runs.dart';

Layer _layer(String id, LayerKind kind) => Layer(
  id: LayerId(id),
  name: id,
  kind: kind,
  frames: const [],
  timeline: const {},
);

void main() {
  const metrics = TimelineGridMetrics();

  group('timelineSectionRuns', () {
    test('groups consecutive rows by section; lanes join their layer', () {
      final camera = _layer('cam', LayerKind.camera);
      final rows = buildTimelineDisplayRows(
        layers: [
          _layer('cel-a', LayerKind.animation),
          _layer('se-1', LayerKind.se),
          _layer('se-2', LayerKind.se),
          camera,
        ],
        expandedLayerIds: {camera.id},
        lanesForLayer: (layer) => layer.kind == LayerKind.camera
            ? const [
                PropertyLaneRow(
                  laneId: 'position',
                  label: 'Position',
                  keyedFrames: {},
                ),
              ]
            : const [],
      );

      final runs = timelineSectionRuns(rows);

      expect(runs, [
        const TimelineSectionRun(
          section: TimelineSection.drawing,
          startRowIndex: 0,
          rowCount: 1,
        ),
        const TimelineSectionRun(
          section: TimelineSection.se,
          startRowIndex: 1,
          rowCount: 2,
        ),
        // Camera layer row + its expanded lane row.
        const TimelineSectionRun(
          section: TimelineSection.camera,
          startRowIndex: 3,
          rowCount: 2,
        ),
      ]);
    });

    test('a hidden section contributes no rows and no run at all', () {
      final rows = buildTimelineDisplayRows(
        layers: [
          _layer('cel-a', LayerKind.animation),
          _layer('se-1', LayerKind.se),
          _layer('cam', LayerKind.camera),
        ],
        expandedLayerIds: const {},
        lanesForLayer: (_) => const [],
        hiddenSections: const {TimelineSection.se},
      );

      final runs = timelineSectionRuns(rows);

      expect(rows, hasLength(2));
      expect(runs.map((run) => run.section), [
        TimelineSection.drawing,
        TimelineSection.camera,
      ]);
      expect(
        timelineDisplayRowsExtent(rows, metrics),
        metrics.layerRowHeight * 2,
      );
      expect(
        timelineSectionRunExtent(runs[1], rows, metrics),
        metrics.layerRowHeight,
      );
    });
  });
}
