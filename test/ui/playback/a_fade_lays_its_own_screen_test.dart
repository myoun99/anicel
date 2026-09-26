import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';

/// 🗣️F-192 (유저 2026-09-27): 「컷의 페이드인은 애초에 쌩 검은화면에서
/// 바뀐단거였음. 화이트인은 쌩 흰화면에서 바뀌는거고 … 백그라운드색을
/// 바꾸는거말고 구조적으로」.
///
/// The playback and export stack's one painter lays a one-sided transition's
/// screen over the cut's whole unit. What lies BEHIND the unit — here a red
/// that no fade would ever be — must not show through it.
void main() {
  const size = CanvasSize(width: 4, height: 4);
  const behind = Color(0xFFFF0000);

  Future<(int, int, int, int)> centreOf(PlaybackFramePainter painter) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = behind);
    painter.paint(canvas, const Size(4, 4));
    final picture = recorder.endRecording();
    final image = await picture.toImage(4, 4);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    const offset = (2 * 4 + 2) * 4;
    return (
      bytes!.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
      bytes.getUint8(offset + 3),
    );
  }

  /// A green unit — the apron fills the camera frame — in front of [behind].
  PlaybackFramePainter unit({
    required List<({int color, double opacity})> veils,
  }) => PlaybackFramePainter(
    image: null,
    canvasSize: size,
    cameraPose: CameraPose(center: CanvasPoint(x: 2, y: 2)),
    cameraFrameSize: size,
    paintPaper: false,
    pasteboardColor: const Color(0xFF00FF00),
    paintLetterbox: false,
    veils: veils,
  );

  testWidgets('a closed F.O is solid black — not what lies behind', (
    tester,
  ) async {
    await tester.runAsync(() async {
      expect(
        await centreOf(unit(veils: const [(color: 0xFF000000, opacity: 1)])),
        (0, 0, 0, 255),
      );
    });
  });

  testWidgets('a W.I halfway is the picture half-covered by WHITE', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final (r, g, b, a) = await centreOf(
        unit(veils: const [(color: 0xFFFFFFFF, opacity: 0.5)]),
      );
      expect(a, 255);
      expect(r, closeTo(128, 2), reason: 'white over green, never the red');
      expect(g, 255);
      expect(b, closeTo(128, 2));
    });
  });

  testWidgets('no screen, no change — the unit as it was', (tester) async {
    await tester.runAsync(() async {
      expect(await centreOf(unit(veils: const [])), (0, 255, 0, 255));
    });
  });
}
