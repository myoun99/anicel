import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_range_mask.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';

/// The mask a held fill's range is marked under on the engine is made once
/// for as long as the range lasts — a press pushing its checker marks the
/// same cover, and uploads nothing again — and let go by the first frame
/// that marks none (flip lane ⓐ-3), as the engine's count of what it holds
/// says; a mask is made of its box's bytes alone.
void main() {
  late GpuComposite composite;
  setUpAll(() => composite = GpuComposite(appGpuEngine));
  tearDownAll(() => composite.free());

  FloodFillRegion cover() => FloodFillRegion(
    left: 3,
    top: 2,
    width: 5,
    height: 2,
    mask: Uint8List(10)..fillRange(0, 10, 255),
  );

  EngineRangeMask masks() {
    final masks = EngineRangeMask(composite);
    addTearDown(masks.free);
    return masks;
  }

  /// What the engine holds of masks the app keeps, past what it held at
  /// [before] — counted where it makes and frees them.
  int heldSince(int before) => GpuMask.liveBytes - before;

  /// A mask of [cover]'s 5 × 2: two words a row, two rows.
  const plane = 2 * 4 * 2;

  test('a cover marked frame after frame is marked under one mask', () {
    final before = GpuMask.liveBytes;
    final kept = masks();
    final range = cover();
    final first = kept.of(range);
    kept.settle();

    expect(kept.of(range), same(first));
    expect(heldSince(before), plane);
  });

  test('another range is marked under a mask of its own, the one before let '
      'go', () {
    final before = GpuMask.liveBytes;
    final kept = masks();
    final first = kept.of(cover());

    expect(kept.of(cover()), isNot(same(first)));
    expect(heldSince(before), plane, reason: 'one range at most');
  });

  test('a frame that marks none lets the mask go, and a frame that marks '
      'keeps it for the next', () {
    final before = GpuMask.liveBytes;
    final kept = masks();
    final range = cover();
    final first = kept.of(range);
    kept.settle();
    expect(heldSince(before), plane, reason: 'a frame that marked');
    kept.settle();
    expect(heldSince(before), 0, reason: 'a frame that marked none');

    expect(kept.of(range), isNot(same(first)));
  });

  test('freed, it holds nothing', () {
    final before = GpuMask.liveBytes;
    EngineRangeMask(composite)
      ..of(cover())
      ..free();

    expect(heldSince(before), 0);
  });

  test('a mask is refused bytes that are not its box\'s, and a box of no '
      'pixel with the engine\'s reason', () {
    expect(
      () => GpuMask(composite, Uint8List(9), x: 0, y: 0, width: 2, height: 5),
      throwsArgumentError,
    );
    expect(
      () => GpuMask(composite, Uint8List(0), x: 0, y: 0, width: 0, height: 3),
      throwsA(
        isA<StateError>().having((e) => e.message, 'why', contains('pixel')),
      ),
    );
  });
}
