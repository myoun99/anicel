import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/canvas/static_composite_bake.dart';

/// 2026-09-11: a rasterised bake slot is one visible-rect image (~9MB at a
/// 1928×1200 view), and the memory readout never saw them. The bake now
/// counts what it holds and says so; the canvas view that owns it reports
/// that together with its display buffer.
void main() {
  testWidgets('a rasterised slot is counted, and dropping the slots '
      'uncounts it', (tester) async {
    final bake = StaticCompositeBake();
    addTearDown(bake.dispose);
    var told = 0;
    bake.onHeldBytesChanged = () => told += 1;

    void paintOnce() {
      final recorder = ui.PictureRecorder();
      bake.drawRaster(
        Canvas(recorder),
        'folder',
        const Rect.fromLTWH(0, 0, 10, 4),
        (canvas) =>
            canvas.drawRect(const Rect.fromLTWH(0, 0, 10, 4), Paint()),
      );
      recorder.endRecording().dispose();
    }

    paintOnce();
    expect(bake.heldBytes, 10 * 4 * 4, reason: '4 bytes a pixel');
    expect(told, 1);

    paintOnce();
    expect(bake.heldBytes, 10 * 4 * 4, reason: 'replayed, not held twice');
    expect(told, 1);

    bake.invalidate();
    expect(bake.heldBytes, 0);
    expect(told, 2);
  });
}
