import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/exposure_instruction.dart';
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
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';
import 'package:anicel/src/ui/timeline/timeline_row_run_labels_painter.dart';

import '../storyboard_cut_block_probe.dart';
import 'timeline_frame_geometry_probe.dart';

/// 🗣️F-228 (유저 2026-09-29): 「디렉션레이어나 트랜지션레이어만 코마텍스트가
/// 없는데, 블록이라면 전부 코마텍스트가 존재해야함. 통일해서 적용」.
void main() {
  TimelineCellExposureState stateFor(Layer layer, int frameIndex) =>
      TimelineCellExposureState.uncovered;

  Future<TimelineRowRunLabelsPainter?> mount(
    WidgetTester tester,
    Layer layer,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Material(
            child: TimelineFrameCellsRow(
              layer: layer,
              playbackFrameCount: 12,
              geometry: testFrameGeometry(
                frameCellExtent: 48,
                frameEndIndexExclusive: 12,
              ),
              crossAxisExtent: 52,
              exposureStateForLayer: stateFor,
              onSelectLayer: (_) {},
              onSelectFrame: (_) {},
            ),
          ),
        ),
      ),
    );
    return tester
            .widget<CustomPaint>(
              find.byKey(ValueKey<String>('timeline-row-cells-${layer.id}')),
            )
            .foregroundPainter
        as TimelineRowRunLabelsPainter?;
  }

  List<(int, String)> labelsOf(TimelineRowRunLabelsPainter? painter) => [
    for (final label in painter!.runLabels()) (label.startIndex, label.text),
  ];

  testWidgets('🚨a DIRECTION block prints its length', (tester) async {
    final painter = await mount(
      tester,
      Layer(
        id: const LayerId('d-1'),
        name: 'D',
        kind: LayerKind.instruction,
        frames: const [],
        timeline: {
          0: const TimelineExposure.drawing(
            FrameId('d-f1'),
            length: 3,
            instruction: ExposureInstruction(instructionId: 'pan'),
          ),
          5: const TimelineExposure.drawing(FrameId('d-f2'), length: 4),
        },
      ),
    );

    expect(labelsOf(painter), [(0, '3'), (5, '4')]);
  });

  testWidgets('🚨a TRANSITION span prints its length', (tester) async {
    final painter = await mount(
      tester,
      Layer(
        id: const LayerId('t-1'),
        name: 'T',
        kind: LayerKind.transition,
        frames: const [],
        instructions: {
          2: const InstructionEvent(instructionId: 'ol', length: 4),
        },
      ),
    );

    expect(labelsOf(painter), [(2, '4')]);
  });

  testWidgets('the camera row keeps keys, not blocks — no lengths', (
    tester,
  ) async {
    final painter = await mount(
      tester,
      Layer(
        id: const LayerId('c-1'),
        name: 'C',
        kind: LayerKind.camera,
        frames: const [],
      ),
    );

    expect(painter, isNull);
  });

  test('every kind whose content is blocks has them — and only those', () {
    for (final kind in LayerKind.values) {
      expect(
        kind.hasBlocks,
        kind.holdsDrawings || kind.carriesInstructions,
        reason: kind.name,
      );
    }
    expect(LayerKind.instruction.hasBlocks, isTrue);
    expect(LayerKind.transition.hasBlocks, isTrue);
    expect(LayerKind.camera.hasBlocks, isFalse);
  });

  group('on the storyboard', () {
    const trackId = TrackId('koma-track');
    const seLayerId = LayerId('koma-se');

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

    Frame sound(String id, int length) =>
        Frame(id: FrameId(id), duration: length, name: id, strokes: const []);

    /// A transition span over global 2..6 and three sounds — the last one
    /// comma long, which prints nothing on any row (D23).
    Project project() => Project(
      id: const ProjectId('koma-project'),
      name: 'Koma',
      createdAt: DateTime.utc(2026, 9, 29),
      tracks: [
        Track(
          id: trackId,
          name: 'Video',
          cuts: [cut('cut-1', 10), cut('cut-2', 6)],
          transitionLayer: createTrackTransitionLayer(trackId).copyWith(
            instructions: {
              2: const InstructionEvent(instructionId: 'ol', length: 5),
            },
          ),
          seLayers: [
            Layer(
              id: seLayerId,
              name: 'S1',
              kind: LayerKind.se,
              frames: [sound('s-a', 3), sound('s-b', 4), sound('s-c', 1)],
              timeline: {
                1: const TimelineExposure.drawing(FrameId('s-a'), length: 3),
                6: const TimelineExposure.drawing(FrameId('s-b'), length: 4),
                12: const TimelineExposure.drawing(FrameId('s-c'), length: 1),
              },
            ),
          ],
        ),
      ],
    );

    Future<Track> pump(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final shown = project();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StoryboardPanel(
              project: shown,
              activeCutId: const CutId('cut-1'),
              pixelsPerFrame: 12,
              showSeconds: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return shown.tracks.single;
    }

    TimelineRowRunLabelsPainter labelsOn(WidgetTester tester, LayerId id) =>
        tester
                .widget<CustomPaint>(
                  find.byKey(ValueKey<String>('storyboard-run-labels-$id')),
                )
                .foregroundPainter!
            as TimelineRowRunLabelsPainter;

    testWidgets('🚨an S row block prints its length', (tester) async {
      await pump(tester);

      expect(labelsOf(labelsOn(tester, seLayerId)), [(1, '0+3'), (6, '0+4')]);
    });

    testWidgets('🚨a transition span prints its length', (tester) async {
      final track = await pump(tester);

      expect(labelsOf(labelsOn(tester, track.transitionLayer.id)), [
        (2, '0+5'),
      ]);
    });

    testWidgets("the numbers ride the V row's own axis, window and count", (
      tester,
    ) async {
      final track = await pump(tester);
      final cuts = cutBlocksPainter(tester);

      for (final id in [seLayerId, track.transitionLayer.id]) {
        final labels = labelsOn(tester, id);
        // The LIVE handle: a zoom step repaints the numbers through it. A
        // handle made per build would leave them where the last zoom put
        // them whenever the row's width did not change.
        expect(identical(labels.geometry, cuts.geometry), isTrue, reason: '$id');
        expect(
          identical(labels.windowBucket, cuts.windowBucket),
          isTrue,
          reason: '$id',
        );
        expect(labels.viewportMainExtent, cuts.viewportMainExtent);
        expect(labels.viewportMainExtent, greaterThan(0));
        expect(labels.showSeconds, cuts.showSeconds);
        expect(labels.countingBase, cuts.countingBase);
      }
    });
  });
}
