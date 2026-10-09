import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/canvas_look.dart';

/// [CanvasLook] (playback-plays-the-screen-material ②): the one answer to
/// how the canvas shows a cut's frame — the view the canvas draws it
/// through, and the level the warmer makes its rows at, read off that same
/// view.
void main() {
  const canvasSize = CanvasSize(width: 2340, height: 1654);
  final cut = Cut(
    id: const CutId('c'),
    name: 'c',
    duration: 4,
    canvasSize: canvasSize,
    layers: const [],
  );

  /// A camera at the canvas's middle that zooms out from frame 2 on.
  CanvasCamera zoomingOut({double rotationDegrees = 0}) => (
    poseOf: (cut, frame) => CameraPose(
      center: CanvasPoint(x: 1170, y: 827),
      zoom: frame < 2 ? 1 : 0.4,
      rotationDegrees: rotationDegrees,
    ),
    frameSize: const CanvasSize(width: 1920, height: 1080),
  );

  test('a frame is drawn at the level of the view it is seen through — the '
      'camera\'s zoom at that frame included', () {
    final look = CanvasLook(
      view: CanvasViewport(),
      devicePixelRatio: 1,
      camera: zoomingOut(),
    );
    expect(
      [for (var frame = 0; frame < 4; frame += 1) look.qualityAt(cut, frame)],
      [
        PlaybackQuality.full,
        PlaybackQuality.full,
        PlaybackQuality.half,
        PlaybackQuality.half,
      ],
    );
    final noCamera = CanvasLook(view: CanvasViewport(), devicePixelRatio: 1);
    expect(
      noCamera.qualityAt(cut, 3),
      PlaybackQuality.full,
      reason: 'seen through no camera, a frame is at the panel\'s own level',
    );
  });

  test('🚨the pan never moves a level: the level the warmer reads is the one '
      'the canvas draws through the panned view, to the bit', () {
    for (final rotationDegrees in [0.0, 17.0, -95.0]) {
      final camera = zoomingOut(rotationDegrees: rotationDegrees);
      for (final pan in [(0.0, 0.0), (13.37, -421.5), (-0.1, 9999.9)]) {
        final panel = CanvasViewport(
          zoom: 0.63,
          panX: pan.$1,
          panY: pan.$2,
          rotationDegrees: 5,
        );
        final look = CanvasLook(
          view: panel,
          devicePixelRatio: 1.25,
          camera: camera,
        );
        for (var frame = 0; frame < 4; frame += 1) {
          final drawnThrough = look.frameViewThrough(panel, cut, frame);
          expect(
            look.qualityAt(cut, frame),
            rowQualityThrough(drawnThrough, 1.25),
            reason: 'turned $rotationDegrees°, panned $pan, frame $frame',
          );
          expect(
            look.frameViewThrough(look.view, cut, frame).zoom,
            drawnThrough.zoom,
            reason: 'the scale itself, not merely its level',
          );
        }
      }
    }
  });

  test('looks that differ only by a pan are one look — the warmer is told '
      'nothing new for a pan', () {
    // One camera, as the session's tear-off is one.
    final camera = zoomingOut();
    CanvasLook panned(double x) => CanvasLook(
      view: CanvasViewport(zoom: 0.5, panX: x, panY: -x),
      devicePixelRatio: 2,
      camera: camera,
    );
    expect(panned(0), panned(250));
    expect(panned(0).hashCode, panned(250).hashCode);
    expect(
      panned(0),
      isNot(
        CanvasLook(
          view: CanvasViewport(zoom: 0.5),
          devicePixelRatio: 2,
        ),
      ),
      reason: 'the camera is part of the look',
    );
  });
}
