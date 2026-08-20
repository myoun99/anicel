import 'package:anicel/src/ui/canvas/integral_layer_offset.dart';
import 'package:anicel/src/ui/effective_device_pixel_ratio.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_dock_host.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🎯**The round's headline.** The chain from the window origin to the
/// canvas must land the canvas on a whole device pixel, at any effective
/// ratio, by construction.
///
/// ⛔**Measure [IntegralLayerOffset], NOT the `canvas-content-boundary`
/// key.** That key sits on a `RepaintBoundary` INSIDE the wrapper, and
/// `RenderTransform` applies its matrix in its PARENT's
/// `applyPaintTransform` — so `localToGlobal` on the keyed box reads the
/// BRIDGE's compensated output rather than the chain feeding it. A first
/// draft of this file did exactly that and **passed verbatim on master**,
/// with the editing canvas 0.2 device px off at 1.35. The wrapper's own
/// `localToGlobal` is the uncompensated chain, which is the thing this
/// round exists to make unnecessary.
///
/// ⚠️Fractional ratios throughout, and BOTH `devicePixelRatio` and
/// `physicalSize` are set. `setSurfaceSize` is forbidden here: it
/// desynchronises MediaQuery from the render tree and builds a letterbox
/// scale into the root.
void main() {
  Widget shell({double uiScale = 1.0}) => MaterialApp(
    builder: (context, child) => EffectiveDevicePixelRatioScope(
      uiScale: uiScale,
      child: child ?? const SizedBox.shrink(),
    ),
    home: const HomePage(),
  );

  /// The UNCOMPENSATED chain origins, in device pixels, largest first.
  ///
  /// Two canvases mount a wrapper — the editing canvas, which fills the
  /// workspace, and a rail-docked preview. Size is what tells them apart,
  /// and keeping them separate is what lets each be asserted for what it
  /// is: they are at different stages of this round, and a claim about
  /// "every" boundary would be false for one of them today.
  List<({Offset device, Size size})> chainOrigins(
    WidgetTester tester,
    double effectiveRatio,
  ) {
    final finder = find.byType(IntegralLayerOffset);
    expect(finder, findsWidgets, reason: 'the wrapper must exist to be read');
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

      expectOnGrid(chainOrigins(tester, ratio).first.device, at: 'ratio $ratio');
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
    // ⚠️DEBT, owed to the UI-scale PR: no `createViewConfigurationFor`
    // override exists yet, so the root matrix still scales by the raw 1.5
    // while this asserts against 1.35. Both this and the wrapper divide by
    // the same 1.35, so the assertion is self-consistent — but the grid it
    // names is not yet the compositor's. `device_grid_audit.dart` records
    // the same debt; the override and these assertions have to be
    // reconciled in the PR that ships the scale.
    const monitor = 1.5;
    const scale = 0.9;
    tester.view.devicePixelRatio = monitor;
    tester.view.physicalSize = const Size(1600 * monitor, 1000 * monitor);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(shell(uiScale: scale));
    await tester.pumpAndSettle();

    expectOnGrid(
      chainOrigins(tester, monitor * scale).first.device,
      at: 'product 1.35',
    );
  });

  testWidgets(
    'the RAIL-DOCKED canvas chain is still off — owned by the workspace and '
    'rail PRs',
    (tester) async {
      // 🚨An honest record, not an aspiration. That wrapper's chain runs
      // through the panel strip and the rail column, which this PR did not
      // touch — `EditorPanelTabs.stripHeight = 30` and `_railGroupGap = 8`
      // are what hold it off. Pinning the state lets the round watch it
      // close instead of assuming it did.
      //
      // ⛔When the workspace and rail PRs land, this test FAILS. That is
      // the signal to move this boundary into the on-grid group above, not
      // to delete the case.
      const ratio = 1.35;
      tester.view.devicePixelRatio = ratio;
      tester.view.physicalSize = const Size(1600 * ratio, 1000 * ratio);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(shell());
      await tester.pumpAndSettle();

      final origins = chainOrigins(tester, ratio);
      expect(origins.length, greaterThanOrEqualTo(2));
      final railDocked = origins[1].device;
      expect(
        offGridBy(railDocked.dx) + offGridBy(railDocked.dy),
        greaterThan(1e-3),
        reason:
            'the rail-docked canvas is on the grid at $railDocked — if the '
            'workspace/rail quantization landed, move it into the on-grid '
            'group above rather than deleting this case',
      );
    },
  );

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
      });
    }
  });
}
