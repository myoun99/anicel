import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/page_stack.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/canvas/viewport_canvas_transform.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/conte/conte_page_painter.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import '../../helpers/device_viewport.dart';

/// 🗣️F-201 (유저 2026-09-27): 「캔버스 베이스 패널, 뷰어든 콘티 프리뷰든
/// pdf같은거 여러페이지 동시에 볼수있게 하고싶음. pdf리더같은거 밑으로 쭉
/// 존재하잖아. 별개로 왼쪽 알약인 페이지 넘기는 버튼은 동시존재해서 그거로
/// 다음페이지 스냅」 — the conte's book lies one page under another, and the
/// page strip scrolls to a page instead of swapping the paper.
void main() {
  /// Eight one-cell cuts: five rows a page, so two body pages after the
  /// cover and its blank back.
  Project project() => Project(
    id: const ProjectId('book'),
    name: 'Book',
    createdAt: DateTime.utc(2026, 9, 27),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Video',
        cuts: [
          for (var index = 1; index <= 8; index += 1)
            Cut(
              id: CutId('$index'),
              name: '$index',
              duration: 12,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: [
                Layer(
                  id: LayerId('$index-sb'),
                  name: 'SB',
                  kind: LayerKind.storyboard,
                  frames: [
                    Frame(
                      id: FrameId('$index-0'),
                      duration: 1,
                      strokes: const [],
                    ),
                  ],
                  timeline: {
                    0: TimelineExposure.drawing(
                      FrameId('$index-0'),
                      length: 12,
                      memo: ExposureMemo(inkId: 'ink-$index'),
                    ),
                  },
                ),
              ],
            ),
        ],
      ),
    ],
  );

  List<ContePageLayout> pagesOf(EditorSessionManager session) =>
      layoutConteBook(
        buildConteSheetSource(session.repository.requireProject()),
        metrics: ConteSheetMetrics(
          cameraAspect: session.camera.cameraFrameAspect,
        ),
      );

  PageStack stackOf(List<ContePageLayout> pages) => PageStack([
    for (final page in pages)
      ui.Size(page.metrics.pageWidth, page.metrics.pageHeight),
  ]);

  /// The panel on [session] through a view the test owns, [seed] its first
  /// value (render units; null leaves it unframed).
  Future<ValueNotifier<CanvasViewport?>> pump(
    WidgetTester tester,
    EditorSessionManager session, {
    CanvasViewport? seed,
    bool brush = false,
    Size surface = const Size(900, 900),
  }) async {
    final view = ValueNotifier<CanvasViewport?>(
      seed == null ? null : seedFromRender(tester, seed),
    );
    addTearDown(view.dispose);
    final ink = ConteInkController();
    addTearDown(ink.dispose);
    final tool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(tool.dispose);
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([session, view]),
            builder: (context, _) => ConteTabHost(
              session: session,
              thumbnails: null,
              viewportController: view,
              inkController: ink,
              brushToolState: tool,
              brushAllowed: brush,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return view;
  }

  String readout(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('conte-page-readout')),
          matching: find.byType(Text),
        ),
      )
      .data!;

  /// The view the pages are printed through: the panel's — held to the
  /// paper (F-201) — snapped to the device grid as the sheet snaps it.
  CanvasViewport printedThrough(WidgetTester tester) => renderSnappedViewport(
    tester
        .widget<CanvasViewportGestureLayer>(
          find.byType(CanvasViewportGestureLayer),
        )
        .viewport,
    tester.view.devicePixelRatio,
  );

  EditorSessionManager sessionOf() {
    final session = EditorSessionManager(initialProject: project());
    addTearDown(session.dispose);
    return session;
  }

  testWidgets('a view across two pages shows both, each where it lies — and '
      'the pen\'s windows lie over both, each page\'s where its page is', (
    tester,
  ) async {
    final session = sessionOf();
    final pages = pagesOf(session);
    expect(
      pages.where((page) => page.kind == ContePageKind.body),
      hasLength(2),
      reason: 'fixture: two body pages',
    );
    final stack = stackOf(pages);
    // The gap between the two body pages at the middle of the panel, on a
    // whole pixel so the panel's snap leaves the view as it is.
    final seam = stack.pageRect(2).bottom + stack.gap / 2;
    final seed = CanvasViewport(
      panX: -stack.margin,
      panY: (450 - seam).roundToDouble(),
    );
    await pump(tester, session, seed: seed, brush: true);

    expect(find.byKey(const ValueKey<String>('conte-page-2')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('conte-page-3')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('conte-page-0')),
      findsNothing,
      reason: 'a page the view does not meet costs nothing',
    );

    // The first cell of the second body page — cut 6's band.
    final band = conteInkWindows(pages[3]).first;
    final view = tester.widget<InteractiveBrushEditCanvasView>(
      find.byKey(ValueKey<String>('conte-ink-${band.id}')),
    );
    expect(
      view.viewport,
      band
          .shiftedBy(stack.pageRect(3).topLeft)
          .inkViewport(printedThrough(tester)),
    );
  });

  testWidgets('a turn scrolls to the page — its top at the top of the view, '
      'half a gap above it, at the zoom the view has — and the readout '
      'follows the view', (tester) async {
    final session = sessionOf();
    final stack = stackOf(pagesOf(session));
    final seed = CanvasViewport(
      zoom: 0.5,
      panX: -stack.margin,
      panY: -stack.pageRect(2).top * 0.5,
    );
    // A view shorter than a page, so no page here is near enough the
    // paper's end for the view to stop short of its top.
    final view = await pump(
      tester,
      session,
      seed: seed,
      surface: const Size(900, 360),
    );
    expect(readout(tester), '3 / 4', reason: 'the body\'s first page');
    final zoom = view.value!.zoom;

    await tester.tap(
      find.byKey(const ValueKey<String>('conte-next-page-button')),
    );
    await tester.pumpAndSettle();
    expect(view.value!.zoom, zoom, reason: 'a turn does not zoom');
    expect(
      view.value!.panY,
      closeTo(-(stack.pageRect(3).top - stack.gap / 2) * zoom, 1e-6),
    );
    expect(readout(tester), '4 / 4');

    await tester.tap(
      find.byKey(const ValueKey<String>('conte-previous-page-button')),
    );
    await tester.pumpAndSettle();
    expect(readout(tester), '3 / 4');

    // Scrolled by hand until the middle of the second body page is at the
    // top of the view: the readout reads the view, as a PDF reader counts.
    final middle = stack.pageRect(3).center.dy;
    view.value = view.value!.copyWith(panY: -middle * zoom);
    await tester.pumpAndSettle();
    expect(readout(tester), '4 / 4');
    // …and half a gap short of the page, it is still the page above.
    final short = -(stack.pageRect(3).top - stack.gap * 1.5) * zoom;
    view.value = view.value!.copyWith(panY: short);
    await tester.pumpAndSettle();
    expect(readout(tester), '3 / 4');
    expect(
      view.value!.panY,
      closeTo(short, 1e-6),
      reason: 'the page read follows the hand — the hand is not snapped '
          'to the page',
    );
  });

  testWidgets('a drag that takes the page read off the view reads the page '
      'at its top', (tester) async {
    final session = sessionOf();
    final stack = stackOf(pagesOf(session));
    await pump(
      tester,
      session,
      seed: CanvasViewport(
        zoom: 0.5,
        panX: -stack.margin,
        panY: -stack.pageRect(2).top * 0.5,
      ),
      surface: const Size(900, 360),
    );
    expect(readout(tester), '3 / 4', reason: '⛔전제');

    // On the desk beside the paper, where no cell takes the press.
    final box = tester.getRect(find.byType(CanvasViewportGestureLayer));
    final gesture = await tester.startGesture(
      Offset(box.left + 60, box.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    for (var step = 0; step < 6; step += 1) {
      await gesture.moveBy(Offset(0, -stack.pageRect(2).height / 12 * 1.2));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(readout(tester), '4 / 4');
  });

  testWidgets('Fit frames the page read', (tester) async {
    final session = sessionOf();
    final stack = stackOf(pagesOf(session));
    await pump(
      tester,
      session,
      seed: CanvasViewport(
        zoom: 2,
        panX: -stack.margin * 2,
        panY: -stack.pageRect(3).top * 2,
      ),
    );
    expect(readout(tester), '4 / 4', reason: '⛔전제');

    await tester.tap(
      find.byKey(const ValueKey<String>('canvas-viewport-fit')),
    );
    await tester.pumpAndSettle();
    final shown = printedThrough(tester);
    final box = tester.getSize(find.byType(CanvasViewportGestureLayer));
    final page = stack.pageRect(3);
    final onScreen = Rect.fromLTWH(
      page.left * shown.zoom + shown.panX,
      page.top * shown.zoom + shown.panY,
      page.width * shown.zoom,
      page.height * shown.zoom,
    );
    // A portrait page fits the view's height, less the fit's own margin —
    // not the whole book, whose four pages would each take a quarter.
    expect(onScreen.height, lessThanOrEqualTo(box.height));
    expect(onScreen.height, greaterThan(box.height * 0.85));
  });

  testWidgets('a turn to a last page shorter than the view stops at the '
      'paper\'s end — and reads the last page, which never reached the '
      'top', (tester) async {
    final session = sessionOf();
    final stack = stackOf(pagesOf(session));
    await pump(
      tester,
      session,
      seed: CanvasViewport(
        panX: -stack.margin,
        panY: -stack.pageRect(2).top,
      ),
    );
    expect(readout(tester), '3 / 4', reason: '⛔전제');

    await tester.tap(
      find.byKey(const ValueKey<String>('conte-next-page-button')),
    );
    await tester.pumpAndSettle();
    expect(readout(tester), '4 / 4');
    final shown = printedThrough(tester);
    final box = tester.getSize(find.byType(CanvasViewportGestureLayer));
    expect(
      stack.paper.bottom * shown.zoom + shown.panY,
      closeTo(box.height, 1),
      reason: 'the paper\'s end on the view\'s',
    );
  });

  testWidgets('a book zoomed out to fit whole moves not at all, and a turn '
      'still changes the page read', (tester) async {
    final session = sessionOf();
    final view = await pump(tester, session, seed: CanvasViewport(zoom: 0.2));
    expect(readout(tester), '1 / 4', reason: 'the book\'s top at the top');
    final whole = view.value;

    await tester.tap(
      find.byKey(const ValueKey<String>('conte-next-page-button')),
    );
    await tester.pumpAndSettle();
    expect(readout(tester), '2 / 4');
    expect(view.value, whole, reason: 'nowhere to move');

    await tester.tap(
      find.byKey(const ValueKey<String>('conte-next-page-button')),
    );
    await tester.pumpAndSettle();
    expect(readout(tester), '3 / 4');
  });

  testWidgets('at a zoom that puts a page between device pixels, the page is '
      'printed on the grid and its windows lie on the page as printed', (
    tester,
  ) async {
    final session = sessionOf();
    final pages = pagesOf(session);
    final stack = stackOf(pages);
    const zoom = 0.7;
    await pump(
      tester,
      session,
      seed: CanvasViewport(
        zoom: zoom,
        panX: -stack.margin * zoom,
        panY: (-(stack.pageRect(3).top - 100) * zoom).roundToDouble(),
      ),
      brush: true,
    );
    final ratio = tester.view.devicePixelRatio;
    final printed = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('conte-page-3')),
            matching: find.byKey(const ValueKey<String>('conte-form-paint')),
          ),
        )
        .painter!;
    final onPage = (printed as ContePagePainter).viewport!;
    // The page lies on the device grid already: its printers' own snap
    // leaves it where the ink windows are.
    final resnapped = renderSnappedViewport(onPage, ratio);
    expect(resnapped.panX, closeTo(onPage.panX, 1e-9));
    expect(resnapped.panY, closeTo(onPage.panY, 1e-9));
    final band = conteInkWindows(pages[3]).first;
    final window = tester
        .widget<InteractiveBrushEditCanvasView>(
          find.byKey(ValueKey<String>('conte-ink-${band.id}')),
        )
        .viewport;
    final asPrinted = band.inkViewport(onPage);
    expect(window.zoom, closeTo(asPrinted.zoom, 1e-9));
    expect(window.panX, closeTo(asPrinted.panX, 1e-9));
    expect(window.panY, closeTo(asPrinted.panY, 1e-9));
  });

  testWidgets('a view nobody has moved opens fitted to the body\'s first page, '
      'and a turn fits the next without framing the view', (tester) async {
    final session = sessionOf();
    final view = await pump(tester, session);
    expect(readout(tester), '3 / 4');
    expect(find.byKey(const ValueKey<String>('conte-page-2')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('conte-page-0')),
      findsNothing,
      reason: 'the body\'s first page is on screen, not the cover',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('conte-next-page-button')),
    );
    await tester.pumpAndSettle();
    expect(readout(tester), '4 / 4');
    expect(view.value, isNull, reason: 'still nobody\'s framing');
  });
}
