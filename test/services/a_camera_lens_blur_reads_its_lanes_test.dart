import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/core/draw_space.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/camera_lens_blur_passes.dart';
import 'package:anicel/src/services/composite_effect_paint.dart';
import 'package:anicel/src/services/shaded_passes.dart';

/// A camera lens blur's passes, as its lanes lay them: its rows summed
/// ([rowSumPasses]), then its iris gathered out of them ([IrisGatherPass]),
/// the light read where its Highlight or linear light asks. The iris's
/// shape is the GPU's (`an_iris_table_covers_its_shape_test`).
void main() {
  IrisProperties iris(
    int sides, {
    double roundness = 0,
    double aspect = 1,
    double rotation = 0,
    double fringe = 0,
  }) => (
    sides: sides,
    roundness: roundness,
    aspect: aspect,
    rotation: rotation,
    fringe: fringe,
  );

  test('a row sum covers every texel of its row up to it, in as few passes '
      'as 64 taps a pass make', () {
    for (final width in [1, 2, 63, 64, 65, 300, 4096, 4097]) {
      final passes = rowSumPasses(width);
      final taps = passes.first.taps;
      expect(passes.map((pass) => pass.taps).toSet(), {taps});
      expect(taps, inInclusiveRange(1, rowSumTapsAPass));
      if (passes.length > 1) {
        expect(math.pow(rowSumTapsAPass, passes.length - 1), lessThan(width));
      }
      // The passes run as `row_sum.frag` runs them, over a row of ones.
      var row = List<double>.filled(width, 1);
      for (final RowSumPass(:stride, :taps) in passes) {
        row = [
          for (var x = 0; x < width; x += 1)
            [
              for (var i = 0; i < taps && x - i * stride >= 0; i += 1)
                row[x - i * stride],
            ].fold(0.0, (sum, each) => sum + each),
        ];
      }
      expect(row, [for (var x = 0; x < width; x += 1) x + 1.0]);
    }
    expect(rowSumPasses(4096), hasLength(2));
    expect(rowSumPasses(4097), hasLength(3));
  });

  /// Read as stored, nothing boosted.
  const asStored = (
    gain: 0.0,
    threshold: 1.0,
    saturation: 0.0,
    linear: false,
  );

  group('the light', () {
    List<ShadedPass> passesOf(LensLight light) => cameraLensBlurPasses(
      (radius: 6, iris: iris(5), light: light),
      rasterWidth: 300,
      paper: null,
    );

    LensLight? lightOf(List<ShadedPass> passes) =>
        (passes.last as IrisGatherPass).light;

    test('is read by the first row sum, of the picture, and the iris — not '
        'by the sums of sums', () {
      const boosted = (
        gain: 40.0,
        threshold: 0.8,
        saturation: 0.5,
        linear: false,
      );
      final passes = passesOf(boosted);
      final sums = passes.whereType<RowSumPass>().toList();
      expect(sums, hasLength(2), reason: 'fixture: 300 wide is two passes');
      expect(sums.first.stride, 1);
      expect(sums.first.light, boosted);
      expect(sums.last.light, isNull);
      expect(lightOf(passes), boosted);
    });

    test('is none where it is read as stored and nothing is boosted', () {
      expect(lightOf(passesOf(asStored)), isNull);
      LensLight boost(double gain, double threshold) => (
        gain: gain,
        threshold: threshold,
        saturation: 1,
        linear: false,
      );
      expect(lightOf(passesOf(boost(0, 0))), isNull, reason: 'no gain');
      expect(
        lightOf(passesOf(boost(40, 1))),
        isNull,
        reason: 'past white, nothing is boosted',
      );
      expect(lightOf(passesOf(boost(40, 0.99))), isNotNull);
      expect(
        passesOf(asStored).whereType<RowSumPass>().map((pass) => pass.light),
        everyElement(isNull),
      );
      const linear = (
        gain: 0.0,
        threshold: 1.0,
        saturation: 0.0,
        linear: true,
      );
      expect(lightOf(passesOf(linear)), linear, reason: 'linear light alone');
    });
  });

  group('the kind', () {
    const paper = ui.Rect.fromLTWH(0, 0, 64, 64);

    /// The iris of a lens blur whose [lanes] are as they say, by id — the
    /// rest at their first values.
    IrisGatherPass irisOf(
      Map<String, double> lanes, {
      DrawSpace? space,
      Map<String, LayerId?> layers = const {},
    }) =>
        shadedPassesOf(
              ResolvedLayerEffect(
                kind: EffectKind.cameraLensBlur,
                values: [
                  for (final spec in EffectKind.cameraLensBlur.parameters)
                    lanes[spec.id] ?? spec.defaultValue,
                ],
                layers: layers,
              ),
              space ?? DrawSpace.canvas,
              paper: paper,
              rasterWidth: 64,
            ).last
            as IrisGatherPass;

    test('reads its lanes as the iris: the menu its sides, a percent its '
        'roundness, degrees its turn, the fringe as it is', () {
      final shape = EffectKind.cameraLensBlur.parameterSpec('irisShape')!;
      expect(
        [for (final choice in shape.choices) choice.id],
        [
          'triangle',
          'square',
          'pentagon',
          'hexagon',
          'heptagon',
          'octagon',
          'nonagon',
          'decagon',
        ],
      );
      for (var index = 0; index < shape.choices.length; index += 1) {
        final pass = irisOf({
          'blurRadius': 12,
          'irisShape': index.toDouble(),
          'irisRoundness': 30,
          'irisAspectRatio': 1.4,
          'irisRotation': 25,
          'irisDiffractionFringe': 200,
        });
        expect(
          pass.iris,
          iris(
            3 + index,
            roundness: 0.3,
            aspect: 1.4,
            rotation: 25 * math.pi / 180,
            fringe: 200,
          ),
          reason: shape.choices[index].id,
        );
        expect(pass.radius, 12);
        expect(pass.paper, isNull, reason: 'its edge repeats only when on');
        expect(pass.map, isNull, reason: 'no blur map named');
        expect(pass.light, isNull, reason: 'no gain, read as stored');
      }
    });

    test('reads its Highlight lanes as the light: the threshold over 255, '
        'the saturation a percent, the gain as it is', () {
      expect(
        irisOf({
          'blurRadius': 12,
          'highlightGain': 40,
          'highlightThreshold': 204,
          'highlightSaturation': 50,
          'useLinearWorkingSpace': 1,
        }).light,
        (gain: 40.0, threshold: 0.8, saturation: 0.5, linear: true),
      );
      expect(
        irisOf({
          'blurRadius': 12,
          'useLinearWorkingSpace': 1,
        }).light?.linear,
        isTrue,
        reason: 'Use Linear Working Space alone',
      );
    });

    test('reads its blur map\'s lanes where it names a row: the channel its '
        'menu says, the focal distance as it is, the inversion', () {
      final channel = EffectKind.cameraLensBlur.parameterSpec(
        'blurMapChannel',
      )!;
      for (var index = 0; index < channel.choices.length; index += 1) {
        for (final inverts in [false, true]) {
          final pass = irisOf(
            {
              'blurRadius': 12,
              'blurMapChannel': index.toDouble(),
              'blurFocalDistance': 40,
              'invertBlurMap': inverts ? 1 : 0,
            },
            layers: {'blurMapLayer': const LayerId('map')},
          );
          final map = pass.map!;
          expect(map.channel.name, channel.choices[index].id);
          expect((map.focal, map.inverts), (40, inverts));
        }
      }
      expect(
        irisOf({'blurRadius': 12, 'blurFocalDistance': 40}).map,
        isNull,
        reason: 'no row named, no map',
      );
    });

    test('its radius is canvas pixels: a raster at twice the scale spans '
        'twice the rows', () {
      const flat = {'blurRadius': 12.0};
      expect(irisOf(flat).reach, 12);
      expect(irisOf(flat, space: const DrawSpace.preScaled(2)).reach, 24);
    });

    test('begins at the Square, and at no blur', () {
      final effect = LayerEffect.defaults(
        id: const EffectId('lens'),
        kind: EffectKind.cameraLensBlur,
      );
      final shape = EffectKind.cameraLensBlur.parameterSpec('irisShape')!;
      expect(
        shape.choices[effect.parameters['irisShape']!.value.toInt()].id,
        'square',
      );
      expect(effect.parameters['blurRadius']!.value, 0);
    });

    test('begins with no highlight, read as stored', () {
      final effect = LayerEffect.defaults(
        id: const EffectId('lens'),
        kind: EffectKind.cameraLensBlur,
      );
      expect(
        {
          for (final id in [
            'highlightGain',
            'highlightThreshold',
            'highlightSaturation',
            'useLinearWorkingSpace',
          ])
            id: effect.parameters[id]!.value,
        },
        {
          'highlightGain': 0,
          'highlightThreshold': 255,
          'highlightSaturation': 0,
          'useLinearWorkingSpace': 0,
        },
      );
    });
  });
}
