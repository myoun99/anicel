import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/ui/sheet/sheet_photo_drop.dart';

/// I-97 Q2 c (유저 2026-10-15): a pool picture dropped on a sheet's cell
/// stands at its own pixels — a pixel of the picture a pixel of the ink —
/// shrunk to fit the cell where it is larger, centred where it was dropped.
void main() {
  // A cell 100×50 of paper at two ink pixels a unit: 200×100 of its ink,
  // its surface starting 10 pixels in.
  const placement = SheetInkPlacement(
    window: Rect.fromLTWH(30, 40, 100, 50),
    scale: 2,
    origin: Offset(10, 0),
  );
  const dropped = Offset(55, 60);

  test('a picture smaller than its cell stands at its own pixels, its '
      'centre where it was dropped', () {
    final photo = droppedSheetPhoto(
      path: 'C:/pool/small.png',
      picture: const CanvasSize(width: 40, height: 30),
      placement: placement,
      paper: dropped,
    );

    expect(photo.assetPath, 'C:/pool/small.png');
    expect(photo.pictureSize, const CanvasSize(width: 40, height: 30));
    expect((photo.pose.scaleX, photo.pose.scaleY), (1.0, 1.0));
    final at = placement.pixelOf(dropped);
    expect(photo.pose.center, CanvasPoint(x: at.dx, y: at.dy));
  });

  test('one larger than its cell on either axis is shrunk to fit it, its '
      'shape kept — and never grown', () {
    final wide = droppedSheetPhoto(
      path: 'C:/pool/wide.png',
      picture: const CanvasSize(width: 800, height: 100),
      placement: placement,
      paper: dropped,
    );
    final tall = droppedSheetPhoto(
      path: 'C:/pool/tall.png',
      picture: const CanvasSize(width: 50, height: 400),
      placement: placement,
      paper: dropped,
    );

    expect((wide.pose.scaleX, wide.pose.scaleY), (0.25, 0.25));
    expect((tall.pose.scaleX, tall.pose.scaleY), (0.25, 0.25));
    final at = placement.pixelOf(dropped);
    expect(wide.pose.center, CanvasPoint(x: at.dx, y: at.dy));
  });
}
