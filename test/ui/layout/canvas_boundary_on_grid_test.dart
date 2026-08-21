import 'package:anicel/src/ui/effective_device_pixel_ratio.dart';
import 'package:anicel/src/ui/ui_scale.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_dock_host.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/scaled_test_binding.dart';

/// 🎯**The round's headline.** The chain from the window origin to the
/// canvas must land the canvas on a whole device pixel, at any effective
/// ratio, by construction.
///
/// 🚨**The anchor moved, and the old warning INVERTED.** It used to read:
/// "measure `IntegralLayerOffset`, NOT the `canvas-content-boundary` key",
/// because the key sat on a `RepaintBoundary` INSIDE that wrapper and
/// `RenderTransform` applies its matrix in its PARENT's
/// `applyPaintTransform` — so `localToGlobal` on the keyed box read the
/// wrapper's COMPENSATED output rather than the chain feeding it. A first
/// draft did exactly that and **passed verbatim on master**, with the
/// editing canvas 0.2 device px off at 1.35.
///
/// The wrapper is gone (R11 retired it — the chain is integral by
/// construction, so there was nothing left to compensate), which means
/// **the key IS the uncompensated chain now**. Nothing sits between it and
/// panel layout. ⛔If a compensating transform is ever reintroduced above
/// this boundary, move the anchor back above it or this whole file starts
/// measuring the compensation instead of the chain.
///
/// ⚠️Fractional ratios throughout, and BOTH `devicePixelRatio` and
/// `physicalSize` are set. `setSurfaceSize` is forbidden here: it
/// desynchronises MediaQuery from the render tree and builds a letterbox
/// scale into the root.
void main() {
  // 🚨The BINDING half, and this file is where it matters most.
  //
  // The scale reaches pixels through `createViewConfigurationFor`, which
  // lives on the binding — not through anything a widget can mount. Under
  // the default test binding the scope below publishes `monitor × scale`
  // to the widgets while the compositor still scales by the raw monitor
  // ratio, so every "on the grid at 1.35" case here was checking its own
  // arithmetic against a grid nothing rasterises to. Self-consistent, and
  // proof of nothing.
  //
  // ⚠️It also replaces the 800×600 test-surface hook, so every case sets
  // `physicalSize` itself. `setSurfaceSize` stays forbidden here.
  ScaledTestBinding.ensureInitialized();

  tearDown(() => AppUiScale.value.value = AppUiScale.defaultScale);

  /// The app shell, wired to the scale the way `main.dart` wires it — the
  /// binding reads [AppUiScale] and so does the scope, from one listener,
  /// so the two halves cannot disagree about what the scale is.
  ///
  /// ⛔Do not take the scale as a parameter here. That was the old shape,
  /// and it let a case set the widget half while leaving the binding at
  /// 100% — which is exactly the hole this file grew.
  Widget shell() => ValueListenableBuilder<double>(
    valueListenable: AppUiScale.value,
    builder: (context, scale, _) => MaterialApp(
      builder: (context, child) => EffectiveDevicePixelRatioScope(
        uiScale: scale,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomePage(),
    ),
  );

  /// The UNCOMPENSATED chain origins, in device pixels, largest first.
  ///
  /// Two canvases mount a content boundary — the editing canvas, which
  /// fills the workspace, and a rail-docked preview. Size is what tells
  /// them apart, and keeping them separate is what lets each be asserted
  /// for what it is; both are on the grid at every ratio today, but they
  /// got there in different PRs and the split is what proved it.
  List<({Offset device, Size size})> chainOrigins(
    WidgetTester tester,
    double effectiveRatio,
  ) {
    final finder = find.byKey(
      const ValueKey<String>('canvas-content-boundary'),
    );
    expect(
      finder,
      findsWidgets,
      reason: 'the content boundary must exist to be read',
    );
    final found = <({Offset device, Size size})>[
      for (final element in finder.evaluate())
        () {
          final box = element.renderObject! as RenderBox;
          final logical = box.localToGlobal(Offset.zero);
          return (
            device: Offset(
              logical.dx * effectiveRatio,
              logical.dy * effectiveRatio,
            ),
            size: box.size,
          );
        }(),
    ];
    found.sort(
      (a, b) => (b.size.width * b.size.height).compareTo(
        a.size.width * a.size.height,
      ),
    );
    return found;
  }

  double offGridBy(double device) => (device - device.roundToDouble()).abs();

  void expectOnGrid(Offset device, {required String at}) {
    for (final (axis, value) in <(String, double)>[
      ('x', device.dx),
      ('y', device.dy),
    ]) {
      expect(
        offGridBy(value),
        lessThan(1e-3),
        reason:
            '$at: the canvas chain reaches device $axis=$value, '
            '${offGridBy(value).toStringAsFixed(4)} of a pixel off the grid. '
            'Something between the window origin and here — the safe-area '
            'inset, the top strip, or the tool strip — is choosing a '
            'non-integral number of device pixels.',
      );
    }
  }

  for (final ratio in <double>[1.125, 1.25, 1.35, 1.75]) {
    testWidgets('the EDITING canvas chain is on the grid at ratio $ratio', (
      tester,
    ) async {
      tester.view.devicePixelRatio = ratio;
      tester.view.physicalSize = Size(1600 * ratio, 1000 * ratio);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(shell());
      await tester.pumpAndSettle();

      expectOnGrid(
        chainOrigins(tester, ratio).first.device,
        at: 'ratio $ratio',
      );
    });
  }

  testWidgets('★the editing canvas chain survives a PRODUCT ratio', (
    tester,
  ) async {
    // 1.5 × 0.9 = 1.35, where an integer would have to be a multiple of 20
    // to land on the grid by itself. Nothing in the chain is. The chain's
    // constants sit on the grid at every Windows scaling step by LUCK —
    // 48 = 16×3 — and a UI scale is exactly what destroys that luck.
    //
    // ✅The debt this case used to carry is PAID, and it was paid TWICE.
    // First the override had to exist; then this file had to actually run
    // it. The old note claimed "1.35 IS the compositor's grid here" while
    // the file still ran under the default binding, where it was 1.5 — the
    // claim was true of the app and false of the test asserting it.
    // `ScaledTestBinding` closes that, and the scale is set through the
    // notifier the app itself reads.
    const monitor = 1.5;
    const scale = 0.9;
    tester.view.devicePixelRatio = monitor;
    tester.view.physicalSize = const Size(1600 * monitor, 1000 * monitor);
    addTearDown(tester.view.reset);

    AppUiScale.value.value = scale;
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();
    expect(
      tester.binding.renderViews.single.configuration.devicePixelRatio,
      closeTo(monitor * scale, 1e-9),
      reason: 'the ROOT matrix carries the product — not just the widgets',
    );

    expectOnGrid(
      chainOrigins(tester, monitor * scale).first.device,
      at: 'product 1.35',
    );
  });

  group('the RAIL-DOCKED canvas chain', () {
    Future<Offset> railDockedAt(WidgetTester tester, double ratio) async {
      tester.view.devicePixelRatio = ratio;
      tester.view.physicalSize = Size(1600 * ratio, 1000 * ratio);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(shell());
      await tester.pumpAndSettle();
      final origins = chainOrigins(tester, ratio);
      expect(origins.length, greaterThanOrEqualTo(2));
      return origins[1].device;
    }

    // 🎯Closed at every ratio. What finally did it was the two `Positioned`
    // widgets that actually CARRY the column: they were still re-adding a
    // raw `_railGroupGap` to a raw width, while the quantized spans sat
    // 130 lines above and were handed only to `floorCover` and
    // `columnStop`. The canvas is framed against one boundary and the rail
    // was drawn at another.
    //
    // ⚠️An earlier draft of this file blamed "the column stop and the
    // bottom region's 2/3 split", and that was wrong on both counts —
    // `_regionOnTop` is false, so the stops land in `bottom:` and never in
    // `top:`, and the bottom region is not an ancestor of this chain at
    // all. A wrong culprit in a test comment aims the next PR at nothing.
    for (final ratio in <double>[1.125, 1.25, 1.35, 1.75]) {
      testWidgets('is on the grid at ratio $ratio', (tester) async {
        expectOnGrid(await railDockedAt(tester, ratio), at: 'rail $ratio');
      });
    }
  });

  testWidgets('the rail gap beside the strip is a whole number of device '
      'pixels', (tester) async {
    // ⚠️Pinned DIRECTLY, because it is currently unobservable from the
    // canvas: 8 is already integral at 1.125, 1.25 and 1.75, and the one
    // ratio where it matters — 1.35, where 8 × 1.35 is 10.8 — is a ratio
    // at which a larger fraction upstream still dominates the rail-docked
    // boundary. Without this the quantization would ship unpinned and a
    // later edit could undo it silently, only for the defect to surface
    // when the upstream work finally lands.
    const ratio = 1.35;
    tester.view.devicePixelRatio = ratio;
    tester.view.physicalSize = const Size(1600 * ratio, 1000 * ratio);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();

    final found = find
        .byKey(const ValueKey<String>('rail-group-gap'))
        .evaluate();
    expect(found, isNotEmpty, reason: 'the rail gap must be in the tree');
    for (final element in found) {
      final padding = (element.renderObject! as RenderPadding).padding.resolve(
        TextDirection.ltr,
      );
      for (final side in <double>[padding.left, padding.right]) {
        if (side == 0) {
          continue;
        }
        expect(
          offGridBy(side * ratio),
          lessThan(1e-3),
          reason: 'a rail gap of $side logical is ${side * ratio} device px',
        );
      }
    }
  });

  group('the empty dock drop zone', () {
    for (final ratio in <double>[1.125, 1.25, 1.35, 1.75]) {
      testWidgets('occupies a whole number of device pixels at $ratio', (
        tester,
      ) async {
        // 🚨The one reachable phase jump the recon found. This zone exists
        // ONLY while a tab is in the air, and its footprint shifts
        // everything beside it — including the canvas — on a frame that is
        // itself a layout change. 30 logical px is 37.5 device at 1.25.
        //
        // ⚠️A first draft of this case never mounted the zone and asserted
        // `isOnGrid(position(30))`, which is true by the definition of
        // `position`. It also named a transition that does not occur: an
        // emptied strip REPLACES the filled dock rather than adding to it,
        // so the reachable widths are 0 / this / the dock's.
        tester.view.devicePixelRatio = ratio;
        tester.view.physicalSize = Size(800 * ratio, 600 * ratio);
        addTearDown(tester.view.reset);

        final dragging = ValueNotifier<EditorPanelTabDragData?>(
          const EditorPanelTabDragData(tabId: 't', fromGroupId: 'elsewhere'),
        );
        addTearDown(dragging.dispose);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: EditorDockDropZone(
                dockId: 'probe',
                axis: Axis.vertical,
                draggingTab: dragging,
                canAcceptTab: (_) => true,
                onDropped: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();

        final rendered = tester.getSize(find.byType(EditorDockDropZone));
        expect(
          offGridBy(rendered.width * ratio),
          lessThan(1e-3),
          reason:
              'the zone occupies ${rendered.width} logical = '
              '${rendered.width * ratio} device px at $ratio',
        );

        // …and it occupies the SAME width with nothing in the air (유저
        // 2026-08-21: 통일). Landing on the grid stopped the change from
        // smearing across half a device pixel; it did not stop the change.
        // The zone reserves its place and alters only what it DRAWS —
        // which is the standing law (「자리는 항상 예약하고 내용만
        // 바꾼다」) finally arriving here.
        dragging.value = null;
        await tester.pump();
        expect(
          tester.getSize(find.byType(EditorDockDropZone)).width,
          rendered.width,
          reason: 'the tab-lift frame must not move the canvas beside it',
        );
      });
    }
  });

  group('ON THE FRAME OF A LAYOUT CHANGE', () {
    // 🎯**The group that decides whether the two defensive measures can be
    // retired**, and the one measurement the previous attempt never had.
    //
    // #1106 retired `willChange: true` and leaned on [IntegralLayerOffset]
    // instead. It came back on device (2026-08-17) for ONE reason, written
    // in that widget's own doc: the wrapper MEASURES, from a post-frame
    // callback, so the frame OF an ancestor layout change still paints
    // with the PREVIOUS compensation — and the jump moments (a panel
    // opening, a tool change, an active-layer switch) ARE
    // ancestor-layout-change frames.
    //
    // R11 does not measure. It makes every app-chosen offset an integral
    // count of device pixels IN LAYOUT, so a layout-change frame lays out
    // on the grid in that same frame. There is no stale compensation
    // because there is no compensation.
    //
    // ⛔So these pump EXACTLY ONE frame after the change. Settling first
    // lets the wrapper's post-frame chain catch up, and would measure the
    // state that was never in doubt.
    for (final ratio in <double>[1.25, 1.35]) {
      testWidgets('opening a panel leaves the chain on the grid at $ratio', (
        tester,
      ) async {
        tester.view.devicePixelRatio = ratio;
        tester.view.physicalSize = Size(1600 * ratio, 1000 * ratio);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(shell());
        await tester.pumpAndSettle();
        expectOnGrid(
          chainOrigins(tester, ratio).first.device,
          at: 'settled at $ratio',
        );

        // Opening the menu is setup, not the moment under test.
        await tester.tap(
          find.byKey(const ValueKey<String>('top-strip-settings-button')),
        );
        await tester.pumpAndSettle();
        final entry = find.byKey(
          const ValueKey<String>('panels-menu-item-media'),
        );
        await tester.ensureVisible(entry);
        await tester.pumpAndSettle();

        await tester.tap(entry);
        // ⛔ONE frame. This is the frame the wrapper cannot help with.
        await tester.pump();

        expectOnGrid(
          chainOrigins(tester, ratio).first.device,
          at: 'the frame a panel opened, at $ratio',
        );
        await tester.pumpAndSettle();
      });
    }

    testWidgets('a UI SCALE change leaves the chain on the grid in the '
        'same frame', (tester) async {
      // The largest ancestor layout change the app can produce: every
      // logical length in the shell moves at once.
      tester.view.devicePixelRatio = 1.5;
      tester.view.physicalSize = const Size(2400, 1500);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(shell());
      await tester.pumpAndSettle();
      expectOnGrid(chainOrigins(tester, 1.5).first.device, at: 'scale 100%');

      // 🚨The change is a NOTIFIER write, not a new widget tree, and that is
      // the real gesture: the user picks 90% in Preferences and nothing
      // rebuilds the app from above. Both halves hang off this one value —
      // the binding relays out the window, the scope re-publishes the
      // ratio — so writing it is the only way to exercise the pair.
      AppUiScale.value.value = 0.9;
      // `pump` renders exactly one frame — the frame OF the change.
      await tester.pump();
      // ⚠️Asserted explicitly, because at THIS surface size the chain lands
      // on the grid from the widget half alone — measured: the case stays
      // green under the default binding. Without this line it would report
      // on a scale the compositor never received.
      expect(
        tester.binding.renderViews.single.configuration.devicePixelRatio,
        closeTo(1.5 * 0.9, 1e-9),
        reason: 'the root matrix moved in the SAME frame, not after it',
      );
      expectOnGrid(
        chainOrigins(tester, 1.5 * 0.9).first.device,
        at: 'the frame the scale became 90% (effective 1.35)',
      );
      await tester.pumpAndSettle();
    });
  });
}
