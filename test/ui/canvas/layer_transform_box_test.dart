import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
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
    CanvasViewport? viewport,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTransformBox(
            bounds: bounds,
            pose: pose,
            anchorPoint: anchor,
            canvasSize: canvasSize,
            viewport: viewport ?? CanvasViewport(),
            onScaleChanged: (_) {},
            onScaleCommitted: zooms.add,
            onRotationChanged: (_) {},
            onRotationCommitted: rotations.add,
            onCancelled: () {},
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

  // finger-mode-reaches-canvas-handles (2026-09-29): a handle took its
  // devices when its recognizer was MADE, which no rebuild runs again — so
  // the mode changes here with the box already up, and nothing else.
  testWidgets('switching the one-finger slot to DRAWING with the box up '
      'reaches its handles at once', (tester) async {
    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.flip,
    );
    addTearDown(() {
      AppInput.settings.value = AppInputSettings.testCorpusBaseline;
    });
    final zooms = <double>[];
    await pumpBox(
      tester,
      pose: TransformPose(center: anchor),
      zooms: zooms,
      rotations: [],
    );
    final corner = find.byKey(
      const ValueKey<String>('layer-transform-box-corner-2'),
    );

    await tester.drag(
      corner,
      const Offset(100, 100),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();
    expect(zooms, isEmpty, reason: 'TS9: a flipping finger drives no tool');

    AppInput.settings.value = AppInput.settings.value.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.draw,
    );
    await tester.pump();
    await tester.drag(
      corner,
      const Offset(100, 100),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();

    expect(zooms, hasLength(1), reason: 'the finger draws now');
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

  // F-222 ①: the box turns by the one turn law — canvas angles, folded step
  // by step ([TransformBoxLaw.turn]).
  testWidgets('a turn through the ±180° seam keeps going the way the hand '
      'went', (tester) async {
    final rotations = <double>[];
    await pumpBox(
      tester,
      pose: TransformPose(center: anchor),
      zooms: [],
      rotations: rotations,
    );
    final start = tester.getCenter(
      find.byKey(const ValueKey<String>('layer-transform-box-rotate')),
    );
    const pivot = Offset(200, 150);
    final radius = (start - pivot).distance;

    // Three quarters ANTI-clockwise from straight above, through the pivot's
    // left — where the screen angle flips from −180° to 180°.
    final gesture = await tester.startGesture(start);
    for (final degrees in const [-135.0, 180.0, 135.0, 90.0, 45.0, 0.0]) {
      final radians = degrees * math.pi / 180;
      await gesture.moveTo(
        pivot + Offset(math.cos(radians), math.sin(radians)) * radius,
      );
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      rotations.single,
      closeTo(-270, 0.5),
      reason: '↩️the whole sweep from the press read +90 here: the same '
          'picture, keyed a quarter turn the other way',
    );
  });

  testWidgets('under a flipped view the rotate handle follows the hand', (
    tester,
  ) async {
    final rotations = <double>[];
    // Mirrored about the canvas's x = 0, then panned back: the pivot and
    // the handle stand where they stood unflipped.
    await pumpBox(
      tester,
      pose: TransformPose(center: anchor),
      zooms: [],
      rotations: rotations,
      viewport: CanvasViewport(panX: 400, flipHorizontal: true),
    );
    final start = tester.getCenter(
      find.byKey(const ValueKey<String>('layer-transform-box-rotate')),
    );
    final radius = (start - const Offset(200, 150)).distance;

    // To the pivot's right ON SCREEN — the canvas's left: a quarter turn
    // back on the canvas is what brings the handle under the hand.
    await tester.dragFrom(start, Offset(200 + radius, 150) - start);
    await tester.pumpAndSettle();

    expect(rotations.single, closeTo(-90, 0.5));
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

  testWidgets('F-195: the grabbed corner stays under the pointer while the '
      'host hands the scaled pose back per move — the zoom is measured from '
      'where the grab began', (tester) async {
    final shown = ValueNotifier<double>(1);
    addTearDown(shown.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<double>(
            valueListenable: shown,
            builder: (context, zoom, _) => LayerTransformBox(
              bounds: const Rect.fromLTRB(100, 50, 300, 250),
              pose: TransformPose(center: anchor, zoom: zoom),
              anchorPoint: anchor,
              canvasSize: canvasSize,
              viewport: CanvasViewport(),
              // The app's loop: the value in flight comes back as the pose.
              onScaleChanged: (next) => shown.value = next,
              onScaleCommitted: (_) {},
              onRotationChanged: (_) {},
              onRotationCommitted: (_) {},
              onCancelled: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final corner = find.byKey(
      const ValueKey<String>('layer-transform-box-corner-2'),
    );
    final start = tester.getCenter(corner);

    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    // The grab is measured from the press, so the corner rides the hand.
    var pointer = start;
    for (var step = 0; step < 4; step += 1) {
      await gesture.moveBy(const Offset(20, 20));
      pointer += const Offset(20, 20);
      await tester.pump();
    }

    expect(
      (tester.getCenter(corner) - pointer).distance,
      lessThan(2),
      reason: 'measured from the pose handed back, each move would compound '
          'and the corner would run away from the hand',
    );
    await gesture.up();
  });

  testWidgets('a grab that comes back to where it began writes nothing and '
      'drops what it showed', (tester) async {
    final zooms = <double>[];
    var cancels = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTransformBox(
            bounds: const Rect.fromLTRB(100, 50, 300, 250),
            pose: TransformPose(center: anchor),
            anchorPoint: anchor,
            canvasSize: canvasSize,
            viewport: CanvasViewport(),
            onScaleChanged: (_) {},
            onScaleCommitted: zooms.add,
            onRotationChanged: (_) {},
            onRotationCommitted: (_) {},
            onCancelled: () => cancels += 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final corner = find.byKey(
      const ValueKey<String>('layer-transform-box-corner-2'),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(corner),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(40, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(-40, -40));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(zooms, isEmpty, reason: 'the same zoom is no edit');
    expect(cancels, 1, reason: 'what the grab showed is dropped');
  });

  testWidgets('a box taken away mid-grab drops what it showed once the tree '
      'settles', (tester) async {
    var cancels = 0;
    final shown = ValueNotifier<bool>(true);
    addTearDown(shown.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: shown,
            builder: (context, visible, _) => visible
                ? LayerTransformBox(
                    bounds: const Rect.fromLTRB(100, 50, 300, 250),
                    pose: TransformPose(center: anchor),
                    anchorPoint: anchor,
                    canvasSize: canvasSize,
                    viewport: CanvasViewport(),
                    onScaleChanged: (_) {},
                    onScaleCommitted: (_) {},
                    onRotationChanged: (_) {},
                    onRotationCommitted: (_) {},
                    onCancelled: () => cancels += 1,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey<String>('layer-transform-box-corner-2')),
      ),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(20, 20));
    await tester.pump();

    shown.value = false;
    await tester.pump();
    await tester.pump();

    expect(cancels, 1, reason: 'no release will come to drop it');
    await gesture.up();
  });
}
