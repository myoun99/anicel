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
        .sessionStateFor(window.plane! as TimesheetInkPlane, window.key)
        .canvasState
        .currentSurface;

    /// Whether [window]'s surface holds ink under paper point [paper].
    bool inkUnder(SheetInkWindow window, Offset paper) =>
        inkAt(surfaceOf(window), window.placement.pixelOf(paper));

    double rowsHeight(int half) =>
        layout.halfRowCount(half) * TimesheetDocumentLayout.rowHeight;

    Future<Offset> pumpSheet(
      WidgetTester tester, {
      Widget? under,
      ValueNotifier<BrushToolState>? brush,
    }) async {
      layout = TimesheetDocumentLayout(
        document: TimesheetDocument.fromCut(
          cut: Cut(
            id: cutId,
            name: 'Cut 1',
            layers: const [],
            duration: 24,
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
        pagedLayout: layout,
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
                      pagedLayout: layout,
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

    test('each window keeps its own slice: the paper less the strips, the '
        'two halves apart on their one band surface', () {
      layout = TimesheetDocumentLayout(
        document: TimesheetDocument.fromCut(
          cut: Cut(
            id: cutId,
            name: 'Cut 1',
            layers: const [],
            duration: 24,
            canvasSize: const CanvasSize(width: 1280, height: 720),
          ),
          projectName: 'Project',
          fps: 24,
        ),
      );
      windows = timesheetInkWindows(
        layout: layout,
        pagedLayout: layout,
        cutId: cutId,
      );
      final regions = sheetInkRegions(windows);
      CanvasPoint pixelIn(SheetInkWindow window, Offset paper) {
        final pixel = window.placement.pixelOf(paper);
        return CanvasPoint(x: pixel.dx, y: pixel.dy);
      }

      final page = windows.indexWhere((window) => window.id == 'page-0');
      final left = windows.indexWhere((window) => window.id == 'strip-0-h0');
      final right = windows.indexWhere((window) => window.id == 'strip-0-h1');
      final onTheGrid = Offset(
        layout.halfLeft(0, 0) + 30,
        layout.halfRowsTop(0) + 30,
      );
      final onTheMemo = layout.memoBandRect(0).topLeft + const Offset(30, 30);

      expect(
        regions[page]!.containsPoint(pixelIn(windows[page], onTheMemo)),
        isTrue,
      );
      expect(
        regions[page]!.containsPoint(pixelIn(windows[page], onTheGrid)),
        isFalse,
        reason: 'the strip shows that spot, so the strip keeps it',
      );
      // The band surface's rows, where the left half's slice ends.
      final seam = windows[left].surfaceRect.bottom;
      expect(
        regions[left]!.containsPoint(CanvasPoint(x: 30, y: seam - 1)),
        isTrue,
      );
      expect(
        regions[left]!.containsPoint(CanvasPoint(x: 30, y: seam + 1)),
        isFalse,
        reason: 'below its last row the band surface is the right half',
      );
      expect(
        regions[right]!.containsPoint(CanvasPoint(x: 30, y: seam + 1)),
        isTrue,
      );

      // The continuous view is the same law over its own windows: page 1's
      // paper under the one long strip.
      final continuous = TimesheetDocumentLayout(
        document: layout.document,
        continuous: true,
      );
      final strip = timesheetInkWindows(
        layout: continuous,
        pagedLayout: layout,
        cutId: cutId,
      );
      final stripRegions = sheetInkRegions(strip);
      final paper = strip.indexWhere(
        (window) => window.id == 'page-0-continuous',
      );
      final band = strip.indexWhere(
        (window) => window.id == 'strip-0-continuous',
      );
      final onTheStrip = Offset(
        continuous.halfLeft(0, 0) + 30,
        continuous.halfRowsTop(0) + 30,
      );
      expect(
        stripRegions[paper]!.containsPoint(pixelIn(strip[paper], onTheStrip)),
        isFalse,
      );
      expect(
        stripRegions[band]!.containsPoint(pixelIn(strip[band], onTheStrip)),
        isTrue,
      );
      final onTheMemoToo =
          continuous.memoBandRect(0).topLeft + const Offset(30, 30);
      expect(
        stripRegions[paper]!.containsPoint(pixelIn(strip[paper], onTheMemoToo)),
        isTrue,
      );
    });

    testWidgets('a stroke from the memo band into the grid is the page\'s: '
        'the grid keeps none of it — one hold, and ONE undo', (tester) async {
      final origin = await pumpSheet(tester);
      final page = window('page-0');
      final strip = window('strip-0-h0');
      // What the pen being up lets go of — the session's held seeks and cut
      // switches — must find the stroke already landed.
      List<bool>? landedAtRelease;
      strokeActive.addListener(() {
        if (!strokeActive.value) {
          landedAtRelease = [
            controller.hasInkFor(TimesheetInkPlane.page, page.key),
            controller.hasInkFor(TimesheetInkPlane.strip, strip.key),
          ];
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
        isFalse,
        reason: 'the page keeps it where it shows, and the strip shows there',
      );
      expect(
        controller.hasInkFor(TimesheetInkPlane.strip, strip.key),
        isFalse,
        reason: 'the grid it crossed into takes none of it',
      );
      expect(holds, [true, false], reason: 'one pen, one hold');
      expect(landedAtRelease, [true, false]);

      history.undo();
      expect(controller.hasInkFor(TimesheetInkPlane.page, page.key), isFalse);
      history.redo();
      expect(controller.hasInkFor(TimesheetInkPlane.page, page.key), isTrue);
    });

    testWidgets('and one from the grid out onto the memo band is the '
        'strip\'s', (tester) async {
      final origin = await pumpSheet(tester);
      final page = window('page-0');
      final strip = window('strip-0-h0');
      final x = layout.halfLeft(0, 0) + 30;
      final start = Offset(x, layout.halfRowsTop(0) + 60);
      await stroke(tester, origin, [
        start,
        Offset(x, layout.halfRowsTop(0) - 10),
        Offset(x, layout.memoBandRect(0).top + 20),
      ]);

      expect(inkUnder(strip, start), isTrue);
      expect(controller.hasInkFor(TimesheetInkPlane.page, page.key), isFalse);
    });

    testWidgets('the eraser keeps to the window it starts in, as the brush '
        'does — and ONE undo brings back what it rubbed out', (tester) async {
      final brush = ValueNotifier<BrushToolState>(BrushToolState.defaults);
      addTearDown(brush.dispose);
      final origin = await pumpSheet(tester, brush: brush);
      final page = window('page-0');
      final strip = window('strip-0-h0');
      final x = layout.halfLeft(0, 0) + 30;
      final onMemo = Offset(x, layout.memoBandRect(0).top + 20);
      final onGrid = Offset(x, layout.halfRowsTop(0) + 60);
      await stroke(tester, origin, [onMemo, onMemo + const Offset(12, 0)]);
      await stroke(tester, origin, [onGrid, onGrid + const Offset(12, 0)]);
      expect(inkUnder(page, onMemo), isTrue, reason: '⛔CONTROL: drawn');
      expect(inkUnder(strip, onGrid), isTrue, reason: '⛔CONTROL: drawn');

      brush.value = brush.value.copyWith(
        tool: CanvasTool.eraser,
        size: brush.value.size * 4,
      );
      await stroke(tester, origin, [
        onMemo,
        Offset(x, layout.halfRowsTop(0) - 10),
        onGrid,
      ]);
      expect(inkUnder(page, onMemo), isFalse, reason: 'where it started');
      expect(
        inkUnder(strip, onGrid),
        isTrue,
        reason: 'the grid it crossed into kept its ink',
      );

      history.undo();
      expect(inkUnder(page, onMemo), isTrue);
    });

    testWidgets('off the bottom of the left half nothing lands in the right '
        'half — the same band surface', (tester) async {
      final origin = await pumpSheet(tester);
      final x = layout.halfLeft(0, 0) + 30;
      final seam = layout.halfRowsTop(0) + rowsHeight(0);
      await stroke(tester, origin, [
        Offset(x, seam - 40),
        Offset(x, seam - 10),
        Offset(x, seam + 30),
      ]);

      final left = window('strip-0-h0');
      expect(inkUnder(left, Offset(x, seam - 20)), isTrue);
      // Where the left half's own mapping puts the part below its last
      // row: the band surface's rows the RIGHT half shows, at its top.
      expect(
        inkUnder(left, Offset(x, seam + 12)),
        isFalse,
        reason: 'the top of the right half is not where the pen went',
      );
    });

    testWidgets('a stroke across the halves keeps to the half it starts in: '
        'the paper between and the other half keep none of it', (
      tester,
    ) async {
      final origin = await pumpSheet(tester);
      final y = layout.halfRowsTop(0) + 100;
      final leftEnd = layout.halfLeft(0, 0) + layout.halfWidth;
      final rightStart = layout.halfLeft(0, 1);
      await stroke(tester, origin, [
        Offset(leftEnd - 30, y),
        Offset((leftEnd + rightStart) / 2, y),
        Offset(rightStart + 30, y),
      ]);

      final page = window('page-0');
      final left = window('strip-0-h0');
      final right = window('strip-0-h1');
      expect(inkUnder(left, Offset(leftEnd - 20, y)), isTrue);
      expect(
        inkUnder(right, Offset(rightStart + 20, y)),
        isFalse,
        reason: 'the right half is the same band surface, and none of the '
            'stroke reached it',
      );
      expect(
        controller.hasInkFor(TimesheetInkPlane.page, page.key),
        isFalse,
        reason: 'nor the paper between the halves',
      );

      history.undo();
      expect(controller.hasInkFor(TimesheetInkPlane.strip, left.key), isFalse);
    });

    testWidgets('🚨F-233: a window reads its band when the pen lands, not when '
        'it was last built', (tester) async {
      // An undo or a stroke just landed changes the band inside its own
      // event, and the window builds again at the next frame. A pen that
      // lands in between draws on the band as it stands — the view asks
      // its host, and the host asks the controller then.
      await pumpSheet(tester);
      final window = windows.singleWhere((w) => w.id == 'strip-0-h0');
      final plane = window.plane! as TimesheetInkPlane;
      final view = tester.widget<InteractiveBrushEditCanvasView>(
        find.byKey(const ValueKey<String>('timesheet-ink-strip-0-h0')),
      );
      final before = view.celNow();

      controller.commitStroke(
        plane: plane,
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
          .sessionStateFor(plane, window.key)
          .canvasState
          .currentSurface;
      expect(
        identical(landed, before),
        isFalse,
        reason: '⛔premise: the stroke landed on the band',
      );
      expect(
        identical(view.celNow(), landed),
        isTrue,
        reason: 'no frame has built since, and the window still answers '
            'with the band as it stands',
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
                    sessionStateFor: (window) => controller.sessionStateFor(
                      window.plane! as TimesheetInkPlane,
                      window.key,
                    ),
                    onStrokeCommitted: (window, strokeData) =>
                        controller.commitStroke(
                          plane: window.plane! as TimesheetInkPlane,
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
        controller.hasInkFor(
          TimesheetInkPlane.strip,
          window('strip-0-h0').key,
        ),
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
