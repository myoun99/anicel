import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';
import 'package:anicel/src/ui/home_page.dart';

import 'timeline_cell_probe.dart';

/// F-3 (first half) and F-7 — **one boundary, one line, one colour.**
///
/// Two different failures of the same law. The grid overlay sits UNDER the
/// rows (D32), so a row that paints owes the grid a redraw; the debt is only
/// settled if the row OCCLUDES first. And the row seam is not part of the
/// frame grid at all — it is the layer area's divider continued into the
/// cells, so it does not take the grid's ground treatment.
void main() {
  const trackId = TrackId('grid-once-track');
  const drawingId = LayerId('grid-once-draw');

  Project project() => Project(
    id: const ProjectId('grid-once'),
    name: 'Grid once',
    createdAt: DateTime.utc(2026, 8, 25),
    tracks: [
      Track(
        id: trackId,
        name: 'V',
        cuts: [
          Cut(
            id: const CutId('c'),
            name: '1',
            duration: 12,
            canvasSize: const CanvasSize(width: 64, height: 64),
            layers: [
              Layer(
                id: drawingId,
                name: 'A',
                frames: [
                  Frame(
                    id: const FrameId('cel'),
                    duration: 4,
                    strokes: const [],
                  ),
                ],
                timeline: const {
                  1: TimelineExposure.drawing(FrameId('cel'), length: 4),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );

  group('F-3: the row seam is the LAYER AREA\'s divider, flat', () {
    testWidgets('the same colour inside a block and on empty space', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: project())),
      );
      await tester.pumpAndSettle();

      final painter = timelineRowCellsPainterFor(tester, drawingId.value);
      final expected = timelineGridRowSeamInk(painter.colorScheme).color;

      // Frame 2 is inside the block (its paper is the layer's colour mark);
      // frame 8 is empty space (the row's own ground). The FRAME grid line
      // deliberately differs between those two — the seam must not.
      final insideBlock = painter.rowSeamLineFor(2)!;
      final onEmpty = painter.rowSeamLineFor(8)!;

      expect(
        insideBlock.color,
        expected,
        reason: 'the rail draws this divider flat over whatever ground the '
            'row happens to have; multiplying it here is what made the same '
            'line read darker on the frame side',
      );
      expect(onEmpty.color, expected);
      expect(insideBlock.color, onEmpty.color);
    });

    testWidgets('while the FRAME boundary line still takes the ground', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: HomePage(initialProject: project())),
      );
      await tester.pumpAndSettle();

      final painter = timelineRowCellsPainterFor(tester, drawingId.value);
      expect(
        painter.heldSeamLineFor(2)!.color,
        isNot(painter.heldSeamLineFor(8)!.color),
        reason: '「세로나 그 외는 그대로」 — the frame grid rules the paper it '
            'crosses, so it must keep darkening it. If this ever goes equal, '
            'the seam fix has been over-applied to the wrong line',
      );
    });
  });

  group('F-7: a washed row occludes before it redraws', () {
    testWidgets('the fx band paints an OPAQUE ground, not a 60% wash', (
      tester,
    ) async {
      final layer = Layer(
        id: const LayerId('fx'),
        name: 'FX',
        frames: const [],
      );
      const host = Color(0xFF101214);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimelineGridLaw(
              ground: host,
              framesPerSecond: 24,
              child: SizedBox(
                width: 600,
                height: 40,
                child: TimelineLaneFrameRow(
                  layer: layer,
                  lane: const PropertyLaneRow(
                    laneId: 'position',
                    label: 'Position',
                    keyedFrames: {},
                  ),
                  frameStartIndex: 0,
                  frameEndIndexExclusive: 12,
                  leadingFrameSpacerWidth: 0,
                  trailingFrameSpacerWidth: 0,
                  metrics: const TimelineGridMetrics(
                    frameCellWidth: 24,
                    layerRowHeight: 28,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final grid = find.byKey(
        const ValueKey<String>('timeline-lane-grid-fx-position'),
      );
      expect(grid, findsOneWidget, reason: 'the band draws the law itself');

      final decorated = tester.widget<DecoratedBox>(
        find.ancestor(of: grid, matching: find.byType(DecoratedBox)).first,
      );
      final color = (decorated.decoration as BoxDecoration).color!;

      expect(
        color.a,
        1.0,
        reason: 'a 60% wash DIMS the buried overlay instead of covering it, '
            'so the band\'s own redraw lands as a second line on the same '
            'boundary — which is the thick line that was reported',
      );
      expect(
        color,
        Color.alphaBlend(
          AppColors.washDown.withValues(alpha: 0.6),
          host,
        ),
        reason: 'and it is the SAME colour on screen: the wash composited '
            'onto the host, not a new one',
      );
    });
  });
}
