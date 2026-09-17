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
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/canvas/canvas_zoom_scale.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart';
import 'package:anicel/src/ui/effective_device_pixel_ratio.dart';

import '../../helpers/brush_canvas_fixture.dart';
import '../../helpers/canvas_pill.dart';

/// 🚨★★★ONE LAW FOR WHERE A ZOOM LANDS, AND THE PILL WRITES ALL OF IT.
///
/// 유저 2026-09-13 (F-122): 「알약에 있는 줌 텍스트도 터치로 조작하면 미세하게
/// 조작되서 **55%랑 56% 사이 숫자가 존재**하는데 … **변형가능한만큼
/// 텍스트로도 표시** … 10.85 까진 가능해도 10.858 이렇게 **세자리째는
/// 막는게**」 · 2026-09-17: 「캔버스 베이스 패널 많을테니 **다 법 통일해서**
/// 적용되면되. 지금 100%인게 **100.00%**가 될거같은데 문제없어」 ·
/// 「**근본/구조적으로** 해결해줘. 증상만 해결말고」.
///
/// The pill rounded to a whole percent while every verb moved the zoom
/// continuously, so `55%` stood for every zoom from 54.5 to 55.5. Writing
/// more digits alone only moves that gap to the third place — so the ZOOM
/// lands on the grid the pill writes, at every verb, and the pill writes
/// every digit it has.
///
/// I-27 (유저 2026-09-13: 「확대 축소 로직이 터치랑 … 여러곳에
/// 나뉘어져있을 가능성 높으니 **법 하나로 통일**」) is the same law's other
/// half: the panel's verbs stopped at 10%–1600% and the gesture layer's only
/// at the model's sanity rail.
void main() {
  setUp(CanvasTouchContacts.reset);
  tearDown(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  /// How far [percent] sits from the 0.01 grid, in hundredths.
  double offTheGrid(double percent) =>
      (percent * 100 - (percent * 100).roundToDouble()).abs();

  group('the gesture layer', () {
    Future<List<CanvasViewport>> pumpCanvas(
      WidgetTester tester, {
      double ratio = 1.0,
      CanvasViewport? initial,
    }) async {
      tester.view.devicePixelRatio = ratio;
      addTearDown(tester.view.resetDevicePixelRatio);
      AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
        // The engine drives touch only off a non-draw one-finger slot.
        touchDragOneFinger: CanvasTouchDragAction.flip,
      );
      final emitted = <CanvasViewport>[];
      var viewport = initial ?? CanvasViewport();
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            home: Scaffold(
              body: InputInspectorHost(
                child: CanvasViewportGestureLayer(
                  viewport: viewport,
                  onViewportChanged: (next) {
                    emitted.add(next);
                    setState(() => viewport = next);
                  },
                  onInvokeAction: (_) {},
                  onBrushSizeDragStart: () {},
                  onBrushSizeDragUpdate: (_, {required snap}) {},
                  onBrushSizeDragEnd: () {},
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return emitted;
    }

    Future<void> wheel(
      WidgetTester tester,
      Offset position, {
      required bool zoomIn,
    }) async {
      final mouse = TestPointer(77, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(position));
      await tester.sendEventToBinding(
        mouse.scroll(Offset(0, zoomIn ? -120 : 120)),
      );
      await tester.pump();
    }

    for (final ratio in <double>[1.0, 1.5]) {
      testWidgets('🚨a free pinch lands on a zoom the pill can write, and '
          'the artwork under the fingers stays under them (ratio $ratio)', (
        tester,
      ) async {
        final emitted = await pumpCanvas(tester, ratio: ratio);
        final first = await tester.startGesture(
          const Offset(300, 300),
          kind: PointerDeviceKind.touch,
          pointer: 41,
        );
        final second = await tester.startGesture(
          const Offset(397, 300),
          kind: PointerDeviceKind.touch,
          pointer: 42,
        );
        await first.moveBy(const Offset(-20, 0));
        await second.moveBy(const Offset(21, 0));
        await tester.pump();

        // 97px apart → 138px apart: 138/97 of the opening zoom, which no
        // two-digit percentage is.
        final asked = ratio * 100 * 138 / 97;
        final percent = emitted.last.zoom * ratio * 100;
        expect(offTheGrid(asked), greaterThan(0.1), reason: 'fixture');
        expect(
          offTheGrid(percent),
          lessThan(1e-6),
          reason: 'the pinch kept $percent% — a zoom the pill cannot write',
        );
        expect((percent - asked).abs(), lessThanOrEqualTo(0.005 + 1e-9));

        // The anchor is solved at the zoom that was KEPT. Rounding a view
        // that was already anchored leaves the point under the fingers
        // anchored for a zoom the view no longer has.
        const startFocal = Offset(348.5, 300);
        const focalNow = Offset(349, 300);
        final under = CanvasViewport().viewportToCanvas(
          ViewportPoint(x: startFocal.dx, y: startFocal.dy),
        );
        final now = emitted.last.canvasToViewport(under);
        expect(now.x, closeTo(focalNow.dx, 1e-9));
        expect(now.y, closeTo(focalNow.dy, 1e-9));

        await first.up();
        await second.up();
        await tester.pump();
      });
    }

    testWidgets('🚨the wheel lands every notch: five in reads 161.05, not '
        '161.051', (tester) async {
      final emitted = await pumpCanvas(tester);
      for (var notch = 0; notch < 5; notch += 1) {
        await wheel(tester, const Offset(350, 300), zoomIn: true);
      }
      expect(
        emitted.map((view) => view.zoom * 100).toList(),
        [
          closeTo(110, 1e-9),
          closeTo(121, 1e-9),
          closeTo(133.1, 1e-9),
          closeTo(146.41, 1e-9),
          closeTo(161.05, 1e-9),
        ],
      );
    });

    testWidgets('the trackpad pinch lands too', (tester) async {
      final emitted = await pumpCanvas(tester);
      final trackpad = TestPointer(5, PointerDeviceKind.trackpad);
      const at = Offset(350, 300);
      await tester.sendEventToBinding(trackpad.panZoomStart(at));
      await tester.sendEventToBinding(
        trackpad.panZoomUpdate(at, scale: 1.23456),
      );
      await tester.pump();
      expect(emitted.last.zoom * 100, closeTo(123.46, 1e-9));
      await tester.sendEventToBinding(trackpad.panZoomEnd());
    });

    // 🚨THE RANGE IS ONE LAW: the wheel and the pinch stop at 1600% and at
    // 10%, where the pill and its buttons always stopped. They went on to
    // the model's sanity rail (2200% here), past what the readout accepts —
    // so the readout's next one-percent nudge threw the view back to 1600%.
    testWidgets('🚨a wheel stops at 1600%, where the pill stops', (
      tester,
    ) async {
      final emitted = await pumpCanvas(
        tester,
        initial: CanvasViewport(zoom: 16),
      );
      await wheel(tester, const Offset(350, 300), zoomIn: true);
      expect(
        emitted.map((view) => view.zoom),
        everyElement(closeTo(16, 1e-12)),
      );
    });

    testWidgets('🚨a wheel stops at 10%, where the pill stops', (tester) async {
      final emitted = await pumpCanvas(
        tester,
        initial: CanvasViewport(zoom: 0.1),
      );
      await wheel(tester, const Offset(350, 300), zoomIn: false);
      expect(
        emitted.map((view) => view.zoom),
        everyElement(closeTo(0.1, 1e-12)),
      );
    });

    testWidgets('🚨a pinch through the top stops at 1600% too', (tester) async {
      final emitted = await pumpCanvas(
        tester,
        initial: CanvasViewport(zoom: 12),
      );
      final first = await tester.startGesture(
        const Offset(300, 300),
        kind: PointerDeviceKind.touch,
        pointer: 41,
      );
      final second = await tester.startGesture(
        const Offset(400, 300),
        kind: PointerDeviceKind.touch,
        pointer: 42,
      );
      await first.moveBy(const Offset(-25, 0));
      await second.moveBy(const Offset(25, 0));
      await tester.pump();
      expect(emitted.last.zoom, closeTo(16, 1e-12), reason: '12 × 1.5 = 18');
      await first.up();
      await second.up();
      await tester.pump();
    });

    testWidgets('a twist lands on an angle the pill can write', (tester) async {
      final emitted = await pumpCanvas(tester);
      final first = await tester.startGesture(
        const Offset(300, 300),
        kind: PointerDeviceKind.touch,
        pointer: 41,
      );
      final second = await tester.startGesture(
        const Offset(400, 300),
        kind: PointerDeviceKind.touch,
        pointer: 42,
      );
      // The second finger swings down around the first: atan2(37, 100) is
      // 20.30…°, and the deadzone takes its own bite out of it.
      await second.moveBy(const Offset(0, 37));
      await tester.pump();
      final degrees = emitted.last.rotationDegrees;
      expect(degrees, isNot(0), reason: 'fixture: past the deadzone');
      expect(
        offTheGrid(degrees),
        lessThan(1e-6),
        reason: 'the twist kept $degrees° — an angle the pill cannot write',
      );
      await first.up();
      await second.up();
      await tester.pump();
    });
  });

  group('the pill', () {
    Widget harness({
      required double uiScale,
      CanvasSize canvasSize = const CanvasSize(width: 300, height: 300),
      CanvasViewport? viewport,
      ValueNotifier<CanvasViewport?>? controller,
      CanvasViewCommands? commands,
    }) {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      return MediaQuery(
        data: MediaQueryData.fromView(
          WidgetsBinding.instance.platformDispatcher.views.first,
        ),
        child: EffectiveDevicePixelRatioScope(
          uiScale: uiScale,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 1000,
                height: 420,
                child: BrushCanvasPanel(
                  coordinator: BrushCanvasFixture.createCoordinator(
                    frameKeys: frameKeys,
                    canvasSize: canvasSize,
                  ),
                  availableFrameKeys: frameKeys,
                  cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                  floorCover: EdgeInsets.zero,
                  canvasSize: canvasSize,
                  viewport: viewport,
                  viewportController: controller,
                  viewCommands: commands,
                ),
              ),
            ),
          ),
        ),
      );
    }

    String textOf(WidgetTester tester, String key) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(ValueKey<String>(key)),
            matching: find.byType(Text),
          ),
        )
        .data!;

    String zoomReadout(WidgetTester tester) =>
        textOf(tester, 'canvas-viewport-zoom-label');

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

    testWidgets('🚨writes every digit the zoom has: 100% reads 100.00%', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.5;
      tester.view.physicalSize = const Size(2400, 1800);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(uiScale: 1.0));
      await tester.pump();
      expect(zoomReadout(tester), '100.00%');

      // ⚠️`viewport:` is in DEVICE units, so it IS the percentage.
      await tester.pumpWidget(
        harness(uiScale: 1.0, viewport: CanvasViewport(zoom: 0.5537)),
      );
      await tester.pump();
      expect(zoomReadout(tester), '55.37%');
    });

    testWidgets('🚨a typed third digit does not exist: 55.555 is 55.56, in '
        'the view as on the pill', (tester) async {
      tester.view.devicePixelRatio = 1.5;
      tester.view.physicalSize = const Size(2400, 1800);
      addTearDown(tester.view.reset);
      final owner = ValueNotifier<CanvasViewport?>(null);
      addTearDown(owner.dispose);
      await tester.pumpWidget(harness(uiScale: 1.25, controller: owner));
      await tester.pump();

      await typeZoom(tester, '55.555');
      expect(zoomReadout(tester), '55.56%');
      // The owner's value is in DEVICE units — the percentage itself.
      expect(owner.value!.zoom, closeTo(0.5556, 1e-12));

      await typeZoom(tester, '55.5');
      expect(zoomReadout(tester), '55.50%');
      expect(owner.value!.zoom, closeTo(0.555, 1e-12));
    });

    testWidgets('🚨what the pill says IS the view, after a wheel over the '
        'canvas', (tester) async {
      tester.view.devicePixelRatio = 1.25;
      tester.view.physicalSize = const Size(2000, 1250);
      addTearDown(tester.view.reset);
      final owner = ValueNotifier<CanvasViewport?>(null);
      addTearDown(owner.dispose);
      await tester.pumpWidget(harness(uiScale: 1.0, controller: owner));
      await tester.pump();

      final canvas = tester.getCenter(
        find.byKey(const ValueKey<String>('brush-canvas-editor-viewport')),
      );
      final mouse = TestPointer(77, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(canvas));
      for (var notch = 0; notch < 7; notch += 1) {
        await tester.sendEventToBinding(mouse.scroll(const Offset(0, -120)));
        await tester.pump();
      }

      final percent = owner.value!.zoom * 100;
      expect(percent, greaterThan(190), reason: 'fixture: seven notches in');
      expect(offTheGrid(percent), lessThan(1e-6));
      expect(zoomReadout(tester), '${percent.toStringAsFixed(2)}%');
    });

    testWidgets('🚨Fit lands DOWN, and centres at the zoom it kept', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 1200);
      addTearDown(tester.view.reset);
      const canvasSize = CanvasSize(width: 317, height: 171);
      await tester.pumpWidget(harness(uiScale: 1.0, canvasSize: canvasSize));
      await tester.pump();

      final window = tester.getSize(
        find.byKey(const ValueKey<String>('brush-canvas-editor-viewport')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('canvas-viewport-fit')),
      );
      await tester.pump();

      final loose = CanvasViewport.fitToView(
        canvasWidth: 317,
        canvasHeight: 171,
        viewportWidth: window.width,
        viewportHeight: window.height,
      );
      final fitted = tester
          .widget<InteractiveBrushEditCanvasView>(
            find.byType(InteractiveBrushEditCanvasView),
          )
          .viewport;
      expect(offTheGrid(loose.zoom * 100), greaterThan(0.01), reason: 'fixture');
      expect(offTheGrid(fitted.zoom * 100), lessThan(1e-6));
      expect(
        fitted.zoom,
        lessThanOrEqualTo(loose.zoom),
        reason: 'the next digit UP puts the edge of what was asked to fit '
            'outside the window it was fitted into',
      );
      expect(loose.zoom - fitted.zoom, lessThan(0.0001 + 1e-12));

      // Centred for the zoom the view HAS.
      final centre = fitted.canvasToViewport(
        CanvasPoint(x: 317 / 2, y: 171 / 2),
      );
      expect(centre.x, closeTo(window.width / 2, 1e-9));
      expect(centre.y, closeTo(window.height / 2, 1e-9));
    });

    testWidgets('the angle reads 0.00° and writes what a rotation kept', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 1200);
      addTearDown(tester.view.reset);

      // The angle sits on a wide floor pill and in its settings list on a
      // narrower one — wherever this width put it.
      Future<String> angleReadout() async {
        const key = ValueKey<String>('canvas-viewport-rotation-label');
        if (!tester.any(find.byKey(key))) {
          await openViewSettings(tester);
        }
        return textOf(tester, 'canvas-viewport-rotation-label');
      }

      await tester.pumpWidget(harness(uiScale: 1.0));
      await tester.pump();
      expect(await angleReadout(), '0.00°');

      // ⚠️`viewport:` is a SEED, taken once — a fresh panel, not a new prop.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        harness(
          uiScale: 1.0,
          viewport: CanvasViewport(rotationDegrees: -15.37),
        ),
      );
      await tester.pump();
      expect(await angleReadout(), '-15.37°');
    });

    testWidgets('🚨a stop the view cannot land on is not a rung a step '
        'dies on', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 1200);
      addTearDown(tester.view.reset);
      // The stop list is the user's own text and takes any digits — the
      // settings field parses `33.333` and shows it as `33`.
      AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
        zoomSnapPercents: const [25, 33.333, 50],
      );
      // The command channel is the road Shift+. and Shift+, take, and the
      // pill's ± press the same step (I-19) — a panel off the floor has no
      // ± of its own to press.
      final commands = CanvasViewCommands();
      await tester.pumpWidget(
        harness(
          uiScale: 1.0,
          viewport: CanvasViewport(zoom: 0.25),
          commands: commands,
        ),
      );
      await tester.pump();
      expect(zoomReadout(tester), '25.00%');

      Future<void> step({required bool zoomIn}) async {
        commands.zoomStep(zoomIn: zoomIn);
        await tester.pump();
      }

      await step(zoomIn: true);
      expect(zoomReadout(tester), '33.33%');
      await step(zoomIn: true);
      expect(
        zoomReadout(tester),
        '50.00%',
        reason: 'from 33.33 the next stop "up" was 33.333 — which lands on '
            '33.33 again, so the step did nothing at that rung for ever',
      );
      await step(zoomIn: false);
      expect(zoomReadout(tester), '33.33%');
      await step(zoomIn: false);
      expect(zoomReadout(tester), '25.00%');
    });
  });

  group('the user\'s stops', () {
    // The list is written in DISPLAY percent. These two are the only
    // readers it has, so the unit is converted in one place.
    test('are stepped through on the grid the view lands on', () {
      const scale = CanvasZoomScale(1.5);
      const stops = <double>[25, 33.333, 50];
      double percentOf(double? renderZoom) =>
          scale.display(renderZoom!) * 100;

      final first = scale.steppedThroughStops(
        scale.render(0.25),
        stops,
        up: true,
      );
      expect(percentOf(first), closeTo(33.33, 1e-9));
      final second = scale.steppedThroughStops(first!, stops, up: true);
      expect(percentOf(second), closeTo(50, 1e-9));
      expect(scale.steppedThroughStops(second!, stops, up: true), isNull);
      expect(
        percentOf(scale.steppedThroughStops(second, stops, up: false)),
        closeTo(33.33, 1e-9),
      );
    });

    test('are snapped to in DISPLAY percent, and the snap lands', () {
      // 🚩The audit of 2026-09-15: snapped as a RENDER zoom, a 150% stop
      // read 225% on a 150% monitor.
      const scale = CanvasZoomScale(1.5);
      final snapped = scale.snappedToStops(
        scale.render(1.43),
        const [100, 150, 200],
      );
      expect(scale.display(snapped) * 100, closeTo(150, 1e-9));
      expect(
        scale.display(scale.snappedToStops(scale.render(0.334), const [33.333])) *
            100,
        closeTo(33.33, 1e-9),
      );
    });
  });

  group('the view', () {
    test('a rotation lands on the grid its readout writes', () {
      final anchor = ViewportPoint(x: 120, y: 80);
      final turned = CanvasViewport(zoom: 1.5, panX: 10, panY: 20)
          .rotatedAround(nextRotationDegrees: 15.3719, anchor: anchor);
      expect(turned.rotationDegrees, closeTo(15.37, 1e-12));

      // Dust is not an angle: nothing under half a hundredth survives, so
      // the rotated slow path is never left armed by a float.
      final dust = CanvasViewport().rotatedAround(
        nextRotationDegrees: 0.0049,
        anchor: anchor,
      );
      expect(dust.rotationDegrees, 0);
      expect(dust.hasRotationOrFlip, isFalse);
    });
  });
}
