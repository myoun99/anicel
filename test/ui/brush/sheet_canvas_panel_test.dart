import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/page_stack.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/canvas_book.dart';
import 'package:anicel/src/ui/brush/sheet_canvas_panel.dart';
import 'package:anicel/src/ui/canvas/viewport_canvas_transform.dart';
import 'package:anicel/src/ui/effective_device_pixel_ratio.dart';

import '../../helpers/device_viewport.dart';

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
            sheetSize: const Size(200, 100),
            viewLimit: null,
            viewport: raw,
            // This pin is about the SNAP, and it mounts no ink.
            drawingOn: false,
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
    expect(
      shell.canvasSize,
      const CanvasSize(width: 200, height: 100),
      reason: 'a sheet laid in its paper\'s pixels: a unit is a pixel',
    );
  });

  group('🚨F-294 (유저 2026-10-05: 「타임시트 용지패널 용지크기 너무 작음」 · '
      '「dpi를 기준으로 생각할거야」) — the canvas is the paper\'s PIXELS, the '
      'sheet speaks its own units', () {
    // A two-page book in units of its own, shown 2.5 pixels a unit.
    const scale = 2.5;
    final pages = PageStack(const [Size(100, 150), Size(100, 150)]);
    const page = Rect.fromLTWH(24, 24, 100, 150);

    Future<({BrushCanvasPanel shell, CanvasViewport Function() content})>
    pump(
      WidgetTester tester, {
      ValueNotifier<CanvasViewport?>? view,
      ValueNotifier<int>? reading,
    }) async {
      CanvasViewport? received;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SheetCanvasPanel(
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              sheetSize: pages.size,
              paperScale: scale,
              viewport: null,
              viewportController: view,
              fitFocusRect: page,
              unframedFit: page,
              viewLimit: pages.paper,
              book: reading == null
                  ? null
                  : CanvasBook(pages: pages, reading: reading),
              drawingOn: false,
              content: (context, viewport) {
                received = viewport;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pump();
      return (
        shell: tester.widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel)),
        content: () => received!,
      );
    }

    testWidgets('everything a host says in its units reaches the canvas '
        'panel in pixels — the canvas, what Fit frames, where the view '
        'stops, the book', (tester) async {
      expect(pages.size, const Size(148, 380), reason: 'fixture');
      final reading = ValueNotifier<int>(0);
      addTearDown(reading.dispose);

      final (:shell, content: _) = await pump(tester, reading: reading);

      expect(shell.canvasSize, const CanvasSize(width: 370, height: 950));
      expect(shell.fitFocusRect, const Rect.fromLTWH(60, 60, 250, 375));
      expect(shell.unframedFit, const Rect.fromLTWH(60, 60, 250, 375));
      expect(shell.viewLimit, const Rect.fromLTRB(60, 60, 310, 890));
      final book = shell.book!;
      expect(identical(book.reading, reading), isTrue);
      expect(book.pages.length, 2);
      expect(book.pages.gap, PageStack.defaultGap * scale);
      expect(book.pages.pageRect(0), const Rect.fromLTWH(60, 60, 250, 375));
      expect(
        book.pages.pageRect(1),
        const Rect.fromLTWH(60, (24 + 150 + 32) * scale, 250, 375),
      );
    });

    testWidgets('the view is kept in the paper\'s pixels, and the content '
        'reads it in the sheet\'s units — the same pan, the zoom times the '
        'pixels a unit takes', (tester) async {
      final view = ValueNotifier<CanvasViewport?>(
        CanvasViewport(zoom: 0.5, panX: 0, panY: 0),
      );
      addTearDown(view.dispose);

      final (shell: _, :content) = await pump(tester, view: view);

      // The controller's units are the device's, as every canvas panel's.
      final kept = renderOf(tester, view.value!);
      final seen = content();
      expect(seen.zoom, kept.zoom * scale);
      final ratio = tester.view.devicePixelRatio;
      expect(seen.panX, closeTo(kept.panX, 0.5 / ratio + 1e-9));
      expect(seen.panY, closeTo(kept.panY, 0.5 / ratio + 1e-9));
      // A point of the sheet lands where its pixel of the paper does.
      const unit = Offset(50, 80);
      expect(
        seen.panX + seen.zoom * unit.dx,
        closeTo(kept.panX + kept.zoom * unit.dx * scale, 0.5 / ratio + 1e-9),
      );
    });
  });

  test('sheetUnitsView: the same pan, the zoom times the paper\'s pixels a '
      'unit takes — and a sheet laid in pixels reads the view as it is', () {
    final paperView = CanvasViewport(zoom: 0.4, panX: 12.5, panY: -7.25);

    final units = sheetUnitsView(paperView, 4);
    expect(units.zoom, 1.6);
    expect(units.panX, 12.5);
    expect(units.panY, -7.25);

    expect(identical(sheetUnitsView(paperView, 1), paperView), isTrue);
  });
}
