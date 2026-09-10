import 'package:flutter/material.dart';

import '../../models/brush_anti_alias.dart';
import '../../models/brush_pressure_curve.dart';
import '../../models/brush_shape.dart' show BrushMaskSlot;
import '../../models/brush_tip_entry.dart';
import '../../models/brush_tip_rotation_mode.dart';
import '../../models/separable_blend_mode.dart';
import '../panels/editor_panel_frame.dart';
import '../widgets/field_slider.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/pressure_curve_popup.dart';
import 'brush_tip_picker.dart';
import 'brush_tool_state.dart';
import '../text/app_strings.dart';

/// Editable brush tool properties — the CSP-style GROUPED layout (BB-2,
/// user-picked candidate B, 07-22): 브러시 크기 / 잉크 / 브러시 끝 /
/// 보정, with the BRUSH BLEND dropdown living in the ink group exactly
/// where Clip Studio keeps its 합성 모드. The color swatches and the tip
/// shape segment are GONE (R26 #11): color belongs to the color wheel
/// panel, the tip belongs to brush presets.
///
/// The brush library lives in the separate [BrushPresetPanel]; this panel
/// only mutates the live [BrushToolState].
class BrushSettingsPanel extends StatelessWidget {
  const BrushSettingsPanel({
    super.key,
    required this.state,
    required this.onChanged,
    this.tips = const <BrushTipEntry>[],
    this.onTipImportRequested,
    this.onRenameTip,
    this.onDeleteTip,
  });

  final BrushToolState state;
  final ValueChanged<BrushToolState> onChanged;

  /// The shared tip library, for the tip / dual / texture pickers.
  ///
  /// ⛔An empty library used to take the three picker rows and the whole
  /// Texture group OFF the panel. That was product shape decided by a bare
  /// panel test — the app always ships built-in tips, so the branch could
  /// only ever fire in a test, and what it removed was a group HEADER as
  /// well. The rows are always here now; an empty library just opens an
  /// empty grid.
  final List<BrushTipEntry> tips;

  /// Opens the add-a-tip-from-an-image flow.
  final VoidCallback? onTipImportRequested;

  /// Manage the tip picked inside the library popup. Null leaves the
  /// buttons out — the same shape [onTipImportRequested] already has.
  final void Function(BrushTipEntry tip)? onRenameTip;
  final void Function(BrushTipEntry tip)? onDeleteTip;

  // The `language` parameter left with the blend row: it existed only for
  // the blend labels (ja = CSP terms), and the rest of the panel reads its
  // wording from `AppText.strings`.

  /// The CSP-style per-setting pressure button (BB-3): sits at the right
  /// of each pressure-capable slider row and opens the shared curve popup.
  Widget _pressureButton(BrushPressureTarget target, String title) {
    return PressureCurveButton(
      keyValue: 'brush-tool-pressure-${target.name}',
      title: title,
      curves: state.targetCurves(target),
      onChanged: (curves) => onChanged(state.withTargetCurves(target, curves)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return EditorPanelFrame(
      title: AppText.strings.brushSettingsTitle,
      child: Column(
        key: const ValueKey<String>('brush-settings-panel'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 유저 확정 (rail-and-strip): SIZE, OPACITY and BLEND — each with
          // its pressure curve or lock — left this panel for the TOP STRIP.
          // They are the settings a hand changes mid-stroke, against a test
          // mark on the canvas, and this panel scrolls; the strip is always
          // where it was. Keeping a second copy here would be two places
          // showing one number.
          const _GroupHeader('Ink', first: true),
          _PanelSlider(
            label: AppText.strings.brFlow,
            unit: '%',
            displayScale: 100,
            value: BrushToolState.clampUnit(state.flow),
            min: 0,
            max: 1,
            keyValue: 'brush-tool-flow-slider',
            onChanged: (value) => onChanged(state.copyWith(flow: value)),
            trailing: _pressureButton(
              BrushPressureTarget.flow,
              AppText.strings.brFlow,
            ),
          ),
          const _GroupHeader('Brush tip'),
          BrushTipPickerRow(
            label: AppText.strings.brBrushTip,
            role: BrushTipRole.tip,
            selected: state.tipMask,
            tips: tips,
            onImportRequested: onTipImportRequested,
            onRenameTip: onRenameTip,
            onDeleteTip: onDeleteTip,
            // The sampled tip REPLACES hardness and tip shape, so clearing
            // it is how a brush gets its parametric footprint back — which
            // is why this goes through withTipMask rather than copyWith.
            onPicked: (mask) =>
                onChanged(state.withMask(BrushMaskSlot.tip, mask)),
          ),
          _PanelSlider(
            label: AppText.strings.brHardness,
            unit: '%',
            displayScale: 100,
            value: BrushToolState.clampUnit(state.hardness),
            min: 0,
            max: 1,
            keyValue: 'brush-tool-hardness-slider',
            onChanged: (value) => onChanged(state.copyWith(hardness: value)),
            trailing: _pressureButton(
              BrushPressureTarget.hardness,
              AppText.strings.brHardness,
            ),
          ),
          // Beside hardness on purpose: hardness sets how WIDE the coverage
          // ramp is, this sets how hard its edge cuts. Two halves of one
          // footprint, so they read together.
          _AntiAliasRow(
            value: state.antiAlias,
            onChanged: (step) => onChanged(state.copyWith(antiAlias: step)),
          ),
          _PanelSlider(
            label: AppText.strings.brRoundness,
            unit: '%',
            displayScale: 100,
            value: BrushToolState.clampRoundness(state.roundness),
            min: BrushToolState.minRoundness,
            max: 1,
            keyValue: 'brush-tool-roundness-slider',
            onChanged: (value) => onChanged(state.copyWith(roundness: value)),
          ),
          _PanelSlider(
            label: AppText.strings.brAngle,
            unit: '°',
            value: BrushToolState.clampAngleDegrees(state.angleDegrees),
            min: BrushToolState.minAngleDegrees,
            max: BrushToolState.maxAngleDegrees,
            keyValue: 'brush-tool-angle-slider',
            onChanged: (value) =>
                onChanged(state.copyWith(angleDegrees: value)),
          ),
          _PanelSlider(
            label: AppText.strings.brSpacing,
            unit: '%',
            displayScale: 100,
            value: BrushToolState.clampSpacing(state.spacing),
            min: BrushToolState.minSpacing,
            max: BrushToolState.maxSpacing,
            scale: FieldSliderScale.exponential,
            keyValue: 'brush-tool-spacing-slider',
            onChanged: (value) => onChanged(state.copyWith(spacing: value)),
          ),
          _RotationModeRow(state: state, onChanged: onChanged),
          // P20 shipped placement dynamics into the engine and left them
          // unreachable: only a preset or an import could set them. These
          // are those knobs.
          const _GroupHeader('Randomness'),
          _PanelSlider(
            label: AppText.strings.brSizeJitter,
            unit: '%',
            displayScale: 100,
            value: BrushToolState.clampZeroToOne(state.sizeJitter),
            min: 0,
            max: 1,
            keyValue: 'brush-tool-size-jitter-slider',
            onChanged: (value) => onChanged(state.copyWith(sizeJitter: value)),
          ),
          _PanelSlider(
            label: AppText.strings.brOpacityJitter,
            unit: '%',
            displayScale: 100,
            value: BrushToolState.clampZeroToOne(state.opacityJitter),
            min: 0,
            max: 1,
            keyValue: 'brush-tool-opacity-jitter-slider',
            onChanged: (value) =>
                onChanged(state.copyWith(opacityJitter: value)),
          ),
          _PanelSlider(
            label: AppText.strings.brAngleJitter,
            unit: '%',
            displayScale: 100,
            value: BrushToolState.clampZeroToOne(state.angleJitter),
            min: 0,
            max: 1,
            keyValue: 'brush-tool-angle-jitter-slider',
            onChanged: (value) => onChanged(state.copyWith(angleJitter: value)),
          ),
          _PanelSlider(
            label: AppText.strings.brRoundnessJitter,
            unit: '%',
            displayScale: 100,
            value: BrushToolState.clampZeroToOne(state.roundnessJitter),
            min: 0,
            max: 1,
            keyValue: 'brush-tool-roundness-jitter-slider',
            onChanged: (value) =>
                onChanged(state.copyWith(roundnessJitter: value)),
          ),
          _PanelSlider(
            label: AppText.strings.brSpacingJitter,
            unit: '%',
            displayScale: 100,
            value: BrushToolState.clampZeroToOne(state.spacingJitter),
            min: 0,
            max: 1,
            keyValue: 'brush-tool-spacing-jitter-slider',
            onChanged: (value) =>
                onChanged(state.copyWith(spacingJitter: value)),
          ),
          const _GroupHeader('Mixing'),
          _PanelSwitch(
            label: AppText.strings.brMixing,
            value: state.mixesGroundColor,
            keyValue: 'brush-tool-mixing-toggle',
            onChanged: (value) =>
                onChanged(state.copyWith(mixesGroundColor: value)),
          ),
          // ⛔THE ROWS DO NOT APPEAR AND DISAPPEAR — they go DEAD (유저, 반복:
          // 「없다가 생기는 UI 금지. 자리는 항상 예약하고 내용만 바꾼다」).
          // The three below used to be mounted only while mixing was on, so
          // turning the switch made the panel jump and everything under it
          // moved out from under the finger.
          _PanelSlider(
            label: AppText.strings.brPaintAmount,
            unit: '%',
            displayScale: 100,
            value: BrushToolState.clampZeroToOne(state.paintAmount),
            min: 0,
            max: 1,
            keyValue: 'brush-tool-paint-amount-slider',
            onChanged: state.mixesGroundColor
                ? (value) => onChanged(state.copyWith(paintAmount: value))
                : null,
          ),
          _PanelSlider(
            label: AppText.strings.brPaintDensity,
            unit: '%',
            displayScale: 100,
            value: BrushToolState.clampZeroToOne(state.paintDensity),
            min: 0,
            max: 1,
            keyValue: 'brush-tool-paint-density-slider',
            onChanged: state.mixesGroundColor
                ? (value) => onChanged(state.copyWith(paintDensity: value))
                : null,
          ),
          _PanelSlider(
            label: AppText.strings.brColorStretch,
            unit: '%',
            displayScale: 100,
            value: BrushToolState.clampZeroToOne(state.colorStretch),
            min: 0,
            max: 1,
            keyValue: 'brush-tool-color-stretch-slider',
            onChanged: state.mixesGroundColor
                ? (value) => onChanged(state.copyWith(colorStretch: value))
                : null,
          ),
          const _GroupHeader('Scattering'),
          _PanelSlider(
            // A ratio of the brush size, so scatter keeps its character as
            // the brush grows.
            label: AppText.strings.brScatter,
            unit: '%',
            displayScale: 100,
            value: BrushToolState.clampScatterRadius(state.scatterRadiusRatio),
            min: 0,
            max: 4,
            keyValue: 'brush-tool-scatter-slider',
            onChanged: (value) =>
                onChanged(state.copyWith(scatterRadiusRatio: value)),
          ),
          _PanelSlider(
            label: AppText.strings.brScatterCount,
            value: BrushToolState.clampScatterCount(
              state.scatterCount,
            ).toDouble(),
            min: 1,
            max: 16,
            // A COUNT of dabs, so the bar stops between them — F-34's own
            // sentence (「데이터적으로 소수점이 필요없는것들 정수화 … 조절시
            // 자연수이도록」) and the same fix the RGB channel and the
            // opacity bars already carry. Without it the bar hands 8.4 to an
            // int and its own readout has to write `8.0`.
            divisions: 15,
            keyValue: 'brush-tool-scatter-count-slider',
            onChanged: (value) =>
                onChanged(state.copyWith(scatterCount: value.round())),
          ),
          _PanelSwitch(
            label: AppText.strings.brScatterBothAxes,
            value: state.scatterBothAxes,
            keyValue: 'brush-tool-scatter-both-axes-toggle',
            onChanged: (value) =>
                onChanged(state.copyWith(scatterBothAxes: value)),
          ),
          const _GroupHeader('Texture'),
          BrushTipPickerRow(
            label: AppText.strings.brDualTip,
            role: BrushTipRole.dual,
            selected: state.dualMask,
            tips: tips,
            onImportRequested: onTipImportRequested,
            onRenameTip: onRenameTip,
            onDeleteTip: onDeleteTip,
            onPicked: (mask) =>
                onChanged(state.withMask(BrushMaskSlot.dual, mask)),
          ),
          _PanelSlider(
            label: AppText.strings.brScale,
            unit: '%',
            displayScale: 100,
            value: BrushToolState.clampDualMaskScale(state.dualMaskScale),
            min: 0.05,
            max: 10,
            scale: FieldSliderScale.exponential,
            keyValue: 'brush-tool-dual-scale-slider',
            onChanged: state.dualMask == null
                ? null
                : (value) => onChanged(state.copyWith(dualMaskScale: value)),
          ),
          // The dual mask's own density, beside its scale — the same pair
          // the texture mask below has had all along. The dual mask used to
          // be an unconditional multiply, which made it the one mask you
          // could only have at full strength.
          _PanelSlider(
            label: AppText.strings.brTextureDensity,
            unit: '%',
            displayScale: 100,
            value: BrushToolState.clampZeroToOne(state.dualDensity),
            min: 0,
            max: 1,
            keyValue: 'brush-tool-dual-density-slider',
            onChanged: state.dualMask == null
                ? null
                : (value) => onChanged(state.copyWith(dualDensity: value)),
          ),
          _DualBlendRow(state: state, onChanged: onChanged),
          BrushTipPickerRow(
            label: AppText.strings.brTexture,
            role: BrushTipRole.texture,
            // ⚠️The SOURCE, not the painted mask: the swatch answers "which
            // texture did I pick", and a levelled bake is a different object
            // that would never match a library entry.
            selected: state.textureMaskSource,
            tips: tips,
            onImportRequested: onTipImportRequested,
            onRenameTip: onRenameTip,
            onDeleteTip: onDeleteTip,
            onPicked: (mask) =>
                onChanged(state.withMask(BrushMaskSlot.texture, mask)),
          ),
          _PanelSlider(
            label: AppText.strings.brScale,
            unit: '%',
            displayScale: 100,
            value: BrushToolState.clampDualMaskScale(state.textureScale),
            min: 0.05,
            max: 10,
            scale: FieldSliderScale.exponential,
            keyValue: 'brush-tool-texture-scale-slider',
            onChanged: state.textureMaskSource == null
                ? null
                : (value) => onChanged(state.copyWith(textureScale: value)),
          ),
          _PanelSlider(
            label: AppText.strings.brTextureDensity,
            unit: '%',
            displayScale: 100,
            value: BrushToolState.clampZeroToOne(state.textureDensity),
            min: 0,
            max: 1,
            keyValue: 'brush-tool-texture-density-slider',
            onChanged: state.textureMaskSource == null
                ? null
                : (value) => onChanged(state.copyWith(textureDensity: value)),
          ),
          // The three LEVELS both source formats carry and neither could
          // reach: the importers baked them into the mask, which left no
          // original to re-bake from. Clip Studio calls them 濃度反転 /
          // 明るさ / コントラスト and Photoshop InvT / Brightness / Contrast.
          _PanelSwitch(
            label: AppText.strings.brTextureInvert,
            value: state.textureInvert,
            keyValue: 'brush-tool-texture-invert-toggle',
            onChanged: state.textureMaskSource == null
                ? null
                : (value) => onChanged(state.copyWith(textureInvert: value)),
          ),
          _PanelSlider(
            label: AppText.strings.brTextureBrightness,
            unit: '%',
            displayScale: 100,
            value: BrushToolState.clampSignedUnit(state.textureBrightness),
            min: -1,
            max: 1,
            keyValue: 'brush-tool-texture-brightness-slider',
            onChanged: state.textureMaskSource == null
                ? null
                : (value) =>
                      onChanged(state.copyWith(textureBrightness: value)),
          ),
          _PanelSlider(
            label: AppText.strings.brTextureContrast,
            unit: '%',
            displayScale: 100,
            value: BrushToolState.clampSignedUnit(state.textureContrast),
            min: -1,
            max: 1,
            keyValue: 'brush-tool-texture-contrast-slider',
            onChanged: state.textureMaskSource == null
                ? null
                : (value) => onChanged(state.copyWith(textureContrast: value)),
          ),
          const _GroupHeader('Correction'),
          // Pull-string stabilization (P7): a hand-feel setting, kept OUT
          // of brush presets on purpose.
          _PanelSlider(
            label: AppText.strings.brStabilizer,
            value: BrushToolState.clampStabilizerStrength(
              state.stabilizerStrength,
            ),
            min: 0,
            max: 100,
            keyValue: 'brush-tool-stabilizer-slider',
            onChanged: (value) =>
                onChanged(state.copyWith(stabilizerStrength: value)),
          ),
          // ⛔THE AUTO-FRAME TOGGLE IS NOT HERE ANY MORE (F-61, 유저:
          // 「프레임 자동생성 버튼 툴 설정에 있는데, **왜 이딴식으로
          // 결정한거지? 내가 분명 타임라인 헤더쪽에 두라하지않았나?** 프레임
          // 알약 안, 중간나누기 버튼 오른쪽에 두도록. 기존 잔재는 삭제」).
          //
          // ⚠️Kept as a note rather than deleted silently: the earlier
          // quote I built it from (「**프레임 자동생성 on버튼** 만들게
          // 햇던거같은데」) says nothing about WHERE, and I read the tool
          // settings convention into the gap. It lives in the frame pill —
          // beside the other verbs that make and unmake a block, which is
          // the group it belongs to.
        ],
      ),
    );
  }
}

/// The CSP category rule: a small header over each settings group, a
/// hairline separating it from the group above.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label, {this.first = false});

  final String label;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!first)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Divider(
                height: 1,
                thickness: 1,
                color: theme.colorScheme.outlineVariant,
              ),
            ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// How a dab picks its angle: the fixed [BrushToolState.angleDegrees], or
/// the stroke's own direction with that angle as an offset.
///
/// A flat tip is the whole reason this exists — a calligraphy nib held at a
/// fixed angle draws thick and thin as the stroke turns, while a bristle
/// brush wants to rake ALONG the stroke however it curves.
class _RotationModeRow extends StatelessWidget {
  const _RotationModeRow({required this.state, required this.onChanged});

  final BrushToolState state;
  final ValueChanged<BrushToolState> onChanged;

  String _labelFor(BrushTipRotationMode mode) => switch (mode) {
    BrushTipRotationMode.fixed => AppText.strings.brRotationFixed,
    BrushTipRotationMode.direction => AppText.strings.brRotationDirection,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              AppText.strings.brTipRotation,
              style: theme.textTheme.labelSmall,
            ),
          ),
          PanelFlyoutButton(
            key: const ValueKey<String>('brush-tool-rotation-menu-button'),
            label: _labelFor(state.rotationMode),
            tooltip: AppText.strings.brTipRotation,
            entriesBuilder: () => panelFlyoutChoices(
              values: BrushTipRotationMode.values,
              current: state.rotationMode,
              keyPrefix: 'brush-tool-rotation-',
              labelOf: _labelFor,
              onPicked: (mode) =>
                  onChanged(state.copyWith(rotationMode: mode)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled on/off row, matching the slider rows' label-left layout.
class _PanelSwitch extends StatelessWidget {
  const _PanelSwitch({
    required this.label,
    required this.value,
    required this.keyValue,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final String keyValue;
  /// Null makes the row DEAD, not absent — the same contract [_PanelSlider]
  /// states, for the same reason.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.labelSmall)),
          Switch(
            key: ValueKey<String>(keyValue),
            value: value,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// The BRUSH BLEND row moved to the TOP STRIP with size and opacity (유저
// 확정). It is the same button and the same lock, transplanted rather than
// rebuilt — see `_BlendModeControl` in editor_top_strip.dart.

/// The brush EDGE row — 없음 / 1 / 2 / 3 (유저 확정, 클튜 4단).
///
/// A [SegmentedButton] because that is how this program already asks a
/// short N-way question (the transform anchor and the eyedropper source),
/// and because the four answers have plain names — no icon has to be
/// invented for them. `showSelectedIcon: false` for the house rule:
/// 선택 표시는 색상만.
class _AntiAliasRow extends StatelessWidget {
  const _AntiAliasRow({required this.value, required this.onChanged});

  final BrushAntiAlias value;
  final ValueChanged<BrushAntiAlias> onChanged;

  /// 1·2·3 are DIGITS, not words — they read the same in every language
  /// this program speaks, so only 없음 goes through [AppText].
  String _labelFor(BrushAntiAlias step) => switch (step) {
    BrushAntiAlias.none => AppText.strings.brEdgeNone,
    BrushAntiAlias.low => '1',
    BrushAntiAlias.medium => '2',
    BrushAntiAlias.high => '3',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Same trailing reservation as [_PanelSlider]: this row lines up with
    // the sliders above and below it, and the slot stays empty rather than
    // letting the segments grow into it (⛔자리는 항상 예약하고 내용만 바꾼다).
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  AppText.strings.brEdge,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SegmentedButton<BrushAntiAlias>(
                    key: const ValueKey<String>('brush-tool-edge-segments'),
                    showSelectedIcon: false,
                    segments: [
                      for (final step in BrushAntiAlias.values)
                        ButtonSegment<BrushAntiAlias>(
                          value: step,
                          label: Text(_labelFor(step)),
                        ),
                    ],
                    selected: {value},
                    onSelectionChanged: (selection) =>
                        onChanged(selection.first),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: _PanelSlider._trailingGap),
          const SizedBox(width: PressureCurveButton.slotWidth),
        ],
      ),
    );
  }
}

class _PanelSlider extends StatelessWidget {
  const _PanelSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.keyValue,
    required this.onChanged,
    this.unit = '',
    this.displayScale = 1,
    this.divisions,
    this.scale = FieldSliderScale.linear,
    this.trailing,
  });

  final String label;

  /// ⛔THE ROW PASSES A UNIT, NEVER A NUMBER (F-34). Seventeen of these rows
  /// wrote `'${(x * 100).round()}%'` by hand — a rounding the bar had not
  /// done, so a spacing holding 12.4% read `12%`, and the digit count came
  /// and went with the value.
  final String unit;
  final double displayScale;
  final int? divisions;
  final double value;
  final double min;
  final double max;
  final String keyValue;

  /// Null makes the row DEAD, not absent: it keeps its place, its label and
  /// its number, and stops taking the gesture. That is the whole reason this
  /// is nullable — see the mixing and mask rows, which used to be mounted
  /// conditionally and made the panel jump under the finger.
  final ValueChanged<double>? onChanged;
  final FieldSliderScale scale;

  /// Optional right-edge control (BB-3: the pressure-curve button).
  ///
  /// ⚠️Optional in CONTENT, never in SPACE — see [build].
  final Widget? trailing;

  /// The gap between the slider and the trailing slot.
  static const double _trailingGap = 4;

  @override
  Widget build(BuildContext context) {
    final slider = FieldSlider(
      key: ValueKey<String>(keyValue),
      value: value,
      min: min,
      max: max,
      label: label,
      unit: unit,
      displayScale: displayScale,
      divisions: divisions,
      scale: scale,
      onChanged: onChanged,
    );
    // 🚨THE SLOT IS ALWAYS THERE, whether or not a button sits in it (유저
    // 09-08: 「슬라이더 크기는 항상 고정되도록. 압력버튼없으면 그냥
    // 빈공간으로」). ⛔The branch this replaced gave the eighteen sliders
    // WITHOUT a curve button the button's width as well, so one panel drew
    // its slider at two different lengths — 「자리는 항상 예약하고 내용만
    // 바꾼다」 with the reservation missing.
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: slider),
          const SizedBox(width: _trailingGap),
          SizedBox(
            width: PressureCurveButton.slotWidth,
            child: trailing,
          ),
        ],
      ),
    );
  }
}

/// How the DUAL mask COMBINES with the coverage under it.
///
/// 🚨A brush could ARRIVE with a mode and never be edited to one (v33). Both
/// source formats carry it — Clip Studio's `DualBrushCompositeMode`, whose
/// 加算 shows up in the user's own files, and Photoshop's `dualBrush.BlnM`,
/// eight codes across 765 brushes — the engine reads them now, and the dual
/// mask's other knobs have had rows here all along.
///
/// ⛔A `PanelFlyoutButton` row, the shape this panel already uses for tip
/// rotation. Twelve entries is what a flyout is for; the segmented button
/// above is for the four-way edge step, and a third control shape would be
/// a new convention for no reason.
class _DualBlendRow extends StatelessWidget {
  const _DualBlendRow({required this.state, required this.onChanged});

  final BrushToolState state;
  final ValueChanged<BrushToolState> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final language = AppText.language;
    // ⛔The row is ALWAYS here and goes DEAD without a dual tip — the same
    // shape the two sliders above it take, and 「없다가 생기는 UI 금지」: the
    // mask rows used to mount only once a mask was picked, which shoved
    // four rows under the finger that had just come back from the popup.
    final enabled = state.dualMask != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              AppText.strings.brDualBlend,
              style: theme.textTheme.labelSmall,
            ),
          ),
          PanelFlyoutButton(
            key: const ValueKey<String>('brush-tool-dual-blend-menu-button'),
            label: state.dualCompositeMode.labelFor(language),
            tooltip: AppText.strings.brDualBlend,
            // ⛔`enabled`, NOT an empty list. `showMenu` asserts on one, and
            // a button that opens nothing is 「잠궜는데 바꿀 수 있으면 잠금이
            // 아니잖아」 — the flyout's own doc says a host that needs a shut
            // state owns the appearance of one, and this button can dim
            // itself.
            enabled: enabled,
            entriesBuilder: () => panelFlyoutChoices(
              values: SeparableBlendMode.values,
              current: state.dualCompositeMode,
              keyPrefix: 'brush-tool-dual-blend-',
              labelOf: (mode) => mode.labelFor(language),
              onPicked: (mode) =>
                  onChanged(state.copyWith(dualCompositeMode: mode)),
            ),
          ),
        ],
      ),
    );
  }
}
