import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';

/// R3b: the cut's whole unit — pasteboard fill, paper, picture — is what a
/// fade thins, and the camera's view of it reaches past the paper onto the
/// stage's apron.
///
/// ↩️The painter thinned the unit itself (`fadeOpacity`) while it drew a
/// film's picture; the unit is laid around the painters now, as playback
/// lays it (`a_film_frame_is_the_frame_playback_shows_test`).
void main() {
  Future<(int, int, int, int)> pixelAt(
    PlaybackFramePainter painter, {
    required int width,
    required int height,
    required int x,
    required int y,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    painter.paint(canvas, Size(width.toDouble(), height.toDouble()));
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final offset = (y * width + x) * 4;
    image.dispose();
    return (
      bytes!.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
      bytes.getUint8(offset + 3),
    );
  }

  testWidgets('the camera sees the PASTEBOARD past the paper\'s edge — the '
      'stage apron is part of the unit', (tester) async {
    await tester.runAsync(() async {
      // An 8-wide camera frame over a 4-wide canvas centered at x=2: the
      // right half of the frame reaches past the paper.
      const canvasSize = CanvasSize(width: 4, height: 4);
      const frameSize = CanvasSize(width: 8, height: 4);
      final painter = PlaybackFramePainter(
        canvasSize: canvasSize,
        cameraPose: CameraPose(center: CanvasPoint(x: 2, y: 2)),
        cameraFrameSize: frameSize,
        paperBackground: ProjectBackground.defaultBackground,
        pasteboardColor: const Color(0xFF445566),
        paintLetterbox: false,
      );
      final paper = await pixelAt(painter, width: 8, height: 4, x: 3, y: 2);
      expect((paper.$1, paper.$2, paper.$3), (255, 255, 255));
      final apron = await pixelAt(painter, width: 8, height: 4, x: 7, y: 2);
      expect((apron.$1, apron.$2, apron.$3), (0x44, 0x55, 0x66));
    });
  });
}
