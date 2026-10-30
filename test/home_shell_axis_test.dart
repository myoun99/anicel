// HomePage widget tests — the shell, the frame axis and its zoom.
// Split from widget_test.dart (2026-09-04) so the suite runs across
// isolates; the shared probes live in helpers/home_page_probes.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/layout/device_grid_safe_area.dart';
import 'package:anicel/src/ui/timeline/frame_ruler_view.dart';

import 'ui/timeline/timeline_ruler_probe.dart';

import 'helpers/app_icon_button_probe.dart';
import 'helpers/home_page_probes.dart';
import 'helpers/the_classic_rail.dart';
import 'helpers/timeline_zoom.dart';

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
    // An install opens on Clip Studio's layout, where Add Frame has no key:
    // TVPaint's I is the eyedropper's there (F-417-Q2). ↩️It showed
    // anicel's Shift+I until then (I-63-Q4).
    expect(find.tooltipSaying('New Frame'), findsOneWidget);
    await expectCutName(tester, 'default-cut-1', '1');
    await expectActiveCutName(tester, '1');
    expect(find.text('New Drawing'), findsNothing);

    // Cut management rides the toolbar's cut group (R-toolbar round): a
    // new-cut button plus the Cut ▾ flyout with the command set.
    expect(find.tooltipSaying('New cut'), findsOneWidget);
    final cutMenu = find.byKey(const ValueKey<String>('cut-menu-button'));
    await tester.ensureVisible(cutMenu);
    await tester.pumpAndSettle();
    await tester.tap(cutMenu);
    await tester.pumpAndSettle();
    for (final item in [
      'edit-cut-note-button',
      'resize-cut-canvas-button',
      'add-cut-create-linked',
      'convert-cut-to-linked-button',
    ]) {
      expect(find.byKey(ValueKey<String>(item)), findsOneWidget);
    }
    // 🗣️F-455 (유저 2026-10-23): 「컷 버튼의 컷 왼쪽/오른쪽으로 삭제 …
    // 카메라AE키프레임 복사도 삭제 … 컷 이름 변경도 … 삭제 … 레이어랑
    // 컷버튼의 레이어복제/컷복제 삭제」.
    for (final gone in [
      'rename-cut-button',
      'duplicate-cut-button',
      'move-cut-left-button',
      'move-cut-right-button',
      'copy-cut-ae-camera-button',
    ]) {
      expect(find.byKey(ValueKey<String>(gone)), findsNothing, reason: gone);
    }
    await tester.tapAt(const Offset(5, 400));
    await tester.pumpAndSettle();
  });

  testWidgets('default sample cut duration is 24 frames', (
    WidgetTester tester,
  ) async {
    withTouchScroll();
    await tester.pumpWidget(const AnicelApp());
    await standTheClassicRail(tester);

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
        timelineRulerPainter(tester).scale.frameEndIndexExclusive > 48;

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

    // 19.2, where a cut opens (F-403: 「80%를 100%로」) — 200% on the bar
    // since F-491 — laid on whole pixels; the painterized ruler (UI-R13 #1)
    // reports geometry/labels through its painter. ↩️24 (R-toolbar round).
    double headerWidth() => timelineHeaderGlobalRect(tester, 0).width;
    expect(headerWidth(), 19);
    // Wide cells label every frame in-cell.
    expect(timelineHeaderModel(tester, 0).label, '1');

    Future<void> zoomTo(double pixelsPerFrame) =>
        zoomTimelineTo(tester, pixelsPerFrame);

    // Under the bar's ceiling, 38.4 (F-403-Q1; 400% since F-491). ↩️40,
    // under 250%.
    await zoomTo(36);
    expect(headerWidth(), 36);

    // A drag along the zoom readout, a percent a pixel (F-463): 250% to
    // 281% (F-491: 100% is 9.6). ↩️125% to 156% of 19.2; before that the
    // −/+ step buttons flanking the slider stood here (UI-R11 #11), ×1.25 a
    // press.
    await zoomTo(24);
    await dragTimelineZoom(tester, 31);
    expect(headerWidth(), 27, reason: '281% of 9.6 = 26.976');

    await zoomTo(12);
    expect(headerWidth(), 12);
    // Two digits narrow into a 12px cell as far as half-width
    // (ruler-digits-in-the-app-face-Q1): every frame keeps its number.
    expect(timelineHeaderModel(tester, 1).label, '2');

    await zoomTo(8);
    expect(headerWidth(), 8);
    // Where not even half-width fits, the labels move to the every-Nth
    // ladder: unlabeled headers read '' off the painter model (frame 1
    // stays the anchor).
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
    // 19.2 at 100%, laid on whole pixels, as the timeline's header (F-403).
    expect(xsheetFrameRowGlobalRect(tester, 0).height, 19);

    await zoomTimelineTo(tester, 36);
    // 36 is a step of the bar (187.5%), under its 200% (F-403-Q1).
    // ↩️40: the bar's tenth nearest it, 39.9936, laid on the pixel 40.
    expect(xsheetFrameRowGlobalRect(tester, 0).height, moreOrLessEquals(36));
  });

  // ↩️The bar's frame counter read seconds too, until F-463 took it off.
  testWidgets('the time display toggle switches the frame places to '
      'seconds', (WidgetTester tester) async {
    await tester.pumpWidget(const AnicelApp());

    // F-284 (유저 2026-10-04: 「이런 표기는 초+코마 표기로 바꾼거에
    // 대응하도록 법 통일」): the lists that name a frame are written by the
    // session, and this button is what they follow — one toggle, the
    // project's (F-354).
    String placeInALine() => tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session
        .framePlaceLabel(14);
    expect(placeInALine(), '15');

    // I-81-Q2: the corner lists the counts, and a pick turns the rulers.
    Future<void> pick(FrameRulerView view) async {
      await tapToolbarButton(
        tester,
        const ValueKey<String>('timeline-time-display-toggle-button'),
      );
      await tester.tap(
        find.byKey(ValueKey<String>('frame-ruler-view-${view.name}')),
      );
      await tester.pumpAndSettle();
    }

    await pick(FrameRulerView.secondsPlusFrames);
    // Frame 15 at 24fps in conte notation — bare digits, the sheet's own
    // (feedback #12).
    expect(placeInALine(), '0+15');

    // I-81-Q4 「그 외는 프레임뷰랑 똑같음」: the page view names a place as
    // the frames view does.
    await pick(FrameRulerView.pages);
    expect(placeInALine(), '15');

    await pick(FrameRulerView.frames);
    expect(placeInALine(), '15');
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
        xsheetRailPainter(tester).scale.frameEndIndexExclusive > 48;

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
