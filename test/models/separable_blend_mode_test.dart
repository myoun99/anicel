import 'dart:ui' show BlendMode;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/separable_blend_mode.dart';

/// The single source of truth this test pins: each separable mode's GPU blend
/// and English label. BrushBlendMode and LayerBlendMode both resolve their
/// separable cases through SeparableBlendMode, so these values must reach
/// both — and a value renamed out of the name-based [forName] link (which
/// would resolve to null and throw at runtime) fails here first.
///
/// ↩️This map also pinned each mode's Japanese label, and that every other
/// language kept the English (the 07-22 rule: ja localized first). 유저
/// 2026-09-15 (blend-mode-names-language-Q1: 「블렌드 모드도 모든 언어로
/// 번역」) reversed the rule: every language is keyed by `name` in the string
/// tables, and `model_vocabulary_speaks_every_language_test` pins the ja
/// words that stood here, unchanged.
const _expected = <SeparableBlendMode, (BlendMode, String)>{
  SeparableBlendMode.darken: (BlendMode.darken, 'Darken'),
  SeparableBlendMode.multiply: (BlendMode.multiply, 'Multiply'),
  SeparableBlendMode.colorBurn: (BlendMode.colorBurn, 'Color Burn'),
  SeparableBlendMode.lighten: (BlendMode.lighten, 'Lighten'),
  SeparableBlendMode.screen: (BlendMode.screen, 'Screen'),
  SeparableBlendMode.colorDodge: (BlendMode.colorDodge, 'Color Dodge'),
  SeparableBlendMode.add: (BlendMode.plus, 'Add'),
  SeparableBlendMode.overlay: (BlendMode.overlay, 'Overlay'),
  SeparableBlendMode.softLight: (BlendMode.softLight, 'Soft Light'),
  SeparableBlendMode.hardLight: (BlendMode.hardLight, 'Hard Light'),
  SeparableBlendMode.difference: (BlendMode.difference, 'Difference'),
  SeparableBlendMode.exclusion: (BlendMode.exclusion, 'Exclusion'),
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
      expect(SeparableBlendMode.forName('nonsense'), isNull);
    });
  });

  group('BrushBlendMode delegates separable data', () {
    const heads = {
      BrushBlendMode.color: (BlendMode.srcOver, 'Color'),
      BrushBlendMode.behind: (BlendMode.dstOver, 'Behind'),
      BrushBlendMode.erase: (BlendMode.dstOut, 'Erase'),
    };

    test('heads keep their own blend/labels and are not separable', () {
      heads.forEach((mode, want) {
        final (blend, en) = want;
        expect(mode.separable, isNull, reason: '${mode.name} head');
        expect(mode.isSeparable, isFalse);
        expect(mode.previewBlendMode, blend);
        expect(mode.label, en);
      });
    });

    test('every non-head value resolves through SeparableBlendMode', () {
      for (final mode in BrushBlendMode.values) {
        if (heads.containsKey(mode)) continue;
        final separable = mode.separable;
        expect(separable, isNotNull, reason: '${mode.name} must be separable');
        expect(mode.isSeparable, isTrue);
        expect(mode.previewBlendMode, separable!.blendMode);
        expect(mode.label, separable.label);
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
  });
}
