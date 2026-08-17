import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/integral_layer_offset.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

import '../../helpers/brush_canvas_fixture.dart';

/// The integral layer offset LAW: whatever fractional offset panel layout
/// hands the canvas area, the canvas content's accumulated paint transform
/// lands on the DEVICE-pixel grid.
///
/// Why it is a law and not a nicety: Skia's raster cache snaps a stable
/// picture's layer to integral device translation and replays the cached
/// raster there, while live repaints render at the fractional offset the
/// layout produced — the flip hopped axis-aligned edges by 1px at every
/// pen-down / pen-up / layer switch (device-confirmed 2026-08-17). No
/// in-picture transform can close that gap (the cache replays the SAME
/// picture at a snapped CTM, so an in-picture correction is replayed
/// snapped too); the only agreeable coordinate is the layer offset
/// itself.
///
/// 🚨What this law does NOT cover — and why `willChange: true` came back
/// (`bypass_raster_cache_wiring_test.dart` owns that half): the wrapper's
/// measurement is a post-frame chain, so the frame OF an ancestor layout
/// change paints with the PREVIOUS compensation and the boundary sits
/// fractional for exactly that frame — while its unchanged picture is
/// still stable-CACHED, so the snap is live on precisely that frame. Tool
/// panels opening, wheel-click chrome, active-layer switches are ancestor
/// layout changes, which is how #1106 (wrapper alone, hint retired) put
/// the device jumps back. The one-frame gap is PINNED AND QUANTIFIED
/// below at the device's own DPR shape (1.25), as the standing proof that
/// the wrapper composes with the hint instead of replacing it.
void main() {
  const dpr = 3.0;

  /// The accumulated paint translation of [box], in DEVICE pixels.
  Offset deviceOffsetOf(RenderBox box) {
    final transform = box.getTransformTo(null);
    return Offset(transform.storage[12] * dpr, transform.storage[13] * dpr);
  }

  void expectIntegral(Offset deviceOffset, String what) {
    expect(
      (deviceOffset.dx - deviceOffset.dx.roundToDouble()).abs(),
      lessThan(1e-3),
      reason: '$what must sit on the device-pixel grid in x '
          '(got ${deviceOffset.dx})',
    );
    expect(
      (deviceOffset.dy - deviceOffset.dy.roundToDouble()).abs(),
      lessThan(1e-3),
      reason: '$what must sit on the device-pixel grid in y '
          '(got ${deviceOffset.dy})',
    );
  }

  /// LIVENESS: the uncompensated placement must actually be fractional,
  /// or the integral expectation above proves nothing.
  void expectFractional(Offset deviceOffset, String what) {
    final fracX = (deviceOffset.dx - deviceOffset.dx.roundToDouble()).abs();
    final fracY = (deviceOffset.dy - deviceOffset.dy.roundToDouble()).abs();
    expect(
      fracX + fracY,
      greaterThan(1e-2),
      reason: '$what was supposed to be FRACTIONAL — an integral placement '
          'makes the law\'s pin vacuous (got $deviceOffset)',
    );
  }

  Widget stackUnderPadding(EdgeInsets padding) {
    return MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: padding,
          child: SizedBox(
            width: 120,
            height: 90,
            child: IntegralLayerOffset(
              // The boundary mirrors the production wiring: the wrapper's
              // shift lands on THIS layer's device offset (below a
              // boundary it would be recorded in-picture, which the
              // library doc proves useless).
              child: RepaintBoundary(
                child: CanvasLayerStackView(
                  nodes: const [CanvasActiveLayerNode(opacity: 1)],
                  imageCache: LayerFrameImageCache(
                    frameStore: BrushFrameStore(),
                  ),
                  canvasSize: const CanvasSize(width: 16, height: 16),
                  viewport: CanvasViewport(zoom: 1),
                  paintPaper: true,
                  paperBackground: const ProjectBackground.color(0xFFFFFFFF),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a fractionally-placed canvas stack still lands on the '
      'device-pixel grid', (tester) async {
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.resetDevicePixelRatio);

    // 10.37 logical × dpr 3 = 31.11 device px — deliberately fractional.
    await tester.pumpWidget(
      stackUnderPadding(const EdgeInsets.only(left: 10.37, top: 7.13)),
    );
    await tester.pumpAndSettle();

    // The wrapper's OWN offset excludes its own transform: this is what
    // layout handed us, and it must be off-grid for the pin to bite.
    expectFractional(
      deviceOffsetOf(
        tester.renderObject(find.byType(IntegralLayerOffset)) as RenderBox,
      ),
      'the padding-placed wrapper',
    );
    // MUTATION oracle: compensating with Offset.zero (dropping the
    // measurement) leaves the stack at the fractional offset above — red.
    expectIntegral(
      deviceOffsetOf(
        tester.renderObject(find.byType(CanvasLayerStackView)) as RenderBox,
      ),
      'the canvas stack under a fractional padding',
    );
  });

  testWidgets('the compensation follows a layout change to a NEW '
      'fractional offset', (tester) async {
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      stackUnderPadding(const EdgeInsets.only(left: 10.37, top: 7.13)),
    );
    await tester.pumpAndSettle();

    // The panel moved (a splitter drag, a bar folding). The measurement
    // is a post-frame chain precisely because ancestors move this subtree
    // without rebuilding it — the correction must land again.
    await tester.pumpWidget(
      stackUnderPadding(const EdgeInsets.only(left: 3.21, top: 5.55)),
    );
    await tester.pumpAndSettle();

    expectFractional(
      deviceOffsetOf(
        tester.renderObject(find.byType(IntegralLayerOffset)) as RenderBox,
      ),
      'the re-placed wrapper',
    );
    expectIntegral(
      deviceOffsetOf(
        tester.renderObject(find.byType(CanvasLayerStackView)) as RenderBox,
      ),
      'the canvas stack after the move',
    );
  });

  group('the one-frame gap, quantified at the device DPR shape (1.25)', () {
    // DPR 1.25 is the Windows-device shape: EVERY logical-integer layout
    // offset is device-fractional unless it is a multiple of 4 logical
    // pixels, so ordinary chrome relayouts (a tool panel opening, wheel-
    // click chrome) move the canvas to a new fractional phase constantly.
    const deviceDpr = 1.25;

    /// The accumulated paint translation of [box] at [deviceDpr].
    Offset deviceOffsetAt(RenderBox box) {
      final transform = box.getTransformTo(null);
      return Offset(
        transform.storage[12] * deviceDpr,
        transform.storage[13] * deviceDpr,
      );
    }

    testWidgets(
      'the frame OF an ancestor layout change paints with the PREVIOUS '
      'compensation — fractional by exactly (new phase − old phase)',
      (tester) async {
        tester.view.devicePixelRatio = deviceDpr;
        addTearDown(tester.view.resetDevicePixelRatio);

        // Padding A: (10.1, 3.3) logical × 1.25 = (12.625, 4.125) device —
        // fractional parts (0.625, 0.125), so the settled compensation is
        // (−0.625, −0.125) device.
        await tester.pumpWidget(
          stackUnderPadding(const EdgeInsets.only(left: 10.1, top: 3.3)),
        );
        await tester.pumpAndSettle();
        expectIntegral(
          deviceOffsetAt(
            tester.renderObject(find.byType(CanvasLayerStackView))
                as RenderBox,
          ),
          'the settled boundary at DPR 1.25',
        );

        // Padding B: (20.3, 7.5) logical × 1.25 = (25.375, 9.375) device.
        // THE FRAME OF THE CHANGE still carries A's compensation, so the
        // boundary lands at (25.375 − 0.625, 9.375 − 0.125) =
        // (24.75, 9.25): 0.25 device pixels off the grid on both axes. This
        // is the frame the raster cache snaps — the picture did not
        // change, only its offset did — and it is the frame every
        // chrome-driven jump moment produces. The wrapper CANNOT close
        // it; `willChange: true` on the artwork pictures is what does
        // (`bypass_raster_cache_wiring_test.dart`).
        await tester.pumpWidget(
          stackUnderPadding(const EdgeInsets.only(left: 20.3, top: 7.5)),
        );
        final staleFrame = deviceOffsetAt(
          tester.renderObject(find.byType(CanvasLayerStackView)) as RenderBox,
        );
        expect(
          (staleFrame.dx - staleFrame.dx.roundToDouble()).abs(),
          moreOrLessEquals(0.25, epsilon: 1e-3),
          reason: 'the change frame must sit at the STALE phase '
              '(24.75 device px → 0.25 from the grid) — an integral '
              'reading here would mean the compensation somehow landed '
              'same-frame and the one-frame gap is closed '
              '(got ${staleFrame.dx})',
        );
        expect(
          (staleFrame.dy - staleFrame.dy.roundToDouble()).abs(),
          moreOrLessEquals(0.25, epsilon: 1e-3),
          reason: 'the change frame must sit at the STALE phase in y '
              '(9.25 device px → 0.25 from the grid) '
              '(got ${staleFrame.dy})',
        );

        // One more frame: the post-frame measurement from the change
        // frame lands its setState, and the boundary is integral again.
        await tester.pump();
        expectIntegral(
          deviceOffsetAt(
            tester.renderObject(find.byType(CanvasLayerStackView))
                as RenderBox,
          ),
          'the boundary one frame after the change',
        );
      },
    );
  });

  testWidgets('under an ancestor rotation the wrapper fails OPEN — no '
      'compensation rather than a wrong one', (tester) async {
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.resetDevicePixelRatio);

    // The gate, not the law: panels are axis-aligned, so this geometry
    // does not occur in the app — but if it ever does, "round to a device
    // pixel" has no single direction and a guessed shift would smear.
    await tester.pumpWidget(
      MaterialApp(
        home: Transform.rotate(
          angle: 0.25,
          child: Padding(
            padding: const EdgeInsets.only(left: 10.37, top: 7.13),
            child: SizedBox(
              width: 120,
              height: 90,
              child: IntegralLayerOffset(
                child: RepaintBoundary(
                  child: CanvasLayerStackView(
                    nodes: const [CanvasActiveLayerNode(opacity: 1)],
                    imageCache: LayerFrameImageCache(
                      frameStore: BrushFrameStore(),
                    ),
                    canvasSize: const CanvasSize(width: 16, height: 16),
                    viewport: CanvasViewport(zoom: 1),
                    paintPaper: true,
                    paperBackground: const ProjectBackground.color(0xFFFFFFFF),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final wrapperTransform = tester.widget<Transform>(
      find
          .descendant(
            of: find.byType(IntegralLayerOffset),
            matching: find.byType(Transform),
          )
          .first,
    );
    final translation = wrapperTransform.transform.getTranslation();
    expect(
      Offset(translation.x, translation.y),
      Offset.zero,
      reason: 'a rotated subtree has no well-defined device-pixel grid — '
          'the wrapper must refuse to guess',
    );
  });

  testWidgets('the panel mounts the wrapper ABOVE the content boundary, '
      'and the boundary lands on the grid', (tester) async {
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.resetDevicePixelRatio);

    final frameKeys = BrushCanvasFixture.createFrameKeys();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            // The deliberately fractional panel placement — the exact
            // situation the desktop layout produces and the raster cache
            // snapped against.
            padding: const EdgeInsets.only(left: 10.37, top: 7.13),
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

    final boundaryFinder = find.byKey(
      const ValueKey<String>('canvas-content-boundary'),
    );
    // ⛔ORDER IS THE LAW: below the boundary the shift would be recorded
    // in-picture, and the cache replays the same picture at a snapped CTM
    // — an in-picture correction contradicts itself. Only a wrapper ABOVE
    // the boundary moves the layer offset the cache actually snaps.
    expect(
      find.ancestor(
        of: boundaryFinder,
        matching: find.byType(IntegralLayerOffset),
      ),
      findsOneWidget,
      reason: 'the wrapper must sit above the content boundary — below it '
          'the compensation is in-picture and mathematically void',
    );

    expectFractional(
      deviceOffsetOf(
        tester.renderObject(find.byType(IntegralLayerOffset)) as RenderBox,
      ),
      'the fractionally-padded panel content',
    );
    expectIntegral(
      deviceOffsetOf(tester.renderObject(boundaryFinder) as RenderBox),
      'the canvas content boundary',
    );
  });
}
