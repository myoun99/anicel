import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/onion_skin_settings.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart';
import 'package:anicel/src/ui/panels/onion_skin_panel.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';

import '../../helpers/raster_parity.dart';

/// Baking must never change a pixel — rendered BOTH WAYS and compared.
///
/// The bake's invariants are enforced here rather than documented,
/// because every one of them fails invisibly. A surface stands itself
/// down as soon as it starts changing every frame, so any difference
/// between baked and unbaked appears and disappears while someone works.
/// They would report it as a glitch, and they would be right.
///
/// ## 🚨What this file got wrong for a whole round, and the rule that
/// came out of it
///
/// It rendered at device ratio 3, into a box of whole logical size, at a
/// whole logical offset — and wrote down that the whole offset was
/// deliberate, "so the two renderings differ by resampling rather than by
/// overflow". That reasoning is sound and the conclusion was backwards:
/// resampling was not a different question to be excluded, it was THE
/// defect, and excluding it is why the defect survived.
///
/// The bake is a copy only when the surface's device-space rectangle is
/// whole pixels. Off the grid, `FilterQuality.none` snapped it. Measured
/// on the onion panel, before [RenderStaticRaster] started aligning its
/// captures:
///
/// | condition                            | worst channel | pixels wrong |
/// |--------------------------------------|---------------|--------------|
/// | ratio 1.25 (Windows at 125%)         | 64            | 222          |
/// | ratio 1.5  (Windows at 150%)         | 127           | 268 = a row  |
/// | ratio 1.75 (Windows at 175%)         | 63            | 309          |
/// | ratio 2.5                            | 127           | 430          |
/// | ratio 2, panel a quarter pixel right | 128           | 1483, 12 cols|
/// | height 116.5, 117, 118.5 at ratio 1.5| 47–64         | 336 = a row  |
///
/// At ratio 1 and 2, on whole bounds, at a whole offset: zero. Which is
/// the one configuration this file tested.
///
/// ⇒ **A test for a geometric property must sweep the geometry.** The
/// cases below walk the device ratios Windows actually ships, sub-pixel
/// offsets in eighths, and sizes that are not a whole number of device
/// pixels.
Future<ByteData> _bytes(
  WidgetTester tester,
  Widget child, {
  required bool bake,
  required double left,
  required double width,
  required double height,
}) {
  StaticRaster.globallyEnabled.value = bake;
  return surfaceBytes(
    tester,
    StaticRaster(debugLabel: 'parity', child: child),
    left: left,
    width: width,
    height: height,
    settle: tester.pumpAndSettle,
  );
}

Future<void> _expectParity(
  WidgetTester tester,
  Widget child, {
  required String what,
  double left = 20,
  double width = 240,
  double height = 240,
}) async {
  final baked = await _bytes(
    tester,
    child,
    bake: true,
    left: left,
    width: width,
    height: height,
  );
  final through = await _bytes(
    tester,
    child,
    bake: false,
    left: left,
    width: width,
    height: height,
  );
  final ratio = tester.view.devicePixelRatio;
  final result = compareRasters(
    baked,
    through,
    width: (parityCaptureWidth * ratio).round(),
    tolerance: parityRoundingTolerance,
  );
  expect(
    result.over,
    lessThanOrEqualTo(parityTieBudget),
    reason:
        '$what looks different baked than painted through.\n'
        'ratio $ratio, box ${width}x$height at left $left — device '
        '${width * ratio}x${height * ratio} at ${left * ratio}\n'
        '${result.over} pixels beyond the rounding floor, worst channel '
        '${result.worst}, in ${result.where}\n'
        'Samples (baked vs painted through): ${result.samples}\n'
        'A whole row or column means the bake is being RESAMPLED rather '
        'than copied: its device rectangle is not whole pixels and '
        'RenderStaticRaster failed to align the capture. A band hugging '
        'the box means the child paints outside its own bounds. Scattered '
        'pixels on feature edges are ties and are what the budget is for.',
  );
}

void main() {
  tearDown(() {
    StaticRaster.globallyEnabled.value = true;
  });

  /// A child that paints far outside its own box.
  ///
  /// ⚠️A childless `ColoredBox` takes `constraints.smallest` and draws
  /// NOTHING — the first version of this control was an empty comparison
  /// that passed while proving nothing. This app has been bitten by that
  /// exact widget five times now.
  const overflowing = OverflowBox(
    maxWidth: 900,
    maxHeight: 900,
    child: SizedBox(
      width: 900,
      height: 900,
      child: ColoredBox(color: Color(0xFFFF0000)),
    ),
  );

  Widget onionPanel() =>
      OnionSkinPanel(
        settings: const OnionSkinSettings(),
        currentColorOf: () => 0xFF000000,
        onChanged: (_) {},
      );

  testWidgets('the comparison can see a difference at all', (tester) async {
    // The positive control has to compare two things that genuinely
    // differ, and since the whole point of the fix is that baking never
    // changes a pixel, the control cannot BE the bake. So: two different
    // children, same harness.
    final red = await _bytes(
      tester,
      overflowing,
      bake: true,
      left: 20,
      width: 240,
      height: 240,
    );
    final blue = await _bytes(
      tester,
      const ColoredBox(color: Color(0xFF0000FF)),
      bake: true,
      left: 20,
      width: 240,
      height: 240,
    );
    final result = compareRasters(
      red,
      blue,
      width: (parityCaptureWidth * 3).round(),
      tolerance: parityRoundingTolerance,
    );
    expect(
      result.over,
      greaterThan(parityTieBudget),
      reason: 'if this passes, every parity assertion below is vacuous',
    );
  });

  testWidgets('overflow is clipped the SAME in both modes', (tester) async {
    // Baking is a hard clip to `size`; painting through clips
    // identically, so a child that draws outside its box looks the same
    // either way and cannot flicker as the surface stands down.
    await _expectParity(
      tester,
      overflowing,
      what: 'a child painting far outside its box',
    );
  });

  testWidgets('the tool column bakes to the same pixels it paints', (
    tester,
  ) async {
    await _expectParity(
      tester,
      ToolsPanel(tool: CanvasTool.brush, onPress: (_) {}),
      what: 'the tool column',
    );
  });

  testWidgets('the onion panel bakes to the same pixels it paints', (
    tester,
  ) async {
    await _expectParity(tester, onionPanel(), what: 'the onion panel');
  });

  // ─── the geometry sweeps ────────────────────────────────────────────
  //
  // Each of these fails on the unaligned bake, and none of them is
  // exotic: they are the display scalings Windows ships and the positions
  // a splitter leaves a dock in.

  testWidgets('the capture really is being aligned', (tester) async {
    // The fixture-reaches-the-defect guard. Every sweep below is vacuous
    // if the surface happens to land on the grid anyway, and "it passed"
    // would then mean nothing at all.
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetDevicePixelRatio);
    await _bytes(
      tester,
      onionPanel(),
      bake: true,
      left: 20 + 1 / 3,
      width: 240,
      height: 240,
    );
    final baked = StaticRaster.census.where((r) => r.captureCount > 0);
    expect(baked, isNotEmpty, reason: 'nothing baked, so nothing was tested');
    expect(
      baked.any((r) => r.debugGridShift != Offset.zero),
      isTrue,
      reason:
          'no baked surface sat off the device pixel grid, so the sweeps '
          'below never exercise the alignment they exist to protect',
    );
  });

  for (final ratio in <double>[1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]) {
    testWidgets('the onion panel bakes the same at device ratio $ratio', (
      tester,
    ) async {
      // 1.25, 1.5 and 1.75 are Windows at 125%, 150% and 175%. The
      // panel's own height is 117 logical pixels, which is 146.25, 175.5
      // and 204.75 device pixels — not one of them whole.
      tester.view.devicePixelRatio = ratio;
      addTearDown(tester.view.resetDevicePixelRatio);
      await _expectParity(
        tester,
        onionPanel(),
        what: 'the onion panel at device ratio $ratio',
      );
    });
  }

  testWidgets('a panel on a fractional pixel bakes the same', (tester) async {
    // A splitter does not stop on whole pixels, and at ratio 2 a panel
    // half a logical pixel across is a whole device pixel out of phase.
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    for (var eighth = 0; eighth < 8; eighth += 1) {
      await _expectParity(
        tester,
        onionPanel(),
        what: 'the onion panel at left 20 + $eighth/8',
        left: 20 + eighth / 8,
      );
    }
  });

  testWidgets('a panel of fractional device size bakes the same', (
    tester,
  ) async {
    // `toImageSync` rounds the image UP to whole pixels, so a box that is
    // not a whole number of device pixels wide has a last column with
    // nothing legitimate to sample.
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final width in <double>[240, 240 + 1 / 3, 240.5, 240.75, 241]) {
      await _expectParity(
        tester,
        onionPanel(),
        what: 'the onion panel $width wide (${width * 1.5} device pixels)',
        width: width,
      );
    }
  });
}
