import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/sheet_canvas_panel.dart';
import 'package:anicel/src/ui/canvas/viewport_canvas_transform.dart';
import 'package:anicel/src/ui/effective_device_pixel_ratio.dart';

/// The paper panel the four sheets mount: no coordinator, no frame keys,
/// no rotation, and the viewport handed to the content SNAPPED ONCE (P8,
/// 유저 답 `host` 2026-08-28) — so a page painter and an ink window over it
/// cannot land on different device pixels.
void main() {
  testWidgets('the content receives the viewport snapped to the device grid, '
      'and the shell is the sheets\' recipe', (tester) async {
    final sink = BrushEditCacheInvalidationSink();
    final raw = CanvasViewport(zoom: 1, panX: 10.3, panY: 4.7);
    CanvasViewport? received;
    double? ratio;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SheetCanvasPanel(
            cacheInvalidationSink: sink,
            canvasSize: const CanvasSize(width: 200, height: 100),
            viewport: raw,
            content: (context, viewport) {
              received = viewport;
              ratio = EffectiveDevicePixelRatio.of(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(received, isNotNull);
    // The shell fits and clamps the raw view first; whatever it lands on,
    // the content sees it snapped — snapping again changes nothing.
    expect(received, renderSnappedViewport(received!, ratio!));
    expect(
      (received!.panX * ratio!).roundToDouble(),
      received!.panX * ratio!,
      reason: 'the pan lands on a whole device pixel',
    );

    final shell = tester.widget<BrushCanvasPanel>(
      find.byType(BrushCanvasPanel),
    );
    expect(shell.coordinator, isNull);
    expect(shell.availableFrameKeys, isEmpty);
    expect(shell.allowViewRotation, isFalse);
    expect(identical(shell.cacheInvalidationSink, sink), isTrue);
  });
}
