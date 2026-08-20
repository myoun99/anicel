import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/canvas/canvas_zoom_scale.dart';
import 'package:anicel/src/ui/effective_device_pixel_ratio.dart';

import '../../helpers/brush_canvas_fixture.dart';
import '../../helpers/canvas_pill.dart';

/// 100% means one artwork pixel per DEVICE pixel (유저 확정 2026-08-21), and
/// the same division keeps the UI scale off the document views.
void main() {
  group('CanvasZoomScale', () {
    test('display and render are inverses', () {
      for (final ratio in <double>[1, 1.125, 1.25, 1.5, 1.75, 2, 3]) {
        final scale = CanvasZoomScale(ratio);
        for (final zoom in <double>[0.1, 0.37, 1, 2.5, 16]) {
          expect(scale.render(scale.display(zoom)), closeTo(zoom, 1e-12));
          expect(scale.display(scale.render(zoom)), closeTo(zoom, 1e-12));
        }
      }
    });

    test('100% is one artwork pixel per DEVICE pixel', () {
      for (final ratio in <double>[1, 1.25, 1.5, 2]) {
        final scale = CanvasZoomScale(ratio);
        // The render zoom that shows "100%" puts `ratio` logical pixels of
        // artwork into `ratio` device pixels — one each.
        expect(scale.render(1.0), closeTo(1 / ratio, 1e-12));
        expect(scale.identityViewport.zoom, closeTo(1 / ratio, 1e-12));
        expect(scale.display(scale.identityViewport.zoom), closeTo(1, 1e-12));
      }
    });

    test('⛔the identity view is NOT a bare CanvasViewport()', () {
      // The regression this exists for: `CanvasViewport()` is one artwork
      // pixel per LOGICAL pixel, which on a 1.5 display drew at 150% while
      // the readout said 100%.
      expect(
        const CanvasZoomScale(1.5).identityViewport.zoom,
        isNot(CanvasViewport().zoom),
      );
      expect(const CanvasZoomScale(1.0).identityViewport.zoom, 1.0);
    });

    test('a hostile ratio degrades to 1 rather than to infinity', () {
      for (final bad in <double>[0, -1, double.nan, double.infinity]) {
        expect(CanvasZoomScale(bad).ratio, 1.0);
      }
      // `==` stays reflexive — a NaN kept raw would break it.
      expect(CanvasZoomScale(double.nan), CanvasZoomScale(double.nan));
    });

    test('device units round-trip, and the device identity is a bare one', () {
      for (final ratio in <double>[1, 1.25, 1.5, 1.875, 3]) {
        final scale = CanvasZoomScale(ratio);
        final view = CanvasViewport(
          zoom: 0.8,
          panX: 31,
          panY: -12,
          rotationDegrees: 15,
          flipHorizontal: true,
        );
        final back = scale.fromDevice(scale.toDevice(view));
        expect(back.zoom, closeTo(view.zoom, 1e-12));
        expect(back.panX, closeTo(view.panX, 1e-12));
        expect(back.panY, closeTo(view.panY, 1e-12));
        // Angles and signs carry no factor — that is the half of the claim
        // a zoom-only conversion would get wrong.
        expect(back.rotationDegrees, view.rotationDegrees);
        expect(back.flipHorizontal, view.flipHorizontal);

        // ⭐The identity in DEVICE units is `CanvasViewport()` — the exact
        // value that was WRONG in render units. Storing the view in these
        // units is what makes "nothing has framed this yet" and "one
        // artwork pixel per device pixel" the same object.
        expect(scale.toDevice(scale.identityViewport).zoom, closeTo(1, 1e-12));
        // And the device zoom IS the percentage, with no conversion left.
        expect(
          scale.toDevice(view).zoom,
          closeTo(scale.display(view.zoom), 1e-12),
        );
      }
    });

    test('a ratio change moves NOTHING when the view is kept in device '
        'units — no re-zoom, no anchor', () {
      // 🎯The property layer 3 rests on, and the reason the hold can go: a
      // stored device view converted out at a DIFFERENT ratio puts every
      // artwork point back on the device pixel it was already on. The old
      // `rescaledFrom` could only promise this for ONE point (the anchor)
      // and only while a panel was mounted to run it.
      const before = CanvasZoomScale(1.5);
      const after = CanvasZoomScale(1.875); // the same monitor at 125% UI
      final stored = before.toDevice(
        CanvasViewport(zoom: 0.8, panX: 31, panY: -12, rotationDegrees: 15),
      );

      final was = before.fromDevice(stored);
      final now = after.fromDevice(stored);
      for (final point in <CanvasPoint>[
        CanvasPoint(x: 0, y: 0),
        CanvasPoint(x: 300, y: 200),
        CanvasPoint(x: -140, y: 990),
      ]) {
        // Logical positions differ — the root matrix grew by the factor.
        // DEVICE positions are identical, which is what the eye reads.
        final wasDevice = was.canvasToViewport(point);
        final nowDevice = now.canvasToViewport(point);
        expect(wasDevice.x * 1.5, closeTo(nowDevice.x * 1.875, 1e-9));
        expect(wasDevice.y * 1.5, closeTo(nowDevice.y * 1.875, 1e-9));
      }
    });

    test('the DISPLAY zoom is the invariant across a ratio change', () {
      // What `rescaledFrom` used to compute the hard way. Kept because it
      // is the user-visible promise — "the percentage you set is the
      // percentage you keep" — not because of how it is arrived at.
      const from = CanvasZoomScale(1.25);
      const to = CanvasZoomScale(2.0);
      final stored = from.toDevice(CanvasViewport(zoom: 0.8, panX: 30));

      expect(to.display(to.fromDevice(stored).zoom), closeTo(1.0, 1e-12));
      expect(from.display(from.fromDevice(stored).zoom), closeTo(1.0, 1e-12));
      // ⭐The artwork covers the same DEVICE pixels — that IS the exclusion.
      expect(
        to.fromDevice(stored).zoom * 2.0,
        closeTo(from.fromDevice(stored).zoom * 1.25, 1e-12),
      );
    });

    testWidgets('of() reads the EFFECTIVE ratio, so the UI scale is in it', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.25;
      tester.view.physicalSize = const Size(2000, 1250);
      addTearDown(tester.view.reset);

      late CanvasZoomScale scale;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData.fromView(
            WidgetsBinding.instance.platformDispatcher.views.first,
          ),
          child: EffectiveDevicePixelRatioScope(
            uiScale: 1.5,
            child: Builder(
              builder: (context) {
                scale = CanvasZoomScale.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(scale.ratio, closeTo(1.875, 1e-9));
    });
  });

  group('the panel speaks the convention', () {
    // Wide enough that the pill shows its whole zoom cluster — the 1:1
    // button is the first thing a narrow panel folds away.
    Widget harness({
      required double uiScale,
      CanvasViewport? viewport,
      ValueNotifier<CanvasViewport?>? controller,
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
                    canvasSize: const CanvasSize(width: 300, height: 300),
                  ),
                  availableFrameKeys: frameKeys,
                  cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                  floorCover: EdgeInsets.zero,
                  canvasSize: const CanvasSize(width: 300, height: 300),
                  viewport: viewport,
                  viewportController: controller,
                ),
              ),
            ),
          ),
        ),
      );
    }

    String readout(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('canvas-viewport-zoom-label'),
            ),
            matching: find.byType(Text),
          ),
        )
        .data!;

    testWidgets('the readout counts DEVICE pixels, not logical ones', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.5;
      tester.view.physicalSize = const Size(2400, 1800);
      addTearDown(tester.view.reset);

      // ⚠️`viewport:` is in DEVICE units, so it IS the percentage — 1.5
      // device pixels per artwork pixel reads 150%, on any display. The
      // number the caller writes and the number the user reads are finally
      // the same number.
      await tester.pumpWidget(
        harness(uiScale: 1.0, viewport: CanvasViewport(zoom: 1.5)),
      );
      await tester.pump();
      expect(readout(tester), '150%');

      // And the bare constructor is 100% here — the same value that, read
      // as a logical zoom, put the artwork at 150% and called it 100%.
      await tester.pumpWidget(
        harness(uiScale: 1.0, viewport: CanvasViewport()),
      );
      await tester.pump();
      expect(readout(tester), '100%');
    });

    testWidgets('the UI scale does not touch what the document view shows', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.5;
      tester.view.physicalSize = const Size(2400, 1800);
      addTearDown(tester.view.reset);

      final owner = ValueNotifier<CanvasViewport?>(null);
      addTearDown(owner.dispose);
      Widget scaled(double uiScale) {
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
                  width: 600,
                  height: 420,
                  child: BrushCanvasPanel(
                    key: const ValueKey<String>('scale-probe-panel'),
                    coordinator: BrushCanvasFixture.createCoordinator(
                      frameKeys: frameKeys,
                      canvasSize: const CanvasSize(width: 300, height: 300),
                    ),
                    availableFrameKeys: frameKeys,
                    cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                    floorCover: EdgeInsets.zero,
                    canvasSize: const CanvasSize(width: 300, height: 300),
                    viewportController: owner,
                  ),
                ),
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(scaled(1.0));
      await tester.pump();
      final before = readout(tester);

      // The user picks 125%: the root matrix grows, and this view must not.
      await tester.pumpWidget(scaled(1.25));
      // ⛔Read it on the FIRST frame, before any `pump()`. The old hold made
      // frame 2 right on its own, so a pin that settled first passed with
      // the correction deleted and the user still saw one wrong frame.
      // Nothing corrects anything now — the stored value never moved — so
      // this line is the claim that there is no frame to be wrong.
      expect(
        readout(tester),
        before,
        reason: 'the FIRST frame after a scale change is already correct',
      );
      await tester.pump();
      expect(
        readout(tester),
        before,
        reason: 'the percentage is the invariant across a scale change',
      );
      // ⭐And the STORED value is untouched, which is the whole of layer 3:
      // it is in device units, so it means the same thing at both ratios.
      // Still null, in fact — nobody framed this view, and "unframed" and
      // "one artwork pixel per device pixel" are the same value here.
      expect(
        owner.value,
        isNull,
        reason: 'a ratio change writes NOTHING — there is nothing to correct',
      );
    });

    testWidgets('an OWNER that reframes the view repaints the canvas, not '
        'just the readout', (tester) async {
      // 🚨The hole the controller opened. The view used to arrive as a PROP,
      // so an owner that reframed it rebuilt the panel by definition; handed
      // a notifier, the owner writes into an object the panel only READS and
      // nothing schedules a frame. Measured on the playback stop restore.
      //
      // ⛔The witness is the GESTURE LAYER, deliberately, and not the pill's
      // percentage: the pill is handed the notifier itself and listens on its
      // own, so it prints the new number whether or not the canvas moved. The
      // gesture layer takes the viewport as a build-time value — and it is
      // what turns a press into an artwork coordinate, so a stale one means
      // the strokes land where the picture used to be.
      tester.view.devicePixelRatio = 1.5;
      tester.view.physicalSize = const Size(2400, 1800);
      addTearDown(tester.view.reset);
      final owner = ValueNotifier<CanvasViewport?>(null);
      addTearDown(owner.dispose);

      await tester.pumpWidget(harness(uiScale: 1.0, controller: owner));
      await tester.pump();

      CanvasViewport layerViewport() => tester
          .widget<CanvasViewportGestureLayer>(
            find.byType(CanvasViewportGestureLayer).first,
          )
          .viewport;
      final opened = layerViewport();

      // ⚠️The owner writes DEVICE pixels; the layer is handed LOGICAL ones.
      // Crossing the boundary in the assertion is the point — 37 device
      // pixels of pan must show up as 37/1.5 logical, and a pin that wrote
      // and read the same number would pass with the projection deleted.
      owner.value = CanvasViewport(panX: 37);
      await tester.pump();
      expect(
        layerViewport().panX,
        closeTo(opened.panX + 37 / 1.5, 1e-9),
        reason: "the owner's frame is the canvas's frame, in one pump",
      );
    });

    testWidgets('⭐a view that was UNMOUNTED across the scale change comes '
        'back at the percentage it left at (C5)', (tester) async {
      // 🚨The blocker device units exist to make unrepresentable. A document
      // tab the user closed has no panel, so nothing was there to re-zoom
      // its stored view when the UI scale moved — it came back having
      // absorbed the scale factor in full. Every fix that kept the view in
      // logical units needed someone AWAKE at the moment of the change: the
      // tab itself (not mounted), or an owner walking its viewports (which
      // is a list nobody can be sure is complete).
      //
      // Stored in device pixels, the value simply does not depend on the
      // ratio, so being asleep through the change costs nothing.
      tester.view.devicePixelRatio = 1.5;
      tester.view.physicalSize = const Size(2400, 1800);
      addTearDown(tester.view.reset);
      // A tab framed at 400% before it was closed.
      final closedTab = ValueNotifier<CanvasViewport?>(
        CanvasViewport(zoom: 4.0, panX: 60),
      );
      addTearDown(closedTab.dispose);

      // It is NOT on screen while the scale moves — that is the whole
      // scenario, so the panel never mounts at the old ratio at all.
      await tester.pumpWidget(harness(uiScale: 1.0));
      await tester.pump();

      // The user raises the UI scale, then reopens the tab.
      await tester.pumpWidget(harness(uiScale: 1.25, controller: closedTab));
      await tester.pumpAndSettle();

      expect(
        readout(tester),
        '400%',
        reason: 'the percentage it was closed at, not that times the scale',
      );
      expect(
        closedTab.value!.zoom,
        4.0,
        reason: 'and nothing rewrote the stored value to make that true',
      );
    });

    testWidgets('a scale change survives a host that setStates on the '
        'viewport callback', (tester) async {
      // 🚨The defect this exists for shipped past a harness that only wrote
      // the value down. The REAL consumer answers `onViewportChanged` with
      // its own `setState`, and the ratio-change correction used to run
      // from `didChangeDependencies` — inside the panel's rebuild — so
      // every scale change raised "setState() called during build" on an
      // ancestor. The correction is gone, and this stays: it is the pin
      // that a scale change writes nothing at all, which is the strongest
      // possible form of "it does not write during build".
      tester.view.devicePixelRatio = 1.5;
      tester.view.physicalSize = const Size(2400, 1800);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const _ScaleHost(uiScale: 1.0));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final opened = readout(tester);

      await tester.pumpWidget(const _ScaleHost(uiScale: 1.25));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'a scale change must not write from inside a build',
      );

      final state = tester.state<_ScaleHostState>(find.byType(_ScaleHost));
      expect(
        state.viewport,
        isNull,
        reason: 'the host was never called — a ratio change is not an edit',
      );
      expect(
        readout(tester),
        opened,
        reason: 'and the view held its percentage anyway',
      );
    });

    testWidgets('1:1 means one artwork pixel per device pixel', (tester) async {
      tester.view.devicePixelRatio = 1.5;
      tester.view.physicalSize = const Size(2400, 1800);
      addTearDown(tester.view.reset);

      // ⚠️No `viewport:` — a CONTROLLED viewport is pushed back over the
      // panel's own on the next build, so a reset would be undone by the
      // harness rather than by the code under test.
      await tester.pumpWidget(harness(uiScale: 1.0));
      await tester.pump();
      // An uncontrolled panel already OPENS at the identity, so frame it
      // somewhere else first or the button has nothing to prove.
      expect(readout(tester), '100%');
      await tester.tap(
        find.byKey(const ValueKey<String>('canvas-viewport-fit')),
      );
      await tester.pump();
      expect(readout(tester), isNot('100%'));

      // 1:1 folds into the gear on any pill that is not the floor's.
      await tapInViewSettings(tester, 'canvas-viewport-reset');
      expect(readout(tester), '100%');
    });
  });
}

/// A host that answers `onViewportChanged` the way the real one does — with
/// its own `setState`. That is the whole point: a harness that only records
/// the value measures "the callback fired", never "it fired somewhere it was
/// allowed to".
class _ScaleHost extends StatefulWidget {
  const _ScaleHost({required this.uiScale});

  final double uiScale;

  @override
  State<_ScaleHost> createState() => _ScaleHostState();
}

class _ScaleHostState extends State<_ScaleHost> {
  CanvasViewport? viewport;

  @override
  Widget build(BuildContext context) {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    return MediaQuery(
      data: MediaQueryData.fromView(
        WidgetsBinding.instance.platformDispatcher.views.first,
      ),
      child: EffectiveDevicePixelRatioScope(
        uiScale: widget.uiScale,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 420,
              child: BrushCanvasPanel(
                coordinator: BrushCanvasFixture.createCoordinator(
                  frameKeys: frameKeys,
                  canvasSize: const CanvasSize(width: 300, height: 300),
                ),
                availableFrameKeys: frameKeys,
                cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                floorCover: EdgeInsets.zero,
                canvasSize: const CanvasSize(width: 300, height: 300),
                viewport: viewport,
                onViewportChanged: (next) => setState(() => viewport = next),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
