import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/canvas_visible_rect.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

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
  Future<void> pumpApp(WidgetTester tester, {Size size = const Size(1600, 1000)}) async {
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
      expect(
        takenByRegion(timeline.topRight + const Offset(-2, 2)),
        isFalse,
      );
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
      // artwork. Same law, read from the opposite side.
      final splitter = tester.getRect(
        find.byKey(const ValueKey<String>('dock-resize-bottom')),
      );
      expect(splitter.bottom, lessThanOrEqualTo(timeline.top + 0.5));
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
        box.bottom - cover!.bottom,
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
      final window = canvasVisibleRect(
        box.size,
        panel.floorCover! + BrushCanvasPanel.floorChromeInsets,
      );
      final timeline = tester.getRect(region());

      // The window Fit aimed at is entirely above the timeline. A Fit
      // against the BOX would have centred the drawing a third of the way
      // into the panel.
      expect(window.bottom + box.top, lessThanOrEqualTo(timeline.top + 0.5));
      expect(window.height, greaterThan(0));
      expect(find.byType(EditorCanvasArea), findsOneWidget);
    });
  });
}
