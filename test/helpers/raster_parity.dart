import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The harness a panel raster proves its pixels with: a surface rendered
/// at a chosen box, compared byte for byte against itself rendered the
/// other way. `StaticRaster`'s bakes and `StillRaster`'s still images ask
/// the same question of it — does drawing this region from an image change
/// a pixel.
const _captureKey = ValueKey<String>('parity-capture');

/// Where the surface sits inside the capture. Bigger than the box, with
/// margin all round: capturing exactly the box would put any overflow
/// outside the picture too, and a positive control would pass while
/// proving nothing.
const double parityCaptureWidth = 420;
const double parityCaptureHeight = 300;

/// Renders [surface] as a [width]×[height] box at ([left], 20) inside the
/// capture, lets [settle] bring it to the state under test, and returns
/// the capture's RGBA bytes at the view's ratio.
Future<ByteData> surfaceBytes(
  WidgetTester tester,
  Widget surface, {
  required double left,
  required double width,
  required double height,
  required Future<void> Function() settle,
}) async {
  await pumpSurface(
    tester,
    surface,
    left: left,
    width: width,
    height: height,
  );
  await settle();
  return captureBytes(tester);
}

/// Mounts [surface] as a [width]×[height] box at ([left], 20) inside the
/// capture — the same tree every time, so a second call updates the first
/// one's elements rather than replacing them.
Future<void> pumpSurface(
  WidgetTester tester,
  Widget surface, {
  required double left,
  required double width,
  required double height,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: _captureKey,
          child: SizedBox(
            width: parityCaptureWidth,
            height: parityCaptureHeight,
            child: Stack(
              // Without this the Stack clips the very overflow the
              // positive control exists to produce, and the control
              // passes while proving nothing.
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned(
                  left: left,
                  top: 20,
                  width: width,
                  height: height,
                  child: surface,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// The capture's RGBA bytes as the scene has them right now.
Future<ByteData> captureBytes(WidgetTester tester) async {
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

/// How far two renderings of the capture are apart: the worst channel
/// anywhere, how many pixels move by more than [tolerance], where those
/// sit, and a few of them as they read in [a] and [b].
({int worst, int over, String where, String samples}) compareRasters(
  ByteData a,
  ByteData b, {
  required int width,
  required int tolerance,
}) {
  final x = a.buffer.asUint8List();
  final y = b.buffer.asUint8List();
  var worst = 0;
  var over = 0;
  var left = 1 << 30;
  var top = 1 << 30;
  var right = -1;
  var bottom = -1;
  final samples = <String>[];
  for (var i = 0; i < x.length; i += 4) {
    var pixel = 0;
    for (var channel = 0; channel < 4; channel += 1) {
      final delta = (x[i + channel] - y[i + channel]).abs();
      if (delta > pixel) {
        pixel = delta;
      }
    }
    if (pixel > worst) {
      worst = pixel;
    }
    if (pixel <= tolerance) {
      continue;
    }
    over += 1;
    final index = i ~/ 4;
    final px = index % width;
    final py = index ~/ width;
    if (px < left) left = px;
    if (px > right) right = px;
    if (py < top) top = py;
    if (py > bottom) bottom = py;
    if (samples.length < 4) {
      // Alpha-only differences are geometry (something was clipped
      // away); differences where R, G and B move by different amounts
      // are subpixel text antialiasing. Those are different problems and
      // the numbers say which.
      samples.add(
        '($px,$py) ${x[i]},${x[i + 1]},${x[i + 2]},${x[i + 3]} '
        'vs ${y[i]},${y[i + 1]},${y[i + 2]},${y[i + 3]}',
      );
    }
  }
  return (
    worst: worst,
    over: over,
    where: right < 0 ? 'nowhere' : '($left,$top)..($right,$bottom)',
    samples: samples.join('  |  '),
  );
}

/// What the extra compositing step is allowed to move a channel by.
///
/// Rendering a subtree into its own surface and compositing it
/// antialiases edges against transparent and then blends, where painting
/// directly blends once. The two are equivalent in arithmetic and not in
/// rounding, so a panel full of icons differs in a few hundred bytes by a
/// unit or two and looks identical.
///
/// Eight is measured, not guessed: across every ratio, offset and size
/// static_raster_parity_test.dart sweeps, the rounding floor for an
/// antialiased edge came out at 8 — and a curved antialiased clip
/// (`ClipRRect`, `ClipOval`, a `Material` with a shape) sits at the top of
/// that range, because its coverage is computed against a different
/// backdrop in a layer than on the window.
const int parityRoundingTolerance = 8;

/// How many pixels may exceed [parityRoundingTolerance] before it is a
/// defect rather than a tie.
///
/// 🚨This is the assertion that actually holds the line, and magnitude
/// alone is not.
///
/// A glyph run's position in device space is computed one way when the
/// picture is rasterised onto the window (the surface's offset is in the
/// layer transform) and another way when it is rasterised into a capture
/// (the offset is folded into the paint offset). The two agree to within
/// floating-point noise, and glyph rasterisation quantises sub-pixel
/// positions, so noise is occasionally enough to land a run in a
/// different bucket. When that happens the run's two boundary columns
/// move a long way — up to 97 of 255, measured — and nothing else does.
/// It is not reachable by aligning better: the two expressions cannot be
/// made bitwise equal.
///
/// So the shape of that difference is the tell, and it is nothing like a
/// defect's:
///
/// | | pixels beyond the floor | shape |
/// |---|---|---|
/// | a run's bucket flipping | ≤ 72 measured over 240 configurations | 2 columns, one run tall |
/// | a resampled bake (static_raster_parity_test.dart) | 222 – 1483 | whole rows, whole columns |
///
/// The budget sits between them with room on both sides. If it ever
/// starts failing on ties rather than defects, the failure message prints
/// the bounding box, and two narrow columns say so at a glance.
const int parityTieBudget = 128;
