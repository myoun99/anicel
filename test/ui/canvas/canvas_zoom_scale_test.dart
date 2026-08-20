import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/viewport_point.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
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

    test('rescaledFrom holds the DISPLAY zoom across a ratio change', () {
      final anchor = ViewportPoint(x: 200, y: 150);
      final viewport = CanvasViewport(zoom: 0.8, panX: 30, panY: -12);
      const from = CanvasZoomScale(1.25);
      const to = CanvasZoomScale(2.0);

      final held = to.rescaledFrom(from, viewport, anchor: anchor);
      expect(to.display(held.zoom), closeTo(from.display(viewport.zoom), 1e-12));
      // ⭐The artwork covers the same DEVICE pixels — that IS the exclusion.
      expect(held.zoom * 2.0, closeTo(viewport.zoom * 1.25, 1e-12));
    });

    test('rescaledFrom keeps the anchored canvas point under the anchor', () {
      final anchor = ViewportPoint(x: 200, y: 150);
      final viewport = CanvasViewport(zoom: 0.8, panX: 30, panY: -12);
      final before = viewport.viewportToCanvas(anchor);
      final held = const CanvasZoomScale(
        2.0,
      ).rescaledFrom(const CanvasZoomScale(1.25), viewport, anchor: anchor);
      final after = held.viewportToCanvas(anchor);
      expect(after.x, closeTo(before.x, 1e-9));
      expect(after.y, closeTo(before.y, 1e-9));
    });

    test('an unchanged ratio returns the identical viewport', () {
      final viewport = CanvasViewport(zoom: 0.8, panX: 30);
      expect(
        identical(
          const CanvasZoomScale(1.5).rescaledFrom(
            const CanvasZoomScale(1.5),
            viewport,
            anchor: ViewportPoint(x: 0, y: 0),
          ),
          viewport,
        ),
        isTrue,
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
    Widget harness({required double uiScale, CanvasViewport? viewport}) {
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

      // A logical zoom of 1.0 on a 1.5 display puts one artwork pixel into
      // 1.5 device pixels — which is 150%, and used to read "100%".
      await tester.pumpWidget(
        harness(uiScale: 1.0, viewport: CanvasViewport(zoom: 1.0)),
      );
      await tester.pump();
      expect(readout(tester), '150%');

      await tester.pumpWidget(
        harness(uiScale: 1.0, viewport: CanvasViewport(zoom: 1 / 1.5)),
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

      CanvasViewport? reported;
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
                    onViewportChanged: (v) => reported = v,
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
      // ⛔Read it on the FIRST frame, before any `pump()`. This is the whole
      // point of the held viewport: the post-frame commit would make frame
      // 2 right on its own, so a test that settles first passes with the
      // hold deleted and the user still sees one wrong frame. Deleting
      // `_ratioHeldViewport ??` from the `_viewport` getter must turn THIS
      // line red.
      expect(
        readout(tester),
        before,
        reason: 'the FIRST frame after a scale change is already correct — '
            'the hold, not the post-frame commit, is what makes it so',
      );
      await tester.pump();
      expect(
        readout(tester),
        before,
        reason: 'the percentage is the invariant across a scale change',
      );
      // And the panel really re-zoomed rather than the readout lying: the
      // logical zoom dropped by exactly the factor the matrix gained.
      expect(reported, isNotNull);
      // The DEVICE coverage is what must be unchanged: render x effective
      // ratio is the display zoom, and the view opened at 100%.
      expect(reported!.zoom * (1.5 * 1.25), closeTo(1.0, 1e-9));
    });

    testWidgets('a scale change survives a host that setStates on the '
        'viewport callback', (tester) async {
      // 🚨The defect this exists for shipped past a harness that only wrote
      // the value down. The REAL consumer (`editor_canvas_area.dart`)
      // answers `onViewportChanged` with its own `setState`, and the
      // ratio-change hold used to commit from `didChangeDependencies` —
      // inside the panel's rebuild — so every scale change raised
      // "setState() called during build" on an ancestor.
      tester.view.devicePixelRatio = 1.5;
      tester.view.physicalSize = const Size(2400, 1800);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const _ScaleHost(uiScale: 1.0));
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const _ScaleHost(uiScale: 1.25));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'the hold must not commit from inside a build',
      );

      // And it really did land — the host holds the re-zoomed view.
      final state = tester.state<_ScaleHostState>(find.byType(_ScaleHost));
      expect(state.viewport, isNotNull);
      expect(state.viewport!.zoom * (1.5 * 1.25), closeTo(1.0, 1e-9));
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
