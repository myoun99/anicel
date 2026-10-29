import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_preset.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_dab_interpolator.dart';
import 'package:anicel/src/services/brush_ground_color_mixing.dart';
import 'package:anicel/src/services/brush_preset_defaults.dart';

/// 🗣️EVERY MIXING BRUSH DRAGS A BAND IT CROSSES A WAY, AND LETS IT GO
/// (gouache card Q8, 2026-10-30): the built-ins were picked again for the
/// refilling mixer, by eye over red, yellow and black bands. A loaded brush
/// comes back to its own colour; a dry one — the blend group's, as Clip
/// Studio's 수채 섞기 「다른 칠해진 색을 섞을 뿐」 — thins out and lays none
/// of its own. ↩️Under the mixer that never refilled, a blue brush that
/// crossed red was red to the end of the stroke.
void main() {
  const loaded = {
    'builtin-pastel',
    'builtin-wet-watercolor',
    'builtin-dense-watercolor',
    'builtin-flat-wash',
    'builtin-gouache',
    'builtin-oil-brush',
    'builtin-palette-knife',
  };
  const dry = {
    'builtin-blender',
    'builtin-water-blend',
    'builtin-blending-stump',
  };
  const blue = 0xFF0000FF;
  const red = BrushGroundSample(rgb: 0xFF0000, coverage: 1);

  /// What [preset] lays, at its own size and spacing, along a blue stroke
  /// that crosses a red band two of its widths wide and runs on over bare
  /// canvas for twenty — the dabs past the band.
  List<BrushDab> pastTheBand(BrushPreset preset) {
    final s = preset.settings;
    final step = const BrushDabInterpolator().spacingForBrushSize(
      s.size,
      s.spacing,
    );
    final band = 2 * s.size;
    final laid = BrushGroundColorMixer(shape: s.shape).apply(
      [
        for (var x = 0.0; x <= 22 * s.size; x += step)
          BrushDab(
            center: CanvasPoint(x: x, y: 0),
            color: blue,
            size: s.size,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.round,
            pressure: 1,
            sequence: 0,
            pathStep: x == 0 ? null : step,
          ),
      ],
      sample: (x, _, _) => x < band ? red : BrushGroundSample.empty,
    );
    return [
      for (final dab in laid)
        if (dab.center.x >= band) dab,
    ];
  }

  int redOf(BrushDab dab) => (dab.color >> 16) & 0xFF;
  int alphaOf(BrushDab dab) => (dab.color >> 24) & 0xFF;

  test('the mixing brushes are these — one made since is picked here too', () {
    expect(
      {
        for (final preset in defaultBrushPresets)
          if (preset.settings.shape.picksUpGround) preset.id.value,
      },
      {...loaded, ...dry},
    );
  });

  test('🎯a loaded one carries the band off it and comes back to its own '
      'colour', () {
    for (final preset in defaultBrushPresets) {
      if (!loaded.contains(preset.id.value)) {
        continue;
      }
      expect(preset.settings.paintAmount, greaterThan(0), reason: preset.name);
      final reds = pastTheBand(preset).map(redOf).toList();
      expect(reds.first, greaterThan(48), reason: '${preset.name} carries it');
      for (var i = 1; i < reds.length; i += 1) {
        expect(
          reds[i],
          lessThanOrEqualTo(reds[i - 1]),
          reason: '${preset.name} never takes more of it on over bare canvas',
        );
      }
      expect(
        reds.last,
        lessThan(reds.first / 2),
        reason: '${preset.name} comes back: ${reds.first} → ${reds.last}',
      );
    }
  });

  test('🎯a dry one lays only what it picked up, thinning out', () {
    for (final preset in defaultBrushPresets) {
      if (!dry.contains(preset.id.value)) {
        continue;
      }
      expect(preset.settings.paintAmount, 0, reason: preset.name);
      final past = pastTheBand(preset);
      expect(
        past.map((dab) => dab.color & 0xFFFFFF),
        everyElement(0xFF0000),
        reason: '${preset.name} lays none of its own blue',
      );
      final alphas = past.map(alphaOf).toList();
      expect(alphas.first, greaterThan(48), reason: preset.name);
      expect(
        alphas.last,
        lessThan(alphas.first / 4),
        reason: '${preset.name} thins out: ${alphas.first} → ${alphas.last}',
      );
    }
  });
}
