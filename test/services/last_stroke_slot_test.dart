import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/last_stroke_slot.dart';

/// What 확정 holds between strokes (confirm-button) — the pixels to lay
/// down again, and nothing that belongs to the cel they came from.
void main() {
  BrushDab dab({BrushStampImage? stamp, double x = 4}) => BrushDab(
    center: CanvasPoint(x: x, y: 4),
    color: 0xFF000000,
    size: 2,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: 0,
    stamp: stamp,
  );

  test('it keeps what lays the stroke down again, and lets the promotion go '
      '— those tiles were blended against the cel it left', () {
    final slot = LastStrokeSlot();
    addTearDown(slot.dispose);
    final pixels = Uint8List(16);
    final bounds = DirtyRegion(
      left: 0,
      top: 0,
      rightExclusive: 2,
      bottomExclusive: 2,
    );
    slot.hold(
      BrushStrokeCommitData(
        sourceDabs: [dab()],
        strokePixels: pixels,
        strokeBounds: bounds,
        blendMode: BrushBlendMode.erase,
        strokeOpacity: 0.5,
        promotedBase: BitmapSurface(
          canvasSize: const CanvasSize(width: 8, height: 8),
        ),
        promotedTiles: const [],
      ),
    );

    final held = slot.stroke!;
    expect(held.sourceDabs, hasLength(1));
    expect(identical(held.strokePixels, pixels), isTrue);
    expect(held.strokeBounds, bounds);
    expect(held.blendMode, BrushBlendMode.erase, reason: '지우개면 지우개로');
    expect(held.strokeOpacity, 0.5);
    expect(held.promotedBase, isNull, reason: '⛔떠난 셀의 그림을 붙잡지 않는다');
    expect(held.promotedTiles, isNull);
  });

  test('its bytes are its pixels and each picture its dabs stamp, once', () {
    final slot = LastStrokeSlot();
    addTearDown(slot.dispose);
    final stamp = BrushStampImage(
      id: 'piece',
      width: 2,
      height: 2,
      rgba: Uint8List(16),
    );
    slot.hold(
      BrushStrokeCommitData(
        sourceDabs: [dab(stamp: stamp), dab(stamp: stamp, x: 6)],
        strokePixels: Uint8List(40),
      ),
    );
    expect(slot.strokeBytes, 40 + 16, reason: '같은 그림을 찍은 둘은 한 번');
  });

  test('a canvas coming or going is news — the ↵ has to hear it', () async {
    final slot = LastStrokeSlot();
    addTearDown(slot.dispose);
    slot.hold(BrushStrokeCommitData(sourceDabs: [dab()]));
    var heard = 0;
    slot.addListener(() => heard += 1);

    expect(slot.canReinput, isFalse, reason: '받을 캔버스가 없다');
    slot.reinputHandler = () {};
    await Future<void>.delayed(Duration.zero);
    expect(slot.canReinput, isTrue);
    expect(heard, 1);

    slot.reinputHandler = null;
    await Future<void>.delayed(Duration.zero);
    expect(slot.canReinput, isFalse);
    expect(heard, 2);
  });
}
