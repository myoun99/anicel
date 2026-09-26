import 'package:flutter/material.dart' show Axis, Rect, TextStyle, ThemeData;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart'
    show timelineMarkGap;
import 'package:anicel/src/ui/timeline/timeline_frame_ruler_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_glyph_cache.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart'
    show XSheetFrameRailPainter;

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
    TimelineRulerScale rail(double rowExtent, {int frames = 30}) =>
        TimelineRulerScale(
          axis: Axis.vertical,
          frameStartIndex: 0,
          frameEndIndexExclusive: frames,
          currentFrameIndex: -1,
          playbackFrameCount: frames,
          leadingFrameSpacer: 0,
          crossExtent: 28,
          // frameCellWidth is the frame ROW HEIGHT in the transposed metrics.
          metrics: TimelineGridMetrics(
            frameCellWidth: rowExtent,
            layerRowHeight: 164,
          ),
          colorScheme: ThemeData.light().colorScheme,
          face: const TextStyle(),
          numberType: XSheetFrameRailPainter.numberType,
          secondsFontSize: 8,
        );

    test('a wide row labels every frame; a squeezed one climbs the '
        'paper-timesheet ladder anchored at frame 1', () {
      expect(rail(36).labelEveryFrames, 1);
      final tight = rail(6);
      expect(tight.labelEveryFrames, greaterThan(1));
      expect(tight.modelAt(0).label, '1');
    });

    test('I-22: the rail measures its numbers DOWN the rail — a row tall '
        'enough keeps its number, however wide the number is', () {
      final type = XSheetFrameRailPainter.numberType(
        rail(16),
        everyFrame: true,
      );
      final glyph = timelineGlyphPainter('00', type);
      expect(
        glyph.height + timelineMarkGap,
        lessThanOrEqualTo(16),
        reason: 'fixture: two digits stand in a 16px row',
      );
      expect(
        glyph.width + timelineMarkGap,
        greaterThan(16),
        reason: 'fixture: and would not fit one across',
      );
      expect(rail(16).labelEveryFrames, 1);
    });

    test('I-22: whatever the row, neighbouring numbers never touch', () {
      for (final row in [4.0, 6.0, 8.0, 12.0, 16.0, 24.0]) {
        final scale = rail(row, frames: 1200);
        Rect? previous;
        for (var frame = 0; frame < 240; frame += 1) {
          final number = XSheetFrameRailPainter.glyphsAt(
            scale,
            frame,
            current: false,
          ).where((glyph) => glyph.painter.plainText == '${frame + 1}');
          if (number.isEmpty) {
            continue;
          }
          final box = number.single.rect;
          if (previous != null) {
            expect(
              box.top - previous.bottom,
              greaterThanOrEqualTo(timelineMarkGap - 1e-9),
              reason: '${row}px rows: number ${frame + 1}',
            );
          }
          previous = box;
        }
      }
    });
  });
}
