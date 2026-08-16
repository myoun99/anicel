import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show Matrix4, MatrixUtils, Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/canvas/layer_pose_paint.dart';
import 'package:anicel/src/ui/canvas/viewport_canvas_transform.dart';

/// P8 painter-parity pins: the shared paint matrix must speak EXACTLY the
/// viewport's coordinate mapping, and its analytic inverse must undo it —
/// otherwise painted pixels and pointer math drift apart.
///
/// Plus the pan-phase snap's pins ([renderSnappedViewport], applied inside
/// [applyViewportTransform]): the rendered TRANSLATION lands on whole
/// DEVICE pixels — device, not logical — and a rotated view keeps its
/// exact fractional phase.
void main() {
  final assortedViewports = [
    CanvasViewport(),
    CanvasViewport(zoom: 2.5, panX: 33, panY: -7),
    CanvasViewport(rotationDegrees: 45),
    CanvasViewport(flipHorizontal: true),
    CanvasViewport(
      zoom: 0.6,
      panX: -20,
      panY: 14,
      rotationDegrees: -120,
      flipHorizontal: true,
    ),
  ];

  final assortedPoints = [
    CanvasPoint(x: 0, y: 0),
    CanvasPoint(x: 64, y: 128),
    CanvasPoint(x: -5.5, y: 7.25),
  ];

  test('viewportTransformMatrix maps points exactly like canvasToViewport', () {
    for (final viewport in assortedViewports) {
      final matrix = viewportTransformMatrix(viewport);
      for (final point in assortedPoints) {
        final expected = viewport.canvasToViewport(point);
        final mapped = MatrixUtils.transformPoint(
          matrix,
          Offset(point.x, point.y),
        );
        expect(mapped.dx, closeTo(expected.x, 1e-6), reason: '$viewport');
        expect(mapped.dy, closeTo(expected.y, 1e-6), reason: '$viewport');
      }
    }
  });

  test('the analytic inverse undoes the transform', () {
    for (final viewport in assortedViewports) {
      final product = viewportTransformMatrix(
        viewport,
      ).multiplied(viewportInverseTransformMatrix(viewport));
      final identity = Matrix4.identity();
      for (var i = 0; i < 16; i += 1) {
        expect(
          product.storage[i],
          closeTo(identity.storage[i], 1e-9),
          reason: '$viewport [$i]',
        );
      }
    }
  });

  test('an identity pose wraps to identity under ANY viewport', () {
    const canvasSize = CanvasSize(width: 200, height: 100);
    final identityPose = TransformPose(
      center: CanvasPoint(x: 100, y: 50),
      zoom: 1,
      rotationDegrees: 0,
    );
    for (final viewport in assortedViewports) {
      final wrap = layerPoseViewportWrapMatrix(
        identityPose,
        canvasSize,
        viewport,
      );
      final identity = Matrix4.identity();
      for (var i = 0; i < 16; i += 1) {
        expect(
          wrap.storage[i],
          closeTo(identity.storage[i], 1e-6),
          reason: '$viewport [$i]',
        );
      }
    }
  });

  // ------------------------------------------------------------------ //
  // The pan-phase snap, pinned through the pixels painters actually get.
  //
  // The fixture is the shared entry itself: a white ground, then 1px
  // canvas-space lines every 8px at offset .25 drawn under
  // [applyViewportTransform] — edges OFF the integer grid, so one device
  // pixel of translation phase (1/3 logical px at DPR 3) carries an edge
  // across pixel centers and MUST change bytes. AA off throughout:
  // coverage is pixel-center exact, so equal transforms mean equal bytes
  // and nothing else does.

  const rasterWidth = 120;
  const rasterHeight = 90;

  Future<Uint8List> renderBytes(
    WidgetTester tester,
    CanvasViewport viewport, {
    required double devicePixelRatio,
  }) {
    return tester
        .runAsync(() async {
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          canvas.drawRect(
            ui.Rect.fromLTWH(
              0,
              0,
              rasterWidth.toDouble(),
              rasterHeight.toDouble(),
            ),
            ui.Paint()
              ..color = const ui.Color(0xFFFFFFFF)
              ..isAntiAlias = false,
          );
          applyViewportTransform(
            canvas,
            viewport,
            devicePixelRatio: devicePixelRatio,
          );
          final ink = ui.Paint()
            ..color = const ui.Color(0xFF000000)
            ..isAntiAlias = false;
          for (var k = -8; k < 40; k += 1) {
            canvas.drawRect(ui.Rect.fromLTWH(k * 8 + 0.25, -64, 1, 512), ink);
            canvas.drawRect(ui.Rect.fromLTWH(-64, k * 8 + 0.25, 512, 1), ink);
          }
          final picture = recorder.endRecording();
          final image = picture.toImageSync(rasterWidth, rasterHeight);
          picture.dispose();
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!.buffer.asUint8List();
        })
        .then((bytes) => bytes!);
  }

  testWidgets('pans within one device pixel paint byte-identically', (
    tester,
  ) async {
    // DPR 3: a device pixel is 1/3 logical px. 10.30·3 = 30.9 and
    // 10.32·3 = 30.96 both round to device pixel 31 (5.10/5.12 → 15), so
    // the two viewports are ONE effective translation.
    final a = await renderBytes(
      tester,
      CanvasViewport(panX: 10.30, panY: 5.10),
      devicePixelRatio: 3,
    );
    final b = await renderBytes(
      tester,
      CanvasViewport(panX: 10.32, panY: 5.12),
      devicePixelRatio: 3,
    );
    expect(
      a,
      equals(b),
      reason: 'two pans on the same device pixel must render one picture',
    );
  });

  testWidgets('pans one DEVICE pixel apart paint differently', (tester) async {
    // The presence anchor for the equality above — and the pin that the
    // snap counts DEVICE pixels: 10.10·3 = 30.3 → 30 and 10.30·3 =
    // 30.9 → 31 are different device pixels on the SAME logical rounding
    // (both 10), so a snap that rounded logical pixels would collapse the
    // two into one picture.
    final a = await renderBytes(
      tester,
      CanvasViewport(panX: 10.10, panY: 5.10),
      devicePixelRatio: 3,
    );
    final b = await renderBytes(
      tester,
      CanvasViewport(panX: 10.30, panY: 5.10),
      devicePixelRatio: 3,
    );
    expect(
      a,
      isNot(equals(b)),
      reason: 'a device-pixel step must move the picture — if it does not, '
          'the equality test above is vacuous or the snap rounds logical '
          'pixels',
    );
  });

  testWidgets('a rotated view keeps its exact fractional phase', (
    tester,
  ) async {
    // The same-device-pixel pair again (10.24·3 = 30.72 and 10.32·3 =
    // 30.96 both → 31; 5.10/5.11 → 15), under rotation: the snap is gated
    // OFF there — rotated sampling is inherently fractional and a device
    // rounding of a pre-rotation translate is ill-defined — so the raw
    // sub-pixel pan difference must reach the pixels.
    final a = await renderBytes(
      tester,
      CanvasViewport(panX: 10.24, panY: 5.10, rotationDegrees: 30),
      devicePixelRatio: 3,
    );
    final b = await renderBytes(
      tester,
      CanvasViewport(panX: 10.32, panY: 5.11, rotationDegrees: 30),
      devicePixelRatio: 3,
    );
    expect(
      a,
      isNot(equals(b)),
      reason: 'rotated views must NOT snap — identical bytes mean the '
          'rotation gate is gone',
    );
  });
}
