import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';

import '../../helpers/timeline_host.dart';

/// 🗣️F-541 (유저 2026-11-02): 「콘티패널에서 컷크기 줄일때 카메라레이어의 키
/// 줄이는거 라이브로 따라가는데, 타임라인패널만 안따라감. 법 통일」 — a cut's
/// end carries its camera's keys under the hand, and the timeline's camera
/// row shows them there. The conte's rows listen to the track itself; the
/// timeline's stand on a gate no length change tripped, so its marks sat
/// where they were until the release.
void main() {
  const cut = CutId('a');
  const camera = LayerId('a-cam');

  Project project() => Project(
    id: const ProjectId('live'),
    name: 'Live',
    createdAt: DateTime.utc(2026, 11, 2),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'V',
        cuts: [
          Cut(
            id: cut,
            name: 'a',
            duration: 24,
            canvasSize: const CanvasSize(width: 640, height: 360),
            camera: CutCamera(
              keyframes: {
                for (final frame in const [0, 12, 23])
                  frame: CameraPose(
                    center: CanvasPoint(x: 320.0 + frame, y: 180),
                  ),
              },
            ),
            layers: [
              Layer(id: const LayerId('a-cel'), name: 'A', frames: const []),
              Layer(
                id: camera,
                name: 'Camera',
                kind: LayerKind.camera,
                frames: const [],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  Finder markOn(String prefix, int frame) => find.byKey(
    ValueKey<String>(
      '$prefix-lane-key-${camera.value}-'
      '${transformGroupHeaderLane.laneId}-$frame',
    ),
  );

  void begin(EditorSessionManager session) => expect(
    session.edgeDrag.beginCutEdgeDrag(
      cutId: cut,
      edge: TimelineBlockEdge.end,
    ),
    isTrue,
    reason: '⛔전제',
  );

  group('the camera row\'s gate', () {
    final row = Layer(
      id: camera,
      name: 'Camera',
      kind: LayerKind.camera,
      frames: const [],
    );
    final drawing = Layer(
      id: const LayerId('a-cel'),
      name: 'A',
      frames: const [],
    );
    final transition = Layer(
      id: const LayerId('o-l'),
      name: 'O.L',
      frames: const [],
    );
    final carrying = {cut: CutCamera.empty()};

    test('a length change carrying a camera trips it, afresh at every step, '
        'and no other row\'s', () {
      for (final preview in <TimelineDragPreview>[
        CutTrimDragPreview(
          previewDurations: const {},
          previewCameras: carrying,
        ),
        ExposureEdgeDragPreview(
          previewLayer: transition,
          previewCameras: carrying,
        ),
      ]) {
        final shown = timelineRowPreviewLayer(preview, row);
        expect(shown, isNotNull, reason: '${preview.runtimeType}');
        expect(
          identical(shown, timelineRowPreviewLayer(preview, row)),
          isFalse,
        );
        expect(timelineRowPreviewLayer(preview, drawing), isNull);
      }
    });

    test('one that carries none leaves it', () {
      for (final preview in <TimelineDragPreview?>[
        null,
        const CutTrimDragPreview(previewDurations: {}),
        ExposureEdgeDragPreview(previewLayer: transition),
      ]) {
        expect(timelineRowPreviewLayer(preview, row), isNull);
      }
    });
  });

  for (final (orientation, prefix) in const [
    (TimelineOrientation.horizontal, 'timeline'),
    (TimelineOrientation.vertical, 'xsheet'),
  ]) {
    group('on the ${orientation.name} grid', () {
      testWidgets('🎯the camera row\'s marks follow the cut\'s end under the '
          'hand, and a cancel puts them back', (tester) async {
        final session = await pumpTimelineHost(
          tester,
          project(),
          orientation: orientation,
          surface: const Size(1400, 1400),
        );
        Finder mark(int frame) => markOn(prefix, frame);
        expect(mark(23), findsOneWidget, reason: '⛔전제');

        begin(session);
        session.edgeDrag.updateCutEdgeDrag(-6);
        await tester.pump();

        expect(mark(17), findsOneWidget, reason: 'the end key under the hand');
        expect(mark(23), findsNothing);

        session.edgeDrag.updateCutEdgeDrag(-13);
        await tester.pump();

        expect(mark(10), findsOneWidget, reason: 'the end key');
        expect(mark(9), findsOneWidget, reason: 'the key it pushed');
        expect(mark(12), findsNothing);

        session.edgeDrag.cancelCutEdgeDrag();
        await tester.pump();

        expect(mark(23), findsOneWidget);
        expect(mark(12), findsOneWidget);
        expect(mark(9), findsNothing);
      });
    });
  }
}
