import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/viewport_point.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/canvas_view_commands.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/canvas_zoom_scale.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/widgets/app_scrollbar_lane.dart';

import '../../helpers/brush_canvas_fixture.dart';
import '../../helpers/canvas_pill.dart';
import '../../helpers/dart_sources.dart';

/// 🗣️I-27 (유저 2026-09-13): 「설정 줌 스냅 근처에 최대 줌 제한기능. 100%이면
/// 100% 넘어서 확대하지 못하게 락 거는용도. 축소는 이전처럼 자유. 동시에
/// 확대 축소 로직이 … 여러곳에 나뉘어져있을 가능성 높으니 법 하나로
/// 통일하면서」.
///
/// The one law came first (F-122, `a_zoom_lands_where_the_pill_can_say_it_
/// test`); this is the lock it was unified for. Asked where it holds and how
/// (I-27-Q1 · Q2): one line under the zoom snaps, 「그리기 캔버스만」, and
/// 「화면에 맞추기도 최대 줌에서 멈춘다」 — a lock without an exception.
void main() {
  setUp(CanvasTouchContacts.reset);
  tearDown(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  group('the law, under a lock', () {
    const locked = CanvasZoomScale(1, ceilingPercent: 100);

    test('🚨a zoom lands at the lock and no further — zooming out is as '
        'free as it was', () {
      expect(locked.landed(2.5), 1.0);
      expect(locked.landed(16), 1.0);
      expect(locked.landed(0.3), closeTo(0.3, 1e-12));
      expect(locked.landed(0.01), closeTo(0.1, 1e-12), reason: 'the 10% end');
    });

    test('the lock is a DISPLAY percent: on a 1.5 monitor 100% is one '
        'artwork pixel per device pixel', () {
      const onHiDpi = CanvasZoomScale(1.5, ceilingPercent: 100);
      expect(onHiDpi.display(onHiDpi.landed(3)), closeTo(1.0, 1e-12));
    });

    test('🚨a Fit stops at the lock — upward only', () {
      expect(locked.landedToFit(2.5), 1.0);
      expect(locked.landedToFit(0.6), closeTo(0.6, 1e-12));
      // Below the advertised range a Fit is still a Fit.
      expect(locked.landedToFit(0.04), closeTo(0.04, 1e-12));
    });

    test('with NO lock nothing changed: 1600% is the top, and a Fit goes '
        'past it', () {
      const free = CanvasZoomScale(1);
      expect(free.ceilingPercent, isNull);
      expect(free.landed(40), 16.0);
      expect(free.landedToFit(40), 40.0);
    });

    test('a lock typed outside the range a view can stand in is the nearest '
        'stop inside it', () {
      expect(const CanvasZoomScale(1, ceilingPercent: 5).ceilingPercent, 10);
      expect(
        const CanvasZoomScale(1, ceilingPercent: 5000).ceilingPercent,
        1600,
      );
    });

    test('🚨a view that stands past the lock is brought back to it around '
        'the anchor — and one at or under it is handed back ITSELF', () {
      final anchor = ViewportPoint(x: 320, y: 200);
      final past = CanvasViewport(zoom: 3, panX: -40, panY: 25);
      final under = past.viewportToCanvas(anchor);

      final held = locked.heldUnderCeiling(past, anchor: anchor);

      expect(held.zoom, 1.0);
      final after = held.viewportToCanvas(anchor);
      expect(after.x, closeTo(under.x, 1e-9));
      expect(after.y, closeTo(under.y, 1e-9));

      expect(
        identical(locked.heldUnderCeiling(held, anchor: anchor), held),
        isTrue,
        reason: 'a view AT the lock is not held again',
      );
      final below = CanvasViewport(zoom: 0.5);
      expect(
        identical(locked.heldUnderCeiling(below, anchor: anchor), below),
        isTrue,
      );
      expect(
        identical(
          const CanvasZoomScale(1).heldUnderCeiling(past, anchor: anchor),
          past,
        ),
        isTrue,
        reason: 'no lock, nothing to hold',
      );
    });

    test('a view that LANDED on the lock on a fractional monitor is not '
        'past it by a rounding error', () {
      // 🧪Measured 2026-10-08: on a 1.5 monitor a view landed on 110% reads
      // 110.00000000000001 after the trip through render units — and about
      // one lock in ten does, over the ratios monitors have.
      const onHiDpi = CanvasZoomScale(1.5, ceilingPercent: 110);
      final landed = CanvasViewport(zoom: onHiDpi.landed(4));
      expect(
        onHiDpi.display(landed.zoom) * 100,
        greaterThan(110),
        reason: '⛔premise: it reads past its lock',
      );
      expect(
        identical(
          onHiDpi.heldUnderCeiling(landed, anchor: ViewportPoint(x: 0, y: 0)),
          landed,
        ),
        isTrue,
      );
    });

    test('🚨a stop past the lock is no step up — and the steps down are '
        'untouched', () {
      const stops = <double>[50, 100, 125, 200];
      expect(locked.steppedThroughStops(1.0, stops, up: true), isNull);
      expect(locked.steppedThroughStops(0.5, stops, up: true), 1.0);
      expect(locked.steppedThroughStops(1.0, stops, up: false), 0.5);
      expect(
        const CanvasZoomScale(
          1,
          ceilingPercent: 125,
        ).steppedThroughStops(1.0, stops, up: true),
        1.25,
        reason: 'a stop AT the lock is a stop',
      );
    });

    test('two scales that differ only in the lock are different scales', () {
      expect(locked == const CanvasZoomScale(1), isFalse);
      expect(locked == const CanvasZoomScale(1, ceilingPercent: 100), isTrue);
      expect(
        locked.hashCode,
        const CanvasZoomScale(1, ceilingPercent: 100).hashCode,
      );
    });
  });

  group('a locked panel', () {
    Widget harness({
      required double? lock,
      CanvasSize canvasSize = const CanvasSize(width: 300, height: 300),
      ValueNotifier<CanvasViewport?>? controller,
      CanvasViewCommands? commands,
    }) {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 420,
            // What the drawing canvas's host does for the view under it.
            child: CanvasZoomCeiling(
              percent: lock,
              child: BrushCanvasPanel(
                // ⚠️One State across the pumps of a test: the lock changes
                // above a panel that stays.
                key: const ValueKey<String>('panel'),
                coordinator: BrushCanvasFixture.createCoordinator(
                  frameKeys: frameKeys,
                  canvasSize: canvasSize,
                ),
                availableFrameKeys: frameKeys,
                cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                floorCover: EdgeInsets.zero,
                canvasSize: canvasSize,
                viewportController: controller,
                viewCommands: commands,
              ),
            ),
          ),
        ),
      );
    }

    String zoomReadout(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('canvas-viewport-zoom-label'),
            ),
            matching: find.byType(Text),
          ),
        )
        .data!;

    Future<void> typeZoom(WidgetTester tester, String text) async {
      await tester.tap(
        find.byKey(const ValueKey<String>('canvas-viewport-zoom-label')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('canvas-viewport-zoom-input')),
        text,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    void onADesk(WidgetTester tester) {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 1200);
      addTearDown(tester.view.reset);
    }

    testWidgets('🚨a typed 250% reads the lock; a typed 40% is 40%', (
      tester,
    ) async {
      onADesk(tester);
      final controller = ValueNotifier<CanvasViewport?>(CanvasViewport());
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(lock: 100, controller: controller));
      await tester.pump();

      await typeZoom(tester, '250');
      expect(zoomReadout(tester), '100.00%');
      await typeZoom(tester, '40');
      expect(zoomReadout(tester), '40.00%');
    });

    testWidgets('🚨the step up has no stop past the lock; the step down is '
        'free', (tester) async {
      onADesk(tester);
      AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
        zoomSnapPercents: const [50, 100, 125, 200],
      );
      final controller = ValueNotifier<CanvasViewport?>(CanvasViewport());
      addTearDown(controller.dispose);
      final commands = CanvasViewCommands();
      await tester.pumpWidget(
        harness(lock: 100, controller: controller, commands: commands),
      );
      await tester.pump();
      expect(zoomReadout(tester), '100.00%', reason: '⛔premise');

      commands.zoomStep(zoomIn: true);
      await tester.pump();
      expect(zoomReadout(tester), '100.00%');

      commands.zoomStep(zoomIn: false);
      await tester.pump();
      expect(zoomReadout(tester), '50.00%');
    });

    testWidgets('🚨the wheel stops at the lock', (tester) async {
      onADesk(tester);
      final controller = ValueNotifier<CanvasViewport?>(CanvasViewport());
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(lock: 100, controller: controller));
      await tester.pump();
      final over = tester.getCenter(
        find.byKey(const ValueKey<String>('brush-canvas-editor-viewport')),
      );
      final mouse = TestPointer(77, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(over));

      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -120)));
      await tester.pump();
      expect(zoomReadout(tester), '100.00%');

      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
      await tester.pump();
      expect(
        controller.value!.zoom,
        lessThan(1),
        reason: 'out is as free as it was',
      );
    });

    // I-27-Q2: 「화면에 맞추기도 최대 줌에서 멈춘다」 — and the option's own
    // words for what that looks like: a small canvas stands smaller than its
    // window.
    testWidgets('🚨Fit stops at the lock too, and centres the canvas at the '
        'zoom it kept', (tester) async {
      onADesk(tester);
      const canvasSize = CanvasSize(width: 317, height: 171);
      await tester.pumpWidget(harness(lock: 100, canvasSize: canvasSize));
      await tester.pump();
      final box = tester.getSize(
        find.byKey(const ValueKey<String>('brush-canvas-editor-viewport')),
      );
      final band = pillBandOf(tester);
      final window = Size(
        box.width - AppScrollbarLane.wide,
        box.height - AppScrollbarLane.wide - band,
      );
      expect(
        CanvasViewport.fitToView(
          canvasWidth: 317,
          canvasHeight: 171,
          viewportWidth: window.width,
          viewportHeight: window.height,
        ).zoom,
        greaterThan(1.5),
        reason: '⛔premise: unlocked, this canvas fits well past 100%',
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('canvas-viewport-fit')),
      );
      await tester.pump();

      final fitted = tester
          .widget<InteractiveBrushEditCanvasView>(
            find.byType(InteractiveBrushEditCanvasView),
          )
          .viewport;
      expect(fitted.zoom, 1.0);
      final centre = fitted.canvasToViewport(
        CanvasPoint(x: 317 / 2, y: 171 / 2),
      );
      expect(centre.x, closeTo(window.width / 2, 1e-9));
      expect(centre.y, closeTo(band + window.height / 2, 1e-9));
    });

    testWidgets('🚨a view stored past the lock is SHOWN at the lock — and '
        'the store is brought to say so', (tester) async {
      onADesk(tester);
      final controller = ValueNotifier<CanvasViewport?>(
        CanvasViewport(zoom: 3),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(lock: 100, controller: controller));
      expect(zoomReadout(tester), '100.00%', reason: 'at the first build');

      await tester.pump();
      await tester.pump();
      expect(controller.value!.zoom, closeTo(1, 1e-9));
    });

    testWidgets('a lock SET under a view that stands past it brings the view '
        'down; lifted, the view goes past it again', (tester) async {
      onADesk(tester);
      final controller = ValueNotifier<CanvasViewport?>(
        CanvasViewport(zoom: 3),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(harness(lock: null, controller: controller));
      await tester.pump();
      expect(zoomReadout(tester), '300.00%', reason: '⛔premise');

      await tester.pumpWidget(harness(lock: 100, controller: controller));
      await tester.pump();
      await tester.pump();
      expect(zoomReadout(tester), '100.00%');
      expect(controller.value!.zoom, closeTo(1, 1e-9));

      await tester.pumpWidget(harness(lock: null, controller: controller));
      await tester.pump();
      await typeZoom(tester, '250');
      expect(zoomReadout(tester), '250.00%');
    });
  });

  group('where it holds', () {
    // I-27-Q1's note: 「그리기 캔버스만」. The law is every document view's
    // (`CanvasZoomScale`), so WHO says the lock is the whole of the scope.
    test('⛔ONE place says the lock to a view: the drawing canvas\'s host', () {
      final speakers = [
        for (final file in dartFilesUnder('lib'))
          if (file.readAsStringSync().contains('CanvasZoomCeiling(') &&
              !file.path.endsWith('canvas_zoom_scale.dart'))
            libPath(file),
      ];
      expect(speakers, ['lib/src/ui/brush/main_canvas_brush_host.dart']);
    });

    testWidgets('the drawing canvas says the settings\' lock to the view '
        'under it — while the switch is on, and at the number it holds', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
      double? said() => tester
          .widget<CanvasZoomCeiling>(find.byType(CanvasZoomCeiling))
          .percent;
      expect(said(), isNull, reason: 'off until the user locks one');

      AppInput.settings.value = AppInput.settings.value.copyWith(
        zoomCeilingOn: true,
        zoomCeilingPercent: 150,
      );
      await tester.pumpAndSettle();
      expect(said(), 150);

      AppInput.settings.value = AppInput.settings.value.copyWith(
        zoomCeilingOn: false,
      );
      await tester.pumpAndSettle();
      expect(said(), isNull);
      expect(
        AppInput.settings.value.zoomCeilingPercent,
        150,
        reason: 'switched off, the number is kept',
      );
    });
  });
}
