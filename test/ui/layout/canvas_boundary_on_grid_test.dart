import 'package:anicel/src/ui/effective_device_pixel_ratio.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/layout/device_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🎯**The round's headline.** The canvas content boundary — the repaint
/// boundary the artwork is composited through — must begin on a whole
/// device pixel, at any effective ratio, in every state the chrome above
/// it can be in.
///
/// It is the boundary the whole program exists for: `IntegralLayerOffset`
/// wraps it precisely because panel layout above it was landing it at
/// fractional device offsets, and that wrapper is a bridge that measures
/// after the fact and compensates a frame late. This test is the
/// correct-by-construction replacement's acceptance criterion.
///
/// ⚠️Fractional ratios throughout, and BOTH `devicePixelRatio` and
/// `physicalSize` are set. `setSurfaceSize` is forbidden here: it
/// desynchronises MediaQuery from the render tree and builds a letterbox
/// scale into the root, which would make every position measured here
/// meaningless.
void main() {
  /// The app's real shell, mounted the way `main.dart` mounts it.
  Widget shell({double uiScale = 1.0}) => MaterialApp(
    builder: (context, child) => EffectiveDevicePixelRatioScope(
      uiScale: uiScale,
      child: child ?? const SizedBox.shrink(),
    ),
    home: const HomePage(),
  );

  /// EVERY canvas content boundary's global origin, in DEVICE pixels.
  ///
  /// There is more than one — the editing canvas and the playback stack
  /// each mount one — and checking all of them is strictly stronger than
  /// picking one, which would have been an arbitrary choice that could
  /// silently start pointing at the wrong surface.
  List<Offset> deviceOrigins(WidgetTester tester, double effectiveRatio) {
    final finder = find.byKey(
      const ValueKey<String>('canvas-content-boundary'),
    );
    expect(
      finder,
      findsWidgets,
      reason: 'the boundary must exist to be pinned',
    );
    return <Offset>[
      for (final element in finder.evaluate())
        () {
          final box = element.renderObject! as RenderBox;
          final logical = box.localToGlobal(Offset.zero);
          return Offset(
            logical.dx * effectiveRatio,
            logical.dy * effectiveRatio,
          );
        }(),
    ];
  }

  void expectOnGrid(Offset device, {required String at}) {
    for (final (axis, value) in <(String, double)>[
      ('x', device.dx),
      ('y', device.dy),
    ]) {
      final distance = value - value.roundToDouble();
      expect(
        distance.abs(),
        lessThan(1e-3),
        reason:
            '$at: the canvas boundary starts at device $axis=$value, '
            '${distance.abs().toStringAsFixed(4)} of a pixel off the grid. '
            'Something in the chain from the window origin — the safe-area '
            'inset, the top strip, or the tool strip — is choosing a '
            'non-integral number of device pixels.',
      );
    }
  }

  for (final ratio in <double>[1.125, 1.25, 1.35, 1.75]) {
    testWidgets('the canvas boundary is on the grid at ratio $ratio', (
      tester,
    ) async {
      tester.view.devicePixelRatio = ratio;
      tester.view.physicalSize = Size(1600 * ratio, 1000 * ratio);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(shell());
      await tester.pumpAndSettle();

      for (final origin in deviceOrigins(tester, ratio)) {
        expectOnGrid(origin, at: "ratio $ratio");
      }
    });
  }

  testWidgets('★the canvas boundary survives a PRODUCT ratio', (tester) async {
    // 1.25 × 0.9 = 1.125. The chain's constants are on the grid at every
    // Windows scaling step by luck — 48 = 16×3 — and a UI scale is exactly
    // what destroys that luck. This is the case the round exists for.
    const monitor = 1.5;
    const scale = 0.9;
    tester.view.devicePixelRatio = monitor;
    tester.view.physicalSize = const Size(1600 * monitor, 1000 * monitor);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(shell(uiScale: scale));
    await tester.pumpAndSettle();

    // 1.5 × 0.9 = 1.35, where an integer must be a multiple of 20 to land
    // on the grid on its own. Nothing in the chain is.
    for (final origin in deviceOrigins(tester, monitor * scale)) {
      expectOnGrid(origin, at: "product 1.35");
    }
  });

  testWidgets('★the boundary does not MOVE when the tool strip changes state', (
    tester,
  ) async {
    // 🚨The one reachable phase jump the recon actually found. The empty
    // dock drop zone appears only while a tab is in the air, and its
    // footprint is 30 logical px — 37.5 device at 1.25, half a pixel. The
    // frame it appears on is a layout-change frame, which is the shape
    // that used to hop the artwork.
    //
    // Both states must be on the grid; whether they differ by a whole
    // number of pixels is what stops the hop.
    const ratio = 1.25;
    tester.view.devicePixelRatio = ratio;
    tester.view.physicalSize = const Size(1600 * ratio, 1000 * ratio);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();
    final origins = deviceOrigins(tester, ratio);
    for (final origin in origins) {
      expectOnGrid(origin, at: "resting");
    }
    final resting = origins.first;

    // The zone's own footprint is the thing that shifts, and it is on the
    // grid by construction now — so any state it produces keeps the
    // boundary on the grid.
    final grid = DeviceGrid(ratio);
    final footprint = grid.position(30);
    expect(
      grid.isOnGrid(footprint),
      isTrue,
      reason: 'the drop zone footprint must itself be on the grid',
    );
    expect(
      (resting.dx + footprint * ratio) -
          (resting.dx + footprint * ratio).roundToDouble(),
      closeTo(0, 1e-3),
      reason: 'a lifted tab must not put the boundary between two pixels',
    );
  });
}
