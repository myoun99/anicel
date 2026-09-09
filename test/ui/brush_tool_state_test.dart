import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_rotation_mode.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';

void main() {
  group('BrushToolState', () {
    test(
      'default brush tool state maps to production brush input settings',
      () {
        const state = BrushToolState.defaults;

        expect(
          state.toInputSettings(),
          BrushEditCanvasInputSettings(size: 10, spacing: 0.25),
        );
      },
    );

    test('eraser tool maps to erase input settings', () {
      const state = BrushToolState.defaults;
      expect(state.tool, CanvasTool.brush);
      expect(state.toInputSettings().erase, isFalse);

      final eraser = state.copyWith(tool: CanvasTool.eraser);
      expect(eraser.toInputSettings().erase, isTrue);
      // Brush options ride along unchanged.
      expect(eraser.toInputSettings().size, state.size);

      // Presets never carry the tool: applying one returns to the brush.
      final reapplied = BrushToolState.fromBrushSettings(
        eraser.toBrushSettings(),
      );
      expect(reapplied.tool, CanvasTool.brush);
    });

    test('public constructor always stores a clamped size', () {
      expect(BrushToolState(size: -10).size, BrushToolState.minSize);
      expect(BrushToolState(size: 10000).size, BrushToolState.maxSize);
      expect(BrushToolState(size: double.nan).size, BrushToolState.defaultSize);
      expect(
        BrushToolState(size: double.infinity).size,
        BrushToolState.defaultSize,
      );
    });

    test('public constructor always stores clamped opacity', () {
      expect(BrushToolState(opacity: -1).opacity, 0);
      expect(BrushToolState(opacity: 2).opacity, 1);
      expect(
        BrushToolState(opacity: double.nan).opacity,
        BrushToolState.defaultOpacity,
      );
    });

    test('clamped factory keeps size opacity and spacing in safe ranges', () {
      expect(BrushToolState.clamped(size: -10).size, BrushToolState.minSize);
      expect(BrushToolState.clamped(opacity: 2).opacity, 1);
      expect(
        BrushToolState.clamped(spacing: -1).spacing,
        BrushToolState.minSpacing,
      );
      expect(
        BrushToolState.clamped(spacing: 100).spacing,
        BrushToolState.maxSpacing,
      );
    });

    test('public constructor and copyWith clamp spacing', () {
      expect(BrushToolState().spacing, BrushToolState.defaultSpacing);
      expect(BrushToolState(spacing: -1).spacing, BrushToolState.minSpacing);
      expect(BrushToolState(spacing: 100).spacing, BrushToolState.maxSpacing);
      expect(
        BrushToolState(spacing: double.nan).spacing,
        BrushToolState.defaultSpacing,
      );
      expect(
        BrushToolState(spacing: double.infinity).spacing,
        BrushToolState.defaultSpacing,
      );

      expect(
        BrushToolState.defaults.copyWith(spacing: 100).spacing,
        BrushToolState.maxSpacing,
      );
      expect(
        BrushToolState.defaults.copyWith(spacing: double.nan).spacing,
        BrushToolState.defaultSpacing,
      );
      expect(BrushToolState(spacing: 0.75).toInputSettings().spacing, 0.75);
    });

    test('color updates remain stable', () {
      const color = 0xFF123456;
      final state = BrushToolState(color: color);

      expect(state.color, color);
      expect(state.toInputSettings().color, color);
    });

    test('pressure curves default to null (no pressure response)', () {
      const state = BrushToolState.defaults;
      expect(state.sizePressureCurve, isNull);
      expect(state.opacityPressureCurve, isNull);
      expect(state.flowPressureCurve, isNull);
      expect(state.hardnessPressureCurve, isNull);
      expect(state.toInputSettings().hasPressureDynamics, isFalse);
    });

    test('pressure curves round-trip through copyWith and input settings', () {
      final state = BrushToolState.defaults.copyWith(
        sizePressureCurve: BrushPressureCurve.identity(),
        opacityPressureCurve: BrushPressureCurve.linearFrom(0.25),
      );
      expect(state.sizePressureCurve, BrushPressureCurve.identity());
      expect(state.opacityPressureCurve, BrushPressureCurve.linearFrom(0.25));

      final settings = state.toInputSettings();
      expect(settings.sizePressureCurve, BrushPressureCurve.identity());
      expect(
        settings.opacityPressureCurve,
        BrushPressureCurve.linearFrom(0.25),
      );

      // Omitted copyWith args keep the existing curves.
      expect(
        state.copyWith(size: 5).sizePressureCurve,
        BrushPressureCurve.identity(),
      );
      expect(
        state.copyWith(size: 5).opacityPressureCurve,
        BrushPressureCurve.linearFrom(0.25),
      );
    });

    test('withPressureCurve sets and CLEARS one channel', () {
      final state = BrushToolState.defaults.withPressureCurve(
        BrushPressureTarget.flow,
        BrushPressureCurve.identity(),
      );
      expect(state.flowPressureCurve, BrushPressureCurve.identity());
      expect(
        state.pressureCurveFor(BrushPressureTarget.flow),
        BrushPressureCurve.identity(),
      );

      // copyWith cannot clear (it preserves); withPressureCurve(null) can.
      final cleared = state.withPressureCurve(BrushPressureTarget.flow, null);
      expect(cleared.flowPressureCurve, isNull);
      // Other channels survive the clear.
      final both = state.withPressureCurve(
        BrushPressureTarget.size,
        BrushPressureCurve.identity(),
      );
      final sizeOnly = both.withPressureCurve(BrushPressureTarget.flow, null);
      expect(sizeOnly.sizePressureCurve, BrushPressureCurve.identity());
      expect(sizeOnly.flowPressureCurve, isNull);
    });

    test('pressure curves participate in equality', () {
      final a = BrushToolState.defaults.copyWith(
        sizePressureCurve: BrushPressureCurve.identity(),
      );
      final b = BrushToolState.defaults.copyWith(
        sizePressureCurve: BrushPressureCurve.identity(),
      );
      const c = BrushToolState.defaults;
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('the blend participates in equality (BB-3 audit fix)', () {
      // It rides in `shape` now, but the hole this pins is the same: two
      // states differing only in blend must not compare equal, or listeners
      // skip the rebuild that shows the change.
      final a = BrushToolState.defaults.copyWith(
        blendMode: BrushBlendMode.multiply,
      );
      const b = BrushToolState.defaults;
      expect(a == b, isFalse);
      expect(
        a,
        BrushToolState.defaults.copyWith(blendMode: BrushBlendMode.multiply),
      );
    });

    test('roundness and angle default to the classic full-round tip', () {
      const state = BrushToolState.defaults;
      expect(state.roundness, 1.0);
      expect(state.angleDegrees, 0.0);
      expect(state.toInputSettings().roundness, 1.0);
      expect(state.toInputSettings().angleDegrees, 0.0);
    });

    test('roundness and angle are clamped and round-trip', () {
      expect(
        BrushToolState(roundness: 0.0).roundness,
        BrushToolState.minRoundness,
      );
      expect(BrushToolState(roundness: 2.0).roundness, 1.0);
      expect(
        BrushToolState(roundness: double.nan).roundness,
        BrushToolState.defaultRoundness,
      );
      expect(BrushToolState(angleDegrees: -10).angleDegrees, 0.0);
      expect(BrushToolState(angleDegrees: 361).angleDegrees, 180.0);
      expect(
        BrushToolState(angleDegrees: double.nan).angleDegrees,
        BrushToolState.defaultAngleDegrees,
      );

      final state = BrushToolState.defaults.copyWith(
        roundness: 0.4,
        angleDegrees: 45,
      );
      expect(state.roundness, 0.4);
      expect(state.angleDegrees, 45.0);
      final settings = state.toInputSettings();
      expect(settings.roundness, 0.4);
      expect(settings.angleDegrees, 45.0);
      // Omitted copyWith args keep the existing values.
      expect(state.copyWith(size: 5).roundness, 0.4);
      expect(state.copyWith(size: 5).angleDegrees, 45.0);
    });

    // EVERY field carried between the three brush param bags, each at a
    // NON-default value. A converter that silently drops one turns its value
    // back into the default, so the round-trip equality below fails loudly
    // instead of passing on default==default (the trap the old, partial
    // version of this test walked into). What is NOT carried into
    // BrushSettings is what is not a brush parameter — `tool` and
    // `stabilizerStrength` (hand feel) — so they stay at their defaults
    // here. ⛔The blend used to be on that list under R26 #10 and is not
    // any more: it is a carried field like every other, and it is below.
    BrushTipMask maskFor(String id) => BrushTipMask(
      id: id,
      size: 2,
      alpha: Uint8List.fromList(const [10, 20, 30, 40]),
    );

    BrushToolState everyCarriedFieldNonDefault() => BrushToolState(
      size: 14,
      opacity: 0.7,
      color: 0xFF1E88E5,
      spacing: 0.3,
      hardness: 0.6,
      flow: 0.5,
      sizePressureCurve: BrushPressureCurve.linearFrom(0.2),
      opacityPressureCurve: BrushPressureCurve.linearFrom(0.3),
      flowPressureCurve: BrushPressureCurve.linearFrom(0.4),
      hardnessPressureCurve: BrushPressureCurve.identity(),
      roundness: 0.4,
      angleDegrees: 60,
      tipMask: maskFor('tip'),
      rotationMode: BrushTipRotationMode.direction,
      sizeJitter: 0.2,
      opacityJitter: 0.3,
      angleJitter: 0.4,
      scatterRadiusRatio: 0.5,
      scatterCount: 3,
      scatterBothAxes: false,
      dualMask: maskFor('dual'),
      dualMaskScale: 0.7,
      textureMaskSource: maskFor('texture'),
      textureScale: 1.2,
      textureDensity: 0.9,
      blendMode: BrushBlendMode.multiply,
    );

    test('every carried field survives toBrushSettings/fromBrushSettings', () {
      final state = everyCarriedFieldNonDefault();
      expect(BrushToolState.fromBrushSettings(state.toBrushSettings()), state);
    });

    test('every carried field survives toInputSettings', () {
      final state = everyCarriedFieldNonDefault();
      final input = state.toInputSettings();
      expect(input.size, state.size);
      expect(input.opacity, state.opacity);
      expect(input.color, state.color);
      expect(input.spacing, state.spacing);
      expect(input.hardness, state.hardness);
      expect(input.flow, state.flow);
      expect(input.sizePressureCurve, state.sizePressureCurve);
      expect(input.opacityPressureCurve, state.opacityPressureCurve);
      expect(input.flowPressureCurve, state.flowPressureCurve);
      expect(input.hardnessPressureCurve, state.hardnessPressureCurve);
      expect(input.roundness, state.roundness);
      expect(input.angleDegrees, state.angleDegrees);
      expect(input.tipMask, state.tipMask);
      expect(input.rotationMode, state.rotationMode);
      expect(input.sizeJitter, state.sizeJitter);
      expect(input.opacityJitter, state.opacityJitter);
      expect(input.angleJitter, state.angleJitter);
      expect(input.scatterRadiusRatio, state.scatterRadiusRatio);
      expect(input.scatterCount, state.scatterCount);
      expect(input.scatterBothAxes, state.scatterBothAxes);
      expect(input.dualMask, state.dualMask);
      expect(input.dualMaskScale, state.dualMaskScale);
      expect(input.textureMask, state.textureMask);
      expect(input.textureScale, state.textureScale);
      expect(input.textureDensity, state.textureDensity);
      expect(input.blendMode, state.blendMode);
    });

    test('fromBrushSettings clamps out-of-range preset values', () {
      final state = BrushToolState.fromBrushSettings(
        BrushSettings(size: 5000, spacing: 100, angleDegrees: 720),
      );
      expect(state.size, BrushToolState.maxSize);
      expect(state.spacing, BrushToolState.maxSpacing);
      expect(state.angleDegrees, BrushToolState.maxAngleDegrees);
    });
  });

  group('ground-colour mixing', () {
    BrushSettings mixingPreset() => BrushSettings(
      mixesGroundColor: true,
      paintAmount: 0.9,
      paintDensity: 0.5,
      colorStretch: 0.3,
    );

    test('applying an imported preset carries mixing to the canvas', () {
      // The whole point of the import program: a watercolour brush from a
      // .sut has to mix when it paints, with no hand setup in between.
      final state = BrushToolState.fromBrushSettings(mixingPreset());
      final input = state.toInputSettings();

      expect(input.shape.mixesGroundColor, isTrue);
      expect(input.shape.paintAmount, closeTo(0.9, 1e-9));
      expect(input.shape.paintDensity, closeTo(0.5, 1e-9));
      expect(input.shape.colorStretch, closeTo(0.3, 1e-9));
    });

    test('mixing leaves the blend mode alone', () {
      // Clip Studio runs 下地混色 and a 乗算 composite together on the same
      // brush — loading the brush and laying the stroke down are different
      // stages — so suppressing the blend was a deviation, not a safeguard.
      final state = BrushToolState.fromBrushSettings(
        mixingPreset(),
      ).copyWith(blendMode: BrushBlendMode.multiply);

      expect(state.toInputSettings().blendMode, BrushBlendMode.multiply);
    });

    test('the eraser still wins over mixing', () {
      final state = BrushToolState.fromBrushSettings(
        mixingPreset(),
      ).copyWith(tool: CanvasTool.eraser);
      final input = state.toInputSettings();

      expect(input.blendMode, BrushBlendMode.erase);
      expect(input.erase, isTrue);
    });

    test('a non-mixing brush keeps its blend mode', () {
      final state = BrushToolState(blendMode: BrushBlendMode.multiply);

      expect(state.toInputSettings().blendMode, BrushBlendMode.multiply);
    });
  });

  /// ⛔This group was called "blend lock" and pinned a nullable PIN that
  /// overrode a separate hand setting. 유저 2026-09-08 retired both — 「툴/손
  /// 설정 구분 없애고 모든 설정이 내보낼때 나르도록 … 3번으로 자물쇠 삭제
  /// 가자」 — so a brush simply HAS a blend, 通常 included, and there is no
  /// second value for it to win over. What survives is every promise the pin
  /// was making, now made structurally.
  group('the brush blend', () {
    test('reaches the stroke', () {
      final state = BrushToolState(blendMode: BrushBlendMode.multiply);

      expect(state.blendMode, BrushBlendMode.multiply);
      expect(state.toInputSettings().blendMode, BrushBlendMode.multiply);
    });

    test('travels with the preset, through JSON both ways', () {
      final settings = BrushSettings(blendMode: BrushBlendMode.multiply);
      final applied = BrushToolState.fromBrushSettings(settings);

      expect(applied.blendMode, BrushBlendMode.multiply);
      expect(
        BrushSettings.fromJson(settings.toJson()).blendMode,
        BrushBlendMode.multiply,
      );
    });

    test('writes nothing when it is 通常, and reads the legacy pin key', () {
      // 通常 IS the default, so a preset saved before every brush carried a
      // blend round-trips byte-identically...
      expect(BrushSettings().toJson().containsKey('blendMode'), isFalse);
      expect(BrushSettings().blendMode, BrushBlendMode.color);

      // ...and one saved WITH a pin still loads: a brush that pinned a blend
      // now simply has it.
      expect(
        BrushSettings.fromJson({
          'color': 0xFF000000,
          'size': 4.0,
          'opacity': 1.0,
          'rotationMode': 'fixed',
          'lockedBlendMode': 'multiply',
        }).blendMode,
        BrushBlendMode.multiply,
      );
    });

    test('still yields to the eraser TOOL', () {
      final state = BrushToolState(
        tool: CanvasTool.eraser,
      ).copyWith(blendMode: BrushBlendMode.multiply);

      expect(state.toInputSettings().blendMode, BrushBlendMode.erase);
      expect(state.toInputSettings().erase, isTrue);
    });

    test('a brush whose blend IS erase erases', () {
      final state = BrushToolState().copyWith(blendMode: BrushBlendMode.erase);

      expect(state.toInputSettings().erase, isTrue);
    });
  });
}
