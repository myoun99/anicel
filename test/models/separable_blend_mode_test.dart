import 'dart:ui' show BlendMode;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/non_separable_blend_mode.dart';
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
/// the CPU, and a layer composes it over its backdrop (brush-fidelity).
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

/// The same for the six that mix the three channels — shared the same way
/// since brush-fidelity-Q4 gave the layer list the six the brush had.
const _expectedMixers = <NonSeparableBlendMode, (BlendMode?, String)>{
  NonSeparableBlendMode.darkerColor: (null, 'Darker Color'),
  NonSeparableBlendMode.lighterColor: (null, 'Lighter Color'),
  NonSeparableBlendMode.hue: (BlendMode.hue, 'Hue'),
  NonSeparableBlendMode.saturation: (BlendMode.saturation, 'Saturation'),
  NonSeparableBlendMode.chroma: (BlendMode.color, 'Color'),
  NonSeparableBlendMode.luminosity: (BlendMode.luminosity, 'Luminosity'),
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

  group('NonSeparableBlendMode', () {
    test('carries the expected blend and English label', () {
      expect(
        _expectedMixers.keys.toSet(),
        NonSeparableBlendMode.values.toSet(),
      );
      _expectedMixers.forEach((mode, want) {
        final (blend, en) = want;
        expect(mode.blendMode, blend, reason: '${mode.name} blend');
        expect(mode.label, en, reason: '${mode.name} en');
      });
    });

    test('forName resolves each value and is null for anything else', () {
      for (final mode in NonSeparableBlendMode.values) {
        expect(NonSeparableBlendMode.forName(mode.name), mode);
      }
      expect(NonSeparableBlendMode.forName('color'), isNull);
      expect(NonSeparableBlendMode.forName('darken'), isNull);
      expect(NonSeparableBlendMode.forName('nonsense'), isNull);
    });
  });

  group('BrushBlendMode delegates the shared data', () {
    // ↩️Each also pinned its GPU preview blend (`previewBlendMode`), until
    // brush-fidelity-Q9 left no brush blend drawn on the GPU.
    const heads = {
      BrushBlendMode.color: 'Normal',
      BrushBlendMode.behind: 'Behind',
      BrushBlendMode.erase: 'Erase',
    };

    test('heads keep their own labels and are in neither table', () {
      heads.forEach((mode, en) {
        expect(mode.separable, isNull, reason: '${mode.name} head');
        expect(mode.nonSeparable, isNull, reason: '${mode.name} head');
        expect(mode.label, en);
      });
    });

    test('every other value resolves through exactly one table', () {
      for (final mode in BrushBlendMode.values) {
        if (heads.containsKey(mode)) continue;
        final separable = mode.separable;
        final mixer = mode.nonSeparable;
        expect(
          (separable == null) != (mixer == null),
          isTrue,
          reason: '${mode.name} is in one table',
        );
        expect(mode.label, separable?.label ?? mixer!.label);
      }
      // ...and every mode of both tables is the brush's.
      for (final name in [
        for (final mode in SeparableBlendMode.values) mode.name,
        for (final mode in NonSeparableBlendMode.values) mode.name,
      ]) {
        expect(
          BrushBlendMode.named(name),
          isNotNull,
          reason: '$name is in the brush list',
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

  group('LayerBlendMode delegates the shared data', () {
    const heads = {
      LayerBlendMode.passThrough: 'Pass Through',
      LayerBlendMode.normal: 'Normal',
    };

    test('heads keep their own labels and are in neither table', () {
      heads.forEach((mode, en) {
        expect(mode.separable, isNull, reason: '${mode.name} head');
        expect(mode.nonSeparable, isNull, reason: '${mode.name} head');
        expect(mode.paintBlendMode, BlendMode.srcOver);
        expect(mode.label, en);
      });
    });

    test('every other value resolves through exactly one table, and the '
        'GPU blend is the table\'s', () {
      for (final mode in LayerBlendMode.values) {
        if (heads.containsKey(mode)) continue;
        final separable = mode.separable;
        final mixer = mode.nonSeparable;
        expect(
          (separable == null) != (mixer == null),
          isTrue,
          reason: '${mode.name} is in one table',
        );
        expect(mode.gpuBlendMode, separable?.blendMode ?? mixer!.blendMode);
        expect(mode.label, separable?.label ?? mixer!.label);
      }
    });

    // 🗣️brush-fidelity-Q4 (유저 2026-10-17 「레이어까지 같이」): a layer takes
    // every mode the brush does — in the brush list's order, Clip Studio's
    // (brush-fidelity-Q5: 「일반 · 배경 · 지우기는 맨 앞 그대로, 나머지는
    // 클튜 순서로」). ↩️Until then this pinned the opposite: that the layer
    // list held only the modes with a GPU blend.
    test('takes every mode the brush does, in the brush list\'s order', () {
      expect(
        [
          for (final mode in LayerBlendMode.values)
            if (!heads.containsKey(mode)) mode.name,
        ],
        [
          for (final mode in BrushBlendMode.values)
            if (mode.separable != null || mode.nonSeparable != null)
              mode.name,
        ],
      );
    });

    test('a mode the GPU lacks is never painted in a blend', () {
      for (final mode in LayerBlendMode.values) {
        if (mode.needsItsBackdrop) {
          expect(
            () => mode.paintBlendMode,
            throwsStateError,
            reason: '${mode.name} is composed over its backdrop',
          );
        } else {
          expect(mode.paintBlendMode, mode.gpuBlendMode, reason: mode.name);
        }
      }
    });
  });
}
