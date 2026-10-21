import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/ui/playback/camera_shot.dart';

/// [CameraShot] (playback-plays-the-screen-material ②): a run seen through
/// the camera on the canvas shows the camera's frame — the canvas's picture
/// in it on the stage's apron, everything past it letterboxed, and nothing
/// of the canvas past its own edge (the film shows no pasteboard).
void main() {
  const apron = Color(0xFF00FF00);
  const letterbox = 0xFF15191C;
  const picture = 0xFFFF0000;
  final screen = GlobalKey();

  // The camera's frame, 40×30, looking at the canvas's own coordinates: its
  // middle at (20, 15), one canvas pixel a frame pixel. The canvas, 30×20,
  // fills the frame's top left; the rest of the frame is the apron.
  final shot = (
    pose: CameraPose(center: CanvasPoint(x: 20, y: 15)),
    frameSize: const CanvasSize(width: 40, height: 30),
    frameView: CanvasViewport(),
  );

  Future<void> pumpShot(WidgetTester tester, {required bool throughIt}) {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    return tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: screen,
            child: SizedBox(
              width: 60,
              height: 40,
              child: CameraShot(
                view: CanvasViewport(),
                shot: throughIt ? shot : null,
                canvasSize: const CanvasSize(width: 30, height: 20),
                background: ProjectBackground.defaultBackground,
                pasteboardColor: apron,
                pasteboardNone: false,
                pasteboardReach: PasteboardReach.whole,
                // The canvas's picture, reaching past its own edge as
                // pasteboard artwork does.
                child: const ColoredBox(color: Color(picture)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<int Function(int x, int y)> shown(WidgetTester tester) async {
    final render =
        screen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final rgba = (await tester.runAsync<Uint8List>(() async {
      final image = await render.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
    return (int x, int y) {
      final o = (y * 60 + x) * 4;
      return (rgba[o + 3] << 24) |
          (rgba[o] << 16) |
          (rgba[o + 1] << 8) |
          rgba[o + 2];
    };
  }

  testWidgets('through the camera: the picture in the canvas, the apron in '
      'the rest of the frame, the letterbox past it', (tester) async {
    await pumpShot(tester, throughIt: true);
    final at = await shown(tester);

    expect(at(10, 10), picture, reason: 'the canvas, in the frame');
    expect(at(35, 10), apron.toARGB32(), reason: 'past the canvas\'s edge');
    expect(at(10, 25), apron.toARGB32(), reason: 'below it');
    expect(at(50, 10), letterbox, reason: 'past the frame');
    expect(at(10, 35), letterbox, reason: 'below the frame');
  });

  testWidgets('through no camera it paints nothing and cuts nothing — the '
      'canvas as it stands', (tester) async {
    await pumpShot(tester, throughIt: false);
    final at = await shown(tester);

    for (final (x, y) in [(10, 10), (35, 10), (10, 25), (50, 10), (10, 35)]) {
      expect(at(x, y), picture, reason: '($x, $y)');
    }
  });
}
