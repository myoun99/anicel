import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
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
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_span_layout.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';
import 'package:anicel/src/ui/timeline/timeline_span_name.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';

/// 🗣️I-73 ⑤ (유저 2026-10-08): 「이 선 중앙에 카메라 움직임에 따라 지시명도
/// 적을거거든?」 — the camera row names each move over the line between its
/// keys, as an instruction span is named over its span: 「그림은 지시 행의
/// 구간과 같은 그림」.
void main() {
  final layer = Layer(
    id: const LayerId('camera'),
    name: 'Camera',
    kind: LayerKind.camera,
    frames: const [],
  );

  CutCamera keyed(Map<int, CameraPose> poses) => CutCamera(keyframes: poses);

  CameraPose at(double x, {double zoom = 1}) =>
      CameraPose(center: CanvasPoint(x: x, y: 0), zoom: zoom);

  group('the camera\'s lane', () {
    test('carries each move over its stretch, in the vocabulary\'s name and '
        'the term\'s ink', () {
      const tinted = CameraInstructionDef(
        id: 'tu',
        name: 'TRACK UP',
        iconKey: 'track-up',
        colorValue: 0xFF3366CC,
      );
      final lane = cameraUnionHeader(
        keyed({0: at(0), 6: at(0, zoom: 2), 10: at(0, zoom: 2)}).track,
        defById: (id) => id == 'tu' ? tinted : null,
      );

      expect(lane.stretchWords, hasLength(1), reason: '6 → 10 does not move');
      final word = lane.stretchWords.single;
      expect((word.from, word.to, word.word), (0, 6, 'TRACK UP'));
    });

    // 🗣️I-89 (유저 2026-10-10): 「그리고 회전은 모아트기준대로 하자」.
    test('a turn is written 回転, before the move it rides with', () {
      final lane = cameraUnionHeader(
        keyed({
          0: at(0),
          4: CameraPose(center: CanvasPoint(x: 0, y: 0), rotationDegrees: 30),
          8: CameraPose(
            center: CanvasPoint(x: 0, y: 0),
            zoom: 0.5,
            rotationDegrees: 60,
          ),
        }).track,
        defById: CameraInstructionSet.standard.defById,
      );

      expect([for (final word in lane.stretchWords) word.word], [
        '回転',
        '回転 T.B',
      ]);
    });

    test('a term the vocabulary has lost is written by its id', () {
      final lane = cameraUnionHeader(
        keyed({0: at(0), 4: at(9)}).track,
        defById: (_) => null,
      );

      expect(lane.stretchWords.single.word, 'pan');
    });

    testWidgets('its word rides a span from the first key\'s cell through the '
        'next\'s, between the line and the marks', (tester) async {
      final spans = timelineUnionKeyMarkerSpans(
        keyPrefix: 'timeline',
        layer: layer,
        lane: cameraUnionHeader(
          keyed({2: at(0), 8: at(30)}).track,
          defById: CameraInstructionSet.standard.defById,
        ),
        crossExtent: 28,
        axis: Axis.horizontal,
      ).cast<TimelineFrameSpan>();

      expect(spans, hasLength(4), reason: 'the line, the word, two marks');
      expect(spans[0].child, isA<TimelineLaneKeysLine>());
      final word = spans[1];
      expect(
        word.placement,
        const TimelineFrameSpanPlacement(startIndex: 2, endIndexExclusive: 9),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              for (final span in spans.take(2))
                SizedBox(width: 168, height: 28, child: span.child),
            ],
          ),
        ),
      );
      final name = tester.widget<TimelineSpanName>(
        find.byType(TimelineSpanName),
      );
      expect((name.text, name.axis), ('PAN', Axis.horizontal));
      // In the keys' own colour, the row's colour label (유저 2026-10-12:
      // 「너무 연해서 있는지도몰랏어. 키 색(즉 색라벨 색)이랑 똑같이」).
      expect(
        find.descendant(
          of: find.byType(TimelineLaneKeysLine),
          matching: find.byType(CustomPaint),
        ),
        paints..line(color: name.ink),
      );
      final termInk = timelineInstructionInk(
        CameraInstructionSet.standard.defById('pan'),
      );
      expect(
        name.ink,
        isNot(termInk),
        reason: '⛔전제: the term\'s own ink is another colour',
      );
    });
  });

  // The row as the app mounts it.
  group('on the camera row itself', () {
    Project project() => Project(
      id: const ProjectId('camera-moves'),
      name: 'Camera moves',
      createdAt: DateTime.utc(2026, 10, 9),
      tracks: [
        Track(
          id: const TrackId('t'),
          name: 'Video',
          cuts: [
            Cut(
              id: const CutId('cut-0'),
              name: 'cut-0',
              duration: 24,
              canvasSize: const CanvasSize(width: 1280, height: 720),
              camera: keyed({2: at(640), 8: at(640, zoom: 2), 14: at(900)}),
              layers: [
                Layer(
                  id: const LayerId('drawing'),
                  name: 'Drawing',
                  frames: const [],
                ),
                layer,
              ],
            ),
          ],
        ),
      ],
    );

    for (final sheet in [false, true]) {
      testWidgets('🎯names T.U and T.B over their stretches '
          '${sheet ? 'down the x-sheet' : 'along the timeline'}', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(1280, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(home: HomePage(initialProject: project())),
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

        final names = [
          for (final element in find.byType(TimelineSpanName).evaluate())
            element.widget as TimelineSpanName,
        ];
        expect(
          {for (final name in names) name.text},
          {'T.U', 'T.B'},
          reason: '2 → 8 zooms in; 8 → 14 zooms back out as it pans',
        );
        final axis = sheet ? Axis.vertical : Axis.horizontal;
        expect({for (final name in names) name.axis}, {axis});
        expect(
          tester
              .widget<EditorWorkspace>(find.byType(EditorWorkspace))
              .session
              .activeCutOrNull
              ?.id,
          const CutId('cut-0'),
          reason: '⛔전제',
        );
      });
    }
  });
}
