import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';

/// 🚨F-114: an ABSENT paper is the checkerboard ON SCREEN — the playback
/// views draw it the way the editing canvas does (유저 2026-09-15: 「없음버튼
/// 누르면 없는상태. 즉 해당 용지부분이 체크무늬되도록」) — and nothing at all in
/// an export, which paints through the same painter without the flag.
void main() {
  const canvasSize = CanvasSize(width: 32, height: 32);
  const absent = ProjectBackground.color(0xFF3366CC, none: true);

  Future<Uint8List> paint(
    WidgetTester tester,
    PlaybackFramePainter painter,
  ) async {
    final bytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(32, 32));
      final picture = recorder.endRecording();
      final image = picture.toImageSync(32, 32);
      picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  List<int> rgbaAt(Uint8List bytes, int x, int y) {
    final i = (y * 32 + x) * 4;
    return bytes.sublist(i, i + 4);
  }

  testWidgets('on screen the page is the checkerboard, not the kept colour', (
    tester,
  ) async {
    final bytes = await paint(
      tester,
      const PlaybackFramePainter(
        image: null,
        canvasSize: canvasSize,
        paperBackground: absent,
        checkersAbsentPlanes: true,
      ),
    );
    // Eight-pixel cells from the page's corner: a white cell, then a grey.
    expect(rgbaAt(bytes, 4, 4), [255, 255, 255, 255]);
    expect(rgbaAt(bytes, 12, 4), [0xCC, 0xCC, 0xCC, 255]);
  });

  testWidgets('in an export the absent page paints nothing', (tester) async {
    final bytes = await paint(
      tester,
      const PlaybackFramePainter(
        image: null,
        canvasSize: canvasSize,
        paperBackground: absent,
      ),
    );
    expect(rgbaAt(bytes, 4, 4)[3], 0);
    expect(rgbaAt(bytes, 12, 4)[3], 0);
  });

  testWidgets('an absent APRON checkers the camera frame on screen, prints '
      'nothing, and a present one paints its colour', (tester) async {
    // A 32px page centred in a 64px camera frame: the corner is apron.
    Future<Uint8List> frame({
      required bool none,
      required bool onScreen,
    }) async {
      final recorder = ui.PictureRecorder();
      final painter = PlaybackFramePainter(
        image: null,
        canvasSize: canvasSize,
        cameraPose: CameraPose(center: CanvasPoint(x: 16, y: 16)),
        cameraFrameSize: const CanvasSize(width: 64, height: 64),
        pasteboardColor: const Color(0xFF123456),
        pasteboardNone: none,
        checkersAbsentPlanes: onScreen,
        paintLetterbox: false,
      );
      final bytes = await tester.runAsync(() async {
        painter.paint(Canvas(recorder), const Size(64, 64));
        final picture = recorder.endRecording();
        final image = picture.toImageSync(64, 64);
        picture.dispose();
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return data!.buffer.asUint8List();
      });
      return bytes!;
    }

    List<int> at(Uint8List bytes, int x, int y) {
      final i = (y * 64 + x) * 4;
      return bytes.sublist(i, i + 4);
    }

    final present = await frame(none: false, onScreen: true);
    expect(at(present, 2, 2), [0x12, 0x34, 0x56, 255], reason: 'control');
    final absent = await frame(none: true, onScreen: true);
    expect(at(absent, 2, 2), [255, 255, 255, 255]);
    expect(at(absent, 10, 2), [0xCC, 0xCC, 0xCC, 255]);
    final printed = await frame(none: true, onScreen: false);
    expect(at(printed, 2, 2)[3], 0);
  });

  testWidgets('control: the same page present paints its colour', (
    tester,
  ) async {
    final bytes = await paint(
      tester,
      const PlaybackFramePainter(
        image: null,
        canvasSize: canvasSize,
        paperBackground: ProjectBackground.color(0xFF3366CC),
        checkersAbsentPlanes: true,
      ),
    );
    expect(rgbaAt(bytes, 4, 4), [0x33, 0x66, 0xCC, 255]);
  });
}
