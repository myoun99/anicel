import 'dart:ui' show BlendMode;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/separable_blend_mode.dart';

/// The single source of truth this test pins: each separable mode's GPU blend
/// and English label. BrushBlendMode and LayerBlendMode both resolve their
/// separable cases through SeparableBlendMode, so the label must reach both
/// and the blend the layer's — and a value renamed out of the name-based
/// [forName] link (which would resolve to null and throw at runtime) fails
/// here first.
///
/// ↩️This map also pinned each mode's Japanese label, and that every other
/// language kept the English (the 07-22 rule: ja localized first). 유저
/// 2026-09-15 (blend-mode-names-language-Q1: 「블렌드 모드도 모든 언어로
/// 번역」) reversed the rule: every language is keyed by `name` in the string
/// tables, and `model_vocabulary_speaks_every_language_test` pins the ja
/// words that stood here, unchanged.
///
/// A null blend is a mode the GPU has none for — the brush composites it on
/// the CPU (brush-fidelity).
const _expected = <SeparableBlendMode, (BlendMode?, String)>{
  SeparableBlendMode.darken: (BlendMode.darken, 'Darken'),
  SeparableBlendMode.multiply: (BlendMode.multiply, 'Multiply'),
  SeparableBlendMode.colorBurn: (BlendMode.colorBurn, 'Color Burn'),
  SeparableBlendMode.linearBurn: (null, 'Linear Burn'),
  SeparableBlendMode.subtract: (null, 'Subtract'),
  SeparableBlendMode.lighten: (BlendMode.lighten, 'Lighten'),
  SeparableBlendMode.screen: (BlendMode.screen, 'Screen'),
  SeparableBlendMode.colorDodge: (BlendMode.colorDodge, 'Color Dodge'),
  SeparableBlendMode.add: (BlendMode.plus, 'Add'),
  SeparableBlendMode.overlay: (BlendMode.overlay, 'Overlay'),
  SeparableBlendMode.softLight: (BlendMode.softLight, 'Soft Light'),
  SeparableBlendMode.hardLight: (BlendMode.hardLight, 'Hard Light'),
  SeparableBlendMode.difference: (BlendMode.difference, 'Difference'),
  SeparableBlendMode.vividLight: (null, 'Vivid Light'),
  SeparableBlendMode.linearLight: (null, 'Linear Light'),
  SeparableBlendMode.pinLight: (null, 'Pin Light'),
  SeparableBlendMode.hardMix: (null, 'Hard Mix'),
  SeparableBlendMode.exclusion: (BlendMode.exclusion, 'Exclusion'),
  SeparableBlendMode.divide: (null, 'Divide'),
};

void main() {
  group('SeparableBlendMode', () {
    test('carries the expected blend and English label', () {
      // Every separable mode is pinned (the map covers all values).
      expect(_expected.keys.toSet(), SeparableBlendMode.values.toSet());
      _expected.forEach((mode, want) {
        final (blend, en) = want;
        expect(mode.blendMode, blend, reason: '${mode.name} blend');
        expect(mode.label, en, reason: '${mode.name} en');
      });
    });

    test('forName resolves each value and is null for anything else', () {
      for (final mode in SeparableBlendMode.values) {
        expect(SeparableBlendMode.forName(mode.name), mode);
      }
      expect(SeparableBlendMode.forName('color'), isNull);
      expect(SeparableBlendMode.forName('passThrough'), isNull);
      expect(SeparableBlendMode.forName('hue'), isNull);
      expect(SeparableBlendMode.forName('nonsense'), isNull);
    });
  });

  group('BrushBlendMode delegates separable data', () {
    // ↩️Each also pinned its GPU preview blend (`previewBlendMode`), until
    // brush-fidelity-Q9 left no brush blend drawn on the GPU.
    const heads = {
      BrushBlendMode.color: 'Normal',
      BrushBlendMode.behind: 'Behind',
      BrushBlendMode.erase: 'Erase',
    };
    // The six that mix the three channels — the brush's own.
    const mixers = {
      BrushBlendMode.darkerColor: 'Darker Color',
      BrushBlendMode.lighterColor: 'Lighter Color',
      BrushBlendMode.hue: 'Hue',
      BrushBlendMode.saturation: 'Saturation',
      BrushBlendMode.chroma: 'Color',
      BrushBlendMode.luminosity: 'Luminosity',
    };

    test('heads keep their own labels and are not separable', () {
      heads.forEach((mode, en) {
        expect(mode.separable, isNull, reason: '${mode.name} head');
        expect(mode.label, en);
      });
    });

    test('the six that mix the channels keep their own labels', () {
      mixers.forEach((mode, en) {
        expect(mode.separable, isNull, reason: '${mode.name} mixes');
        expect(mode.label, en, reason: '${mode.name} en');
      });
    });

    test('every other value resolves through SeparableBlendMode', () {
      for (final mode in BrushBlendMode.values) {
        if (heads.containsKey(mode) || mixers.containsKey(mode)) continue;
        final separable = mode.separable;
        expect(separable, isNotNull, reason: '${mode.name} must be separable');
        expect(mode.label, separable!.label);
      }
      // ...and every separable mode is the brush's.
      for (final separable in SeparableBlendMode.values) {
        expect(
          BrushBlendMode.named(separable.name),
          isNotNull,
          reason: '${separable.name} is in the brush list',
        );
      }
    });

    test('everything but plain colour and the eraser blends the whole '
        'stroke', () {
      for (final mode in BrushBlendMode.values) {
        expect(
          mode.blendsTheWholeStroke,
          mode != BrushBlendMode.color && mode != BrushBlendMode.erase,
          reason: mode.name,
        );
      }
    });
  });

  group('LayerBlendMode delegates separable data', () {
    const heads = {
      LayerBlendMode.passThrough: 'Pass Through',
      LayerBlendMode.normal: 'Normal',
    };

    test('heads keep their own labels and are not separable', () {
      heads.forEach((mode, en) {
        expect(mode.separable, isNull, reason: '${mode.name} head');
        expect(mode.paintBlendMode, BlendMode.srcOver);
        expect(mode.label, en);
      });
    });

    test('every non-head value resolves through SeparableBlendMode', () {
      for (final mode in LayerBlendMode.values) {
        if (heads.containsKey(mode)) continue;
        final separable = mode.separable;
        expect(separable, isNotNull, reason: '${mode.name} must be separable');
        expect(mode.paintBlendMode, separable!.blendMode);
        expect(mode.label, separable.label);
      }
    });

    // 🚨A layer composites on the GPU on every route (playback, canvas,
    // export), so a mode the GPU has no blend for cannot be a layer's —
    // the seven are the brush's alone (brush-fidelity-Q4).
    test('lists exactly the separable modes the GPU has a blend for', () {
      final layerSeparables = {
        for (final mode in LayerBlendMode.values)
          if (mode.separable != null) mode.separable!,
      };
      expect(layerSeparables, {
        for (final mode in SeparableBlendMode.values)
          if (mode.blendMode != null) mode,
      });
    });
  });
}
