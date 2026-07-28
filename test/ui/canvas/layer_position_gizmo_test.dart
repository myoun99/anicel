import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/canvas/layer_position_gizmo.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart';

const _gizmoKey = ValueKey<String>('layer-position-gizmo');

void main() {
  group('transformTrackWithPositionDragged', () {
    test('keys the dragged position at the playhead, preserving an '
        'existing key\'s interpolation', () {
      final track = TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>().withKey(
          0,
          CanvasPoint(x: 1, y: 1),
          interpolation: PropertyKeyInterpolation.hold,
        ),
      );

      final dragged = transformTrackWithPositionDragged(
        track,
        frameIndex: 0,
        position: CanvasPoint(x: 9, y: 3),
      );
      expect(dragged.position.keyAt(0)!.value, CanvasPoint(x: 9, y: 3));
      expect(
        dragged.position.keyAt(0)!.interpolation,
        PropertyKeyInterpolation.hold,
      );

      final keyedFresh = transformTrackWithPositionDragged(
        TransformTrack.empty(),
        frameIndex: 4,
        position: CanvasPoint(x: 2, y: 2),
      );
      expect(keyedFresh.position.keyAt(4)!.value, CanvasPoint(x: 2, y: 2));
      expect(
        keyedFresh.position.keyAt(4)!.interpolation,
        PropertyKeyInterpolation.linear,
      );
    });
  });

  group('LayerPositionGizmo', () {
    testWidgets('dragging the handle commits ONE position in canvas '
        'coordinates (screen delta ÷ viewport zoom)', (tester) async {
      final committed = <CanvasPoint>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayerPositionGizmo(
              pose: TransformPose(center: CanvasPoint(x: 100, y: 80)),
              viewport: CanvasViewport(zoom: 2),
              onPositionCommitted: committed.add,
            ),
          ),
        ),
      );

      await tester.drag(find.byKey(_gizmoKey), const Offset(48, -20));
      await tester.pumpAndSettle();

      expect(committed, hasLength(1));
      expect(committed.single.x, closeTo(100 + 48 / 2, 0.001));
      expect(committed.single.y, closeTo(80 - 20 / 2, 0.001));
    });

    testWidgets('shows only while the active layer\'s Transform lanes are '
        'twirled open (never blocks ordinary drawing)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            initialProject: Project(
              id: const ProjectId('gizmo-project'),
              name: 'Gizmo Project',
              createdAt: DateTime.utc(2026, 7, 10),
              tracks: [
                Track(
                  id: const TrackId('gizmo-track'),
                  name: 'Video Track',
                  cuts: [
                    Cut(
                      id: const CutId('gizmo-cut'),
                      name: 'Gizmo Cut',
                      duration: 12,
                      canvasSize: const CanvasSize(width: 1280, height: 720),
                      layers: [
                        Layer(
                          id: const LayerId('gizmo-draw'),
                          name: 'Drawing',
                          frames: const [],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_gizmoKey), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-lane-toggle-gizmo-draw')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_gizmoKey), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-lane-toggle-gizmo-draw')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_gizmoKey), findsNothing);
    });
  });
}
