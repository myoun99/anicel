// F-201 (유저 2026-09-27): 「캔버스 베이스 패널, 뷰어든 콘티 프리뷰든
// pdf같은거 여러페이지 동시에 볼수있게 하고싶음. pdf리더같은거 밑으로 쭉
// 존재하잖아. 별개로 왼쪽 알약인 페이지 넘기는 버튼은 동시존재해서 그거로
// 다음페이지 스냅」.
//
// THE VIEWER READS A BOOK: a PDF's pages lie one under another, each drawn
// where it lies and asked for at the zoom the view has; the strip's ▲▼ snap
// the view to a page and the page read is the slot's position; a cut is of
// the page it lies on. A document that turns its own pages — a movie — shows
// the page it is on alone.
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/cut_piece_slot.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/services/persistence/app_memory_settings.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';

import '../../helpers/device_viewport.dart';
import '../../helpers/fake_pdf_document.dart';

void main() {
  const pageSize = ui.Size(600, 800);
  const path = 'C:/work/book.pdf';

  late EditorSessionManager session;
  late MediaViewerSlot slot;
  late CutPieceSlot held;
  late ValueNotifier<BrushToolState> tool;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    AppMemory.settings.value = AppMemorySettings(
      allowanceBytes: session.deviceCacheBudgets.total,
    );
    slot = MediaViewerSlot();
    held = CutPieceSlot();
    tool = ValueNotifier<BrushToolState>(
      BrushToolState.defaults.copyWith(
        tool: CanvasTool.cut,
        cutShape: CanvasShapeKind.rect,
      ),
    );
  });

  tearDown(() {
    PdfRenderService.debugResetForTests();
    AppMemory.settings.value = const AppMemorySettings();
    tool.dispose();
    slot.dispose();
    session.dispose();
  });

  /// The viewer on a [pages]-page document, its view the slot's — seeded
  /// with [view] (render units) and not framed by the viewer, so the test
  /// says where the pages are; unless it is the document's [firstOpen],
  /// which the viewer frames.
  Future<FakePdfDocument> open(
    WidgetTester tester, {
    int pages = 3,
    double? framesPerSecond,
    required CanvasViewport view,
    bool firstOpen = false,
  }) async {
    final fake = FakePdfDocument(
      pageSizes: List<ui.Size>.filled(pages, pageSize),
      framesPerSecond: framesPerSecond,
    );
    PdfRenderService.debugOpenerOverride = (_) async => fake;
    slot.framedFor.value = firstOpen ? null : path;
    slot.viewport.value = seedFromRender(tester, view);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaViewerTabHost(
            viewerId: 'media-viewer',
            session: session,
            request: slot.request,
            position: slot.position,
            viewportController: slot.viewport,
            framedFor: slot.framedFor,
            brushTool: tool,
            cutPieceSlot: held,
          ),
        ),
      ),
    );
    slot.open(const MediaViewerRequest(path: path, kind: MediaAssetKind.pdf));
    await tester.pumpAndSettle();
    return fake;
  }

  BrushCanvasPanel panel(WidgetTester tester) =>
      tester.widget<BrushCanvasPanel>(find.byType(BrushCanvasPanel));

  /// What the page painter was handed: each page on screen, where it lies.
  List<({Rect rect, ui.Image? image})> drawn(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey<String>('media-viewer-page')),
    );
    return (paint.painter as dynamic).pages
        as List<({Rect rect, ui.Image? image})>;
  }

  String readout(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('media-viewer-page-readout')),
          matching: find.byType(Text),
        ),
      )
      .data!;

  /// Page [page]'s rect in the book: no margin, a 32 gap.
  Rect pageRect(int page) =>
      Rect.fromLTWH(0, page * (pageSize.height + 32), 600, 800);

  /// [page] framed whole: a portrait page fits the view's height, less the
  /// fit's own margin — not the book, whose pages would each take a share.
  void expectFramed(WidgetTester tester, Rect page) {
    final view = renderOf(tester, slot.viewport.value!);
    final box = tester.getSize(
      find.byKey(const ValueKey<String>('brush-canvas-editor-viewport')),
    );
    final top = page.top * view.zoom + view.panY;
    final height = page.height * view.zoom;
    expect(height, lessThanOrEqualTo(box.height));
    expect(height, greaterThan(box.height * 0.85));
    expect(top, greaterThanOrEqualTo(-1e-6));
    expect(top + height, lessThanOrEqualTo(box.height + 1e-6));
  }

  /// Drags the cut tool's rect across [outline] — book units, through the
  /// view the slot holds now.
  Future<void> cutOut(WidgetTester tester, Rect outline) async {
    final view = renderOf(tester, slot.viewport.value!);
    final origin = tester.getTopLeft(
      find.byKey(const ValueKey<String>('brush-canvas-editor-viewport')),
    );
    Offset onScreen(Offset at) {
      final shown = view.canvasToViewport(CanvasPoint(x: at.dx, y: at.dy));
      return origin + Offset(shown.x, shown.y);
    }

    final gesture = await tester.startGesture(
      onScreen(outline.topLeft),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(onScreen(outline.center));
    await tester.pump();
    await gesture.moveTo(onScreen(outline.bottomRight));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('the pages lie one under another: every page the view meets '
      'is drawn where it lies, and nothing past it is asked for', (
    tester,
  ) async {
    // A third of a page per screen pixel: the first two pages on screen.
    final fake = await open(tester, pages: 4, view: CanvasViewport(zoom: 0.5));

    expect(panel(tester).book, isNotNull, reason: 'a PDF is read as a book');
    expect(
      drawn(tester).map((page) => page.rect),
      [pageRect(0), pageRect(1)],
    );
    expect(
      drawn(tester).every((page) => page.image != null),
      isTrue,
      reason: 'each drawn with its own raster',
    );
    expect(
      fake.renderRequests.map((ask) => ask.$1).toSet(),
      {0, 1},
      reason: 'the pages off screen are not asked for',
    );
    expect(
      find.byKey(const ValueKey<String>('media-viewer-page')),
      paints
        ..rect(rect: pageRect(0))
        ..drawImageRect(destination: pageRect(0))
        ..rect(rect: pageRect(1))
        ..drawImageRect(destination: pageRect(1)),
      reason: 'each page painted, paper and raster, where it lies',
    );
  });

  testWidgets('each page is asked for at the zoom the view HAS — the view '
      'the slot keeps, which is how the app hands it over', (tester) async {
    final fake = await open(tester, pages: 2, view: CanvasViewport(zoom: 0.5));
    final wide = fake.renderRequests.last.$2;

    slot.viewport.value = seedFromRender(
      tester,
      CanvasViewport(zoom: 2),
    );
    await tester.pumpAndSettle();

    expect(
      fake.renderRequests.last.$2,
      greaterThan(wide),
      reason: 'zoomed in fourfold, the page is asked for sharper',
    );
  });

  testWidgets('a book opened for the first time is framed to its first '
      'page — every page asked for through the view that shows it, none '
      'through the one the fit replaced', (tester) async {
    final fake = await open(
      tester,
      pages: 3,
      view: CanvasViewport(zoom: 2),
      firstOpen: true,
    );

    expectFramed(tester, pageRect(0));
    expect(
      fake.renderRequests.map((ask) => ask.$2).toSet(),
      hasLength(1),
      reason: 'one scale — the fitted view\'s',
    );
  });

  testWidgets('Fit frames the page read, not the book', (tester) async {
    await open(tester, pages: 3, view: CanvasViewport(zoom: 2));
    await tester.tap(
      find.byKey(const ValueKey<String>('media-viewer-next-page-button')),
    );
    await tester.pumpAndSettle();
    expect(slot.position.value, 1, reason: '⛔전제');

    await tester.tap(
      find.byKey(const ValueKey<String>('canvas-viewport-fit')),
    );
    await tester.pumpAndSettle();

    expectFramed(tester, pageRect(1));
    expect(slot.position.value, 1);
  });

  testWidgets('▼ snaps the view to the next page and the slot reads it; '
      'the view leaving a page reads the page at its top', (tester) async {
    await open(tester, pages: 3, view: CanvasViewport(zoom: 1));
    expect(readout(tester), '1 / 3');

    await tester.tap(
      find.byKey(const ValueKey<String>('media-viewer-next-page-button')),
    );
    await tester.pumpAndSettle();
    expect(slot.position.value, 1);
    expect(readout(tester), '2 / 3');
    final view = renderOf(tester, slot.viewport.value!);
    expect(
      view.panY + pageRect(1).top * view.zoom,
      closeTo(16 * view.zoom, 1e-6),
      reason: 'its top half a gap under the view\'s',
    );

    // Back to the top by hand: the page read follows the view.
    slot.viewport.value = seedFromRender(tester, CanvasViewport(zoom: 1));
    await tester.pumpAndSettle();
    expect(slot.position.value, 0);
    expect(readout(tester), '1 / 3');
  });

  testWidgets('a cut is of the page it lies on, in that page\'s own '
      'pixels', (tester) async {
    final fake = await open(tester, pages: 3, view: CanvasViewport(zoom: 1));
    await tester.tap(
      find.byKey(const ValueKey<String>('media-viewer-next-page-button')),
    );
    await tester.pumpAndSettle();

    final top = pageRect(1).top;
    await cutOut(tester, Rect.fromLTRB(100, top + 100, 400, top + 300));

    expect(held.isNotEmpty, isTrue, reason: 'the cut went');
    final (page, left, topPx, width, height) = fake.regionReads.single;
    expect(page, 1, reason: 'the page it lies on');
    expect(
      (left, topPx),
      (100, 100),
      reason: 'in the page\'s own pixels, not the book\'s',
    );
    // The outline's own size, to the pixel the read rounds its edge out
    // by — the cut's rule, not the book's.
    expect(width, inInclusiveRange(300, 301));
    expect(height, inInclusiveRange(200, 201));
  });

  testWidgets('a cut deep in the book is of its page too — the canvas '
      'the panel is handed spans the book, not its first page', (
    tester,
  ) async {
    final fake = await open(tester, pages: 5, view: CanvasViewport(zoom: 1));
    slot.position.value = 4;
    await tester.pumpAndSettle();

    final top = pageRect(4).top;
    await cutOut(tester, Rect.fromLTRB(100, top + 100, 400, top + 300));

    expect(held.isNotEmpty, isTrue, reason: 'the cut went');
    final (page, left, topPx, _, _) = fake.regionReads.single;
    expect((page, left, topPx), (4, 100, 100));
  });

  // Across the seam of pages 2 and 3: 50 rows of one, 100 or 150 of the
  // other.
  for (final (most, over) in const [(2, 150.0), (1, -150.0)]) {
    testWidgets('an outline across two pages cuts the one it covers most — '
        'page ${most + 1}', (tester) async {
      final fake = await open(tester, pages: 3, view: CanvasViewport(zoom: 1));
      final seam = pageRect(1).bottom;
      slot.viewport.value = seedFromRender(
        tester,
        CanvasViewport(zoom: 1, panY: -(seam - 200)),
      );
      await tester.pumpAndSettle();

      final outline = over > 0
          ? Rect.fromLTRB(100, seam - 50, 400, pageRect(2).top + over - 50)
          : Rect.fromLTRB(100, seam + over, 400, pageRect(2).top + 50);
      await cutOut(tester, outline);

      expect(held.isNotEmpty, isTrue, reason: 'the cut went');
      final (page, _, topPx, _, height) = fake.regionReads.single;
      expect(page, most);
      expect(
        most == 2 ? topPx : topPx + height,
        most == 2 ? 0 : 800,
        reason: 'what it holds of that page, which ends where the page does',
      );
    });
  }

  testWidgets('a document that turns its own pages shows the one it is on '
      'alone — no book', (tester) async {
    await open(
      tester,
      pages: 3,
      framesPerSecond: 24,
      view: CanvasViewport(zoom: 0.5),
    );

    expect(panel(tester).book, isNull);
    expect(drawn(tester).map((page) => page.rect), [pageRect(0)]);
  });
}
