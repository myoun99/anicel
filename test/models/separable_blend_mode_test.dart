import 'dart:ui' show BlendMode;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/separable_blend_mode.dart';

/// The single source of truth this test pins: each separable mode's GPU blend,
/// English label, and Japanese label. BrushBlendMode and LayerBlendMode both
/// resolve their separable cases through SeparableBlendMode, so these values
/// must reach both — and a value renamed out of the name-based [forName] link
/// (which would resolve to null and throw at runtime) fails here first.
const _expected = <SeparableBlendMode, (BlendMode, String, String)>{
  SeparableBlendMode.darken: (BlendMode.darken, 'Darken', '比較（暗）'),
  SeparableBlendMode.multiply: (BlendMode.multiply, 'Multiply', '乗算'),
  SeparableBlendMode.colorBurn: (BlendMode.colorBurn, 'Color Burn', '焼き込みカラー'),
  SeparableBlendMode.lighten: (BlendMode.lighten, 'Lighten', '比較（明）'),
  SeparableBlendMode.screen: (BlendMode.screen, 'Screen', 'スクリーン'),
  SeparableBlendMode.colorDodge: (
    BlendMode.colorDodge,
    'Color Dodge',
    '覆い焼きカラー',
  ),
  SeparableBlendMode.add: (BlendMode.plus, 'Add', '加算'),
  SeparableBlendMode.overlay: (BlendMode.overlay, 'Overlay', 'オーバーレイ'),
  SeparableBlendMode.softLight: (BlendMode.softLight, 'Soft Light', 'ソフトライト'),
  SeparableBlendMode.hardLight: (BlendMode.hardLight, 'Hard Light', 'ハードライト'),
  SeparableBlendMode.difference: (
    BlendMode.difference,
    'Difference',
    '差の絶対値',
  ),
  SeparableBlendMode.exclusion: (BlendMode.exclusion, 'Exclusion', '除外'),
};

void main() {
  group('SeparableBlendMode', () {
    test('carries the expected blend, English label, and Japanese label', () {
      // Every separable mode is pinned (the map covers all values).
      expect(_expected.keys.toSet(), SeparableBlendMode.values.toSet());
      _expected.forEach((mode, want) {
        final (blend, en, ja) = want;
        expect(mode.blendMode, blend, reason: '${mode.name} blend');
        expect(mode.label, en, reason: '${mode.name} en');
        expect(mode.labelFor(AppLanguage.ja), ja, reason: '${mode.name} ja');
        // Non-ja languages keep the shared English vocabulary.
        expect(mode.labelFor(AppLanguage.en), en);
        expect(mode.labelFor(AppLanguage.ko), en);
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
      BrushBlendMode.color: (BlendMode.srcOver, 'Color', '通常'),
      BrushBlendMode.behind: (BlendMode.dstOver, 'Behind', '背面'),
      BrushBlendMode.erase: (BlendMode.dstOut, 'Erase', '消去'),
    };

    test('heads keep their own blend/labels and are not separable', () {
      heads.forEach((mode, want) {
        final (blend, en, ja) = want;
        expect(mode.separable, isNull, reason: '${mode.name} head');
        expect(mode.isSeparable, isFalse);
        expect(mode.previewBlendMode, blend);
        expect(mode.label, en);
        expect(mode.labelFor(AppLanguage.ja), ja);
        expect(mode.labelFor(AppLanguage.en), en);
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
        expect(mode.labelFor(AppLanguage.ja), separable.labelFor(AppLanguage.ja));
      }
    });
  });

  group('LayerBlendMode delegates separable data', () {
    const heads = {
      LayerBlendMode.passThrough: ('Pass Through', '通過'),
      LayerBlendMode.normal: ('Normal', '通常'),
    };

    test('heads keep their own labels and are not separable', () {
      heads.forEach((mode, want) {
        final (en, ja) = want;
        expect(mode.separable, isNull, reason: '${mode.name} head');
        expect(mode.paintBlendMode, BlendMode.srcOver);
        expect(mode.label, en);
        expect(mode.labelFor(AppLanguage.ja), ja);
        expect(mode.labelFor(AppLanguage.en), en);
      });
    });

    test('every non-head value resolves through SeparableBlendMode', () {
      for (final mode in LayerBlendMode.values) {
        if (heads.containsKey(mode)) continue;
        final separable = mode.separable;
        expect(separable, isNotNull, reason: '${mode.name} must be separable');
        expect(mode.paintBlendMode, separable!.blendMode);
        expect(mode.label, separable.label);
        expect(mode.labelFor(AppLanguage.ja), separable.labelFor(AppLanguage.ja));
      }
    });
  });
}
