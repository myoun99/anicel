// F-201 (유저 2026-09-27): 「캔버스 베이스 패널, 뷰어든 콘티 프리뷰든
// pdf같은거 여러페이지 동시에 볼수있게 하고싶음. pdf리더같은거 밑으로 쭉
// 존재하잖아. 별개로 왼쪽 알약인 페이지 넘기는 버튼은 동시존재해서 그거로
// 다음페이지 스냅」.
//
// THE VIEWER READS A BOOK: a PDF's pages lie one under another, each drawn
// where it lies and asked for at the zoom the view has; the page turner's
// ◀ ▶ (the 왼쪽 알약 then, in the band under the bars since F-383) snap
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
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/services/persistence/app_memory_settings.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/canvas_zoom_scale.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/session/media_file_views.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/app_scrollbar_lane.dart';
import 'package:anicel/src/ui/widgets/cursor_notice.dart';

import '../../helpers/canvas_pill.dart';
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
    bool drawnAtAnySize = true,
  }) async {
    final fake = FakePdfDocument(
      pageSizes: List<ui.Size>.filled(pages, pageSize),
      framesPerSecond: framesPerSecond,
      drawnAtAnySize: drawnAtAnySize,
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

  /// [page] framed whole: a portrait page fits the window's height, less
  /// the fit's own margin — not the book, whose pages would each take a
  /// share. The window is the box less the pill's band over it, and the
  /// lane and the page turner's band under it (유저 2026-09-30: 「판정을
  /// 알약까지 포함해서」 · F-383).
  void expectFramed(WidgetTester tester, Rect page) {
    final view = renderOf(tester, slot.viewport.value!);
    final box = tester.getSize(
      find.byKey(const ValueKey<String>('brush-canvas-editor-viewport')),
    );
    final window = Rect.fromLTRB(
      0,
      pillBandOf(tester),
      box.width - AppScrollbarLane.thin,
      box.height - AppScrollbarLane.thin - bandCoverOf(tester),
    );
    final top = page.top * view.zoom + view.panY;
    final height = page.height * view.zoom;
    expect(height, greaterThan(window.height * 0.85));
    expect(top, greaterThanOrEqualTo(window.top - 1e-6));
    expect(top + height, lessThanOrEqualTo(window.bottom + 1e-6));
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

  testWidgets('🚨a page made of its file\'s pixels is asked for at them '
      'however the view zooms — never past them (유저 2026-09-11 「pdf는 '
      '확대하면 선명해지는게 맞긴하네 … 이미지나 비디오는 아닐지라도」), never '
      'under (10-16 「늘 원본(캔버스처럼)」)', (tester) async {
    final quarter = CanvasZoomScale(tester.view.devicePixelRatio).render(0.25);
    final fake = await open(
      tester,
      pages: 2,
      view: CanvasViewport(zoom: quarter),
      drawnAtAnySize: false,
    );
    expect(
      fake.renderRequests.map((ask) => (ask.$2, ask.$3)).toSet(),
      {(600, 800)},
      reason: 'zoomed out fourfold, at its own pixels — ↩️at a quarter of '
          'them',
    );

    slot.viewport.value = seedFromRender(
      tester,
      CanvasViewport(zoom: 2),
    );
    await tester.pumpAndSettle();

    expect(
      fake.renderRequests.map((ask) => (ask.$2, ask.$3)).toSet(),
      {(600, 800)},
      reason: 'zoomed in eightfold, at its own pixels and no more',
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
      closeTo(pillBandOf(tester) + 16 * view.zoom, 1e-6),
      reason: 'its top half a gap under the view\'s — the window\'s, under '
          'the pill\'s band',
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

  // 🗣️F-254 (유저 2026-10-08): 「잘라내기도구로 빈 곳에 그렸을때도 동일하게
  // 법 통일해서 적용」.
  testWidgets('an outline on the desk between pages cuts nothing — and says '
      'so, as every cut that finds nothing does', (tester) async {
    addTearDown(cursorNotices.clear);
    final fake = await open(tester, pages: 3, view: CanvasViewport(zoom: 1));
    final desk = pageRect(0).bottom;
    slot.viewport.value = seedFromRender(
      tester,
      CanvasViewport(zoom: 1, panY: -(desk - 200)),
    );
    await tester.pumpAndSettle();

    await cutOut(tester, Rect.fromLTRB(100, desk + 6, 400, desk + 26));

    expect(held.isEmpty, isTrue);
    expect(fake.regionReads, isEmpty);
    expect(cursorNotices.message, AppText.strings.noticeNothingToCut);
    cursorNotices.clear();
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

  /// 🗣️F-382 (유저 2026-10-17): 「… 줌 상태나 페이지상태등이 기억되서 다른
  /// 파일 열엇다가 돌아오면 그대로 열리도록」 — the page the file's, the
  /// framing the viewer's (`MediaFileViews`).
  group('a file comes back where it was left (F-382)', () {
    const book = MediaViewerRequest(path: path, kind: MediaAssetKind.pdf);
    const layout = MediaViewerRequest(
      path: 'C:/work/layout.pdf',
      kind: MediaAssetKind.pdf,
    );
    late MediaFileViews views;

    /// The viewer keeping what it shows in [views], with the two-page
    /// [layout] in — so the five-page [book] comes in over another
    /// document, as a file opened again does.
    Future<void> showTheLayout(WidgetTester tester) async {
      views = MediaFileViews();
      slot.keepIn(views, viewer: 'media-viewer');
      PdfRenderService.debugOpenerOverride = (source) async => FakePdfDocument(
        pageSizes: List<ui.Size>.filled(switch (source) {
          MediaFileBytes(path: final file) when file.endsWith('layout.pdf') =>
            2,
          _ => 5,
        }, pageSize),
      );
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
              keptFraming: slot.keptFramingOf,
            ),
          ),
        ),
      );
      slot.open(layout);
      await tester.pumpAndSettle();
    }

    Future<void> openIt(WidgetTester tester, MediaViewerRequest file) async {
      slot.open(file);
      await tester.pumpAndSettle();
    }

    testWidgets('a file this viewer framed comes back framed so — and a page '
        'turned since, in the other viewer, is a turn at that zoom', (
      tester,
    ) async {
      await showTheLayout(tester);
      await openIt(tester, book);
      // The user reads it at a scale of their own.
      slot.viewport.value = seedFromRender(tester, CanvasViewport(zoom: 1));
      await tester.pumpAndSettle();
      expect(slot.position.value, 0, reason: '⛔fixture');
      final kept = renderOf(tester, slot.viewport.value!);

      await openIt(tester, layout);
      // Read on to its third page in the other viewer.
      views.rememberPage(path, 2);
      await openIt(tester, book);

      expect(slot.position.value, 2);
      expect(readout(tester), '3 / 5');
      final view = renderOf(tester, slot.viewport.value!);
      expect(
        view.zoom,
        closeTo(kept.zoom, 1e-9),
        reason: 'the zoom it was left at — not fitted',
      );
      expect(view.panX, closeTo(kept.panX, 1e-9));
      expect(
        view.panY + pageRect(2).top * view.zoom,
        closeTo(pillBandOf(tester) + 16 * view.zoom, 1e-6),
        reason: 'turned to: its top half a gap under the window\'s',
      );
    });

    testWidgets('a file this viewer never framed is fitted — at the page it '
        'was left at, which the document it came in over does not have', (
      tester,
    ) async {
      await showTheLayout(tester);
      expect(readout(tester), '1 / 2', reason: '⛔fixture: two pages');
      views.rememberPage(path, 3);

      await openIt(tester, book);

      expect(slot.position.value, 3);
      expect(readout(tester), '4 / 5');
      expectFramed(tester, pageRect(3));
    });
  });
}
