import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/dirty_region.dart';

/// The stamp's landing rect is ONE arithmetic (round 8 of the audit): the
/// commit's stamp blend, the fill preview, the float hold and the
/// landed-ink painter all used to spell `(centre - size / 2).round()` by
/// hand, and the float hold's comment confessed it — "by the same
/// arithmetic the stamp blend uses".
void main() {
  BrushStampImage stamp({required int width, required int height}) =>
      BrushStampImage(
        id: 'stamp',
        width: width,
        height: height,
        rgba: Uint8List(width * height * 4),
      );

  group('BrushStampImage.landingRect', () {
    test('is the integer top-left ROUNDED from the centre, one stamp size '
        'wide and tall', () {
      // width 3: 5 - 1.5 = 3.5 rounds AWAY from zero to 4; height 4: 5 - 2
      // = 3 exactly.
      expect(
        stamp(width: 3, height: 4).landingRect(CanvasPoint(x: 5, y: 5)),
        DirtyRegion(left: 4, top: 3, rightExclusive: 7, bottomExclusive: 7),
      );
    });

    test('a dab centred at left + w/2, top + h/2 lands EXACTLY at (left, '
        'top) — the lift-then-drop round trip', () {
      final image = stamp(width: 7, height: 5);
      for (final (left, top) in const [(0, 0), (13, 4), (-9, -21), (100, 3)]) {
        expect(
          image.landingRect(CanvasPoint(x: left + 7 / 2, y: top + 5 / 2)),
          DirtyRegion(
            left: left,
            top: top,
            rightExclusive: left + 7,
            bottomExclusive: top + 5,
          ),
          reason: 'placed at ($left, $top)',
        );
      }
    });

    test('lands in the PASTEBOARD too: negative coordinates round the same '
        'way', () {
      // -1.5 - 1 = -2.5 rounds away from zero to -3.
      expect(
        stamp(width: 2, height: 2).landingRect(CanvasPoint(x: -1.5, y: -2)),
        DirtyRegion(left: -3, top: -3, rightExclusive: -1, bottomExclusive: -1),
      );
    });
  });
}
