import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/ui/canvas/guide_overlay.dart';

/// 🚨A vanishing point at infinity is a family of parallel LINES across the
/// whole view, and they turn with the paper (vanishing-point-types,
/// 2026-10-16). Each line of the family left its anchor one way only — the
/// anchors stand on the line through the view's middle — so 「정확히
/// 수직으로」 drew its verticals below the middle of the view alone; and the
/// family's canvas direction was drawn on the screen unturned.
///
/// ⚠️These RENDER the painter. The view is quiet (not the guide tool's), so
/// no handle and no name is drawn, and the eye level is hidden: what ink
/// there is, is the family's.
void main() {
  const size = ui.Size(300, 200);

  GuideOverlayPainter painterFor(
    VanishingPoint family, {
    CanvasViewport? viewport,
  }) => GuideOverlayPainter(
    guides: CutGuides(
      guides: [
        DrawingGuide(
          id: const GuideId('per'),
          name: '퍼스 1',
          shape: PerspectiveShape(
            eyeLevel: GuideAxis(
              origin: CanvasPoint(x: 150, y: 100),
              angleDegrees: 0,
            ),
            eyeLevelVisible: false,
            vanishingPoints: [family],
          ),
        ),
      ],
    ),
    viewport: viewport ?? CanvasViewport(),
    canvasSize: const CanvasSize(width: 300, height: 200),
    emphasized: false,
    color: const Color(0xFF00FF00),
    face: const TextStyle(),
    vanishingPointLabel: 'VP',
  );

  Future<ByteData> render(
    WidgetTester tester,
    GuideOverlayPainter painter,
  ) async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), size);
    final picture = recorder.endRecording();
    // ⚠️`runAsync`: outside it the fake clock never lets the rasterizer
    // finish and the future simply never completes — a hang, not a failure.
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

  bool inked(ByteData data, int x, int y) =>
      data.getUint8((y * size.width.toInt() + x) * 4 + 3) != 0;

  /// The inked pixels inside [rect].
  int inkIn(ByteData data, Rect rect) {
    var count = 0;
    for (var y = rect.top.toInt(); y < rect.bottom.toInt(); y += 1) {
      for (var x = rect.left.toInt(); x < rect.right.toInt(); x += 1) {
        if (inked(data, x, y)) count += 1;
      }
    }
    return count;
  }

  /// The rows a line runs the whole width of — a family lying across.
  int rowsAcross(ByteData data) => [
    for (var y = 0; y < size.height.toInt(); y += 1)
      if ([
        for (var x = 0; x < size.width.toInt(); x += 1) inked(data, x, y),
      ].every((ink) => ink))
        y,
  ].length;

  /// The columns a line runs the whole height of — a family standing up.
  int columnsDown(ByteData data) => [
    for (var x = 0; x < size.width.toInt(); x += 1)
      if ([
        for (var y = 0; y < size.height.toInt(); y += 1) inked(data, x, y),
      ].every((ink) => ink))
        x,
  ].length;

  testWidgets('a vertical family stands above the middle of the view as '
      'well as below it', (tester) async {
    final data = await render(
      tester,
      painterFor(VanishingPointTowards(dx: 0, dy: 1)),
    );

    expect(
      inkIn(data, const Rect.fromLTRB(0, 100, 300, 200)),
      greaterThan(0),
      reason: '⛔fixture: the family is drawn below the middle',
    );
    expect(inkIn(data, const Rect.fromLTRB(0, 0, 300, 100)), greaterThan(0));
    expect(columnsDown(data), greaterThan(0));
  });

  testWidgets('a lying family reaches left of the middle as well as right', (
    tester,
  ) async {
    final data = await render(
      tester,
      painterFor(VanishingPointTowards(dx: 1, dy: 0)),
    );

    expect(
      inkIn(data, const Rect.fromLTRB(150, 0, 300, 200)),
      greaterThan(0),
      reason: '⛔fixture: the family is drawn right of the middle',
    );
    expect(inkIn(data, const Rect.fromLTRB(0, 0, 150, 200)), greaterThan(0));
    expect(rowsAcross(data), greaterThan(0));
  });

  testWidgets('🚨a vertical family on a view turned a quarter lies across '
      'the screen — it turns with the paper', (tester) async {
    final upright = await render(
      tester,
      painterFor(VanishingPointTowards(dx: 0, dy: 1)),
    );
    expect(
      columnsDown(upright),
      greaterThan(0),
      reason: '⛔control: unturned, the family stands up',
    );
    expect(rowsAcross(upright), 0, reason: '⛔control: and lies nowhere');

    final turned = await render(
      tester,
      painterFor(
        VanishingPointTowards(dx: 0, dy: 1),
        viewport: CanvasViewport(rotationDegrees: 90),
      ),
    );

    expect(columnsDown(turned), 0);
    expect(rowsAcross(turned), greaterThan(0));
  });
}
