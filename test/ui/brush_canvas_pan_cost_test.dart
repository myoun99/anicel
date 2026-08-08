import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/widgets/superellipse_clip.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';

import '../helpers/brush_canvas_fixture.dart';
import 'brush_canvas_test_helpers.dart';

/// What a PAN costs the panel beyond the redraw it genuinely owes.
///
/// Panning re-records the artwork by definition — the viewport moved, so
/// `_LayerStackPainter.shouldRepaint` is right to say yes, and no boundary
/// can or should change that. Everything ELSE the drag pays for is waste,
/// and this file is where it is counted.
///
/// 유저, R4 후속: 렉이라면 무조건 고치고 싶다.
void main() {
  /// The panel, with both observation seams open:
  ///
  ///  * `panelBuilds` counts the panel's own `build` runs — the underlay
  ///    builder is a callback invoked from it, so its call count IS the
  ///    rebuild count;
  ///  * `painters` records the `activeSurfacePainter` handed down on each of
  ///    those builds, which is what `CanvasLayerStackView.shouldRepaint`
  ///    compares BY IDENTITY.
  Future<void> pumpPanel(
    WidgetTester tester, {
    required List<int> panelBuilds,
    required List<BitmapSurfacePainter?> painters,
    required ActiveStrokeOverlayModel overlay,
  }) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: BrushCanvasFixture.createCoordinator(
              frameKeys: frameKeys,
            ),
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            floorCover: EdgeInsets.zero,
            // MERGED mode: this is the configuration in which the host owns
            // the overlay and the panel hands a surface painter down — i.e.
            // the one the drawing floor actually runs in.
            activeStrokeOverlayModel: overlay,
            // ⚠️NO `viewport:` PARAMETER. `build` re-applies a non-null one
            // whenever it differs from the last value the panel published,
            // so a fixture that pins it CLOBBERS the pan on every frame —
            // the viewport snaps back, the pill's token never moves, and
            // the test passes for the wrong reason. (It did, first time
            // round.) The panel owning its own viewport is what a pan looks
            // like between the host's rebuilds.
            viewportUnderlayBuilder: (context, viewport, activeSurfacePainter) {
              panelBuilds[0] += 1;
              painters.add(activeSurfacePainter);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The memoized view pill, by identity. `_ensureShellBars` hands back the
  /// SAME widget instance while its token holds, so "did panning throw the
  /// pill away" is a pointer comparison.
  Object? pillBody(WidgetTester tester) {
    final capsule = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('canvas-view-pill')),
    );
    final clip = capsule.child! as SuperellipseClip;
    return (clip.child! as SizedBox).child;
  }

  /// A middle-button drag across the canvas — the default pan mapping.
  Future<TestGesture> startPan(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      canvasGlobalOffset(tester, const Offset(60, 60)),
      buttons: kTertiaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    return gesture;
  }

  testWidgets('panning does not throw the view pill away', (tester) async {
    // 🐛The pill's memo token carried the WHOLE viewport, and `_setViewport`
    // runs a panel `setState` per `PointerMove` — so every frame of every
    // pan rebuilt the pill from scratch: thirteen icon buttons with their
    // tooltips, overlay portals, ink and gesture detectors.
    //
    // Nothing the pill SHOWS changes when the canvas is panned. The zoom
    // readout, Fit, 1:1, the rotate and flip pair, the three swatches — a
    // pan moves none of them. It is the same defect the token's own comment
    // already records one field over (the panel TITLE, measured at 391
    // widget rebuilds a step), and it survived because the cure was applied
    // to the field that had been caught rather than to the rule.
    final overlay = ActiveStrokeOverlayModel();
    addTearDown(overlay.dispose);
    final panelBuilds = <int>[0];
    final painters = <BitmapSurfacePainter?>[];
    await pumpPanel(
      tester,
      panelBuilds: panelBuilds,
      painters: painters,
      overlay: overlay,
    );

    final before = pillBody(tester);
    expect(before, isNotNull, reason: 'the pill has a body to keep');

    final gesture = await startPan(tester);
    final buildsAtStart = panelBuilds[0];
    for (var i = 1; i <= 8; i += 1) {
      await gesture.moveBy(const Offset(6, 4));
      await tester.pump();
    }

    // LIVENESS — a pan that never reached the panel would pass everything
    // below without proving anything.
    expect(
      panelBuilds[0],
      greaterThan(buildsAtStart),
      reason: 'the pan must actually have moved the viewport',
    );

    expect(
      identical(pillBody(tester), before),
      isTrue,
      reason:
          'the pill is memoized on what it SHOWS, and a pan shows none '
          'of it',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('zooming DOES rebuild the pill — the readout is in it', (
    tester,
  ) async {
    // The other half of the contract, and the reason this is not just
    // "delete the viewport from the token": the pill prints the zoom, so a
    // zoom must invalidate it. A memo that never breaks is a stale bar.
    final overlay = ActiveStrokeOverlayModel();
    addTearDown(overlay.dispose);
    final panelBuilds = <int>[0];
    final painters = <BitmapSurfacePainter?>[];
    await pumpPanel(
      tester,
      panelBuilds: panelBuilds,
      painters: painters,
      overlay: overlay,
    );

    final before = pillBody(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('canvas-viewport-zoom-in')),
    );
    await tester.pumpAndSettle();

    expect(
      identical(pillBody(tester), before),
      isFalse,
      reason: 'the zoom readout changed, so the bar must be rebuilt',
    );
  });

  testWidgets('a panel rebuild hands the layer stack the SAME surface '
      'painter', (tester) async {
    // 🐛`_activeSurfacePainterFor` minted a fresh `BitmapSurfacePainter` on
    // every call, and `CanvasLayerStackView.shouldRepaint` compares that
    // field with `!identical(...)`. So the comparison could never answer
    // false: ANY rebuild of the panel — a pan frame, a tool switch, an
    // unrelated notify — re-composited the entire layer stack, paper,
    // ghosts, group-buffer `saveLayer`s and all.
    //
    // ⚠️Not a pan-specific defect. The pan is one trigger; the blast radius
    // is every rebuild.
    final overlay = ActiveStrokeOverlayModel();
    addTearDown(overlay.dispose);
    final panelBuilds = <int>[0];
    final painters = <BitmapSurfacePainter?>[];
    await pumpPanel(
      tester,
      panelBuilds: panelBuilds,
      painters: painters,
      overlay: overlay,
    );

    expect(
      painters.first,
      isNotNull,
      reason: 'MERGED mode must actually hand a painter down',
    );

    final gesture = await startPan(tester);
    for (var i = 1; i <= 8; i += 1) {
      await gesture.moveBy(const Offset(6, 4));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      panelBuilds[0],
      greaterThan(1),
      reason: 'the panel must have rebuilt for this to mean anything',
    );
    final distinct = <BitmapSurfacePainter>{};
    for (final painter in painters) {
      if (painter != null) {
        distinct.add(painter);
      }
    }
    expect(
      distinct.length,
      1,
      reason:
          'the artwork did not change, so the painter identity that '
          'gates the whole composite must not either',
    );
  });
}
