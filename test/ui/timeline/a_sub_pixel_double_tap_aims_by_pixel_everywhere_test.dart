import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_section_defaults.dart'
    show createTrackTransitionLayer;
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart'
    show TimelineLaneSelection;
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_double_tap.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_range_gesture.dart';

/// 🗣️유저 2026-09-26 (zoom-floor-fixed-marks-Q2, 「1px 보다 좁은 칸은 같은
/// 픽셀이면 같은 칸」) on every surface that mounts the double-tap gate —
/// the rows have their own pin beside the gate's; these are the lane bands
/// and the storyboard's transition and SE rows.
void main() {
  const eighth = 1 / 8;

  setUp(TimelineDoubleTapGate.reset);

  Future<void> doubleTapAt(
    WidgetTester tester,
    Offset origin,
    double first,
    double second,
  ) async {
    await tester.tapAt(origin + Offset(first, 12));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(origin + Offset(second, 12));
    await tester.pump(const Duration(milliseconds: 700));
  }

  group('a lane band', () {
    Future<List<int>> activationsAt(
      WidgetTester tester,
      double first,
      double second,
    ) async {
      final activations = <int>[];
      final selection = ValueNotifier<TimelineLaneSelection?>(null);
      addTearDown(selection.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                height: 24,
                // The band lays itself out as a row's Positioned layer.
                child: Stack(
                  children: [
                    TimelineLaneRangeGestureLayer(
                      layer: Layer(
                        id: const LayerId('lane-owner'),
                        name: 'A',
                        frames: const [],
                        timeline: const {},
                      ),
                      laneId: 'position',
                      frameStartIndex: 0,
                      leadingFrameSpacerWidth: 0,
                      frameCellExtent: eighth,
                      crossAxisExtent: 24,
                      callbacks: TimelineLaneRangeCallbacks(
                        selection: selection,
                        onSelectUpdate: (_, _, _, _, _) {},
                        onTapAt: (_, _, _) {},
                        onTapClear: () {},
                        onMoveBegin: () => false,
                        onMoveUpdate: (_) {},
                        onMoveEnd: () {},
                        onMoveCancel: () {},
                        onActivateAt: (_, _, frame) => activations.add(frame),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await doubleTapAt(tester, Offset.zero, first, second);
      return activations;
    }

    testWidgets('two taps in one pixel open that pixel\'s cell', (
      tester,
    ) async {
      expect(await activationsAt(tester, 100.1, 100.8), <int>[804]);
    });

    testWidgets('two taps a pixel apart are two cells', (tester) async {
      expect(await activationsAt(tester, 100.8, 101.2), isEmpty);
    });
  });

  group('the storyboard\'s transition row', () {
    const trackId = TrackId('t');

    Cut cut(String id, int duration) => Cut(
      id: CutId(id),
      name: id,
      duration: duration,
      canvasSize: const CanvasSize(width: 640, height: 360),
      layers: const [],
    );

    Future<List<int>> editsAt(
      WidgetTester tester,
      double first,
      double second,
    ) async {
      final edits = <int>[];
      await tester.binding.setSurfaceSize(const Size(1200, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StoryboardPanel(
              project: Project(
                id: const ProjectId('p'),
                name: 'P',
                createdAt: DateTime.utc(2026, 9, 26),
                tracks: [
                  Track(
                    id: trackId,
                    name: 'V',
                    cuts: [cut('C1', 400), cut('C2', 100)],
                    // One span over the first 400 frames: fifty pixels.
                    transitionLayer: createTrackTransitionLayer(trackId)
                        .copyWith(
                          instructions: {
                            0: const InstructionEvent(
                              instructionId: 'ol',
                              length: 400,
                            ),
                          },
                        ),
                  ),
                ],
              ),
              activeCutId: const CutId('C1'),
              pixelsPerFrame: eighth,
              thumbnails: null,
              onEditTransitionSpan: edits.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(
        ValueKey<String>('storyboard-transition-row-${trackId.value}'),
      );
      expect(row, findsOneWidget, reason: 'the premise: the row is there');
      await doubleTapAt(tester, tester.getTopLeft(row), first, second);
      return edits;
    }

    testWidgets('two taps in one pixel open the span there', (tester) async {
      // 20.1 and 20.8 are frames 160 and 166; the pixel's middle is 164.
      expect(await editsAt(tester, 20.1, 20.8), <int>[164]);
    });

    testWidgets('two taps a pixel apart are two seeks', (tester) async {
      expect(await editsAt(tester, 20.8, 21.2), isEmpty);
    });
  });

  group('the storyboard\'s SE row', () {
    const trackId = TrackId('t');
    const soundRow = LayerId('se');

    Future<List<int>> editsAt(
      WidgetTester tester,
      double first,
      double second,
    ) async {
      final edits = <int>[];
      await tester.binding.setSurfaceSize(const Size(1200, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StoryboardPanel(
              project: Project(
                id: const ProjectId('p'),
                name: 'P',
                createdAt: DateTime.utc(2026, 9, 26),
                tracks: [
                  Track(
                    id: trackId,
                    name: 'V',
                    cuts: [
                      Cut(
                        id: const CutId('C1'),
                        name: 'C1',
                        duration: 500,
                        canvasSize: const CanvasSize(width: 640, height: 360),
                        layers: const [],
                      ),
                    ],
                    // One sound over the first 400 frames: fifty pixels.
                    seLayers: [
                      Layer(
                        id: soundRow,
                        name: 'S1',
                        kind: LayerKind.se,
                        frames: [
                          Frame(
                            id: const FrameId('bang'),
                            duration: 400,
                            name: 'Bang',
                            strokes: const [],
                          ),
                        ],
                        timeline: {
                          0: const TimelineExposure.drawing(
                            FrameId('bang'),
                            length: 400,
                          ),
                        },
                      ),
                    ],
                  ),
                ],
              ),
              activeCutId: const CutId('C1'),
              pixelsPerFrame: eighth,
              thumbnails: null,
              onEditSeEntry: (_, frame) => edits.add(frame),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey<String>('storyboard-se-row-0-1'));
      expect(row, findsOneWidget, reason: 'the premise: the row is there');
      await doubleTapAt(tester, tester.getTopLeft(row), first, second);
      return edits;
    }

    testWidgets('two taps in one pixel open the sound there', (tester) async {
      expect(await editsAt(tester, 20.1, 20.8), <int>[164]);
    });

    testWidgets('two taps a pixel apart are two seeks', (tester) async {
      expect(await editsAt(tester, 20.8, 21.2), isEmpty);
    });
  });
}
