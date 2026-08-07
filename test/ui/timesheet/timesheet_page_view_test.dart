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
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_layer.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';

/// 150 frames at 24fps and 6s pages = two sheets of paper.
const _twoPageDuration = 150;

const _dataModeKey = ValueKey<String>('timesheet-data-mode-toggle-button');
const _pageModeKey = ValueKey<String>('timesheet-page-mode-toggle-button');
const _prevKey = ValueKey<String>('timesheet-page-prev-button');
const _nextKey = ValueKey<String>('timesheet-page-next-button');
const _pageLabelKey = ValueKey<String>('timesheet-page-label');
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
  group('TimesheetDocumentLayout single page (R26 #41)', () {
    test('page view is ONE sheet of paper: the document is one page tall and '
        'the visible page prints at the top margin', () {
      final document = _document();
      final stacked = TimesheetDocumentLayout(document: document);
      expect(document.pages, hasLength(2));

      final second = TimesheetDocumentLayout(document: document, singlePage: 1);

      expect(second.visiblePageIndexes, [1]);
      expect(second.documentSize.height, stacked.paperHeight + 48);
      // The second sheet moved UP to where the first one used to print —
      // turning the page swaps the paper, it does not scroll the stack.
      expect(second.pageRect(1), stacked.pageRect(0));
      // The paper itself never changes with the view mode (the standing
      // sheet rule).
      expect(second.paperWidth, stacked.paperWidth);
      expect(second.paperHeight, stacked.paperHeight);
    });

    test('the stacked layout is unchanged when no page is pinned (exports, '
        'focused tests)', () {
      final document = _document();
      final stacked = TimesheetDocumentLayout(document: document);

      expect(stacked.resolvedSinglePage, isNull);
      expect(stacked.visiblePageIndexes, [0, 1]);
      expect(stacked.pageTop(1), greaterThan(stacked.pageTop(0)));
    });

    test('a page index past the last sheet clamps instead of stranding the '
        'reader on blank paper', () {
      final layout = TimesheetDocumentLayout(
        document: _document(),
        singlePage: 9,
      );

      expect(layout.resolvedSinglePage, 1);
      expect(layout.visiblePageIndexes, [1]);
      expect(layout.pageLabel(layout.resolvedSinglePage!), '2/2');
    });

    test('continuous view ignores the pinned page — one strip, no pages', () {
      final layout = TimesheetDocumentLayout(
        document: _document(),
        continuous: true,
        singlePage: 1,
      );

      expect(layout.resolvedSinglePage, isNull);
      expect(layout.visiblePageIndexes, [0]);
      expect(layout.pageLabel(0), '1/1');
    });

    test('ink windows mount for the visible page ONLY (the off-screen '
        'sheets keep their surfaces, they just have no window)', () {
      final document = _document();
      final paged = TimesheetDocumentLayout(document: document);
      final second = TimesheetDocumentLayout(document: document, singlePage: 1);

      final windows = timesheetInkWindows(
        layout: second,
        pagedLayout: paged,
        cutId: const CutId('cut-1'),
      );

      // One page window + two strip halves, all page 1's.
      expect(windows, hasLength(3));
      expect(windows.map((window) => window.id), [
        'page-1',
        'strip-1-h0',
        'strip-1-h1',
      ]);
      expect(windows.first.documentRect, second.pageRect(1));
    });
  });

  group('Timesheet page navigation (R26 #41)', () {
    late EditorSessionManager session;
    late int page;

    Future<void> pumpHost(
      WidgetTester tester, {
      bool continuous = false,
    }) async {
      session = EditorSessionManager(initialProject: _twoPageProject());
      addTearDown(session.dispose);
      final inkController = TimesheetInkController();
      addTearDown(inkController.dispose);
      final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
      addTearDown(brushTool.dispose);

      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      page = 0;
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
                page: page,
                onPageChanged: (next) => setState(() => page = next),
                viewport: CanvasViewport(),
                onViewportChanged: (_) {},
                inkController: inkController,
                brushToolState: brushTool,
                onInkEnabledChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String pageText(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(of: find.byKey(_pageLabelKey), matching: find.byType(Text)),
        )
        .data!;

    bool enabled(WidgetTester tester, Key key) =>
        tester.widget<IconButton>(find.byKey(key)).onPressed != null;

    testWidgets('the bottom bar carries the sheet cluster left of the '
        'panbar, in the user order: data / page-mode / ◀ / n-N / ▶', (
      tester,
    ) async {
      await pumpHost(tester);

      final xs = <Key, double>{
        for (final key in [
          _dataModeKey,
          _pageModeKey,
          _prevKey,
          _pageLabelKey,
          _nextKey,
        ])
          key: tester.getCenter(find.byKey(key)).dx,
      };
      // R2 #13: the panbar is its own capsule on the top edge now, so what
      // the cluster is left of is FIT — the head of the view controls it
      // shares the pill with.
      final fitX = tester
          .getCenter(find.byKey(const ValueKey<String>('canvas-viewport-fit')))
          .dx;

      expect(xs[_dataModeKey]!, lessThan(xs[_pageModeKey]!));
      expect(xs[_pageModeKey]!, lessThan(xs[_prevKey]!));
      expect(xs[_prevKey]!, lessThan(xs[_pageLabelKey]!));
      expect(xs[_pageLabelKey]!, lessThan(xs[_nextKey]!));
      expect(xs[_nextKey]!, lessThan(fitX));

      // The status strip is gone entirely (R2 #13) and its commands came
      // with the page cluster into the one pill.
      expect(
        find.byKey(const ValueKey<String>('timesheet-ink-toggle-button')),
        findsOneWidget,
      );
      expect(
        tester
            .getCenter(
              find.byKey(
                const ValueKey<String>('timesheet-ink-toggle-button'),
              ),
            )
            .dx,
        lessThan(xs[_dataModeKey]!),
      );
    });

    testWidgets('▶ turns to the next sheet and ◀ comes back; the ends '
        'disable', (tester) async {
      await pumpHost(tester);

      expect(pageText(tester), '1/2');
      expect(enabled(tester, _prevKey), isFalse);
      expect(enabled(tester, _nextKey), isTrue);

      await tester.tap(find.byKey(_nextKey));
      await tester.pumpAndSettle();

      expect(page, 1);
      expect(pageText(tester), '2/2');
      expect(enabled(tester, _prevKey), isTrue);
      expect(enabled(tester, _nextKey), isFalse);

      await tester.tap(find.byKey(_prevKey));
      await tester.pumpAndSettle();

      expect(page, 0);
      expect(pageText(tester), '1/2');
    });

    testWidgets('the page readout is the shared drag readout: dragging it '
        'turns pages, a TAP types one', (tester) async {
      await pumpHost(tester);

      // 8px per page (see the host) — 40px right is well past one page but
      // the last sheet clamps it.
      await tester.drag(find.byKey(_pageLabelKey), const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(page, 1);

      // R10: one tap opens the entry. It used to take a double tap, which
      // put every tap on the readout behind the double-tap window. Tap and
      // drag still do not fight — the drag above proves it: past the slop
      // the drag takes the arena and the tap is refused.
      await tester.tap(find.byKey(_pageLabelKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_pageInputKey), '1');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(page, 0);
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

    testWidgets('page view mounts one sheet of ink windows; turning the page '
        'swaps which', (tester) async {
      await pumpHost(tester);

      expect(
        find.byKey(const ValueKey<String>('timesheet-ink-strip-0-h0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('timesheet-ink-strip-1-h0')),
        findsNothing,
      );

      await tester.tap(find.byKey(_nextKey));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('timesheet-ink-strip-0-h0')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('timesheet-ink-strip-1-h0')),
        findsOneWidget,
      );
    });
  });
}
