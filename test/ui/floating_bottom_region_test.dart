import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/canvas_visible_rect.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

import '../helpers/brush_canvas_fixture.dart';
import '../helpers/panel_finders.dart';

/// The timeline came OFF the canvas.
///
/// It used to be a sibling in a column: it took its height out of the
/// drawing, and the drawing's box was the drawing's window. Now the canvas
/// is the app's floor — laid out full-bleed under everything — and the
/// timeline is a shape lying on it. Three things have to be true for that
/// to be an improvement rather than a picture of one: the corners it cut
/// away must not still take pointers, the panel must still say which panel
/// it is, and every verb that frames the artwork must aim at what is left
/// visible rather than at the box.
void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(1600, 1000),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
  }

  Finder region() =>
      find.byKey(const ValueKey<String>('floating-bottom-region'));

  group('the floating region lies ON the canvas', () {
    testWidgets('the canvas runs underneath it instead of stopping at it', (
      tester,
    ) async {
      await pumpApp(tester);

      final canvas = tester.getRect(mainCanvasPanelShell());
      final timeline = tester.getRect(region());

      expect(
        canvas.bottom,
        greaterThan(timeline.top),
        reason: 'the canvas box extends under the timeline, not up to it',
      );
      // …and all the way to the window's own bottom edge.
      expect(canvas.bottom, closeTo(timeline.bottom, 0.5));
    });

    testWidgets('a cut-away corner falls through to the canvas', (
      tester,
    ) async {
      await pumpApp(tester);
      final timeline = tester.getRect(region());
      final regionRender = tester.renderObject(region());

      // Whether a pointer at [point] is taken by the floating region, read
      // off the real hit path rather than off a rectangle: walk each hit
      // target up its render tree and see whether the region is an
      // ancestor.
      bool takenByRegion(Offset point) {
        return tester.hitTestOnBinding(point).path.any((entry) {
          final target = entry.target;
          if (target is! RenderObject) {
            return false;
          }
          for (RenderObject? node = target; node != null; node = node.parent) {
            if (identical(node, regionRender)) {
              return true;
            }
          }
          return false;
        });
      }

      // The body of the region takes its own pointers — so the corner
      // assertion below cannot be passing because nothing is there at all.
      expect(takenByRegion(timeline.center), isTrue);
      expect(find.byType(TimelinePanel), findsOneWidget);

      // Two pixels in from the top-left corner: outside the superellipse,
      // so this belongs to the drawing underneath. The clip is
      // load-bearing, not decoration — ClipRSuperellipse paints the same
      // silhouette but keeps hit-testing the full rectangle, which would
      // leave a dead square of canvas at each corner.
      expect(takenByRegion(timeline.topLeft + const Offset(2, 2)), isFalse);
      expect(takenByRegion(timeline.topRight + const Offset(-2, 2)), isFalse);
    });
  });

  group('the 문턱', () {
    testWidgets('sits on the bottom inner edge — geometry toward the canvas, '
        'identity toward the frame', (tester) async {
      await pumpApp(tester);

      final timeline = tester.getRect(region());
      final strip = tester.getRect(
        find
            .descendant(of: region(), matching: find.byType(EditorPanelTabs))
            .first,
      );
      final threshold = Rect.fromLTRB(
        strip.left,
        strip.bottom - EditorPanelTabs.stripHeight,
        strip.right,
        strip.bottom,
      );

      expect(
        threshold.bottom,
        closeTo(timeline.bottom, 0.5),
        reason: 'the threshold is against the window frame',
      );
      // The resize handle is on the OTHER edge — the one facing the
      // artwork. Same law, read from the opposite side. It lies ON that
      // edge, inside the region's own clip, so hovering it lights the
      // panel's edge and the corners follow the silhouette (R2 #11).
      final splitter = tester.getRect(
        find.byKey(const ValueKey<String>('dock-resize-bottom')),
      );
      expect(splitter.top, closeTo(timeline.top, 0.5));
    });

    testWidgets('the side grips stop at it — the leading tab keeps its lift '
        'zone, on either edge', (tester) async {
      await pumpApp(tester);

      Rect grip(String id) => tester.getRect(find.byKey(ValueKey<String>(id)));
      Rect leadingTab() => tester.getRect(
        find.byKey(const ValueKey<String>('timeline-mode-timeline-button')),
      );
      Rect collapseButton() => tester.getRect(
        find.byKey(const ValueKey<String>('floating-bottom-collapse')),
      );

      // Two edge gestures, five pixels. The side grip runs the region's
      // whole side and the strip's LEADING tab carries its 8px lift zone in
      // the same corner; the splitter hit-tests opaque, so while it reached
      // the frame-facing edge the first panel of the region could not be
      // lifted at all — and the same bite took the collapse button's
      // trailing edge on the other side.
      expect(grip('bottom-inset-left').overlaps(leadingTab()), isFalse);
      expect(grip('bottom-inset-right').overlaps(collapseButton()), isFalse);

      // Numbers are not the promise: the zone is the ONLY surface that
      // lifts a tab, so it has to actually lift this one. With the drag
      // live, every eligible dock puts its drop bands up.
      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey<String>('panel-grip-timeline')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      // The oracle used to be `dock-drop-join-`, a band painted over a
      // panel's body — the free-form docking that is gone, and the rails'
      // own drop zones only mount when a rail is EMPTY, so neither can say
      // whether a lift happened. The grip itself can: it goes accent the
      // moment it is actually dragging something, which is the contract
      // this test is really about.
      expect(
        tester
            .widget<ColoredBox>(
              find.descendant(
                of: find.byKey(const ValueKey<String>('panel-grip-timeline')),
                matching: find.byType(ColoredBox),
              ),
            )
            .color,
        AppColors.accent,
        reason: 'the tab lifted',
      );
      await gesture.up();
      await tester.pumpAndSettle();

      // Which 30px the grips leave alone is not a rule of their own: it
      // follows the threshold, so it flips with the region.
      await tester.tap(
        find.byKey(const ValueKey<String>('top-strip-settings-button')),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(
        const ValueKey<String>('menu-window-region-on-top'),
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(grip('bottom-inset-left').overlaps(leadingTab()), isFalse);
      expect(grip('bottom-inset-right').overlaps(collapseButton()), isFalse);
    });

    testWidgets('collapse shrinks the region without closing it', (
      tester,
    ) async {
      await pumpApp(tester);
      final open = tester.getRect(region()).height;

      await tester.tap(
        find.byKey(const ValueKey<String>('floating-bottom-collapse')),
      );
      await tester.pumpAndSettle();

      final collapsed = tester.getRect(region());
      expect(collapsed.height, lessThan(open));
      // Collapsed is not closed: the region is still on screen, still
      // carries its threshold, and is therefore still a drop target.
      expect(region(), findsOneWidget);
      expect(
        collapsed.height,
        greaterThanOrEqualTo(EditorPanelTabs.stripHeight),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('floating-bottom-collapse')),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(region()).height, closeTo(open, 0.5));
    });
  });

  group('docking the region on the other edge', () {
    testWidgets('flips the whole geometry out of ONE flag — handle, '
        'threshold, corners and cover', (tester) async {
      await pumpApp(tester);

      Rect regionRect() => tester.getRect(region());
      Rect handle() => tester.getRect(
        find.byKey(const ValueKey<String>('dock-resize-bottom')),
      );
      Rect threshold() => tester.getRect(
        find
            .descendant(of: region(), matching: find.byType(EditorPanelTabs))
            .first,
      );

      // Docked at the bottom: 기하는 캔버스 향한 변에 (the handle is on the
      // TOP edge, facing the artwork), 정체성은 창틀 향한 변에 (the 문턱 is
      // on the bottom, against the frame).
      final low = regionRect();
      expect(handle().top, closeTo(low.top, 0.5));
      expect(threshold().bottom, closeTo(low.bottom, 0.5));
      final canvas = tester.getRect(mainCanvasPanelShell());
      expect(low.bottom, closeTo(canvas.bottom, 0.5));

      await tester.tap(
        find.byKey(const ValueKey<String>('top-strip-settings-button')),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(
        const ValueKey<String>('menu-window-region-on-top'),
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();

      // Both edges flip, and neither needed a rule of its own.
      final high = regionRect();
      expect(high.top, closeTo(canvas.top, 0.5));
      expect(
        handle().bottom,
        closeTo(high.bottom, 0.5),
        reason: 'the handle followed the artwork-facing edge',
      );
      expect(
        threshold().top,
        closeTo(high.top, 0.5),
        reason: 'the threshold followed the frame-facing edge',
      );

      // And the FLOOR is told the cover moved with it, so Fit still frames
      // the artwork where it can be seen.
      final panel = tester.widget<BrushCanvasPanel>(mainCanvasPanelShell());
      expect(panel.floorCover.top, greaterThan(0));
      expect(panel.floorCover.bottom, 0);
    });
  });

  group('the floor knows what is covering it', () {
    testWidgets('the canvas is told exactly what the panels hide', (
      tester,
    ) async {
      await pumpApp(tester);

      final panel = tester.widget<BrushCanvasPanel>(mainCanvasPanelShell());
      final cover = panel.floorCover;
      expect(cover, isNotNull, reason: 'the main canvas IS the floor');

      final box = tester.getRect(mainCanvasPanelShell());
      final timeline = tester.getRect(region());
      // What it was told and what is actually there agree. Two numbers that
      // can drift apart is the whole failure mode this guards.
      expect(
        box.bottom - cover.bottom,
        lessThanOrEqualTo(timeline.top + 0.5),
        reason: 'the window stops at or above the timeline, never under it',
      );
    });

    testWidgets('Fit puts the artwork in the window, not under the timeline', (
      tester,
    ) async {
      await pumpApp(tester);

      final fit = find.descendant(
        of: mainCanvasPanelShell(),
        matching: find.byKey(const ValueKey<String>('canvas-viewport-fit')),
      );
      await tester.tap(fit);
      await tester.pumpAndSettle();

      final panel = tester.widget<BrushCanvasPanel>(mainCanvasPanelShell());
      final box = tester.getRect(mainCanvasPanelShell());
      final window = canvasVisibleRect(box.size, panel.floorCover);
      final timeline = tester.getRect(region());

      // The window Fit aimed at is entirely above the timeline. A Fit
      // against the BOX would have centred the drawing a third of the way
      // into the panel.
      expect(window.bottom + box.top, lessThanOrEqualTo(timeline.top + 0.5));
      expect(window.height, greaterThan(0));
      expect(find.byType(EditorCanvasArea), findsOneWidget);
    });
  });

  group('the floor wears capsules, not bands', () {
    // SCOPED to the floor. Every canvas panel wears these now (R2 #13), so
    // an app-wide finder matches the timesheet's too.
    Finder onFloor(String key) => find.descendant(
      of: mainCanvasPanelShell(),
      matching: find.byKey(ValueKey<String>(key)),
    );
    Finder pill() => onFloor('canvas-view-pill');
    Finder hBar() => onFloor('canvas-panbar-horizontal');
    Finder vBar() => onFloor('canvas-panbar-vertical');

    testWidgets('the panbars centre on WHAT YOU CAN SEE', (tester) async {
      await pumpApp(tester);

      final timeline = tester.getRect(region());
      final pillRect = tester.getRect(pill());
      final canvas = tester.getRect(mainCanvasPanelShell());
      final panel = tester.widget<BrushCanvasPanel>(mainCanvasPanelShell());
      final visible = canvasVisibleRect(
        canvas.size,
        panel.floorCover,
      ).shift(canvas.topLeft);

      // 유저, R3 #5·#6 — the third pass over this. Pinned to the panel they
      // hid under the timeline; pinned to the panel's centre they sat in
      // the middle of a rectangle a third of which is covered. They centre
      // on the VISIBLE rectangle: the vertical one walks up as the region
      // grows, the horizontal one rides its BOTTOM edge.
      expect(tester.getRect(vBar()).center.dy, closeTo(visible.center.dy, 1.0));
      expect(tester.getRect(hBar()).center.dx, closeTo(visible.center.dx, 1.0));
      expect(tester.getRect(hBar()).bottom, lessThanOrEqualTo(timeline.top));

      // 알약은 상단중앙 (유저, R3 #6) — and clear of the region.
      expect(pillRect.center.dx, closeTo(visible.center.dx, 1.0));
      expect(pillRect.top, lessThan(timeline.top));

      // It is not a band: it covers a small fraction of the width it rides,
      // which is the whole difference from the strips it replaced.
      expect(tester.getRect(hBar()).width, lessThan(canvas.width * 0.5));
      expect(pillRect.width, lessThan(canvas.width * 0.5));

      // Opposite edges now, so they cannot share a pixel at any width.
      expect(pillRect.overlaps(tester.getRect(hBar())), isFalse);
    });

    testWidgets('widening a rail pushes the pill in instead of hiding it '
        'under the panel', (tester) async {
      // The pill is centred on what you can SEE, so widening the right
      // rail walks it left.
      await pumpApp(tester);
      final before = tester.getRect(pill()).center.dx;

      await tester.drag(
        find.byKey(const ValueKey<String>('dock-resize-rail-R2')),
        const Offset(-120, 0),
      );
      await tester.pumpAndSettle();

      expect(tester.getRect(pill()).center.dx, lessThan(before));
    });

    testWidgets('the vertical panbar steps aside only for a rail that is '
        'actually beside it', (tester) async {
      // 유저, R3 #5: a rail panel is as tall as it was left at, so a short
      // one covers a BAND and not an edge. Stepping in for the whole edge
      // left the bar hanging in the middle of nothing.
      await pumpApp(tester);
      // At its saved height the panel DOES reach the bar's row, so it is
      // stepped in to begin with.
      final dodged = tester.getRect(vBar()).right;

      // Pull the panel up above the bar and the bar takes the edge back.
      await tester.drag(
        find.byKey(const ValueKey<String>('dock-resize-rail-R2-height')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      final atEdge = tester.getRect(vBar()).right;
      expect(
        atEdge,
        greaterThan(dodged),
        reason: 'nothing is beside it any more, so it stops standing aside',
      );

      // And grow it back down and the bar yields again.
      await tester.drag(
        find.byKey(const ValueKey<String>('dock-resize-rail-R2-height')),
        const Offset(0, 400),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(vBar()).right, lessThan(atEdge));
    });

    testWidgets('EVERY canvas panel gets a pill, and only the floor gets '
        'rotate and flip', (tester) async {
      // ⚠️「뷰 컨트롤은 바닥에만」 is PARTLY REPEALED (유저, R2 #13). The law
      // gave the floor every view control and the paper panels two
      // scrollbars, on the reading that a timesheet is a page you read
      // beside the drawing. In the hand a page you read is a page you
      // zoom, so Fit and the zoom steps come back everywhere. Rotate and
      // flip do not: a sheet with a form printed on it has no reason to be
      // turned over.
      await pumpApp(tester);

      expect(
        find.descendant(
          of: mainCanvasPanelShell(),
          matching: find.byKey(const ValueKey<String>('canvas-viewport-fit')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: timesheetPanel(),
          matching: find.byKey(const ValueKey<String>('canvas-viewport-fit')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: timesheetPanel(),
          matching: find.byKey(const ValueKey<String>('canvas-viewport-flip')),
        ),
        findsNothing,
      );
    });

    testWidgets('the cluster fades out of the way of a stroke', (tester) async {
      // A panel that is drawable, standing in for the floor — the app's
      // empty default project has no cel under the playhead, so no stroke
      // can start in it and the assertion below would pass vacuously.
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: BrushCanvasPanel(
                coordinator: BrushCanvasFixture.createCoordinator(
                  frameKeys: frameKeys,
                ),
                availableFrameKeys: frameKeys,
                cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                floorCover: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      double clusterOpacity() => tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey<String>('canvas-floating-controls')),
          )
          .opacity;

      expect(clusterOpacity(), 1.0);

      // Hover is not available to answer this: touch has none, and a pen
      // hovers over the DRAWING rather than over the controls. What the app
      // already knows is that a stroke is live, and that is the moment the
      // controls are in the way.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(InteractiveBrushEditCanvasView)),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();
      await gesture.moveBy(const Offset(20, 12));
      await tester.pump();

      expect(clusterOpacity(), lessThan(1.0));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(clusterOpacity(), 1.0);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    });
  });
}
