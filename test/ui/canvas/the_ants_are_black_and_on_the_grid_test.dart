import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/ui/canvas/selection_ants_painter.dart';

/// 🚨★★★유저 (F-65): 「선택툴의 개미행렬 색을 앱 강조색이아니라 **검정색으로.
/// 그러니 흰색바탕에 검정 개미가 지나가도록**. 앞으로 개미행렬은 이 공통 ui를
/// 사용 / 라이브로 선택중일땐 선이 픽셀에 안착안된 벡터로 보여도 상관없는데,
/// **선택 커밋될떈 픽셀에 제대로 안착한 상태로**. 지금은 **변형되는 픽셀
/// 범위와 개미행렬 위치가 다르다**」.
///
/// ⚠️These RENDER the painter rather than reading its fields. What the user
/// reported is where the line lands on screen, and a field says nothing
/// about that — the sibling unit tests next door already pin the geometry
/// the painter asks for.
void main() {
  const zoom = 16.0;

  CanvasSelectionRegion fractionalRect() => CanvasSelectionRegion([
    CanvasSelectionStep.copies([
      CanvasSelectionShape.rect(
        left: 10.3,
        top: 20.7,
        right: 30.4,
        bottom: 40.2,
      ),
    ], SelectionCombineMode.replace),
  ]);

  /// ⚠️`toImage`/`toByteData` under [WidgetTester.runAsync]. Outside it the
  /// test binding's fake clock never lets the rasterizer finish and the
  /// future simply never completes — 🧪measured: a plain `await` here sat
  /// until the 10-minute test timeout. The parity test next door already
  /// says this; it is repeated because the symptom is a hang rather than a
  /// failure, and a hang teaches nothing.
  Future<ByteData> render(
    WidgetTester tester,
    SelectionAntsPainter painter,
    ui.Size size,
  ) async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), size);
    final picture = recorder.endRecording();
    final bytes = await tester.runAsync(() async {
      final image = await picture.toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data;
    });
    picture.dispose();
    return bytes!;
  }

  SelectionAntsPainter antsFor(
    CanvasSelectionRegion? region, {
    bool live = false,
  }) => SelectionAntsPainter(
    repaint: const AlwaysStoppedAnimation<double>(0),
    viewport: CanvasViewport(zoom: zoom),
    committedRegion: region,
    screenOffset: Offset.zero,
    marqueeShapes: const [],
    openTrail: const [],
    outlineIsLive: live,
  );

  /// The box around every pixel the painter put ink on.
  ({double left, double top, double right, double bottom})? inkBounds(
    ByteData bytes,
    int width,
    int height,
  ) {
    var left = double.infinity, top = double.infinity;
    var right = double.negativeInfinity, bottom = double.negativeInfinity;
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        if (bytes.getUint8((y * width + x) * 4 + 3) == 0) {
          continue;
        }
        if (x < left) left = x.toDouble();
        if (y < top) top = y.toDouble();
        if (x > right) right = x.toDouble();
        if (y > bottom) bottom = y.toDouble();
      }
    }
    if (left > right) {
      return null;
    }
    return (left: left, top: top, right: right, bottom: bottom);
  }

  testWidgets('the committed outline sits on the pixel grid, not on the drag', (
    tester,
  ) async {
    const size = ui.Size(700, 700);
    final bytes = await render(tester, antsFor(fractionalRect()), size);
    final ink = inkBounds(bytes, 700, 700);

    expect(ink, isNotNull, reason: 'the painter drew something');

    // Selected pixels are x 10…29 and y 21…39, so the outline runs
    // (10, 21)–(30, 40) in canvas space = (160, 336)–(480, 640) at ×16.
    // ⛔The polygon would be (164.8, 331.2)–(486.4, 643.2) — five pixels
    // out in every direction, which is exactly what the user is seeing.
    // A 1px stroke straddles the line, hence the ±1.
    expect(ink!.left, closeTo(160, 1));
    expect(ink.top, closeTo(336, 1));
    expect(ink.right, closeTo(480, 1));
    expect(ink.bottom, closeTo(640, 1));
  });

  testWidgets('and the ants themselves are black', (tester) async {
    const size = ui.Size(700, 700);
    final bytes = await render(tester, antsFor(fractionalRect()), size);

    // The dashes are drawn OVER a solid white under-stroke, so the line
    // carries both; what must not be there is the session green or red the
    // ants used to wear.
    //
    // ⚠️Measured as NEUTRALITY rather than as two exact colours. A 1px
    // stroke on an integer boundary is half-covered everywhere, so almost
    // every pixel here is partly transparent — 🧪an earlier version filtered
    // on `alpha >= 200` and counted ZERO pixels of any colour, which is the
    // 「빈 것을 쟀다」 shape. Un-premultiplying first is what makes the hue
    // readable at any coverage.
    var dark = 0;
    var light = 0;
    var coloured = 0;
    for (var i = 0; i < 700 * 700; i += 1) {
      final a = bytes.getUint8(i * 4 + 3);
      if (a == 0) {
        continue;
      }
      final r = bytes.getUint8(i * 4) * 255 ~/ a;
      final g = bytes.getUint8(i * 4 + 1) * 255 ~/ a;
      final b = bytes.getUint8(i * 4 + 2) * 255 ~/ a;
      final high = r > g ? (r > b ? r : b) : (g > b ? g : b);
      final low = r < g ? (r < b ? r : b) : (g < b ? g : b);
      if (high - low > 24) {
        coloured += 1;
        continue;
      }
      if (high < 64) dark += 1;
      if (low > 192) light += 1;
    }

    expect(dark, greaterThan(0), reason: '「검정 개미가 지나가도록」');
    expect(
      light,
      greaterThan(0),
      reason: '「흰색바탕에」 — the under-stroke it is read against',
    );
    expect(
      coloured,
      0,
      reason:
          '⛔not one coloured pixel: the session green/red the ants used to '
          'wear would show up here as a hue no blend of black and white can '
          'produce',
    );
  });

  // 유저: 「**라이브로 선택중일땐 선이 픽셀에 안착안된 벡터로 보여도
  // 상관없는데**, 선택 커밋될떈 픽셀에 제대로 안착한 상태로」 — the other half
  // of the same sentence, and the half that keeps a transform drag cheap.
  testWidgets('a LIVE outline still traces the polygon', (tester) async {
    const size = ui.Size(700, 700);
    final bytes = await render(
      tester,
      antsFor(fractionalRect(), live: true),
      size,
    );
    final ink = inkBounds(bytes, 700, 700);

    expect(ink, isNotNull);
    // 10.3 × 16 = 164.8 and 20.7 × 16 = 331.2, against the settled
    // outline's 160 and 336 above. ⚠️±1.5: a 1px stroke straddles the line
    // and the ink lands on the pixel below it.
    expect(ink!.left, closeTo(164.8, 1.5));
    expect(ink.top, closeTo(331.2, 1.5));
  });

  testWidgets('no committed region draws no ants at all', (tester) async {
    const size = ui.Size(200, 200);
    final bytes = await render(tester, antsFor(null), size);
    expect(
      inkBounds(bytes, 200, 200),
      isNull,
      reason: 'the premise: this fixture paints nothing on its own',
    );
  });
}
