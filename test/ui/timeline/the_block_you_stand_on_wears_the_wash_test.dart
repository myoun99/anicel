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
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cursor_layer.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';

/// 🗣️F-248 (유저 2026-09-30 「선택되있는 블럭 다시 표시하게하고싶음. 우선
/// 외곽라인말고 블럭을 바탕색으로서 강조색 표시. 전처럼 연하게」, 10-01 「재생헤드가
/// 선 블록」): THE BLOCK YOU STAND ON WEARS THE WASH.
///
/// The unit is what a click on the playhead's cell selects — its block, or
/// the one cell (F-175) — on the row you stand on, as the rows below show
/// it through a drag. One cursor layer carries it for the timeline, the
/// x-sheet and the folded row.
void main() {
  const metrics = TimelineGridMetrics.defaults;

  Layer drawn(String id, Map<int, int> blocks) => Layer(
    id: LayerId(id),
    name: id,
    frames: [
      for (final start in blocks.keys)
        Frame(id: FrameId('$id$start'), duration: 1, strokes: const []),
    ],
    timeline: {
      for (final MapEntry(key: start, value: length) in blocks.entries)
        start: TimelineExposure.drawing(FrameId('$id$start'), length: length),
    },
  );
  // [0,6) · [6,12) · two empty cells · [14,20).
  final layer = drawn('a', {0: 6, 6: 6, 14: 6});
  final rows = [
    TimelineDisplayRow.layer(layer, layerIndex: 0),
    TimelineDisplayRow.lane(
      layer,
      const PropertyLaneRow(
        laneId: 'position',
        label: 'Position',
        keyedFrames: {},
      ),
      layerIndex: 0,
    ),
  ];

  Future<void> pump(
    WidgetTester tester, {
    required int frame,
    TimelineRowAddress? standing,
    TimelineDragPreview? preview,
    Axis axis = Axis.horizontal,
    int windowStart = 0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 800,
            child: Stack(
              fit: StackFit.expand,
              children: [
                TimelineCursorLayer(
                  frameCursor: ValueNotifier<int>(frame),
                  rows: rows,
                  activeLayerId: const LayerId('a'),
                  currentRow: ValueNotifier<TimelineRowAddress?>(standing),
                  dragPreview: ValueNotifier<TimelineDragPreview?>(preview),
                  frameStartIndex: windowStart,
                  frameEndIndexExclusive: 30,
                  leadingFrameSpacerWidth: 0,
                  metrics: metrics,
                  crossAxisExtent: 2 * metrics.layerRowHeight,
                  axis: axis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  final wash = find.byKey(const ValueKey<String>('timeline-standing-wash'));

  /// The frames and the row the wash covers, read off its rect.
  ({int start, int end, int row}) washed(
    WidgetTester tester, {
    Axis axis = Axis.horizontal,
    int windowStart = 0,
  }) {
    final origin = tester.getTopLeft(find.byType(TimelineCursorLayer));
    final rect = tester.getRect(wash).shift(-origin);
    final (alongStart, alongEnd, across) = axis == Axis.horizontal
        ? (rect.left, rect.right, rect.top)
        : (rect.top, rect.bottom, rect.left);
    int frameAt(double along) =>
        windowStart + (along / metrics.frameCellWidth).round();
    return (
      start: frameAt(alongStart),
      end: frameAt(alongEnd),
      row: (across / metrics.layerRowHeight).round(),
    );
  }

  testWidgets('on a block, the block — a fill and no line', (tester) async {
    await pump(tester, frame: 8);
    expect(washed(tester), (start: 6, end: 12, row: 0));
    final decoration =
        tester.widget<DecoratedBox>(wash).decoration as BoxDecoration;
    expect(decoration.color, timelineStandingWashColor);
    expect(decoration.border, isNull);
  });

  testWidgets('on an empty cell, that one cell (F-175)', (tester) async {
    await pump(tester, frame: 12);
    expect(washed(tester), (start: 12, end: 13, row: 0));
  });

  testWidgets('standing on a lane, the lane\'s cell — and the layer row '
      'wears none', (tester) async {
    await pump(
      tester,
      frame: 8,
      standing: const LaneRowAddress(LayerId('a'), 'position'),
    );
    expect(wash, findsOneWidget);
    expect(washed(tester), (start: 8, end: 9, row: 1));
  });

  testWidgets('through a drag, the row as it is previewed (H12) — and only '
      'its own row\'s preview', (tester) async {
    await pump(
      tester,
      frame: 8,
      preview: ExposureEdgeDragPreview(
        previewLayer: drawn('a', {0: 6, 6: 8, 14: 6}),
      ),
    );
    expect(washed(tester), (start: 6, end: 14, row: 0));

    await pump(
      tester,
      frame: 8,
      preview: ExposureEdgeDragPreview(previewLayer: drawn('b', {0: 20})),
    );
    expect(washed(tester), (start: 6, end: 12, row: 0));
  });

  testWidgets('the x-sheet turns it', (tester) async {
    await pump(tester, frame: 8, axis: Axis.vertical);
    expect(washed(tester, axis: Axis.vertical), (start: 6, end: 12, row: 0));
  });

  testWidgets('scrolled out, it stays while its block reaches into the '
      'window, and goes when it does not', (tester) async {
    await pump(tester, frame: 8, windowStart: 10);
    expect(
      find.byKey(const ValueKey<String>('timeline-playhead')),
      findsNothing,
      reason: 'premise: the playhead is out of the window',
    );
    expect(washed(tester, windowStart: 10), (start: 6, end: 12, row: 0));

    await pump(tester, frame: 2, windowStart: 10);
    expect(wash, findsNothing);
  });

  // The grids hand the layer the preview their rows show.
  group('in the app, through a comma drag', () {
    Project project() => Project(
      id: const ProjectId('standing-wash'),
      name: 'Standing wash',
      createdAt: DateTime.utc(2026, 10, 1),
      tracks: [
        Track(
          id: const TrackId('t'),
          name: 'Video',
          cuts: [
            Cut(
              id: const CutId('cut-0'),
              name: 'cut-0',
              duration: 48,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: [drawn('a', {0: 6, 6: 6}), drawn('b', {0: 6, 6: 6})],
            ),
          ],
        ),
      ],
    );

    for (final sheet in [false, true]) {
      testWidgets('the wash rides it${sheet ? ' (x-sheet)' : ''}', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(1600, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: HomePage(initialProject: project()),
          ),
        );
        await tester.pumpAndSettle();
        if (sheet) {
          await tester.tap(
            find.byKey(
              const ValueKey<String>('timeline-orientation-toggle-button'),
            ),
          );
          await tester.pumpAndSettle();
        }
        final session = tester
            .widget<EditorWorkspace>(find.byType(EditorWorkspace))
            .session;
        // The first block: the x-sheet's short panel shows four frames.
        session.selectLayer(const LayerId('b'));
        session.selectFrameIndex(1);
        await tester.pumpAndSettle();
        double along() {
          final rect = tester.getRect(wash);
          return sheet ? rect.height : rect.width;
        }

        final standing = along();
        expect(
          session.edgeDrag.beginExposureEdgeDrag(
            layerId: const LayerId('b'),
            blockStartIndex: 0,
            edge: TimelineBlockEdge.end,
          ),
          isTrue,
          reason: 'premise: the block is there to grab',
        );
        session.edgeDrag.updateExposureEdgeDrag(2);
        await tester.pump();
        expect(along() / standing, moreOrLessEquals(8 / 6));

        session.edgeDrag.cancelExposureEdgeDrag();
        await tester.pumpAndSettle();
      });
    }
  });
}
