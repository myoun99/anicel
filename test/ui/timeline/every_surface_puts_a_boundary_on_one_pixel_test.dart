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
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_coordinate_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_playhead.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../storyboard_cut_block_probe.dart';
import 'timeline_frame_geometry_probe.dart';

/// 🗣️F-220 (유저 2026-09-29): the zoom follows every percent, so a cell is
/// seldom a whole number of pixels — and every surface must still put a
/// boundary on the SAME whole pixel, or a line and the block beside it part
/// by a pixel. The source scan holds the code to the one law
/// (`test/architecture/the_frame_axis_has_one_law_test.dart`); this holds
/// what the surfaces draw, at a zoom a product of frames and cell would get
/// wrong.
void main() {
  const cell = 7.3;
  double edge(int frame) => timelineFrameEdge(frame, cell);

  test('a row\'s cells tile the axis on the law\'s whole pixels', () {
    final painter = TimelineRowCellsPainter(
      layer: Layer(
        id: const LayerId('edge-a'),
        name: 'A',
        frames: [
          Frame(id: const FrameId('f'), duration: 1, strokes: const []),
        ],
        timeline: {0: const TimelineExposure.drawing(FrameId('f'), length: 30)},
      ),
      geometry: testFrameGeometry(
        frameCellExtent: cell,
        frameEndIndexExclusive: 40,
      ),
      crossAxisExtent: 28,
      exposureStateForLayer: (_, _) => TimelineCellExposureState.held,
      colorScheme: const ColorScheme.dark(),
      baseTextStyle: const TextStyle(fontSize: 11),
      substrateGeneration: 'g1',
    );
    for (var frame = 0; frame < 39; frame += 1) {
      final rect = painter.cellRectFor(frame);
      expect(rect.left, edge(frame), reason: 'frame $frame');
      expect(rect.right, edge(frame + 1), reason: 'frame $frame');
      expect(
        painter.frameIndexAt(Offset(rect.left, 1)),
        frame,
        reason: 'a press on the cell\'s first pixel is that cell',
      );
    }
  });

  test('the grid sheet rules each boundary on the law\'s pixel', () {
    final lines = _Lines();
    TimelineGridSheetPainter(
      frameCellExtent: cell,
      framesPerSecond: 24,
      colorScheme: const ColorScheme.dark(),
      ground: null,
    ).paint(lines, const Size(cell * 60, 30));
    expect(lines.alongs, isNotEmpty, reason: 'fixture: the sheet rules');
    for (final along in lines.alongs) {
      final boundary = along - timelineGridLineSnap;
      expect(boundary, boundary.roundToDouble(), reason: 'at $along');
      expect(
        timelineFrameAt(boundary, cell),
        predicate<int>((frame) => edge(frame) == boundary),
        reason: 'a line at $along stands on a boundary the law puts there',
      );
    }
  });

  testWidgets('the playhead\'s column is the playhead cell', (tester) async {
    for (final frame in [0, 1, 7, 13, 29]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: TimelinePlayhead(
            currentFrameIndex: frame,
            frameStartIndex: 0,
            frameEndIndexExclusive: 40,
            leadingFrameSpacerWidth: 0,
            metrics: const TimelineGridMetrics(frameCellWidth: cell),
            layerCount: 1,
            crossAxisExtent: 40,
          ),
        ),
      );
      final column = tester.getRect(
        find.byKey(const ValueKey<String>('timeline-playhead-column')),
      );
      expect(column.left, edge(frame), reason: 'frame $frame');
      expect(column.right, edge(frame + 1), reason: 'frame $frame');
    }
  });

  testWidgets('the storyboard\'s cut blocks start and end on the law\'s '
      'pixels', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Cut cut(String id, int duration) => Cut(
      id: CutId(id),
      name: id,
      duration: duration,
      canvasSize: const CanvasSize(width: 640, height: 360),
      layers: [
        Layer(
          id: LayerId('$id-cel'),
          name: 'A',
          frames: const [],
          timeline: const {},
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoryboardPanel(
            project: Project(
              id: const ProjectId('edges'),
              name: 'Edges',
              createdAt: DateTime.utc(2026, 9, 29),
              tracks: [
                Track(
                  id: const TrackId('edge-track'),
                  name: 'Video',
                  cuts: [cut('cut-1', 17), cut('cut-2', 23), cut('cut-3', 31)],
                ),
              ],
            ),
            activeCutId: const CutId('cut-1'),
            pixelsPerFrame: cell,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var start = 0;
    for (final (id, duration) in [('cut-1', 17), ('cut-2', 23), ('cut-3', 31)]) {
      final block = requireCutBlock(tester, id);
      expect(block.rect.left, edge(start), reason: '$id starts');
      expect(block.rect.right, edge(start + duration), reason: '$id ends');
      start += duration;
    }
  });
}

class _Lines implements Canvas {
  final alongs = <double>[];

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => alongs.add(p1.dx);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
