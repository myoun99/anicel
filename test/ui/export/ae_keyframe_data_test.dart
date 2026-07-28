import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/ui/export/ae_keyframe_data.dart';

void main() {
  group('bakeCameraAeSamples', () {
    test('bakes one sample per frame with the AE transform mapping', () {
      // Keys at 0 (default-ish) and 2 (moved, zoom 2, rotated 90cw); the
      // middle frame lerps linearly.
      final samples = bakeCameraAeSamples(
        camera: CutCamera(
          keyframes: {
            0: CameraPose(center: CanvasPoint(x: 100, y: 50)),
            2: CameraPose(
              center: CanvasPoint(x: 200, y: 150),
              zoom: 2,
              rotationDegrees: 90,
            ),
          },
        ),
        canvasSize: const CanvasSize(width: 800, height: 600),
        frameCount: 3,
      );

      expect(samples, hasLength(3));
      expect(samples.map((s) => s.frame), [0, 1, 2]);
      expect(samples[1].anchorX, closeTo(150, 1e-9));
      expect(samples[1].anchorY, closeTo(100, 1e-9));
      // zoom 1 -> 1.5 -> 2 becomes AE scale percent.
      expect(samples.map((s) => s.scalePercent), [100, 150, 200]);
      // The world spins opposite the camera's clockwise rotation.
      expect(samples.map((s) => s.rotationDegrees), [0, -45, -90]);
    });

    test('an empty camera bakes the default centered pose', () {
      final samples = bakeCameraAeSamples(
        camera: CutCamera.empty(),
        canvasSize: const CanvasSize(width: 800, height: 600),
        frameCount: 2,
      );

      expect(samples.map((s) => s.anchorX), [400, 400]);
      expect(samples.map((s) => s.anchorY), [300, 300]);
      expect(samples.map((s) => s.scalePercent), [100, 100]);
      expect(samples.map((s) => s.rotationDegrees), [0, 0]);
    });
  });

  group('buildAeTransformKeyframeData', () {
    test('emits the AE clipboard layout with tab-separated rows', () {
      final text = buildAeTransformKeyframeData(
        framesPerSecond: 24,
        sourceWidth: 1920,
        sourceHeight: 1080,
        samples: const [
          AeTransformSample(
            frame: 0,
            anchorX: 960,
            anchorY: 540,
            scalePercent: 100,
            rotationDegrees: 0,
          ),
          AeTransformSample(
            frame: 1,
            anchorX: 970.5,
            anchorY: 540,
            scalePercent: 150.25,
            rotationDegrees: -45,
          ),
        ],
      );

      expect(text, startsWith('Adobe After Effects 8.0 Keyframe Data\n'));
      expect(text, contains('\tUnits Per Second\t24\n'));
      expect(text, contains('\tSource Width\t1920\n'));
      expect(text, contains('\tSource Height\t1080\n'));

      expect(text, contains('Transform\tAnchor Point\n'));
      expect(text, contains('\tFrame\tX pixels\tY pixels\tZ pixels\t\n'));
      expect(text, contains('\t0\t960\t540\t0\t\n'));
      expect(text, contains('\t1\t970.5\t540\t0\t\n'));

      // One constant Position key pins the layer to the comp center.
      expect(text, contains('Transform\tPosition\n'));
      expect(text, contains('\t0\t960\t540\t0\t\n'));

      expect(text, contains('Transform\tScale\n'));
      expect(text, contains('\tFrame\tX percent\tY percent\tZ percent\t\n'));
      expect(text, contains('\t0\t100\t100\t100\t\n'));
      expect(text, contains('\t1\t150.25\t150.25\t100\t\n'));

      expect(text, contains('Transform\tRotation\n'));
      expect(text, contains('\tFrame\tdegrees\t\n'));
      expect(text, contains('\t1\t-45\t\n'));

      expect(text, endsWith('End of Keyframe Data\n'));
    });

    test('rejects an empty sample list', () {
      expect(
        () => buildAeTransformKeyframeData(
          framesPerSecond: 24,
          sourceWidth: 16,
          sourceHeight: 9,
          samples: const [],
        ),
        throwsArgumentError,
      );
    });
  });

  group('formatAeNumber', () {
    test('integers bare, fractions trimmed to four decimals', () {
      expect(formatAeNumber(960), '960');
      expect(formatAeNumber(-45), '-45');
      expect(formatAeNumber(970.5), '970.5');
      expect(formatAeNumber(150.25), '150.25');
      expect(formatAeNumber(1.23456789), '1.2346');
      expect(formatAeNumber(0.10000), '0.1');
    });
  });
}
