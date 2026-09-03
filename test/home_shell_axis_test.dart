// HomePage widget tests — the shell, the frame axis and its zoom.
// Split from widget_test.dart (2026-09-04) so the suite runs across
// isolates; the shared probes live in helpers/home_page_probes.dart.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/ui/layout/device_grid_safe_area.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

import 'ui/timeline/timeline_ruler_probe.dart';

import 'helpers/home_page_probes.dart';

void main() {
  testWidgets('shows placeholder app shell', (WidgetTester tester) async {
    await tester.pumpWidget(const AnicelApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    // PEN-8 #1: the editor body sits inside a safe area so tablet OS
    // chrome (status bar, gesture areas) never overlaps the app.
    //
    // R11: a DeviceGridSafeArea, not a bare SafeArea. Same intent, plus
    // the inset is floored onto the device-pixel grid — it is the FIRST
    // link in the window-origin chain, and a fractional inset there puts
    // every panel below it between two device pixels.
    expect(find.byType(DeviceGridSafeArea), findsWidgets);
    // R26 #24: the app-name label is gone from the top strip.
    expect(find.text('Anicel'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('new-frame-button')),
      findsOneWidget,
    );
    expect(find.byTooltip('Add'), findsOneWidget);
    await expectCutName(tester, 'default-cut-1', '1');
    await expectActiveCutName(tester, '1');
    expect(find.text('New Drawing'), findsNothing);

    // Cut management rides the toolbar's cut group (R-toolbar round): a
    // split new-cut button plus the Cut ▾ flyout with the command set.
    expect(find.byTooltip('New cut'), findsOneWidget);
    final cutMenu = find.byKey(const ValueKey<String>('cut-menu-button'));
    await tester.ensureVisible(cutMenu);
    await tester.pumpAndSettle();
    await tester.tap(cutMenu);
    await tester.pumpAndSettle();
    for (final item in [
      'rename-cut-button',
      'edit-cut-note-button',
      'resize-cut-canvas-button',
      'duplicate-cut-button',
      'set-cut-thumbnail-button',
      'move-cut-left-button',
      'move-cut-right-button',
    ]) {
      expect(find.byKey(ValueKey<String>(item)), findsOneWidget);
    }
    await tester.tapAt(const Offset(5, 400));
    await tester.pumpAndSettle();
  });

  testWidgets('default sample cut duration is 24 frames', (
    WidgetTester tester,
  ) async {
    withTouchScroll();
    await tester.pumpWidget(const AnicelApp());

    // The bottom dock runs between the two vertical tool bars, so the
    // grid viewport is 88px narrower than the window — scroll far enough
    // for the cut's last frame header to materialize (24px slim cells:
    // don't overshoot past it either).
    await tester.drag(
      find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
      const Offset(-350, 0),
    );
    await tester.pumpAndSettle();

    expect(timelineHeaderInWindow(tester, 23), isTrue);
  });

  testWidgets('timeline frame axis: scrolling stays CLAMPED to the built '
      'cells; the ruler edge-drag alone extends it (UI-R12 #16)', (
    WidgetTester tester,
  ) async {
    withTouchScroll();
    await tester.pumpWidget(const AnicelApp());

    // Painterized ruler (UI-R13 #1): headers past the base exist exactly
    // when the painter's window reaches past 48.
    bool beyondBaseHeaders() =>
        timelineRulerPainter(tester).frameEndIndexExclusive > 48;

    // Scroll gestures wall at the built extent (base 48 cells): however
    // far the viewport is flung, nothing past the base materializes and
    // the scrollbar range never grows from scrolling.
    for (var i = 0; i < 3; i += 1) {
      await tester.drag(
        find.byKey(const ValueKey<String>('timeline-frame-scroll-viewport')),
        const Offset(-1200, 0),
      );
      await tester.pumpAndSettle();
    }
    expect(beyondBaseHeaders(), isFalse);

    // The ruler edge-drag is THE way past the wall: a scrub held at the
    // right edge pans the axis (overshooting the built extent) and the
    // growth listener materializes the frames the view needs.
    final rulerRect = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-frame-ruler-scrub-area')),
    );
    final gesture = await tester.startGesture(
      Offset(rulerRect.right - 30, rulerRect.center.dy),
    );
    for (var i = 0; i < 12; i += 1) {
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(beyondBaseHeaders(), isTrue);
  });

  testWidgets('timeline zoom buttons rescale the frame axis', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    // 24 at 100% — the slim default (R-toolbar round); the painterized
    // ruler (UI-R13 #1) reports geometry/labels through its painter.
    double headerWidth() => timelineHeaderGlobalRect(tester, 0).width;
    expect(headerWidth(), 24);
    // Wide cells label every frame in-cell.
    expect(timelineHeaderModel(tester, 0).label, '1');

    Future<void> zoomTo(double pixelsPerFrame) async {
      tester
          .widget<FieldSlider>(
            find.byKey(const ValueKey<String>('timeline-zoom-slider')),
          )
          .onChanged!(pixelsPerFrame);
      await tester.pumpAndSettle();
    }

    await zoomTo(72);
    expect(headerWidth(), 72);

    // UI-R11 #11: the −/+ STEP buttons flanking the slider zoom without
    // dragging — multiplicative ×1.25 steps on the whole-px grid.
    await zoomTo(24);
    await tapToolbarButton(
      tester,
      const ValueKey<String>('timeline-zoom-in-button'),
    );
    expect(headerWidth(), 30, reason: '24 × 1.25');
    await tapToolbarButton(
      tester,
      const ValueKey<String>('timeline-zoom-out-button'),
    );
    await tapToolbarButton(
      tester,
      const ValueKey<String>('timeline-zoom-out-button'),
    );
    expect(headerWidth(), 19, reason: '30 ÷ 1.25 ÷ 1.25');

    await zoomTo(12);
    expect(headerWidth(), 12);
    // Narrow cells move their labels to the every-Nth ladder: unlabeled
    // headers read '' off the painter model (frame 1 stays the anchor).
    expect(timelineHeaderModel(tester, 1).label, '');
    expect(timelineHeaderModel(tester, 0).label, isNotEmpty);
  });

  testWidgets('xsheet zoom rescales the frame row height', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());
    await tapToolbarButton(
      tester,
      const ValueKey<String>('timeline-orientation-toggle-button'),
    );

    // The rail is painterized (UI-R14 #1): row geometry probes off its
    // painter.
    //
    // R10 R6: a frame ROW is a frame CELL turned on its side, so the sheet
    // reads the slider 1:1 instead of scaling it by an old 36/24 ratio —
    // one slider position now means one frame extent on both surfaces.
    expect(xsheetFrameRowGlobalRect(tester, 0).height, timelineFrameCellWidth);

    tester
        .widget<FieldSlider>(
          find.byKey(const ValueKey<String>('timeline-zoom-slider')),
        )
        .onChanged!(72);
    await tester.pumpAndSettle();
    expect(xsheetFrameRowGlobalRect(tester, 0).height, 72);
  });

  testWidgets('the time display toggle switches the counter to seconds', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AnicelApp());

    String counterText() => tester
        .widget<Text>(
          find.byKey(const ValueKey<String>('timeline-local-frame-counter')),
        )
        .data!;
    expect(counterText(), '1');

    await tapToolbarButton(
      tester,
      const ValueKey<String>('timeline-time-display-toggle-button'),
    );
    // Frame 1 at 24fps in conte notation — bare digits, the sheet's own
    // (feedback #12); this used to read `0+01`.
    expect(counterText(), '0+1');

    await tapToolbarButton(
      tester,
      const ValueKey<String>('timeline-time-display-toggle-button'),
    );
    expect(counterText(), '1');
  });

  testWidgets('xsheet frame axis: scrolling stays CLAMPED to the built '
      'cells; the frame-rail edge-drag alone extends it (UI-R12 #16)', (
    WidgetTester tester,
  ) async {
    withTouchScroll();
    await tester.pumpWidget(const AnicelApp());
    await tapToolbarButton(
      tester,
      const ValueKey<String>('timeline-orientation-toggle-button'),
    );

    // Painterized rail (UI-R14 #1): rows past the base exist exactly
    // when the rail painter's window reaches past 48.
    bool beyondBaseRows() =>
        xsheetRailPainter(tester).frameEndIndexExclusive > 48;

    // Scroll gestures wall at the built extent (base 48 rows).
    for (var i = 0; i < 3; i += 1) {
      await tester.drag(
        find.byKey(const ValueKey<String>('xsheet-frame-vertical-viewport')),
        const Offset(0, -1200),
      );
      await tester.pumpAndSettle();
    }
    expect(beyondBaseRows(), isFalse);

    // The frame-rail edge-drag is THE way past the wall (UI-R12 #16).
    final railRect = tester.getRect(
      find.byKey(const ValueKey<String>('xsheet-frame-rail-scrub-area')),
    );
    final gesture = await tester.startGesture(
      Offset(railRect.center.dx, railRect.bottom - 30),
    );
    for (var i = 0; i < 12; i += 1) {
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(beyondBaseRows(), isTrue);
  });
}
