import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/services/brush_stroke_blend.dart';
import 'package:anicel/src/services/import/clip_import_planner.dart';
import 'package:anicel/src/services/photoshop/psd_blend_modes.dart';

/// 🔬WHAT CLIP STUDIO EXPORTS (brush-fidelity Q3 · Q6, 유저 2026-10-17: 「13개
/// + 클튜의 발광 둘」): one flat stroke over a grey ramp, exported under each
/// of its four modes (`参考/CSP_decode/1017`) and read across. `source` and
/// `ground` are the stroke's channel and the ramp's byte there, `landed` the
/// byte of the export. ±2: the stroke's own byte is read off the export too.
const _alpha = 127;

const _exported = <BrushBlendMode, List<({int source, int ground, int landed})>>{
  BrushBlendMode.add: [
    (source: 255, ground: 71, landed: 163),
    (source: 255, ground: 129, landed: 192),
    (source: 255, ground: 174, landed: 214),
    (source: 126, ground: 71, landed: 134),
    (source: 126, ground: 145, landed: 200),
    (source: 126, ground: 174, landed: 214),
    (source: 61, ground: 71, landed: 101),
  ],
  BrushBlendMode.glowAdd: [
    (source: 255, ground: 71, landed: 198),
    (source: 255, ground: 113, landed: 240),
    (source: 255, ground: 129, landed: 255),
    (source: 126, ground: 145, landed: 207),
    (source: 126, ground: 174, landed: 236),
    (source: 61, ground: 71, landed: 101),
  ],
  BrushBlendMode.colorDodge: [
    (source: 255, ground: 71, landed: 163),
    (source: 255, ground: 174, landed: 214),
    (source: 126, ground: 71, landed: 106),
    (source: 126, ground: 129, landed: 192),
    (source: 126, ground: 174, landed: 214),
    (source: 61, ground: 71, landed: 82),
  ],
  BrushBlendMode.glowDodge: [
    (source: 255, ground: 71, landed: 141),
    (source: 255, ground: 113, landed: 225),
    (source: 255, ground: 129, landed: 255),
    (source: 126, ground: 71, landed: 95),
    (source: 126, ground: 129, landed: 171),
    (source: 126, ground: 174, landed: 229),
    (source: 61, ground: 174, landed: 197),
  ],
};

/// [source] at [alpha] blended onto [ground] at [groundAlpha], grey.
List<int> _land(
  BrushBlendMode mode, {
  required int source,
  required int alpha,
  required int ground,
  int groundAlpha = 255,
}) => blendStrokeRegionPixels(
  dst: Uint8List.fromList([ground, ground, ground, groundAlpha]),
  src: Uint8List.fromList([source, source, source, alpha]),
  mode: mode,
  pixelCount: 1,
);

void main() {
  for (final MapEntry(key: mode, value: rows) in _exported.entries) {
    test('${mode.name} lands what Clip Studio exports', () {
      for (final (:source, :ground, :landed) in rows) {
        expect(
          _land(mode, source: source, alpha: _alpha, ground: ground)[0],
          closeTo(landed, 2),
          reason: '$source over $ground',
        );
      }
    });
  }

  test('at full opacity a 発光 is the mode it glows — only a thin source tells '
      'them apart', () {
    for (final (:glow, :plain) in const [
      (glow: BrushBlendMode.glowAdd, plain: BrushBlendMode.add),
      (glow: BrushBlendMode.glowDodge, plain: BrushBlendMode.colorDodge),
    ]) {
      for (final ground in [0, 71, 129, 255]) {
        expect(
          _land(glow, source: 126, alpha: 255, ground: ground),
          _land(plain, source: 126, alpha: 255, ground: ground),
        );
      }
    }
  });

  group('a ground that is not opaque (`csp-format`, measured in Clip Studio)', () {
    for (final mode in [BrushBlendMode.glowAdd, BrushBlendMode.glowDodge]) {
      test('${mode.name}: the source alone where the ground is empty', () {
        expect(
          _land(mode, source: 200, alpha: 100, ground: 0, groundAlpha: 0),
          [200, 200, 200, 100],
        );
      });

      test('${mode.name}: alpha lays over the ground as every mode\'s, not '
          'added up', () {
        expect(
          _land(mode, source: 200, alpha: 128, ground: 100, groundAlpha: 128)[3],
          closeTo(255 * (0.502 + 0.502 * 0.498), 1),
        );
      });
    }

    test('half a ground takes half of what the glow makes of it', () {
      const source = 255;
      const alpha = 128;
      const ground = 51;
      const as_ = alpha / 255;
      const ad = 128 / 255;
      const ao = as_ + ad * (1 - as_);
      final glowed = (ground / 255 + as_).clamp(0.0, 1.0);
      expect(
        _land(
          BrushBlendMode.glowAdd,
          source: source,
          alpha: alpha,
          ground: ground,
          groundAlpha: 128,
        )[0],
        closeTo(255 * (as_ * (1 - ad) + ad * glowed) / ao, 1),
      );
    });
  });

  test('a .clip layer in a 発光 arrives in it, and in every mode the list '
      'has: no mode is left without its number', () {
    expect(clipBlendModes[10], LayerBlendMode.glowDodge);
    expect(clipBlendModes[12], LayerBlendMode.glowAdd);
    expect(clipBlendModes.values.toSet(), LayerBlendMode.values.toSet());
  });

  test('Photoshop has neither: each goes as the mode it glows', () {
    expect(psdBlendKeyOf(LayerBlendMode.glowDodge), 'div ');
    expect(psdBlendKeyOf(LayerBlendMode.glowAdd), 'lddg');
    expect(
      psdBlendModes.values,
      isNot(contains(LayerBlendMode.glowAdd)),
      reason: 'a PSD\'s lddg opens as add',
    );
  });
}
