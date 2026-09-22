import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/canvas/selection_ants_painter.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// H28 — 유저 2026-08-27 실기: 「변경사항이 있으면 변형툴 ui? 실루엣을 다른
/// 색으로. 예를들어 빨간색? 그러고 변형된 상황. 변경된게 없으면 초록색으로」.
///
/// The ants and the confirm button already answered that way. The transform
/// box — the SILHOUETTE the user is looking at while dragging — did not: it
/// was a fixed blue, because all three carried their own copy of the pair.
///
/// So the assertion is not 「the box is red」 but 「the box says the same
/// thing the ants say」. That is what stops a fourth copy appearing.
void main() {
  const size = Size(120, 120);

  /// A box with a handle at each corner.
  const chrome = (
    box: [Offset(30, 30), Offset(90, 30), Offset(90, 90), Offset(30, 90)],
    handles: [Offset(30, 30), Offset(90, 30), Offset(90, 90), Offset(30, 90)],
  );

  /// 🚨The readback runs under `runAsync`. `toImage` needs the real event
  /// loop, and a widget test's fake clock simply never delivers it — the
  /// test hangs to the harness timeout rather than failing.
  Future<Uint8List> paint(
    WidgetTester tester, {
    required bool changed,
  }) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);
    final painter = SelectionAntsPainter(
      repaint: controller,
      viewport: CanvasViewport(),
      committedRegion: null,
      screenOffset: Offset.zero,
      marqueeShapes: const [],
      openTrail: const [],
      transformChrome: chrome,
      sessionHasChanges: changed,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder, Offset.zero & size), size);
    final picture = recorder.endRecording();
    final bytes = await tester.runAsync(() async {
      final image = await picture.toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    picture.dispose();
    return bytes!;
  }

  /// The most saturated pixel on the box's top edge, away from the corner
  /// handles (those are filled white with a stroked border, so sampling one
  /// would measure the handle rather than the silhouette).
  ///
  /// 🚨★★★**UN-PREMULTIPLIED, AND THAT IS THE MEASUREMENT.** The readback
  /// arrives premultiplied, so a 1.5px stroke's edge pixel is the colour
  /// times its coverage — (192,51,51) for a law of (255,68,68) at 75%.
  /// ↩️This compared the raw bytes and got away with it only because a
  /// filled circle — the rotate knob's — happened to sit in the band at
  /// full coverage. 유저 had that knob deleted on 2026-09-22, and what
  /// was left was an anti-aliased line the old tolerance called a
  /// different colour. Dividing by alpha asks the question the pin
  /// actually means, and asks it exactly.
  (int, int, int) edgeInk(Uint8List rgba) {
    var best = (0, 0, 0);
    var bestSum = -1;
    for (var x = 45; x < 76; x += 1) {
      for (var y = 28; y < 33; y += 1) {
        final o = (y * size.width.toInt() + x) * 4;
        final alpha = rgba[o + 3];
        if (alpha < 0x80) continue;
        int straight(int channel) => (channel * 255 / alpha).round();
        final pixel = (straight(rgba[o]), straight(rgba[o + 1]), straight(rgba[o + 2]));
        final sum = pixel.$1 + pixel.$2 + pixel.$3;
        if (sum > bestSum && (pixel.$1 > 0x60 || pixel.$2 > 0x60)) {
          bestSum = sum;
          best = pixel;
        }
      }
    }
    expect(bestSum, greaterThanOrEqualTo(0), reason: 'the box drew an edge');
    return best;
  }

  test('the two session colours are a red and a green, and they differ', () {
    final changed = AppColors.selectionSession(changed: true);
    final settled = AppColors.selectionSession(changed: false);
    expect(changed, isNot(settled));
    expect(changed.r, greaterThan(changed.g));
    expect(settled.g, greaterThan(settled.r));
  });

  testWidgets('the transform SILHOUETTE turns red once the session holds '
      'changes, and is green when it does not', (tester) async {
    final red = edgeInk(await paint(tester, changed: true));
    final green = edgeInk(await paint(tester, changed: false));

    expect(
      red.$1,
      greaterThan(red.$2),
      reason: 'changed = red — 유저: 「변경사항이 있으면 … 빨간색」',
    );
    expect(
      green.$2,
      greaterThan(green.$1),
      reason: 'unchanged = green — 유저: 「변경된게 없으면 초록색으로」',
    );
  });

  testWidgets('the box and the ants are drawn in the SAME colour — one '
      'question gets one answer', (tester) async {
    // ⛔The box used to be a fixed blue while the ants were red or green.
    // Sampling both out of the same picture is what makes a fourth private
    // constant impossible to add quietly.
    for (final changed in [true, false]) {
      final ink = edgeInk(await paint(tester, changed: changed));
      final law = AppColors.selectionSession(changed: changed);
      expect(
        (ink.$1 - (law.r * 255).round()).abs(),
        lessThan(0x30),
        reason: 'the silhouette draws the session law, not a colour of its '
            'own (changed: $changed)',
      );
      expect(
        (ink.$2 - (law.g * 255).round()).abs(),
        lessThan(0x30),
        reason: 'changed: $changed',
      );
    }
  });
}
