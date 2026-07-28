import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/canvas/deferred_image_disposal.dart';

/// Retired display images must outlive the frames that may still reference
/// them: disposing an image in step with its replacement races the raster
/// thread and intermittently flashed the tile black for one frame.
void main() {
  Future<ui.Image> makeImage(WidgetTester tester) async {
    final image = await tester.runAsync(() {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 1, 1),
        Paint()..color = const Color(0xFF123456),
      );
      final picture = recorder.endRecording();
      final decoded = picture.toImage(1, 1);
      picture.dispose();
      return decoded;
    });
    return image!;
  }

  testWidgets('a retired image survives the next two frame boundaries', (
    tester,
  ) async {
    final disposer = DeferredImageDisposer();
    final image = await makeImage(tester);

    disposer.retire(image);
    expect(image.debugDisposed, isFalse);

    await tester.pump();
    expect(image.debugDisposed, isFalse);
    await tester.pump();
    expect(image.debugDisposed, isFalse);
  });

  testWidgets('a retired image is disposed after enough frame boundaries', (
    tester,
  ) async {
    final disposer = DeferredImageDisposer();
    final image = await makeImage(tester);

    disposer.retire(image);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(image.debugDisposed, isTrue);
  });

  testWidgets('images retired on different frames age independently', (
    tester,
  ) async {
    final disposer = DeferredImageDisposer();
    final first = await makeImage(tester);
    final second = await makeImage(tester);

    disposer.retire(first);
    await tester.pump();
    disposer.retire(second);
    await tester.pump();
    await tester.pump();

    expect(first.debugDisposed, isTrue);
    expect(second.debugDisposed, isFalse);

    await tester.pump();
    expect(second.debugDisposed, isTrue);
  });
}
