// F-201 (유저 2026-09-27): 「스크롤 최대치가 너무 커서? 그림이 밖으로
// 빠져나가는데 좀 줄여서 캔버스패널정도로? 마지막부분이 걸칠정도면
// 충분할거같은데. 다른 미디어 뷰어 프로그램이 그러니까」 — answered `edge`
// (F-201-pan-limit-Q1: 「끝이 화면 가장자리에 딱 닿는다」).
//
// THE VIEW STOPS AT THE PAPER: the paper's edge never comes inside the
// window's, and along an axis where the paper is shorter than the window it
// stands in the middle — whatever moved the view. The drawing canvas gives
// no paper and pans as it always has.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/canvas_view_limit.dart';
import 'package:anicel/src/ui/brush/canvas_viewport_pan_metrics.dart';
import 'package:anicel/src/ui/brush/sheet_canvas_panel.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_tab_host.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';
import 'package:anicel/src/ui/widgets/app_scrollbar.dart';

import '../../helpers/canvas_pill.dart';
import '../../helpers/fake_pdf_document.dart';

void main() {
  const window = Rect.fromLTWH(0, 0, 400, 300);
  const paper = Rect.fromLTWH(24, 24, 600, 800);

  group('the law', () {
    test('past either end the view stops with the paper\'s edge on the '
        'window\'s', () {
      final early = viewHeldTo(
        CanvasViewport(panX: 900, panY: 900),
        limit: paper,
        window: window,
      );
      expect((early.panX, early.panY), (-24.0, -24.0));
      final late = viewHeldTo(
        CanvasViewport(panX: -900, panY: -900),
        limit: paper,
        window: window,
      );
      // 24 + 600 − 400 · 24 + 800 − 300
      expect((late.panX, late.panY), (-224.0, -524.0));
    });

    test('inside the ends the view is its own — the same object back', () {
      final view = CanvasViewport(panX: -100, panY: -200);
      expect(
        identical(viewHeldTo(view, limit: paper, window: window), view),
        isTrue,
      );
    });

    test('a paper shorter than the window stands in its middle', () {
      final view = viewHeldTo(
        CanvasViewport(zoom: 0.25, panX: 5, panY: 300),
        limit: paper,
        window: window,
      );
      // 150×200 from (6, 6): 200 − (6 + 75) · 150 − (6 + 100)
      expect((view.panX, view.panY), (119.0, 44.0));
    });

    test('each axis on its own: a paper narrower than the window but taller '
        'stands in the middle across and stops along', () {
      final view = viewHeldTo(
        CanvasViewport(zoom: 0.5, panX: -80, panY: 70),
        limit: paper,
        window: window,
      );
      // 300×400 from (12, 12): 200 − (12 + 150) · top on the window's top
      expect((view.panX, view.panY), (38.0, -12.0));
    });

    test('a float\'s dust past the edge is not a move', () {
      final view = CanvasViewport(panX: -24 + 1e-9, panY: -24);
      expect(
        identical(viewHeldTo(view, limit: paper, window: window), view),
        isTrue,
      );
    });

    test('a turned view holds the paper\'s silhouette, not its raw rect', () {
      final turned = CanvasViewport(rotationDegrees: 90, panX: 5000);
      final held = viewHeldTo(turned, limit: paper, window: window);
      final span = viewportSpan(Axis.horizontal, held, paper);
      expect(span.extent, closeTo(800, 1e-6), reason: '⛔전제: turned');
      expect(
        held.panX + span.start,
        closeTo(window.left, 1e-6),
        reason: 'its left edge on the window\'s',
      );
    });
  });

  group('the pan bars span the paper and nothing past it', () {
    CanvasViewportPanMetrics bar(Axis axis, CanvasViewport viewport) =>
        CanvasViewportPanMetrics(
          axis: axis,
          viewport: viewport,
          editorViewportSize: window.size,
          canvasSize: const CanvasSize(width: 648, height: 848),
          limit: (rect: paper, window: window),
        );

    test('their two ends are the two places the view stops', () {
      final top = bar(Axis.vertical, CanvasViewport(panY: -24));
      expect(top.maxScroll, 500, reason: '800 − 300: no runway');
      expect(top.scrollOffset, 0);
      expect(top.viewportForScroll(500).panY, -524);
      final side = bar(Axis.horizontal, CanvasViewport(panX: -224));
      expect(side.scrollOffset, 200);
      expect(side.viewportForScroll(0).panX, -24);
    });

    test('a paper shorter than the window leaves nothing to scroll', () {
      final metrics = bar(Axis.vertical, CanvasViewport(zoom: 0.25));
      expect(metrics.maxScroll, 0);
    });
  });

  group('every road that moves the view ends held', () {
    /// A 400×300 sheet over a 648×848 canvas whose paper is [paper], its
    /// view in [controller] (DEVICE units, as the workspace keeps it).
    Future<ValueNotifier<CanvasViewport?>> pumpSheet(
      WidgetTester tester, {
      Rect? limit = paper,
      Size box = const Size(400, 300),
    }) async {
      final controller = ValueNotifier<CanvasViewport?>(null);
      addTearDown(controller.dispose);
      await tester.pumpWidget(sheetIn(controller, box, limit: limit));
      await tester.pumpAndSettle();
      // 🚨The store is in DEVICE units and the painting in logical ones,
      // and the factor carries the UI scale as well as the screen's — so
      // it is MEASURED (as the playback fit's pins do): a known device
      // zoom in, the painted one out, and the view unframed again.
      controller.value = CanvasViewport(zoom: 8);
      await tester.pump();
      _ratio = 8 / painted(tester).zoom;
      controller.value = null;
      await tester.pump();
      return controller;
    }

    /// [view] (LOGICAL) as the store keeps it.
    CanvasViewport device(WidgetTester tester, CanvasViewport view) =>
        CanvasViewport(
          zoom: view.zoom * _ratio,
          panX: view.panX * _ratio,
          panY: view.panY * _ratio,
        );

    /// The store — the value the owner reads — says what the panel shows.
    void expectStoreShows(
      WidgetTester tester,
      ValueNotifier<CanvasViewport?> controller,
    ) {
      final stored = controller.value!;
      final shown = painted(tester);
      expect(stored.panX / _ratio, closeTo(shown.panX, 1e-6));
      expect(stored.panY / _ratio, closeTo(shown.panY, 1e-6));
    }

    /// The window the view is held in: the sheet's box less the lanes a
    /// docked panel's scrollbars stand in (F-209) and the pill's band
    /// across its top (유저 2026-09-30: 「판정을 알약까지 포함해서」).
    Rect windowOf(WidgetTester tester) {
      final box = tester.getSize(find.byType(CanvasViewportGestureLayer));
      return Rect.fromLTRB(
        0,
        pillBandOf(tester),
        box.width - AppScrollbarLane.wide,
        box.height - AppScrollbarLane.wide,
      );
    }

    /// The paper's corners on screen under the painted view.
    Rect paperOnScreen(WidgetTester tester) {
      final view = painted(tester);
      final topLeft = view.canvasToViewport(
        CanvasPoint(x: paper.left, y: paper.top),
      );
      final bottomRight = view.canvasToViewport(
        CanvasPoint(x: paper.right, y: paper.bottom),
      );
      return Rect.fromLTRB(
        topLeft.x,
        topLeft.y,
        bottomRight.x,
        bottomRight.y,
      );
    }

    Future<void> drag(WidgetTester tester, Offset by) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CanvasViewportGestureLayer)),
        kind: PointerDeviceKind.mouse,
      );
      for (var step = 0; step < 5; step += 1) {
        await gesture.moveBy(by / 5);
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('a drag past either end stops with the paper\'s edge on the '
        'window\'s', (tester) async {
      final controller = await pumpSheet(tester);
      controller.value = device(tester, CanvasViewport(panX: -100));
      await tester.pump();
      final shown = windowOf(tester);
      expect(shown.width, lessThan(600), reason: '⛔전제: paper wider');
      expect(shown.height, lessThan(800), reason: '⛔전제: paper taller');

      await drag(tester, const Offset(900, 900));
      expect(paperOnScreen(tester).topLeft, shown.topLeft);
      expectStoreShows(tester, controller);

      await drag(tester, const Offset(-2000, -2000));
      final on = paperOnScreen(tester);
      expect(on.right, closeTo(shown.right, 1e-6));
      expect(on.bottom, closeTo(shown.bottom, 1e-6));
      expectStoreShows(tester, controller);
    });

    testWidgets('the very frame a window changes in already shows the '
        'paper over it — not a frame later', (tester) async {
      final controller = await pumpSheet(tester);
      // The paper's right edge on the window's.
      controller.value = device(tester, CanvasViewport(panX: -224));
      await tester.pump();
      await tester.pumpWidget(sheetIn(controller, const Size(500, 300)));
      expect(
        paperOnScreen(tester).right,
        greaterThanOrEqualTo(windowOf(tester).right - 1e-6),
      );
    });

    testWidgets('an owner\'s write is held at once — the store itself reads '
        'the held view, not only the painting', (tester) async {
      final controller = await pumpSheet(tester);
      controller.value = device(tester, CanvasViewport(panX: 900, panY: 900));
      final stored = controller.value!;
      // The paper's corner on the window's: its left edge, and the top
      // just below the pill's band.
      expect(stored.panX / _ratio, closeTo(-24, 1e-6));
      expect(stored.panY / _ratio, closeTo(pillBandOf(tester) - 24, 1e-6));
    });

    testWidgets('zooming out past the paper stands it in the middle', (
      tester,
    ) async {
      final controller = await pumpSheet(tester);
      controller.value = device(tester, CanvasViewport(zoom: 0.25));
      await tester.pump();
      final on = paperOnScreen(tester);
      expect(on.center.dx, closeTo(windowOf(tester).center.dx, 1e-6));
      expect(on.center.dy, closeTo(windowOf(tester).center.dy, 1e-6));
    });

    testWidgets('a pan bar reaches the paper\'s end and no further', (
      tester,
    ) async {
      final controller = await pumpSheet(tester);
      // The paper's top on the window's, just below the pill's band.
      controller.value = device(
        tester,
        CanvasViewport(panX: -24, panY: pillBandOf(tester) - 24),
      );
      await tester.pump();
      final bar = find.byKey(
        const ValueKey<String>('canvas-viewport-vertical-scrollbar'),
      );
      final scrollbar = tester.widget<AppScrollbar>(
        find.descendant(of: bar, matching: find.byType(AppScrollbar)),
      );
      expect(scrollbar.contentExtent, closeTo(800, 1e-6), reason: 'the '
          'paper, with no runway past it');
      expect(scrollbar.offset, closeTo(0, 1e-6));
      final gesture = await tester.startGesture(
        tester.getCenter(bar),
        kind: PointerDeviceKind.mouse,
      );
      for (var step = 0; step < 8; step += 1) {
        await gesture.moveBy(const Offset(0, 200));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        paperOnScreen(tester).bottom,
        closeTo(windowOf(tester).bottom, 1e-6),
      );
    });

    testWidgets('a window that changes keeps the paper over it, and the '
        'store says what it shows', (tester) async {
      final controller = await pumpSheet(tester);
      // The paper's right edge on the window's.
      controller.value = device(tester, CanvasViewport(panX: -224));
      await tester.pump();
      for (final width in const [500.0, 700.0, 300.0]) {
        await pumpSheetAgain(tester, controller, Size(width, 300));
        final shown = windowOf(tester);
        final on = paperOnScreen(tester);
        if (shown.width < 600) {
          expect(on.left, lessThanOrEqualTo(shown.left + 1e-6));
          expect(on.right, greaterThanOrEqualTo(shown.right - 1e-6));
        } else {
          expect(on.center.dx, closeTo(shown.center.dx, 1e-6));
        }
        expect(
          controller.value!.panX / _ratio,
          closeTo(painted(tester).panX, 1e-6),
          reason: 'at $width wide',
        );
      }
    });

    testWidgets('a view stored before the panel was ever laid out is '
        'held once it is — a restored view past the paper', (
      tester,
    ) async {
      final controller = await pumpSheet(tester);
      await tester.pumpWidget(const SizedBox());
      controller.value = device(tester, CanvasViewport(panX: 900));
      await pumpSheetAgain(tester, controller, const Size(400, 300));
      expect(controller.value!.panX / _ratio, closeTo(-24, 1e-6));
    });

    testWidgets('a paper that shrinks under a stored view holds it '
        'anew', (tester) async {
      final controller = await pumpSheet(tester);
      // The paper's bottom edge on the window's.
      controller.value = device(tester, CanvasViewport(panY: -524));
      await tester.pump();
      await pumpSheetAgain(
        tester,
        controller,
        const Size(400, 300),
        limit: const Rect.fromLTWH(24, 24, 600, 500),
      );
      // 24 + 500 − (300 − the bottom lane): the shorter paper's bottom on
      // the window's.
      expect(
        controller.value!.panY / _ratio,
        closeTo(-(24 + 500 - (300 - AppScrollbarLane.wide)), 1e-6),
      );
    });

    testWidgets('with no paper the view goes where it is sent — the drawing '
        'canvas\'s way', (tester) async {
      final controller = await pumpSheet(tester, limit: null);
      controller.value = device(tester, CanvasViewport(panX: 900));
      await tester.pump();
      expect(painted(tester).panX, closeTo(900, 1e-6));
    });
  });

  group('every canvas-base panel gives its paper', () {
    late EditorSessionManager session;

    setUp(() {
      session = EditorSessionManager(initialProject: createDefaultProject());
    });

    tearDown(() {
      PdfRenderService.debugResetForTests();
      session.dispose();
    });

    BrushCanvasPanel panel(WidgetTester tester) =>
        tester.widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel));

    /// The paper [panel] stops at, and the canvas it lies on.
    void expectPaper(WidgetTester tester, {required double margin}) {
      final shown = panel(tester);
      final limit = shown.viewLimit;
      expect(limit, isNotNull);
      final canvas = shown.canvasSize;
      expect(limit!.left, margin);
      expect(limit.top, margin);
      expect(limit.right, closeTo(canvas.width - margin, 1));
      expect(limit.bottom, closeTo(canvas.height - margin, 1));
    }

    Future<void> pumpIn(WidgetTester tester, Widget host) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: host)));
      await tester.pumpAndSettle();
    }

    testWidgets('the timesheet: its paper, inside the margin round it', (
      tester,
    ) async {
      await pumpIn(
        tester,
        TimesheetTabHost(
          session: session,
          continuous: false,
          onContinuousChanged: (_) {},
        ),
      );
      expectPaper(tester, margin: 24);
    });

    testWidgets('the conte: its book\'s paper, inside the margin round it', (
      tester,
    ) async {
      await pumpIn(tester, ConteTabHost(session: session, thumbnails: null));
      expectPaper(tester, margin: 24);
    });

    testWidgets('the cut envelope: its paper', (tester) async {
      await pumpIn(tester, CutEnvelopeTabHost(session: session));
      expectPaper(tester, margin: 0);
    });

    testWidgets('the viewer: its page once the document is there — and none '
        'before, so a restored view is not held to a stand-in', (
      tester,
    ) async {
      final fake = FakePdfDocument(pageSizes: const [ui.Size(595, 842)]);
      final opened = Completer<FakePdfDocument>();
      PdfRenderService.debugOpenerOverride = (_) => opened.future;
      final slot = MediaViewerSlot();
      addTearDown(slot.dispose);
      await pumpIn(
        tester,
        ValueListenableBuilder<int>(
          valueListenable: slot.position,
          builder: (context, position, _) => MediaViewerTabHost(
            viewerId: 'media-viewer',
            session: session,
            request: slot.request,
            position: slot.position,
          ),
        ),
      );
      expect(panel(tester).viewLimit, isNull, reason: 'nothing to view');

      slot.request.value = const MediaViewerRequest(
        path: 'C:/work/conte.pdf',
        kind: MediaAssetKind.pdf,
        name: 'conte',
      );
      await tester.pump();
      expect(
        panel(tester).viewLimit,
        isNull,
        reason: 'the document is still on its way',
      );

      opened.complete(fake);
      await tester.pumpAndSettle();
      expect(panel(tester).viewLimit, const Rect.fromLTWH(0, 0, 595, 842));
    });
  });
}

/// Logical units per device unit in the panel, as [pumpSheet] measured it.
double _ratio = 1;

/// What the panel paints and hit-tests with — the held view.
CanvasViewport painted(WidgetTester tester) => tester
    .widget<CanvasViewportGestureLayer>(
      find.byType(CanvasViewportGestureLayer),
    )
    .viewport;

/// The same sheet in a box of [box] — the controller carried over.
Future<void> pumpSheetAgain(
  WidgetTester tester,
  ValueNotifier<CanvasViewport?> controller,
  Size box, {
  Rect limit = const Rect.fromLTWH(24, 24, 600, 800),
}) async {
  await tester.pumpWidget(sheetIn(controller, box, limit: limit));
  await tester.pumpAndSettle();
}

/// A sheet over a 648×848 canvas in a box of [box], its view in
/// [controller].
Widget sheetIn(
  ValueNotifier<CanvasViewport?> controller,
  Size box, {
  Rect? limit = const Rect.fromLTWH(24, 24, 600, 800),
}) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox.fromSize(
      size: box,
      child: SheetCanvasPanel(
        cacheInvalidationSink: BrushEditCacheInvalidationSink(),
        canvasSize: const CanvasSize(width: 648, height: 848),
        viewport: null,
        viewportController: controller,
        viewLimit: limit,
        drawingOn: false,
        content: (context, viewport) => const SizedBox.expand(),
      ),
    ),
  ),
);
