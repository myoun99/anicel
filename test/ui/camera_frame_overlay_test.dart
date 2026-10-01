import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/camera/camera_frame_overlay.dart';
import 'package:anicel/src/ui/canvas/row_transform_box.dart';

void main() {
  const frameSize = CanvasSize(width: 1920, height: 1080);

  CameraFramePainter painter({
    required CameraPose pose,
    CanvasViewport? viewport,
  }) {
    return CameraFramePainter(
      pose: pose,
      cameraFrameSize: frameSize,
      viewport: viewport ?? CanvasViewport(),
      dimOpacity: 0.5,
      outlineColor: CameraFrameOverlay.outlineColor,
    );
  }

  group('CameraFramePainter.frameCornersInViewport', () {
    test('zoom 1 no rotation maps the frame 1:1 around the center', () {
      final corners = painter(
        pose: CameraPose(center: CanvasPoint(x: 1000, y: 600)),
      ).frameCornersInViewport();

      expect(corners[0], const Offset(1000 - 960, 600 - 540));
      expect(corners[1], const Offset(1000 + 960, 600 - 540));
      expect(corners[2], const Offset(1000 + 960, 600 + 540));
      expect(corners[3], const Offset(1000 - 960, 600 + 540));
    });

    test('camera zoom 2 halves the view rect on canvas', () {
      final corners = painter(
        pose: CameraPose(center: CanvasPoint(x: 1000, y: 600), zoom: 2),
      ).frameCornersInViewport();

      expect(corners[0], const Offset(1000 - 480, 600 - 270));
      expect(corners[2], const Offset(1000 + 480, 600 + 270));
    });

    test('viewport zoom and pan transform canvas points to screen', () {
      final corners = painter(
        pose: CameraPose(center: CanvasPoint(x: 1000, y: 600)),
        viewport: CanvasViewport(zoom: 0.5, panX: 10, panY: 20),
      ).frameCornersInViewport();

      expect(
        corners[0],
        const Offset((1000 - 960) * 0.5 + 10, (600 - 540) * 0.5 + 20),
      );
      expect(
        corners[2],
        const Offset((1000 + 960) * 0.5 + 10, (600 + 540) * 0.5 + 20),
      );
    });

    test('90 degrees rotates the frame clockwise around the center', () {
      final corners = painter(
        pose: CameraPose(
          center: CanvasPoint(x: 1000, y: 600),
          rotationDegrees: 90,
        ),
      ).frameCornersInViewport();

      // Top-left corner offset (-960, -540) rotated 90° clockwise in y-down
      // screen space becomes (540, -960).
      expect(corners[0].dx, closeTo(1000 + 540, 1e-6));
      expect(corners[0].dy, closeTo(600 - 960, 1e-6));
    });
  });

  group('cameraFrameBoundsInCanvas', () {
    test('unrotated bounds match the frame rect around the center', () {
      final bounds = cameraFrameBoundsInCanvas(
        pose: CameraPose(center: CanvasPoint(x: 1000, y: 600), zoom: 2),
        cameraFrameSize: frameSize,
      );

      expect(
        bounds,
        const Rect.fromLTRB(1000 - 480, 600 - 270, 1000 + 480, 600 + 270),
      );
    });

    test('rotation expands the bounds to the rotated corners', () {
      final bounds = cameraFrameBoundsInCanvas(
        pose: CameraPose(
          center: CanvasPoint(x: 1000, y: 600),
          rotationDegrees: 90,
        ),
        cameraFrameSize: frameSize,
      );

      // At 90° the 1920×1080 frame occupies 1080×1920 around the center.
      expect(bounds.left, closeTo(1000 - 540, 1e-6));
      expect(bounds.right, closeTo(1000 + 540, 1e-6));
      expect(bounds.top, closeTo(600 - 960, 1e-6));
      expect(bounds.bottom, closeTo(600 + 960, 1e-6));
    });
  });

  testWidgets('the frame only DRAWS — a press goes through it to what is '
      'beneath', (tester) async {
    var tappedBelow = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => tappedBelow = true,
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
              Positioned.fill(
                child: CameraFrameOverlay(
                  pose: CameraPose(center: CanvasPoint(x: 100, y: 100)),
                  cameraFrameSize: frameSize,
                  viewport: CanvasViewport(),
                  dimOpacity: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('camera-frame-overlay')),
      warnIfMissed: false,
    );
    expect(tappedBelow, isTrue);
  });

  // F-222 ③: the frame is grabbed through the box every row wears; what is
  // the camera's own is how the box's values map onto the camera's.
  group('CameraFrameBox', () {
    // Camera center (1000, 600) at viewport zoom 0.5 = screen (500, 300);
    // its top-left corner shows at (20, 30). The stage is a 1920×1080
    // canvas, whose pasteboard covers the whole test screen.
    Future<List<_Commit>> pumpBox(WidgetTester tester) async {
      final committed = <_Commit>[];
      RowBoxLanding<T> into<T>(String member) => (
        changed: (_) {},
        committed: (value) => committed.add((member: member, value: value!)),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CameraFrameBox(
              pose: CameraPose(center: CanvasPoint(x: 1000, y: 600)),
              cameraFrameSize: frameSize,
              canvasSize: const CanvasSize(width: 1920, height: 1080),
              viewport: CanvasViewport(zoom: 0.5),
              claimsCanvas: true,
              onCancelled: () {},
              move: into('move'),
              zoom: into('zoom'),
              turn: into('rotation'),
            ),
          ),
        ),
      );
      return committed;
    }

    testWidgets('the inside moves the camera, in canvas pixels', (
      tester,
    ) async {
      final committed = await pumpBox(tester);

      await tester.dragFrom(const Offset(400, 300), const Offset(50, -30));
      await tester.pump();

      // Screen delta divided by the viewport zoom 0.5 = canvas delta.
      expect(committed, [
        (member: 'move', value: CanvasPoint(x: 1100, y: 540)),
      ]);
    });

    testWidgets('a corner zooms about the centre — dragged halfway in, the '
        'frame halves and the zoom doubles', (tester) async {
      final committed = await pumpBox(tester);

      await tester.dragFrom(const Offset(20, 30), const Offset(240, 135));
      await tester.pump();

      expect(committed, hasLength(1));
      expect(committed.single.member, 'zoom', reason: 'the zoom alone');
      expect(committed.single.value as double, closeTo(2, 1e-6));
    });

    testWidgets('outside the frame, on stage, turns the camera about its '
        'centre', (tester) async {
      final committed = await pumpBox(tester);

      // Straight above the centre, past the top edge (y 30), swung to the
      // centre's right: a quarter turn clockwise.
      await tester.dragFrom(const Offset(500, 10), const Offset(270, 290));
      await tester.pump();

      expect(committed, hasLength(1));
      expect(committed.single.member, 'rotation', reason: 'the turn alone');
      expect(committed.single.value as double, closeTo(90, 1e-6));
    });

    testWidgets('it wears no cross and draws no outline of its own — the '
        'frame\'s hairline is the outline', (tester) async {
      await pumpBox(tester);
      final box = tester.widget<RowTransformBox>(find.byType(RowTransformBox));
      expect(box.cross, isNull);
      expect(box.outlined, isFalse);
    });
  });
}

/// What one drag committed: the member its handle drives, and the value.
typedef _Commit = ({String member, Object value});
