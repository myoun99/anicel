import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_book.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_layer.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';
import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/canvas_pill.dart';
import '../../helpers/device_viewport.dart';

/// THE TIMESHEET'S PAGE VIEW LAYS ITS SHEETS ONE UNDER ANOTHER (F-201,
/// 유저 2026-09-27 F-201-timesheet-pages-Q1: 「타임시트 페이지 보기도
/// 쌓는다」) — the conte's and the viewer's law: the strip's ▲▼ scroll to a
/// sheet, the readout reads the sheet you are on, and playback crossing into
/// a sheet moves the view to it.
///
/// ↩️R26 #41 (07-23) showed ONE sheet at a time and swapped the paper under
/// a view that never moved; its pins stood in this file.

/// 150 frames at 24fps and 6s pages = two sheets of paper.
const _twoPageDuration = 150;

const _dataModeKey = ValueKey<String>('timesheet-data-mode-toggle-button');
const _pageModeKey = ValueKey<String>('timesheet-page-mode-toggle-button');
const _prevKey = ValueKey<String>('timesheet-previous-page-button');
const _nextKey = ValueKey<String>('timesheet-next-page-button');
const _pageLabelKey = ValueKey<String>('timesheet-page-readout');
const _pageInputKey = ValueKey<String>('timesheet-page-input');

TimesheetDocument _document({int duration = _twoPageDuration}) {
  return TimesheetDocument.fromCut(
    cut: Cut(
      id: const CutId('cut-1'),
      name: 'Cut 1',
      layers: const [],
      duration: duration,
      canvasSize: const CanvasSize(width: 1280, height: 720),
    ),
    projectName: 'Project',
    fps: 24,
  );
}

/// The default project with its one cut stretched over two sheets.
Project _twoPageProject() {
  final project = createDefaultProject();
  final track = project.tracks.first;
  return project.copyWith(
    tracks: [
      track.copyWith(
        cuts: [track.cuts.first.copyWith(duration: _twoPageDuration)],
      ),
    ],
  );
}

void main() {
  group('TimesheetDocumentLayout — the sheets one under another', () {
    test('page view lays every sheet, each the paper it prints, one under '
        'another — the stack the exports print', () {
      final document = _document();
      final layout = TimesheetDocumentLayout(document: document);
      expect(document.pages, hasLength(2), reason: '⛔전제');

      expect(layout.visiblePageIndexes, [0, 1]);
      expect(layout.pageRect(1).top, greaterThan(layout.pageRect(0).bottom));
      expect(layout.pageRect(0), layout.pageStack.pageRect(0));
      expect(layout.pageRect(1), layout.pageStack.pageRect(1));
      expect(layout.documentSize, layout.pageStack.size);
      // The paper spans both sheets and the gap between them.
      expect(layout.paper.top, layout.pageRect(0).top);
      expect(layout.paper.bottom, layout.pageRect(1).bottom);
    });

    test('a page read past the last sheet reads the last one — a shorter cut '
        'does not strand the reader on blank paper', () {
      final layout = TimesheetDocumentLayout(document: _document());
      final reading = ValueNotifier<int>(9);
      addTearDown(reading.dispose);
      final book = CanvasBook(pages: layout.pageStack, reading: reading);

      expect(book.page, 1);
      expect(layout.pageLabel(book.page), '2/2');
    });

    test('continuous view is one strip — no sheets', () {
      final layout = TimesheetDocumentLayout(
        document: _document(),
        continuous: true,
      );

      expect(layout.visiblePageIndexes, [0]);
      expect(layout.pageLabel(0), '1/1');
    });

    test('ink windows are laid for the pages asked — every page when none '
        'are named', () {
      final document = _document();
      final layout = TimesheetDocumentLayout(document: document);

      final second = timesheetInkWindows(
        layout: layout,
        pagedLayout: layout,
        cutId: const CutId('cut-1'),
        pages: const [1],
      );
      expect(second.map((window) => window.id), [
        'page-1',
        'strip-1-h0',
        'strip-1-h1',
      ]);
      expect(second.first.documentRect, layout.pageRect(1));

      final all = timesheetInkWindows(
        layout: layout,
        pagedLayout: layout,
        cutId: const CutId('cut-1'),
      );
      expect(all, hasLength(6));
    });
  });

  group('Timesheet page view', () {
    late EditorSessionManager session;
    late ValueNotifier<int> reading;

    Future<void> pumpHost(
      WidgetTester tester, {
      bool continuous = false,
      CanvasViewport? render,
    }) async {
      session = EditorSessionManager(initialProject: _twoPageProject());
      addTearDown(session.dispose);
      final inkController = TimesheetInkController();
      addTearDown(inkController.dispose);
      final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
      addTearDown(brushTool.dispose);
      reading = ValueNotifier<int>(0);
      addTearDown(reading.dispose);

      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var isContinuous = continuous;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => TimesheetTabHost(
                session: session,
                continuous: isContinuous,
                onContinuousChanged: (next) =>
                    setState(() => isContinuous = next),
                reading: reading,
                viewport: seedFromRender(tester, render ?? CanvasViewport()),
                onViewportChanged: (_) {},
                inkController: inkController,
                brushToolState: brushTool,
                // Drawing ON: the sheet's ink windows are what follow the
                // pages on screen (the brush switch starts off since
                // 2026-09-25).
                brushAllowed: true,
                onBrushAllowedChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String pageText(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(_pageLabelKey),
            matching: find.byType(Text),
          ),
        )
        .data!;

    bool enabled(WidgetTester tester, Key key) =>
        tester.appIconButton(find.byKey(key)).onPressed != null;

    /// The view the panel paints and hit-tests with.
    CanvasViewport painted(WidgetTester tester) => tester
        .widget<CanvasViewportGestureLayer>(
          find.byType(CanvasViewportGestureLayer),
        )
        .viewport;

    TimesheetDocumentLayout layoutOf() => TimesheetDocumentLayout(
      document: TimesheetDocument.fromCut(
        cut: session.activeCutOrNull!,
        projectName: session.repository.requireProject().name,
        fps: session.projectSettings.projectFps,
      ),
    );

    /// Where [page]'s top stands on screen, down from the panel's top.
    double pageTopOnScreen(WidgetTester tester, int page) {
      final view = painted(tester);
      return layoutOf().pageRect(page).top * view.zoom + view.panY;
    }

    /// Where a turn puts a sheet's top: half a gap under the view's top —
    /// the window's, under the pill's band (유저 2026-09-30: 「판정을
    /// 알약까지 포함해서 판정. 타임시트 최대 스크롤기준이나」).
    double turnedTop(WidgetTester tester) =>
        pillBandOf(tester) +
        layoutOf().pageStack.gap / 2 * painted(tester).zoom;

    testWidgets('the MODES stay in the pill and the PAGES stand on the left '
        'edge, above / n-N / below', (tester) async {
      // 유저 확정 ⑥ (2026-08-13) split what used to be one row. The two mode
      // toggles are things you press while reading and stayed in the pill;
      // turning pages moved to a capsule of its own on the left edge,
      // because three controls at 44px of the pill's shedding budget were
      // most of what a rail-width sheet had to spend — and what it spent
      // them on was losing the lot.
      await pumpHost(tester);

      final xs = <Key, double>{
        for (final key in [_dataModeKey, _pageModeKey])
          key: tester.getCenter(find.byKey(key)).dx,
      };
      // R2 #13: the panbar is its own capsule on the top edge now, so what
      // the cluster is left of is FIT — the head of the view controls it
      // shares the pill with.
      final fitX = tester
          .getCenter(find.byKey(const ValueKey<String>('canvas-viewport-fit')))
          .dx;

      expect(xs[_dataModeKey], lessThan(xs[_pageModeKey]!));
      expect(xs[_pageModeKey], lessThan(fitX));

      // The page cluster reads DOWNWARD in its own capsule, and the whole
      // capsule sits left of the pill it left.
      final ys = <Key, double>{
        for (final key in [_prevKey, _pageLabelKey, _nextKey])
          key: tester.getCenter(find.byKey(key)).dy,
      };
      expect(ys[_prevKey], lessThan(ys[_pageLabelKey]!));
      expect(ys[_pageLabelKey], lessThan(ys[_nextKey]!));
      expect(
        tester
            .getRect(find.byKey(const ValueKey<String>('canvas-page-strip')))
            .right,
        lessThan(
          tester
              .getRect(find.byKey(const ValueKey<String>('canvas-view-pill')))
              .left,
        ),
      );

      // The status strip is gone entirely (R2 #13) and its commands came
      // with the page cluster into the one pill.
      expect(
        find.byKey(const ValueKey<String>('timesheet-brush-toggle-button')),
        findsOneWidget,
      );
      expect(
        tester
            .getCenter(
              find.byKey(
                const ValueKey<String>('timesheet-brush-toggle-button'),
              ),
            )
            .dx,
        lessThan(xs[_dataModeKey]!),
      );
    });

    testWidgets('▼ scrolls to the next sheet — its top half a gap under the '
        'view\'s — and ▲ comes back; the ends disable', (tester) async {
      await pumpHost(tester, render: CanvasViewport());

      expect(pageText(tester), '1/2');
      expect(enabled(tester, _prevKey), isFalse);
      expect(enabled(tester, _nextKey), isTrue);

      await tester.tap(find.byKey(_nextKey));
      await tester.pumpAndSettle();

      expect(reading.value, 1);
      expect(pageText(tester), '2/2');
      expect(pageTopOnScreen(tester, 1), closeTo(turnedTop(tester), 1e-6));
      expect(enabled(tester, _prevKey), isTrue);
      expect(enabled(tester, _nextKey), isFalse);

      await tester.tap(find.byKey(_prevKey));
      await tester.pumpAndSettle();

      expect(reading.value, 0);
      expect(pageText(tester), '1/2');
      expect(
        pageTopOnScreen(tester, 0),
        closeTo(pillBandOf(tester), 1e-6),
        reason: 'the first sheet\'s top stops on the view\'s — the paper, '
            'under the pill\'s band',
      );
    });

    testWidgets('the page readout is the shared drag readout: dragging it '
        'turns pages, a TAP types one', (tester) async {
      await pumpHost(tester);

      // 8px per page (see the strip) — 40px right is well past one page
      // but the last sheet clamps it.
      await tester.drag(find.byKey(_pageLabelKey), const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(reading.value, 1);

      // R10: one tap opens the entry. It used to take a double tap, which
      // put every tap on the readout behind the double-tap window. Tap and
      // drag still do not fight — the drag above proves it: past the slop
      // the drag takes the arena and the tap is refused.
      await tester.tap(find.byKey(_pageLabelKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_pageInputKey), '1');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(reading.value, 0);
    });

    testWidgets('continuous view keeps the cluster mounted but inert (one '
        'strip has no pages to turn)', (tester) async {
      await pumpHost(tester, continuous: true);

      expect(find.byKey(_prevKey), findsOneWidget);
      expect(find.byKey(_nextKey), findsOneWidget);
      expect(enabled(tester, _prevKey), isFalse);
      expect(enabled(tester, _nextKey), isFalse);
      expect(pageText(tester), '1/1');
    });

    testWidgets('the ink windows are the pages\' on screen: scrolling to the '
        'next sheet brings its own, and back takes it away', (tester) async {
      await pumpHost(tester, render: CanvasViewport());
      final second = find.byKey(
        const ValueKey<String>('timesheet-ink-strip-1-h0'),
      );

      expect(
        find.byKey(const ValueKey<String>('timesheet-ink-strip-0-h0')),
        findsOneWidget,
      );
      expect(
        second,
        findsNothing,
        reason: '⛔전제: the second sheet is below the view',
      );

      await tester.tap(find.byKey(_nextKey));
      await tester.pumpAndSettle();
      expect(second, findsOneWidget);

      // Back on the first sheet, the second is below the view again. (The
      // way down is not the mirror: a turn puts the sheet under the pill's
      // band, and the first sheet's tail still shows beside the pill.)
      await tester.tap(find.byKey(_prevKey));
      await tester.pumpAndSettle();
      expect(second, findsNothing);
    });

    testWidgets('playback crossing into the next sheet moves the view to it '
        '— the reader goes where the playhead is', (tester) async {
      await pumpHost(tester, render: CanvasViewport());
      final layout = layoutOf();
      expect(reading.value, 0, reason: '⛔전제');

      session.playbackRig.playback.play(scope: PlaybackScope.allCuts);
      await tester.pump();
      session.playbackRig.playback.seekToGlobalFrame(
        layout.document.pageFrameCount + 2,
      );
      await tester.pump();
      await tester.pump();

      expect(reading.value, 1);
      expect(pageText(tester), '2/2');
      expect(pageTopOnScreen(tester, 1), closeTo(turnedTop(tester), 1e-6));

      session.playbackRig.playback.stop();
      session.playbackRig.prerenderScheduler.cancel();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    });
  });
}
