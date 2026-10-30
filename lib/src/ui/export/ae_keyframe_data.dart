import '../../models/camera_pose.dart';
import '../../models/canvas_size.dart';
import '../../models/cut_camera.dart';
import '../../services/camera_pose_resolver.dart';
import '../../services/export/ae_script.dart' show formatAeNumber;

// ⚠️NO DOOR CALLS THE WRITER NOW, ON PURPOSE (the AE Script tab reads the
// camera through [aeCameraSampleOf] alone). 🗣️F-455 (유저 2026-10-23) took
// the cut menu's 「카메라 AE 키프레임 복사」 away for 「다른 카드에서 선택한 행
// ae복사(애니메이션행의 경우 트랜스폼이나 노출같은거 다 포함해서)로 폭넓게
// 구현할것임」 — the writer and the camera's bake below are what that copy
// starts from. ⛔Not dead code to sweep: the copy of a row is coming.

/// One baked transform sample for After Effects keyframe-data text.
///
/// The mapping mirrors the app's camera render transform
/// (`translate(out/2)·scale(zoom)·rotate(−θ)·translate(−center)`), which is
/// exactly an AE layer whose Anchor Point animates while Position stays at
/// the comp center: anchor = camera center, scale = zoom·100, rotation =
/// −rotationDegrees (the world spins opposite the camera).
class AeTransformSample {
  const AeTransformSample({
    required this.frame,
    required this.anchorX,
    required this.anchorY,
    required this.scalePercent,
    required this.rotationDegrees,
  });

  final int frame;
  final double anchorX;
  final double anchorY;
  final double scalePercent;
  final double rotationDegrees;
}

/// Builds "Adobe After Effects 8.0 Keyframe Data" clipboard text.
///
/// Paste onto the canvas-sequence layer in a comp sized [sourceWidth]×
/// [sourceHeight] at [framesPerSecond]: the text carries Anchor Point,
/// Scale and Rotation rows per sample plus one constant Position key
/// pinning the layer to the comp center.
String buildAeTransformKeyframeData({
  required int framesPerSecond,
  required int sourceWidth,
  required int sourceHeight,
  required List<AeTransformSample> samples,
}) {
  if (samples.isEmpty) {
    throw ArgumentError.value(samples, 'samples', 'Samples must not be empty.');
  }

  final buffer = StringBuffer()
    ..writeln('Adobe After Effects 8.0 Keyframe Data')
    ..writeln()
    ..writeln('\tUnits Per Second\t$framesPerSecond')
    ..writeln('\tSource Width\t$sourceWidth')
    ..writeln('\tSource Height\t$sourceHeight')
    ..writeln('\tSource Pixel Aspect Ratio\t1')
    ..writeln('\tComp Pixel Aspect Ratio\t1')
    ..writeln()
    ..writeln('Transform\tAnchor Point')
    ..writeln('\tFrame\tX pixels\tY pixels\tZ pixels\t');
  for (final sample in samples) {
    buffer.writeln(
      '\t${sample.frame}'
      '\t${formatAeNumber(sample.anchorX)}'
      '\t${formatAeNumber(sample.anchorY)}'
      '\t0\t',
    );
  }

  buffer
    ..writeln()
    ..writeln('Transform\tPosition')
    ..writeln('\tFrame\tX pixels\tY pixels\tZ pixels\t')
    ..writeln(
      '\t${samples.first.frame}'
      '\t${formatAeNumber(sourceWidth / 2)}'
      '\t${formatAeNumber(sourceHeight / 2)}'
      '\t0\t',
    )
    ..writeln()
    ..writeln('Transform\tScale')
    ..writeln('\tFrame\tX percent\tY percent\tZ percent\t');
  for (final sample in samples) {
    final scale = formatAeNumber(sample.scalePercent);
    buffer.writeln('\t${sample.frame}\t$scale\t$scale\t100\t');
  }

  buffer
    ..writeln()
    ..writeln('Transform\tRotation')
    ..writeln('\tFrame\tdegrees\t');
  for (final sample in samples) {
    buffer.writeln(
      '\t${sample.frame}\t${formatAeNumber(sample.rotationDegrees)}\t',
    );
  }

  buffer
    ..writeln()
    ..writeln('End of Keyframe Data');
  return buffer.toString();
}

/// Bakes a cut's camera into one AE sample per playback frame.
///
/// Baking every frame (instead of exporting only the keyframes) sidesteps
/// AE's auto-bezier spatial interpolation on pasted Anchor Point keys — the
/// pasted motion matches this app's linear resolver exactly, the same way
/// the Toei digital timesheet drives AE frame by frame.
List<AeTransformSample> bakeCameraAeSamples({
  required CutCamera camera,
  required CanvasSize canvasSize,
  required int frameCount,
}) {
  return [
    for (var frame = 0; frame < frameCount; frame += 1)
      aeCameraSampleOf(
        frame,
        resolveCameraPoseAt(
          camera: camera,
          canvasSize: canvasSize,
          frameIndex: frame,
        ),
      ),
  ];
}

/// [pose] as the AE layer that looks through the camera: the canvas
/// anchored at the camera's centre and pinned to the comp's, scaled by its
/// zoom and turned against it — the class doc's mapping, ONE spelling for
/// the clipboard's bake and the AE Script tab's camera comp.
AeTransformSample aeCameraSampleOf(int frame, CameraPose pose) {
  return AeTransformSample(
    frame: frame,
    anchorX: pose.center.x,
    anchorY: pose.center.y,
    scalePercent: pose.zoom * 100,
    rotationDegrees: -pose.rotationDegrees,
  );
}
