import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/onion_skin_settings.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tools_panel.dart';
import 'package:anicel/src/ui/panels/onion_skin_panel.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';

/// The bake's SECOND invariant, enforced instead of documented.
///
/// Baking captures `Offset.zero & size` and blits it back, so it is a
/// hard clip. Painting through is not — `RenderProxyBox` clips nothing.
/// A child that draws past its own bounds therefore looks DIFFERENT
/// baked than unbaked — and because a surface stands itself down as soon
/// as it starts changing every frame, that difference would appear and
/// disappear while someone works. They would report it as a glitch, and
/// they would be right.
///
/// The audit that found this suggested asserting that a child does not
/// overflow. There is no honest way to ask a render object that. What
/// there is, is the oracle the sheet's culling already uses: render it
/// BOTH WAYS and compare the bytes.
const _captureKey = ValueKey<String>('parity-capture');

Future<ByteData> _bytes(WidgetTester tester, Widget child, {
  required bool bake,
}) async {
  StaticRaster.globallyEnabled.value = bake;
  // Two things this geometry has to get right, both learned the hard way:
  //
  //  * The capture is BIGGER than the baked box, with margin all round.
  //    Capturing exactly the baked box would put any overflow outside
  //    the picture too, and the positive control below would pass while
  //    proving nothing.
  //  * The baked box sits at an INTEGER offset. The bake is a 1:1 blit,
  //    so at a fractional position the two renderings differ by
  //    resampling rather than by overflow — a real difference, but a
  //    different one, and mixing them makes the result unreadable.
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: _captureKey,
          child: SizedBox(
            width: 400,
            height: 480,
            child: Stack(
              // Without this the Stack clips the very overflow the
              // positive control exists to produce, and the control
              // passes while proving nothing.
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned(
                  left: 80,
                  top: 80,
                  width: 240,
                  height: 320,
                  child: StaticRaster(debugLabel: 'parity', child: child),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  late ByteData data;
  await tester.runAsync(() async {
    final image = await boundary.toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    data = (await image.toByteData())!;
    image.dispose();
  });
  return data;
}

/// The WORST channel difference between two renderings, 0..255.
///
/// Counting differing bytes was the first thing tried and it is the
/// wrong question: rendering a subtree into its own surface and
/// compositing it antialiases edges against transparent and then blends,
/// where painting directly blends once. The two are equivalent in
/// arithmetic and not in rounding, so a panel full of icons differs in a
/// few hundred bytes by ±1 and looks identical.
///
/// What a person would actually see — a cropped shadow, a clipped label
/// — moves a channel by a lot. So the magnitude is the signal and the
/// count is noise.
int _worstChannelDelta(ByteData a, ByteData b) {
  final x = a.buffer.asUint8List();
  final y = b.buffer.asUint8List();
  if (x.length != y.length) {
    return 255;
  }
  var worst = 0;
  for (var i = 0; i < x.length; i += 1) {
    final delta = (x[i] - y[i]).abs();
    if (delta > worst) {
      worst = delta;
    }
  }
  return worst;
}

/// WHERE the two renderings disagree, in capture pixels.
///
/// "They differ" is not a bug report. The baked box sits at (80,80) with
/// 80px of margin all round, so a difference band hugging that box's
/// edge is overflow, and one in the middle of it is something else
/// entirely — and knowing which is the difference between a five-minute
/// fix and an afternoon.
String _differenceBounds(ByteData a, ByteData b, int width, int threshold) {
  final x = a.buffer.asUint8List();
  final y = b.buffer.asUint8List();
  var left = 1 << 30, top = 1 << 30, right = -1, bottom = -1, count = 0;
  for (var i = 0; i < x.length; i += 4) {
    var differs = false;
    for (var channel = 0; channel < 4; channel += 1) {
      if ((x[i + channel] - y[i + channel]).abs() > threshold) {
        differs = true;
        break;
      }
    }
    if (!differs) {
      continue;
    }
    final pixel = i ~/ 4;
    final px = pixel % width;
    final py = pixel ~/ width;
    if (px < left) left = px;
    if (px > right) right = px;
    if (py < top) top = py;
    if (py > bottom) bottom = py;
    count += 1;
  }
  return right < 0
      ? 'none'
      : '$count px in ($left,$top)..($right,$bottom)';
}

/// A handful of the disagreeing pixels, with both values.
///
/// "They differ by 255" says nothing about WHY. Alpha-only differences
/// are geometry (something was clipped away); differences where R, G and
/// B move by different amounts are subpixel text antialiasing, which a
/// layer cannot reproduce because it has no opaque destination to blend
/// against. Those are completely different problems and the numbers say
/// which.
String _differenceSamples(ByteData a, ByteData b, int width, int threshold) {
  final x = a.buffer.asUint8List();
  final y = b.buffer.asUint8List();
  final samples = <String>[];
  for (var i = 0; i < x.length && samples.length < 6; i += 4) {
    var differs = false;
    for (var channel = 0; channel < 4; channel += 1) {
      if ((x[i + channel] - y[i + channel]).abs() > threshold) {
        differs = true;
        break;
      }
    }
    if (!differs) {
      continue;
    }
    final pixel = i ~/ 4;
    final baked = '${x[i]},${x[i + 1]},${x[i + 2]},${x[i + 3]}';
    final through = '${y[i]},${y[i + 1]},${y[i + 2]},${y[i + 3]}';
    samples.add('(${pixel % width},${pixel ~/ width}) $baked vs $through');
  }
  return samples.join('  |  ');
}

/// Rounding from the extra compositing step, and nothing more.
const int _roundingTolerance = 4;

Future<void> _expectParity(
  WidgetTester tester,
  Widget child, {
  required String what,
}) async {
  final baked = await _bytes(tester, child, bake: true);
  final through = await _bytes(tester, child, bake: false);
  final captureWidth = (400 * tester.view.devicePixelRatio).round();
  expect(
    _worstChannelDelta(baked, through),
    lessThanOrEqualTo(_roundingTolerance),
    reason:
        '$what looks different baked than painted through.\n'
        'Differs at: ${_differenceBounds(baked, through, captureWidth, _roundingTolerance)}\n'
        'Samples (baked vs through): '
        '${_differenceSamples(baked, through, captureWidth, _roundingTolerance)}\n'
        'The baked box is (80,80)..(320,400) in logical pixels, times the '
        'device ratio. A band hugging that rectangle is the child drawing '
        'outside its own box: the bake clips it, painting through does '
        'not, so it appears and disappears as the surface stands down and '
        'comes back.',
  );
}

void main() {
  tearDown(() => StaticRaster.globallyEnabled.value = true);

  /// A child that paints far outside its own box.
  ///
  /// ⚠️A childless `ColoredBox` takes `constraints.smallest` and draws
  /// NOTHING — the first version of this control was an empty comparison
  /// that passed while proving nothing. This app has been bitten by that
  /// exact widget three times now.
  const overflowing = OverflowBox(
    maxWidth: 900,
    maxHeight: 900,
    child: SizedBox(
      width: 900,
      height: 900,
      child: ColoredBox(color: Color(0xFFFF0000)),
    ),
  );

  testWidgets('the comparison can see a difference at all', (tester) async {
    // The positive control has to compare two things that genuinely
    // differ, and since the whole point of the fix is that baking never
    // changes a pixel, the control cannot BE the bake. So: two different
    // children, same harness.
    final red = await _bytes(tester, overflowing, bake: true);
    final blue = await _bytes(
      tester,
      const ColoredBox(color: Color(0xFF0000FF)),
      bake: true,
    );
    expect(
      _worstChannelDelta(red, blue),
      greaterThan(_roundingTolerance),
      reason: 'if this passes, every parity assertion below is vacuous',
    );
  });

  testWidgets('overflow is clipped the SAME in both modes', (tester) async {
    // The second invariant, dissolved rather than documented. Baking is
    // a hard clip to `size`; painting through now clips identically, so
    // a child that draws outside its box looks the same either way and
    // cannot flicker as the surface stands down and comes back.
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
      ToolsPanel(tool: CanvasTool.brush, onToolChanged: (_) {}),
      what: 'the tool column',
    );
  });

  testWidgets('the onion panel bakes to the same pixels it paints', (
    tester,
  ) async {
    // Passes today because the onion panel's bake is OFF — this is the
    // test that turned it off. A horizontal band inside the strip was
    // present painting through and fully transparent when baked, which
    // is not the overflow case (both modes clip identically now) and
    // nobody has explained it. Re-enable the bake and this goes red
    // again, which is the point of leaving the assertion here.
    await _expectParity(
      tester,
      OnionSkinPanel(
        settings: const OnionSkinSettings(),
        onChanged: (_) {},
      ),
      what: 'the onion panel',
    );
  });
}
