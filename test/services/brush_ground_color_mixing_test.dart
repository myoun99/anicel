import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/brush_dab.dart';
import 'package:quick_animaker_v2/src/models/brush_shape.dart';
import 'package:quick_animaker_v2/src/models/brush_tip_shape.dart';
import 'package:quick_animaker_v2/src/models/canvas_point.dart';
import 'package:quick_animaker_v2/src/services/brush_ground_color_mixing.dart';

/// A dab carrying [color]; only colour, position and size matter here.
BrushDab dabAt(double x, int color) => BrushDab(
  center: CanvasPoint(x: x, y: 0),
  color: color,
  size: 10,
  opacity: 1.0,
  flow: 1.0,
  hardness: 1.0,
  tipShape: BrushTipShape.round,
  pressure: 1.0,
  sequence: 0,
);

BrushGroundColorSampler groundOf(int rgb, {double coverage = 1.0}) =>
    (_, _, _) => BrushGroundSample(rgb: rgb, coverage: coverage);

void main() {
  const red = 0xFFFF0000;
  const blue = 0x0000FF;
  const white = 0xFFFFFF;

  BrushShape mixing({
    double paintAmount = 1.0,
    double paintDensity = 1.0,
    double colorStretch = 0.0,
  }) => BrushShape(
    mixesGroundColor: true,
    paintAmount: paintAmount,
    paintDensity: paintDensity,
    colorStretch: colorStretch,
  );

  test('a brush that does not mix returns its dabs untouched', () {
    final mixer = BrushGroundColorMixer(shape: const BrushShape());
    final dabs = [dabAt(0, red)];

    expect(mixer.apply(dabs, sample: groundOf(blue)), same(dabs));
  });

  test('full paint amount with no stretch deposits the brush colour', () {
    // The brush is loaded with its own colour and releases all of it, so the
    // ground contributes nothing to what lands.
    final mixer = BrushGroundColorMixer(shape: mixing());

    final out = mixer.apply([dabAt(0, red)], sample: groundOf(blue));

    expect(out.single.color, red);
  });

  test('paint amount pulls the deposit toward the ground', () {
    // Half the paint released: the deposit sits midway between the ground
    // and what the brush holds.
    final mixer = BrushGroundColorMixer(shape: mixing(paintAmount: 0.5));

    final out = mixer.apply([dabAt(0, 0xFF000000)], sample: groundOf(white));

    expect(out.single.color, 0xFF808080);
  });

  test('colour stretch loads the ground into the reservoir and smears it', () {
    // A fully-stretching brush takes the ground on completely, so the NEXT
    // dab carries the previous ground even where the canvas is now bare.
    final mixer = BrushGroundColorMixer(shape: mixing(colorStretch: 1.0));

    final first = mixer.apply([dabAt(0, red)], sample: groundOf(blue));
    final second = mixer.apply(
      [dabAt(10, red)],
      sample: (_, _, _) => BrushGroundSample.empty,
    );

    expect(first.single.color, 0xFF0000FF);
    expect(second.single.color, 0xFF0000FF, reason: 'reservoir carried over');
  });

  test('bare canvas leaves the reservoir alone', () {
    // Transparent pixels have RGB 0; letting them into the average would
    // drag every stroke toward black.
    final mixer = BrushGroundColorMixer(shape: mixing(colorStretch: 1.0));

    final out = mixer.apply(
      [dabAt(0, red)],
      sample: (_, _, _) => BrushGroundSample.empty,
    );

    expect(out.single.color, red);
  });

  test('partial ground coverage scales the pickup', () {
    // Half-painted ground moves the reservoir half as far as solid ground.
    final mixer = BrushGroundColorMixer(shape: mixing(colorStretch: 1.0));

    final out = mixer.apply(
      [dabAt(0, 0xFF000000)],
      sample: groundOf(white, coverage: 0.5),
    );

    // Reservoir moved halfway to white, then all of it was deposited over a
    // ground that is itself white — paint amount 1.0 keeps the reservoir.
    expect(out.single.color, 0xFF808080);
  });

  test('paint density scales the dab alpha, not its colour', () {
    final mixer = BrushGroundColorMixer(shape: mixing(paintDensity: 0.5));

    final out = mixer.apply([dabAt(0, red)], sample: groundOf(blue));

    expect(out.single.color, 0x80FF0000);
  });

  test('the reservoir carries across dabs within one batch', () {
    // Ordering is load-bearing: the rasterizers may never reorder dabs in a
    // mixing stroke.
    final mixer = BrushGroundColorMixer(shape: mixing(colorStretch: 0.5));

    final out = mixer.apply([
      dabAt(0, 0xFF000000),
      dabAt(10, 0xFF000000),
    ], sample: groundOf(white));

    // First dab lifts halfway to white, the second lifts halfway again.
    expect((out[0].color >> 16) & 0xFF, 128);
    expect((out[1].color >> 16) & 0xFF, 192);
  });
}
