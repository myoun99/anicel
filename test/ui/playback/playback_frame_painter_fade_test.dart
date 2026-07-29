import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';

/// R3b: the painter's fade is TRANSPARENCY — the cut's whole unit
/// (pasteboard fill, paper, picture) thins as one layer, revealing what
/// was painted behind it. No wash, no target color.
void main() {
  Future<(int, int, int, int)> pixelAt(
    PlaybackFramePainter painter, {
    required int width,
    required int height,
    required int x,
    required int y,
    Color? behind,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (behind != null) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..color = behind,
      );
    }
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

  testWidgets('a mid-fade frame blends toward what lies BEHIND the unit — '
      'not toward a wash color', (tester) async {
    await tester.runAsync(() async {
      const size = CanvasSize(width: 4, height: 4);
      final painter = PlaybackFramePainter(
        image: null,
        canvasSize: size,
        cameraPose: CameraPose(center: CanvasPoint(x: 2, y: 2)),
        cameraFrameSize: size,
        paperBackground: ProjectBackground.white,
        pasteboardColor: const Color(0xFFFFFFFF),
        paintLetterbox: false,
        fadeOpacity: 0.5,
      );
      // Behind = pure red: a white unit at fade 0.5 lands on pink —
      // the wash model would have landed on grey (toward black) instead.
      final (r, g, b, a) = await pixelAt(
        painter,
        width: 4,
        height: 4,
        x: 2,
        y: 2,
        behind: const Color(0xFFFF0000),
      );
      expect(a, 255);
      expect(r, 255);
      expect(g, closeTo(128, 2));
      expect(b, closeTo(128, 2));
    });
  });

  testWidgets('a fully faded frame vanishes — alpha 0 with nothing behind, '
      'the backdrop untouched when there is one', (tester) async {
    await tester.runAsync(() async {
      const size = CanvasSize(width: 4, height: 4);
      final painter = PlaybackFramePainter(
        image: null,
        canvasSize: size,
        cameraPose: CameraPose(center: CanvasPoint(x: 2, y: 2)),
        cameraFrameSize: size,
        paperBackground: ProjectBackground.white,
        pasteboardColor: const Color(0xFFFFFFFF),
        paintLetterbox: false,
        fadeOpacity: 0,
      );
      final (_, _, _, a) = await pixelAt(
        painter,
        width: 4,
        height: 4,
        x: 2,
        y: 2,
      );
      expect(a, 0, reason: 'the unit thinned away entirely');
    });
  });

  testWidgets('the camera sees the PASTEBOARD past the paper\'s edge — the '
      'stage apron is part of the unit', (tester) async {
    await tester.runAsync(() async {
      // An 8-wide camera frame over a 4-wide canvas centered at x=2: the
      // right half of the frame reaches past the paper.
      const canvasSize = CanvasSize(width: 4, height: 4);
      const frameSize = CanvasSize(width: 8, height: 4);
      final painter = PlaybackFramePainter(
        image: null,
        canvasSize: canvasSize,
        cameraPose: CameraPose(center: CanvasPoint(x: 2, y: 2)),
        cameraFrameSize: frameSize,
        paperBackground: ProjectBackground.white,
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
