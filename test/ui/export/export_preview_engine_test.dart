import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/export/export_preview_engine.dart';

void main() {
  Future<ui.Image> makeImage() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 1, 1),
      ui.Paint()..color = const ui.Color(0xFF000000),
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(1, 1);
    } finally {
      picture.dispose();
    }
  }

  test('previewOutputSize fits without upscaling', () {
    expect(
      previewOutputSize(
        sourceWidth: 1920,
        sourceHeight: 1080,
        maxWidth: 320,
        maxHeight: 300,
      ),
      (width: 320, height: 180),
    );
    expect(
      previewOutputSize(
        sourceWidth: 100,
        sourceHeight: 400,
        maxWidth: 320,
        maxHeight: 200,
      ),
      (width: 50, height: 200),
    );
    // Small sources render 1:1.
    expect(
      previewOutputSize(
        sourceWidth: 64,
        sourceHeight: 48,
        maxWidth: 320,
        maxHeight: 300,
      ),
      isNull,
    );
  });

  testWidgets('debounce is latest-wins: only the newest request renders',
      (tester) async {
    final controller = ExportPreviewController(
      debounce: const Duration(milliseconds: 30),
    );
    addTearDown(controller.dispose);
    var aRenders = 0;
    var bRenders = 0;
    controller.request(
      key: 'a',
      caption: 'A',
      render: () async {
        aRenders += 1;
        return null;
      },
    );
    controller.request(
      key: 'b',
      caption: 'B',
      render: () async {
        bRenders += 1;
        return null;
      },
    );
    await tester.pump(const Duration(milliseconds: 40));
    expect(aRenders, 0);
    expect(bRenders, 1);
    expect(controller.caption, 'B');
    expect(controller.image, isNull);
  });

  testWidgets('cache hit lands immediately; eviction forgets the oldest; '
      'clear() forgets everything', (tester) async {
    await tester.runAsync(() async {
      final controller = ExportPreviewController(
        debounce: const Duration(milliseconds: 1),
        capacity: 2,
      );
      final renders = <String, int>{};
      Future<void> requestAndSettle(String key) async {
        controller.request(
          key: key,
          caption: key,
          render: () async {
            renders[key] = (renders[key] ?? 0) + 1;
            return makeImage();
          },
        );
        await controller.debugFlushPending();
      }

      await requestAndSettle('k1');
      expect(renders['k1'], 1);
      expect(controller.image, isNotNull);

      // A repeat of k1 is a cache hit — no new render.
      await requestAndSettle('k1');
      expect(renders['k1'], 1);

      // k2, k3 push k1 out (capacity 2); k1 renders again on return.
      await requestAndSettle('k2');
      await requestAndSettle('k3');
      await requestAndSettle('k1');
      expect(renders['k1'], 2);

      // The on-screen picture survives eviction pressure: k1 is current
      // and stays usable even as k2 re-renders around it.
      expect(controller.image, isNotNull);
      expect(controller.caption, 'k1');

      controller.clear();
      expect(controller.image, isNull);
      await requestAndSettle('k3');
      expect(renders['k3'], 2);

      controller.dispose();
    });
  });
}
