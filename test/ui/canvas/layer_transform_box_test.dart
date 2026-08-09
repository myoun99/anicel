import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/canvas/layer_transform_box.dart';
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart';

/// R5 #10b — the box frames the PICTURE and each handle drives ONE member.
void main() {
  const canvasSize = CanvasSize(width: 400, height: 300);
  // The anchor at the canvas centre, landed on the same point: the
  // identity pose, so artwork coordinates and screen coordinates agree at
  // zoom 1 and the arithmetic below is readable.
  final anchor = CanvasPoint(x: 200, y: 150);

  Future<void> pumpBox(
    WidgetTester tester, {
    required TransformPose pose,
    required List<double> zooms,
    required List<double> rotations,
    Rect bounds = const Rect.fromLTRB(100, 50, 300, 250),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTransformBox(
            bounds: bounds,
            pose: pose,
            anchorPoint: anchor,
            canvasSize: canvasSize,
            viewport: CanvasViewport(),
            onScaleCommitted: zooms.add,
            onRotationCommitted: rotations.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a corner sits on the picture bounds, not the canvas',
      (tester) async {
    await pumpBox(
      tester,
      pose: TransformPose(center: anchor),
      zooms: [],
      rotations: [],
    );
    // The identity pose maps artwork to canvas 1:1, and the default
    // viewport maps canvas to screen 1:1 — so the top-left handle is over
    // the bounds' top-left, NOT the canvas origin.
    final topLeft = tester.getCenter(
      find.byKey(const ValueKey<String>('layer-transform-box-corner-0')),
    );
    expect(topLeft.dx, closeTo(100, 0.5));
    expect(topLeft.dy, closeTo(50, 0.5));
  });

  testWidgets('dragging a corner AWAY from the anchor scales up, and '
      'commits scale ALONE', (tester) async {
    final zooms = <double>[];
    final rotations = <double>[];
    await pumpBox(
      tester,
      pose: TransformPose(center: anchor),
      zooms: zooms,
      rotations: rotations,
    );

    // The bottom-right corner is (300, 250); the pivot (the anchor) is at
    // (200, 150), so it starts 100√2 away. Dragging it to (400, 350)
    // doubles that distance.
    await tester.drag(
      find.byKey(const ValueKey<String>('layer-transform-box-corner-2')),
      const Offset(100, 100),
    );
    await tester.pumpAndSettle();

    expect(zooms, hasLength(1));
    expect(zooms.single, closeTo(2.0, 0.01));
    expect(rotations, isEmpty, reason: 'a corner is a statement about scale');
  });

  testWidgets('dragging INTO the anchor scales down rather than flipping',
      (tester) async {
    final zooms = <double>[];
    await pumpBox(
      tester,
      pose: TransformPose(center: anchor),
      zooms: zooms,
      rotations: [],
    );
    // Halfway in from (300, 250) toward the pivot at (200, 150).
    await tester.drag(
      find.byKey(const ValueKey<String>('layer-transform-box-corner-2')),
      const Offset(-50, -50),
    );
    await tester.pumpAndSettle();
    expect(zooms.single, closeTo(0.5, 0.01));
    expect(zooms.single, greaterThan(0), reason: 'zoom must stay positive');
  });

  testWidgets('the rotate handle sweeps degrees about the anchor, and '
      'commits rotation ALONE', (tester) async {
    final zooms = <double>[];
    final rotations = <double>[];
    await pumpBox(
      tester,
      pose: TransformPose(center: anchor),
      zooms: zooms,
      rotations: rotations,
    );

    final handle = find.byKey(
      const ValueKey<String>('layer-transform-box-rotate'),
    );
    final start = tester.getCenter(handle);
    // The handle sits straight above the pivot. Swing it to the pivot's
    // RIGHT, at the same radius: a quarter turn clockwise.
    final radius = (start - const Offset(200, 150)).distance;
    await tester.dragFrom(
      start,
      Offset(200 + radius, 150) - start,
    );
    await tester.pumpAndSettle();

    expect(rotations, hasLength(1));
    expect(rotations.single, closeTo(90, 0.5));
    expect(zooms, isEmpty, reason: 'the rotate handle is about rotation');
  });

  testWidgets('a drag that never moves commits nothing', (tester) async {
    final zooms = <double>[];
    final rotations = <double>[];
    await pumpBox(
      tester,
      pose: TransformPose(center: anchor),
      zooms: zooms,
      rotations: rotations,
    );
    await tester.drag(
      find.byKey(const ValueKey<String>('layer-transform-box-corner-0')),
      Offset.zero,
    );
    await tester.pumpAndSettle();
    expect(zooms, isEmpty);
    expect(rotations, isEmpty);
  });

  group('the commit helpers touch one lane', () {
    test('scale keys scale, keeping its interpolation and the other lanes',
        () {
      final track = TransformTrack.empty().copyWith(
        scale: PropertyTrack<double>().withKey(
          2,
          1.5,
          interpolation: PropertyKeyInterpolation.hold,
        ),
        rotation: PropertyTrack<double>().withKey(2, 30),
      );
      final next = transformTrackWithScaleDragged(
        track,
        frameIndex: 2,
        zoom: 2.5,
      );
      expect(next.scale.keyAt(2)!.value, 2.5);
      expect(
        next.scale.keyAt(2)!.interpolation,
        PropertyKeyInterpolation.hold,
      );
      expect(next.rotation.keyAt(2)!.value, 30, reason: 'untouched');
      expect(next.position.isEmpty, isTrue);
    });

    test('rotation keys rotation alone', () {
      final next = transformTrackWithRotationDragged(
        TransformTrack.empty(),
        frameIndex: 4,
        rotationDegrees: -45,
      );
      expect(next.rotation.keyAt(4)!.value, -45);
      expect(next.scale.isEmpty, isTrue);
      expect(next.position.isEmpty, isTrue);
    });
  });
}
