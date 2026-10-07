import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_form.dart';
import 'package:anicel/src/models/envelope/cut_envelope_layout.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_overlay.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_layer.dart';

/// 🚨★★★A STROKE IS THE WINDOW'S IT STARTS IN — 유저 2026-09-30 (H49):
/// 「그냥 선 시작한곳에따라 칸 나누자 … 일반칸은 일반칸내에서만 지정된 범위
/// 안에서만 그려지도록」.
///
/// The window on top where the pen lands takes the whole stroke and keeps
/// it where it shows — nothing of it lands in a window it crosses into —
/// and the pen-up is ONE undo. ↩️From 09-25 a stroke crossed the sheet as
/// one paper, every window keeping the piece drawn over it (「진짜 하나의
/// 용지처럼」); before that the start window kept it all, unclipped, off
/// the bottom of a timesheet's left half into the top of the right one.
void main() {
  const cutId = CutId('cut-1');

  bool inkAt(BitmapSurface surface, Offset pixel) =>
      (surfacePixelRgba(surface, pixel.dx.floor(), pixel.dy.floor()) ?? 0) !=
      0;

  group('the timesheet', () {
    late TimesheetDocumentLayout layout;
    late TimesheetInkController controller;
    late HistoryManager history;
    late ValueNotifier<bool> strokeActive;
    late List<bool> holds;
    late List<SheetInkWindow> windows;

    SheetInkWindow window(String id) =>
        windows.singleWhere((window) => window.id == id);

    BitmapSurface surfaceOf(SheetInkWindow window) => controller
        .sessionStateFor(null, window.key)
        .canvasState
        .currentSurface;

    /// Whether [window]'s surface holds ink under paper point [paper].
    bool inkUnder(SheetInkWindow window, Offset paper) =>
        inkAt(surfaceOf(window), window.placement.pixelOf(paper));

    Future<Offset> pumpSheet(
      WidgetTester tester, {
      Widget? under,
      ValueNotifier<BrushToolState>? brush,
    }) async {
      // Two pages, so a stroke can leave the page it starts on.
      layout = TimesheetDocumentLayout(
        document: TimesheetDocument.fromCut(
          cut: Cut(
            id: cutId,
            name: 'Cut 1',
            layers: const [],
            duration: 150,
            canvasSize: const CanvasSize(width: 1280, height: 720),
          ),
          projectName: 'Project',
          fps: 24,
        ),
      );
      controller = TimesheetInkController()..syncGeometry(layout);
      addTearDown(controller.dispose);
      history = HistoryManager();
      strokeActive = ValueNotifier<bool>(false);
      addTearDown(strokeActive.dispose);
      holds = <bool>[];
      strokeActive.addListener(() => holds.add(strokeActive.value));
      windows = timesheetInkWindows(
        layout: layout,
        cutId: cutId,
      );
      final size = layout.documentSize;
      await tester.binding.setSurfaceSize(
        Size(size.width + 40, size.height + 40),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: Stack(
                  children: [
                    ?under,
                    TimesheetInkLayer(
                      controller: controller,
                      layout: layout,
                      cutId: cutId,
                      brushToolState:
                          brush ?? ValueNotifier(BrushToolState.defaults),
                      historyManager: history,
                      viewport: CanvasViewport(),
                      strokeActive: strokeActive,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      return tester.getTopLeft(find.byType(TimesheetInkLayer));
    }

    Future<void> stroke(
      WidgetTester tester,
      Offset origin,
      List<Offset> path,
    ) async {
      final gesture = await tester.startGesture(
        origin + path.first,
        pointer: 7,
      );
      await tester.pump();
      for (final point in path.skip(1)) {
        await gesture.moveTo(origin + point);
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
    }

    /// A point on the column grid's x, [dy] below the foot of page [page]'s
    /// paper — above it, on the page, when negative.
    Offset nearFootOf(int page, double dy) => Offset(
      layout.halfLeft(page, 0) + 30,
      layout.pageRect(page).bottom + dy,
    );

    /// The same, [dy] below the head of page [page]'s paper.
    Offset nearHeadOf(int page, double dy) => Offset(
      layout.halfLeft(page, 0) + 30,
      layout.pageRect(page).top + dy,
    );

    testWidgets('a stroke from the memo band into the grid is the page\'s, '
        'all of it — one hold, and ONE undo', (tester) async {
      final origin = await pumpSheet(tester);
      final page = window('page-0');
      // What the pen being up lets go of — the session's held seeks and cut
      // switches — must find the stroke already landed.
      bool? landedAtRelease;
      strokeActive.addListener(() {
        if (!strokeActive.value) {
          landedAtRelease = controller.hasInkFor(null, page.key);
        }
      });
      final x = layout.halfLeft(0, 0) + 30;
      final start = Offset(x, layout.memoBandRect(0).top + 20);
      final end = Offset(x, layout.halfRowsTop(0) + 60);
      await stroke(tester, origin, [
        start,
        Offset(x, layout.halfRowsTop(0) - 10),
        end,
      ]);

      expect(inkUnder(page, start), isTrue);
      expect(
        inkUnder(page, end),
        isTrue,
        reason: 'the grid is the page\'s paper too (F-252)',
      );
      expect(holds, [true, false], reason: 'one pen, one hold');
      expect(landedAtRelease, isTrue);

      history.undo();
      expect(controller.hasInkFor(null, page.key), isFalse);
      history.redo();
      expect(controller.hasInkFor(null, page.key), isTrue);
    });

    testWidgets('a stroke off the foot of one page onto the next keeps to '
        'the page it starts on — the next keeps none of it', (tester) async {
      final origin = await pumpSheet(tester);
      final first = window('page-0');
      final second = window('page-1');
      expect(
        layout.pageRect(1).top,
        greaterThanOrEqualTo(layout.pageRect(0).bottom),
        reason: '⛔전제: the pages stack, the second under the first',
      );
      final start = nearFootOf(0, -40);
      final across = nearHeadOf(1, 40);
      await stroke(tester, origin, [
        start,
        nearFootOf(0, -10),
        Offset(start.dx, (layout.pageRect(0).bottom + across.dy) / 2),
        across,
      ]);

      expect(inkUnder(first, start), isTrue);
      expect(
        controller.hasInkFor(null, second.key),
        isFalse,
        reason: 'the page it crossed into takes none of it',
      );

      history.undo();
      expect(controller.hasInkFor(null, first.key), isFalse);
    });

    testWidgets('the eraser keeps to the page it starts on, as the brush '
        'does — and ONE undo brings back what it rubbed out', (tester) async {
      final brush = ValueNotifier<BrushToolState>(BrushToolState.defaults);
      addTearDown(brush.dispose);
      final origin = await pumpSheet(tester, brush: brush);
      final first = window('page-0');
      final second = window('page-1');
      final onFirst = nearFootOf(0, -40);
      final onSecond = nearHeadOf(1, 40);
      await stroke(tester, origin, [onFirst, onFirst + const Offset(12, 0)]);
      await stroke(tester, origin, [onSecond, onSecond + const Offset(12, 0)]);
      expect(inkUnder(first, onFirst), isTrue, reason: '⛔CONTROL: drawn');
      expect(inkUnder(second, onSecond), isTrue, reason: '⛔CONTROL: drawn');

      brush.value = brush.value.copyWith(
        tool: CanvasTool.eraser,
        size: brush.value.size * 4,
      );
      await stroke(tester, origin, [onFirst, nearFootOf(0, -10), onSecond]);
      expect(inkUnder(first, onFirst), isFalse, reason: 'where it started');
      expect(
        inkUnder(second, onSecond),
        isTrue,
        reason: 'the page it crossed into kept its ink',
      );

      history.undo();
      expect(inkUnder(first, onFirst), isTrue);
    });

    testWidgets('🚨F-233: a window reads its page when the pen lands, not when '
        'it was last built', (tester) async {
      // An undo or a stroke just landed changes the page inside its own
      // event, and the window builds again at the next frame. A pen that
      // lands in between draws on the page as it stands — the view asks
      // its host, and the host asks the controller then.
      await pumpSheet(tester);
      final window = windows.singleWhere((w) => w.id == 'page-0');
      final view = tester.widget<InteractiveBrushEditCanvasView>(
        find.byKey(const ValueKey<String>('timesheet-ink-page-0')),
      );
      final before = view.celNow();

      controller.commitStroke(
        plane: null,
        key: window.key,
        strokeData: BrushStrokeCommitData(
          sourceDabs: [
            BrushDab(
              center: CanvasPoint(x: 20, y: 20),
              color: 0xFF000000,
              size: 4,
              opacity: 1,
              flow: 1,
              hardness: 1,
              tipShape: BrushTipShape.round,
              pressure: 1,
              sequence: 0,
            ),
          ],
        ),
        historyManager: history,
      );
      final landed = controller
          .sessionStateFor(null, window.key)
          .canvasState
          .currentSurface;
      expect(
        identical(landed, before),
        isFalse,
        reason: '⛔premise: the stroke landed on the page',
      );
      expect(
        identical(view.celNow(), landed),
        isTrue,
        reason: 'no frame has built since, and the window still answers '
            'with the page as it stands',
      );
    });

    testWidgets('a window taken away mid-stroke does not hold the pen down '
        'for good', (tester) async {
      await pumpSheet(tester);
      final shown = ValueNotifier<bool>(true);
      addTearDown(shown.dispose);
      final size = layout.documentSize;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: ValueListenableBuilder<bool>(
                  valueListenable: shown,
                  builder: (context, on, _) => SheetInkLayer(
                    windows: on ? windows : const <SheetInkWindow>[],
                    keyPrefix: 'timesheet',
                    viewport: CanvasViewport(),
                    brushToolState: ValueNotifier(BrushToolState.defaults),
                    strokeActive: strokeActive,
                    history: history.gestures,
                    sessionStateFor: (window) =>
                        controller.sessionStateFor(null, window.key),
                    onStrokeCommitted: (window, strokeData) =>
                        controller.commitStroke(
                          plane: null,
                          key: window.key,
                          strokeData: strokeData,
                          historyManager: history,
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final origin = tester.getTopLeft(find.byType(SheetInkLayer));
      final at = Offset(layout.halfLeft(0, 0) + 30, layout.halfRowsTop(0) + 30);
      final gesture = await tester.startGesture(origin + at, pointer: 7);
      await tester.pump();
      await gesture.moveTo(origin + at + const Offset(10, 10));
      await tester.pump();
      expect(strokeActive.value, isTrue);

      shown.value = false;
      await tester.pump();
      await tester.pump();
      expect(strokeActive.value, isFalse);
      await gesture.up();
      await tester.pump();
    });

    testWidgets('the layer takes every press once: nothing under it hears '
        'one, in a window or outside them all', (tester) async {
      var heard = 0;
      final origin = await pumpSheet(
        tester,
        under: Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => heard += 1,
          ),
        ),
      );
      final onTheGrid = Offset(
        layout.halfLeft(0, 0) + 30,
        layout.halfRowsTop(0) + 30,
      );
      await stroke(tester, origin, [
        onTheGrid,
        onTheGrid + const Offset(12, 6),
      ]);
      await stroke(tester, origin, [const Offset(4, 4), const Offset(8, 8)]);

      expect(heard, 0);
      expect(
        controller.hasInkFor(null, window('page-0').key),
        isTrue,
        reason: 'and the press still draws',
      );
    });
  });

  testWidgets('the envelope: a stroke from box to box is the box\'s it '
      'starts in — the next box keeps none of it — and ONE undo', (
    tester,
  ) async {
    final layout = CutEnvelopeLayout.fit(
      form: const CutEnvelopeForm(
        id: 'test',
        name: 'Test',
        aspectRatio: 1,
        boxes: [
          EnvelopeBox(
            id: 'left',
            rect: EnvelopeRect(x: 0, y: 0, width: 0.5, height: 1),
          ),
          EnvelopeBox(
            id: 'right',
            rect: EnvelopeRect(x: 0.5, y: 0, width: 0.5, height: 1),
          ),
        ],
      ),
      paperWidth: 400,
      paperHeight: 400,
    );
    final controller = CutEnvelopeInkController()
      ..syncGeometry(aspectRatio: 1);
    addTearDown(controller.dispose);
    final history = HistoryManager();
    final strokeActive = ValueNotifier<bool>(false);
    addTearDown(strokeActive.dispose);
    final windows = envelopeInkWindows(layout, cutId);
    await tester.binding.setSurfaceSize(const Size(440, 440));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 400,
              child: CutEnvelopeInkOverlay(
                controller: controller,
                windows: windows,
                brushToolState: ValueNotifier(BrushToolState.defaults),
                historyManager: history,
                viewport: CanvasViewport(),
                strokeActive: strokeActive,
              ),
            ),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byType(CutEnvelopeInkOverlay));
    final gesture = await tester.startGesture(
      origin + const Offset(100, 200),
      pointer: 7,
    );
    await tester.pump();
    await gesture.moveTo(origin + const Offset(200, 200));
    await tester.pump();
    await gesture.moveTo(origin + const Offset(300, 200));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final left = windows.singleWhere((window) => window.id == 'left');
    final right = windows.singleWhere((window) => window.id == 'right');
    BitmapSurface surfaceOf(SheetInkWindow window) => controller
        .sessionStateFor(null, window.key)
        .canvasState
        .currentSurface;
    expect(
      inkAt(surfaceOf(left), left.placement.pixelOf(const Offset(150, 200))),
      isTrue,
    );
    expect(
      controller.hasInkFor(null, right.key),
      isFalse,
      reason: 'the box it crossed into takes none of it',
    );
    expect(
      inkAt(surfaceOf(left), left.placement.pixelOf(const Offset(250, 200))),
      isFalse,
      reason: 'past its own box the left box keeps nothing',
    );

    history.undo();
    expect(controller.hasInkFor(null, left.key), isFalse);
  });
}
