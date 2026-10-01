import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/canvas/row_transform_box.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart';

/// Stands on the Transform GROUP header — the row that declares every
/// manipulator its members do (R5 #10).
///
/// The NAME, not the cell: the chevron twirls and the value cell edits, so
/// the label's text is the part of the row that only ever means "stand
/// here".
Future<void> _standOnTransformHeader(WidgetTester tester) async {
  final label = find.byKey(
    const ValueKey<String>(
      'timeline-lane-label-gizmo-draw-transform-group',
    ),
  );
  await tester.ensureVisible(label);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: label, matching: find.text('Transform')),
    warnIfMissed: false,
  );
  await tester.pumpAndSettle();
}

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

  test('R5 #10: the anchor keys anchor-point alone — the member you touch '
      'is the member that keys', () {
    final dragged = transformTrackWithAnchorDragged(
      TransformTrack.empty(),
      frameIndex: 3,
      anchorPoint: CanvasPoint(x: 75, y: 45),
    );
    expect(dragged.anchorPoint.keyAt(3)!.value, CanvasPoint(x: 75, y: 45));
    expect(
      dragged.position.isEmpty,
      isTrue,
      reason: 'compensating would key Position, which the user\'s rule for '
          '#10 forbids — and 유저 2026-10-01 kept it: 「그림은 가만히라기보다 '
          '지금 로직 그대로」',
    );
  });

  testWidgets('R5 #10: shows only while a lane that DECLARES it is the '
      'standing row — twirling alone is not intent', (tester) async {
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

    expect(find.byType(RowTransformBox), findsNothing);

    // Opening the lanes shows the Transform header. It does NOT put a
    // handle on the artwork: reading a row's properties is not asking to
    // pose it, which is the whole of R5 #10.
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-lane-toggle-gizmo-draw')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RowTransformBox), findsNothing);

    // Standing on the Transform group declares everything its members do
    // — the box AND the anchor, together, which is the one row where both
    // are on screen at once.
    await _standOnTransformHeader(tester);
    final box = tester.widget<RowTransformBox>(find.byType(RowTransformBox));
    expect(box.move, isNotNull, reason: 'the box: position, scale, rotation');
    expect(box.cross, isNotNull, reason: 'and the anchor\'s cross with it');
    // F-222 ②: a blank cel's box is the canvas — the transform tool's rule
    // for a picture with nothing in it — so the position is still grabbed
    // where the crosshair used to stand alone.
    expect(box.corners, [
      CanvasPoint(x: 0, y: 0),
      CanvasPoint(x: 1280, y: 0),
      CanvasPoint(x: 1280, y: 720),
      CanvasPoint(x: 0, y: 720),
    ]);

    // Stepping back onto the LAYER row takes it away — the layer is what
    // you draw on, and nothing there declares a manipulator.
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-layer-name-gizmo-draw')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RowTransformBox), findsNothing);
  });

  testWidgets('the TRANSFORM group\'s own bypass hides it — the row MASTER '
      'cannot answer this, since a row with one effect off is `mixed` '
      '(R8)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          initialProject: Project(
            id: const ProjectId('gizmo-fx-project'),
            name: 'Gizmo FX Project',
            createdAt: DateTime.utc(2026, 7, 30),
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
                        // An effect that stays ON: with the transform
                        // bypassed the row reads `mixed`, which is the
                        // ONE state that tells the two gates apart.
                        effects: [
                          LayerEffect(
                            id: const EffectId('gizmo-fx'),
                            kind: EffectKind.brightnessContrast,
                            parameters: {
                              'brightness': EffectParameter(value: 20),
                            },
                          ),
                        ],
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

    // Twirl the row's lanes open and stand on the Transform group.
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-lane-toggle-gizmo-draw')),
    );
    await tester.pumpAndSettle();
    await _standOnTransformHeader(tester);
    expect(find.byType(RowTransformBox), findsOneWidget);

    final headerSwitch = find.byKey(
      const ValueKey<String>(
        'timeline-lane-group-fx-gizmo-draw-transform-group',
      ),
    );
    await tester.ensureVisible(headerSwitch);
    await tester.pumpAndSettle();

    await tester.tap(headerSwitch);
    await tester.pumpAndSettle();
    expect(
      find.byType(RowTransformBox),
      findsNothing,
      reason: 'the pose it would drag is bypassed',
    );

    await tester.tap(headerSwitch);
    await tester.pumpAndSettle();
    expect(find.byType(RowTransformBox), findsOneWidget);
  });
}
