import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/ui/export/export_preview_document.dart';
import 'package:anicel/src/ui/export/offscreen_raster.dart';

/// The file the export window would write, as a document the viewer's
/// machinery shows (F-289): its pages are the pixels their files are
/// written at, and each is rendered at the size it is asked at.
void main() {
  ExportPreviewDocument document({
    required Future<ui.Image?> Function(int page, CanvasSize size) renderAt,
  }) => ExportPreviewDocument(
    subject: 'file',
    look: 'plain',
    shape: ExportPreviewShape.single,
    pageCount: 2,
    sizeOf: (page) => page == 0
        ? const CanvasSize(width: 32, height: 18)
        : const CanvasSize(width: 8, height: 8),
    renderAt: renderAt,
  );

  test('a page\'s size is the pixels its file is written at — a page each', () {
    final shown = document(renderAt: (_, _) async => null);
    expect(shown.pageSize(0), const ui.Size(32, 18));
    expect(shown.pageSize(1), const ui.Size(8, 8));
    expect(shown.framesPerSecond, isNull);
  });

  testWidgets('a page is rendered at the size it is asked at', (tester) async {
    final asks = <(int, CanvasSize)>[];
    final shown = document(
      renderAt: (page, size) {
        asks.add((page, size));
        return rasterizeOffscreen(
          width: size.width,
          height: size.height,
          paint: (_) {},
        );
      },
    );
    final image = await tester.runAsync(
      () => shown.renderPage(1, width: 4, height: 2),
    );
    addTearDown(image!.dispose);
    expect(asks, [(1, const CanvasSize(width: 4, height: 2))]);
    expect((image.width, image.height), (4, 2));
  });

  testWidgets('a page with nothing on it lands as a CLEAR picture — a page '
      'that was drawn, with what stands under it showing', (tester) async {
    final shown = document(renderAt: (_, _) async => null);
    final bytes = await tester.runAsync(() async {
      final image = await shown.renderPage(0, width: 32, height: 18);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    expect(bytes, isNotEmpty);
    expect(bytes!.every((byte) => byte == 0), isTrue);
  });
}
