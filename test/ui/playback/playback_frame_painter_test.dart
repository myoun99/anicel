import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';

/// R7-③ pixel pins: in CANVAS mode the cut pose (V track) moves only the
/// merged CONTENT — the paper is the panel's static stage and the moving
/// picture clips to it. (Camera mode keeps the whole finished picture —
/// paper included — moving inside the output frame, like the MP4 bake.)
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  // R28 #9: the painter's default paper — pure white, from the one
  // ProjectBackground constant.
  const paper = Color(0xFFFFFFFF);
  const red = Color(0xFFFF0000);

  Future<ui.Image> solidComposite() async {
    final recorder = ui.PictureRecorder();
    Canvas(
      recorder,
    ).drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = red);
    return recorder.endRecording().toImage(8, 8);
  }

  Future<ui.Image> paintToImage(PlaybackFramePainter painter) async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(40, 40));
    return recorder.endRecording().toImage(40, 40);
  }

  Future<Color> pixelAt(ui.Image image, int x, int y) async {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final offset = (y * image.width + x) * 4;
    return Color.fromARGB(
      data.getUint8(offset + 3),
      data.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
    );
  }

  test('canvas mode without a pose: the composite covers the paper', () async {
    final image = await paintToImage(
      PlaybackFramePainter(
        image: await solidComposite(),
        canvasSize: canvasSize,
      ),
    );
    expect(await pixelAt(image, 4, 4), red);
  });

  test('canvas mode under a cut pose: the paper stays put and only the '
      'content moves, clipped to the canvas', () async {
    final image = await paintToImage(
      PlaybackFramePainter(
        image: await solidComposite(),
        canvasSize: canvasSize,
        // The content's center lands on x=8 (the canvas's right edge):
        // its left half fills canvas x 4..8, the right half clips away.
        cutPose: CameraPose(center: CanvasPoint(x: 8, y: 4)),
      ),
    );
    expect(
      await pixelAt(image, 2, 4),
      paper,
      reason: 'the vacated canvas shows the STATIC paper, not background',
    );
    expect(
      await pixelAt(image, 6, 4),
      red,
      reason: 'the moved content still shows inside the canvas',
    );
    expect(
      await pixelAt(image, 10, 4),
      const Color(0x00000000),
      reason: 'the content clips at the canvas edge — nothing escapes it',
    );
  });
}
